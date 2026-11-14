import 'dart:async';

import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/memory.dart';

/// A connection that answers each message with the next of [replies] (the
/// last one again once they run out), reporting [contextUsed] tokens of
/// conversation, and records how each run was started.
class EchoEngine implements AgentEngine {
  EchoEngine(this.replies);
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
    return _EchoRun(this, items);
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

class _EchoRun implements EngineRun {
  _EchoRun(this.engine, this.items);
  final EchoEngine engine;
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
