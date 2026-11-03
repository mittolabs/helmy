import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/claude/claude_reducer.dart';
import 'package:helmy/domain/models/chat_item.dart';

// Shapes copied from claude 2.1.317's stream-json output.
Map<String, Object?> ev(Map<String, Object?> e) => {
  'type': 'stream_event',
  'event': e,
  'parent_tool_use_id': null,
};

void main() {
  test('streams text, then takes the complete block as final', () {
    final items = <ChatItem>[];
    final r = ClaudeReducer(items)
      ..apply({
        'type': 'system',
        'subtype': 'init',
        'session_id': 's1',
        'model': 'claude-haiku-5-5',
      })
      ..apply(
        ev({
          'type': 'message_start',
          'message': {'id': 'm1'},
        }),
      )
      ..apply(
        ev({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        }),
      )
      ..apply(
        ev({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'Hel'},
        }),
      )
      ..apply(
        ev({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'lo'},
        }),
      );
    expect((items.single as AssistantText).text, 'Hello');
    r.apply({
      'type': 'assistant',
      'parent_tool_use_id': null,
      'message': {
        'id': 'm1',
        'content': [
          {'type': 'text', 'text': 'Hello!'},
        ],
      },
    });
    expect(items, hasLength(1));
    expect((items.single as AssistantText).text, 'Hello!');
    expect(r.sessionId, 's1');
  });

  test('tool call, approval request and result line up', () {
    final items = <ChatItem>[];
    final r = ClaudeReducer(items)
      ..apply({
        'type': 'assistant',
        'parent_tool_use_id': null,
        'message': {
          'id': 'm2',
          'content': [
            {
              'type': 'tool_use',
              'id': 't1',
              'name': 'Write',
              'input': {'file_path': '/x/hello.txt', 'content': 'hi'},
            },
          ],
        },
      })
      ..apply({
        'type': 'control_request',
        'request_id': 'r1',
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': 'Write',
          'input': {'file_path': '/x/hello.txt', 'content': 'hi'},
          'permission_suggestions': [
            {'type': 'setMode', 'mode': 'acceptEdits', 'destination': 'session'},
          ],
          'tool_use_id': 't1',
        },
      });
    final call = items[0] as ToolCall;
    final prompt = items[1] as PermissionPrompt;
    expect(call.summary, '/x/hello.txt');
    expect(call.done, isFalse);
    expect(prompt.decision, PermissionDecision.pending);
    expect(prompt.suggestions, hasLength(1));

    r.apply({
      'type': 'user',
      'parent_tool_use_id': null,
      'message': {
        'content': [
          {'type': 'tool_result', 'tool_use_id': 't1', 'content': 'File created'},
        ],
      },
    });
    expect(call.result, 'File created');

    final ended = r.apply({
      'type': 'result',
      'subtype': 'success',
      'is_error': false,
      'session_id': 's1',
      'total_cost_usd': 0.0025,
      'duration_ms': 4640,
    });
    expect(ended, isTrue);
    final turn = items.last as TurnSummary;
    expect(turn.ok, isTrue);
    expect(turn.costUsd, 0.0025);
  });

  test('an interrupt is a notice, not a failure', () {
    final items = <ChatItem>[];
    ClaudeReducer(items)
      ..apply({
        'type': 'user',
        'parent_tool_use_id': null,
        'message': {
          'content': [
            {'type': 'text', 'text': '[Request interrupted by user]'},
          ],
        },
      })
      ..apply({'type': 'result', 'subtype': 'error_during_execution', 'is_error': true});
    expect(items.first, isA<Notice>());
    expect((items.last as TurnSummary).ok, isTrue);
  });

  test('usage is the fuller window', () {
    final r = ClaudeReducer([])
      ..apply({
        'type': 'rate_limit_event',
        'rate_limit_info': {
          'unifiedWindows': {
            'five_hour': {'utilization': 0.16, 'resetsAt': 1793712600},
            'seven_day': {'utilization': 0.04, 'resetsAt': 1794268800},
          },
        },
      });
    expect(r.usage!.used, 0.16);
    expect(r.usage!.resetsAt, DateTime.fromMillisecondsSinceEpoch(1793712600000));
  });

  test("a helper agent's steps go inside the call that started it", () {
    final items = <ChatItem>[];
    ClaudeReducer(items)
      ..apply({
        'type': 'assistant',
        'parent_tool_use_id': null,
        'message': {
          'id': 'm1',
          'content': [
            {
              'type': 'tool_use',
              'id': 'task1',
              'name': 'Agent',
              'input': {'description': 'Look around'},
            },
          ],
        },
      })
      ..apply({
        'type': 'assistant',
        'parent_tool_use_id': 'task1',
        'message': {
          'id': 'm9',
          'content': [
            {'type': 'text', 'text': 'inner'},
            {
              'type': 'tool_use',
              'id': 'c1',
              'name': 'Bash',
              'input': {'command': 'ls'},
            },
          ],
        },
      })
      ..apply({
        'type': 'user',
        'parent_tool_use_id': 'task1',
        'message': {
          'content': [
            {'type': 'tool_result', 'tool_use_id': 'c1', 'content': 'a.txt'},
          ],
        },
      });
    final helper = items.single as ToolCall;
    expect(helper.children.single.name, 'Bash');
    expect(helper.children.single.result, 'a.txt');
    // Its text stays out of the main conversation.
    expect(items.whereType<AssistantText>(), isEmpty);
    // And survives a restart.
    final back = ChatItem.fromJson(helper.toJson()) as ToolCall;
    expect(back.children.single.result, 'a.txt');
  });

  test('items survive a round trip through JSON, pending prompts as cancelled', () {
    final prompt = PermissionPrompt(
      requestId: 'r',
      toolName: 'Bash',
      input: {'command': 'ls'},
      suggestions: const [],
    );
    final back = ChatItem.fromJson(prompt.toJson()) as PermissionPrompt;
    expect(back.decision, PermissionDecision.cancelled);
    final call = ToolCall(id: 't', name: 'Bash', input: {'command': 'ls'})..result = 'a\nb';
    expect((ChatItem.fromJson(call.toJson()) as ToolCall).result, 'a\nb');
  });

  test("a step moved to the background says how it stands, as the agent reports", () {
    final items = <ChatItem>[];
    final r = ClaudeReducer(items)
      ..apply({
        "type": "assistant",
        "message": {
          "id": "m1",
          "content": [
            {
              "type": "tool_use",
              "id": "t1",
              "name": "Bash",
              "input": {"command": "sleep 8; echo finished", "run_in_background": true},
            },
          ],
        },
        "parent_tool_use_id": null,
      })
      ..apply({
        "type": "system",
        "subtype": "task_started",
        "task_id": "b1",
        "tool_use_id": "t1",
        "is_backgrounded": true,
        "task_type": "local_bash",
      })
      ..apply({
        "type": "user",
        "message": {
          "content": [
            {
              "type": "tool_result",
              "tool_use_id": "t1",
              "content": "Command running in background with ID: b1. Output is being written to: /tmp/x/b1.output. You will be notified.",
            },
          ],
        },
        "parent_tool_use_id": null,
      });
    final call = items.whereType<ToolCall>().single;
    expect(call.background!.status, BackgroundStatus.running);

    r
      ..apply({
        "type": "system",
        "subtype": "task_updated",
        "task_id": "b1",
        "patch": {"status": "completed"},
      })
      ..apply({
        "type": "system",
        "subtype": "task_notification",
        "task_id": "b1",
        "tool_use_id": "t1",
        "status": "completed",
        "output_file": "/tmp/x/b1.output",
      });
    expect(call.background!.status, BackgroundStatus.completed);
    expect(call.background!.outputFile, "/tmp/x/b1.output");

    // Saved while running and read back later, it is not claimed to run still.
    call.background!.status = BackgroundStatus.running;
    final back = ChatItem.fromJson(call.toJson()) as ToolCall;
    expect(back.background!.status, BackgroundStatus.unknown);
    expect(BackgroundStatus.of("killed"), BackgroundStatus.stopped);
  });
}
