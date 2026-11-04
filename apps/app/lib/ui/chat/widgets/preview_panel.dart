import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../utils/platform.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/dropdown_menu.dart';
import '../../core/ashlar/input.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../view_models/chat_view_model.dart';

/// What was typed in the address, as somewhere to go: an address as it is, a
/// host without its scheme (localhost over http), or else a search.
String addressFor(String typed) {
  final s = typed.trim();
  if (RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(s)) return s;
  if (RegExp(r'^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?(/.*)?$').hasMatch(s)) return 'http://$s';
  if (!s.contains(' ') &&
      RegExp(r'^[^/\s]+\.[a-z]{2,}(:\d+)?(/.*)?$', caseSensitive: false).hasMatch(s)) {
    return 'https://$s';
  }
  return 'https://duckduckgo.com/?q=${Uri.encodeQueryComponent(s)}';
}

/// Beside the conversation: the page an answer pointed at, a running app on
/// this computer, or a document, live in a web view you can click through.
/// The address can be typed into; the menu has the page's inspector, a reload
/// past the cache, its zoom and appearance, and clearing what it stored.
class PreviewPanel extends StatefulWidget {
  const PreviewPanel({super.key, required this.vm});
  final ChatViewModel vm;

  @override
  State<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  final _c = WebViewController();
  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  String? _loaded;
  String _at = '';
  double _zoom = 1;

  /// What a menu action had to say (it could not be done), for a moment.
  String? _note;
  Timer? _noteTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_c.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(
      _c.setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) => setState(() {
            _at = change.url ?? _at;
            if (!_addressFocus.hasFocus) _address.text = _at;
          }),
        ),
      ),
    );
    widget.vm.addListener(_follow);
    _follow();
  }

  /// Loads what the session last asked to preview, when that changes.
  void _follow() {
    final url = widget.vm.previewUrl;
    if (url == null || url == _loaded) return;
    _loaded = url;
    _go(url);
  }

  void _go(String url) {
    _at = url;
    _address.text = url;
    final uri = Uri.parse(url);
    unawaited(uri.scheme == 'file' ? _c.loadFile(uri.toFilePath()) : _c.loadRequest(uri));
    if (mounted) setState(() {});
  }

  void _say(String note) {
    _noteTimer?.cancel();
    setState(() => _note = note);
    _noteTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _note = null);
    });
  }

  Future<void> _inspect() async {
    // Turns WebKit's developer tools on for the page and asks for its
    // inspector; says so when it did not show, with the ways that open it.
    await widget.vm.webPage('inspect');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!await widget.vm.webPage('inspecting')) {
      _say(
        'Developer tools are on for this page. Right-click it and choose Inspect Element, '
        'or in Safari choose Develop, then this Mac, then Helmy.',
      );
    }
  }

  Future<void> _setZoom(double z) async {
    _zoom = z.clamp(.3, 3.0);
    setState(() {});
    await widget.vm.webPage('zoom', {'zoom': _zoom});
  }

  @override
  void dispose() {
    widget.vm.removeListener(_follow);
    _noteTimer?.cancel();
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    // The page's own tools, where the system gives them (WebKit on a Mac).
    final native = Desktop.current == .mac;
    Widget tool(IconData icon, String label, VoidCallback onPressed) => Tooltip(
      message: label,
      child: Button(
        variant: .ghost,
        size: .iconXs,
        semanticLabel: label,
        onPressed: onPressed,
        child: AshlarIcon(icon, size: 14),
      ),
    );
    MenuItem item(IconData icon, String label, VoidCallback onPressed) =>
        MenuItem(leading: AshlarIcon(icon, size: 16), onPressed: onPressed, child: Text(label));
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Padding(
          padding: const .fromLTRB(8, 6, 8, 6),
          child: Row(
            spacing: 2,
            children: [
              tool(AshlarIconsRoundedStroke.arrowLeft, 'Back', () => unawaited(_c.goBack())),
              tool(AshlarIconsRoundedStroke.arrowRight, 'Forward', () => unawaited(_c.goForward())),
              tool(AshlarIconsRoundedStroke.rotateCw, 'Reload', () => unawaited(_c.reload())),
              const SizedBox(width: 4),
              Expanded(
                child: Input(
                  controller: _address,
                  focusNode: _addressFocus,
                  size: .sm,
                  placeholder: 'An address, or words to search for',
                  semanticLabel: 'Address',
                  onSubmitted: (typed) {
                    if (typed.trim().isEmpty) return;
                    _go(addressFor(typed));
                    _addressFocus.unfocus();
                  },
                ),
              ),
              const SizedBox(width: 4),
              if (native) tool(AshlarIconsRoundedStroke.squareCode, 'Inspect the page', _inspect),
              DropdownMenu(
                align: .end,
                items: [
                  if (native)
                    item(AshlarIconsRoundedStroke.refreshCw, 'Reload, skipping the cache', () {
                      unawaited(widget.vm.webPage('hardReload'));
                    }),
                  if (native)
                    item(AshlarIconsRoundedStroke.squareCode, 'Inspect the page', _inspect),
                  item(
                    AshlarIconsRoundedStroke.externalLink,
                    'Open in its own app',
                    () => unawaited(widget.vm.open(_at)),
                  ),
                  if (native) ...[
                    const MenuSeparator(),
                    MenuLabel(child: Text('Zoom ${(_zoom * 100).round()}%')),
                    item(AshlarIconsRoundedStroke.zoomIn, 'Zoom in', () => _setZoom(_zoom + .1)),
                    item(AshlarIconsRoundedStroke.zoomOut, 'Zoom out', () => _setZoom(_zoom - .1)),
                    item(AshlarIconsRoundedStroke.scan, 'Actual size', () => _setZoom(1)),
                    const MenuSeparator(),
                    const MenuLabel(child: Text('The page sees')),
                    for (final (mode, label, icon) in const [
                      ('light', 'Light mode', AshlarIconsRoundedStroke.sun),
                      ('dark', 'Dark mode', AshlarIconsRoundedStroke.moon),
                      ('system', "The system's mode", AshlarIconsRoundedStroke.sunMoon),
                    ])
                      item(icon, label, () {
                        unawaited(widget.vm.webPage('appearance', {'appearance': mode}));
                        unawaited(_c.reload());
                      }),
                  ],
                  const MenuSeparator(),
                  item(AshlarIconsRoundedStroke.cookie, 'Clear cookies', () async {
                    await WebViewCookieManager().clearCookies();
                    _say('Cookies cleared: sites see a first visit.');
                  }),
                  item(AshlarIconsRoundedStroke.trash, 'Clear cache', () async {
                    await _c.clearCache();
                    await _c.clearLocalStorage();
                    _say('Cache and stored data cleared.');
                  }),
                ],
                builder: (context, menu) => Tooltip(
                  message: 'More',
                  child: Button(
                    variant: .ghost,
                    size: .iconXs,
                    semanticLabel: 'More for this page',
                    onPressed: menu.open,
                    child: const AshlarIcon(AshlarIconsRoundedStroke.ellipsisVertical, size: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_note != null)
          Padding(
            padding: const .fromLTRB(12, 0, 12, 6),
            child: Text(_note!, style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
          ),
        Container(height: 1, color: t.colors.border),
        Expanded(child: WebViewWidget(controller: _c)),
      ],
    );
  }
}
