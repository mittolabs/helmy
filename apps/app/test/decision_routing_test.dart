import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/data/services/engines/decider.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/ollama/ollama_chat_engine.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/memory.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

/// An engine that answers every message with [reply], or (for a plain engine
/// that finds it needs tools) with the needs-tools signal.
class _Engine implements AgentEngine {
  _Engine(this.info, this.reply);
  @override
  final EngineInfo info;
  final String reply;
  bool asksForTools = false;
  String? failure;
  final sent = <String>[];

  /// The folder each run started in.
  final startedIn = <String>[];

  @override
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items) async {
    startedIn.add(launch.cwd);
    return _Run(this, items);
  }

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
  @override
  Future<String?> ask(String instructions, String question) async => null;
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
    scheduleMicrotask(() {
      if (engine.failure case final error?) {
        items
          ..add(AssistantText('limit', error))
          ..add(TurnSummary(ok: false, error: error));
      } else if (engine.asksForTools) {
        items.add(TurnSummary(ok: false, error: needsToolsError));
      } else {
        items
          ..add(AssistantText('${engine.info.id}-${engine.sent.length}', engine.reply))
          ..add(TurnSummary(ok: true));
      }
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
  void compact() {}
  @override
  void stopTask(String taskId) {}
  @override
  void setLevel(PermissionLevel level) {}
  @override
  Future<void> close() => _changes.close();
}

class _Decider implements Decider {
  Decision? next;
  final asked = <({bool route, bool onlyIfLoaded})>[];
  @override
  String get host => '';
  @override
  Future<Decision?> decide(
    String message, {
    required bool route,
    bool onlyIfLoaded = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    asked.add((route: route, onlyIfLoaded: onlyIfLoaded));
    return next;
  }
}

void main() {
  steering();
  moving();
  group('holding', holding);
  late Directory root;
  late SessionRepositoryLocal sessions;
  late StorageService storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('decide');
    storage = storageAt(root);
    sessions = SessionRepositoryLocal(storage);
  });
  tearDown(() async {
    await storage.flush();
    await root.delete(recursive: true);
  });

  Future<(ConversationRepositoryEngines, Session)> make(List<_Engine> engines, _Decider d) async {
    final meter = UsageMeter();
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry(engines),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
      decider: d,
    );
    final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
    repo.of(s.id).loaded = true;
    return (repo, s);
  }

  Future<String> answerTo(ConversationRepositoryEngines repo, Session s, String text) async {
    await repo.send(sessions.byId(s.id)!, text);
    for (var i = 0; i < 50 && repo.of(s.id).busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return repo.of(s.id).items.whereType<AssistantText>().last.text;
  }

  _Engine plain() =>
      _Engine(const EngineInfo(id: 'ollama-chat', name: 'plain', localOnly: true), 'plain answer');
  _Engine localAgent() => _Engine(
    const EngineInfo(
      id: 'ollama',
      name: 'agent',
      localOnly: true,
      capabilities: {Capability.tools},
    ),
    'agent answer',
  );

  test('a limit printed as an answer falls back without asking the person', () async {
    final first = _Engine(
      const EngineInfo(id: 'first', name: 'First', capabilities: {Capability.tools}),
      '',
    )..failure = "You've hit your 5-hour limit · resets 10:40pm (Africa/Nairobi)";
    final next = _Engine(
      const EngineInfo(id: 'next', name: 'Next', capabilities: {Capability.tools}),
      'Done',
    );
    final (repo, session) = await make([first, next], _Decider());
    addTearDown(repo.dispose);
    await repo.send(session, 'change the code');
    await pumpEventQueue();
    expect(first.sent, hasLength(1));
    expect(next.sent, hasLength(1));
    expect(repo.of(session.id).items.whereType<AssistantText>().single.text, 'Done');
    expect(repo.of(session.id).busy, isFalse);
  });

  test('offline, a message sure to need no tools gets a plain answer', () async {
    final d = _Decider()..next = (direct: true, services: <Capability>{});
    final (repo, s) = await make([plain(), localAgent()], d);
    expect(await answerTo(repo, s, 'what does HTTP 429 mean?'), 'plain answer');
    expect(d.asked.single, (route: true, onlyIfLoaded: false));
  });

  test('offline, a message that needs tools, or an unsure one, goes to the agent', () async {
    final d = _Decider()..next = (direct: false, services: <Capability>{});
    final (repo, s) = await make([plain(), localAgent()], d);
    expect(await answerTo(repo, s, 'why is my build failing?'), 'agent answer');
    d.next = null; // the model did not answer: as unsure
    expect(await answerTo(repo, s, 'what is in this folder?'), 'agent answer');
  });

  test('a plain answer that asks for tools hands over, and is not held against it', () async {
    final d = _Decider()..next = (direct: true, services: <Capability>{});
    final p = plain()..asksForTools = true;
    final agent = localAgent();
    final (repo, s) = await make([p, agent], d);
    expect(await answerTo(repo, s, 'what is in this folder?'), 'agent answer');
    expect(p.sent, hasLength(1));
    expect(
      repo.of(s.id).items.whereType<TurnSummary>().where((t) => !t.ok),
      isEmpty,
      reason: 'the hand-over leaves no failure behind',
    );
    // The next plain question still goes to the plain engine.
    p.asksForTools = false;
    expect(await answerTo(repo, s, 'thanks!'), 'plain answer');
  });

  test('online, only services are asked about, and only of a model already loaded', () async {
    final d = _Decider()..next = (direct: false, services: {Capability.gmail});
    final online = _Engine(
      const EngineInfo(id: 'claude', name: 'online', capabilities: {Capability.tools}),
      'online answer',
    );
    final (repo, s) = await make([online, plain(), localAgent()], d);
    expect(await answerTo(repo, s, 'any mail from Sarah?'), 'online answer');
    expect(d.asked.single, (route: false, onlyIfLoaded: true));
  });
}

/// Never finishes a message until it is stopped; answers later ones at once.
class _SlowRun extends _Run {
  _SlowRun(super.engine, super.items);
  var _first = true;

  @override
  void send(String text, {List<String> attachments = const []}) {
    if (_first) {
      _first = false;
      engine.sent.add(text);
      return;
    }
    super.send(text);
  }

  @override
  void interrupt() => scheduleMicrotask(() {
    items
      ..add(Notice('Interrupted'))
      ..add(TurnSummary(ok: true));
    _changes.add(true);
  });
}

class _SlowEngine extends _Engine {
  _SlowEngine(super.info, super.reply, {this.steers = false});
  final bool steers;
  @override
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items) async =>
      steers ? _SteeredRun(this, items) : _SlowRun(this, items);
}

/// A turn that keeps going until a message joins it, then answers that.
class _SteeredRun extends _SlowRun {
  _SteeredRun(super.engine, super.items);
  var interrupted = false;

  @override
  Future<bool> steer(String text, {List<String> attachments = const []}) async {
    engine.sent.add('(joined) $text');
    scheduleMicrotask(() {
      items
        ..add(AssistantText('steered', engine.reply))
        ..add(TurnSummary(ok: true));
      _changes.add(true);
    });
    return true;
  }

  @override
  void interrupt() {
    interrupted = true;
    super.interrupt();
  }
}

void steering() {
  test('sending now redirects: the turn under way stops and the message goes at once', () async {
    final root = await Directory.systemTemp.createTemp('steer');
    final storage = storageAt(root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final engine = _SlowEngine(
      const EngineInfo(id: 'claude', name: 'agent', capabilities: {Capability.tools}),
      'redirected answer',
    );
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry([engine]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
    repo.of(s.id).loaded = true;

    await repo.send(sessions.byId(s.id)!, 'refactor the whole app');
    expect(repo.of(s.id).busy, isTrue);
    await repo.send(sessions.byId(s.id)!, 'stop, just rename one file instead');
    expect(repo.of(s.id).queue, hasLength(1), reason: 'it waits while the agent works');

    repo.steer(s.id, 0);
    for (var i = 0; i < 50 && (repo.of(s.id).busy || repo.of(s.id).queue.isNotEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(engine.sent, ['refactor the whole app', 'stop, just rename one file instead']);
    expect(repo.of(s.id).items.whereType<AssistantText>().last.text, 'redirected answer');
    expect(meter.isDown('claude'), isFalse, reason: 'a stop is not a failure');
    repo.dispose();
    await storage.flush();
    await root.delete(recursive: true);
  });

  test('where the agent can take it, sending now joins the turn under way', () async {
    final root = await Directory.systemTemp.createTemp('steer');
    final storage = storageAt(root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final engine = _SlowEngine(
      const EngineInfo(id: 'claude', name: 'agent', capabilities: {Capability.tools}),
      'renamed it instead',
      steers: true,
    );
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry([engine]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
    repo.of(s.id).loaded = true;

    await repo.send(sessions.byId(s.id)!, 'refactor the whole app');
    await repo.send(sessions.byId(s.id)!, 'stop, just rename one file instead');
    repo.steer(s.id, 0);
    for (var i = 0; i < 50 && (repo.of(s.id).busy || repo.of(s.id).queue.isNotEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final items = repo.of(s.id).items;
    expect(engine.sent, ['refactor the whole app', '(joined) stop, just rename one file instead']);
    expect(items.whereType<Notice>(), isEmpty, reason: 'nothing was stopped');
    expect(items.whereType<UserMessage>().map((m) => m.text), [
      'refactor the whole app',
      'stop, just rename one file instead',
    ]);
    expect(items.whereType<TurnSummary>(), hasLength(1), reason: 'one turn, joined');
    expect(items.whereType<AssistantText>().last.text, 'renamed it instead');
    repo.dispose();
    await storage.flush();
    await root.delete(recursive: true);
  });
}

void moving() {
  test(
    'an answer that ends naming a folder moves the session there, and the line never shows',
    () async {
      final root = await Directory.systemTemp.createTemp('move');
      final there = await Directory('${root.path}/elsewhere').create();
      final storage = storageAt(root);
      final sessions = SessionRepositoryLocal(storage);
      final meter = UsageMeter();
      final engine = _Engine(
        const EngineInfo(id: 'claude', name: 'agent', capabilities: {Capability.tools}),
        "I'm in elsewhere now.\nHELMY_FOLDER: ${there.path}/",
      );
      final repo = ConversationRepositoryEngines(
        engines: EngineRegistry([engine]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
      repo.of(s.id).loaded = true;

      Future<void> settle() async {
        for (var i = 0; i < 100 && repo.of(s.id).busy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }

      await repo.send(sessions.byId(s.id)!, "let's work in elsewhere");
      await settle();
      final moved = sessions.byId(s.id)!;
      expect(moved.cwd, there.path);
      expect(moved.threads, isEmpty, reason: 'every connection starts afresh there');
      final items = repo.of(s.id).items;
      expect(items.whereType<AssistantText>().single.text, "I'm in elsewhere now.");
      expect(items.whereType<Notice>().single.text, contains('elsewhere'));
      expect(items.last, isA<TurnSummary>(), reason: 'the turn still reads as done');

      // The next message runs there.
      await repo.send(sessions.byId(s.id)!, 'list the files');
      await settle();
      expect(engine.startedIn, [root.path, there.path]);

      repo.dispose();
      await storage.flush();
      await root.delete(recursive: true);
    },
  );
}

void holding() {
  Future<
    (
      ConversationRepositoryEngines,
      SessionRepositoryLocal,
      Session,
      _Engine,
      UsageMeter,
      StorageService,
    )
  >
  setUpHeld(String name) async {
    final root = await Directory.systemTemp.createTemp(name);
    final storage = storageAt(root);
    addTearDown(() => deleteFolder(root));
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final engine = _Engine(
      const EngineInfo(id: 'claude', name: 'agent', capabilities: {Capability.tools}),
      'answered once there was room',
    );
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry([engine]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
      holdMargin: Duration.zero,
    );
    addTearDown(repo.dispose);
    final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
    repo.of(s.id).loaded = true;
    return (repo, sessions, s, engine, meter, storage);
  }

  test('at its limit everywhere, a message waits and goes when the limit lifts', () async {
    final (repo, sessions, s, engine, meter, _) = await setUpHeld('held');
    final reset = DateTime.now().add(const Duration(milliseconds: 400));
    meter
      ..report('claude', Usage(used: 1, resetsAt: reset))
      ..markDown('claude');
    await repo.send(sessions.byId(s.id)!, 'sum up the budget');
    final c = repo.of(s.id);
    expect((c.busy, c.heldUntil), (true, reset));
    expect(
      c.items.whereType<Notice>().single.text,
      contains('goes by itself at'),
      reason: 'the reset the connection reported, said as a time',
    );
    // Sent while it waits: after it, in turn.
    await repo.send(sessions.byId(s.id)!, 'and the travel line');
    expect(c.queue, hasLength(1));
    expect(engine.sent, isEmpty);

    for (var i = 0; i < 100 && (c.busy || c.queue.isNotEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(c.heldUntil, isNull);
    expect(engine.sent.map((t) => t.split('\n').last), [
      'sum up the budget',
      'and the travel line',
    ]);
    expect(c.items.whereType<AssistantText>(), hasLength(2));
  });

  test('with no reset said, it says when it tries again; stopping lets it go', () async {
    final (repo, sessions, s, engine, meter, storage) = await setUpHeld('held-unknown');
    meter.markDown('claude');
    await repo.send(sessions.byId(s.id)!, 'sum up the budget');
    final c = repo.of(s.id);
    expect(c.items.whereType<Notice>().single.text, contains('none said when it frees up'));
    expect(c.heldUntil, isNotNull);

    // Helmy closed while it waited: opened again, the conversation says so.
    final again = ConversationRepositoryEngines(
      engines: EngineRegistry([engine]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    addTearDown(again.dispose);
    await storage.flush();
    await again.load(s.id);
    expect(again.of(s.id).items.whereType<Notice>().last.fix, 'retry');

    repo.interrupt(s.id);
    expect((c.busy, c.heldUntil), (false, null));
    expect(c.items.whereType<Notice>().last.text, startsWith('Not sent'));
    expect(engine.sent, isEmpty);
  });
}
