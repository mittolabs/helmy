import '../../../domain/models/engine.dart';
import '../../../domain/models/work.dart';
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
    WorkKind? kind,
    bool warm = false,
    Set<String>? alike,
  });

  /// Why the last [choose] chose what it did, in a few words for the person
  /// ("most room left"); null when it did not say.
  String? get why;
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
///
/// A move off a connection that is nearly out (measured at
/// [UsageMeter.switchAt] in its current window) or out keeps the chat's
/// class of model: [alike] are the candidates that can answer with a model of
/// the same class as the one the chat was on (flagship to flagship). Where
/// none of them has room, a connection still short of its limit keeps the
/// chat rather than drop to another class; null [alike] means the class is
/// not known, and any connection with more room will do.
class HeadroomRouter implements EngineRouter {
  new(
    this._meter, {
    double Function()? margin,
    this.nearlyOut = UsageMeter.switchAt,
    DateTime Function()? now,
    String? Function(WorkKind)? bestAt,
  }) : _margin = margin ?? (() => .15),
       _now = now ?? DateTime.now,
       _bestAt = bestAt ?? ((k) => defaultBestAt[k]);

  /// The kind of connection best at a kind of work; null for any. Read on
  /// every choice, so a change in settings applies at once.
  final String? Function(WorkKind) _bestAt;

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
  /// The kind of connection [id] is: every Claude Code account is
  /// 'claude'; an agent ('acp.opencode') is its own kind.
  static String familyOf(String id) => id.startsWith('acp.') ? id : id.split('-').first;
  static String _family(String id) => familyOf(id);

  final UsageMeter _meter;

  /// How much more room another engine needs before a switch is worth a handoff.
  /// Read on every choice, so a change in settings applies at once.
  final double Function() _margin;
  final double nearlyOut;

  /// Measured use in the current window; unknown (never read, or read before
  /// a reset) counts as half.
  double _used(String id) => _meter.usedNow(id, now: _now()) ?? .5;

  @override
  String? why;

  @override
  String? choose({
    required List<EngineInfo> candidates,
    required String? current,
    Set<Capability> needs = const {},
    WorkKind? kind,
    bool warm = false,
    Set<String>? alike,
  }) {
    why = null;
    final best = kind == null ? null : _bestAt(kind);
    // One that says nothing of itself answers only what it is set best at.
    // Unless it is all there is: it answering beats nothing answering.
    final picked = [
      for (final e in candidates)
        if (!e.assignedOnly || (best != null && _family(e.id) == best)) e,
    ];
    final known = picked.isEmpty ? candidates : picked;
    // When nobody has what is needed, the best any engine can do still beats nothing.
    final able = known.where((e) => e.capabilities.containsAll(needs)).toList();
    var pool = [for (final e in able.isEmpty ? known : able) e.id];
    // Then the kind of connection best at this kind of work, while one of
    // them has room.
    if (best != null) {
      final theirs = [
        for (final id in pool)
          if (_family(id) == best && _used(id) < nearlyOut) id,
      ];
      if (theirs.isNotEmpty) pool = theirs;
    }
    if (pool.isEmpty) return null;
    final forWork = best != null && pool.every((id) => _family(id) == best) && kind != null;
    final forNeeds = able.isNotEmpty && able.length < known.length && needs.isNotEmpty;
    String because(String plain) => forNeeds
        ? 'the one that ${needs.map((n) => switch (n) {
            .tools => 'can change files and run commands',
            .imageGeneration => 'can make images',
            _ => 'is connected to ${n.label}',
          }).join(' and ')}'
        : forWork
        ? 'best at ${kind.label.toLowerCase()}'
        : plain;
    String roomiestOf(List<String> ids) => ids.reduce((a, b) => _used(b) < _used(a) ? b : a);
    // Where a thread may start: not where it would soon have to move from.
    final open = [
      for (final id in pool)
        if (!_tight(id)) id,
    ];
    final roomiest = roomiestOf(open.isEmpty ? pool : open);
    // Where a chat goes from a connection nearly out or out: another account
    // of the same connection, then the same class of model elsewhere.
    String? kept() {
      bool roomy(String id) => id != current && _used(id) < nearlyOut;
      final kin = [
        for (final id in pool)
          if (roomy(id) && _family(id) == _family(current!)) id,
      ];
      if (kin.isNotEmpty) return roomiestOf(kin);
      final same = [
        for (final id in pool)
          if (roomy(id) && (alike?.contains(id) ?? false)) id,
      ];
      return same.isEmpty ? null : roomiestOf(same);
    }

    if (current != null && alike != null && !pool.contains(current)) {
      // Out: the same class where one has room, anything with room otherwise.
      why = because('moved: the other was at its limit');
      return kept() ?? roomiest;
    }
    if (current == null || !pool.contains(current)) {
      why = because(pool.length == 1 ? 'the only one free' : 'most room left');
      return roomiest;
    }
    final mine = _meter.usedNow(current, now: _now());
    if (mine == null) {
      why = because('already has this chat');
      return current;
    }
    if (mine >= nearlyOut) {
      // Forced, between turns: the same kind of engine first, then the same
      // class of model, so the thread reads the same.
      if (kept() case final to?) {
        why = because('moved: the other was nearly at its limit');
        return to;
      }
      if (alike != null || roomiest == current) {
        why = because('already has this chat');
        return current;
      }
      why = because('moved: the other was nearly at its limit');
      return roomiest;
    }
    // Warm, it stays: moving would throw its cache away.
    if (warm) {
      why = because('already has this chat, fresh');
      return current;
    }
    if (_used(roomiest) + _margin() < mine) {
      why = because('clearly more room left');
      return roomiest;
    }
    why = because('already has this chat');
    return current;
  }
}
