import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/memory.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

/// A connection whose turn asks to push, and keeps working until told
/// something; told yes, it asks for the same push again.
class _Engine implements AgentEngine {
  @override
  final info = const EngineInfo(id: 'claude', name: 'agent', capabilities: {Capability.tools});

  /// What Helmy's judge was given as instructions, each time.
  final judged = <String>[];
  _Run? run;

  @override
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items) async => run = _Run(items);

  @override
  Future<String?> ask(String instructions, String question) async {
    judged.add(instructions);
    return '{"verdict": "ask", "why": "Push your branch to GitHub?"}';
  }

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
  _Run(this.items);
  final List<ChatItem> items;
  final _changes = StreamController<bool>.broadcast();

  /// Each answer given: the request, what it was, and what the agent was told.
  final answers = <(String, PermissionAnswer, String?)>[];
  final steered = <String>[];
  final questionAnswers = <Map<String, String>>[];
  var _asks = 0;

  void askToPush({String description = 'Push the branch'}) {
    _asks++;
    final input = {'command': 'git push origin feature', 'description': description};
    items
      ..add(ToolCall(id: 't$_asks', name: 'Bash', input: input))
      ..add(
        PermissionPrompt(
          requestId: 'r$_asks',
          toolName: 'Bash',
          input: input,
          suggestions: const [],
          toolUseId: 't$_asks',
        ),
      );
    _changes.add(false);
  }

  void askQuestion() {
    items.add(
      PermissionPrompt(
        requestId: 'q',
        toolName: 'AskUserQuestion',
        input: {
          'questions': [
            {
              'question': 'Which database?',
              'options': [
                {'label': 'Postgres'},
                {'label': 'SQLite'},
              ],
            },
          ],
        },
        suggestions: const [],
      ),
    );
    _changes.add(false);
  }

  @override
  final status = EngineStatus();
  @override
  Stream<bool> get changes => _changes.stream;
  @override
  String? get exitDetail => null;

  /// The turn starts by asking to push, and does not end on its own.
  @override
  void send(String text, {List<String> attachments = const []}) => scheduleMicrotask(askToPush);

  /// Told yes mid-turn, it takes the same step again, described afresh.
  @override
  Future<bool> steer(String text, {List<String> attachments = const []}) async {
    steered.add(text);
    if (text.startsWith('Yes')) scheduleMicrotask(() => askToPush(description: 'Push it now'));
    return true;
  }

  @override
  void answer(PermissionPrompt prompt, PermissionAnswer answer, {String? why}) =>
      answers.add((prompt.requestId, answer, why));
  @override
  void answerQuestion(PermissionPrompt prompt) => questionAnswers.add({...prompt.answers});
  @override
  void interrupt() {}
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
  late Directory root;
  late SessionRepositoryLocal sessions;
  late ConversationRepositoryEngines repo;
  late _Engine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('held');
    final storage = storageAt(root);
    sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    engine = _Engine();
    repo = ConversationRepositoryEngines(
      engines: EngineRegistry([engine]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
  });
  tearDown(() async {
    repo.dispose();
    await root.delete(recursive: true);
  });

  Future<Session> chat({bool away = false}) async {
    final s = (await sessions.create(cwd: root.path, title: 'Ship it') as Ok).value as Session;
    final saved = s.copyWith(away: away);
    await sessions.save(saved);
    return saved;
  }

  PermissionPrompt prompt(String id, String requestId) =>
      repo.of(id).items.whereType<PermissionPrompt>().firstWhere((p) => p.requestId == requestId);

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue);
  }

  test('a question held for the person lets the work go on; a later yes lets the same step '
      'through', () async {
    final s = await chat();
    await repo.send(s, 'Push the branch when it builds');
    await until(() => engine.run?.answers.isEmpty == false || _asked(repo, s.id));
    final p = prompt(s.id, 'r1');
    expect(p.decision, PermissionDecision.pending);
    expect(p.why, 'Push your branch to GitHub?');
    expect(repo.of(s.id).pendingPrompts, 1);

    // Gone: the agent is told to carry on, and the question waits for them.
    repo.carryOn(s.id);
    final run = engine.run!;
    expect(p.decision, PermissionDecision.waiting);
    expect(p.held, isTrue);
    expect(run.answers.single.$1, 'r1');
    expect(run.answers.single.$2, PermissionAnswer.deny);
    expect(run.answers.single.$3, contains('Push your branch to GitHub?'));
    expect(run.answers.single.$3, contains('carry on'));
    expect(repo.of(s.id).pendingPrompts, 1, reason: 'it still needs them');

    // Back, and yes: the agent hears it at its next step, and the same push
    // (described differently) goes through without asking again.
    repo.answerPermission(s.id, p, PermissionAnswer.allow);
    expect(p.decision, PermissionDecision.allowed);
    await until(() => run.answers.any((a) => a.$1 == 'r2'));
    expect(run.steered.single, startsWith('Yes to what you held for me: "Push your branch'));
    expect(run.answers.last, ('r2', PermissionAnswer.allow, null));
    expect(prompt(s.id, 'r2').decision, PermissionDecision.allowed);
    expect(repo.of(s.id).pendingPrompts, 0);
  });

  test('away, nothing waits: what would be asked is held at once, and the judge knows they '
      'are away', () async {
    final s = await chat(away: true);
    await repo.send(s, 'Push the branch when it builds');
    await until(() => engine.run?.answers.isNotEmpty ?? false);
    expect(prompt(s.id, 'r1').decision, PermissionDecision.waiting);
    expect(engine.judged.single, contains('The person is away'));

    // The agent's own question is answered for now with its own choice.
    engine.run!.askQuestion();
    await until(() => engine.run!.questionAnswers.isNotEmpty);
    final q = prompt(s.id, 'q');
    expect(q.decision, PermissionDecision.waiting);
    expect(engine.run!.questionAnswers.single['Which database?'], contains('recommend'));
    expect(q.answers, isEmpty, reason: 'their own answer is still to come');

    // Their answer, later, goes to the agent.
    q.answers['Which database?'] = 'SQLite';
    repo.answerQuestion(s.id, q);
    expect(q.decision, PermissionDecision.allowed);
    await until(() => engine.run!.steered.isNotEmpty);
    expect(engine.run!.steered.single, contains('Which database? SQLite'));
  });

  test('a held decision is kept across a restart; one being judged is not', () {
    final p = PermissionPrompt(
      requestId: 'r',
      toolName: 'Bash',
      input: const {'command': 'git push'},
      suggestions: const [],
    );
    p
      ..decision = PermissionDecision.waiting
      ..held = true;
    final back = PermissionPrompt.fromJson(p.toJson());
    expect(back.decision, PermissionDecision.waiting);
    expect(back.held, isTrue);
    expect(back.needsAnswer, isTrue);
    p.decision = PermissionDecision.pending;
    expect(PermissionPrompt.fromJson(p.toJson()).decision, PermissionDecision.cancelled);
  });

  test('away is kept with the chat', () async {
    final s = await chat(away: true);
    expect(Session.fromJson(s.toJson()).away, isTrue);
    expect(Session.fromJson(s.copyWith(away: false).toJson()).away, isFalse);
  });

  test('the same step is known again whatever words describe it', () {
    PermissionPrompt bash(String description) => PermissionPrompt(
      requestId: description,
      toolName: 'Bash',
      input: {'command': 'git push', 'description': description},
      suggestions: const [],
    );
    expect(
      ConversationRepositoryEngines.heldSignature(bash('Push')),
      ConversationRepositoryEngines.heldSignature(bash('Push it now')),
    );
  });
}

bool _asked(ConversationRepositoryEngines repo, String id) => repo
    .of(id)
    .items
    .whereType<PermissionPrompt>()
    .any((p) => p.decision == PermissionDecision.pending && p.why != null);
