import 'package:flutter/foundation.dart';

import '../../../domain/models/engine.dart';
import '../storage_service.dart';

/// What Helmy knows about each engine's room left: usage the engines
/// reported, when, and which have failed recently. Shared by every session,
/// since limits belong to the account, not the conversation. Readings are kept
/// across launches, with when they were taken, so an old one reads as old.
class UsageMeter extends ChangeNotifier {
  new({this._storage});

  final StorageService? _storage;
  final Map<String, Usage> _usage = {};
  final Map<String, DateTime> _downUntil = {};

  Future<void> load() async {
    final raw = await _storage?.read('usage.json');
    if (raw is! Map) return;
    for (final e in raw.entries) {
      if (e.value is Map) _usage['${e.key}'] = Usage.fromJson((e.value as Map).cast());
    }
    notifyListeners();
  }

  Usage? usageOf(String engineId) => _usage[engineId];

  /// How full a connection may get before the next message goes elsewhere:
  /// between turns, never in the middle of one.
  static const switchAt = .9;

  /// How much of [engineId]'s current window is used, as measured: the
  /// fullest window that has not reset since it was read. Null when nothing
  /// was measured, or every window it read has reset since: a number from
  /// before a reset says nothing about now.
  double? usedNow(String engineId, {DateTime? now}) {
    final u = _usage[engineId];
    if (u == null) return null;
    final at = now ?? DateTime.now();
    bool open(DateTime? reset) => reset == null || reset.isAfter(at);
    if (u.windows.isEmpty) return open(u.resetsAt) ? u.used : null;
    final live = [
      for (final w in u.windows)
        if (open(w.resetsAt)) w.used,
    ];
    return live.isEmpty ? null : live.reduce((a, b) => a > b ? a : b);
  }

  /// Whether [engineId] has measurably reached [switchAt] in its current
  /// window. A connection that has measured nothing is never nearly out.
  bool nearlyOut(String engineId, {DateTime? now}) =>
      (usedNow(engineId, now: now) ?? 0) >= switchAt;

  DateTime? _saved;

  /// Takes a reading. The time it was taken is kept even when the number is the
  /// same as before, so "as of" always says how fresh the newest reading is.
  void report(String engineId, Usage? usage, {DateTime? now}) {
    if (usage == null) return;
    final at = now ?? DateTime.now();
    final old = _usage[engineId];
    _usage[engineId] = Usage(
      used: usage.used,
      resetsAt: usage.resetsAt,
      reportedAt: at,
      windows: usage.windows,
    );
    final changed = old == null || old.used != usage.used || old.resetsAt != usage.resetsAt;
    // Streaming reports come many times a turn: the screen and the file only
    // need the number when it moves, and the time about once a minute.
    if (changed || _saved == null || at.difference(_saved!).inSeconds >= 60) {
      _saved = at;
      notifyListeners();
      _storage?.write('usage.json', {for (final e in _usage.entries) e.key: e.value.toJson()});
    }
  }

  /// Keeps [engineId] out of routing until it resets, or for a while when
  /// nobody said when.
  void markDown(String engineId, {DateTime? until, DateTime? now}) {
    final reset = until ?? _usage[engineId]?.resetsAt;
    final from = now ?? DateTime.now();
    _downUntil[engineId] = reset != null && reset.isAfter(from)
        ? reset
        : from.add(const Duration(minutes: 15));
    notifyListeners();
  }

  bool isDown(String engineId, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final until = _downUntil[engineId];
    if (until != null && at.isBefore(until)) return true;
    final usage = _usage[engineId];
    return usage != null &&
        usage.used >= 1 &&
        usage.resetsAt != null &&
        at.isBefore(usage.resetsAt!);
  }

  DateTime? downUntil(String engineId) {
    if (!isDown(engineId)) return null;
    final marked = _downUntil[engineId];
    final reported = _usage[engineId]?.resetsAt;
    if (marked == null || (reported != null && reported.isAfter(marked))) return reported;
    return marked;
  }
}
