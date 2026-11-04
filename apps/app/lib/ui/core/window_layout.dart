import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/settings_repository.dart';
import '../../utils/platform.dart';

/// Below this window width the sidebar stops sitting beside the page: it is
/// hidden, and its button slides it in over the page.
const narrowWindow = 960.0;

/// Where the window's own buttons (close, minimize, zoom) end, from the
/// window's left edge, and the line through their middle, from its top.
const windowButtonsEnd = 72.0;
const titleLine = 16.0;

/// Whether the window is in full screen, as macOS says. Its buttons are hidden
/// there, so what sits after them moves to the edge.
final windowFullScreen = ValueNotifier(false);

/// Where a title row starts when the sidebar is not beside the page: after
/// the window's buttons on a Mac (the app draws under its title bar there),
/// at the edge in full screen, and at the edge on Windows and Linux, whose
/// title bar sits above the app.
double get titleRowStart =>
    windowFullScreen.value || Desktop.current != .mac ? 16 : windowButtonsEnd;

/// The space either side of a page's content: less on a phone-width window.
double sideMargin(BuildContext context) => MediaQuery.sizeOf(context).width < 600 ? 16 : 32;

/// Whether the sidebar sits beside the page now: open in settings, and the
/// window wide enough. When it does not, a page's header leaves room for the
/// window's buttons and the sidebar's.
bool sidebarBeside(BuildContext context) =>
    context.watch<SettingsRepository>().settings.sidebarOpen &&
    MediaQuery.sizeOf(context).width >= narrowWindow;

/// A strip that stands in for the window's title bar, which the app draws
/// under: a double-click on its empty space does what one on a title bar does
/// (zoom, by default). Clicks on what [child] shows there (a button, a title)
/// are theirs alone, and are never held up waiting for a second click.
class TitleBar extends StatefulWidget {
  const TitleBar({super.key, required this.child});
  final Widget child;

  static const _channel = MethodChannel('helmy/notify');

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> {
  Duration? _last;
  Offset? _at;

  void _down(PointerDownEvent e) {
    final last = _last, at = _at;
    _last = e.timeStamp;
    _at = e.position;
    if (last == null || at == null) return;
    if (e.timeStamp - last > const Duration(milliseconds: 500)) return;
    if ((e.position - at).distance > 6) return;
    _last = null;
    TitleBar._channel.invokeMethod<void>('titleBarDoubleClick').ignore();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      // Behind the content: only clicks that land on nothing of it reach here.
      Positioned.fill(
        child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: _down),
      ),
      widget.child,
    ],
  );
}
