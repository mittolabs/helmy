import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../utils/platform.dart';
import 'watch_service.dart';

/// Helmy's own tools, given to every connection: a small MCP server on this
/// computer only (127.0.0.1, at an address with a secret in it), speaking
/// MCP's plain JSON over HTTP. Its one tool now: watch a video.
class HelmyTools {
  HelmyTools(this._watch);
  final WatchService _watch;

  /// The app's, set where it is put together; null in tests, and then the
  /// connections start without Helmy's tools.
  static HelmyTools? current;

  HttpServer? _server;
  final _secret = List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join();

  /// The server's address, started on first ask; null when it cannot start.
  Future<String?> get url => _url ??= _start();
  Future<String?>? _url;

  /// The tool names as each connection sees them, to allow without asking:
  /// they only look.
  static const claudeTools = ['mcp__helmy__watch_video'];

  Future<String?> _start() async {
    try {
      final server = _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) => unawaited(_handle(r)));
      return 'http://127.0.0.1:${server.port}/mcp/$_secret';
    } on Object {
      return null;
    }
  }

  Future<void> close() async => _server?.close(force: true);

  Future<void> _handle(HttpRequest r) async {
    final res = r.response;
    try {
      if (r.uri.path != '/mcp/$_secret') {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      if (r.method != 'POST') {
        res.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final message = jsonDecode(await utf8.decodeStream(r)) as Map<String, Object?>;
      final id = message['id'];
      // A notification asks nothing back.
      if (id == null) {
        res.statusCode = HttpStatus.accepted;
        return;
      }
      final reply = await answer('${message['method']}', (message['params'] as Map?) ?? const {});
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'jsonrpc': '2.0', 'id': id, ...reply}));
    } on Object catch (e) {
      res.statusCode = HttpStatus.badRequest;
      res.write(jsonEncode({'error': '$e'}));
    } finally {
      await res.close();
    }
  }

  /// The answer to one request: `{result: ...}` or `{error: ...}`.
  Future<Map<String, Object?>> answer(String method, Map params) async => switch (method) {
    'initialize' => {
      'result': {
        'protocolVersion': params['protocolVersion'] ?? '2025-06-18',
        'capabilities': {'tools': <String, Object?>{}},
        'serverInfo': {'name': 'helmy', 'version': '1'},
      },
    },
    'ping' => {'result': <String, Object?>{}},
    'tools/list' => {
      'result': {
        'tools': [
          {
            'name': 'watch_video',
            'description':
                'Watch a video on this computer: see frames spread across it, with when each '
                'is, and hear what is said in it, as text with where each part starts. Use it '
                'whenever you are asked to watch, look at, describe or check a video, or what '
                'happens or is said in it. Give the full path.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'path': {'type': 'string', 'description': 'The video file, as a full path.'},
              },
              'required': ['path'],
            },
            'annotations': {'readOnlyHint': true, 'title': 'Watch a video'},
          },
        ],
      },
    },
    'tools/call' => {'result': await _call(params)},
    _ => {
      'error': {'code': -32601, 'message': 'No such method: $method'},
    },
  };

  Future<Map<String, Object?>> _call(Map params) async {
    Map<String, Object?> says(String text, {bool error = false}) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
      'isError': error,
    };
    if (params['name'] != 'watch_video') return says('No such tool.', error: true);
    var path = '${(params['arguments'] as Map?)?['path'] ?? ''}'.trim();
    if (path.startsWith('~')) path = '$homeDir${path.substring(1)}';
    if (path.isEmpty || !File(path).existsSync()) return says('No file at $path.', error: true);
    if (await _watch.unavailableReason() case final why?) return says(why, error: true);
    final seen = await _watch.watch(path);
    if (seen == null) return says("$path isn't a video that can be read.", error: true);
    String time(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    final about = [
      'Watched ${path.split(Platform.pathSeparator).last}: ${time(seen.length)} long, '
          '${seen.width}x${seen.height}, ${seen.frames.length} frames below, each with when it is.',
      if (!seen.hasSound)
        'It has no sound.'
      else if (seen.transcript != null)
        'What is said:\n${seen.transcript}'
      else
        'It has sound, but the words could not be made out here: ${seen.heard}.',
    ].join('\n\n');
    return {
      'content': [
        {'type': 'text', 'text': about},
        for (final f in seen.frames) ...[
          {'type': 'text', 'text': 'At ${time(f.at)}:'},
          {
            'type': 'image',
            'mimeType': 'image/jpeg',
            'data': base64Encode(File(f.path).readAsBytesSync()),
          },
        ],
      ],
      'isError': false,
    };
  }
}
