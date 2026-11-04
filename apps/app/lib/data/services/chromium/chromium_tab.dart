import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'cdp.dart';

/// One page in the Chromium browser Preview drives: where it is, pictures of
/// it as it changes, and clicks, scrolling and typing sent to it.
class ChromiumTab {
  ChromiumTab(this._cdp, {required this.targetId, required this.session}) {
    _sub = _cdp.events.where((e) => e['sessionId'] == session).listen(_event);
  }

  final Cdp _cdp;
  final String targetId;
  final String session;
  late final StreamSubscription<Map<String, Object?>> _sub;

  final _frames = StreamController<Uint8List>.broadcast();
  final _urls = StreamController<String>.broadcast();

  /// Pictures of the page (JPEG), each as it changes.
  Stream<Uint8List> get frames => _frames.stream;

  /// Where the page is, each time it moves.
  Stream<String> get urls => _urls.stream;

  String url = 'about:blank';

  Future<Map<String, Object?>> _send(String method, [Map<String, Object?> params = const {}]) =>
      _cdp.send(method, params, session);

  Future<void> ready() async {
    await _send('Page.enable');
    await _send('Network.enable');
  }

  void _event(Map<String, Object?> e) {
    final params = (e['params'] as Map?)?.cast<String, Object?>() ?? const {};
    switch (e['method']) {
      case 'Page.screencastFrame':
        _frames.add(base64Decode('${params['data']}'));
        // Chromium sends the next picture once this one is taken.
        unawaited(_send('Page.screencastFrameAck', {'sessionId': params['sessionId']}));
      case 'Page.frameNavigated':
        final frame = params['frame'] as Map?;
        if (frame != null && frame['parentId'] == null) _moved('${frame['url']}');
      case 'Page.navigatedWithinDocument':
        _moved('${params['url']}');
    }
  }

  void _moved(String to) {
    url = to;
    _urls.add(to);
  }

  /// The page drawn at [width] by [height] points, at [scale] pixels a
  /// point, and pictures of it sent at that size.
  Future<void> show(double width, double height, double scale) async {
    final w = width.round(), h = height.round();
    if (w <= 0 || h <= 0) return;
    await _send('Emulation.setDeviceMetricsOverride', {
      'width': w,
      'height': h,
      'deviceScaleFactor': scale,
      'mobile': false,
    });
    await _send('Page.startScreencast', {
      'format': 'jpeg',
      'quality': 80,
      'maxWidth': (w * scale).round(),
      'maxHeight': (h * scale).round(),
    });
  }

  Future<void> navigate(String to) => _send('Page.navigate', {'url': to});

  Future<void> reload({bool skipCache = false}) => _send('Page.reload', {'ignoreCache': skipCache});

  /// Back ([by] -1) or forward (1) in the page's history.
  Future<void> go(int by) async {
    final h = await _send('Page.getNavigationHistory');
    final entries = (h['entries'] as List?) ?? const [];
    final at = (h['currentIndex'] as int? ?? 0) + by;
    if (at < 0 || at >= entries.length) return;
    await _send('Page.navigateToHistoryEntry', {'entryId': (entries[at] as Map)['id']});
  }

  /// Which mouse button and keys, as the protocol counts them.
  Future<void> mouse(
    String type,
    double x,
    double y, {
    String button = 'none',
    int clickCount = 0,
    int modifiers = 0,
  }) => _send('Input.dispatchMouseEvent', {
    'type': type,
    'x': x,
    'y': y,
    'button': button,
    'clickCount': clickCount,
    'modifiers': modifiers,
  });

  Future<void> scroll(double x, double y, double dx, double dy) => _send(
    'Input.dispatchMouseEvent',
    {'type': 'mouseWheel', 'x': x, 'y': y, 'deltaX': dx, 'deltaY': dy},
  );

  /// Text typed into whatever has focus.
  Future<void> type(String text) => _send('Input.insertText', {'text': text});

  /// A key with no text of its own (Enter, Backspace, an arrow), down and up.
  Future<void> key(String key, String code, int keyCode, {int modifiers = 0}) async {
    for (final type in ['rawKeyDown', 'keyUp']) {
      await _send('Input.dispatchKeyEvent', {
        'type': type,
        'key': key,
        'code': code,
        'windowsVirtualKeyCode': keyCode,
        'modifiers': modifiers,
        if (key == 'Enter' && type == 'rawKeyDown') 'text': '\r',
      });
    }
    if (key == 'Enter') await _send('Input.dispatchKeyEvent', {'type': 'char', 'text': '\r'});
  }

  /// The light or dark the page sees; null for the system's.
  Future<void> appearance(String? scheme) => _send('Emulation.setEmulatedMedia', {
    'features': [
      {'name': 'prefers-color-scheme', 'value': scheme ?? ''},
    ],
  });

  Future<void> clearCookies() => _send('Network.clearBrowserCookies');
  Future<void> clearCache() => _send('Network.clearBrowserCache');

  Future<void> close() async {
    await _sub.cancel();
    await _frames.close();
    await _urls.close();
    try {
      await _cdp.send('Target.closeTarget', {'targetId': targetId});
    } on Object {
      // The browser is gone already.
    }
  }
}
