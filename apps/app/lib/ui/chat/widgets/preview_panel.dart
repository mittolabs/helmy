import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/ashlar/button.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../view_models/chat_view_model.dart';

/// Beside the conversation: the page an answer pointed at, a running app on
/// this Mac, or a document, live in a web view you can click through.
class PreviewPanel extends StatefulWidget {
  const PreviewPanel({super.key, required this.vm});
  final ChatViewModel vm;

  @override
  State<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  final _c = WebViewController();
  String? _loaded;
  String _at = '';

  @override
  void initState() {
    super.initState();
    unawaited(_c.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(
      _c.setNavigationDelegate(
        NavigationDelegate(onUrlChange: (change) => setState(() => _at = change.url ?? _at)),
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
    _at = url;
    final uri = Uri.parse(url);
    unawaited(uri.scheme == 'file' ? _c.loadFile(uri.toFilePath()) : _c.loadRequest(uri));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.vm.removeListener(_follow);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
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
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _at,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                ),
              ),
              tool(
                AshlarIconsRoundedStroke.externalLink,
                'Open in its own app',
                () => unawaited(widget.vm.open(_at)),
              ),
            ],
          ),
        ),
        Container(height: 1, color: t.colors.border),
        Expanded(child: WebViewWidget(controller: _c)),
      ],
    );
  }
}
