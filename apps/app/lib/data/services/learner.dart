import 'dart:convert';

import '../repositories/lesson_repository.dart';
import 'engines/engine_registry.dart';
import 'engines/engine_router.dart';
import '../../domain/models/work.dart';

/// A lesson the learner found, before it is kept.
typedef Found = ({String text, bool everywhere, String kind});

/// Reads what happened in a chat for what will help next time: the
/// person's corrections, what worked, their habits. Only lessons that still
/// hold next week; nothing the code or its history already says; nothing
/// already known.
class Learner {
  Learner(this._engines, this._router, this._enabled);
  final EngineRegistry _engines;
  final EngineRouter _router;
  final bool Function(String engineId) _enabled;

  static const _instructions =
      'You help an AI assistant get better at working with one person. You read part of a '
      'conversation between them and note what the assistant should carry into future work, '
      'in any project. Answer with JSON only: {"lessons": [{"text": "...", "everywhere": '
      'true|false, "kind": "correction" | "worked" | "habit"}]}.\n'
      '- "correction": the person corrected the assistant or said what not to do. Keep the why '
      'when they gave one.\n'
      '- "worked": an approach, check or fix that the person confirmed, or that caught a real '
      'problem.\n'
      '- "habit": something the person wants again and again (how to check work, how to write, '
      'which tools).\n'
      '"everywhere" is true when it is about the person and holds in any project, false when it '
      'is about this project only.\n'
      'Each lesson is one short sentence of instruction to the assistant ("Check a change in the '
      'running app, not only the tests."), in plain words.\n'
      'Leave out: what the code, its files or its history already say; one-off details of this '
      'task; anything already in the known lessons; guesses. Most conversations teach nothing: '
      'then answer {"lessons": []}.';

  /// What [conversation] (the person's and the assistant's words, oldest
  /// first) teaches, given what is [known] already. Asks a connection online
  /// with room; none answering, nothing is learned.
  Future<List<Found>> learn(String conversation, {required List<Lesson> known}) async {
    final request = [
      'Known lessons:',
      if (known.isEmpty) '(none)' else for (final l in known) '- ${l.text}',
      '',
      'The conversation:',
      conversation.length > 12000
          ? conversation.substring(conversation.length - 12000)
          : conversation,
    ].join('\n');
    final online = [
      for (final e in _engines.engines)
        if (_enabled(e.info.id) && !e.info.localOnly) e,
    ];
    final first = online.isEmpty
        ? null
        : _router.choose(
            candidates: [for (final e in online) e.info],
            current: null,
            kind: WorkKind.quick,
          );
    for (final e in [
      ...online.where((e) => e.info.id == first),
      ...online.where((e) => e.info.id != first),
    ]) {
      final answer = await e.ask(_instructions, request);
      if (answer == null) continue;
      final found = parse(answer.text);
      if (found != null) return found;
    }
    return const [];
  }

  /// The lessons in a learner's [answer]; null when it holds none to read.
  static List<Found>? parse(String answer) {
    final m = RegExp(r'\{[\s\S]*\}').firstMatch(answer);
    if (m == null) return null;
    try {
      final j = jsonDecode(m[0]!);
      if (j is! Map || j['lessons'] is! List) return null;
      return [
        for (final l in (j['lessons'] as List).whereType<Map>())
          if ('${l['text'] ?? ''}'.trim().isNotEmpty)
            (
              text: '${l['text']}'.trim(),
              everywhere: l['everywhere'] != false,
              kind: const {'correction', 'worked', 'habit'}.contains(l['kind'])
                  ? '${l['kind']}'
                  : 'habit',
            ),
      ];
    } on FormatException {
      return null;
    }
  }
}
