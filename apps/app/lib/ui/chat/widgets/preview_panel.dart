import 'dart:async';
import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/services/chromium/chromium_service.dart';
import '../../../data/services/chromium/chromium_tab.dart';
import '../../../domain/models/settings.dart';
import '../../../utils/platform.dart';
import '../../core/helmy_dialog.dart';
import 'chromium_view.dart';
import 'device_sizes.dart';
import 'page_marking.dart';
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

  /// The light or dark the page sees: 'light', 'dark', or 'system'.
  String _appearance = 'system';

  /// What a menu action had to say (it could not be done), for a moment.
  String? _note;
  Timer? _noteTimer;

  // Chromium, when the user chose it: the browser, the page open in it, and
  // what is happening while it starts or downloads.
  ChromiumBrowser? _browser;
  ChromiumTab? _tab;
  StreamSubscription<String>? _tabUrls;
  String? _chromiumState;

  /// Chromium could not start or keeps closing: the panel offers to start it again.
  bool _chromiumFailed = false;
  final _restarts = <DateTime>[];
  bool get _chromium => widget.vm.previewEngine == .chromium && widget.vm.chromium != null;
  StreamSubscription<(String, String)>? _tabCalls;

  // The size the page is shown at: null fills the panel (Responsive).
  bool _sizesOpen = false;
  DeviceSize? _device;
  Size _fills = Size.zero;

  /// How much a device size is shrunk to fit the panel (1 when it fits).
  double _fit = 1;
  double? _webZoomApplied;

  // Loading: a share from 0 to 1 while a page loads, null when it has.
  double? _progress;
  Timer? _creep;
  StreamSubscription<bool>? _tabLoading;

  void _loadingAt(double share) {
    if (!mounted) return;
    _creep?.cancel();
    if (share >= 1) {
      setState(() => _progress = 1);
      // The full line a moment, then gone.
      _creep = Timer(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => _progress = null);
      });
    } else {
      setState(() => _progress = share.clamp(.05, .95));
    }
  }

  /// Chromium says only when loading starts and stops: the line eases on
  /// in between, slower as it goes, until the page has loaded.
  void _creepFrom(double share) {
    _creep?.cancel();
    if (mounted) setState(() => _progress = share);
    _creep = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!mounted || _progress == null) return;
      setState(() => _progress = _progress! + (.9 - _progress!) * .06);
    });
  }

  /// The built-in browser's page zoom: the user's, times the shrinking that
  /// fits a device size, so the page still lays out at the device's width.
  void _fitWebZoom() {
    final want = _zoom * (_device == null ? 1 : _fit);
    if (_chromium || want == _webZoomApplied) return;
    _webZoomApplied = want;
    unawaited(widget.vm.webPage('zoom', {'zoom': want}));
  }

  void _useSize(DeviceSize? size) {
    setState(() => _device = size);
    final tab = _tab;
    if (tab != null) {
      tab.mobile = size?.mobile ?? false;
      unawaited(tab.setZoom(tab.zoom));
    }
  }

  // Marking up the page for the agent.
  bool _markingOpen = false;
  late final _marking = PageMarking((
    run: _runScript,
    picture: _picture,
    title: _title,
    url: () => _at,
  ));

  Future<void> _runScript(String script) async {
    try {
      if (_chromium) {
        await _tab?.evaluate(script);
      } else {
        await _c.runJavaScript(script);
      }
    } on Object {
      // A page that refuses scripts (a PDF, a blank page) has nothing to mark.
    }
  }

  Future<String?> _picture(String path) async {
    final tab = _tab;
    if (_chromium && tab != null) {
      await File(path).writeAsBytes(await tab.screenshot());
      return path;
    }
    return widget.vm.webSnapshot(path);
  }

  Future<String> _title() async {
    try {
      return _chromium
          ? '${await _tab?.evaluate('document.title') ?? ''}'
          : await _c.getTitle() ?? '';
    } on Object {
      return '';
    }
  }

  Future<void> _addMarks() async {
    final files = await _marking.toFiles();
    if (files == null || !mounted) return;
    widget.vm.attach(files);
    await _marking.clear();
    setState(() => _markingOpen = false);
    _say('Added to your message: a picture of the page with the marks, and what each is on.');
  }

  Future<void> _toggleMarking() async {
    if (_markingOpen) {
      await _marking.clear();
    } else {
      _marking.theme = markTheme(AshlarTheme.of(context));
      await _marking.use('pick');
    }
    if (mounted) setState(() => _markingOpen = !_markingOpen);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_c.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(
      _c.setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) => _moved(change.url ?? _at),
          onPageStarted: (_) => _loadingAt(.05),
          onProgress: (p) => _loadingAt(p / 100),
          onPageFinished: (_) => _loadingAt(1),
        ),
      ),
    );
    // Marks made on the page come back through this channel (the built-in browser).
    unawaited(
      _c.addJavaScriptChannel('Helmy', onMessageReceived: (m) => _marking.fromPage(m.message)),
    );
    widget.vm.addListener(_follow);
    if (_chromium) unawaited(_startChromium());
    _follow();
  }

  void _moved(String url) {
    if (!mounted) return;
    // Another page: the marks were on the last one.
    if (Uri.tryParse(url)?.removeFragment() != Uri.tryParse(_at)?.removeFragment()) {
      _marking.pageMoved();
      _markingOpen = false;
    }
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
      // The zoom and the light or dark chosen before it opened.
      tab.zoom = _zoom;
      if (_appearance != 'system') unawaited(tab.appearance(_appearance));
      _tabUrls = tab.urls.listen(_moved);
      _tabLoading = tab.loading.listen((on) => on ? _creepFrom(.1) : _loadingAt(1));
      tab.mobile = _device?.mobile ?? false;
      // Marks made on the page come back through this binding (Chromium).
      await tab.bind('helmyAnnotate');
      _tabCalls = tab.called
          .where((c) => c.$1 == 'helmyAnnotate')
          .listen((c) => _marking.fromPage(c.$2));
      setState(() {
        _chromiumState = null;
        _chromiumFailed = false;
      });
      if (_at.isNotEmpty) unawaited(tab.navigate(_at));
      unawaited(tab.gone.then((_) => _browserGone(tab, chosen)));
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _chromiumState = "${chosen.name} didn't start: $e";
          _chromiumFailed = true;
        });
      }
    }
  }

  /// The browser closed (it crashed, or something ended it). Once in a while
  /// it starts again by itself, back on the same page; closing again and
  /// again, it stops and says so, with a way to start it.
  Future<void> _browserGone(ChromiumTab tab, ChromiumBrowser browser) async {
    if (!mounted || _tab != tab) return;
    await _closeChromium();
    final now = DateTime.now();
    _restarts.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_restarts.length >= 2) {
      setState(() {
        _chromiumState = '${browser.name} closed again, twice in a minute.';
        _chromiumFailed = true;
      });
      return;
    }
    _restarts.add(now);
    _say('${browser.name} closed; it was started again.');
    await _startChromium();
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
    await _tabCalls?.cancel();
    await _tabLoading?.cancel();
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
      _fitWebZoom();
    }
  }

  @override
  void dispose() {
    widget.vm.removeListener(_follow);
    _noteTimer?.cancel();
    _creep?.cancel();
    unawaited(_closeChromium());
    _marking.dispose();
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
              tool(
                AshlarIconsRoundedStroke.penTool,
                _markingOpen ? 'Stop marking' : 'Mark up the page for the agent',
                () => unawaited(_toggleMarking()),
              ),
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
                    AshlarIconsRoundedStroke.smartphone,
                    _sizesOpen ? 'Hide device sizes' : 'Show device sizes',
                    () {
                      if (_sizesOpen) _useSize(null);
                      setState(() => _sizesOpen = !_sizesOpen);
                    },
                  ),
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
                      MenuItem(
                        leading: AshlarIcon(icon, size: 16),
                        // The one the page sees now, checked.
                        trailing: _appearance == mode
                            ? const AshlarIcon(AshlarIconsRoundedStroke.check, size: 16)
                            : null,
                        selected: _appearance == mode,
                        child: Text(label),
                        onPressed: () {
                          setState(() => _appearance = mode);
                          if (chromium) {
                            // Many sites choose their colors as they load.
                            unawaited(tab?.appearance(mode == 'system' ? null : mode));
                          } else {
                            unawaited(widget.vm.webPage('appearance', {'appearance': mode}));
                            unawaited(_c.reload());
                          }
                        },
                      ),
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
        if (_sizesOpen)
          DeviceSizeBar(
            size: _device,
            fills: _fills,
            onSize: _useSize,
            onClose: () {
              _useSize(null);
              setState(() => _sizesOpen = false);
            },
          ),
        if (_markingOpen)
          MarkingBar(
            marking: _marking,
            onAdd: () => unawaited(_addMarks()),
            onDone: () => unawaited(_toggleMarking()),
          ),
        // The line under the toolbar, and the page's progress along it.
        SizedBox(
          height: 2,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(height: 1, color: t.colors.border),
              ),
              if (_progress != null)
                FractionallySizedBox(
                  widthFactor: _progress,
                  child: Semantics(
                    label: 'Loading the page',
                    value: '${(_progress! * 100).round()}%',
                    child: Container(color: t.colors.primary),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              _fills = box.biggest;
              final page = !chromium
                  ? WebViewWidget(controller: _c)
                  : tab != null && _browser != null
                  ? ChromiumView(tab: tab, browserName: _browser!.name)
                  : null;
              final device = _device;
              if (page == null || device == null) {
                if (!chromium) WidgetsBinding.instance.addPostFrameCallback((_) => _fitWebZoom());
                return page ?? _starting(t);
              }
              // A device size: shown at it, shrunk to fit when bigger.
              final w = device.width.toDouble(), h = device.height.toDouble();
              _fit = [
                1.0,
                (box.maxWidth - 24) / w,
                (box.maxHeight - 44) / h,
              ].reduce((a, b) => a < b ? a : b).clamp(.1, 1.0);
              if (!chromium) WidgetsBinding.instance.addPostFrameCallback((_) => _fitWebZoom());
              return ColoredBox(
                color: t.colors.muted,
                child: Center(
                  child: Column(
                    mainAxisSize: .min,
                    spacing: 6,
                    children: [
                      Text(
                        '${device.name == 'Custom' ? '' : '${device.name}  '}'
                        '${device.width} × ${device.height}'
                        '${_fit < 1 ? '  ·  shown at ${(_fit * 100).round()}%' : ''}',
                        style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                      ),
                      SizedBox(
                        width: w * _fit,
                        height: h * _fit,
                        child: chromium
                            ? FittedBox(
                                child: SizedBox(width: w, height: h, child: page),
                              )
                            : page,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// While Chromium starts or downloads: what is happening.
  Widget _starting(AshlarThemeData t) => Center(
    child: Padding(
      padding: const .all(24),
      child: Column(
        mainAxisSize: .min,
        spacing: 12,
        children: [
          Text(
            _chromiumState ?? '',
            textAlign: .center,
            style: t.text.sm.copyWith(color: t.colors.mutedForeground),
          ),
          if (_chromiumFailed) ...[
            Button(
              size: .sm,
              onPressed: () {
                _restarts.clear();
                unawaited(_startChromium());
              },
              child: const Text('Start it again'),
            ),
            Button(
              variant: .ghost,
              size: .sm,
              onPressed: () => unawaited(_useEngine(.system)),
              child: const Text('Use the built-in browser'),
            ),
          ],
        ],
      ),
    ),
  );
}
