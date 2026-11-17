/// `helmy run <command>`: a command with the secrets in Helmy's vault for
/// this folder, as 1Password's `op run` does. Compiled on its own
/// (`dart compile exe`) for each system, shipped inside Helmy, and put on the
/// PATH by Settings > Vault. Helmy has to be open: it hands the secrets out.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:helmy_cli/run_protocol.dart';

Future<void> main(List<String> args) async => exit(await _run(args));

void _say(String s) => stderr.writeln('helmy: $s');

Future<int> _run(List<String> args) async {
  if (args.length < 2 || args.first != 'run') {
    stderr.writeln('Usage: helmy run <command> [arguments...]');
    return 64;
  }
  final command = args[1];
  final rest = args.sublist(2);

  final file = File(
    runFile(os: Platform.operatingSystem, env: Platform.environment),
  );
  final int port;
  final String token;
  try {
    (port, token) = decodeRunFile(file.readAsStringSync());
  } on Object {
    _say('open Helmy first; it hands out the secrets.');
    return 69;
  }

  final RunAnswer answer;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final q = await client.get('127.0.0.1', port, '/env');
    q.headers
      ..set(tokenHeader, token)
      // Encoded, so a folder with any letters in its name arrives as it is.
      ..set(folderHeader, Uri.encodeComponent(Directory.current.path));
    final r = await q.close().timeout(const Duration(seconds: 30));
    final body = await r.transform(utf8.decoder).join();
    if (r.statusCode != 200) throw HttpException('${r.statusCode}');
    answer = decodeAnswer(body);
  } on Object {
    _say("Helmy didn't answer. Is it open?");
    return 69;
  } finally {
    client.close(force: true);
  }
  for (final p in answer.problems) {
    _say(p);
  }

  final Process child;
  try {
    child = await Process.start(
      command,
      rest,
      environment: answer.env,
      mode: ProcessStartMode.inheritStdio,
      // Windows finds npm, a .cmd, only through its shell.
      runInShell: Platform.isWindows,
    );
  } on ProcessException {
    _say('$command: command not found');
    return 127;
  }

  // Ctrl-C reaches the command itself (it shares the terminal); helmy only
  // waits for it to finish. A request to stop helmy is passed on.
  final subs = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) {}),
    if (!Platform.isWindows)
      for (final s in [ProcessSignal.sigterm, ProcessSignal.sighup])
        s.watch().listen((s) => child.kill(s)),
  ];
  final code = await child.exitCode;
  for (final s in subs) {
    unawaited(s.cancel());
  }
  // Ended by a signal: as a shell reports it.
  return code < 0 ? 128 - code : code;
}
