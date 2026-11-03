import 'dart:io';

/// Finds agent CLIs and the PATH they should run with.
///
/// An app opened from Finder gets launchd's bare PATH, not the shell's, so
/// neither the CLI nor the tools it calls would be found. Ask a login shell
/// once and reuse the answer.
class CliLocator {
  Future<Map<String, String>>? _environment;
  final Map<String, String?> _binaries = {};

  Future<Map<String, String>> environment() => _environment ??= _loadEnvironment();

  Future<Map<String, String>> _loadEnvironment() async {
    final env = Map<String, String>.of(Platform.environment);
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

  /// The absolute path of [name], or null if it is not installed.
  Future<String?> find(String name) async {
    if (_binaries.containsKey(name)) return _binaries[name];
    final env = await environment();
    final home = env['HOME'] ?? '';
    final dirs = [
      ...(env['PATH'] ?? '').split(':'),
      '$home/.local/bin',
      '/opt/homebrew/bin',
      '/usr/local/bin',
    ];
    final found = dirs
        .where((d) => d.isNotEmpty)
        .map((d) => '$d/$name')
        .where((p) => File(p).existsSync())
        .firstOrNull;
    return _binaries[name] = found;
  }
}
