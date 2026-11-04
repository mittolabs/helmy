import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/services/chromium/chromium_service.dart';
import '../../../data/services/chromium/chromium_tab.dart';
import '../../../domain/models/settings.dart';
import '../../../utils/platform.dart';
import '../../core/helmy_dialog.dart';
import 'chromium_view.dart';
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

  // Chromium, when the user chose it: the browser, the page open in it, and
  // what is happening while it starts or downloads.
  ChromiumBrowser? _browser;
  ChromiumTab? _tab;
  StreamSubscription<String>? _tabUrls;
  String? _chromiumState;
  bool get _chromium => widget.vm.previewEngine == .chromium && widget.vm.chromium != null;

  @override
  void initState() {
    super.initState();
    unawaited(_c.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(
      _c.setNavigationDelegate(
        NavigationDelegate(onUrlChange: (change) => _moved(change.url ?? _at)),
      ),
    );
    widget.vm.addListener(_follow);
    if (_chromium) unawaited(_startChromium());
    _follow();
  }

  void _moved(String url) {
    if (!mounted) return;
    setState(() {
      _at = url;
      if (!_addressFocus.hasFocus) _address.text = url;
    });
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
    if (_chromium) {
      unawaited(_tab?.navigate(url));
    } else {
      final uri = Uri.parse(url);
      unawaited(uri.scheme == 'file' ? _c.loadFile(uri.toFilePath()) : _c.loadRequest(uri));
    }
    if (mounted) setState(() {});
  }

  /// Opens the page in the chosen Chromium browser; with none installed,
  /// offers Chrome for Testing, downloaded only when the user agrees.
  Future<void> _startChromium() async {
    final service = widget.vm.chromium!;
    // Drawn as sharp as this screen.
    service.scale = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    setState(() => _chromiumState = 'Starting Chromium…');
    var browser = await service.pick(widget.vm.chromiumBrowser);
    if (browser == null) {
      if (!mounted) return;
      browser = await _download(service);
      if (browser == null) {
        await widget.vm.setPreviewEngine(.system);
        if (mounted) setState(() => _chromiumState = null);
        return;
      }
    }
    final chosen = browser;
    try {
      final tab = await service.open(chosen);
      if (!mounted) {
        unawaited(tab.close());
        return;
      }
      _browser = chosen;
      _tab = tab;
      // The zoom chosen before it opened.
      tab.zoom = _zoom;
      _tabUrls = tab.urls.listen(_moved);
      setState(() => _chromiumState = null);
      if (_at.isNotEmpty) unawaited(tab.navigate(_at));
    } on Object catch (e) {
      if (mounted) {
        setState(() => _chromiumState = "${chosen.name} didn't start: $e");
      }
    }
  }

  Future<ChromiumBrowser?> _download(ChromiumService service) async {
    setState(() => _chromiumState = 'Looking up Chrome for Testing…');
    final latest = await service.latest();
    if (!mounted) return null;
    if (latest == null) {
      _say(
        "No Chromium browser is installed, and Chrome for Testing couldn't be reached. "
        'Check the connection and choose Chromium again.',
      );
      return null;
    }
    final bytes = await service.sizeOf(latest);
    if (!mounted) return null;
    final size = bytes == null ? '' : ', ${(bytes / 1e6).round()} MB';
    final yes = await confirm(
      context,
      title: 'Download Chrome for Testing?',
      body:
          'No Chromium-based browser is installed on ${Desktop.current.thisComputer}. '
          "Chrome for Testing is Google's build of Chrome for apps to drive, signed by "
          "Google (version ${latest.version}$size). It's kept in Helmy's own folder, "
          'apart from any browser you use.',
      action: 'Download',
      icon: AshlarIconsRoundedStroke.download,
    );
    if (!yes || !mounted) return null;
    setState(() => _chromiumState = 'Downloading Chrome for Testing…');
    final got = await service.fetch(
      latest,
      progress: (share) {
        if (mounted) {
          setState(
            () => _chromiumState = 'Downloading Chrome for Testing… ${(share * 100).round()}%',
          );
        }
      },
    );
    if (got == null && mounted) {
      _say("Chrome for Testing didn't download. Try again from the menu.");
    }
    return got;
  }

  Future<void> _useEngine(PreviewEngine engine) async {
    await widget.vm.setPreviewEngine(engine);
    if (engine == .chromium) {
      await _startChromium();
    } else {
      await _closeChromium();
      _go(_at);
    }
    if (mounted) setState(() {});
  }

  Future<void> _closeChromium() async {
    await _tabUrls?.cancel();
    final tab = _tab;
    _tab = null;
    _browser = null;
    await tab?.close();
  }

  void _say(String note) {
    _noteTimer?.cancel();
    setState(() => _note = note);
    _noteTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _note = null);
    });
  }

  Future<void> _inspect() async {
    if (_chromium) {
      final (browser, tab) = (_browser, _tab);
      if (browser == null || tab == null) return;
      if (!await widget.vm.chromium!.inspect(browser, tab)) {
        _say("Developer tools didn't open in ${browser.name}.");
      }
      return;
    }
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
    if (_chromium) {
      await _tab?.setZoom(_zoom);
    } else {
      await widget.vm.webPage('zoom', {'zoom': _zoom});
    }
  }

  @override
  void dispose() {
    widget.vm.removeListener(_follow);
    _noteTimer?.cancel();
    unawaited(_closeChromium());
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final chromium = _chromium;
    final tab = _tab;
    // The page's own tools, where the system gives them (WebKit on a Mac).
    final native = !chromium && Desktop.current == .mac;
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
              tool(
                AshlarIconsRoundedStroke.arrowLeft,
                'Back',
                () => unawaited(chromium ? tab?.go(-1) : _c.goBack()),
              ),
              tool(
                AshlarIconsRoundedStroke.arrowRight,
                'Forward',
                () => unawaited(chromium ? tab?.go(1) : _c.goForward()),
              ),
              tool(
                AshlarIconsRoundedStroke.rotateCw,
                'Reload',
                () => unawaited(chromium ? tab?.reload() : _c.reload()),
              ),
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
              if (native || tab != null)
                tool(AshlarIconsRoundedStroke.squareCode, 'Inspect the page', _inspect),
              DropdownMenu(
                align: .end,
                items: [
                  if (native || tab != null)
                    item(AshlarIconsRoundedStroke.refreshCw, 'Reload, skipping the cache', () {
                      unawaited(
                        chromium ? tab?.reload(skipCache: true) : widget.vm.webPage('hardReload'),
                      );
                    }),
                  if (native || tab != null)
                    item(AshlarIconsRoundedStroke.squareCode, 'Inspect the page', _inspect),
                  item(
                    AshlarIconsRoundedStroke.externalLink,
                    'Open in its own app',
                    () => unawaited(widget.vm.open(_at)),
                  ),
                  if (widget.vm.chromium != null)
                    chromium
                        ? item(
                            AshlarIconsRoundedStroke.appWindow,
                            'Use the built-in browser',
                            () => unawaited(_useEngine(.system)),
                          )
                        : item(
                            AshlarIconsRoundedStroke.globe,
                            'Use Chromium',
                            () => unawaited(_useEngine(.chromium)),
                          ),
                  if (native || tab != null) ...[
                    const MenuSeparator(),
                    MenuLabel(child: Text('Zoom ${(_zoom * 100).round()}%')),
                    item(AshlarIconsRoundedStroke.zoomIn, 'Zoom in', () => _setZoom(_zoom + .1)),
                    item(AshlarIconsRoundedStroke.zoomOut, 'Zoom out', () => _setZoom(_zoom - .1)),
                    item(AshlarIconsRoundedStroke.scan, 'Actual size', () => _setZoom(1)),
                  ],
                  if (native || tab != null) ...[
                    const MenuSeparator(),
                    const MenuLabel(child: Text('The page sees')),
                    for (final (mode, label, icon) in const [
                      ('light', 'Light mode', AshlarIconsRoundedStroke.sun),
                      ('dark', 'Dark mode', AshlarIconsRoundedStroke.moon),
                      ('system', 'Match the system', AshlarIconsRoundedStroke.sunMoon),
                    ])
                      item(icon, label, () {
                        if (chromium) {
                          // Many sites choose their colors as they load.
                          unawaited(tab?.appearance(mode == 'system' ? null : mode));
                        } else {
                          unawaited(widget.vm.webPage('appearance', {'appearance': mode}));
                          unawaited(_c.reload());
                        }
                      }),
                  ],
                  const MenuSeparator(),
                  item(AshlarIconsRoundedStroke.cookie, 'Clear cookies', () async {
                    await (chromium ? tab?.clearCookies() : WebViewCookieManager().clearCookies());
                    _say('Cookies cleared: sites see a first visit.');
                  }),
                  item(AshlarIconsRoundedStroke.trash, 'Clear cache', () async {
                    if (chromium) {
                      await tab?.clearCache();
                    } else {
                      await _c.clearCache();
                      await _c.clearLocalStorage();
                    }
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
        Expanded(
          child: !chromium
              ? WebViewWidget(controller: _c)
              : tab != null && _browser != null
              ? ChromiumView(tab: tab, browserName: _browser!.name)
              : Center(
                  child: Padding(
                    padding: const .all(24),
                    child: Text(
                      _chromiumState ?? '',
                      textAlign: .center,
                      style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
