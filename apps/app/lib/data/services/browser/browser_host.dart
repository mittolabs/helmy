import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../chromium/chromium_service.dart';
import '../chromium/chromium_tab.dart';

/// A page an agent can work: the one in a session's Preview panel, or one
/// in the background when that panel is not on screen.
abstract class PageDriver {
  /// Runs [script], an expression that may be a promise; its value, as JSON
  /// decodes it.
  Future<Object?> eval(String script);
  Future<void> navigate(String url);
  Future<void> back();
  String get url;

  /// Real input, where the engine has it (Chromium); null where it has not,
  /// and actions are done in the page instead (the built-in browser).
  Future<void> Function(double x, double y)? get click;
  Future<void> Function(String text)? get typeText;
  Future<void> Function(String key)? get press;

  Future<Uint8List?> screenshot();
}

/// Which page each session's agent works, and how to open one.
class BrowserHost {
  BrowserHost({this.chromium});

  /// For a page in the background, when a session's panel is not on screen.
  final ChromiumService? chromium;

  final _pages = <String, PageDriver>{};
  final _openers = <String, void Function(String url)>{};
  final _attached = StreamController<String>.broadcast();
  final _background = <String, PageDriver>{};
  final _devices = <String, void Function({bool mac})>{};

  /// How a session shows its Device panel, while its conversation is on screen.
  void deviceOpener(String session, void Function({bool mac})? open) =>
      open == null ? _devices.remove(session) : _devices[session] = open;

  /// Shows the session's Device panel, on This Mac with [mac]; false when its
  /// conversation is not on screen.
  bool showDevice(String? session, {bool mac = false}) {
    final open = session == null || session.isEmpty
        ? _devices.values.lastOrNull
        : _devices[session];
    open?.call(mac: mac);
    return open != null;
  }

  /// A session's Preview panel shows a page the agent can work.
  void attach(String session, PageDriver page) {
    _pages[session] = page;
    _attached.add(session);
  }

  void detach(String session, PageDriver page) {
    if (_pages[session] == page) _pages.remove(session);
  }

  /// How a session opens its Preview panel at an address, while its
  /// conversation is on screen.
  void opener(String session, void Function(String url)? open) =>
      open == null ? _openers.remove(session) : _openers[session] = open;

  /// The page the session's agent works now, if any.
  PageDriver? pageFor(String? session) =>
      session == null ? _pages.values.lastOrNull : (_pages[session] ?? _background[session]);

  /// A page at [url] for the session: its panel opened there when its
  /// conversation is on screen, else a page in the background.
  Future<PageDriver?> open(String? session, String url) async {
    final s = session ?? '';
    final opener = _openers[s];
    if (opener != null) {
      final current = _pages[s];
      if (current != null) {
        await current.navigate(url);
        return current;
      }
      final ready = _attached.stream.firstWhere((x) => x == s).timeout(const Duration(seconds: 20));
      opener(url);
      try {
        await ready;
      } on TimeoutException {
        return null;
      }
      return _pages[s];
    }
    final service = chromium;
    final browser = await service?.pick(null);
    if (service == null || browser == null) return null;
    final page = _background[s] ??= _ChromiumDriver(
      await service.open(browser)
        ..mobile = false,
    );
    await (page as _ChromiumDriver).tab.show(1280, 800, 1);
    await page.navigate(url);
    return page;
  }

  static String? _script;
  static Future<String> script() async =>
      _script ??= await rootBundle.loadString('assets/helmy/browse.js');
}

/// A page in Chromium, driven over its DevTools protocol: real clicks, keys
/// and typing.
class _ChromiumDriver implements PageDriver {
  _ChromiumDriver(this.tab);
  final ChromiumTab tab;

  @override
  String get url => tab.url;

  @override
  Future<Object?> eval(String script) => chromiumEval(tab, script);

  @override
  Future<void> navigate(String url) => tab.navigate(url);

  @override
  Future<void> back() => tab.go(-1);

  @override
  Future<void> Function(double x, double y) get click =>
      (x, y) => chromiumClick(tab, x, y);

  @override
  Future<void> Function(String text) get typeText => tab.type;

  @override
  Future<void> Function(String key) get press =>
      (k) => chromiumPress(tab, k);

  @override
  Future<Uint8List?> screenshot() => tab.screenshot();
}

/// [script]'s value in a Chromium page, awaited and decoded.
Future<Object?> chromiumEval(ChromiumTab tab, String script) async {
  final out = await tab.evaluate(
    '(async () => JSON.stringify(await ($script) ?? null))()',
    awaitPromise: true,
  );
  return out is String ? jsonDecode(out) : out;
}

/// A real click at a point of the page (in its own pixels).
Future<void> chromiumClick(ChromiumTab tab, double x, double y) async {
  final zx = x * tab.zoom, zy = y * tab.zoom;
  await tab.mouse('mouseMoved', zx, zy);
  await tab.mouse('mousePressed', zx, zy, button: 'left', clickCount: 1);
  await tab.mouse('mouseReleased', zx, zy, button: 'left', clickCount: 1);
}

/// A real key press, by its name: Enter, Tab, Escape, Backspace, an arrow.
Future<void> chromiumPress(ChromiumTab tab, String key) async {
  const codes = {
    'Enter': 13,
    'Tab': 9,
    'Escape': 27,
    'Backspace': 8,
    'Delete': 46,
    'ArrowLeft': 37,
    'ArrowUp': 38,
    'ArrowRight': 39,
    'ArrowDown': 40,
    'Home': 36,
    'End': 35,
    'PageUp': 33,
    'PageDown': 34,
    'Space': 32,
  };
  final code = codes[key];
  if (code == null) {
    await tab.type(key);
    return;
  }
  await tab.key(key == 'Space' ? ' ' : key, key, code);
}
