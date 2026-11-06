import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/services/chat_apps.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/theme.dart';

/// A chat app in the conversation: its page at its full height, with its
/// state from the chat and kept there, so it comes back as it was. Kept
/// alive while the conversation scrolls.
class ChatAppView extends StatefulWidget {
  const ChatAppView({
    super.key,
    required this.apps,
    required this.session,
    required this.path,
    required this.words,
  });

  final ChatApps apps;
  final String session;
  final String path;
  final String words;

  @override
  State<ChatAppView> createState() => _ChatAppViewState();
}

class _ChatAppViewState extends State<ChatAppView> with AutomaticKeepAliveClientMixin {
  final _c = WebViewController();
  StreamSubscription<AppChange>? _changes;
  double _height = 360;
  bool _ready = false;
  String? _trouble;

  /// The state as the page last had it, to tell its own saves coming back.
  String _last = 'null';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_c.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(_c.addJavaScriptChannel('HelmyApp', onMessageReceived: (m) => _fromPage(m.message)));
    _changes = widget.apps.changes.listen(_changed);
    unawaited(_load());
  }

  Future<void> _load() async {
    final page = await widget.apps.page(widget.session, widget.path);
    if (!mounted) return;
    if (page == null) {
      setState(() => _trouble = 'This app is no longer here.');
      return;
    }
    final state = await widget.apps.state(widget.session, widget.path);
    if (!mounted) return;
    _last = jsonEncode(state);
    final dir = widget.path.substring(0, widget.path.lastIndexOf('/') + 1);
    await _c.loadHtmlString(withBridge(page, _last), baseUrl: Uri.file(dir).toString());
    if (mounted) setState(() => _ready = true);
  }

  void _fromPage(String message) {
    final Object? m;
    try {
      m = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (m is! Map) return;
    if (m['height'] case final num h when h > 0) {
      final next = h.toDouble().clamp(120.0, 1400.0);
      if ((next - _height).abs() > 1 && mounted) setState(() => _height = next);
    }
    if (m.containsKey('save')) {
      _last = jsonEncode(m['save']);
      unawaited(widget.apps.save(widget.session, widget.path, m['save']));
    }
    if (m['say'] case final String text when text.trim().isNotEmpty) {
      unawaited(widget.apps.say(widget.session, widget.path, text));
    }
  }

  void _changed(AppChange a) {
    if (a.path != widget.path || a.session != widget.session) return;
    if (a.page) {
      setState(() => _ready = false);
      unawaited(_load());
      return;
    }
    final next = jsonEncode(a.state);
    if (next == _last) return;
    _last = next;
    unawaited(_c.runJavaScript('window.helmy && window.helmy._set($next);'));
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = AshlarTheme.of(context);
    return Container(
      height: _trouble != null ? null : _height,
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: ClipRRect(
        borderRadius: .circular(t.radiusLg - 1),
        child: _trouble != null
            ? Padding(
                padding: const .all(12),
                child: Text(
                  '${widget.words}: $_trouble',
                  style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                ),
              )
            : Stack(
                children: [
                  WebViewWidget(controller: _c),
                  if (!_ready) const Center(child: Spinner(size: 16)),
                ],
              ),
      ),
    );
  }
}

/// [page] with `window.helmy` set up before its own scripts, starting from
/// [stateJson]; and its height told to the chat, measured by its content.
String withBridge(String page, String stateJson) {
  final bridge =
      '''
<script>
(function () {
  var state = $stateJson, subs = [];
  function post(m) { try { window.webkit.messageHandlers.HelmyApp.postMessage(JSON.stringify(m)); } catch (e) { try { HelmyApp.postMessage(JSON.stringify(m)); } catch (e2) {} } }
  window.helmy = {
    get state() { return state; },
    save: function (s) { state = s === undefined ? null : JSON.parse(JSON.stringify(s)); post({ save: state }); },
    say: function (t) { post({ say: String(t) }); },
    onState: function (f) { subs.push(f); },
    _set: function (s) { state = s; subs.forEach(function (f) { try { f(s); } catch (e) { console.error(e); } }); }
  };
  var last = 0;
  function measure() {
    var b = document.body; if (!b) return;
    var h = Math.ceil(b.getBoundingClientRect().height + parseFloat(getComputedStyle(b).marginTop) + parseFloat(getComputedStyle(b).marginBottom));
    if (Math.abs(h - last) > 1) { last = h; post({ height: h }); }
  }
  document.addEventListener('DOMContentLoaded', function () {
    measure();
    if (window.ResizeObserver) new ResizeObserver(measure).observe(document.body);
  });
  window.addEventListener('load', measure);
})();
</script>
<style>html, body { height: auto !important; min-height: 0 !important; overflow: hidden; }</style>
''';
  final head = RegExp('<head[^>]*>', caseSensitive: false).firstMatch(page);
  if (head != null) return page.replaceRange(head.end, head.end, bridge);
  final html = RegExp('<html[^>]*>', caseSensitive: false).firstMatch(page);
  if (html != null) return page.replaceRange(html.end, html.end, '<head>$bridge</head>');
  return '<!doctype html><head>$bridge</head>$page';
}
