import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/ui/chat/widgets/chat_screen.dart' show tokensLabel;
import 'package:helmy/utils/format.dart';

/// The working turn's tokens beside "Working": what was written, and every
/// token gone through, short; nothing until a connection has measured.
void main() {
  test('counts read short', () {
    expect(shortCount(950), '950');
    expect(shortCount(1234), '1.2k');
    expect(shortCount(1000), '1k');
    expect(shortCount(182400), '182k');
    expect(shortCount(999600), '1M');
    expect(shortCount(52400000), '52M');
    expect(shortCount(5240000), '5.2M');
  });

  test('written, and in all; nothing unmeasured', () {
    expect(tokensLabel(null), isNull);
    expect(tokensLabel(const TurnTokens()), isNull);
    expect(
      tokensLabel(
        const TurnTokens(fresh: 210000, cacheRead: 52000000, cacheWrite: 8000, output: 182000),
      ),
      '182k written · 52M in all',
    );
    // A connection that gives no written count: only the total.
    expect(tokensLabel(const TurnTokens(fresh: 900, cacheRead: 100)), '1k in all');
  });
}
