@Tags(['live'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/ollama/ollama_chat_engine.dart';
import 'package:helmy/data/services/engines/decider.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/data/services/engines/claude/claude_engine.dart';
import 'package:helmy/data/services/engines/codex/codex_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/memory.dart';
import 'package:helmy/domain/models/permission_rule.dart';
import 'package:helmy/utils/result.dart';

/// Drives the real CLIs through the repository, the way the app does. Spends a
/// few cents. Run with: fvm flutter test --tags live --run-skipped
void main() {
  final locator = CliLocator();
  final claude = ClaudeEngine(locator), codex = CodexEngine(locator);

  for (final engine in [claude, codex]) {
    test('${engine.info.name}: approved write, then a resumed turn', () async {
      final h = await _Live.make([engine], _Scripted([engine.info.id]));
      await h.say(
        'Create a file named hello.txt in the current directory whose only content is '
        'the two letters h and i. Then reply "done".',
      );
      expect(File('${h.work.path}/hello.txt').readAsStringSync().trim(), 'hi');
      expect(h.items.whereType<ToolCall>(), isNotEmpty);
      expect((h.items.last as TurnSummary).ok, isTrue);
      expect(h.session.threads[engine.info.id]?.resumeId, isNotNull);

      // A new process must pick the thread up again.
      await h.repo.stop(h.id);
      await h.say('What file did you just create? Reply with only its name.');
      expect(h.items.whereType<AssistantText>().last.text, contains('hello.txt'));
      await h.close();
    }, timeout: const Timeout(Duration(minutes: 8)));
  }

  for (final engine in [claude, codex]) {
    test('${engine.info.name}: sees an attached picture', () async {
      final h = await _Live.make([engine], _Scripted([engine.info.id]));
      await h.say('What animal is in this picture? Reply with one word.', attachments: [_cat]);
      expect(h.items.whereType<AssistantText>().last.text.toLowerCase(), contains('cat'));
      await h.close();
    }, timeout: const Timeout(Duration(minutes: 4)));
  }

  test('a conversation handed from Claude Code to Codex keeps its thread', () async {
    final h = await _Live.make([claude, codex], _Scripted(['claude', 'codex']));
    await h.say('Remember this code word for later: PERIWINKLE. Reply only "noted".');
    await h.say('What was the code word I gave you? Reply with only the word.');
    expect(h.session.threads.keys, containsAll(['claude', 'codex']));
    expect(h.session.lastEngineId, 'codex');
    expect(h.items.whereType<AssistantText>().last.text.toUpperCase(), contains('PERIWINKLE'));
    await h.close();
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('an image request detours to Codex, then the session is back on Claude', () async {
    final h = await _Live.make([claude, codex], HeadroomRouter(UsageMeter()));
    await h.say('Reply with only the word: ready');
    expect(h.session.lastEngineId, 'claude');
    await h.say('generate an image of a small flat cartoon cat face');
    final image = h.items.whereType<ImageItem>().single;
    expect(File(image.path).existsSync(), isTrue);
    expect(h.session.threads.keys, contains('codex'));
    expect(h.session.lastEngineId, 'claude', reason: 'a detour does not move the session');
    await h.say('What is the file path of the image that was just made? Reply with only the path.');
    expect(h.items.whereType<AssistantText>().last.text, contains(image.path.split('/').last));
    expect(h.session.lastEngineId, 'claude');
    await h.close();
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('Refine sends a change to an image to Codex, though the words never say image', () async {
    final h = await _Live.make([claude, codex], HeadroomRouter(UsageMeter()));
    await h.say('Reply with only the word: ready');
    expect(h.session.lastEngineId, 'claude');
    // What the Refine button sends: the picture, and a need the words do not show.
    await h.say(
      'make the background solid blue',
      attachments: [_cat],
      needs: {Capability.imageGeneration},
    );
    final made = h.items.whereType<ImageItem>().single;
    expect(File(made.path).existsSync(), isTrue);
    expect(made.path, isNot(_cat));
    expect(h.session.lastEngineId, 'claude', reason: 'a detour does not move the session');
    await h.close();
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('both engines list their slash commands, without sending anything', () async {
    final cwd = Directory.systemTemp.path;
    final fromClaude = await claude.commands(cwd);
    final fromCodex = await codex.commands(cwd);
    // ignore: avoid_print
    print(
      'claude ${fromClaude.length}: ${fromClaude.take(5).map((c) => c.name)}; codex ${fromCodex.length}: ${fromCodex.take(5).map((c) => c.name)}',
    );
    expect(fromClaude, isNotEmpty);
    expect(fromCodex, isNotEmpty);
    expect(fromCodex.every((c) => c.path != null), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  for (final engine in [claude, codex]) {
    test('${engine.info.name}: compacts the conversation and goes on', () async {
      final h = await _Live.make([engine], _Scripted([engine.info.id]));
      await h.say('Remember the word TANGERINE. Reply only "ok".');
      final c = h.repo.of(h.id);
      final before = c.context;
      expect(before, isNotNull, reason: 'context is reported');
      final done = Completer<void>();
      void check() {
        if (!c.busy && !done.isCompleted) done.complete();
      }

      h.repo.addListener(check);
      await h.repo.compact(h.session);
      await done.future.timeout(const Duration(minutes: 3));
      h.repo.removeListener(check);
      // ignore: avoid_print
      print('${engine.info.name} context before ${before!.used}, after ${c.context?.used}');
      await h.say('What word did I ask you to remember? Reply with only the word.');
      expect(h.items.whereType<AssistantText>().last.text.toUpperCase(), contains('TANGERINE'));
      await h.close();
    }, timeout: const Timeout(Duration(minutes: 8)));
  }

  test('Claude Code in plan mode asks to approve its plan, then goes ahead', () async {
    final h = await _Live.make([claude], _Scripted(['claude']), level: .readOnly);
    await h.say(
      'Plan how to create hello.txt containing the two letters h and i, then do it once approved.',
    );
    final plan = h.items.whereType<ToolCall>().where((c) => c.name == 'ExitPlanMode').firstOrNull;
    expect(plan, isNotNull, reason: 'a plan was put up for approval');
    expect('${plan!.input['plan']}', contains('hello.txt'));
    await h.close();
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a message sent while the agent works waits, then goes', () async {
    final h = await _Live.make([claude], _Scripted(['claude']));
    await h.say(
      'Count slowly from 1 to 5, one number per line.',
      alsoSend: 'Now reply with only the word: second',
    );
    final asks = h.items.whereType<UserMessage>().map((m) => m.text).toList();
    expect(asks, hasLength(2));
    expect(h.items.whereType<AssistantText>().last.text.toLowerCase(), contains('second'));
    await h.close();
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('a rule answers a real approval without asking', () async {
    final h = await _Live.make(
      [codex],
      _Scripted(['codex']),
      rules: const [PermissionRule(kind: 'command', prefix: 'touch ')],
    );
    await h.say('Run exactly this shell command: touch ruled.txt', allow: false);
    expect(File('${h.work.path}/ruled.txt').existsSync(), isTrue);
    expect(
      h.items.whereType<PermissionPrompt>().map((p) => p.decision),
      everyElement(PermissionDecision.allowedByRule),
    );
    await h.close();
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('Codex says its usage without a message being sent', () async {
    final u = await codex.readUsage();
    expect(u, isNotNull);
    expect(u!.used, inInclusiveRange(0, 1));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('each Claude account says which services it is connected to, without a message', () async {
    for (final account in ClaudeEngine.discover(locator, Platform.environment['HOME']!)) {
      final set = await account.connected();
      // ignore: avoid_print
      print('${account.info.id}: ${set.map((c) => c.label)}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test("a helper agent's steps show inside the step that started it", () async {
    final h = await _Live.make([claude], _Scripted(['claude']));
    File('${h.work.path}/one.txt').writeAsStringSync('x');
    await h.say(
      'Use one helper agent (the Agent tool) to list the files in this folder with Bash, '
      'then tell me what it found. I approve the cost of that one helper: a single small '
      'agent, a few thousand tokens. Tell it not to start agents of its own.',
    );
    final helpers = h.items.whereType<ToolCall>().where(
      (c) => c.name == 'Agent' || c.name == 'Task',
    );
    expect(helpers, isNotEmpty, reason: 'a helper was used');
    expect(helpers.first.children, isNotEmpty, reason: 'its steps were filed under it');
    // ignore: avoid_print
    print('helper steps: ${helpers.first.children.map((c) => c.name)}');
    await h.close();
  }, timeout: const Timeout(Duration(minutes: 5)));

  test(
    'background work shows on its step, and the turn the agent begins afterwards is followed',
    () async {
      final h = await _Live.make([claude], _Scripted(['claude']));
      await h.say(
        "Run 'sleep 6; echo finished' with Bash in the background (run_in_background true). "
        "Then just say 'started' and end your turn without checking on it.",
      );
      final call = h.items.whereType<ToolCall>().firstWhere((c) => c.background != null);
      expect(call.background!.status, BackgroundStatus.running);
      expect(h.repo.of(h.id).busy, isFalse, reason: 'the first turn has ended');

      // The task ends; the agent takes it up by itself, and the session follows.
      var sawBusy = false;
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(deadline)) {
        if (h.repo.of(h.id).busy) sawBusy = true;
        if (sawBusy && !h.repo.of(h.id).busy) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(sawBusy, isTrue, reason: 'the unasked turn showed as working');
      expect(call.background!.status, BackgroundStatus.completed);
      expect(h.items.whereType<TurnSummary>().length, 2);
      await h.storage.flush();
      final saved = File('${h.root.path}/transcripts/${h.id}.json').readAsStringSync();
      expect(saved, contains('"status":"completed"'), reason: 'the unasked turn was saved');
      await h.close();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test('a command is explained in plain words outside the conversation, and kept', () async {
    final h = await _Live.make([claude], _Scripted(['claude']));
    final call = ToolCall(
      id: 'x',
      name: 'Bash',
      input: {'command': "head -20 'My Notes.md' | grep -n todo"},
    );
    h.repo.of(h.id).items.add(call);
    final before = h.repo.of(h.id).items.length;
    final r = await h.repo.explain(h.id, call);
    expect(r, isA<Ok<String>>());
    expect(call.explanation, contains('grep'));
    expect(h.repo.of(h.id).items.length, before, reason: 'nothing added to the conversation');
    await h.storage.flush();
    final saved = File('${h.root.path}/transcripts/${h.id}.json').readAsStringSync();
    expect(saved, contains('"explanation"'));
    await h.close();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the local engine answers with nothing online, on a model on this Mac', () async {
    final local = CodexEngine.local(
      locator,
      model: () => Platform.environment['HELMY_LOCAL_MODEL'],
    );
    expect(await local.unavailableReason(), isNull, reason: 'Ollama is up with a model');
    final h = await _Live.make([local], _Scripted(['ollama']));
    await h.say('Reply with exactly the word: pong');
    final text = h.items.whereType<AssistantText>().map((t) => t.text).join(' ');
    expect(text.toLowerCase(), contains('pong'));
    await h.close();
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('the model on this Mac decides, and answers plain questions itself', () async {
    final model = Platform.environment['HELMY_LOCAL_MODEL'];
    final d = Decider(model: () => model);
    // Loading from disk can outlast a decision's time limit; warm it first.
    await d.decide('hello', route: true, timeout: const Duration(minutes: 3));
    final plain = await d.decide('what does HTTP 429 mean?', route: true);
    final tools = await d.decide('why is my build failing?', route: true);
    final mail = await d.decide('any unread emails from the bank?', route: true);
    // ignore: avoid_print
    print('plain: $plain\ntools: $tools\nmail: $mail');
    expect(plain!.direct, isTrue);
    expect(tools!.direct, isFalse);
    expect(mail!.services, contains(Capability.gmail));

    final engine = OllamaChatEngine(model: () => model);
    Future<List<ChatItem>> reply(String text) async {
      final items = <ChatItem>[];
      final run = await engine.start(
        EngineLaunch(cwd: Directory.systemTemp.path, level: .ask),
        items,
      );
      final done = run.changes.firstWhere((ended) => ended);
      run.send(text);
      await done.timeout(const Duration(minutes: 3));
      await run.close();
      return items;
    }

    final answer = await reply('In one sentence: what does HTTP 429 mean?');
    expect(answer.whereType<AssistantText>().single.text.toLowerCase(), contains('request'));
    final handOver = await reply(
      'List the files in my project folder and tell me what is in them.',
    );
    expect(handOver.whereType<AssistantText>(), isEmpty, reason: 'the marker is never shown');
    expect(handOver.whereType<TurnSummary>().single.error, needsToolsError);
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('Stop ends background work', () async {
    final h = await _Live.make([claude], _Scripted(['claude']));
    await h.say(
      "Run 'sleep 120; echo late' with Bash in the background (run_in_background true). "
      "Then just say 'started' and end your turn without checking on it.",
    );
    final call = h.items.whereType<ToolCall>().firstWhere((c) => c.background != null);
    h.repo.stopTask(h.id, call.background!.id);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (call.background!.status == BackgroundStatus.running &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(call.background!.status, BackgroundStatus.stopped);
    // Whatever the agent does about it, the session settles.
    while (h.repo.of(h.id).busy &&
        DateTime.now().isBefore(deadline.add(const Duration(seconds: 60)))) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(h.repo.of(h.id).busy, isFalse);
    await h.close();
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('a message fails over when the chosen engine cannot start', () async {
    final h = await _Live.make([_Broken(), claude], _Scripted(['broken', 'claude']));
    await h.say('Reply with only the word: ok');
    expect(h.items.whereType<AssistantText>().last.text.toLowerCase(), contains('ok'));
    expect(h.items.whereType<Notice>(), isEmpty);
    expect(h.session.lastEngineId, 'claude');
    await h.close();
  }, timeout: const Timeout(Duration(minutes: 4)));
}

/// A cat Codex drew in an earlier live test.
final _cat = Platform.environment['HELMY_TEST_IMAGE'] ?? '';

/// Picks engines in a fixed order, falling through to what is left.
class _Scripted implements EngineRouter {
  new(this.order);
  final List<String> order;
  int _next = 0;

  @override
  String? choose({
    required List<EngineInfo> candidates,
    required String? current,
    Set<Capability> needs = const {},
  }) {
    final ids = [for (final c in candidates) c.id];
    while (_next < order.length) {
      final id = order[_next++];
      if (ids.contains(id)) return id;
    }
    return ids.firstOrNull;
  }
}

/// An engine that is installed but cannot start.
class _Broken implements AgentEngine {
  @override
  final info = const EngineInfo(id: 'broken', name: 'Broken');
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
  Future<Set<Capability>> connected() async => const {};
  @override
  Future<String?> ask(String instructions, String question) async => null;
  @override
  Future<List<({String name, String status})>> servers() async => const [];
  @override
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items) =>
      Future.error(StateError('cannot start'));
}

class _Live {
  new _(this.root, this.work, this.storage, this.sessions, this.repo, this.id);

  static Future<_Live> make(
    List<AgentEngine> engines,
    EngineRouter router, {
    List<PermissionRule> rules = const [],
    PermissionLevel level = .ask,
  }) async {
    final root = await Directory.systemTemp.createTemp('helmy-live');
    final work = await Directory('${root.path}/work').create();
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry(engines),
      router: router,
      meter: UsageMeter(),
      storage: storage,
      sessions: sessions,
      rules: () => rules,
    );
    final created = await sessions.create(cwd: work.path, level: level) as Ok;
    return _Live._(root, work, storage, sessions, repo, created.value.id as String);
  }

  final Directory root, work;
  final StorageService storage;
  final SessionRepositoryLocal sessions;
  final ConversationRepositoryEngines repo;
  final String id;

  List<ChatItem> get items => repo.of(id).items;
  dynamic get session => sessions.byId(id)!;

  /// Sends [text], allows whatever is asked, and waits for the turn to end.
  Future<void> say(
    String text, {
    List<String> attachments = const [],
    Set<Capability> needs = const {},
    bool allow = true,
    String? alsoSend,
  }) async {
    final done = Completer<void>();
    var sentAlso = false;
    void check() {
      if (alsoSend != null && !sentAlso && repo.of(id).busy) {
        sentAlso = true;
        repo.send(sessions.byId(id)!, alsoSend);
      }
      for (final p in items.whereType<PermissionPrompt>()) {
        if (p.decision == .pending && allow) {
          p.toolName == 'ExitPlanMode'
              ? repo.answerPermission(id, p, .allow)
              : repo.answerPermission(id, p, .allow);
        }
      }
      if (!repo.of(id).busy && repo.of(id).queue.isEmpty && !done.isCompleted) {
        done.complete();
      }
    }

    repo.addListener(check);
    await repo.send(sessions.byId(id)!, text, attachments: attachments, needs: needs);
    check();
    await done.future.timeout(const Duration(minutes: 3));
    repo.removeListener(check);
  }

  Future<void> close() async {
    repo.dispose();
    await storage.flush();
    await root.delete(recursive: true);
  }
}
