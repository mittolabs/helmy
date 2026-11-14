import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../../../domain/browser_page.dart';
import 'page_trouble.dart';

/// Whether this remote can take the page it is beside: in the extension,
/// where Chrome gives it tabs.
bool get pageHere => _chrome?.has('tabs') ?? false;

JSObject? get _chrome => globalContext.has('chrome') ? globalContext['chrome'] as JSObject : null;

extension type _Tab._(JSObject _) implements JSObject {
  external int? get id;
  external String? get url;
  external String? get title;
  external double? get lastAccessed;
}

extension type _Ran._(JSObject _) implements JSObject {
  external JSAny? get result;
}

@JS('chrome.tabs.query')
external JSPromise<JSArray<_Tab>> _tabs(JSAny query);

@JS('chrome.scripting.executeScript')
external JSPromise<JSArray<_Ran>> _run(JSAny injection);

@JS('chrome.tabs.getCurrent')
external JSPromise<_Tab?> _current();

/// The tab in front, in the window last used: its address and title, and
/// what page.js reads of it. Where Chrome lets an extension see a page's
/// address but not run in it (the Web Store), only the address and title.
/// Throws [PageTrouble] for a page Chrome keeps closed altogether (its own
/// settings and other pages); null with no tab at all.
Future<BrowserPage?> thisPage() async {
  if (!pageHere) return null;
  final front = (await _tabs({'active': true, 'lastFocusedWindow': true}.jsify()!).toDart).toDart;
  var tab = front.firstOrNull;
  // The panel opened as a tab of its own is in front: the page meant is the
  // one used last before it.
  final own = (await _current().toDart)?.id;
  if (tab != null && own != null && tab.id == own) {
    final others =
        (await _tabs(
            {'windowType': 'normal'}.jsify()!,
          ).toDart).toDart.where((t) => t.id != own && (t.url ?? '').isNotEmpty).toList()
          ..sort((a, b) => (b.lastAccessed ?? 0).compareTo(a.lastAccessed ?? 0));
    tab = others.firstOrNull;
  }
  if (tab == null) return null;
  final url = tab.url;
  // Chrome shows an extension the address of a page it may read: none is a
  // page of Chrome's own.
  if (url == null || url.isEmpty) {
    throw const PageTrouble(
      "Chrome keeps its own pages closed to extensions, so this one can't be sent.",
    );
  }
  try {
    final ran = (await _run(
      {
        'target': {'tabId': tab.id},
        'files': ['page.js'],
      }.jsify()!,
    ).toDart).toDart;
    final read = BrowserPage.fromJson(ran.firstOrNull?.result.dartify());
    if (read != null) return read;
  } on Object {
    // Seen but not read (the Web Store): where it is, and what it is called.
  }
  return BrowserPage(url: url, title: tab.title ?? '');
}
