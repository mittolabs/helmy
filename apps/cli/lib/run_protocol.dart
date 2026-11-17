/// What `helmy run` and Helmy agree on, shared by the command (bin/helmy.dart)
/// and the app, which depends on this package as it does the relay's.
///
/// Helmy listens on this computer's loopback, on a port of its choosing, and
/// answers only a request carrying the token it wrote to [runFile], a file
/// only this user can read. The same on macOS, Windows and Linux.
library;

import 'dart:convert';

/// Where Helmy writes its port and token while it is open.
String runFile({required String os, required Map<String, String> env}) {
  if (env['HELMY_RUN_FILE'] case final f? when f.isNotEmpty) return f;
  final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
  return switch (os) {
    'macos' => '$home/Library/Application Support/com.mittolabs.helmy/run.json',
    'windows' =>
      '${env['LOCALAPPDATA'] ?? '$home\\AppData\\Local'}\\Helmy\\run.json',
    _ => '${env['XDG_STATE_HOME'] ?? '$home/.local/state'}/helmy/run.json',
  };
}

/// The run file's content.
String runFileJson(int port, String token) =>
    jsonEncode({'port': port, 'token': token});

/// The port and token in a run file.
(int, String) decodeRunFile(String text) {
  final m = jsonDecode(text) as Map;
  return ((m['port'] as num).toInt(), m['token'] as String);
}

/// The header the token is sent in, and the one naming the folder.
const tokenHeader = 'x-helmy-token';
const folderHeader = 'x-helmy-folder';

/// The answer: the variables to set, and anything that could not be fetched.
typedef RunAnswer = ({Map<String, String> env, List<String> problems});

String encodeAnswer(RunAnswer a) =>
    jsonEncode({'env': a.env, 'problems': a.problems});

RunAnswer decodeAnswer(String body) {
  final m = jsonDecode(body) as Map;
  return (
    env: {for (final e in (m['env'] as Map).entries) '${e.key}': '${e.value}'},
    problems: [for (final p in (m['problems'] as List? ?? const [])) '$p'],
  );
}

/// Equal, taking as long whatever the difference: a token is not guessed
/// one letter at a time.
bool sameToken(String a, String b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return d == 0;
}
