import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/models/settings.dart';

void main() {
  test('a connection turned off gets no messages, and is still listed', () {
    const s = AppSettings(pausedEngines: {'claude'}, disabledEngines: {'codex'});
    expect(s.uses('claude'), isFalse, reason: 'turned off');
    expect(s.uses('codex'), isFalse, reason: 'removed');
    expect(s.uses('acp.opencode'), isTrue);
    final back = AppSettings.fromJson(s.toJson());
    expect(back.pausedEngines, {'claude'});
    expect(back.disabledEngines, {'codex'}, reason: 'off is not removed');
  });
}
