/// A tool server (MCP) added to Helmy itself: given to every connection, so
/// what it offers works whichever connection answers. Either an address it
/// is reached at, or a command Helmy starts.
class ToolServer {
  const ToolServer({required this.name, this.url, this.command, this.args = const []});

  /// What it is called, to Helmy and to the agents: lower case, no spaces.
  final String name;

  /// Reached over HTTP at this address.
  final String? url;

  /// Or started as this command, with [args], speaking over its stdin.
  final String? command;
  final List<String> args;

  Map<String, Object?> toJson() => {
    'name': name,
    'url': ?url,
    'command': ?command,
    if (args.isNotEmpty) 'args': args,
  };

  static ToolServer? fromJson(Object? j) {
    if (j is! Map || j['name'] is! String) return null;
    final url = j['url'] as String?, command = j['command'] as String?;
    if (url == null && command == null) return null;
    return ToolServer(
      name: j['name'] as String,
      url: url,
      command: command,
      args: [for (final a in (j['args'] as List?) ?? const []) '$a'],
    );
  }

  /// As Claude Code's --mcp-config has a server.
  Map<String, Object?> get forClaude => url != null
      ? {'type': 'http', 'url': url}
      : {'type': 'stdio', 'command': command, 'args': args};

  /// As Codex's mcp_servers setting has one.
  Map<String, Object?> get forCodex =>
      url != null ? {'url': url} : {'command': command, 'args': args};

  /// As the Agent Client Protocol's session/new has one; null where the
  /// agent cannot reach it that way.
  Map<String, Object?>? forAcp({required bool http}) => url != null
      ? (http ? {'type': 'http', 'name': name, 'url': url, 'headers': <Object>[]} : null)
      : {'name': name, 'command': command, 'args': args, 'env': <Object>[]};
}
