import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../domain/models/chat_item.dart';
import '../../../../domain/models/engine.dart';
import '../../../../domain/models/memory.dart';
import '../../cli_locator.dart';
import '../agent_engine.dart';
import '../attachments.dart';
import 'claude_process.dart';
import 'claude_reducer.dart';

/// Claude Code, driven as `claude -p` over stream-json with approvals routed
/// to us: the protocol the Agent SDK uses.
class ClaudeEngine implements AgentEngine {
  /// One Claude Code login. [configDir] is the account's CLAUDE_CONFIG_DIR;
  /// null is the default account in ~/.claude.
  new(this._locator, {String id = 'claude', this.configDir})
    : info = EngineInfo(
        id: id,
        name: 'Claude Code ($id)',
        liveModeSwitch: true,
        capabilities: const {Capability.tools},
      );

  final CliLocator _locator;
  final String? configDir;

  @override
  final EngineInfo info;

  static final _accountFolder = RegExp(r'^\.claude-[A-Za-z0-9_-]+$');

  /// Every Claude Code account on this machine: ~/.claude, and each
  /// `~/.claude-<name>` folder as the account `claude-<name>`, the way a shell
  /// function setting CLAUDE_CONFIG_DIR makes one.
  static List<ClaudeEngine> discover(CliLocator locator, String home) {
    final accounts = [ClaudeEngine(locator)];
    final dir = Directory(home);
    if (home.isEmpty || !dir.existsSync()) return accounts;
    final folders =
        dir
            .listSync()
            .whereType<Directory>()
            .map((d) => d.path.split('/').last)
            .where(_accountFolder.hasMatch)
            .toList()
          ..sort();
    for (final name in folders) {
      accounts.add(ClaudeEngine(locator, id: name.substring(1), configDir: '$home/$name'));
    }
    return accounts;
  }

  /// Helmy's levels in Claude Code's permission modes.
  static String mode(PermissionLevel level) => switch (level) {
    .ask => 'default',
    .edit => 'acceptEdits',
    .readOnly => 'plan',
    .full => 'bypassPermissions',
  };

  String get _home => configDir ?? '${Platform.environment['HOME']}/.claude';

  /// The account's own CLAUDE.md, and the memory notes Claude Code writes for
  /// each project under `projects/<folder>/memory`.
  @override
  Future<List<MemoryFile>> memoryFiles() async {
    final files = [
      MemoryFile(
        engineId: info.id,
        path: '$_home/CLAUDE.md',
        kind: 'Instructions for every project',
      ),
    ];
    final projects = Directory('$_home/projects');
    if (!projects.existsSync()) return files;
    final dirs = projects.listSync().whereType<Directory>().toList()
      ..sort(
        (a, b) =>
            projectFolder(a.path.split('/').last).compareTo(projectFolder(b.path.split('/').last)),
      );
    for (final dir in dirs) {
      final memory = Directory('${dir.path}/memory');
      if (!memory.existsSync()) continue;
      final project = projectFolder(dir.path.split('/').last);
      final notes =
          memory.listSync().whereType<File>().where((f) => f.path.endsWith('.md')).toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final note in notes) {
        files.add(
          MemoryFile(engineId: info.id, path: note.path, kind: 'Project memory', project: project),
        );
      }
    }
    return files;
  }

  @override
  Future<List<MemoryNote>> memoryNotes() async => const [];

  ({DateTime at, List<({String name, String status})> list})? _servers;

  /// The account's MCP servers, its claude.ai connectors among them, asked of
  /// Claude Code with `mcp_status` after giving them a few seconds to connect.
  /// Kept ten minutes, since asking starts a process.
  @override
  Future<Set<Capability>> connected() async => connectedOf(await servers());

  @override
  Future<List<({String name, String status})>> servers() async {
    final cached = _servers;
    if (cached != null && DateTime.now().difference(cached.at).inMinutes < 10) return cached.list;
    final binary = await _locator.find('claude');
    if (binary == null) return const [];
    try {
      final process = await ClaudeProcess.start(
        binary: binary,
        environment: {...await _locator.environment(), 'CLAUDE_CONFIG_DIR': ?configDir},
        cwd: Directory.systemTemp.path,
        permissionMode: 'default',
      );
      await Future<void>.delayed(const Duration(seconds: 6));
      process.sendControl({'subtype': 'mcp_status'});
      final reply = await process.messages
          .firstWhere(
            (m) =>
                m['type'] == 'control_response' &&
                ((m['response'] as Map?)?['response'] as Map?)?['mcpServers'] != null,
          )
          .timeout(const Duration(seconds: 15));
      await process.close();
      final list = [
        for (final s
            in (((reply['response'] as Map)['response'] as Map)['mcpServers'] as List)
                .whereType<Map>())
          (name: '${s['name']}', status: '${s['status']}'),
      ];
      _servers = (at: DateTime.now(), list: list);
      return list;
    } on Object {
      return _servers?.list ?? const [];
    }
  }

  /// Claude Code reports its usage only with an answer; there is nothing to
  /// ask it outside one.
  @override
  Future<Usage?> readUsage() async => null;

  final Map<String, Future<List<SlashCommand>>> _commands = {};

  /// The commands and skills Claude Code lists when it starts in [cwd]. A
  /// process is started for the asking, answers the handshake, and is ended;
  /// no message is sent, so nothing is spent.
  @override
  Future<List<SlashCommand>> commands(String cwd) =>
      _commands.putIfAbsent(cwd, () => _fetchCommands(cwd));

  Future<List<SlashCommand>> _fetchCommands(String cwd) async {
    final binary = await _locator.find('claude');
    if (binary == null) return const [];
    try {
      final process = await ClaudeProcess.start(
        binary: binary,
        environment: {...await _locator.environment(), 'CLAUDE_CONFIG_DIR': ?configDir},
        cwd: cwd,
        permissionMode: 'default',
      );
      final reply = await process.messages
          .firstWhere((m) => m['type'] == 'control_response')
          .timeout(const Duration(seconds: 20));
      await process.close();
      final list =
          (((reply['response'] as Map?)?['response'] as Map?)?['commands'] as List?) ?? const [];
      return [
        for (final c in list.whereType<Map>())
          SlashCommand(
            name: '${c['name']}',
            description: '${c['description'] ?? ''}',
            hint: (c['argumentHint'] as String?)?.isEmpty == true
                ? null
                : c['argumentHint'] as String?,
          ),
      ];
    } on Object {
      _commands.remove(cwd);
      return const [];
    }
  }

  /// Claude Code names a project's folder by its path with every character that
  /// is not a letter or digit as a dash (/ . _ - space), so each dash could be
  /// any of them. Find the reading that is a
  /// folder on disk; when none is, leave the name as it is.
  static String projectFolder(String name) {
    final parts = name.split('-').where((p) => p.isNotEmpty).toList();
    String? walk(String dir, int i) {
      if (i == parts.length) return dir;
      // Take the next part alone, or joined to the ones after it by - or .
      var segment = parts[i];
      for (var j = i; j < parts.length; j++) {
        if (j > i) {
          for (final joiner in const ['-', '.', '_', ' ']) {
            final joined = '$segment$joiner${parts[j]}';
            final found = _descend(dir, joined, j, walk);
            if (found != null) return found;
          }
          segment = '$segment-${parts[j]}';
          continue;
        }
        final found = _descend(dir, segment, j, walk);
        if (found != null) return found;
      }
      return null;
    }

    return walk('', 0) ?? name;
  }

  static String? _descend(
    String dir,
    String segment,
    int last,
    String? Function(String, int) walk,
  ) {
    final path = '$dir/$segment';
    return Directory(path).existsSync() ? walk(path, last + 1) : null;
  }

  /// A fast model with the instructions as its whole system prompt and no
  /// tools or servers: measured at about 700 tokens in for a command.
  @override
  Future<String?> ask(String instructions, String question) async {
    final binary = await _locator.find('claude');
    if (binary == null) return null;
    try {
      final r = await Process.run(
        binary,
        [
          '-p',
          question,
          '--output-format',
          'json',
          '--model',
          'haiku',
          '--tools',
          '',
          '--system-prompt',
          instructions,
          '--strict-mcp-config',
          '--no-session-persistence',
          '--setting-sources',
          '',
        ],
        workingDirectory: Directory.systemTemp.path,
        environment: {...await _locator.environment(), 'CLAUDE_CONFIG_DIR': ?configDir},
        includeParentEnvironment: false,
      ).timeout(const Duration(seconds: 60));
      final json = jsonDecode('${r.stdout}') as Map;
      if (json['is_error'] == true) return null;
      final text = '${json['result'] ?? ''}'.trim();
      return text.isEmpty ? null : text;
    } on Object {
      return null;
    }
  }

  @override
  Future<String?> unavailableReason() async => await _locator.find('claude') == null
      ? 'Could not find the claude command. Install Claude Code and log in first.'
      : null;

  @override
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items) async {
    final binary = await _locator.find('claude');
    if (binary == null) throw StateError((await unavailableReason())!);
    final process = await ClaudeProcess.start(
      binary: binary,
      environment: {...await _locator.environment(), 'CLAUDE_CONFIG_DIR': ?configDir},
      cwd: launch.cwd,
      permissionMode: mode(launch.level),
      resume: launch.resumeId,
    );
    return _ClaudeRun(process, ClaudeReducer(items), launch.resumeId);
  }
}

class _ClaudeRun implements EngineRun {
  new(this._process, this._reducer, String? resumeId) {
    status.resumeId = resumeId;
    _process.messages.listen(_onMessage, onDone: _changes.close);
  }

  final ClaudeProcess _process;
  final ClaudeReducer _reducer;
  final _changes = StreamController<bool>.broadcast();

  @override
  final status = EngineStatus();

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  String? get exitDetail {
    final tail = _process.stderrTail.trim();
    final code = 'Claude Code exited (code ${_process.exitCode ?? '?'})';
    if (tail.isEmpty) return code;
    return '$code:\n${tail.length > 1500 ? tail.substring(tail.length - 1500) : tail}';
  }

  /// Whether a turn is under way, so one that begins unasked is noticed.
  bool _inTurn = false;

  void _onMessage(Map<String, Object?> m) {
    if (m['type'] == 'system' && m['subtype'] == 'init' && !_inTurn) {
      // Work left in the background ended, and the agent took it up.
      _inTurn = true;
      status.startedByItself = true;
    }
    final ended = _reducer.apply(m);
    if (ended) _inTurn = false;
    if (m['type'] == 'control_request') {
      final request = (m['request'] as Map).cast<String, Object?>();
      if (request['subtype'] != 'can_use_tool') {
        // Hooks and SDK-side MCP servers are not something this host offers.
        _process.respondError(m['request_id']! as String, 'Not supported by this host');
      }
    }
    status
      ..thinking = _reducer.thinking
      ..resumeId = _reducer.sessionId ?? status.resumeId
      ..usage = _reducer.usage ?? status.usage
      ..context = _reducer.context ?? status.context;
    _changes.add(ended);
  }

  @override
  void send(String text, {List<String> attachments = const []}) {
    _inTurn = true;
    if (attachments.isEmpty) return _process.sendUser(text);
    final images = [
      for (final a in attachments)
        if (imageType(a) != null) a,
    ];
    final files = [
      for (final a in attachments)
        if (imageType(a) == null) a,
    ];
    _process.sendUser([
      {'type': 'text', 'text': withFiles(text, files)},
      for (final path in images)
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': imageType(path),
            'data': base64Encode(File(path).readAsBytesSync()),
          },
        },
    ]);
  }

  @override
  void interrupt() => _process.interrupt();

  @override
  void answer(PermissionPrompt prompt, PermissionAnswer answer) {
    if (answer == .deny) {
      _process.respond(prompt.requestId, {
        'behavior': 'deny',
        'message': 'The user declined this tool call.',
      });
      return;
    }
    _process.respond(prompt.requestId, {
      'behavior': 'allow',
      'updatedInput': prompt.input,
      if (answer == .allowForSession && prompt.suggestions.isNotEmpty)
        'updatedPermissions': prompt.suggestions,
    });
  }

  @override
  void answerQuestion(PermissionPrompt prompt) => _process.respond(prompt.requestId, {
    'behavior': 'allow',
    'updatedInput': {...prompt.input, 'answers': prompt.answers},
  });

  /// Claude Code's own command for it.
  @override
  void compact() {
    _inTurn = true;
    _process.sendUser('/compact');
  }

  @override
  void stopTask(String taskId) => _process.sendControl({'subtype': 'stop_task', 'task_id': taskId});

  @override
  void setLevel(PermissionLevel level) => _process.setPermissionMode(ClaudeEngine.mode(level));

  @override
  Future<void> close() => _process.close();
}
