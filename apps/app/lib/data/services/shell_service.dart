import 'dart:io';

import '../../utils/platform.dart';

/// Runs a command the user typed (`!command`) in their own shell, in a folder.
class ShellService {
  const ShellService();

  /// What [command] printed and how it ended, run in [cwd]; at most
  /// [limit] long.
  Future<({String output, bool failed})> run(
    String command,
    String cwd, {
    Duration limit = const Duration(minutes: 2),
  }) async {
    try {
      final (shell, args) = shellFor(command);
      final r = await Process.run(shell, args, workingDirectory: cwd).timeout(limit);
      final out = '${r.stdout}${r.stderr}'.trimRight();
      return (
        output: out.isNotEmpty ? out : (r.exitCode == 0 ? '(no output)' : 'exit ${r.exitCode}'),
        failed: r.exitCode != 0,
      );
    } on Object catch (e) {
      return (output: '$e', failed: true);
    }
  }
}
