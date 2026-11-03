import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';
import 'package:helmy/utils/transcript_markdown.dart';

void main() {
  final items = <ChatItem>[
    UserMessage('List the files'),
    ToolCall(id: 't', name: 'Bash', input: {'command': 'ls'})..result = 'a\nb',
    AssistantText('1', 'There are two.'),
    AssistantText('2', 'a and b.'),
    TurnSummary(ok: true),
    UserMessage('Thanks'),
    AssistantText('3', 'Welcome.'),
  ];

  test('the conversation as Markdown has what was said and one line per step', () {
    final md = transcriptMarkdown('Files', items);
    expect(md, startsWith('# Files'));
    expect(md, contains('**You:**\n\nList the files'));
    expect(md, contains('> Bash: ls'));
    expect(md, contains('There are two.'));
    expect(md, isNot(contains('a\nb')));
  });

  test('an answer is every reply up to the next message', () {
    expect(answerText(items, 0), 'There are two.\n\na and b.');
    expect(answerText(items, 5), 'Welcome.');
  });

  test('editing keeps what came after as a version, and switching brings it back', () async {
    final root = await Directory.systemTemp.createTemp('rewind');
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
    final created = (await sessions.create(cwd: root.path) as Ok).value as Session;
    await sessions.save(
      created.copyWith(threads: {'claude': const EngineThread(resumeId: 'x', seen: 7)}),
    );
    repo.of(created.id)
      ..loaded = true
      ..items.addAll(items);

    await repo.rewind(sessions.byId(created.id)!, 5, 'Thanks a lot');
    final now = repo.of(created.id).items;
    expect(now.take(5), items.take(5));
    expect((now[5] as UserMessage).text, 'Thanks a lot');
    // No engine in this test: the message is sent and finds nobody to answer.
    expect(now.last, isA<Notice>());
    expect(sessions.byId(created.id)!.threads, isEmpty);

    // The old version is kept, and the edited message knows of both.
    final edited = now[5] as UserMessage;
    expect(edited.branches!.length, 2);
    expect(edited.branches!.active, 1);

    // Back to the first version: the conversation is as it was.
    await sessions.save(
      sessions.byId(created.id)!.copyWith(threads: {'claude': const EngineThread(seen: 9)}),
    );
    expect(await repo.showBranch(sessions.byId(created.id)!, 5, 0), isA<Ok<void>>());
    final back = repo.of(created.id).items;
    expect(
      [for (final i in back.take(7)) (i is UserMessage ? i.text : i.runtimeType)],
      [
        'List the files',
        ToolCall,
        AssistantText,
        AssistantText,
        TurnSummary,
        'Thanks',
        AssistantText,
      ],
    );
    expect(back.length, items.length);
    final first = back[5] as UserMessage;
    expect(first.branches!.active, 0);
    expect(edited.branches, isNull, reason: 'only the message showing holds the versions');
    expect(sessions.byId(created.id)!.threads, isEmpty, reason: 'engines are handed this version');

    // A third version from the same message, and everything survives saving.
    await repo.rewind(sessions.byId(created.id)!, 5, 'Cheers');
    final third = repo.of(created.id).items[5] as UserMessage;
    expect(third.branches!.length, 3);
    final reloaded = ChatItem.fromJson(third.toJson()) as UserMessage;
    expect(reloaded.branches!.length, 3);
    expect(reloaded.branches!.active, 2);
    expect(
      [for (final t in reloaded.branches!.tails) (t?.first as UserMessage?)?.text],
      ['Thanks', 'Thanks a lot', null],
    );
    expect(await repo.showBranch(sessions.byId(created.id)!, 5, 9), isA<Error<void>>());

    expect((await repo.rewind(sessions.byId(created.id)!, 2, 'x')) is Error, isTrue);
    repo.dispose();
    await storage.flush();
    await root.delete(recursive: true);
  });
}
