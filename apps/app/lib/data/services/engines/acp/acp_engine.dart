import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../domain/identity.dart';
import '../../../../domain/models/chat_item.dart';
import '../../../../domain/models/engine.dart';
import '../../../../domain/models/memory.dart';
import '../../../../domain/models/settings.dart';
import '../../cli_locator.dart';
import '../../helmy_tools.dart';
import '../agent_engine.dart';
import '../attachments.dart';
import 'acp_reducer.dart';
import 'acp_rpc.dart';
import '../../../../domain/models/tool_server.dart';

/// What checking an agent found: whether it opens a session, why not, and
/// the ways it can be signed in to.
typedef AcpCheck = ({bool ready, String? problem, List<Map<String, Object?>> signIns});

/// An agent just added, and what checking it found.
typedef AcpAdded = ({ConnectionAccount account, AcpCheck? check});

/// What Helmy knows of one agent beyond the protocol: which of its models
/// to use, and how its own settings carry Helmy's permission levels.
class const AcpProfile({
  /// The models Helmy picks, best first. When the agent offers none of
  /// them, it is not used: better no answer than one on a model whose terms
  /// were not chosen.
  final List<String> models = const [],

  /// What the agent is started with, for a level.
  final Map<String, String> Function(PermissionLevel)? environment,

  /// Why [models] are the ones, for the person reading Settings.
  final String? note,
});

/// OpenCode: only its free models whose makers keep nothing and do not
/// train on what is sent (opencode.ai/docs/zen, 2026-11-05). The others are
/// free so their makers can collect what people send.
final opencodeProfile = AcpProfile(
  models: const ['opencode/glm-5.3-flash-free', 'opencode/deepseek-v4.1-flash-free'],
  note: "Free models whose makers keep nothing and don't train on what is sent.",
  environment: (level) => {
    'OPENCODE_CONFIG_CONTENT': jsonEncode({
      'permission': switch (level) {
        .ask => {'edit': 'ask', 'bash': 'ask', 'webfetch': 'ask'},
        .edit => {'edit': 'allow', 'bash': 'ask', 'webfetch': 'allow'},
        .readOnly => {'edit': 'deny', 'bash': 'ask', 'webfetch': 'allow'},
        .full => {'edit': 'allow', 'bash': 'allow', 'webfetch': 'allow'},
      },
    }),
  },
);

/// The profile for an agent from the registry, by its registry id.
AcpProfile profileFor(String agentId) =>
    agentId.startsWith('opencode') ? opencodeProfile : const AcpProfile();

/// Any agent that speaks the Agent Client Protocol (agentclientprotocol.com),
/// started as [command] with [args]: one from the ACP registry, or a local
/// command. It says nothing of its usage limits or what it is good at, so
/// it answers only the kinds of work the user sets it best at.
class AcpEngine implements AgentEngine {
  new(
    this._locator, {
    required String id,
    required String name,
    required this.command,
    this.args = const [],
    this.profile = const AcpProfile(),
    this.tools,
  }) : info = EngineInfo(
         id: id,
         name: name,
         capabilities: const {Capability.tools},
         assignedOnly: true,
       );

  final CliLocator _locator;

  /// The program: a path, or a name found on the PATH (npx, uvx).
  final String command;
  final List<String> args;
  final AcpProfile profile;
  final HelmyTools? tools;

  @override
  final EngineInfo info;

  Future<String?> _program() async {
    if (command.contains('/')) return File(command).existsSync() ? command : null;
    return _locator.find(command);
  }

  Future<Map<String, String>> _environment(PermissionLevel level) async {
    final env = {...await _locator.environment(), ...?profile.environment?.call(level)};
    // OpenCode reads Helmy's skills from its `skills` setting (SkillStore).
    final skills = tools?.skills?.root;
    final config = env['OPENCODE_CONFIG_CONTENT'];
    if (skills != null && config != null) {
      final j = (jsonDecode(config) as Map).cast<String, Object?>();
      env['OPENCODE_CONFIG_CONTENT'] = jsonEncode({
        ...j,
        'skills': [...((j['skills'] as List?) ?? const []), skills],
      });
    }
    return env;
  }

  @override
  Future<String?> unavailableReason() async =>
      await _program() == null ? '${info.name} is not installed: $command was not found.' : null;

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

  /// Whether it starts and opens a session here, and if not why: the
  /// ways it can be signed in to, when that is what it needs.
  Future<AcpCheck> check() async {
    final program = await _program();
    if (program == null) {
      return (
        ready: false,
        problem: await unavailableReason(),
        signIns: const <Map<String, Object?>>[],
      );
    }
    final dir = await Directory.systemTemp.createTemp('helmy-check');
    AcpRpc? rpc;
    var signIns = const <Map<String, Object?>>[];
    try {
      rpc = await AcpRpc.start(
        command: program,
        args: args,
        environment: await _environment(.readOnly),
        cwd: dir.path,
      );
      final init = await rpc
          .request('initialize', {
            'protocolVersion': 1,
            'clientCapabilities': {
              'fs': {'readTextFile': false, 'writeTextFile': false},
              'terminal': false,
            },
            'clientInfo': {'name': 'Helmy', 'version': '0.1.0'},
          })
          .timeout(const Duration(minutes: 3));
      signIns = [
        for (final m in (init['authMethods'] as List? ?? const []).whereType<Map>())
          m.cast<String, Object?>(),
      ];
      final session = await rpc
          .request('session/new', {'cwd': dir.path, 'mcpServers': <Object>[]})
          .timeout(const Duration(minutes: 1));
      if (profile.models.isNotEmpty) {
        final offered = {
          for (final o in (session['configOptions'] as List? ?? const []).whereType<Map>())
            if (o['id'] == 'model')
              for (final v in (o['options'] as List? ?? const []).whereType<Map>()) '${v['value']}',
        };
        if (!profile.models.any(offered.contains)) {
          return (
            ready: false,
            problem:
                'It offers none of the models Helmy uses it with right now '
                '(${profile.models.join(', ')}), so Helmy will not send it anything.',
            signIns: const <Map<String, Object?>>[],
          );
        }
      }
      return (ready: true, problem: null, signIns: signIns);
    } on AcpError catch (e) {
      return (
        ready: false,
        problem: e.authRequired ? 'It needs signing in.' : 'It would not start a session: $e',
        signIns: signIns,
      );
    } on Object catch (e) {
      final tail = rpc?.stderrTail.trim() ?? '';
      return (
        ready: false,
        problem: 'It would not start: $e${tail.isEmpty ? '' : '\n$tail'}',
        signIns: signIns,
      );
    } finally {
      await rpc?.close();
      dir.delete(recursive: true).ignore();
    }
  }

  /// Signs in by [method], one of those [check] gave: the agent's own flow
  /// (it opens the browser), or its login in Terminal. True when it went.
  Future<bool> signIn(Map<String, Object?> method) async {
    final program = await _program();
    if (program == null) return false;
    if (method['type'] == 'terminal') {
      final env = (method['env'] as Map?)?.cast<String, Object?>() ?? {};
      final line = [
        for (final e in env.entries) '${e.key}=${_quote('${e.value}')}',
        _quote(program),
        for (final a in [
          ...args.where((a) => a != 'acp' && a != '--acp'),
          ...((method['args'] as List?) ?? const []),
        ])
          _quote('$a'),
      ].join(' ');
      final script = File(
        '${(await Directory.systemTemp.createTemp('helmy-login')).path}/sign-in.command',
      )..writeAsStringSync('#!/bin/zsh -l\n$line\n');
      await Process.run('/bin/chmod', ['+x', script.path]);
      return (await Process.run('/usr/bin/open', ['-a', 'Terminal', script.path])).exitCode == 0;
    }
    final dir = await Directory.systemTemp.createTemp('helmy-login');
    AcpRpc? rpc;
    try {
      rpc = await AcpRpc.start(
        command: program,
        args: args,
        environment: await _environment(.readOnly),
        cwd: dir.path,
      );
      await rpc.request('initialize', {
        'protocolVersion': 1,
        'clientCapabilities': <String, Object?>{},
        'clientInfo': {'name': 'Helmy', 'version': '0.1.0'},
      });
      await rpc
          .request('authenticate', {'methodId': method['id']})
          .timeout(const Duration(minutes: 10));
      return true;
    } on Object {
      return false;
    } finally {
      await rpc?.close();
      dir.delete(recursive: true).ignore();
    }
  }

  static String _quote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  /// A session in a folder of its own, read-only, its answer collected.
  @override
  Future<String?> ask(String instructions, String question) async {
    final dir = await Directory.systemTemp.createTemp('helmy-ask');
    final items = <ChatItem>[];
    EngineRun? run;
    try {
      run = await start(EngineLaunch(cwd: dir.path, level: .readOnly), items);
      final done = run.changes.firstWhere((ended) => ended);
      run.send('$instructions\n\n$question');
      await done.timeout(const Duration(seconds: 120));
      final text = items.whereType<AssistantText>().map((t) => t.text).join('\n').trim();
      return text.isEmpty ? null : text;
    } on Object {
      return null;
    } finally {
      await run?.close();
      dir.delete(recursive: true).ignore();
    }
  }

  @override
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items) async {
    final program = await _program();
    if (program == null) throw StateError((await unavailableReason())!);
    final rpc = await AcpRpc.start(
      command: program,
      args: args,
      environment: await _environment(launch.level),
      cwd: launch.cwd,
    );
    final run = _AcpRun(rpc, AcpReducer(items), info.name, profile);
    run._ready = run._open(
      launch,
      await tools?.urlFor(launch.sessionId),
      tools?.servers() ?? const [],
    );
    return run;
  }
}

class _AcpRun implements EngineRun {
  new(this._rpc, this._reducer, this._name, this._profile) {
    _rpc.incoming.listen(_onMessage, onDone: _changes.close);
  }

  final AcpRpc _rpc;
  final AcpReducer _reducer;
  final String _name;
  final AcpProfile _profile;
  final _changes = StreamController<bool>.broadcast();
  late Future<String?> _ready;
  String? _sessionId;

  /// Helmy's instructions go with the first message of a new session.
  String? _identity;

  /// While an old session is loaded, the agent replays it: not new.
  bool _replaying = false;

  @override
  final status = EngineStatus();

  @override
  Stream<bool> get changes => _changes.stream;

  String? _failure;

  @override
  String? get exitDetail {
    final tail = _rpc.stderrTail.trim();
    final head = _failure ?? '$_name exited (code ${_rpc.exitCode ?? '?'})';
    if (tail.isEmpty) return head;
    return '$head:\n${tail.length > 1500 ? tail.substring(tail.length - 1500) : tail}';
  }

  /// Starts or picks up the session. Null when that failed; why is in
  /// [exitDetail] and said in the chat.
  Future<String?> _open(EngineLaunch launch, String? toolsUrl, List<ToolServer> added) async {
    try {
      final init = await _rpc.request('initialize', {
        'protocolVersion': 1,
        'clientCapabilities': {
          'fs': {'readTextFile': false, 'writeTextFile': false},
          'terminal': false,
        },
        'clientInfo': {'name': 'Helmy', 'version': '0.1.0'},
      });
      final caps = (init['agentCapabilities'] as Map?)?.cast<String, Object?>() ?? {};
      final http = (caps['mcpCapabilities'] as Map?)?['http'] == true;
      final servers = [
        if (toolsUrl != null && http)
          {'type': 'http', 'name': 'helmy', 'url': toolsUrl, 'headers': <Object>[]},
        // Tool servers added to Helmy, those this agent can reach.
        for (final s in added) ?s.forAcp(http: http),
      ];
      final resumable = (caps['sessionCapabilities'] as Map?)?['resume'] != null;
      final Map<String, Object?> session;
      if (launch.resumeId case final id? when resumable) {
        session = await _rpc.request('session/resume', {
          'sessionId': id,
          'cwd': launch.cwd,
          'mcpServers': servers,
        });
        _sessionId = id;
      } else if (launch.resumeId case final id? when caps['loadSession'] == true) {
        _replaying = true;
        session = await _rpc.request('session/load', {
          'sessionId': id,
          'cwd': launch.cwd,
          'mcpServers': servers,
        });
        _replaying = false;
        _sessionId = id;
      } else {
        session = await _rpc.request('session/new', {'cwd': launch.cwd, 'mcpServers': servers});
        _sessionId = session['sessionId'] as String?;
        _identity = identityWith(launch.brief, lessons: launch.lessons);
      }
      await _choose(session, launch.level);
      status.resumeId = _sessionId;
      _changes.add(false);
      return _sessionId;
    } on Object catch (e) {
      _failure = e is AcpError && e.authRequired
          ? '$_name needs signing in first. Sign it in from Settings > Connections.'
          : '$_name could not open the conversation: $e';
      _reducer.items.add(Notice(_failure!, details: _rpc.stderrTail));
      _changes.add(false);
      await _rpc.close();
      return null;
    }
  }

  /// Sets the model the profile names, and a read-only mode for read-only.
  Future<void> _choose(Map<String, Object?> session, PermissionLevel level) async {
    final options = [
      for (final o in (session['configOptions'] as List? ?? const []).whereType<Map>())
        o.cast<String, Object?>(),
    ];
    _reducer.configOptions = options;
    Set<String> valuesOf(String id) => {
      for (final o in options)
        if (o['id'] == id)
          for (final v in (o['options'] as List? ?? const []).whereType<Map>()) '${v['value']}',
    };
    if (_profile.models.isNotEmpty) {
      final offered = valuesOf('model');
      final model = _profile.models.where(offered.contains).firstOrNull;
      if (model == null) {
        throw AcpError(
          'none of the models Helmy uses it with is offered now '
          '(${_profile.models.join(', ')})',
        );
      }
      await _setOption('model', model);
    }
    if (level == .readOnly && valuesOf('mode').contains('plan')) await _setOption('mode', 'plan');
  }

  Future<void> _setOption(String id, String value) => _rpc.request('session/set_config_option', {
    'sessionId': _sessionId,
    'configId': id,
    'value': value,
  });

  void _onMessage(Map<String, Object?> m) {
    if (_replaying && m['method'] == 'session/update') return;
    _reducer.apply(m);
    final id = m['id'];
    if (id != null && m['method'] != 'session/request_permission') {
      _rpc.replyError(id, -32601, 'Not supported by this client');
    }
    status
      ..thinking = _reducer.thinking
      ..context = _reducer.context ?? status.context;
    _changes.add(false);
  }

  @override
  void send(String text, {List<String> attachments = const []}) =>
      unawaited(_send(text, attachments));

  Future<void> _send(String text, List<String> attachments) async {
    final sessionId = await _ready;
    if (sessionId == null) {
      _changes.add(true);
      return;
    }
    final identity = _identity;
    _identity = null;
    status.thinking = true;
    _changes.add(false);
    try {
      final result = await _rpc.request('session/prompt', {
        'sessionId': sessionId,
        'prompt': [
          if (identity != null)
            {'type': 'text', 'text': '<instructions>\n$identity\n</instructions>'},
          {'type': 'text', 'text': withFiles(text, attachments)},
        ],
      });
      _reducer.ended(stopReason: result['stopReason'] as String?);
    } on Object catch (e) {
      _reducer.ended(error: '$e');
    }
    status.thinking = false;
    _changes.add(true);
  }

  /// The protocol has no way to add to a turn under way.
  @override
  Future<bool> steer(String text, {List<String> attachments = const []}) async => false;

  @override
  void interrupt() {
    final id = _sessionId;
    if (id != null) _rpc.notify('session/cancel', {'sessionId': id});
  }

  Object _rpcId(String requestId) => int.tryParse(requestId) ?? requestId;

  /// Picks the agent's own option of the kind answered: once, always, or
  /// no. Cancelled when it offered none of that kind.
  @override
  void answer(PermissionPrompt prompt, PermissionAnswer answer, {String? why}) {
    final kinds = switch (answer) {
      .allow => ['allow_once', 'allow_always'],
      .allowForSession => ['allow_always', 'allow_once'],
      .deny => ['reject_once', 'reject_always'],
    };
    final options = prompt.suggestions.whereType<Map>().toList();
    final chosen = [for (final k in kinds) ...options.where((o) => o['kind'] == k)].firstOrNull;
    _rpc.reply(_rpcId(prompt.requestId), {
      'outcome': chosen == null
          ? {'outcome': 'cancelled'}
          : {'outcome': 'selected', 'optionId': chosen['optionId']},
    });
  }

  @override
  void answerQuestion(PermissionPrompt prompt) => _rpc.reply(_rpcId(prompt.requestId), {
    'outcome': {'outcome': 'cancelled'},
  });

  @override
  void stopTask(String taskId) {}

  /// Its own /compact, where it offers one.
  @override
  void compact() {
    if (_reducer.commands.any((c) => c.name == 'compact')) send('/compact');
  }

  @override
  void setLevel(PermissionLevel level) {}

  @override
  Future<void> close() => _rpc.close();
}
