import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/acp/acp_reducer.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/utils/diffs.dart';

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

  test('a file written or edited shows as a change, not as its raw input', () {
    final written = ToolCall(
      id: 'w',
      name: AcpReducer.nameOf({'kind': 'edit'}),
      input: AcpReducer.inputOf({
        'kind': 'edit',
        'rawInput': {'filePath': '/tmp/song.py', 'content': 'a\nb'},
      }),
    );
    expect(diffsOf(written).single.added, 2);
    expect(diffsOf(written).single.path, '/tmp/song.py');
    final edited = ToolCall(
      id: 'e',
      name: 'Edit',
      input: AcpReducer.inputOf({
        'kind': 'edit',
        'rawInput': {'filePath': '/tmp/song.py'},
        'content': [
          {'type': 'diff', 'path': '/tmp/song.py', 'oldText': 'a\nb', 'newText': 'a\nc'},
        ],
      }),
    );
    final d = diffsOf(edited).single;
    expect((d.added, d.removed), (1, 1));
  });

  test('a shell step titled with its command reads as what it does, not the command', () {
    final items = <ChatItem>[];
    AcpReducer(items).apply(
      update({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'b1',
        'name': 'bash',
        'title': 'which flutter && flutter --version 2>/dev/null | head -3',
        'kind': 'execute',
        'status': 'pending',
        'rawInput': {'command': 'which flutter && flutter --version 2>/dev/null | head -3'},
      }),
    );
    final call = items.single as ToolCall;
    expect(call.input['description'], isNull, reason: 'the title is only the command again');
    final described = <ChatItem>[];
    AcpReducer(described).apply(
      update({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'b2',
        'name': 'bash',
        'title': 'ls -la',
        'kind': 'execute',
        'status': 'pending',
        'rawInput': {'command': 'ls -la', 'description': 'List the project folder'},
      }),
    );
    expect((described.single as ToolCall).input['description'], 'List the project folder');
  });

  test('a question asked as a form shows as a question, and its answers go back in its fields', () {
    final items = <ChatItem>[];
    // As OpenCode 2.2 builds it: a field with choices, its "other" field, and a yes or no.
    AcpReducer(items).apply({
      'jsonrpc': '2.0',
      'id': 7,
      'method': 'elicitation/create',
      'params': {
        'mode': 'form',
        'sessionId': 's',
        'message': 'Two quick decisions',
        'requestedSchema': {
          'type': 'object',
          'properties': {
            'platform': {
              'type': 'string',
              'title': 'Where should it run?',
              'oneOf': [
                {
                  'const': 'ios',
                  'title': 'iOS simulator',
                  'description': 'Watch it in the Device panel',
                },
                {'const': 'macos', 'title': 'macOS'},
              ],
            },
            'platform_custom': {'type': 'string', 'title': 'Where should it run? (other)'},
            'sound': {'type': 'boolean', 'title': 'With sound?'},
          },
          'required': ['platform'],
        },
      },
    });
    final p = items.single as PermissionPrompt;
    expect(p.isQuestion, isTrue);
    expect(p.questions.map((q) => q['question']), ['Where should it run?', 'With sound?']);
    expect((p.questions.first['options']! as List).map((o) => (o as Map)['label']), [
      'iOS simulator',
      'macOS',
    ]);
    p.answers['Where should it run?'] = 'macOS';
    p.answers['With sound?'] = 'No';
    expect(AcpReducer.formAnswers(p), {'platform': 'macos', 'sound': false});
    p.answers['Where should it run?'] = 'Android emulator';
    expect(AcpReducer.formAnswers(p)['platform_custom'], 'Android emulator');
  });

  test('a command the agent moved to its own background is known as background work', () {
    const said =
        'Command moved to the background (shell ID: sh_1cf5c453c001bFWi8azl9rzohV).\n'
        'Output is streaming to: /Users/sam/.local/share/opencode/shell/7dd1/sh_1cf5c453c001bFWi8azl9rzohV.out\n'
        'You will be notified automatically when the command finishes.';
    final (id, file) = AcpReducer.backgroundIn(said)!;
    expect(id, 'sh_1cf5c453c001bFWi8azl9rzohV');
    expect(file, '/Users/sam/.local/share/opencode/shell/7dd1/sh_1cf5c453c001bFWi8azl9rzohV.out');
    expect(AcpReducer.backgroundIn('No issues found!'), isNull);
    final items = <ChatItem>[];
    AcpReducer(items)
      ..apply(
        update({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'r1',
          'kind': 'execute',
          'status': 'pending',
          'rawInput': {'command': 'flutter run -d ios'},
        }),
      )
      ..apply(
        update({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'r1',
          'status': 'completed',
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': said},
            },
          ],
        }),
      );
    final call = items.single as ToolCall;
    expect(call.background?.status, BackgroundStatus.running);
    expect(call.background?.outputFile, endsWith('.out'));
  });

  test('a question as OpenCode 2.2.7 really asks it: the question, its label above', () {
    final items = <ChatItem>[];
    // Recorded 2026-11-12 from OpenCode over ACP.
    AcpReducer(items).apply({
      'id': 3,
      'method': 'elicitation/create',
      'params': {
        'mode': 'form',
        'sessionId': 'ses',
        'message': 'Questions',
        'requestedSchema': {
          'type': 'object',
          'properties': {
            'q0': {
              'type': 'string',
              'title': 'Button color',
              'description': 'Which color should the button be?',
              'oneOf': [
                {'const': 'Red', 'title': 'Red', 'description': 'Make the button red.'},
                {'const': 'Blue', 'title': 'Blue', 'description': 'Make the button blue.'},
              ],
            },
            'q0_custom': {
              'type': 'string',
              'title': 'Button color (other)',
              'description': 'Type your own answer',
            },
          },
          'required': <Object>[],
        },
      },
    });
    final p = items.single as PermissionPrompt;
    expect(p.questions.single['question'], 'Which color should the button be?');
    expect(p.questions.single['header'], 'Button color');
    p.answers['Which color should the button be?'] = 'Blue';
    expect(AcpReducer.formAnswers(p), {'q0': 'Blue'});
  });
}
