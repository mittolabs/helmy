import 'package:flutter/foundation.dart';

import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/services/history_import.dart';
import '../../domain/models/session.dart';
import '../../utils/result.dart';

/// Bringing the conversations people had in their other AI tools into
/// Helmy: which folders have some, which are chosen, and bringing them in.
class HistoryImportViewModel extends ChangeNotifier {
  HistoryImportViewModel({
    required this._import,
    required this._sessions,
    required this._conversations,
  });

  final HistoryImport _import;
  final SessionRepository _sessions;
  final ConversationRepository _conversations;

  /// What a conversation brought in says first, without naming where from.
  static const note = "Brought in from this Mac's history. It goes on from here.";

  /// Folders with conversations to bring in, newest first; null while looking.
  List<FoundProject>? projects;

  /// The folders chosen.
  final chosen = <String>{};

  /// Being brought in: how many of how many.
  (int, int)? progress;

  /// How many came in, once done.
  int? imported;

  /// Recent work is chosen to start with: a conversation in the last two
  /// weeks.
  static const recent = Duration(days: 14);

  Future<void> load() async {
    final known = {
      for (final s in _sessions.sessions)
        for (final t in s.threads.values) ?t.resumeId,
    };
    final found = await _import.scan(known: known);
    final since = DateTime.now().subtract(recent);
    projects = found;
    chosen
      ..clear()
      ..addAll([
        for (final p in found)
          if (p.latest.isAfter(since)) p.cwd,
      ]);
    notifyListeners();
  }

  void toggle(String cwd) {
    if (!chosen.remove(cwd)) chosen.add(cwd);
    notifyListeners();
  }

  void chooseAll(bool all) {
    chosen.clear();
    if (all) chosen.addAll([for (final p in projects ?? const <FoundProject>[]) p.cwd]);
    notifyListeners();
  }

  /// The conversations in the chosen folders.
  int get chosenConversations => [
    for (final p in projects ?? const <FoundProject>[])
      if (chosen.contains(p.cwd)) p.conversations.length,
  ].fold(0, (a, b) => a + b);

  /// Brings in every conversation in the chosen folders, each as a session
  /// that goes on where it left off. How many came in.
  Future<int> importChosen() async {
    final list = [
      for (final p in projects ?? const <FoundProject>[])
        if (chosen.contains(p.cwd)) ...p.conversations,
    ];
    var done = 0;
    progress = (0, list.length);
    notifyListeners();
    for (final (i, c) in list.indexed) {
      try {
        final read = await _import.read(c);
        if (read != null) {
          final made = await _sessions.create(cwd: c.cwd, title: read.title);
          if (made case Ok(value: final s)) {
            await _sessions.save(
              s.copyWith(
                updatedAt: read.endedAt ?? c.updatedAt,
                // The connection it was had in picks up its own thread, and
                // has seen all of it; any other hears it with the next message.
                threads: {c.engineId: EngineThread(resumeId: c.threadId, seen: read.items.length)},
                lastEngineId: c.engineId,
              ),
            );
            await _conversations.adopt(s.id, read.items, note: note);
            done++;
          }
        }
      } on Object {
        // One that cannot be read is left; the rest still come in.
      }
      progress = (i + 1, list.length);
      notifyListeners();
    }
    progress = null;
    imported = done;
    await load();
    return done;
  }
}
