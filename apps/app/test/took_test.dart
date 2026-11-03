import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/claude/claude_reducer.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/ui/chat/widgets/chat_items.dart';

void main() {
  test('how long an answer took reads as a person says it', () {
    expect(tookLabel(const Duration(milliseconds: 400)), 'under a second');
    expect(tookLabel(const Duration(seconds: 12)), '12s');
    expect(tookLabel(const Duration(seconds: 60)), '1m');
    expect(tookLabel(const Duration(seconds: 65)), '1m 5s');
    expect(tookLabel(const Duration(hours: 1, minutes: 2, seconds: 9)), '1h 2m');
    expect(fullTime(DateTime(2026, 11, 3, 22, 42, 5)), 'Tue, Nov 3, 2026 at 10:42:05 PM');
    expect(fullTime(DateTime(2026, 11, 4, 0, 7, 0)), 'Wed, Nov 4, 2026 at 12:07:00 AM');
  });

  test('when a message went and its answer finished are kept, and unknown stays unknown', () {
    final sent = UserMessage('hello')..sentAt = DateTime(2026, 11, 3, 22, 42, 5);
    expect((ChatItem.fromJson(sent.toJson()) as UserMessage).sentAt, sent.sentAt);
    expect((ChatItem.fromJson(UserMessage('old').toJson()) as UserMessage).sentAt, isNull);

    final items = <ChatItem>[];
    final before = DateTime.now();
    ClaudeReducer(items).apply({'type': 'result', 'subtype': 'success', 'session_id': 's'});
    final summary = items.whereType<TurnSummary>().single;
    expect(summary.endedAt!.isBefore(before), isFalse);
    expect((ChatItem.fromJson(summary.toJson()) as TurnSummary).endedAt, summary.endedAt);
    expect((ChatItem.fromJson(TurnSummary(ok: true).toJson()) as TurnSummary).endedAt, isNull);
  });
}
