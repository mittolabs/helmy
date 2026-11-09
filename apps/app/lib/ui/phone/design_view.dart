import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/services/remote/remote_link.dart';
import '../core/ashlar/button.dart';
import '../core/ashlar/spinner.dart';
import '../core/ashlar/theme.dart';

/// Where the phone's copies of a design's screens say they are: links
/// between screens resolve here, and are followed here.
const _home = 'https://design.helmy.invalid/';

/// A chat's design on the phone, to hold in the hand: its screens one at a
/// time, full width, swiped through in order, links between screens
/// followed. Changes made on the Mac show as they are saved.
class PhoneDesignView extends StatefulWidget {
  const PhoneDesignView({super.key, required this.link, required this.sessionId});
  final RemoteLink link;
  final String sessionId;

  @override
  State<PhoneDesignView> createState() => _PhoneDesignViewState();
}

class _PhoneDesignViewState extends State<PhoneDesignView> {
  final _pages = PageController();
  StreamSubscription<String>? _changes;

  String _title = '';
  List<String> _order = const [];
  Map<String, String> _screens = const {};
  Map<String, Object?> _boards = const {};
  int _at = 0;
  bool _loading = true;
  bool _none = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(widget.link.watchDesign(widget.sessionId, on: true));
    _changes = widget.link.designChanges
        .where((id) => id == widget.sessionId)
        .listen((_) => _load());
  }

  @override
  void dispose() {
    unawaited(widget.link.watchDesign(widget.sessionId, on: false));
    unawaited(_changes?.cancel());
    _pages.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await widget.link.design(widget.sessionId);
    if (!mounted) return;
    final shown = _at < _order.length ? _order[_at] : null;
    setState(() {
      _loading = false;
      _none = d == null;
      if (d == null) return;
      final canvas = (d['canvas'] as Map?) ?? const {};
      _title = '${canvas['title'] ?? ''}';
      _boards = ((canvas['boards'] as Map?) ?? const {}).cast<String, Object?>();
      _screens = ((d['screens'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));
      _order = [for (final f in (d['order'] as List?) ?? const []) '$f']
          .where(_screens.containsKey)
          .toList();
      // The same screen in sight after a change, where it still is.
      final again = shown == null ? -1 : _order.indexOf(shown);
      _at = again < 0 ? _at.clamp(0, (_order.length - 1).clamp(0, 1 << 20)) : again;
    });
    if (_pages.hasClients && _order.isNotEmpty) _pages.jumpToPage(_at);
  }

  /// Goes to the screen [file], as a link to it was tapped.
  void _go(String file) {
    final i = _order.indexOf(file);
    if (i < 0) return;
    unawaited(
      _pages.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final screen = _at < _order.length ? _order[_at] : null;
    final board = screen == null ? null : _boards[screen] as Map?;
    return ColoredBox(
      color: c.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const .fromLTRB(8, 4, 12, 4),
              child: Row(
                spacing: 8,
                children: [
                  Button(
                    variant: .ghost,
                    size: .icon,
                    semanticLabel: 'Back to the chat',
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const AshlarIcon(AshlarIconsRoundedStroke.chevronLeft, size: 20),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      mainAxisSize: .min,
                      children: [
                        Text(
                          '${board?['title'] ?? screen?.replaceAll('.html', '') ?? 'Design'}',
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: t.text.sm.copyWith(fontWeight: .w600),
                        ),
                        Text(
                          [
                            if (_title.isNotEmpty) _title,
                            if (_order.isNotEmpty) '${_at + 1} of ${_order.length}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: t.text.xs.copyWith(color: c.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  // Swiping works too; these work where the page takes the swipe.
                  Button(
                    variant: .ghost,
                    size: .icon,
                    semanticLabel: 'The screen before',
                    onPressed: _at > 0 ? () => _go(_order[_at - 1]) : null,
                    child: const AshlarIcon(AshlarIconsRoundedStroke.arrowLeft, size: 18),
                  ),
                  Button(
                    variant: .ghost,
                    size: .icon,
                    semanticLabel: 'The next screen',
                    onPressed: _at < _order.length - 1 ? () => _go(_order[_at + 1]) : null,
                    child: const AshlarIcon(AshlarIconsRoundedStroke.arrowRight, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: Spinner(size: 20))
                  : _none || _order.isEmpty
                  ? Center(
                      child: Text(
                        'This chat has no design yet.',
                        style: t.text.sm.copyWith(color: c.mutedForeground),
                      ),
                    )
                  : PageView.builder(
                      controller: _pages,
                      itemCount: _order.length,
                      onPageChanged: (i) => setState(() => _at = i),
                      itemBuilder: (context, i) => _Screen(
                        key: ValueKey('${_order[i]}:${_screens[_order[i]].hashCode}'),
                        page: _screens[_order[i]]!,
                        board: (_boards[_order[i]] as Map?) ?? const {},
                        screens: _order,
                        onGo: _go,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One screen, as the phone shows it: a phone screen at the phone's width,
/// a wider one shrunk to fit, a responsive page laid out for the phone.
class _Screen extends StatefulWidget {
  const _Screen({
    super.key,
    required this.page,
    required this.board,
    required this.screens,
    required this.onGo,
  });
  final String page;
  final Map<dynamic, dynamic> board;
  final List<String> screens;
  final void Function(String file) onGo;

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  final _c = WebViewController();

  @override
  void initState() {
    super.initState();
    unawaited(_c.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(
      _c.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) {
            final uri = Uri.tryParse(r.url);
            if (uri == null || r.url == _home || uri.scheme == 'about' || uri.scheme == 'data') {
              return NavigationDecision.navigate;
            }
            // A link to another screen of the design: that screen.
            if (r.url.startsWith(_home)) {
              final file = Uri.decodeFull(uri.path.substring(1));
              if (widget.screens.contains(file)) widget.onGo(file);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.prevent;
          },
        ),
      ),
    );
    unawaited(_c.loadHtmlString(_sized(widget.page), baseUrl: _home));
  }

  /// [page] with the width it is drawn at: the phone's own for a responsive
  /// page, its frame's for any other, which the phone scales to fit.
  String _sized(String page) {
    final w = (widget.board['w'] as num?)?.toInt() ?? 390;
    // A fixed screen keeps its own width, scaled to the phone's: a 390 one
    // fills a 402 phone with no strip at its side.
    final fluid = widget.board['responsive'] == true;
    final meta =
        '<meta name="viewport" content="${fluid ? 'width=device-width, initial-scale=1' : 'width=$w'}">';
    final cleaned = page.replaceAll(
      RegExp(
        r'<meta[^>]+name=["'
        "'"
        r']viewport["'
        "'"
        r'][^>]*>',
        caseSensitive: false,
      ),
      '',
    );
    final head = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(cleaned);
    if (head != null) return cleaned.replaceRange(head.end, head.end, meta);
    final html = RegExp(r'<html[^>]*>', caseSensitive: false).firstMatch(cleaned);
    if (html != null) return cleaned.replaceRange(html.end, html.end, '<head>$meta</head>');
    return '$meta$cleaned';
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _c);
}
