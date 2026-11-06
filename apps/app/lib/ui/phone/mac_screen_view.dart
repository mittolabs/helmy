import 'dart:async';
import 'dart:math' as math;

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
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

  /// Modifiers held for the next key, as a phone keyboard's Shift is: on
  /// until a key goes with them.
  final _mods = <String>{};

  /// The screen alone, edge to edge, the phone's own bars hidden.
  bool _full = false;

  /// In full screen, whether the keys show.
  bool _keysInFull = false;

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
    if (_full) unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
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

  /// [key] pressed on the Mac, with the modifiers held; they let go after.
  void _key(String key, [Set<String> extra = const {}]) {
    unawaited(
      link.input(
        'key',
        more: {
          'key': key,
          'mods': [..._mods, ...extra],
        },
      ),
    );
    if (_mods.isNotEmpty) setState(_mods.clear);
  }

  void _setFull(bool on) {
    setState(() {
      _full = on;
      _keysInFull = false;
    });
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  void _onType(String text) {
    if (text.length < _blank.length) {
      _key('delete');
    } else if (text.length > _blank.length) {
      final typed = text.substring(_blank.length);
      // With a modifier held, a letter is a shortcut (⌘C), not text.
      if (_mods.isNotEmpty && typed.length == 1) {
        _key(typed);
      } else {
        unawaited(link.input('text', more: {'text': typed}));
      }
    }
    _typed.value = const TextEditingValue(
      text: _blank,
      selection: TextSelection.collapsed(offset: _blank.length),
    );
  }

  /// The box that types on the Mac.
  Widget _typingBar() => Padding(
    padding: const .fromLTRB(12, 0, 12, 8),
    child: Input(
      controller: _typed,
      focusNode: _typing,
      size: .sm,
      placeholder: _mods.isEmpty ? 'Type on the Mac' : 'A key, with ${_mods.map(_symbol).join()}',
      textInputAction: .send,
      onChanged: _onType,
      onSubmitted: (_) {
        _key('return');
        _typing.requestFocus();
      },
    ),
  );

  static String _symbol(String mod) => switch (mod) {
    'cmd' => '⌘',
    'alt' => '⌥',
    'ctrl' => '⌃',
    _ => '⇧',
  };

  /// The keys a phone keyboard has not: modifiers held for the next key,
  /// Esc, Tab, arrows, and the shortcuts used most.
  Widget _keys(BuildContext context) {
    final t = AshlarTheme.of(context);
    Widget key(String label, VoidCallback onPressed, {bool on = false, String? semantic}) => Button(
      variant: on ? .secondary : .outline,
      size: .sm,
      semanticLabel: semantic ?? label,
      onPressed: onPressed,
      child: Text(label),
    );
    Widget gap() => Container(width: 1, height: 20, color: t.colors.border);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: .horizontal,
        padding: const .symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final mod in ['cmd', 'alt', 'ctrl', 'shift'])
            Padding(
              padding: const .only(right: 6),
              child: key(
                _symbol(mod),
                () => setState(() => _mods.contains(mod) ? _mods.remove(mod) : _mods.add(mod)),
                on: _mods.contains(mod),
                semantic: switch (mod) {
                  'cmd' => 'Command',
                  'alt' => 'Option',
                  'ctrl' => 'Control',
                  _ => 'Shift',
                },
              ),
            ),
          gap(),
          for (final (label, k, name) in [
            ('Esc', 'escape', 'Escape'),
            ('Tab', 'tab', 'Tab'),
            ('←', 'left', 'Left'),
            ('↑', 'up', 'Up'),
            ('↓', 'down', 'Down'),
            ('→', 'right', 'Right'),
            ('⌫', 'delete', 'Delete'),
            ('⏎', 'return', 'Return'),
          ])
            Padding(
              padding: const .only(left: 6),
              child: key(label, () => _key(k), semantic: name),
            ),
          const SizedBox(width: 6),
          gap(),
          for (final (label, k, mods) in [
            ('Copy', 'c', {'cmd'}),
            ('Paste', 'v', {'cmd'}),
            ('Undo', 'z', {'cmd'}),
            ('Select all', 'a', {'cmd'}),
            ('Switch app', 'tab', {'cmd'}),
            ('Spotlight', 'space', {'cmd'}),
            ('Mission Control', 'up', {'ctrl'}),
            ('Close window', 'w', {'cmd'}),
          ])
            Padding(padding: const .only(left: 6), child: key(label, () => _key(k, mods))),
        ],
      ),
    );
  }

  /// The screen edge to edge, with two small buttons in a corner: the keys,
  /// and back out.
  Widget _fullScreen(BuildContext context) {
    final t = AshlarTheme.of(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final pad = MediaQuery.paddingOf(context);
    Widget round(IconData icon, String label, VoidCallback onPressed, {bool on = false}) => Button(
      variant: on ? .secondary : .ghost,
      size: .icon,
      semanticLabel: label,
      onPressed: onPressed,
      child: AshlarIcon(icon, size: 18, color: on ? null : const Color(0xFFFFFFFF)),
    );
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<Uint8List?>(
              valueListenable: link.frame,
              builder: (context, jpeg, _) =>
                  jpeg == null ? const Center(child: Spinner(size: 20)) : _screen(jpeg),
            ),
          ),
          Positioned(
            top: pad.top + 8,
            right: pad.right + 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x99000000),
                borderRadius: .circular(t.radiusLg),
              ),
              child: Row(
                mainAxisSize: .min,
                children: [
                  round(
                    AshlarIconsRoundedStroke.command,
                    'Keys',
                    () => setState(() => _keysInFull = !_keysInFull),
                    on: _keysInFull,
                  ),
                  round(AshlarIconsRoundedStroke.keyboard, 'Type on the Mac', () {
                    setState(() => _keyboard = !_keyboard);
                    _keyboard ? _typing.requestFocus() : _typing.unfocus();
                  }, on: _keyboard),
                  round(AshlarIconsRoundedStroke.minimize2, 'Leave full screen', () {
                    _setFull(false);
                  }),
                ],
              ),
            ),
          ),
          if (_keysInFull || _keyboard)
            Positioned(
              left: pad.left,
              right: pad.right,
              bottom: inset > 0 ? inset : pad.bottom,
              child: ColoredBox(
                color: t.colors.background.withValues(alpha: .92),
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  children: [_keys(context), if (_keyboard) _typingBar()],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_full) return _fullScreen(context);
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
                        variant: .ghost,
                        size: .icon,
                        semanticLabel: 'Full screen',
                        onPressed: () => _setFull(true),
                        child: const AshlarIcon(AshlarIconsRoundedStroke.maximize2, size: 20),
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
                _keys(context),
                if (_keyboard) _typingBar(),
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
