import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../data/services/remote/remote_link.dart';
import '../../utils/image_size.dart';
import '../core/ashlar/button.dart';
import '../core/ashlar/input.dart';
import '../core/ashlar/spinner.dart';
import '../core/ashlar/theme.dart';

/// The Mac's screen on the phone, to see and use. A tap clicks (two quick
/// taps double-click), a long press right-clicks, one finger drags, two
/// fingers scroll, a pinch zooms in, and two fingers move about once zoomed.
/// The keyboard types on the Mac.
class MacScreenView extends StatefulWidget {
  const MacScreenView({super.key, required this.link});
  final RemoteLink link;

  @override
  State<MacScreenView> createState() => _MacScreenViewState();
}

class _MacScreenViewState extends State<MacScreenView> {
  RemoteLink get link => widget.link;

  /// The zoom, and where the zoomed picture sits.
  double _zoom = 1;
  Offset _shift = Offset.zero;

  /// Where the frame is drawn, unzoomed, in this view.
  Rect _fit = Rect.zero;

  /// What a gesture is doing: dragging on the Mac, or two fingers.
  bool _dragging = false;

  /// Where the last drag was on the Mac, for letting go there.
  Offset? _lastDrag;
  double _zoomAtStart = 1;
  DateTime _lastSent = DateTime(0);

  final _typed = TextEditingController(text: _blank);
  final _typing = FocusNode();
  bool _keyboard = false;

  /// What the box holds when empty: a space, so a delete has something to
  /// take, and is seen.
  static const _blank = ' ';

  @override
  void initState() {
    super.initState();
    unawaited(link.showScreen());
    // The keyboard put away (a tap elsewhere): the typing bar goes with it.
    _typing.addListener(() {
      if (!_typing.hasFocus && _keyboard) setState(() => _keyboard = false);
    });
  }

  @override
  void dispose() {
    unawaited(link.hideScreen());
    _typed.dispose();
    _typing.dispose();
    super.dispose();
  }

  /// Where on the Mac's screen [p] (in this view) falls, from 0 to 1 across
  /// it; null off the picture.
  Offset? _onMac(Offset p) {
    if (_fit.isEmpty) return null;
    final local = (p - _shift) / _zoom;
    final x = (local.dx - _fit.left) / _fit.width, y = (local.dy - _fit.top) / _fit.height;
    if (x < 0 || x > 1 || y < 0 || y > 1) return null;
    return Offset(x, y);
  }

  void _send(String kind, Offset at, {bool always = true}) {
    final now = DateTime.now();
    // Moves are many: at most one each 30 ms.
    if (!always && now.difference(_lastSent) < const Duration(milliseconds: 30)) return;
    _lastSent = now;
    final m = _onMac(at);
    if (m == null) return;
    if (kind == 'down' || kind == 'drag') _lastDrag = m;
    unawaited(link.input(kind, x: m.dx, y: m.dy));
  }

  void _keepInView(Size box) {
    if (_zoom <= 1) {
      _zoom = 1;
      _shift = Offset.zero;
      return;
    }
    final minX = box.width - box.width * _zoom, minY = box.height - box.height * _zoom;
    _shift = Offset(_shift.dx.clamp(minX, 0), _shift.dy.clamp(minY, 0));
  }

  void _onType(String text) {
    if (text.length < _blank.length) {
      unawaited(link.input('key', more: {'key': 'delete'}));
    } else if (text.length > _blank.length) {
      unawaited(link.input('text', more: {'text': text.substring(_blank.length)}));
    }
    _typed.value = const TextEditingValue(
      text: _blank,
      selection: TextSelection.collapsed(offset: _blank.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return ColoredBox(
      color: c.background,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SafeArea(
          bottom: bottom == 0,
          child: ListenableBuilder(
            listenable: link,
            builder: (context, _) => Column(
              crossAxisAlignment: .stretch,
              children: [
                Padding(
                  padding: const .fromLTRB(4, 4, 8, 4),
                  child: Row(
                    children: [
                      Button(
                        variant: .ghost,
                        size: .icon,
                        semanticLabel: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                        child: const AshlarIcon(AshlarIconsRoundedStroke.chevronLeft, size: 22),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: .start,
                          children: [
                            Text(link.pairing.name, style: t.text.base.copyWith(fontWeight: .w600)),
                            Text(
                              link.state != LinkState.connected
                                  ? 'Reaching it…'
                                  : link.screenOn
                                  ? 'Its screen, live'
                                  : link.screenTrouble != null
                                  ? 'Not showing its screen'
                                  : 'Asking to see its screen…',
                              style: t.text.xs.copyWith(color: c.mutedForeground),
                            ),
                          ],
                        ),
                      ),
                      if (_zoom > 1)
                        Button(
                          variant: .ghost,
                          size: .sm,
                          onPressed: () => setState(() {
                            _zoom = 1;
                            _shift = Offset.zero;
                          }),
                          child: const Text('Fit'),
                        ),
                      Button(
                        variant: _keyboard ? .secondary : .ghost,
                        size: .icon,
                        semanticLabel: 'Type on the Mac',
                        onPressed: () {
                          setState(() => _keyboard = !_keyboard);
                          if (_keyboard) {
                            _typing.requestFocus();
                          } else {
                            _typing.unfocus();
                          }
                        },
                        child: const AshlarIcon(AshlarIconsRoundedStroke.keyboard, size: 20),
                      ),
                    ],
                  ),
                ),
                if (link.screenTrouble case final trouble?)
                  Padding(
                    padding: const .fromLTRB(16, 0, 16, 8),
                    child: Text(
                      trouble,
                      style: t.text.sm.copyWith(color: c.mutedForeground, height: 1.45),
                    ),
                  ),
                Expanded(
                  child: ValueListenableBuilder<Uint8List?>(
                    valueListenable: link.frame,
                    builder: (context, jpeg, _) => jpeg == null
                        ? Center(
                            child: link.screenOn || link.screenTrouble == null
                                ? const Spinner(size: 20)
                                : Padding(
                                    padding: const .all(24),
                                    child: Button(
                                      variant: .outline,
                                      size: .sm,
                                      onPressed: () => unawaited(link.showScreen()),
                                      child: const Text('Try again'),
                                    ),
                                  ),
                          )
                        : _screen(jpeg),
                  ),
                ),
                if (_keyboard)
                  Padding(
                    padding: const .fromLTRB(12, 8, 12, 8),
                    child: Row(
                      spacing: 8,
                      children: [
                        Expanded(
                          child: Input(
                            controller: _typed,
                            focusNode: _typing,
                            size: .sm,
                            placeholder: 'Type on the Mac',
                            textInputAction: .send,
                            onChanged: _onType,
                            onSubmitted: (_) {
                              unawaited(link.input('key', more: {'key': 'return'}));
                              _typing.requestFocus();
                            },
                          ),
                        ),
                        for (final (label, key) in [('Tab', 'tab'), ('Esc', 'escape')])
                          Button(
                            variant: .outline,
                            size: .sm,
                            onPressed: () => unawaited(link.input('key', more: {'key': key})),
                            child: Text(label),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _screen(Uint8List jpeg) => LayoutBuilder(
    builder: (context, box) {
      final size = imageSize(jpeg);
      final view = Size(box.maxWidth, box.maxHeight);
      if (size != null) {
        final s = math.min(view.width / size.$1, view.height / size.$2);
        final w = size.$1 * s, h = size.$2 * s;
        _fit = Rect.fromLTWH((view.width - w) / 2, (view.height - h) / 2, w, h);
      }
      return GestureDetector(
        behavior: .opaque,
        onTapUp: (d) => _send('click', d.localPosition),
        onLongPressStart: (d) => _send('right', d.localPosition),
        onScaleStart: (d) {
          _zoomAtStart = _zoom;
          if (d.pointerCount < 2) {
            _dragging = true;
            _send('down', d.localFocalPoint);
          }
        },
        onScaleUpdate: (d) {
          if (d.pointerCount > 1 && _dragging) {
            // A second finger came down: the drag ends where it was.
            _dragging = false;
            _send('up', d.localFocalPoint);
          }
          if (_dragging) {
            _send('drag', d.localFocalPoint, always: false);
            return;
          }
          if (d.pointerCount < 2) return;
          if ((d.scale - 1).abs() > .04 || _zoom > 1) {
            // Pinching zooms about the fingers; zoomed in, two fingers move about.
            setState(() {
              final before = (d.localFocalPoint - _shift) / _zoom;
              _zoom = (_zoomAtStart * d.scale).clamp(1.0, 5.0);
              _shift = d.localFocalPoint - before * _zoom + d.focalPointDelta;
              _keepInView(view);
            });
          } else {
            // Two fingers at the picture's size: the Mac scrolls.
            final now = DateTime.now();
            if (now.difference(_lastSent) < const Duration(milliseconds: 30)) return;
            _lastSent = now;
            final m = _onMac(d.localFocalPoint);
            if (m == null) return;
            unawaited(
              link.input(
                'scroll',
                x: m.dx,
                y: m.dy,
                more: {'dx': d.focalPointDelta.dx * 3, 'dy': d.focalPointDelta.dy * 3},
              ),
            );
          }
        },
        onScaleEnd: (d) {
          if (_dragging) {
            _dragging = false;
            final m = _lastDrag;
            if (m != null) unawaited(link.input('up', x: m.dx, y: m.dy));
          }
        },
        child: ClipRect(
          child: Transform(
            transform: Matrix4.identity()
              ..translateByDouble(_shift.dx, _shift.dy, 0, 1)
              ..scaleByDouble(_zoom, _zoom, 1, 1),
            child: Image.memory(
              jpeg,
              gaplessPlayback: true,
              fit: BoxFit.contain,
              width: view.width,
              height: view.height,
              filterQuality: .medium,
            ),
          ),
        ),
      );
    },
  );
}
