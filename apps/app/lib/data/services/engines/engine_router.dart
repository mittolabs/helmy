import '../../../domain/models/engine.dart';
import 'usage_meter.dart';

/// Picks the engine for each message.
abstract class EngineRouter {
  /// One of [candidates] (all installed and not down), or null when empty.
  /// [current] is the session's own engine; [needs] what the message needs.
  String? choose({
    required List<EngineInfo> candidates,
    required String? current,
    Set<Capability> needs = const {},
  });
}

/// Capability first, then measured headroom. A message that needs something
/// goes to an engine that has it, the session's own if it can. Otherwise the
/// session stays with its engine, so it keeps its own context, unless another
/// has clearly more room or it is nearly out. Engines that have reported
/// nothing yet count as half used: unknown, not empty.
class HeadroomRouter implements EngineRouter {
  new(this._meter, {double Function()? margin, this.nearlyOut = .95})
    : _margin = margin ?? (() => .15);

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
  }) {
    // When nobody has what is needed, the best any engine can do still beats nothing.
    final able = candidates.where((e) => e.capabilities.containsAll(needs)).toList();
    final pool = [for (final e in able.isEmpty ? candidates : able) e.id];
    if (pool.isEmpty) return null;
    final roomiest = pool.reduce((a, b) => _used(b) < _used(a) ? b : a);
    if (current == null || !pool.contains(current)) return roomiest;
    final mine = _meter.usageOf(current)?.used;
    if (mine == null) return current;
    if (mine >= nearlyOut && roomiest != current) return roomiest;
    if (_used(roomiest) + _margin() < mine) return roomiest;
    return current;
  }
}
