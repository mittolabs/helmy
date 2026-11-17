import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/system_keychain.dart';

/// The vault off a Mac: Credential Manager on Windows, the login keyring on
/// Linux. What each is asked, and that a value never goes on a command line.
void main() {
  late List<(String, List<String>, String)> ran;
  ({int code, String out})? answer;

  RunWithInput runner() => (exe, args, input) async {
    ran.add((exe, args, input));
    return answer;
  };

  String script(List<String> args) {
    final bytes = base64.decode(args.last);
    return String.fromCharCodes([
      for (var i = 0; i < bytes.length; i += 2) bytes[i] | bytes[i + 1] << 8,
    ]);
  }

  setUp(() {
    ran = [];
    answer = (code: 0, out: '');
  });

  group('Linux', () {
    test('kept through secret-tool, the value on standard input', () async {
      final k = SystemKeychain(os: 'linux', run: runner());
      expect(await k.set('global/OPENAI_KEY', 'sk-é secret'), isTrue);
      final (exe, args, input) = ran.single;
      expect(exe, 'secret-tool');
      expect(args, [
        'store',
        '--label=Helmy Vault: global/OPENAI_KEY',
        'service',
        'Helmy Vault',
        'account',
        'global/OPENAI_KEY',
      ]);
      expect(input, 'sk-é secret');
      expect(args.join(' '), isNot(contains('secret ')));
    });

    test('read back as it is; nothing there is null', () async {
      final k = SystemKeychain(os: 'linux', run: runner());
      answer = (code: 0, out: 'sk-é secret');
      expect(await k.get('global/OPENAI_KEY'), 'sk-é secret');
      expect(ran.single.$2, ['lookup', 'service', 'Helmy Vault', 'account', 'global/OPENAI_KEY']);
      answer = (code: 1, out: '');
      expect(await k.get('nothing'), isNull);
    });

    test('no secret-tool: kept nowhere, and said so', () async {
      final k = SystemKeychain(os: 'linux', run: runner());
      answer = null;
      expect(await k.set('a', 'b'), isFalse);
      expect(await k.get('a'), isNull);
      expect(await k.delete('a'), isFalse);
    });
  });

  group('Windows', () {
    test('kept in Credential Manager, the value on standard input as base64', () async {
      final k = SystemKeychain(os: 'windows', run: runner());
      expect(await k.set("it's/KEY", 'sk-é secret'), isTrue);
      final (exe, args, input) = ran.single;
      expect(exe, 'powershell');
      expect(args.take(3), ['-NoProfile', '-NonInteractive', '-EncodedCommand']);
      expect(utf8.decode(base64.decode(input)), 'sk-é secret');
      final s = script(args);
      expect(s, contains('PasswordVault'));
      expect(s, contains("PasswordCredential('Helmy Vault'"));
      expect(s, contains(base64.encode(utf8.encode("it's/KEY"))), reason: 'the name as base64');
      expect(s, isNot(contains('sk-')), reason: 'the value is not in the script');
    });

    test('read back from base64; nothing there is null', () async {
      final k = SystemKeychain(os: 'windows', run: runner());
      answer = (code: 0, out: '${base64.encode(utf8.encode('sk-é secret'))}\r\n');
      expect(await k.get('KEY'), 'sk-é secret');
      expect(script(ran.single.$2), contains('Retrieve'));
      answer = (code: 1, out: '');
      expect(await k.get('KEY'), isNull);
    });

    test('removed', () async {
      final k = SystemKeychain(os: 'windows', run: runner());
      expect(await k.delete('KEY'), isTrue);
      expect(script(ran.single.$2), contains(r'$vault.Remove('));
    });
  });
}
