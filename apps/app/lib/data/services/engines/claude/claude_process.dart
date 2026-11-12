import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One long-lived `claude -p` process speaking stream-json both ways, with
/// tool approvals routed to us over stdio (the protocol the Agent SDK uses).
class ClaudeProcess {
  new _(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _onDone);
    _process.stderr.transform(utf8.decoder).listen((s) {
      _stderr.write(s);
      if (_stderr.length > 8000) {
        final tail = _stderr.toString().substring(_stderr.length - 4000);
        _stderr
          ..clear()
          ..write(tail);
      }
    });
    _process.exitCode.then((code) => _exitCode = code);
  }

  static Future<ClaudeProcess> start({
    required String binary,
    required Map<String, String> environment,
    required String cwd,
    required String permissionMode,
    String? resume,
    String? model,

    /// How hard it thinks (low to max); null for its own default.
    String? effort,

    /// Settings beside the person's own, as --settings takes them.
    Map<String, Object?>? settings,
    String? appendSystemPrompt,

    /// Helmy's own tools, an MCP server's address, and the tools from it to
    /// allow without asking.
    String? toolsUrl,
    List<String> allowedTools = const [],

    /// Tool servers added to Helmy, beside its own, as --mcp-config has them.
    Map<String, Object?> servers = const {},

    /// Helmy's skills, as a plugin folder (SkillStore.pluginDir).
    String? pluginDir,
  }) async {
    final process = await Process.start(
      binary,
      [
        '-p',
        '--input-format', 'stream-json',
        '--output-format', 'stream-json',
        '--verbose',
        '--include-partial-messages',
        '--permission-prompt-tool', 'stdio',
        '--permission-mode', permissionMode,
        // Lets the mode be switched to bypass later without a restart.
        '--allow-dangerously-skip-permissions',
        if (resume != null) ...['--resume', resume],
        if (model != null) ...['--model', model],
        if (effort != null) ...['--effort', effort],
        if (settings != null) ...['--settings', jsonEncode(settings)],
        if (appendSystemPrompt != null) ...['--append-system-prompt', appendSystemPrompt],
        if (pluginDir != null) ...['--plugin-dir', pluginDir],
        if (toolsUrl != null || servers.isNotEmpty) ...[
          '--mcp-config',
          jsonEncode({
            'mcpServers': {
              ...servers,
              if (toolsUrl != null) 'helmy': {'type': 'http', 'url': toolsUrl},
            },
          }),
          if (allowedTools.isNotEmpty) ...['--allowedTools', allowedTools.join(',')],
        ],
      ],
      workingDirectory: cwd,
      environment: environment,
      includeParentEnvironment: false,
    );
    final claude = ClaudeProcess._(process);
    claude.sendControl({'subtype': 'initialize'});
    return claude;
  }

  final Process _process;
  final _messages = StreamController<Map<String, Object?>>.broadcast();
  final _stderr = StringBuffer();
  int? _exitCode;
  int _requests = 0;
  bool _closed = false;

  /// Every JSON line the CLI writes, in order. Closes when the process exits.
  Stream<Map<String, Object?>> get messages => _messages.stream;
  String get stderrTail => _stderr.toString();
  int? get exitCode => _exitCode;
  bool get isClosed => _closed;

  /// [content] is the message's text, or a list of content blocks.
  void sendUser(Object content) => _write({
    'type': 'user',
    'message': {'role': 'user', 'content': content},
    'parent_tool_use_id': null,
    'session_id': '',
  });

  void sendControl(Map<String, Object?> request) =>
      _write({'type': 'control_request', 'request_id': 'helmy-${++_requests}', 'request': request});

  void respond(String requestId, Map<String, Object?> response) => _write({
    'type': 'control_response',
    'response': {'subtype': 'success', 'request_id': requestId, 'response': response},
  });

  void respondError(String requestId, String error) => _write({
    'type': 'control_response',
    'response': {'subtype': 'error', 'request_id': requestId, 'error': error},
  });

  void interrupt() => sendControl({'subtype': 'interrupt'});

  void setPermissionMode(String mode) =>
      sendControl({'subtype': 'set_permission_mode', 'mode': mode});

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _process.stdin.close().catchError((_) {});
    // Give it a moment to save the session, then make sure it is gone.
    await _process.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        _process.kill();
        return -1;
      },
    );
  }

  void _write(Map<String, Object?> message) {
    if (_closed) return;
    _process.stdin.writeln(jsonEncode(message));
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map) _messages.add(decoded.cast<String, Object?>());
    } on FormatException {
      _stderr.writeln(line);
    }
  }

  Future<void> _onDone() async {
    _closed = true;
    _exitCode ??= await _process.exitCode;
    await _messages.close();
  }
}
