import '../../utils/format.dart';
import 'engine.dart';

/// How often a scheduled task runs.
enum Repeat {
  once('Once'),
  hourly('Every hour'),
  daily('Every day'),
  weekdays('Weekdays'),
  weekly('Every week'),
  days('On chosen days');

  const Repeat(this.label);
  final String label;
}

/// When a task runs. [at] carries what the repeat needs: the date and time
/// for once, the minute for hourly, the time of day for daily and weekdays,
/// the day of the week and time for weekly.
class const Schedule(final Repeat repeat, final DateTime at, {final Set<int> days = const {}}) {
  /// The first time after [after] that it runs; null when it never will again.
  DateTime? nextAfter(DateTime after) {
    DateTime day(int plus) =>
        DateTime(after.year, after.month, after.day + plus, at.hour, at.minute);
    switch (repeat) {
      case .once:
        return at.isAfter(after) ? at : null;
      case .hourly:
        final c = DateTime(after.year, after.month, after.day, after.hour, at.minute);
        return c.isAfter(after) ? c : DateTime(c.year, c.month, c.day, c.hour + 1, at.minute);
      case .daily || .weekdays || .weekly || .days:
        if (repeat == .days && days.isEmpty) return null;
        for (var plus = 0; plus <= 7; plus++) {
          final c = day(plus);
          if (!c.isAfter(after)) continue;
          if (repeat == .weekdays && c.weekday > DateTime.friday) continue;
          if (repeat == .weekly && c.weekday != at.weekday) continue;
          if (repeat == .days && !days.contains(c.weekday)) continue;
          return c;
        }
        return null;
    }
  }

  /// "Every day at 9:00 AM", "Mondays at 8:30 AM", "Once, Nov 4 at 3:00 PM".
  String get label {
    final time = clock(at);
    return switch (repeat) {
      .once => 'Once, ${monthDay(at)} at $time',
      .hourly => 'Every hour at :${at.minute.toString().padLeft(2, '0')}',
      .daily => 'Every day at $time',
      .weekdays => 'Weekdays at $time',
      .weekly => '${_weekdays[at.weekday - 1]}s at $time',
      .days =>
        '${[for (final d in days.toList()..sort()) _weekdays[d - 1].substring(0, 3)].join(', ')} at $time',
    };
  }

  Map<String, Object?> toJson() => {
    'repeat': repeat.name,
    'at': at.toIso8601String(),
    if (days.isNotEmpty) 'days': days.toList()..sort(),
  };

  static Schedule fromJson(Map<String, Object?> json) => Schedule(
    Repeat.values.asNameMap()[json['repeat']] ?? .daily,
    DateTime.tryParse('${json['at']}') ?? DateTime(2026, 1, 1, 9),
    days: {...((json['days'] as List?) ?? const []).whereType<int>()},
  );

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
}

/// "Nov 4".
String monthDay(DateTime t) =>
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][t.month - 1]} ${t.day}';

/// A message sent by itself on a schedule, each time in a new session.
class const ScheduledTask({
  required final String id,
  required final String name,
  required final String prompt,
  required final String cwd,
  required final PermissionLevel level,
  required final Schedule schedule,
  required final DateTime createdAt,
  final bool enabled = true,
  final DateTime? lastRunAt,
}) {
  /// When it runs next; null when it will not (a one-off already run, or off).
  DateTime? get next => enabled ? schedule.nextAfter(lastRunAt ?? createdAt) : null;

  /// Due at [now]: its next time has come. A time missed while the app was
  /// closed is due too, once.
  bool dueAt(DateTime now) {
    final n = next;
    return n != null && !n.isAfter(now);
  }

  ScheduledTask copyWith({
    String? name,
    String? prompt,
    String? cwd,
    PermissionLevel? level,
    Schedule? schedule,
    bool? enabled,
    DateTime? lastRunAt,
  }) => ScheduledTask(
    id: id,
    name: name ?? this.name,
    prompt: prompt ?? this.prompt,
    cwd: cwd ?? this.cwd,
    level: level ?? this.level,
    schedule: schedule ?? this.schedule,
    createdAt: createdAt,
    enabled: enabled ?? this.enabled,
    lastRunAt: lastRunAt ?? this.lastRunAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'prompt': prompt,
    'cwd': cwd,
    'level': level.id,
    'schedule': schedule.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'enabled': enabled,
    'lastRunAt': lastRunAt?.toIso8601String(),
  };

  static ScheduledTask fromJson(Map<String, Object?> json) => ScheduledTask(
    id: json['id']! as String,
    name: json['name']! as String,
    prompt: json['prompt']! as String,
    cwd: json['cwd']! as String,
    level: PermissionLevel.fromId(json['level'] as String?),
    schedule: Schedule.fromJson((json['schedule'] as Map).cast()),
    createdAt: DateTime.parse(json['createdAt']! as String),
    enabled: json['enabled'] != false,
    lastRunAt: DateTime.tryParse('${json['lastRunAt']}'),
  );
}
