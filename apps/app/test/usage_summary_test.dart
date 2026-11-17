import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/usage_summary.dart';

/// The top bar's usage: the plans messages can go to, the one with the most
/// room, and only what was measured (a window that reset since is unknown).
void main() {
  // As this computer had them on Nov 17, 11:40: Codex read this morning,
  // Claude Code last read on Nov 14.
  final now = DateTime(2026, 11, 17, 11, 40);
  final readings = {
    'codex': Usage(
      used: .01,
      reportedAt: DateTime(2026, 11, 17, 8, 7),
      windows: [
        UsageWindow(name: 'Session (5 hours)', used: .01, resetsAt: DateTime(2026, 11, 17, 13, 5)),
        UsageWindow(name: 'Weekly', used: 0, resetsAt: DateTime(2026, 11, 23, 22, 16)),
      ],
    ),
    'claude': Usage(
      used: .93,
      reportedAt: DateTime(2026, 11, 14, 22, 1),
      windows: [
        UsageWindow(name: 'Session (5 hours)', used: .93, resetsAt: DateTime(2026, 11, 15, 2, 10)),
        UsageWindow(name: 'Weekly', used: .75, resetsAt: DateTime(2026, 11, 18, 19)),
      ],
    ),
  };
  const engines = [
    EngineInfo(id: 'claude', name: 'Claude Code'),
    EngineInfo(id: 'codex', name: 'Codex'),
    EngineInfo(id: 'ollama-chat', name: 'Ollama', localOnly: true),
    EngineInfo(id: 'acp-opencode', name: 'OpenCode', assignedOnly: true),
  ];

  UsageSummary summary({Set<String> off = const {}}) => UsageSummary.of(
    engines: engines,
    uses: (id) => !off.contains(id),
    usage: (id) => readings[id],
    name: (e) => e.name,
    now: now,
  );

  test('plans with a limit only, and the roomiest leads', () {
    final s = summary();
    expect([for (final p in s.plans) p.name], ['Claude Code', 'Codex']);
    expect(s.roomiest?.name, 'Codex');
    expect(s.roomiest?.used, .01);
  });

  test('a window that reset since it was read is unknown, not its old number', () {
    final claude = summary().plans.first;
    expect([for (final w in claude.windows) w.used], [null, .75]);
    expect(claude.used, .75, reason: 'the week is still open');
  });

  test('a plan turned off is not shown; none left shows nothing', () {
    expect(summary(off: {'codex'}).roomiest?.name, 'Claude Code');
    expect(summary(off: {'codex', 'claude'}).isEmpty, isTrue);
  });

  test('windows named as people say them', () {
    expect(windowName('Session (5 hours)'), '5 hours');
    expect(windowName('Weekly'), 'This week');
  });
}
