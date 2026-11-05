import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/acp/acp_reducer.dart';
import 'package:helmy/domain/models/chat_item.dart';

/// An ACP agent's updates, as OpenCode 2.2.5 sent them (recorded
/// 2026-11-05), become the chat's items.
void main() {
  Map<String, Object?> update(Map<String, Object?> u) => {
    'method': 'session/update',
    'params': {'sessionId': 's', 'update': u},
  };

  test('thoughts, a step, its result, the answer, and the usage', () {
    final items = <ChatItem>[];
    final r = AcpReducer(items)
      ..apply(
        update({
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': 'Simple'},
        }),
      );
    expect(r.thinking, isTrue);
    r
      ..apply(
        update({
          'sessionUpdate': 'tool_call',
          'toolCallId': 't1',
          'name': 'write',
          'title': 'write',
          'kind': 'edit',
          'status': 'pending',
          'locations': <Object>[],
          'rawInput': <String, Object?>{},
        }),
      )
      ..apply(
        update({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 't1',
          'status': 'completed',
          'locations': [
            {'path': '/w/hello.txt'},
          ],
          'rawInput': {'path': 'hello.txt', 'content': 'hi'},
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': 'Created file successfully: hello.txt'},
            },
          ],
        }),
      )
      ..apply(
        update({
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'm1',
          'content': {'type': 'text', 'text': 'I created '},
        }),
      )
      ..apply(
        update({
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'm1',
          'content': {'type': 'text', 'text': 'hello.txt.'},
        }),
      )
      ..apply(
        update({
          'sessionUpdate': 'usage_update',
          'used': 8361,
          'size': 200000,
          'cost': {'amount': 0, 'currency': 'USD'},
        }),
      )
      ..ended(stopReason: 'end_turn');
    final step = items.whereType<ToolCall>().single;
    expect(
      (step.name, step.summary, step.result),
      ('Edit', '/w/hello.txt', 'Created file successfully: hello.txt'),
    );
    expect(items.whereType<AssistantText>().single.text, 'I created hello.txt.');
    expect(r.context?.used, 8361);
    expect(items.whereType<TurnSummary>().single.ok, isTrue);
    expect(r.thinking, isFalse);
  });

  test('a permission asked is a prompt, with the agent\'s own options kept', () {
    final items = <ChatItem>[];
    AcpReducer(items).apply({
      'id': 7,
      'method': 'session/request_permission',
      'params': {
        'sessionId': 's',
        'toolCall': {
          'toolCallId': 't2',
          'kind': 'execute',
          'rawInput': {'command': 'ls'},
        },
        'options': [
          {'optionId': 'once', 'name': 'Allow once', 'kind': 'allow_once'},
          {'optionId': 'no', 'name': 'Reject', 'kind': 'reject_once'},
        ],
      },
    });
    final p = items.whereType<PermissionPrompt>().single;
    expect((p.requestId, p.toolName, p.input['command']), ('7', 'Bash', 'ls'));
    expect(p.suggestions, hasLength(2));
  });

  test('a plan, then a newer one in its place', () {
    final items = <ChatItem>[];
    final r = AcpReducer(items);
    for (final status in ['pending', 'completed']) {
      r.apply(
        update({
          'sessionUpdate': 'plan',
          'entries': [
            {'content': 'Check', 'priority': 'high', 'status': status},
          ],
        }),
      );
    }
    expect(items.whereType<TaskList>().single.tasks.single.status, TaskStatus.done);
  });
}
