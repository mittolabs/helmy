import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../domain/models/chat_item.dart';
import '../../../../domain/models/engine.dart';
import '../../../../domain/identity.dart';
import '../../../../domain/models/memory.dart';
import '../agent_engine.dart';
import '../codex/codex_engine.dart';
import 'ollama_doctor.dart';

/// What a plain answer says, alone, when it needed tools after all.
const needsToolsMarker = 'NEEDS_TOOLS';

/// The error a turn ends with when the model asked for tools, so the message
/// goes to an engine that has them rather than counting as a failure.
const needsToolsError = 'needs tools';

/// The model on this Mac, answering directly: no agent, no tools, a short
/// instruction of its own. Chosen offline for messages that need no tools,
/// where Codex's instructions (about 2,000 tokens) would cost every turn
/// seconds. When the question turns out to need tools after all, it says so
/// and the message goes on to an agent.
class OllamaChatEngine implements AgentEngine {
  new({required this._model, this.host = 'http://localhost:11434'});

  /// The model chosen in settings; null for the first one pulled.
  final String? Function() _model;
  final String host;

  @override
  final info = const EngineInfo(
    id: 'ollama-chat',
    name: 'Ollama on this computer (answers only)',
    localOnly: true,
  );

  /// The rule first, with examples: told only as a closing line, qwen3:8b
  /// politely refused ("I cannot list files") instead of handing over.
  static const instructions =
      'Rule one: if answering needs the user\'s files, folder, project, commands, git, '
      'logs, images to be made, or their email, calendar, drive, chat or notes, reply '
      'with exactly $needsToolsMarker and nothing else. Do not apologize or explain; '
      'another assistant with those abilities will take over.\n\n'
      'Examples:\n'
      'User: what is in this folder? -> $needsToolsMarker\n'
      'User: fix the failing test -> $needsToolsMarker\n'
      'User: what does a 404 mean? -> (answer it)\n\n'
      'Otherwise you are a helpful assistant in a desktop chat app: answer directly '
      'and concisely, in Markdown.';

  /// The longest answer, in tokens: a small model asked for a picture once
  /// drew one in text until Ollama gave up after five minutes.
  static const maxTokens = 2048;

  Future<String?> _resolveModel() async {
    final models = await CodexEngine.ollamaModels();
    if (models == null || models.isEmpty) return null;
    final chosen = _model();
    return chosen != null && models.contains(chosen) ? chosen : models.first;
  }

  @override
  Future<String?> unavailableReason() async {
    // Stuck unloading a model, it would never answer: restarted first.
    await OllamaDoctor.ensure();
    final models = await CodexEngine.ollamaModels();
    if (models == null) return 'Ollama is not running.';
    if (models.isEmpty) return 'Ollama has no model yet.';
    return null;
  }

  @override
  Future<List<MemoryFile>> memoryFiles() async => const [];

  @override
  Future<List<MemoryNote>> memoryNotes() async => const [];

  @override
  Future<List<SlashCommand>> commands(String cwd) async => const [];

  @override
  Future<Usage?> readUsage() async => null;

  /// Its model is the one picked in Settings: none to choose here.
  @override
  Future<List<ModelChoice>> models() async => const [];

  @override
  Future<List<({String name, String status})>> servers() async => const [];

  @override
  Future<Set<Capability>> connected() async => const {};

  @override
  Future<Answer?> ask(String instructions, String question) async => null;

  @override
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items) async {
    final model = await _resolveModel();
    if (model == null) throw StateError((await unavailableReason())!);
    return OllamaChatRun(
      host: host,
      model: model,
      items: items,
      brief: launch.brief,
      lessons: launch.lessons,
    );
  }
}

/// One conversation with the model: it keeps the messages so far, and
/// streams each answer into [items].
class OllamaChatRun implements EngineRun {
  new({required this.host, required this.model, required this.items, this.brief, this.lessons});

  /// The chat's brief, frozen for the thread.
  final String? brief;

  /// What Helmy has learned working with the person.
  final String? lessons;

  final String host;
  final String model;
  final List<ChatItem> items;

  final List<Map<String, String>> _history = [];
  final _changes = StreamController<bool>.broadcast();
  HttpClient? _client;
  var _turns = 0;
  String? _failure;

  /// Set when stopped, so the cut-off answer ends as interrupted.
  var _stopped = false;

  @override
  final status = EngineStatus();

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  String? get exitDetail => _failure;

  @override
  void send(String text, {List<String> attachments = const []}) {
    _history.add({'role': 'user', 'content': text});
    unawaited(_answer());
  }

  Future<void> _answer() async {
    _stopped = false;
    final client = _client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final reply = AssistantText('ollama-${_turns++}:0', '');
    var shown = false;
    final buffer = StringBuffer();
    String? error;
    // The model has said all it will: a Stop pressed after this cut nothing.
    var finished = false;
    status.thinking = true;
    _changes.add(false);
    try {
      final req = await client.postUrl(Uri.parse('$host/api/chat'));
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'model': model,
          'think': false,
          'stream': true,
          'options': {'num_predict': OllamaChatEngine.maxTokens},
          'messages': [
            {
              'role': 'system',
              'content':
                  '${identityWith(brief, lessons: lessons)}\n\n${OllamaChatEngine.instructions}',
            },
            ..._history,
          ],
        }),
      );
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('Ollama answered ${res.statusCode}');
      await for (final line in res.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        final chunk = jsonDecode(line) as Map;
        if (chunk['error'] != null) throw HttpException('${chunk['error']}');
        if (chunk['done'] == true) finished = true;
        buffer.write((chunk['message'] as Map?)?['content'] ?? '');
        final sofar = buffer.toString();
        // Held back until it cannot be the marker, so the marker never shows.
        if (!shown && sofar.trimLeft().length >= needsToolsMarker.length + 2 ||
            !shown && chunk['done'] == true) {
          if (sofar.trim().startsWith(needsToolsMarker)) break;
          shown = true;
          status.thinking = false;
          items.add(reply);
        }
        if (shown) {
          reply.text = sofar;
          _changes.add(false);
        }
      }
    } on Object catch (e) {
      // Once the answer is whole, a connection closed under it lost nothing.
      if (!finished) error = '$e';
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
    status.thinking = false;
    final text = buffer.toString().trim();
    if (_stopped && !finished) {
      if (shown) {
        _history
          ..add({'role': 'assistant', 'content': reply.text})
          // So Helmy knows, if asked, that this answer was cut off.
          ..add({'role': 'system', 'content': 'The user stopped your answer above at this point.'});
      } else {
        _history.removeLast();
      }
      items
        ..add(Notice('Interrupted'))
        ..add(TurnSummary(ok: true)..endedAt = DateTime.now());
    } else if (error == null && text.startsWith(needsToolsMarker)) {
      // Nothing shown: the message goes on to an engine with tools.
      _history.removeLast();
      items.add(TurnSummary(ok: false, error: needsToolsError)..endedAt = DateTime.now());
    } else if (error != null && !shown) {
      _failure = error;
      _history.removeLast();
      items.add(TurnSummary(ok: false, error: error)..endedAt = DateTime.now());
    } else {
      _history.add({'role': 'assistant', 'content': reply.text});
      items.add(TurnSummary(ok: error == null, error: error)..endedAt = DateTime.now());
    }
    _changes.add(true);
  }

  /// Answers take seconds and use no tools: there is no next step to take a
  /// message in at, so a message waits or the answer is stopped for it.
  @override
  Future<bool> steer(String text, {List<String> attachments = const []}) async => false;

  /// Stops the answer where it is.
  @override
  void interrupt() {
    _stopped = true;
    _client?.close(force: true);
  }

  @override
  void answer(PermissionPrompt prompt, PermissionAnswer answer, {String? why}) {}

  @override
  void answerQuestion(PermissionPrompt prompt) {}

  /// Nothing to compact: the conversation is only what was said. The turn
  /// ends at once, so the session does not wait on it.
  @override
  void compact() {
    items.add(TurnSummary(ok: true)..endedAt = DateTime.now());
    _changes.add(true);
  }

  @override
  void stopTask(String taskId) {}

  @override
  void setLevel(PermissionLevel level) {}

  @override
  Future<void> close() async {
    _client?.close(force: true);
    await _changes.close();
  }
}
