import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/claude/claude_reducer.dart';
import 'package:helmy/data/services/engines/codex/codex_reducer.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/handoff.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/permission_rule.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/diffs.dart';
import 'package:helmy/utils/project_files.dart';
import 'package:helmy/utils/result.dart';

void main() {
  group('diffs, from either engine', () {
    test("Claude's edit becomes the lines it changed", () {
      final d = diffsOf(
        ToolCall(
          id: 't',
          name: 'Edit',
          input: {
            'file_path': '/w/a.txt',
            'old_string': 'one\ntwo\nthree',
            'new_string': 'one\n2\nthree',
          },
        ),
      ).single;
      expect(d.lines, [' one', '-two', '+2', ' three']);
      expect((d.added, d.removed), (1, 1));
    });

    test("Claude's new file is all added", () {
      final d = diffsOf(
        ToolCall(id: 't', name: 'Write', input: {'file_path': '/w/b.txt', 'content': 'hi\nthere'}),
      ).single;
      expect(d.lines, ['+hi', '+there']);
    });

    test("Codex's unified diff keeps its lines, without the file headers", () {
      final d = diffsOf(
        ToolCall(
          id: 't',
          name: 'Edit',
          input: {
            'changes': [
              {'path': '/w/c.txt', 'diff': '--- a/c.txt\n+++ b/c.txt\n@@ -1 +1 @@\n-old\n+new'},
            ],
          },
        ),
      ).single;
      expect(d.lines, ['@@ -1 +1 @@', '-old', '+new']);
      expect((d.added, d.removed), (1, 1));
    });

    test('a step that changes no file has no diff', () {
      expect(diffsOf(ToolCall(id: 't', name: 'Bash', input: {'command': 'ls'})), isEmpty);
    });
  });

  group('task lists and context, from either engine', () {
    test("Claude's todo list becomes the task list, replaced as it changes", () {
      final items = <ChatItem>[UserMessage('go')];
      final r = ClaudeReducer(items);
      Map<String, Object?> todo(String status) => {
        'type': 'assistant',
        'parent_tool_use_id': null,
        'message': {
          'id': 'm',
          'content': [
            {
              'type': 'tool_use',
              'id': 'x$status',
              'name': 'TodoWrite',
              'input': {
                'todos': [
                  {'content': 'Write it', 'activeForm': 'Writing it', 'status': status},
                ],
              },
            },
          ],
        },
      };
      r.apply(todo('in_progress'));
      r.apply(todo('completed'));
      final lists = items.whereType<TaskList>().toList();
      expect(lists, hasLength(1));
      expect(lists.single.tasks.single.status, TaskStatus.done);
      expect(items.whereType<ToolCall>(), isEmpty);
    });

    test("Claude's context comes from the last request in a result", () {
      final r = ClaudeReducer([])
        ..apply({
          'type': 'result',
          'subtype': 'success',
          'usage': {
            'iterations': [
              {
                'input_tokens': 2,
                'cache_read_input_tokens': 20000,
                'cache_creation_input_tokens': 5000,
              },
            ],
          },
          'modelUsage': {
            'claude-haiku-5-5': {'contextWindow': 1000000},
          },
        });
      expect(r.context!.used, 25002);
      expect(r.context!.window, 1000000);
    });

    test("Codex's plan and token use", () {
      final items = <ChatItem>[UserMessage('go')];
      final r = CodexReducer(items)
        ..apply({
          'method': 'turn/plan/updated',
          'params': {
            'explanation': 'Two steps',
            'plan': [
              {'step': 'Read', 'status': 'completed'},
              {'step': 'Write', 'status': 'inProgress'},
            ],
          },
        })
        ..apply({
          'method': 'thread/tokenUsage/updated',
          'params': {
            'tokenUsage': {
              'last': {'inputTokens': 14878},
              'modelContextWindow': 258400,
            },
          },
        });
      final list = items.whereType<TaskList>().single;
      expect(list.note, 'Two steps');
      expect([for (final t in list.tasks) t.status], [TaskStatus.done, TaskStatus.active]);
      expect(r.context!.used, 14878);
    });
  });

  group('permission rules', () {
    PermissionPrompt ask(String tool, Map<String, Object?> input) =>
        PermissionPrompt(requestId: 'r', toolName: tool, input: input, suggestions: const []);

    test('a command rule is its first word, and covers Codex\'s wrapped commands', () {
      final rule = PermissionRule.from(ask('Bash', {'command': 'git status'}), '/w')!;
      expect(rule.prefix, 'git ');
      expect(rule.allows(ask('Bash', {'command': 'git log -3'})), isTrue);
      expect(rule.allows(ask('Shell', {'command': '/bin/zsh -lc "git diff"'})), isTrue);
      expect(rule.allows(ask('Bash', {'command': 'gitk'})), isFalse);
      expect(rule.allows(ask('Bash', {'command': 'rm -rf /'})), isFalse);
    });

    test('an edit rule covers its folder only', () {
      final rule = PermissionRule.from(ask('Edit', {'file_path': '/w/a.txt'}), '/w')!;
      expect(rule.allows(ask('Write', {'file_path': '/w/sub/b.txt'})), isTrue);
      expect(rule.allows(ask('Write', {'file_path': '/etc/hosts'})), isFalse);
      expect(rule.allows(ask('Bash', {'command': 'ls'})), isFalse);
    });
  });

  test('a command you ran goes across with what it printed', () {
    final text = handoff([
      UserMessage('!ls'),
      ToolCall(id: 'y', name: 'Bash', input: {'command': 'ls', 'by': 'you'})
        ..result = 'a.txt\nb.txt',
    ]);
    expect(text, contains('User ran `ls`, which printed: a.txt\nb.txt'));
  });

  test('@ picks names that start with what was typed first', () {
    final picked = fuzzyPick([
      'lib/main.dart',
      'test/main_test.dart',
      'lib/domain/remain.dart',
    ], 'main');
    expect(picked.first, 'lib/main.dart');
    expect(picked, contains('lib/domain/remain.dart'));
  });

  test('!command runs in the folder, and a message sent meanwhile waits its turn', () async {
    final root = await Directory.systemTemp.createTemp('shell');
    File('${root.path}/here.txt').writeAsStringSync('x');
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
    final running = repo.send(s, '!ls');
    // Sent while the command runs: it waits.
    await repo.send(sessions.byId(s.id)!, 'what is here?');
    expect(repo.of(s.id).queue.single.text, 'what is here?');
    await running;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final items = repo.of(s.id).items;
    final ran = items.whereType<ToolCall>().single;
    expect(ran.input['by'], 'you');
    expect(ran.result, contains('here.txt'));
    // Then the waiting message went (to no engine, in this test).
    expect(items.whereType<UserMessage>().map((m) => m.text), ['!ls', 'what is here?']);
    expect(repo.of(s.id).queue, isEmpty);
    repo.dispose();
    await storage.flush();
    await root.delete(recursive: true);
  });
}
