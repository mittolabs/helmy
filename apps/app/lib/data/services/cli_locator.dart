import 'dart:io';

/// Finds agent CLIs and the PATH they should run with.
///
/// An app opened from Finder gets launchd's bare PATH, not the shell's, so
/// neither the CLI nor the tools it calls would be found. Ask a login shell
/// once and reuse the answer.
class CliLocator {
  CliLocator({Map<String, String> Function()? chosen}) : _chosen = chosen ?? (() => const {});

  /// Programs the user pointed at in Settings, by name, for where finding
  /// them fails: used first, while the file is there.
  final Map<String, String> Function() _chosen;

  Future<Map<String, String>>? _environment;
  final Map<String, String?> _binaries = {};

  Future<Map<String, String>> environment() => _environment ??= _loadEnvironment();

  Future<Map<String, String>> _loadEnvironment() async {
    final env = Map<String, String>.of(Platform.environment);
    // Windows apps get the user's PATH as it is; there is no login shell.
    if (Platform.isWindows) return env;
    try {
      final out = await Process.run(env['SHELL'] ?? '/bin/zsh', [
        '-ilc',
        r'echo "__PATH__=$PATH"',
      ]).timeout(const Duration(seconds: 10));
      for (final line in (out.stdout as String).split('\n')) {
        if (line.startsWith('__PATH__=')) env['PATH'] = line.substring(9).trim();
      }
    } on Object {
      // Keep the inherited PATH and rely on the fallbacks below.
    }
    return env;
  }

  /// Looks for [name] afresh next time: it may have just been installed.
  void forget(String name) => _binaries.remove(name);

  /// The absolute path of [name], or null if it is not installed.
  Future<String?> find(String name) async {
    if (_chosen()[name] case final path? when File(path).existsSync()) return path;
    if (_binaries.containsKey(name)) return _binaries[name];
    final env = await environment();
    final windows = Platform.isWindows;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    final sep = windows ? r'\' : '/';
    final dirs = [
      ...(env['PATH'] ?? '').split(windows ? ';' : ':'),
      '$home$sep.local${sep}bin',
      if (windows) ...[
        // Where npm puts the commands it installs.
        if (env['APPDATA'] case final appData?) '$appData${sep}npm',
      ] else ...[
        '/opt/homebrew/bin',
        '/usr/local/bin',
      ],
    ];
    // On Windows a command is a file with one of these endings.
    final names = windows ? ['$name.exe', '$name.cmd', '$name.bat', name] : [name];
    final found = [
      for (final d in dirs.where((d) => d.isNotEmpty))
        for (final n in names) '$d$sep$n',
    ].where((p) => File(p).existsSync()).firstOrNull;
    return _binaries[name] = found;
  }
}
