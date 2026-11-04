import '../../../domain/models/engine.dart';
import 'usage_meter.dart';

/// Picks the engine for each message.
abstract class EngineRouter {
  /// One of [candidates] (all installed and not down), or null when empty.
  /// [current] is the session's own engine; [needs] what the message needs.
  /// [warm]: the thread's last turn was moments ago, so its connection
  /// holds it in cache (decision `0014`).
  String? choose({
    required List<EngineInfo> candidates,
    required String? current,
    Set<Capability> needs = const {},
    bool warm = false,
  });
}

/// Capability first, then measured headroom (decision `0014`). A message
/// that needs something goes to an engine that has it, the session's own if
/// it can. A new thread starts where there is room, never on one close to its
/// limit with its reset far off. A warm thread stays on its engine, whose
/// cache holds it, unless that is nearly out; a cold one (idle past the
/// cache's life, so re-read wherever it goes) moves when another has clearly
/// more room. A forced move keeps the same kind of engine (another Claude
/// Code account) where one has room. Engines that have reported nothing yet
/// count as half used: unknown, not empty.
class HeadroomRouter implements EngineRouter {
  new(this._meter, {double Function()? margin, this.nearlyOut = .95, DateTime Function()? now})
    : _margin = margin ?? (() => .15),
      _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Close to its limit, with its reset more than an hour off: no place for a
  /// new thread, which would only have to move.
  bool _tight(String id) {
    final u = _meter.usageOf(id);
    if (u == null || u.used < .8) return false;
    final reset = u.resetsAt;
    return reset == null || reset.difference(_now()) > const Duration(hours: 1);
  }

  /// The kind of engine: every Claude Code account is "claude".
  static String _family(String id) => id.split('-').first;

  final UsageMeter _meter;

  /// How much more room another engine needs before a switch is worth a handoff.
  /// Read on every choice, so a change in settings applies at once.
  final double Function() _margin;
  final double nearlyOut;

  double _used(String id) => _meter.usageOf(id)?.used ?? .5;

  @override
  String? choose({
    required List<EngineInfo> candidates,
    required String? current,
    Set<Capability> needs = const {},
    bool warm = false,
  }) {
    // When nobody has what is needed, the best any engine can do still beats nothing.
    final able = candidates.where((e) => e.capabilities.containsAll(needs)).toList();
    final pool = [for (final e in able.isEmpty ? candidates : able) e.id];
    if (pool.isEmpty) return null;
    String roomiestOf(List<String> ids) => ids.reduce((a, b) => _used(b) < _used(a) ? b : a);
    // Where a thread may start: not where it would soon have to move from.
    final open = [
      for (final id in pool)
        if (!_tight(id)) id,
    ];
    final roomiest = roomiestOf(open.isEmpty ? pool : open);
    if (current == null || !pool.contains(current)) return roomiest;
    final mine = _meter.usageOf(current)?.used;
    if (mine == null) return current;
    if (mine >= nearlyOut) {
      // Forced: the same kind of engine first, so the thread reads the same.
      final kin = [
        for (final id in pool)
          if (id != current && _family(id) == _family(current) && _used(id) < nearlyOut) id,
      ];
      if (kin.isNotEmpty) return roomiestOf(kin);
      return roomiest != current ? roomiest : current;
    }
    // Warm, it stays: moving would throw its cache away.
    if (warm) return current;
    if (_used(roomiest) + _margin() < mine) return roomiest;
    return current;
  }
}
