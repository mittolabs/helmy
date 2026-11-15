import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/turn_totals.dart';

/// The Usage page's month: per connection, from the turn log, only what was reported.
void main() {
  test('turns add up per connection; upkeep apart; nothing unreported is counted', () {
    final t = TurnTotals.of([
      {
        'kind': 'turn',
        'connection': 'claude',
        'tokens': {'fresh': 100, 'cacheRead': 9000, 'cacheWrite': 900, 'output': 500},
      },
      {
        'kind': 'turn',
        'connection': 'claude',
        'tokens': {'fresh': 50, 'cacheRead': 1000, 'output': 100},
      },
      {'kind': 'turn', 'connection': 'codex', 'tokens': null},
      {
        'kind': 'upkeep',
        'what': 'judge',
        'tokens': {'fresh': 1200, 'output': 20},
      },
      {'kind': 'filing'},
    ]);
    final claude = t.byConnection['claude']!;
    expect(claude.turns, 2);
    expect(claude.cached, 10000);
    expect(claude.uncached, 150);
    expect(claude.cacheWrites, 900);
    expect(claude.output, 600);
    expect(claude.all, 11650);
    expect(claude.cachedShare, closeTo(10000 / 11050, 1e-9));
    expect(t.byConnection['codex']!.turns, 1);
    expect(t.byConnection['codex']!.cachedShare, isNull, reason: 'nothing reported');
    expect(t.byConnection['codex']!.reported, 0);
    expect(claude.reported, 2);
    expect(t.upkeep.turns, 1);
    expect(t.upkeep.uncached, 1200);
    expect(TurnTotals.of(const []).isEmpty, isTrue);
  });
}
