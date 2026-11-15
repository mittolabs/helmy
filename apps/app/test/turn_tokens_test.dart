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

  test('written, and how full the conversation is; nothing unmeasured', () {
    expect(tokensLabel(null, null), isNull);
    expect(tokensLabel(const TurnTokens(), null), isNull);
    expect(
      tokensLabel(
        const TurnTokens(fresh: 210000, cacheRead: 52000000, cacheWrite: 8000, output: 182000),
        const ContextUse(used: 168000, window: 200000),
      ),
      '182k written · conversation 168k of 200k',
    );
    // Before its first answer: how full it is, not a count of nothing.
    expect(
      tokensLabel(null, const ContextUse(used: 41000, window: 1000000)),
      'conversation 41k of 1M',
    );
  });
}
