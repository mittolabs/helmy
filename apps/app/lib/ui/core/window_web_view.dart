import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A web page, drawn by the system, in whichever window it is in.
///
/// A panel tab keeps its state as it moves into a window of its own and
/// back (a GlobalKey), and its web view's platform view with it. The engine
/// then leaves the system's view in the window the platform view was first
/// shown in, so the page goes blank where the tab now is. So each window
/// gets a platform view of its own, around the same page: what it shows,
/// its history and its scripts carry on.
///
/// The old one goes a moment before the new one is made: both wrap the one
/// system view, and the old one, let go after, would take it away with it.
class WindowWebView extends StatefulWidget {
  const WindowWebView({super.key, required this.controller});
  final WebViewController controller;

  @override
  State<WindowWebView> createState() => _WindowWebViewState();
}

class _WindowWebViewState extends State<WindowWebView> {
  /// The window the platform view was made in.
  int? _shownIn;

  /// Moved: the moment between the old platform view and the new.
  bool _between = false;

  @override
  Widget build(BuildContext context) {
    final window = View.of(context).viewId;
    if (_shownIn != null && _shownIn != window && !_between) {
      _between = true;
      // The engine lets a platform view go once a later frame is shown,
      // not at once: a moment, rather than a frame.
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted) {
          setState(() {
            _between = false;
            _shownIn = null;
          });
        }
      });
    }
    if (_between) return const SizedBox.expand();
    _shownIn = window;
    return WebViewWidget(key: ValueKey(window), controller: widget.controller);
  }
}
