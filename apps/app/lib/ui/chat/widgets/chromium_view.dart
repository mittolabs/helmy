import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../data/services/chromium/chromium_tab.dart';
import '../../../utils/platform.dart';

/// A page drawn by a Chromium browser on this computer: its pictures as they
/// come, sized to the space, with clicks, scrolling and typing passed to it.
class ChromiumView extends StatefulWidget {
  const ChromiumView({super.key, required this.tab, required this.browserName});
  final ChromiumTab tab;
  final String browserName;

  @override
  State<ChromiumView> createState() => _ChromiumViewState();
}

class _ChromiumViewState extends State<ChromiumView> {
  final _focus = FocusNode();
  StreamSubscription<Uint8List>? _sub;
  Uint8List? _frame;
  Size? _shown;
  double? _scale;

  // Double clicks: when and where the last press was, and how many.
  DateTime _lastDown = DateTime(0);
  Offset _lastAt = Offset.zero;
  int _clicks = 0;
  String _pressed = 'left';

  @override
  void initState() {
    super.initState();
    _sub = widget.tab.frames.listen((f) => setState(() => _frame = f));
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _focus.dispose();
    super.dispose();
  }

  /// Draws the page at the panel's size, when that changes.
  void _fit(Size size, double scale) {
    if (size == _shown && scale == _scale) return;
    _shown = size;
    _scale = scale;
    unawaited(widget.tab.show(size.width, size.height, scale));
  }

  static String _button(int buttons) => buttons & kSecondaryMouseButton != 0
      ? 'right'
      : (buttons & kMiddleMouseButton != 0 ? 'middle' : 'left');

  /// The protocol's modifier bits: Alt 1, Ctrl 2, Meta 4, Shift 8.
  static int _modifiers() {
    final k = HardwareKeyboard.instance;
    return (k.isAltPressed ? 1 : 0) |
        (k.isControlPressed ? 2 : 0) |
        (k.isMetaPressed ? 4 : 0) |
        (k.isShiftPressed ? 8 : 0);
  }

  /// Keys go to the page once it is clicked. The app's text selection takes
  /// focus on a click too, so the page takes it back once the click is done.
  void _takeFocus() {
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _down(PointerDownEvent e) {
    _takeFocus();
    final now = DateTime.now();
    final again =
        now.difference(_lastDown) < const Duration(milliseconds: 450) &&
        (e.localPosition - _lastAt).distance < 6;
    _clicks = again ? _clicks + 1 : 1;
    _lastDown = now;
    _lastAt = e.localPosition;
    _pressed = _button(e.buttons);
    unawaited(
      widget.tab.mouse(
        'mousePressed',
        e.localPosition.dx,
        e.localPosition.dy,
        button: _button(e.buttons),
        clickCount: _clicks,
        modifiers: _modifiers(),
      ),
    );
  }

  // Keys with no text of their own, as the protocol names them.
  static final _keys = <LogicalKeyboardKey, (String, String, int)>{
    LogicalKeyboardKey.enter: ('Enter', 'Enter', 13),
    LogicalKeyboardKey.backspace: ('Backspace', 'Backspace', 8),
    LogicalKeyboardKey.tab: ('Tab', 'Tab', 9),
    LogicalKeyboardKey.escape: ('Escape', 'Escape', 27),
    LogicalKeyboardKey.delete: ('Delete', 'Delete', 46),
    LogicalKeyboardKey.arrowLeft: ('ArrowLeft', 'ArrowLeft', 37),
    LogicalKeyboardKey.arrowUp: ('ArrowUp', 'ArrowUp', 38),
    LogicalKeyboardKey.arrowRight: ('ArrowRight', 'ArrowRight', 39),
    LogicalKeyboardKey.arrowDown: ('ArrowDown', 'ArrowDown', 40),
    LogicalKeyboardKey.home: ('Home', 'Home', 36),
    LogicalKeyboardKey.end: ('End', 'End', 35),
    LogicalKeyboardKey.pageUp: ('PageUp', 'PageUp', 33),
    LogicalKeyboardKey.pageDown: ('PageDown', 'PageDown', 34),
  };

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.handled;
    final command = Desktop.current.commandIsMeta
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    if (command) {
      // Paste goes in as typing; the rest of the app's shortcuts stay its own.
      if (e.logicalKey == LogicalKeyboardKey.keyV) {
        unawaited(
          Clipboard.getData('text/plain').then((d) {
            if (d?.text case final text? when text.isNotEmpty) unawaited(widget.tab.type(text));
          }),
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_keys[e.logicalKey] case (final key, final code, final keyCode)) {
      unawaited(widget.tab.key(key, code, keyCode, modifiers: _modifiers()));
      return KeyEventResult.handled;
    }
    final text = e.character;
    if (text != null && text.isNotEmpty && !text.codeUnits.any((u) => u < 32)) {
      unawaited(widget.tab.type(text));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.devicePixelRatioOf(context);
      _fit(box.biggest, scale);
      final frame = _frame;
      return Semantics(
        // A picture to a screen reader: said plainly, with the way back.
        label:
            'A web page drawn by ${widget.browserName}. A screen reader cannot read it here; '
            "choose the system's web view in the page menu to read it.",
        child: Focus(
          focusNode: _focus,
          onKeyEvent: _key,
          child: Listener(
            onPointerDown: _down,
            onPointerUp: (e) {
              _takeFocus();
              unawaited(
                widget.tab.mouse(
                  'mouseReleased',
                  e.localPosition.dx,
                  e.localPosition.dy,
                  button: _pressed,
                  clickCount: _clicks,
                  modifiers: _modifiers(),
                ),
              );
            },
            onPointerMove: (e) => unawaited(
              widget.tab.mouse(
                'mouseMoved',
                e.localPosition.dx,
                e.localPosition.dy,
                button: _button(e.buttons),
                modifiers: _modifiers(),
              ),
            ),
            onPointerHover: (e) =>
                unawaited(widget.tab.mouse('mouseMoved', e.localPosition.dx, e.localPosition.dy)),
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                unawaited(
                  widget.tab.scroll(
                    e.localPosition.dx,
                    e.localPosition.dy,
                    e.scrollDelta.dx,
                    e.scrollDelta.dy,
                  ),
                );
              }
            },
            // Trackpad scrolling on a Mac comes as pan-zoom.
            onPointerPanZoomUpdate: (e) => unawaited(
              widget.tab.scroll(
                e.localPosition.dx,
                e.localPosition.dy,
                -e.panDelta.dx,
                -e.panDelta.dy,
              ),
            ),
            child: frame == null
                ? const SizedBox.expand()
                : Image.memory(
                    frame,
                    gaplessPlayback: true,
                    fit: BoxFit.fill,
                    width: box.maxWidth,
                    height: box.maxHeight,
                  ),
          ),
        ),
      );
    },
  );
}
