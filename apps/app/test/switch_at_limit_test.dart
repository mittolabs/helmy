import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/model_names.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/memory.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/domain/problem.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/problem_card.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

const _opus = ModelChoice(id: 'claude-opus-5-5', name: 'Opus 5.5');
const _sonnet = ModelChoice(id: 'claude-sonnet-5', name: 'Sonnet 5');
const _astra = ModelChoice(id: 'gpt-6-astra', name: 'GPT-6-Astra');
const _astraMini = ModelChoice(id: 'gpt-6-astra-mini', name: 'GPT-6-Astra Mini');

/// A connection that answers every message, with the models it offers. Its
/// default model is the first it lists.
class _Engine implements AgentEngine {
  _Engine(String id, String name, this.offered, {bool local = false})
    : info = EngineInfo(
        id: id,
        name: name,
        localOnly: local,
        capabilities: const {Capability.tools},
      );

  @override
  final EngineInfo info;
  final List<ModelChoice> offered;
  final sent = <String>[];
  final launches = <EngineLaunch>[];

  @override
  Future<List<ModelChoice>> models() async => offered;
  @override
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items) async {
    launches.add(launch);
    return _Run(this, items)..status.model = launch.model ?? offered.firstOrNull?.id;
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
      items
        ..add(AssistantText('${engine.info.id}-${engine.sent.length}', 'from ${engine.info.id}'))
        ..add(TurnSummary(ok: true));
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

void main() {
  group('model classes', () {
    test('flagships and smaller models read as such', () {
      expect(classOf('claude-opus-5-5'), ModelClass.flagship);
      expect(classOf('opus'), ModelClass.flagship);
      expect(classOf('gpt-6-astra'), ModelClass.flagship);
      expect(classOf('claude-sonnet-5'), ModelClass.smaller);
      expect(classOf('claude-haiku-4-5'), ModelClass.smaller);
      expect(classOf('gpt-6-astra-mini'), ModelClass.smaller);
      expect(classOf('gemini-3-pro'), ModelClass.flagship);
      expect(classOf('llama3.2'), isNull);
    });

    test('the closest model is the same one, then the first of its class', () {
      expect(closestModel('gpt-6-astra', [_astraMini, _astra]), _astra);
      expect(closestModel('claude-opus-5-5', [_astraMini, _astra]), _astra);
      expect(closestModel('claude-sonnet-5', [_astra, _astraMini]), _astraMini);
      expect(closestModel('llama3.2', [_astra]), isNull);
    });
  });

  group('the router at 90%', () {
    final now = DateTime(2026, 11, 14, 12);
    late UsageMeter meter;
    late HeadroomRouter router;
    final both = [
      const EngineInfo(id: 'claude', name: 'claude'),
      const EngineInfo(id: 'codex', name: 'codex'),
    ];
    setUp(() {
      meter = UsageMeter();
      router = HeadroomRouter(meter, now: () => now);
    });

    test('a warm chat leaves a connection measured at 90% for the same class', () {
      meter
        ..report('claude', Usage(used: .9, resetsAt: now.add(const Duration(hours: 2))))
        ..report('codex', const Usage(used: .4));
      expect(
        router.choose(candidates: both, current: 'claude', warm: true, alike: {'codex'}),
        'codex',
      );
      expect(router.why, 'moved: the other was nearly at its limit');
    });

    test('with nothing of its class with room, it stays until the limit itself', () {
      meter
        ..report('claude', const Usage(used: .92))
        ..report('codex', const Usage(used: .1));
      expect(router.choose(candidates: both, current: 'claude', warm: true, alike: {}), 'claude');
    });

    test('a number from before its window reset, or none, never moves it', () {
      meter.report('claude', Usage(used: .97, resetsAt: now.subtract(const Duration(minutes: 1))));
      expect(meter.nearlyOut('claude', now: now), isFalse);
      expect(
        router.choose(candidates: both, current: 'claude', warm: true, alike: {'codex'}),
        'claude',
      );
      expect(meter.nearlyOut('codex', now: now), isFalse, reason: 'never measured');
    });

    test('the current window is the fullest one that has not reset', () {
      meter.report(
        'claude',
        Usage(
          used: .95,
          windows: [
            UsageWindow(
              name: 'Session',
              used: .95,
              resetsAt: now.subtract(const Duration(hours: 1)),
            ),
            UsageWindow(name: 'Weekly', used: .3, resetsAt: now.add(const Duration(days: 3))),
          ],
        ),
      );
      expect(meter.usedNow('claude', now: now), .3);
    });
  });

  late Directory root;
  late SessionRepositoryLocal sessions;
  late StorageService storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('switch');
    storage = storageAt(root);
    sessions = SessionRepositoryLocal(storage);
  });
  tearDown(() => deleteFolder(root));

  Future<(ConversationRepositoryEngines, Session)> make(
    List<_Engine> engines,
    UsageMeter meter, {
    bool developer = false,
  }) async {
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry(engines),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
      developerMode: () => developer,
    );
    final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
    repo.of(s.id).loaded = true;
    return (repo, s);
  }

  Future<void> ask(ConversationRepositoryEngines repo, Session s, String text) async {
    await repo.send(sessions.byId(s.id)!, text);
    for (var i = 0; i < 50 && repo.of(s.id).busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  TurnSummary lastAnswer(ConversationRepositoryEngines repo, Session s) =>
      repo.of(s.id).items.whereType<TurnSummary>().last;

  test('at 90%, the next message goes to the same class elsewhere, said only on hover', () async {
    final meter = UsageMeter();
    final claude = _Engine('claude', 'Claude Code', const [_opus, _sonnet]);
    final codex = _Engine('codex', 'Codex', const [_astraMini, _astra]);
    final (repo, s) = await make([claude, codex], meter);
    addTearDown(repo.dispose);
    meter
      ..report('claude', const Usage(used: .2))
      ..report('codex', const Usage(used: .5));
    await ask(repo, s, 'change the code');
    expect(lastAnswer(repo, s).engineId, 'claude');
    expect(lastAnswer(repo, s).model, 'claude-opus-5-5');

    // Measured at 90% after that turn: the next goes to Codex's flagship,
    // though Codex lists its smaller model first.
    meter.report('claude', Usage(used: .9, resetsAt: DateTime.now().add(const Duration(hours: 3))));
    await ask(repo, s, 'and the tests');
    final by = lastAnswer(repo, s);
    expect((by.engineId, by.model), ('codex', 'gpt-6-astra'));
    expect(codex.launches.single.model, 'gpt-6-astra');
    expect(by.why, 'moved: the other was nearly at its limit');
    // Nothing said in the conversation, and nothing named.
    expect(repo.of(s.id).items.whereType<Notice>(), isEmpty);
    // It stays on that model while it is there.
    await ask(repo, s, 'and the docs');
    expect(lastAnswer(repo, s).engineId, 'codex');
    expect(codex.launches, hasLength(1));
  });

  test('a held chat gives way at its limit, says so, and goes back once it has room', () async {
    final meter = UsageMeter();
    final claude = _Engine('claude', 'Claude Code', const [_sonnet, _opus]);
    final codex = _Engine('codex', 'Codex', const [_astra, _astraMini]);
    final (repo, s) = await make([claude, codex], meter, developer: true);
    addTearDown(repo.dispose);
    await sessions.save(
      s.copyWith(
        pin: const EnginePin(engineId: 'codex', model: 'gpt-6-astra'),
      ),
    );
    final reset = DateTime.now().add(const Duration(hours: 2));
    meter.report('codex', Usage(used: 1, resetsAt: reset));

    await ask(repo, s, 'change the code');
    var by = lastAnswer(repo, s);
    expect((by.engineId, by.model), ('claude', 'claude-opus-5-5'));
    expect(by.why, 'carried on: the one you chose was at its limit');
    final said = repo.of(s.id).items.whereType<Notice>().single.text;
    expect(said, startsWith('Codex (GPT-6-Astra) is out until '));
    expect(said, endsWith(', so I carried on with Claude Code (Opus 5.5).'));
    expect(said, isNot(contains('\u2014')));

    // Still out: it carries on without saying it again.
    await ask(repo, s, 'and the tests');
    expect(lastAnswer(repo, s).engineId, 'claude');
    expect(repo.of(s.id).items.whereType<Notice>(), hasLength(1));

    // Room again: back on the held model, the hold itself untouched.
    meter.report('codex', const Usage(used: .1));
    await ask(repo, s, 'and the docs');
    by = lastAnswer(repo, s);
    expect((by.engineId, by.why), ('codex', 'chosen by you'));
    expect(codex.launches.last.model, 'gpt-6-astra');
    expect(sessions.byId(s.id)!.pin?.engineId, 'codex');
    expect(
      repo.of(s.id).items.whereType<Notice>().last.text,
      'Codex (GPT-6-Astra) has room again, so I went back to it.',
    );
  });

  test('a held chat at 90% gives way between turns, and says it was nearly out', () async {
    final meter = UsageMeter();
    final claude = _Engine('claude', 'Claude Code', const [_opus]);
    final codex = _Engine('codex', 'Codex', const [_astra]);
    final (repo, s) = await make([claude, codex], meter, developer: true);
    addTearDown(repo.dispose);
    await sessions.save(
      s.copyWith(
        pin: const EnginePin(engineId: 'codex', model: 'gpt-6-astra'),
      ),
    );
    meter.report('codex', const Usage(used: .93));
    await ask(repo, s, 'change the code');
    expect(lastAnswer(repo, s).engineId, 'claude');
    expect(
      repo.of(s.id).items.whereType<Notice>().single.text,
      'Codex (GPT-6-Astra) is nearly at its usage limit, so I carried on with '
      'Claude Code (Opus 5.5).',
    );
  });

  group('the limit card', () {
    /// Lets real work (files, the fake connections) and the test clock's
    /// own continuations both run.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    /// Presses the button [label] is on, its work run on the real clock: the
    /// repository reads and writes files and starts connections.
    Future<void> press(WidgetTester tester, Finder label) async {
      final button = tester.widget<Button>(find.ancestor(of: label, matching: find.byType(Button)));
      await tester.runAsync(() async {
        button.onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settle(tester);
    }

    Future<(ConversationRepositoryEngines, ChatViewModel, Session)> stopped(
      WidgetTester tester,
      List<_Engine> engines,
      UsageMeter meter, {
      bool developer = false,
      EnginePin? pin,
    }) async {
      late ConversationRepositoryEngines repo;
      late ChatViewModel vm;
      late Session s;
      await tester.runAsync(() async {
        (repo, s) = await make(engines, meter, developer: developer);
        if (pin != null) await sessions.save(s.copyWith(pin: pin));
        repo.of(s.id).items.addAll([
          UserMessage('change the code'),
          AssistantText('a', 'Starting.'),
          TurnSummary(ok: false, error: 'usage limit reached')..engineId = 'codex',
        ]);
        vm = ChatViewModel(sessionId: s.id, sessions: sessions, conversations: repo);
      });
      final p = diagnose('usage limit reached', engineId: 'codex');
      expect(p.limit, isTrue);
      await tester.pumpWidget(
        AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: ProblemCard(problem: p, vm: vm),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      return (repo, vm, s);
    }

    Future<void> done(WidgetTester tester, ConversationRepositoryEngines repo, ChatViewModel vm) =>
        tester.runAsync(() async {
          vm.dispose();
          repo.dispose();
          await storage.flush();
        });

    testWidgets('another with room: Continue now, unnamed, and Wait until the reset', (
      tester,
    ) async {
      final meter = UsageMeter();
      final reset = DateTime.now().add(const Duration(hours: 1));
      meter.report('codex', Usage(used: 1, resetsAt: reset));
      final claude = _Engine('claude', 'Claude Code', const [_opus]);
      final codex = _Engine('codex', 'Codex', const [_astra]);
      final (repo, vm, s) = await stopped(tester, [claude, codex], meter);
      expect(find.text('Continue now'), findsOneWidget);
      expect(find.text('Wait until ${clockAt(reset, null)}'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.textContaining('Claude'), findsNothing);
      expect(find.textContaining('Codex'), findsNothing);

      // Continue: the message goes again, now, to the one with room.
      await press(tester, find.text('Continue now'));
      expect(claude.sent, hasLength(1));
      expect(codex.sent, isEmpty);
      expect(repo.of(s.id).items.whereType<UserMessage>().single.text, 'change the code');
      await done(tester, repo, vm);
    });

    testWidgets('waiting holds the message until the reset', (tester) async {
      final meter = UsageMeter();
      final reset = DateTime.now().add(const Duration(hours: 1));
      meter
        ..report('codex', Usage(used: 1, resetsAt: reset))
        ..report('claude', Usage(used: 1, resetsAt: reset.add(const Duration(hours: 1))));
      final claude = _Engine('claude', 'Claude Code', const [_opus]);
      final codex = _Engine('codex', 'Codex', const [_astra]);
      final (repo, vm, s) = await stopped(tester, [claude, codex], meter);
      expect(find.text('Continue now'), findsNothing);
      expect(
        find.text(
          'Nothing else I can use has room either; the first frees up '
          '${atTime(reset, null)}.',
        ),
        findsOneWidget,
      );
      await press(tester, find.text('Wait until ${clockAt(reset, null)}'));
      expect(repo.of(s.id).heldUntil, reset);
      expect(repo.of(s.id).items.last, isA<Notice>());
      await tester.runAsync(() async => repo.interrupt(s.id));
      await done(tester, repo, vm);
    });

    testWidgets('a held chat names where it would carry on', (tester) async {
      final meter = UsageMeter();
      final claude = _Engine('claude', 'Claude Code', const [_sonnet, _opus]);
      final codex = _Engine('codex', 'Codex', const [_astra]);
      final (repo, vm, _) = await stopped(
        tester,
        [claude, codex],
        meter,
        developer: true,
        pin: const EnginePin(engineId: 'codex', model: 'gpt-6-astra'),
      );
      expect(find.text('Continue with Claude Code (Opus 5.5)'), findsOneWidget);
      await press(tester, find.text('Continue with Claude Code (Opus 5.5)'));
      expect(claude.launches.single.model, 'claude-opus-5-5');
      await done(tester, repo, vm);
    });

    testWidgets('only the model on this Mac left: Continue on this Mac', (tester) async {
      final meter = UsageMeter();
      final local = _Engine('ollama', 'Ollama', const [], local: true);
      final codex = _Engine('codex', 'Codex', const [_astra]);
      final (repo, vm, _) = await stopped(tester, [local, codex], meter);
      expect(find.text('Continue on this Mac'), findsOneWidget);
      await press(tester, find.text('Continue on this Mac'));
      expect(local.sent, hasLength(1));
      await done(tester, repo, vm);
    });
  });
}
