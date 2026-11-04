import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/chat_tools.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/helmy_tools.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/data/services/turn_log.dart';
import 'package:helmy/data/services/watch_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

void main() {
  test(
    "an agent looks into its chat's other threads, cheapest first, each lookup logged",
    () async {
      final root = await Directory.systemTemp.createTemp('chattools');
      final storage = StorageService(root: () async => root);
      // Saves on their way land before the folder goes.
      addTearDown(() async {
        await storage.flush();
        await root.delete(recursive: true);
      });
      final sessions = SessionRepositoryLocal(storage);
      final chats = ChatRepository(storage, sessions);
      addTearDown(chats.dispose);
      await chats.load();
      final meter = UsageMeter();
      final repo = ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      final log = TurnLog(appData: () async => root, now: () => DateTime.utc(2026, 11, 4));
      final design =
          (await sessions.create(cwd: '/w', title: 'Design the onboarding') as Ok).value as Session;
      final chatId = sessions.byId(design.id)!.chatId!;
      await sessions.save(
        sessions.byId(design.id)!.copyWith(summary: 'Three screens, skip button agreed'),
      );
      repo.of(design.id)
        ..loaded = true
        ..items.addAll([
          UserMessage('Should onboarding have a skip button?'),
          AssistantText('a:0', 'Yes: a skip button on every screen, and the invite code last.'),
        ]);
      final build =
          (await sessions.create(cwd: '/w', title: 'Build it', chatId: chatId) as Ok).value
              as Session;
      final tools = HelmyTools(WatchService(CliLocator()))
        ..chats = ChatTools(sessions: sessions, chats: chats, conversations: repo, log: log);

      Future<String> call(String name, Map args) async {
        final r = await tools.answer('tools/call', {
          'name': name,
          'arguments': args,
        }, session: build.id);
        return ((r['result']! as Map)['content'] as List).first['text'] as String;
      }

      final listed = await tools.answer('tools/list', const {});
      expect([
        for (final t in (listed['result']! as Map)['tools'] as List) t['name'],
      ], containsAll(ChatTools.names));
      expect(HelmyTools.claudeTools, contains('mcp__helmy__chat_thread'));

      final list = await call('chat_threads', const {});
      expect(list, contains('Design the onboarding'));
      expect(list, contains('Three screens, skip button agreed'));
      expect(list, isNot(contains('Build it')), reason: 'not itself');

      final found = await call('chat_thread', {'id': design.id, 'find': 'skip button'});
      expect(found, contains('a skip button on every screen'));
      final whole = await call('chat_thread', {'id': design.id});
      expect(whole, contains('Should onboarding have a skip button?'));
      expect(await call('chat_thread', {'id': 'nope'}), contains('No thread'));

      final rungs = [
        for (final l in await log.read('2026-11'))
          if (l['kind'] == 'lookup') l['rung'],
      ];
      expect(rungs, ['summaries', 'thread-find', 'thread']);
    },
  );

  test('an agent messages another thread, or starts one, labelled, and not without end', () async {
    final root = await Directory.systemTemp.createTemp('chatsend');
    final storage = storageAt(root);
    addTearDown(() => deleteFolder(root));
    final sessions = SessionRepositoryLocal(storage);
    final chats = ChatRepository(storage, sessions);
    addTearDown(chats.dispose);
    await chats.load();
    final meter = UsageMeter();
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    final design =
        (await sessions.create(cwd: '/w', title: 'Design the onboarding') as Ok).value as Session;
    final chatId = sessions.byId(design.id)!.chatId!;
    final build =
        (await sessions.create(cwd: '/w', title: 'Build it', chatId: chatId) as Ok).value
            as Session;
    repo.of(design.id).loaded = true;
    var now = DateTime(2026, 11, 5, 9);
    final tools = ChatTools(sessions: sessions, chats: chats, conversations: repo, now: () => now);
    String text(Map r) => ((r['content'] as List).first as Map)['text'] as String;

    final sent = await tools.call('chat_message', {
      'id': design.id,
      'message': 'Is the skip button on the last screen too?',
    }, build.id);
    expect(sent['isError'], isFalse, reason: text(sent));
    final arrived = repo.of(design.id).items.whereType<UserMessage>().single;
    expect(
      (arrived.text, arrived.from),
      ('Is the skip button on the last screen too?', 'Build it'),
    );

    expect(
      text(await tools.call('chat_message', {'id': build.id, 'message': 'hi'}, build.id)),
      'That is this thread.',
    );
    // A shell command from another agent is a message, never run.
    await tools.call('chat_message', {'id': design.id, 'message': '!rm -rf build'}, build.id);
    expect(repo.of(design.id).items.whereType<UserMessage>().last.text, '!rm -rf build');

    // Held to five to one thread in ten minutes; then room again.
    for (var i = 0; i < 3; i++) {
      await tools.call('chat_message', {'id': design.id, 'message': 'and $i'}, build.id);
    }
    final sixth = await tools.call('chat_message', {'id': design.id, 'message': 'more'}, build.id);
    expect(sixth['isError'], isTrue);
    expect(text(sixth), contains('Wait for its answer'));
    now = now.add(const Duration(minutes: 11));
    expect(
      (await tools.call('chat_message', {'id': design.id, 'message': 'more'}, build.id))['isError'],
      isFalse,
    );

    // A new thread beside this one, in the same chat and folder.
    final started = await tools.call('chat_start', {
      'title': 'Write the copy',
      'message': 'Write the words for the three onboarding screens.',
    }, build.id);
    expect(started['isError'], isFalse, reason: text(started));
    final copy = sessions.sessions.firstWhere((s) => s.title == 'Write the copy');
    expect((copy.chatId, copy.cwd), (chatId, '/w'));
    expect(repo.of(copy.id).items.whereType<UserMessage>().single.from, 'Build it');
  });
}
