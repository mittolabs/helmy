import 'dart:async';

import 'dart:convert';

import '../../../../domain/models/chat_item.dart';

import 'dart:io';

import '../../../../domain/models/engine.dart';
import '../../../../domain/identity.dart';
import '../../../../domain/models/memory.dart';
import '../../cli_locator.dart';
import '../agent_engine.dart';
import '../attachments.dart';
import 'codex_reducer.dart';
import 'codex_rpc.dart';
import '../../../../utils/platform.dart';
import '../../helmy_tools.dart';
import '../ollama/ollama_doctor.dart';

/// Codex, driven through `codex app-server`: one thread per session, approvals
/// answered from the app.
class CodexEngine implements AgentEngine {
  new(this._locator)
    : info = const EngineInfo(
        id: 'codex',
        name: 'Codex',
        // Its image_generation feature, on by default in codex-cli 0.162.1.
        capabilities: {Capability.tools, Capability.imageGeneration},
      ),
      _local = null;

  /// Codex's agent on a model Ollama runs on this Mac: tools, approvals and
  /// all, with no internet. Chosen only when nothing online can answer.
  /// [model] is the one picked in settings, or null for the first pulled.
  new local(this._locator, {required String? Function() model})
    : info = const EngineInfo(
        id: 'ollama',
        name: 'Codex on Ollama (this computer)',
        localOnly: true,
        capabilities: {Capability.tools},
      ),
      _local = model;

  final CliLocator _locator;

  /// Set for the local engine: which Ollama model to use.
  final String? Function()? _local;

  static const _ollama = 'http://localhost:11434';

  /// The models Ollama has pulled, or null when it is not running.
  static Future<List<String>?> ollamaModels() async {
    // It sometimes answers its list with an error for a moment while idle:
    // ask twice before deciding.
    for (var attempt = 0; attempt < 2; attempt++) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      try {
        final req = await client.getUrl(Uri.parse('$_ollama/api/tags'));
        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) throw HttpException('status ${res.statusCode}');
        final body = jsonDecode(await res.transform(utf8.decoder).join());
        _busy = false;
        return _lastModels = [
          for (final m in (body['models'] as List? ?? const []).whereType<Map>()) '${m['name']}',
        ];
      } on SocketException {
        // Nothing listening: Ollama is not running.
        _busy = false;
        return _lastModels = null;
      } on Object {
        if (attempt == 0) await Future<void>.delayed(const Duration(seconds: 1));
      } finally {
        client.close(force: true);
      }
    }
    // Listening but not listing: still there, with the models it last listed,
    // or else the models pulled to this Mac, as its own files record them.
    _busy = true;
    final known = _lastModels ?? pulledModels();
    return known.isEmpty ? known : _lastModels = known;
  }

  /// The models pulled to this Mac, from Ollama's manifests on disk:
  /// `.../manifests/registry.ollama.ai/library/gpt-oss/20b` is gpt-oss:20b.
  static List<String> pulledModels({String? home}) {
    final root = Directory('${home ?? homeDir}/.ollama/models/manifests/registry.ollama.ai');
    if (!root.existsSync()) return const [];
    return [
      for (final f in root.listSync(recursive: true).whereType<File>())
        if (f.path.substring(root.path.length + 1).split('/') case [
          final ns,
          final name,
          final tag,
        ])
          ns == 'library' ? '$name:$tag' : '$ns/$name:$tag',
    ]..sort();
  }

  /// What Ollama last listed, for while it is too busy to answer.
  static List<String>? _lastModels;

  /// Whether Ollama was listening but too busy to list its models just now.
  static bool _busy = false;

  /// The model the local engine runs: the one chosen, if pulled, else the first.
  Future<String?> _localModel() async {
    final models = await ollamaModels() ?? const [];
    final chosen = _local?.call();
    return chosen != null && models.contains(chosen) ? chosen : models.firstOrNull;
  }

  /// Helmy's levels as the approval policy and sandbox Codex takes.
  static (String, String) settings(PermissionLevel level) => switch (level) {
    .ask => ('untrusted', 'workspace-write'),
    .edit => ('on-request', 'workspace-write'),
    .readOnly => ('on-request', 'read-only'),
    .full => ('never', 'danger-full-access'),
  };

  @override
  final EngineInfo info;

  String get _home => '$homeDir/.codex';

  /// Its global AGENTS.md, which it reads in every project.
  @override
  Future<List<MemoryFile>> memoryFiles() async => [
    MemoryFile(engineId: info.id, path: '$_home/AGENTS.md', kind: 'Instructions for every project'),
  ];

  /// What it learns on its own lives in a database it consolidates itself;
  /// writing to it could break it, so Helmy only says how much is there.
  @override
  Future<List<MemoryNote>> memoryNotes() async {
    final db = File('$_home/memories_1.sqlite');
    if (!db.existsSync()) return const [];
    var count = 'some';
    try {
      final out = await Process.run('/usr/bin/sqlite3', [
        '-readonly',
        db.path,
        'select count(*) from stage1_outputs',
      ]).timeout(const Duration(seconds: 5));
      final n = int.tryParse((out.stdout as String).trim());
      if (n != null) count = '$n';
    } on Object {
      // Leave the count unknown rather than guess.
    }
    return [
      MemoryNote(
        engineId: info.id,
        text:
            'Codex also keeps $count memories it learned from past conversations, in its own '
            'database (${db.path.replaceFirst(homeDir, '~')}). '
            'Codex manages those itself, so they are shown here but not edited.',
      ),
    ];
  }

  final Map<String, Future<List<SlashCommand>>> _skills = {};

  /// Codex's skills for [cwd], from its app server.
  @override
  Future<List<SlashCommand>> commands(String cwd) =>
      _skills.putIfAbsent(cwd, () => _fetchSkills(cwd));

  Future<List<SlashCommand>> _fetchSkills(String cwd) async {
    final binary = await _locator.find('codex');
    if (binary == null) return const [];
    try {
      final rpc = await CodexRpc.start(
        binary: binary,
        environment: await _locator.environment(),
        cwd: cwd,
      );
      await rpc.request('initialize', {
        'clientInfo': {'name': 'helmy', 'title': 'Helmy', 'version': '0.1.0'},
        'capabilities': null,
      });
      rpc.notify('initialized', {});
      final result = await rpc
          .request('skills/list', {
            'cwds': [cwd],
          })
          .timeout(const Duration(seconds: 20));
      await rpc.close();
      return [
        for (final entry in (result['data'] as List? ?? const []).whereType<Map>())
          for (final s in (entry['skills'] as List? ?? const []).whereType<Map>())
            if (s['enabled'] != false)
              SlashCommand(
                name: '${s['name']}',
                description: '${s['shortDescription'] ?? s['description'] ?? ''}',
                path: s['path'] as String?,
              ),
      ];
    } on Object {
      _skills.remove(cwd);
      return const [];
    }
  }

  ({DateTime at, List<({String name, String status})> list})? _servers;

  /// The MCP servers Codex runs, with their state.
  @override
  Future<Set<Capability>> connected() async => connectedOf(await servers());

  @override
  Future<List<({String name, String status})>> servers() async {
    final cached = _servers;
    if (cached != null && DateTime.now().difference(cached.at).inMinutes < 10) return cached.list;
    final binary = await _locator.find('codex');
    if (binary == null || _local != null) return const [];
    try {
      final rpc = await CodexRpc.start(
        binary: binary,
        environment: await _locator.environment(),
        cwd: Directory.systemTemp.path,
      );
      await rpc.request('initialize', {
        'clientInfo': {'name': 'helmy', 'title': 'Helmy', 'version': '0.1.0'},
        'capabilities': null,
      });
      rpc.notify('initialized', {});
      final result = await rpc
          .request('mcpServerStatus/list', {})
          .timeout(const Duration(seconds: 15));
      await rpc.close();
      final list = [
        for (final s in (result['data'] as List? ?? const []).whereType<Map>())
          (
            name: '${s['name']}',
            // Codex lists servers it runs; a listed server without a state of
            // its own counts as connected.
            status: '${s['status'] ?? s['startupStatus'] ?? 'connected'}',
          ),
      ];
      _servers = (at: DateTime.now(), list: list);
      return list;
    } on Object {
      return _servers?.list ?? const [];
    }
  }

  /// Codex's app server answers `account/rateLimits/read` at any time, at no
  /// cost, so its reading can be fresh whenever settings is opened.
  @override
  Future<Usage?> readUsage() async {
    if (_local != null) return null;
    final binary = await _locator.find('codex');
    if (binary == null) return null;
    final dir = Directory.systemTemp.path;
    try {
      final rpc = await CodexRpc.start(
        binary: binary,
        environment: await _locator.environment(),
        cwd: dir,
      );
      await rpc.request('initialize', {
        'clientInfo': {'name': 'helmy', 'title': 'Helmy', 'version': '0.1.0'},
        'capabilities': null,
      });
      rpc.notify('initialized', {});
      final result = await rpc
          .request('account/rateLimits/read', {})
          .timeout(const Duration(seconds: 15));
      await rpc.close();
      // The same shape as the update it sends during a turn.
      final reducer = CodexReducer([])
        ..apply({
          'method': 'account/rateLimits/updated',
          'params': {'rateLimits': result['rateLimits']},
        });
      return reducer.usage;
    } on Object {
      return null;
    }
  }

  /// `codex exec`, read-only and kept nowhere; on the local model too.
  @override
  Future<String?> ask(String instructions, String question) async {
    final binary = await _locator.find('codex');
    if (binary == null) return null;
    final local = _local == null ? null : await _localModel();
    if (_local != null && local == null) return null;
    final dir = await Directory.systemTemp.createTemp('helmy-ask');
    try {
      final out = '${dir.path}/answer.txt';
      await Process.run(
        binary,
        [
          'exec',
          '--ephemeral',
          '--skip-git-repo-check',
          '-s',
          'read-only',
          '-o',
          out,
          if (local != null) ...['-c', 'model_provider="ollama"', '-m', local],
          '$instructions\n\n$question',
        ],
        workingDirectory: dir.path,
        environment: await _locator.environment(),
        includeParentEnvironment: false,
      ).timeout(const Duration(seconds: 120));
      final file = File(out);
      final text = file.existsSync() ? file.readAsStringSync().trim() : '';
      return text.isEmpty ? null : text;
    } on Object {
      return null;
    } finally {
      dir.delete(recursive: true).ignore();
    }
  }

  @override
  Future<String?> unavailableReason() async {
    if (await _locator.find('codex') == null) {
      return 'Could not find the codex command. Install Codex CLI first.';
    }
    if (_local == null) return null;
    await OllamaDoctor.ensure();
    final models = await ollamaModels();
    if (models == null) return 'Ollama is not running. Install it from ollama.com and start it.';
    if (models.isEmpty && _busy) return 'Ollama is busy. Try again in a moment.';
    if (models.isEmpty) {
      return 'Ollama has no model yet. Pull one, for example: ollama pull gpt-oss:20b';
    }
    return null;
  }

  @override
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items) async {
    final binary = await _locator.find('codex');
    if (binary == null) throw StateError((await unavailableReason())!);
    final rpc = await CodexRpc.start(
      binary: binary,
      environment: await _locator.environment(),
      cwd: launch.cwd,
    );
    final local = _local == null ? null : await _localModel();
    final run = _CodexRun(
      rpc,
      CodexReducer(items),
      () => commands(launch.cwd),
      // The local engine: Codex's own provider for Ollama, and its model.
      local == null ? const {} : {'modelProvider': 'ollama', 'model': local},
    );
    run._ready = run._open(launch);
    return run;
  }
}

class _CodexRun implements EngineRun {
  new(this._rpc, this._reducer, this._skills, this._provider) {
    _rpc.incoming.listen(_onMessage, onDone: _changes.close);
  }

  final CodexRpc _rpc;
  final CodexReducer _reducer;
  final Future<List<SlashCommand>> Function() _skills;

  /// Which provider and model the thread runs on, when not Codex's default.
  final Map<String, Object?> _provider;
  final _changes = StreamController<bool>.broadcast();
  late Future<String?> _ready;
  String? _threadId;

  @override
  final status = EngineStatus();

  @override
  Stream<bool> get changes => _changes.stream;

  String? _failure;

  @override
  String? get exitDetail {
    final tail = _rpc.stderrTail.trim();
    final head = _failure ?? 'Codex exited (code ${_rpc.exitCode ?? '?'})';
    if (tail.isEmpty) return head;
    return '$head:\n${tail.length > 1500 ? tail.substring(tail.length - 1500) : tail}';
  }

  /// Starts or resumes the thread. Null when that failed; why is in [exitDetail].
  Future<String?> _open(EngineLaunch launch) async {
    final (approval, sandbox) = CodexEngine.settings(launch.level);
    try {
      await _rpc.request('initialize', {
        'clientInfo': {'name': 'helmy', 'title': 'Helmy', 'version': '0.1.0'},
        'capabilities': null,
      });
      _rpc.notify('initialized', {});
      final tools = await HelmyTools.current?.url;
      final settings = {
        // Helmy's own tools, as an MCP server it runs.
        if (tools != null)
          'config': {
            'mcp_servers': {
              'helmy': {'url': tools},
            },
          },
        'cwd': launch.cwd,
        'approvalPolicy': approval,
        'sandbox': sandbox,
        // Added to Codex's own instructions: it answers as Helmy.
        'developerInstructions': helmyIdentity,
        ..._provider,
      };
      final result = launch.resumeId == null
          ? await _rpc.request('thread/start', settings)
          : await _rpc.request('thread/resume', {
              'threadId': launch.resumeId,
              'excludeTurns': true,
              ...settings,
            });
      _threadId = (result['thread'] as Map?)?['id'] as String?;
      status.resumeId = _threadId;
      _changes.add(false);
      return _threadId;
    } on Object catch (e) {
      _failure = 'Codex could not open the conversation: $e';
      _reducer.items.add(Notice(_failure!));
      _changes.add(false);
      await _rpc.close();
      return null;
    }
  }

  void _onMessage(Map<String, Object?> m) {
    final ended = _reducer.apply(m);
    final id = m['id'];
    final method = m['method'] as String? ?? '';
    if (id != null && !_handled.contains(method)) {
      _rpc.replyError(id, 'Not supported by this host');
    }
    status
      ..thinking = _reducer.thinking
      ..usage = _reducer.usage ?? status.usage
      ..context = _reducer.context ?? status.context;
    _changes.add(ended);
  }

  static const _handled = {
    'item/commandExecution/requestApproval',
    'item/fileChange/requestApproval',
    'item/tool/requestUserInput',
  };

  @override
  void send(String text, {List<String> attachments = const []}) =>
      unawaited(_send(text, attachments));

  Future<void> _send(String text, List<String> attachments) async {
    final images = [
      for (final a in attachments)
        if (imageType(a) != null) a,
    ];
    final files = [
      for (final a in attachments)
        if (imageType(a) == null) a,
    ];
    final threadId = await _ready;
    if (threadId == null) return;
    // "/name the rest": Codex is given the skill itself, and the rest as text.
    Map<String, Object?>? skill;
    final word = RegExp(r'^/([\w:.-]+)\s*').firstMatch(text);
    if (word != null) {
      final found = (await _skills()).where((s) => s.name == word.group(1)).firstOrNull;
      if (found?.path != null) {
        skill = {'type': 'skill', 'name': found!.name, 'path': found.path};
        text = text.substring(word.end);
      }
    }
    try {
      await _rpc.request('turn/start', {
        'threadId': threadId,
        'input': [
          ?skill,
          {'type': 'text', 'text': withFiles(text, files), 'text_elements': <Object>[]},
          for (final path in images) {'type': 'localImage', 'path': path},
        ],
      });
    } on Object catch (e) {
      // Said once, by the failed turn, with its cause and fix.
      _reducer.items.add(TurnSummary(ok: false, error: '$e')..endedAt = DateTime.now());
      _changes.add(true);
    }
  }

  /// `turn/steer`, held to the turn under way: if that turn has just
  /// ended, nothing is added and the message is sent as its own.
  @override
  Future<bool> steer(String text, {List<String> attachments = const []}) async {
    final threadId = _threadId, turnId = _reducer.turnId;
    if (threadId == null || turnId == null) return false;
    try {
      await _rpc.request('turn/steer', {
        'threadId': threadId,
        'expectedTurnId': turnId,
        'input': [
          {
            'type': 'text',
            'text': withFiles(text, [
              for (final a in attachments)
                if (imageType(a) == null) a,
            ]),
            'text_elements': <Object>[],
          },
          for (final a in attachments)
            if (imageType(a) != null) {'type': 'localImage', 'path': a},
        ],
      });
      return true;
    } on Object {
      return false;
    }
  }

  @override
  void interrupt() {
    final threadId = _threadId, turnId = _reducer.turnId;
    if (threadId == null || turnId == null) return;
    _rpc.request('turn/interrupt', {'threadId': threadId, 'turnId': turnId}).ignore();
  }

  Object _rpcId(String requestId) => int.tryParse(requestId) ?? requestId;

  @override
  void answer(PermissionPrompt prompt, PermissionAnswer answer) =>
      _rpc.reply(_rpcId(prompt.requestId), {
        'decision': switch (answer) {
          .allow => 'accept',
          .allowForSession => 'acceptForSession',
          .deny => 'decline',
        },
      });

  @override
  void answerQuestion(PermissionPrompt prompt) => _rpc.reply(_rpcId(prompt.requestId), {
    'answers': {
      for (final q in prompt.questions)
        '${q['id']}': {
          'answers': [?prompt.answers[q['question']]],
        },
    },
  });

  /// Codex does not leave work running between turns.
  @override
  void stopTask(String taskId) {}

  @override
  void compact() {
    final threadId = _threadId;
    if (threadId == null) return;
    _rpc.request('thread/compact/start', {'threadId': threadId}).ignore();
  }

  @override
  void setLevel(PermissionLevel level) {}

  @override
  Future<void> close() => _rpc.close();
}
