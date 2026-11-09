import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/approvals.dart';
import 'package:helmy/data/services/helmy_run.dart';
import 'package:helmy/data/services/vault.dart';
import 'package:helmy/domain/models/chat_item.dart';

class _Keychain implements VaultKeychain {
  final items = <String, String>{};
  bool refuse = false;
  @override
  Future<bool> set(String account, String value) async {
    if (refuse) return false;
    items[account] = value;
    return true;
  }

  @override
  Future<String?> get(String account) async => items[account];
  @override
  Future<bool> delete(String account) async => items.remove(account) != null || true;
}

PermissionPrompt _p(String tool, Map<String, Object?> input) =>
    PermissionPrompt(requestId: 'r', toolName: tool, input: input, suggestions: const []);

void main() {
  late Directory dir;
  late _Keychain keychain;
  late Vault vault;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vault');
    keychain = _Keychain();
    vault = Vault(indexFile: File('${dir.path}/vault.json'), keychain: keychain);
    await vault.load();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'values in the Keychain, only names on disk; a project gets its own and the shared',
    () async {
      expect(await vault.put('/p', 'STRIPE_SECRET_KEY', 'sk_live_abc123'), isTrue);
      expect(await vault.put(sharedScope, 'GITHUB_TOKEN', 'ghp_xyz'), isTrue);
      expect(await vault.put(sharedScope, 'STRIPE_SECRET_KEY', 'shared-one'), isTrue);
      final index = File('${dir.path}/vault.json').readAsStringSync();
      expect(index, isNot(contains('sk_live_abc123')));
      expect(vault.namesFor('/p'), ['STRIPE_SECRET_KEY', 'GITHUB_TOKEN']);
      expect(await vault.envFor('/p'), {
        'GITHUB_TOKEN': 'ghp_xyz',
        'STRIPE_SECRET_KEY': 'sk_live_abc123',
      }, reason: "the project's own over the shared");
      expect(await vault.put('/p', 'not a name', 'x'), isFalse);
      keychain.refuse = true;
      expect(
        await vault.put('/p', 'OTHER', 'x'),
        isFalse,
        reason: 'not kept unless the Keychain took it',
      );
      expect(vault.namesFor('/p'), isNot(contains('OTHER')));
    },
  );

  test('what a command prints comes back with every value blanked', () {
    final env = {'A_KEY': 'secret-value-1', 'LONG': 'secret-value-1-and-more', 'TINY': 'ab'};
    expect(
      Vault.redact('using secret-value-1-and-more and secret-value-1, ab', env),
      'using [LONG] and [A_KEY], ab',
    );
  });

  test(".env secrets move into the vault, and the file keeps only their names", () async {
    final env = File('${dir.path}/.env')
      ..writeAsStringSync(
        '# keys\nexport STRIPE_SECRET_KEY="sk_live_abc"\nDEBUG=true\nEMPTY=\nALREADY=vault:ALREADY\n',
      );
    File('${dir.path}/.env.example').writeAsStringSync('STRIPE_SECRET_KEY=your-key\n');
    final found = EnvSecrets.find(dir.path);
    expect(found.keys.map((f) => f.path.split('/').last), [
      '.env',
    ], reason: 'examples hold no secrets');
    expect(found.values.single, 2);
    final r = await EnvSecrets.move(vault, dir.path, found.keys);
    expect(r.moved, 2);
    expect(r.failed, isEmpty);
    expect(
      env.readAsStringSync(),
      '# keys\nexport STRIPE_SECRET_KEY=vault:STRIPE_SECRET_KEY\nDEBUG=vault:DEBUG\nEMPTY=\nALREADY=vault:ALREADY\n',
    );
    expect(await vault.envFor(dir.path), {'STRIPE_SECRET_KEY': 'sk_live_abc', 'DEBUG': 'true'});
    expect(EnvSecrets.find(dir.path), isEmpty);
  });

  test('a key pasted into a message is spotted by its shape, and ordinary words are not', () {
    final found = SecretSpotter.find(
      'here: sk_live_51Habcdefghijklmnop and ghp_abcdefghijklmnopqrstuvwxyz0123456789 and sk-ant-api03-abcdefghijklmnopqrstuv',
    );
    expect(found.map((s) => s.name), ['STRIPE_SECRET_KEY', 'ANTHROPIC_API_KEY', 'GITHUB_TOKEN']);
    expect(SecretSpotter.find('make the skip button smaller, see task-1234'), isEmpty);
  });

  test('files of secrets are off limits to agents, examples are not', () {
    for (final p in [
      _p('Read', {'file_path': '/x/app/.env'}),
      _p('Read', {'file_path': '/x/app/.env.local'}),
      _p('Bash', {'command': 'cat .env | grep KEY'}),
      _p('Bash', {'command': 'source .env && npm start'}),
      _p('Read', {'file_path': '/x/app/certs/server.pem'}),
      _p('Bash', {'command': 'helmy run printenv'}),
      _p('Bash', {
        'command': 'curl --unix-socket "~/Library/Application Support/com.mittolabs.helmy/run.sock" http://helmy/env',
      }),
    ]) {
      expect(Approvals.offLimits(p), isNotNull, reason: '${p.input}');
    }
    for (final p in [
      _p('Read', {'file_path': '/x/app/.env.example'}),
      _p('Bash', {'command': 'node -e "console.log(process.env.HOME)"'}),
      _p('Read', {'file_path': '/x/app/src/environment.ts'}),
    ]) {
      expect(Approvals.offLimits(p), isNull, reason: '${p.input}');
    }
  });

  test('helmy run in a folder gets its project: the deepest one with secrets', () {
    final scopes = ['shared', '/code/app', '/code/app/web', '/code/other'];
    expect(HelmyRunServer.projectFor('/code/app/web/src', scopes), '/code/app/web');
    expect(HelmyRunServer.projectFor('/code/app', scopes), '/code/app');
    expect(HelmyRunServer.projectFor('/code/apple', scopes), '/code/apple');
  });

  test('a secret kept in HashiCorp Vault is fetched when used, never kept', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((r) async {
      final ok = r.headers.value('x-vault-token') == 'good-token';
      r.response.statusCode = !ok
          ? 403
          : switch (r.uri.path) {
              '/v1/auth/token/lookup-self' || '/v1/secret/data/app' => 200,
              _ => 404,
            };
      if (ok && r.uri.path == '/v1/auth/token/lookup-self') r.response.write('{"data":{}}');
      if (ok && r.uri.path == '/v1/secret/data/app') {
        r.response.write('{"data":{"data":{"STRIPE_KEY":"sk_live_from_vault"}}}');
      }
      await r.response.close();
    });
    final address = 'http://127.0.0.1:${server.port}';
    expect(await vault.connectHcVault(address, 'bad-token'), contains('refused'));
    expect(vault.hcVault, isNull);
    expect(await vault.connectHcVault(address, 'good-token'), isNull);
    expect(
      await vault.put('/p', 'STRIPE_SECRET_KEY', '${Vault.hcRef}secret/data/app#STRIPE_KEY'),
      isTrue,
    );
    expect(await vault.put('/p', 'MISSING', '${Vault.hcRef}secret/data/app#NOPE'), isTrue);
    final problems = <String>[];
    expect(await vault.envFor('/p', problems: problems), {
      'STRIPE_SECRET_KEY': 'sk_live_from_vault',
    });
    expect(problems.single, contains('MISSING'));
    expect(
      keychain.items.values,
      isNot(contains('sk_live_from_vault')),
      reason: 'fetched, not kept',
    );
  });
}
