import 'dart:io';

import '../../utils/result.dart';
import 'cli_locator.dart';

/// What `gh` said: its exit code and output; null when it could not run.
typedef GhRun = Future<({int code, String out, String err})?> Function(List<String> args);

/// Sharing a chat as a read-only link (as T3 Code shares a thread): the
/// conversation as Markdown in a secret GitHub gist, made with GitHub's own
/// command on the person's account. Anyone with the link can read it; no one
/// can change it; it is unlisted, and stopping sharing deletes it.
class ChatShare {
  ChatShare(this._locator, {GhRun? run}) : _runOverride = run;

  final CliLocator _locator;
  final GhRun? _runOverride;

  Future<({int code, String out, String err})?> _gh(List<String> args) async {
    if (_runOverride case final run?) return run(args);
    final bin = await _locator.find('gh');
    if (bin == null) return null;
    try {
      final r = await Process.run(
        bin,
        args,
        environment: {...await _locator.environment(), 'GH_PROMPT_DISABLED': '1'},
      ).timeout(const Duration(seconds: 60));
      return (code: r.exitCode, out: '${r.stdout}', err: '${r.stderr}');
    } on Object {
      return null;
    }
  }

  /// What keeps sharing from working, in words, with what fixes it; null
  /// when it can.
  Future<String?> trouble() async {
    final auth = await _gh(['auth', 'status']);
    if (auth == null) {
      return "Sharing makes a secret GitHub gist with GitHub's own command, gh, which isn't on "
          'this computer. Install it (on a Mac: brew install gh), sign in with gh auth login, '
          'and share again.';
    }
    if (auth.code != 0) {
      return 'Sharing makes a secret GitHub gist on your account, and GitHub is not signed in '
          'here. Sign in with gh auth login in a terminal, then share again.';
    }
    return null;
  }

  /// Shares [markdown] (the conversation [title]): the link, and the gist's id
  /// to stop sharing with.
  Future<Result<({String url, String id})>> share(String title, String markdown) async {
    if (await trouble() case final why?) return .error(Exception(why));
    final dir = await Directory.systemTemp.createTemp('helmy-share');
    try {
      final name = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ').trim();
      final file = File('${dir.path}/${name.isEmpty ? 'Chat' : name}.md');
      await file.writeAsString(markdown);
      // Secret, as gh makes a gist unless told otherwise: unlisted, by link only.
      final r = await _gh(['gist', 'create', '--desc', '$title (shared from Helmy)', file.path]);
      final url = RegExp(r'https://gist\.github\.com/\S+').firstMatch(r?.out ?? '')?[0];
      if (r == null || r.code != 0 || url == null) {
        final said = (r?.err ?? '').trim();
        return .error(
          Exception(
            'GitHub did not make the gist${said.isEmpty ? '' : ': $said'}. Try again in a moment.',
          ),
        );
      }
      return .ok((url: url, id: url.split('/').last));
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// Stops sharing: the gist is deleted, and its link reads nothing.
  Future<Result<void>> stop(String id) async {
    final r = await _gh(['gist', 'delete', id, '--yes']);
    if (r == null || r.code != 0) {
      final said = (r?.err ?? '').trim();
      // Already gone (deleted on GitHub): not sharing all the same.
      if (said.contains('404') || said.toLowerCase().contains('not found')) return const .ok(null);
      return .error(
        Exception('GitHub did not delete the gist${said.isEmpty ? '' : ': $said'}. Try again.'),
      );
    }
    return const .ok(null);
  }
}
