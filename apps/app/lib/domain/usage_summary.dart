import 'models/engine.dart';

/// One window of a plan as the top bar shows it: how much is used, or null
/// when that is not known now (never read, or reset since it was).
typedef WindowNow = ({String name, double? used, DateTime? resetsAt});

/// One plan Helmy can send messages to, with its windows as they stand.
typedef PlanNow = ({
  String id,
  String name,
  List<WindowNow> windows,

  /// The fullest window still open, or null when none is known.
  double? used,

  /// When its newest reading was taken.
  DateTime? readAt,
});

/// The usage the top bar shows: every plan messages may go to, and the one
/// with the most room, which is where the next message goes on room alone.
/// Local models (no limit) and agents that report none are left out.
class UsageSummary {
  UsageSummary._(this.plans, this.roomiest);

  final List<PlanNow> plans;

  /// The plan with the most room that has measured any; null when none has.
  final PlanNow? roomiest;

  /// Nothing to show: no plan with a limit is in use.
  bool get isEmpty => plans.isEmpty;

  static UsageSummary of({
    required List<EngineInfo> engines,
    required bool Function(String id) uses,
    required Usage? Function(String id) usage,
    required String Function(EngineInfo e) name,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    bool open(DateTime? reset) => reset == null || reset.isAfter(at);
    final plans = <PlanNow>[];
    for (final e in engines) {
      if (e.localOnly || e.assignedOnly || !uses(e.id)) continue;
      final u = usage(e.id);
      final read = u == null
          ? const <UsageWindow>[]
          : u.windows.isEmpty
          ? [UsageWindow(name: 'Limit', used: u.used, resetsAt: u.resetsAt)]
          : u.windows;
      final windows = <WindowNow>[
        for (final w in read)
          (name: w.name, used: open(w.resetsAt) ? w.used : null, resetsAt: w.resetsAt),
      ];
      final known = [for (final w in windows) ?w.used];
      plans.add((
        id: e.id,
        name: name(e),
        windows: windows,
        used: known.isEmpty ? null : known.reduce((a, b) => a > b ? a : b),
        readAt: u?.reportedAt,
      ));
    }
    PlanNow? roomiest;
    for (final p in plans) {
      if (p.used == null) continue;
      if (roomiest == null || p.used! < roomiest.used!) roomiest = p;
    }
    return UsageSummary._(plans, roomiest);
  }
}

/// A window's name as people say it: "5 hours", "This week".
String windowName(String name) {
  final n = name.toLowerCase();
  if (n.contains('5 hour') || n.contains('session')) return '5 hours';
  if (n.contains('week')) return 'This week';
  if (n.contains('month')) return 'This month';
  if (n.contains('day')) return 'Today';
  return name;
}
