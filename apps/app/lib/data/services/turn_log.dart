import 'dart:convert';
import 'dart:io';

import '../../domain/models/engine.dart';

/// What Helmy measures about its chats and threads (decision `0014`), to be
/// improved on: one JSON line per event, a file a month, on this Mac only.
/// Lines point at turns by thread and position; they never copy what was
/// said. A figure a connection does not report is null, never estimated.
class TurnLog {
  TurnLog({required this._appData, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Future<Directory> Function() _appData;
  final DateTime Function() _now;

  /// The folder the monthly files are in.
  Future<Directory> folder() async => Directory('${(await _appData()).path}/logs');

  /// The write under way: each waits for the one before it, since appends
  /// made at once interleave and break a line (found 2026-11-14, judging
  /// on two connections in a row without waiting for the log).
  Future<void> _writing = Future.value();

  Future<void> _write(String kind, Map<String, Object?> fields) {
    final at = _now();
    return _writing = _writing.then((_) => _append(at, kind, fields));
  }

  Future<void> _append(DateTime at, String kind, Map<String, Object?> fields) async {
    try {
      final dir = await folder();
      await dir.create(recursive: true);
      final month = '${at.year}-${at.month.toString().padLeft(2, '0')}';
      final line = jsonEncode({'at': at.toUtc().toIso8601String(), 'kind': kind, ...fields});
      await File('${dir.path}/turns-$month.jsonl')
          .writeAsString('$line\n', mode: FileMode.append, flush: true);
    } on Object {
      // A log that cannot be written never stops the work it logs.
    }
  }

  /// A turn ended: where it ran, whether it stayed on the thread's own
  /// connection, its tokens, how long it took, and which items it holds.
  Future<void> turn({
    required String? chat,
    required String thread,
    required String connection,
    required bool moved,
    required TurnTokens? tokens,
    required Duration took,
    required int from,
    required int to,
    String? why,
  }) => _write('turn', {
    'chat': chat,
    'thread': thread,
    'connection': connection,
    'moved': moved,
    'why': why,
    'tokens': tokens?.toJson(),
    'ms': took.inMilliseconds,
    'items': [from, to],
  });

  /// A connection failed a message before doing anything, and it went on to
  /// another (or waited): which, and its own words for why. Kept, since the
  /// chat takes the failure back and shows only where the message went.
  Future<void> failed({
    required String? chat,
    required String thread,
    required String connection,
    required String error,
    required bool limit,
  }) => _write('failed', {
    'chat': chat,
    'thread': thread,
    'connection': connection,
    'limit': limit,
    'error': error.length > 2000 ? error.substring(0, 2000) : error,
  });

  /// A new thread filed: where, how sure, the runner-up.
  Future<void> filing({
    required String thread,
    required String kind,
    String? chat,
    double? score,
    String? runnerUp,
    double? runnerUpScore,
  }) => _write('filing', {
    'thread': thread,
    'decided': kind,
    'chat': chat,
    'score': score,
    'runnerUp': runnerUp,
    'runnerUpScore': runnerUpScore,
  });

  /// Helmy's own upkeep (a summary, a brief, a judged approval): which
  /// model, its tokens. [connection] and [tokens] (fresh, cached, output)
  /// where the upkeep ran on a connection, with how long it took.
  Future<void> upkeep({
    required String what,
    required String thread,
    String? chat,
    String? model,
    int? promptTokens,
    int? outputTokens,
    bool kept = true,
    String? connection,
    TurnTokens? tokens,
    Duration? took,
  }) => _write('upkeep', {
    'what': what,
    'thread': thread,
    'chat': chat,
    'model': model,
    'local': model != null && connection == null,
    'promptTokens': promptTokens,
    'outputTokens': outputTokens,
    'kept': kept,
    'connection': ?connection,
    if (connection != null) 'tokens': tokens?.toJson(),
    if (took != null) 'ms': took.inMilliseconds,
  });

  /// The agent looked into another thread of its chat: which rung of the
  /// ladder (summaries, a thread's matching parts, a whole thread), and how
  /// much came back, in characters.
  Future<void> lookup({
    required String thread,
    required String chat,
    required String rung,
    required int size,
  }) => _write('lookup', {'thread': thread, 'chat': chat, 'rung': rung, 'size': size});

  /// The person moved a thread to another chat (or out into its own), or
  /// rewrote a chat's brief: what filing and briefs are tuned on.
  Future<void> correction({
    required String what,
    required String thread,
    String? from,
    String? to,
  }) => _write('correction', {'what': what, 'thread': thread, 'from': from, 'to': to});

  /// Every line in [month] ("2026-11"), oldest first.
  Future<List<Map<String, Object?>>> read(String month) async {
    final f = File('${(await folder()).path}/turns-$month.jsonl');
    if (!f.existsSync()) return const [];
    return [
      for (final l in await f.readAsLines())
        if (l.trim().isNotEmpty) (jsonDecode(l) as Map).cast<String, Object?>(),
    ];
  }
}
