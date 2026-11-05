import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/models/settings.dart';
import '../../utils/platform.dart';
import 'cli_locator.dart';
import 'desktop_service.dart';
import 'engines/ollama/ollama_doctor.dart';

/// Where a connection is in being set up.
enum SetupState {
  /// Not installed on this computer.
  missing,

  /// Installed, not signed in (or, for the model here, not running).
  signedOut,

  /// Ready to use.
  ready,
}

/// One connection, as setup sees it.
typedef ConnectionCheck = ({String id, String name, String does, SetupState state});

/// Gets Helmy's connections ready without a terminal: checks each, installs
/// it with its maker's own installer, and signs in through the browser.
/// Settings (and the first-run page) are the one place these are named.
class ConnectionsSetup {
  ConnectionsSetup(this._locator, this._desktop);
  final CliLocator _locator;
  final DesktopService _desktop;

  static const _names = {
    'claude': ('Claude Code', 'Works in your folders and connected accounts'),
    'codex': ('Codex', 'Works in your folders; makes and changes pictures'),
    'ollama': ('Ollama', 'A model on this computer: answers when nothing online can'),
  };

  /// Where [name]'s program is, as found now; null when it is not.
  Future<String?> programOf(String name) => _find(name);

  Future<String?> _find(String name) async {
    _locator.forget(name);
    return _locator.find(name);
  }

  Future<ProcessResult?> _run(String cmd, List<String> args, {Map<String, String>? extra}) async {
    try {
      return await Process.run(
        cmd,
        args,
        environment: {...await _locator.environment(), ...?extra},
      );
    } on Object {
      return null;
    }
  }

  /// Every connection and where it stands.
  Future<List<ConnectionCheck>> check() async => [
    for (final id in _names.keys)
      (id: id, name: _names[id]!.$1, does: _names[id]!.$2, state: await _state(id)),
  ];

  Future<SetupState> _state(String id) async {
    switch (id) {
      case 'claude':
        final bin = await _find('claude');
        if (bin == null) return .missing;
        final r = await _run(bin, ['auth', 'status']);
        try {
          return (jsonDecode('${r?.stdout}') as Map)['loggedIn'] == true ? .ready : .signedOut;
        } on Object {
          return .signedOut;
        }
      case 'codex':
        final bin = await _find('codex');
        if (bin == null) return .missing;
        final r = await _run(bin, ['login', 'status']);
        return r?.exitCode == 0 && '${r?.stdout}${r?.stderr}'.contains('Logged in')
            ? .ready
            : .signedOut;
      case 'ollama':
        if (await _find('ollama') == null && !Directory('/Applications/Ollama.app').existsSync()) {
          return .missing;
        }
        return await OllamaDoctor.answers() ? .ready : .signedOut;
    }
    return .missing;
  }

  /// Installs [id] with its maker's installer; where there is none to run
  /// here, opens its install page. True when it ran an installer that worked.
  Future<bool> install(String id) async {
    final windows = Desktop.current == .windows;
    switch (id) {
      case 'claude':
        final r = windows
            ? await _run('powershell', [
                '-NoProfile',
                '-Command',
                'irm https://claude.ai/install.ps1 | iex',
              ])
            : await _run('bash', ['-c', 'curl -fsSL https://claude.ai/install.sh | bash']);
        return r?.exitCode == 0;
      case 'codex':
        if (await _find('npm') case final npm?) {
          final r = await _run(npm, ['install', '-g', '@openai/codex']);
          if (r?.exitCode == 0) return true;
        }
        await _desktop.open('https://github.com/openai/codex#installation');
        return false;
      case 'ollama':
        if (await _find('brew') case final brew?) {
          final r = await _run(brew, ['install', 'ollama']);
          if (r?.exitCode == 0) {
            await _run(brew, ['services', 'start', 'ollama']);
            return true;
          }
        }
        await _desktop.open('https://ollama.com/download');
        return false;
    }
    return false;
  }

  /// Signs [id] in through the browser (or, for the model here, starts it).
  /// Done when the browser sign-in finishes, or [cancelSignIn] stops it;
  /// true when it worked. [configDir]: an account's own folder.
  Future<bool> signIn(String id, {String? configDir}) async {
    switch (id) {
      case 'claude':
        final bin = await _find('claude');
        if (bin == null) return false;
        return _login(bin, ['auth', 'login', '--claudeai'], {'CLAUDE_CONFIG_DIR': ?configDir});
      case 'codex':
        final bin = await _find('codex');
        if (bin == null) return false;
        return _login(bin, ['login'], {'CODEX_HOME': ?configDir});
      case 'ollama':
        return OllamaDoctor.ensure(start: true);
    }
    return false;
  }

  Process? _signing;

  Future<bool> _login(String bin, List<String> args, Map<String, String> extra) async {
    try {
      final p = await Process.start(
        bin,
        args,
        environment: {...await _locator.environment(), ...extra},
      );
      _signing = p;
      unawaited(p.stdout.drain<void>());
      unawaited(p.stderr.drain<void>());
      return await p.exitCode == 0;
    } on Object {
      return false;
    } finally {
      _signing = null;
    }
  }

  /// Stops a browser sign-in that is waiting, so it ends as not done.
  void cancelSignIn() => _signing?.kill();

  /// Who is signed in to the account in [folder], as the connection says:
  /// their email where it tells, "signed in" where it does not; null when
  /// nobody is.
  Future<String?> signedInAs(String kind, String folder) async {
    switch (kind) {
      case 'claude':
        final bin = await _find('claude');
        if (bin == null) return null;
        final r = await _run(bin, ['auth', 'status'], extra: {'CLAUDE_CONFIG_DIR': folder});
        try {
          final j = jsonDecode('${r?.stdout}') as Map;
          return j['loggedIn'] == true ? (j['email'] as String? ?? 'signed in') : null;
        } on Object {
          return null;
        }
      case 'codex':
        final bin = await _find('codex');
        if (bin == null) return null;
        final r = await _run(bin, ['login', 'status'], extra: {'CODEX_HOME': folder});
        if (r?.exitCode != 0 || !'${r?.stdout}${r?.stderr}'.contains('Logged in')) return null;
        return codexEmail(folder) ?? 'signed in';
    }
    return null;
  }

  /// The email in a Codex account's sign-in token, where it has one.
  static String? codexEmail(String folder) {
    try {
      final auth = jsonDecode(File('$folder/auth.json').readAsStringSync()) as Map;
      final token = '${(auth['tokens'] as Map?)?['id_token'] ?? ''}'.split('.');
      if (token.length < 2) return null;
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token[1]))));
      return (claims as Map)['email'] as String?;
    } on Object {
      return null;
    }
  }

  /// The file that marks an account's folder as one Helmy made, so Helmy
  /// may remove it; folders made another way are the user's own.
  static const addedMark = '.helmy-added';

  /// Signs a new account of [kind] ('claude' or 'codex') in through the
  /// browser, into a folder of its own beside the usual one, named after
  /// [name] (~/.claude-work). The account, or null when sign-in did not
  /// finish, in which case the folder goes too: nothing half-done is kept.
  /// [taken]: ids already in use.
  Future<ConnectionAccount?> addAccount(
    String kind,
    String name, {
    String? home,
    Set<String> taken = const {},
  }) async {
    final base = home ?? homeDir;
    if (base.isEmpty) return null;
    final slug = slugOf(name);
    var id = '$kind-$slug';
    for (var n = 2; taken.contains(id) || Directory('$base/.$id').existsSync(); n++) {
      id = '$kind-$slug-$n';
    }
    final dir = Directory('$base/.$id');
    await dir.create(recursive: true);
    await File('${dir.path}/$addedMark').writeAsString('Added by Helmy.\n');
    if (!await signIn(kind, configDir: dir.path)) {
      await dir.delete(recursive: true);
      return null;
    }
    return ConnectionAccount(id: id, kind: kind, name: name, folder: dir.path, made: true);
  }

  /// [name] as it can stand in a folder's name and an id: "Work (2026)" is
  /// work-2026.
  static String slugOf(String name) {
    final s = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'account' : s;
  }

  /// Whether the account in [folder] is one Helmy added.
  static bool addedByHelmy(String folder) => File('$folder/$addedMark').existsSync();

  /// Removes an account Helmy added: its folder and sign-in go. False for one
  /// Helmy did not add, which stays.
  Future<bool> removeAccount(String folder) async {
    if (!addedByHelmy(folder)) return false;
    await Directory(folder).delete(recursive: true);
    return true;
  }

  /// A connection's kind, for its version: every Claude Code account is the
  /// one program, as is every Codex; Ollama is its own.
  static String? kindOf(String engineId) => engineId.startsWith('claude')
      ? 'claude'
      : engineId.startsWith('codex')
      ? 'codex'
      : engineId.contains('ollama')
      ? 'ollama'
      : null;

  /// The version of [kind] installed here, as it says it; null when it is
  /// not installed or would not say.
  Future<String?> installedVersion(String kind) async {
    final bin = await _find(kind);
    if (bin == null) return null;
    final r = await _run(bin, ['--version']);
    return versionIn('${r?.stdout ?? ''}${r?.stderr ?? ''}');
  }

  /// The newest version of [kind] its maker has published; null when that
  /// could not be found out (offline, say).
  Future<String?> latestVersion(String kind) async {
    final url = switch (kind) {
      'claude' => 'https://registry.npmjs.org/@anthropic-ai/claude-code/latest',
      'codex' => 'https://registry.npmjs.org/@openai/codex/latest',
      'ollama' => 'https://api.github.com/repos/ollama/ollama/releases/latest',
      _ => null,
    };
    if (url == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'Helmy');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      return versionIn('${json['version'] ?? json['tag_name'] ?? ''}');
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Updates [kind] the way it was installed: Claude Code and Codex update
  /// themselves; Ollama through Homebrew, else its download page opens.
  /// True when an update ran and worked.
  Future<bool> update(String kind) async {
    switch (kind) {
      case 'claude' || 'codex':
        final bin = await _find(kind);
        if (bin == null) return false;
        return (await _run(bin, ['update']))?.exitCode == 0;
      case 'ollama':
        final bin = await _find('ollama');
        final brew = await _find('brew');
        if (bin != null &&
            brew != null &&
            (await File(bin).resolveSymbolicLinks()).contains('/Cellar/')) {
          return (await _run(brew, ['upgrade', 'ollama']))?.exitCode == 0;
        }
        await _desktop.open('https://ollama.com/download');
        return false;
    }
    return false;
  }

  /// The first version number in [text]: "codex-cli 0.162.1" is 0.162.1.
  static String? versionIn(String text) => RegExp(r'\d+\.\d+(?:\.\d+)?').firstMatch(text)?[0];

  /// Whether version [a] is newer than [b], part by part.
  static bool newer(String a, String b) {
    final x = [for (final p in a.split('.')) int.tryParse(p) ?? 0];
    final y = [for (final p in b.split('.')) int.tryParse(p) ?? 0];
    for (var i = 0; i < 3; i++) {
      final l = i < x.length ? x[i] : 0, r = i < y.length ? y[i] : 0;
      if (l != r) return l > r;
    }
    return false;
  }
}
