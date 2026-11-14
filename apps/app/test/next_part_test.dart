import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/approvals.dart';
import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/identity.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/memory.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/domain/next_part.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

/// A connection that answers each message with the next of [replies] (the
/// last one again once they run out), reporting [contextUsed] tokens of
/// conversation, and records how each run was started.
class _Engine implements AgentEngine {
  _Engine(this.replies);
  final List<String> replies;
  var contextUsed = 1000;
  var failNext = false;

  @override
  final info = const EngineInfo(id: 'claude', name: 'agent', capabilities: {Capability.tools});

  final launches = <EngineLaunch>[];
  final sent = <String>[];
  var compacted = 0;

  @override
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items) async {
    launches.add(launch);
    return _Run(this, items);
  }

  @override
  Future<Answer?> ask(String instructions, String question) async => null;
  @override
  Future<List<ModelChoice>> models() async => const [];
  @override
  Future<String?> unavailableReason() async => null;
  @override
  Future<List<MemoryFile>> memoryFiles() async => const [];
  @override
  Future<List<MemoryNote>> memoryNotes() async => const [];
  @override
  Future<List<SlashCommand>> commands(String cwd) async => const [];
  @override
  Future<Usage?> readUsage() async => null;
  @override
  Future<List<({String name, String status})>> servers() async => const [];
  @override
  Future<Set<Capability>> connected() async => const {};
}

class _Run implements EngineRun {
  _Run(this.engine, this.items);
  final _Engine engine;
  final List<ChatItem> items;
  final _changes = StreamController<bool>.broadcast();

  @override
  final status = EngineStatus();
  @override
  Stream<bool> get changes => _changes.stream;
  @override
  String? get exitDetail => null;

  @override
  void send(String text, {List<String> attachments = const []}) {
    engine.sent.add(text);
    final reply = engine.replies[(engine.sent.length - 1).clamp(0, engine.replies.length - 1)];
    scheduleMicrotask(() {
      status
        ..resumeId = 'thread-${engine.launches.length}'
        ..context = ContextUse(used: engine.contextUsed, window: 1000000);
      final failed = engine.failNext;
      engine.failNext = false;
      items
        ..add(AssistantText('a${engine.sent.length}', reply))
        ..add(TurnSummary(ok: !failed, error: failed ? 'it broke' : null));
      _changes.add(true);
    });
  }

  @override
  void compact() {
    engine.compacted++;
    scheduleMicrotask(() {
      items.add(TurnSummary(ok: true));
      _changes.add(true);
    });
  }

  @override
  Future<bool> steer(String text, {List<String> attachments = const []}) async => false;
  @override
  void interrupt() {}
  @override
  void answer(PermissionPrompt prompt, PermissionAnswer answer, {String? why}) {}
  @override
  void answerQuestion(PermissionPrompt prompt) {}
  @override
  void stopTask(String taskId) {}
  @override
  void setLevel(PermissionLevel level) {}
  @override
  Future<void> close() => _changes.close();
}

void main() {
  group('the note', () {
    test('is what follows the last marker, and leaves the answer', () {
      const text =
          'Built the backend.\n\nHELMY_NEXT: Backend done in apps/backend.\nNext: screens.';
      expect(nextPartIn(text), 'Backend done in apps/backend.\nNext: screens.');
      expect(withoutNextPart(text), 'Built the backend.');
      expect(nextPartIn('All done.'), isNull);
      expect(nextPartIn('Done.\nHELMY_NEXT:   '), isNull, reason: 'an empty note starts nothing');
    });

    test('never flashes while it arrives', () {
      expect(withoutNextPart('Built it.\nHELMY_N', streaming: true), 'Built it.');
      expect(withoutNextPart('Built it.\nHELMY_N'), 'Built it.\nHELMY_N');
    });

    test('the agent is told how to end a part, and to read narrowly', () {
      expect(helmyIdentity, contains('HELMY_NEXT:'));
      expect(helmyIdentity, contains('Search first'));
    });

    test("a next part's message is not the person asking", () {
      expect(Approvals.byThePerson(UserMessage('Build Spotly')), isTrue);
      expect(Approvals.byThePerson(UserMessage('push to main')..from = nextPartFrom), isFalse);
    });
  });

  group('parts', () {
    late Directory root;
    late SessionRepositoryLocal sessions;
    late ConversationRepositoryEngines repo;
    final stores = <StorageService>[];

    ConversationRepositoryEngines make(_Engine engine) {
      final storage = storageAt(root);
      stores.add(storage);
      final meter = UsageMeter();
      return ConversationRepositoryEngines(
        engines: EngineRegistry([engine]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
    }

    setUp(() async {
      root = await Directory.systemTemp.createTemp('parts');
      final storage = storageAt(root);
      stores.add(storage);
      sessions = SessionRepositoryLocal(storage);
    });
    tearDown(() async {
      repo.dispose();
      // What is still being saved lands before its folder goes.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (final s in stores) {
        await s.flush();
      }
      stores.clear();
      await root.delete(recursive: true);
    });

    Future<Session> chat() async =>
        (await sessions.create(cwd: root.path, title: 'Build it') as Ok).value as Session;

    Future<void> until(bool Function() done, {int tries = 1000}) async {
      for (var i = 0; i < tries && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(done(), isTrue);
    }

    test('a part ends with a note, and the next starts from it in a fresh context', () async {
      final engine = _Engine([
        'Backend built and tested.\n\nHELMY_NEXT: The backend is in apps/backend and its tests '
            'pass. Next: the explore screen, checked in the browser.',
        'Explore screen built. All done.',
      ]);
      repo = make(engine);
      final s = await chat();
      await repo.send(s, 'Build Spotly on our stack');
      await until(() => engine.sent.length == 2 && !repo.of(s.id).busy);

      // The second part started a new thread, not the first one's.
      expect(engine.launches.map((l) => l.resumeId), [null, null]);
      expect(engine.sent.last, contains('The backend is in apps/backend'));
      // It was not handed the conversation again: only the note.
      expect(engine.sent.last, isNot(contains('Build Spotly on our stack')));

      final items = repo.of(s.id).items;
      // The note left the answer, and the person sees where the part ended.
      expect(items.whereType<AssistantText>().first.text, 'Backend built and tested.');
      expect(items.whereType<Notice>().single.text, startsWith('Part done.'));
      expect(items.whereType<UserMessage>().last.from, nextPartFrom);
      // The finished part ends there: no third.
      expect(engine.sent, hasLength(2));
    });

    test('a failed part, or a message from the person, stops it going on by itself', () async {
      final engine = _Engine(['Half built.\nHELMY_NEXT: Next: the rest.'])..failNext = true;
      repo = make(engine);
      final s = await chat();
      await repo.send(s, 'Build it');
      await until(() => !repo.of(s.id).busy && engine.sent.length == 1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(engine.sent, hasLength(1), reason: 'a failed part does not start another');
    });

    test('after many parts in a row, it waits for the person', () async {
      final engine = _Engine(['A part.\nHELMY_NEXT: Next: another part.']);
      repo = make(engine);
      final s = await chat();
      await repo.send(s, 'Build it');
      await until(
        () => repo.of(s.id).items.whereType<Notice>().any((n) => n.text.contains('in a row')),
        // Twenty-one parts, each saved to disk: slow on a busy machine.
        tries: 6000,
      );
      expect(engine.sent, hasLength(ConversationRepositoryEngines.partsInARow + 1));
    });

    test('a conversation grown large is compacted between turns', () async {
      final engine = _Engine(['Done.'])..contextUsed = ConversationRepositoryEngines.compactAt;
      repo = make(engine);
      final s = await chat();
      await repo.send(s, 'Build it');
      await until(() => engine.compacted == 1 && !repo.of(s.id).busy);

      final small = _Engine(['Done.']);
      repo.dispose();
      repo = make(small);
      final t = await chat();
      await repo.send(t, 'A small thing');
      await until(() => !repo.of(t.id).busy && small.sent.length == 1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(small.compacted, 0);
    });
  });
}
