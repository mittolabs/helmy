import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../utils/platform.dart';
import 'browser/browser_tools.dart';
import 'devices.dart';
import 'watch_service.dart';

/// Helmy's own tools, given to every connection: a small MCP server on this
/// computer only (127.0.0.1, at an address with a secret in it), speaking
/// MCP's plain JSON over HTTP. Its tools: watch a video, and see and use a
/// simulator or emulator.
class HelmyTools {
  HelmyTools(this._watch, [this._devices, this._browser, this._showDevice]);
  final WatchService _watch;
  final DeviceService? _devices;
  final BrowserTools? _browser;

  /// Shows a session's Device panel; true when it could.
  final bool Function(String? session)? _showDevice;

  HttpServer? _server;
  final _secret = List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join();

  /// The server's address, started on first ask; null when it cannot start.
  Future<String?> get url => _url ??= _start();
  Future<String?>? _url;

  /// The address for one session's runs: its tools then know which session
  /// asks, for the page in that session's Preview panel.
  Future<String?> urlFor(String? session) async {
    final base = await url;
    if (base == null || session == null) return base;
    return '$base?session=${Uri.encodeQueryComponent(session)}';
  }

  /// The tool names as each connection sees them, to allow without asking:
  /// watching only looks, and the device tools act only on a simulator or
  /// emulator.
  static final claudeTools = [
    'mcp__helmy__watch_video',
    for (final t in deviceTools) 'mcp__helmy__$t',
    for (final t in BrowserTools.names) 'mcp__helmy__$t',
  ];

  static const deviceTools = [
    'device_list',
    'device_screen',
    'device_tap',
    'device_swipe',
    'device_type',
    'device_home',
  ];

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
      final reply = await answer(
        '${message['method']}',
        (message['params'] as Map?) ?? const {},
        session: r.uri.queryParameters['session'],
      );
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
  Future<Map<String, Object?>> answer(String method, Map params, {String? session}) async =>
      switch (method) {
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
              if (_devices != null) ..._deviceToolList,
              if (_browser != null) ...BrowserTools.list,
            ],
          },
        },
        'tools/call' => {'result': await _call(params, session)},
        _ => {
          'error': {'code': -32601, 'message': 'No such method: $method'},
        },
      };

  Future<Map<String, Object?>> _call(Map params, [String? session]) async {
    Map<String, Object?> says(String text, {bool error = false}) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
      'isError': error,
    };
    final name = '${params['name']}';
    if (BrowserTools.names.contains(name) && _browser != null) {
      return _browser.call(name, (params['arguments'] as Map?) ?? const {}, session);
    }
    if (deviceTools.contains(name) && _devices != null) {
      return _device(name, (params['arguments'] as Map?) ?? const {}, says, session);
    }
    if (name != 'watch_video') return says('No such tool.', error: true);
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
      else if ('${seen.heard}'.contains('not allowed'))
        'It has sound, but Helmy is not allowed to recognize speech on this computer, so '
            'what is said is unknown. Tell the user, and give them this link, which opens '
            'the setting: [Allow speech recognition](helmy://fix/allow-speech). Do not guess '
            'what is said.'
      else
        'It has sound, but the words could not be made out here: ${seen.heard}. Say so; '
            'do not guess what is said.',
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

  static Map<String, Object?> _tool(
    String name,
    String title,
    String description, {
    Map<String, Object?> properties = const {},
    List<String> required = const [],
    bool readOnly = false,
  }) => {
    'name': name,
    'description': description,
    'inputSchema': {
      'type': 'object',
      'properties': {
        'device': {
          'type': 'string',
          'description': 'The device id from device_list; the running one when left out.',
        },
        ...properties,
      },
      'required': required,
    },
    'annotations': {'readOnlyHint': readOnly, 'title': title},
  };

  static final _deviceToolList = [
    _tool(
      'device_list',
      'List devices',
      'The iOS simulators and Android emulators on this computer, which are running, and '
          'their ids. Use the device tools to try an app you built on a phone: see its '
          'screen, tap, swipe, type and go home.',
      readOnly: true,
    ),
    _tool(
      'device_screen',
      "See a device's screen",
      "A picture of the device's screen now, with its size in the units device_tap takes. "
          'Starts the device if it is not running.',
      readOnly: true,
    ),
    _tool(
      'device_tap',
      'Tap a device',
      'Taps the device at x, y: points on iOS, pixels on Android, as device_screen gives.',
      properties: {
        'x': {'type': 'number'},
        'y': {'type': 'number'},
      },
      required: ['x', 'y'],
    ),
    _tool(
      'device_swipe',
      'Swipe on a device',
      'Swipes from x1, y1 to x2, y2, in the units device_tap takes.',
      properties: {
        for (final k in ['x1', 'y1', 'x2', 'y2']) k: {'type': 'number'},
      },
      required: ['x1', 'y1', 'x2', 'y2'],
    ),
    _tool(
      'device_type',
      'Type on a device',
      'Types text into whatever has focus on the device.',
      properties: {
        'text': {'type': 'string'},
      },
      required: ['text'],
    ),
    _tool('device_home', 'Press home', "Presses the device's home button."),
  ];

  Future<Map<String, Object?>> _device(
    String name,
    Map args,
    Map<String, Object?> Function(String, {bool error}) says, [
    String? session,
  ]) async {
    final devices = _devices!;
    final all = await devices.list();
    if (name == 'device_list') {
      if (all.isEmpty) {
        return says(
          'There is no simulator or emulator here. Xcode brings iOS simulators; '
          'Android Studio, Android emulators.',
        );
      }
      return says(
        [
          for (final d in all)
            '${d.id}: ${d.name}${d.runtime.isEmpty ? '' : ' (${d.runtime})'}'
                '${d.booted ? ', running' : ''}',
        ].join('\n'),
      );
    }
    final wanted = args['device'] as String?;
    var d = wanted == null
        ? (all.where((x) => x.booted).firstOrNull ?? all.firstOrNull)
        : all.where((x) => x.id == wanted).firstOrNull;
    if (d == null) return says('No such device. device_list gives the ids.', error: true);
    if (!d.booted) {
      if (!await devices.boot(d)) return says("${d.name} didn't start.", error: true);
      d = Device(id: d.id, name: d.name, ios: d.ios, booted: true, runtime: d.runtime);
    }
    // The user sees what the agent does: the device in the session's panel.
    final shown = _showDevice?.call(session) ?? false;
    if (d.ios && name != 'device_screen' && !await devices.iosInput()) {
      return says(
        'Taps and typing on iOS simulators need AXe, which is not installed. Tell the user, '
        'and give them this link, which installs it: '
        '[Install AXe](helmy://fix/install-device-input). Seeing the screen works without it.',
        error: true,
      );
    }
    double n(String k) => (args[k] as num?)?.toDouble() ?? 0;
    final bool ok;
    switch (name) {
      case 'device_screen':
        final bytes = await devices.screen(d);
        if (bytes == null) return says("${d.name}'s screen can't be read.", error: true);
        final size = imageSize(bytes);
        final scale = d.ios && size != null ? (size.$1 >= 1000 ? 3 : 2) : 1;
        final png = bytes.length > 3 && bytes[1] == 0x50;
        return {
          'content': [
            {
              'type': 'text',
              'text':
                  (size == null
                      ? '${d.name} now.'
                      : '${d.name} now: ${size.$1 ~/ scale} by ${size.$2 ~/ scale} '
                            '${d.ios ? 'points' : 'pixels'}, the units device_tap takes.') +
                  (shown
                      ? ' It shows live in the Device panel beside the conversation.'
                      : ' The Device panel is not on screen, so the user does not see it; '
                            'show them this picture if it matters.'),
            },
            {
              'type': 'image',
              'mimeType': png ? 'image/png' : 'image/jpeg',
              'data': base64Encode(bytes),
            },
          ],
          'isError': false,
        };
      case 'device_tap':
        ok = await devices.tap(d, n('x'), n('y'));
      case 'device_swipe':
        ok = await devices.swipe(d, (n('x1'), n('y1')), (n('x2'), n('y2')));
      case 'device_type':
        ok = await devices.type(d, '${args['text'] ?? ''}');
      default:
        ok = await devices.home(d);
    }
    return ok
        ? says(
            'Done. device_screen shows what it did.'
            '${shown ? ' The user sees it live in the Device panel.' : ''}',
          )
        : says("It didn't work.", error: true);
  }
}

/// The width and height of a PNG or JPEG, read from its header; null when
/// it is neither.
(int, int)? imageSize(List<int> b) {
  int be16(int i) => b[i] << 8 | b[i + 1];
  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
    return (be16(16) << 16 | be16(18), be16(20) << 16 | be16(22));
  }
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    // Start of frame: every SOFn but the DHT, JPG and DAC markers.
    if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
      return (be16(i + 7), be16(i + 5));
    }
    i += 2 + be16(i + 2);
  }
  return null;
}
