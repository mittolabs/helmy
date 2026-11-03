import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/codex/codex_reducer.dart';
import 'package:helmy/domain/models/chat_item.dart';

// Shapes copied from codex-cli 0.162.1's app-server output.
Map<String, Object?> note(String method, Map<String, Object?> params) => {
  'method': method,
  'params': params,
};

void main() {
  test('a streamed message, a command that asks first, and the turn end', () {
    final items = <ChatItem>[];
    final r = CodexReducer(items)
      ..apply(
        note('turn/started', {
          'turn': {'id': 't1', 'status': 'inProgress'},
        }),
      )
      ..apply(
        note('item/started', {
          'item': {'type': 'agentMessage', 'id': 'm1', 'text': ''},
        }),
      )
      ..apply(note('item/agentMessage/delta', {'itemId': 'm1', 'delta': 'I'}))
      ..apply(note('item/agentMessage/delta', {'itemId': 'm1', 'delta': 'll do it'}));
    expect(r.turnId, 't1');
    expect((items.single as AssistantText).text, 'Ill do it');
    r
      ..apply(
        note('item/completed', {
          'item': {'type': 'agentMessage', 'id': 'm1', 'text': "I'll do it."},
        }),
      )
      ..apply(
        note('item/started', {
          'item': {
            'type': 'commandExecution',
            'id': 'exec-1',
            'command': "printf hi > hello.txt",
            'cwd': '/w',
            'status': 'inProgress',
          },
        }),
      )
      ..apply({
        'method': 'item/commandExecution/requestApproval',
        'id': 0,
        'params': {'itemId': 'exec-1', 'command': 'printf hi > hello.txt', 'cwd': '/w'},
      });
    expect((items[0] as AssistantText).text, "I'll do it.");
    final call = items[1] as ToolCall;
    final prompt = items[2] as PermissionPrompt;
    expect(call.name, 'Shell');
    expect(call.summary, 'printf hi > hello.txt');
    expect(prompt.requestId, '0');
    expect(prompt.toolUseId, 'exec-1');

    r.apply(
      note('item/completed', {
        'item': {
          'type': 'commandExecution',
          'id': 'exec-1',
          'status': 'completed',
          'aggregatedOutput': '',
          'exitCode': 0,
        },
      }),
    );
    expect(call.done, isTrue);
    expect(call.isError, isFalse);

    r.apply(
      note('account/rateLimits/updated', {
        'rateLimits': {
          'primary': {'usedPercent': 7, 'windowDurationMins': 300},
        },
      }),
    );
    expect(r.usage!.used, closeTo(.07, 1e-9));

    final ended = r.apply(
      note('turn/completed', {
        'turn': {'id': 't1', 'status': 'completed', 'durationMs': 2400, 'error': null},
      }),
    );
    expect(ended, isTrue);
    expect((items.last as TurnSummary).ok, isTrue);
    expect((items.last as TurnSummary).durationMs, 2400);
    expect(r.turnId, isNull);
  });

  test('a failed turn carries its error; an interrupted one is a notice', () {
    final items = <ChatItem>[];
    CodexReducer(items)
      ..apply(
        note('turn/completed', {
          'turn': {
            'status': 'failed',
            'error': {'message': 'Usage limit reached'},
          },
        }),
      )
      ..apply(
        note('turn/completed', {
          'turn': {'status': 'interrupted'},
        }),
      );
    expect((items[0] as TurnSummary).error, 'Usage limit reached');
    expect(items[1], isA<Notice>());
    expect((items[2] as TurnSummary).ok, isTrue);
  });

  test('a question comes in the same shape as Claude asks one', () {
    final items = <ChatItem>[];
    CodexReducer(items).apply({
      'method': 'item/tool/requestUserInput',
      'id': 4,
      'params': {
        'itemId': 'q',
        'questions': [
          {
            'id': 'drink',
            'header': 'Drink',
            'question': 'Tea or coffee?',
            'options': [
              {'label': 'Tea', 'description': ''},
              {'label': 'Coffee', 'description': ''},
            ],
          },
        ],
      },
    });
    final p = items.single as PermissionPrompt;
    expect(p.isQuestion, isTrue);
    expect(p.questions.single['id'], 'drink');
  });
}
