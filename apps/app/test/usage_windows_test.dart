import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/claude/claude_reducer.dart';
import 'package:helmy/data/services/engines/codex/codex_reducer.dart';
import 'package:helmy/domain/models/engine.dart';

void main() {
  final reset = DateTime(2026, 11, 4, 14);
  final secs = reset.millisecondsSinceEpoch ~/ 1000;

  test("Claude's windows are each kept, named by their length", () {
    final r = ClaudeReducer([])
      ..apply({
        'type': 'rate_limit_event',
        'rate_limit_info': {
          'unifiedWindows': {
            'five_hour': {'utilization': 0.22, 'resetsAt': secs},
            'seven_day': {'utilization': 0.19, 'resetsAt': secs},
            'seven_day_opus': {'utilization': 0.0, 'resetsAt': secs},
          },
        },
      });
    final w = r.usage!.windows;
    expect(w.map((x) => x.name), ['Session (5 hours)', 'Weekly', 'Weekly · Opus']);
    expect(r.usage!.used, 0.22, reason: 'routing goes by the fullest');
    expect(w.first.length, const Duration(hours: 5));
  });

  test("Codex's primary and secondary windows, with their lengths", () {
    final r = CodexReducer([])
      ..apply({
        'method': 'account/rateLimits/updated',
        'params': {
          'rateLimits': {
            'primary': {'usedPercent': 5, 'windowDurationMins': 300, 'resetsAt': secs},
            'secondary': {'usedPercent': 6, 'windowDurationMins': 10080, 'resetsAt': secs},
          },
        },
      });
    expect(r.usage!.windows.map((x) => x.name), ['Session (5 hours)', 'Weekly']);
    expect(r.usage!.used, closeTo(.06, 1e-9));
  });

  test('pace: how far through its window it is, unknown without its length', () {
    final w = UsageWindow(
      name: 'Session',
      used: .3,
      resetsAt: reset,
      length: const Duration(hours: 5),
    );
    expect(w.paceAt(reset.subtract(const Duration(hours: 4))), closeTo(.2, 1e-9));
    expect(UsageWindow(name: 'x', used: .3, resetsAt: reset).paceAt(reset), isNull);
    final back = Usage.fromJson(Usage(used: .3, windows: [w]).toJson());
    expect(back.windows.single.length, const Duration(hours: 5));
  });
}
