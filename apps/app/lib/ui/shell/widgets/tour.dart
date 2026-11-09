import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../data/services/notify_service.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/theme.dart';

/// A part of the window the first-run tour points at.
enum TourStop {
  message(
    'Tell me what you want done, the way you would tell a person. '
    'Type / for commands, and @ to bring in a file.',
  ),
  folder(
    'Chats start on their own. When the work belongs to a project, '
    'choose its folder here and I work in it.',
  ),
  level('How much I do before checking with you. Ask first is the careful start.'),
  attach('Give me files, pictures and screenshots of any window to work from.'),
  panel(
    'A browser, a terminal, your files and my changes, beside the chat. '
    'I use them too, and you see what I do.',
  ),
  scheduled(
    'Things I do on my own, on a schedule: a morning summary, a weekly tidy. '
    'Your connections, phone and the rest are in Settings.',
  );

  const TourStop(this.line);

  /// What Helmy says about it.
  final String line;
}

/// Marks [child] as the part of the window that [stop] points at.
class TourTarget extends StatefulWidget {
  const TourTarget({super.key, required this.stop, required this.child});
  final TourStop stop;
  final Widget child;

  @override
  State<TourTarget> createState() => _TourTargetState();
}

class _TourTargetState extends State<TourTarget> {
  // The latest one built wins: the chat on screen, not one going away.
  static final _shown = <TourStop, _TourTargetState>{};

  @override
  void initState() {
    super.initState();
    _shown[widget.stop] = this;
  }

  @override
  void dispose() {
    if (_shown[widget.stop] == this) _shown.remove(widget.stop);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The first-run tour, over [child]: the window dimmed but for one part at a
/// time, and Helmy beside it saying what it is for. It plays once after the
/// first run ([due], then [onSeen]) and again from Help, Show the Tour.
/// Explains only: Next, Back and Skip, never waiting on the user.
class Tour extends StatefulWidget {
  const Tour({super.key, required this.due, required this.onSeen, required this.child});
  final bool due;
  final VoidCallback onSeen;
  final Widget child;

  @override
  State<Tour> createState() => _TourState();
}

class _TourState extends State<Tour> {
  /// The stop showing; null when the tour is not.
  int? _at;
  Rect? _hole;
  final _focus = FocusNode(debugLabel: 'Tour');
  final _box = GlobalKey();

  @override
  void initState() {
    super.initState();
    tourRequests.addListener(_start);
    if (widget.due) _startSoon();
  }

  @override
  void didUpdateWidget(Tour old) {
    super.didUpdateWidget(old);
    if (widget.due && !old.due) _startSoon();
  }

  @override
  void dispose() {
    tourRequests.removeListener(_start);
    _focus.dispose();
    super.dispose();
  }

  // Once the window has settled into the chat it opens to.
  void _startSoon() => Timer(const Duration(milliseconds: 900), _start);

  void _start() {
    if (!mounted || _at != null) return;
    widget.onSeen();
    _go(0, 1);
  }

  /// To the stop at [i], or the next shown one in [step]'s direction.
  void _go(int i, int step) {
    final stops = TourStop.values;
    while (i >= 0 && i < stops.length) {
      if (_TourTargetState._shown[stops[i]]?.mounted ?? false) {
        setState(() => _at = i);
        _focus.requestFocus();
        _measure();
        return;
      }
      i += step;
    }
    if (step > 0) _end();
  }

  void _end() => setState(() {
    _at = null;
    _hole = null;
  });

  // Where the stop is, again each frame while showing: windows resize and
  // panels move.
  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = _at;
      if (!mounted || at == null) return;
      final target = _TourTargetState._shown[TourStop.values[at]];
      final box = target?.context.findRenderObject() as RenderBox?;
      final over = _box.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || over == null || !box.attached || !box.hasSize) return;
      final rect = box.localToGlobal(Offset.zero, ancestor: over) & box.size;
      if (rect != _hole) setState(() => _hole = rect);
      _measure();
    });
  }

  bool get _last {
    final at = _at!;
    return !TourStop.values.skip(at + 1).any((s) => _TourTargetState._shown[s]?.mounted ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final at = _at;
    return Stack(
      key: _box,
      children: [
        widget.child,
        if (at != null)
          Positioned.fill(
            child: Focus(
              focusNode: _focus,
              autofocus: true,
              onKeyEvent: (_, e) {
                if (e is! KeyDownEvent) return .ignored;
                switch (e.logicalKey) {
                  case LogicalKeyboardKey.escape:
                    _end();
                  case LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.enter:
                    _go(at + 1, 1);
                  case LogicalKeyboardKey.arrowLeft:
                    _go(at - 1, -1);
                  default:
                    return .ignored;
                }
                return .handled;
              },
              child: _Spotlight(
                hole: _hole,
                stop: TourStop.values[at],
                number: TourStop.values
                    .take(at + 1)
                    .where((s) => _TourTargetState._shown[s]?.mounted ?? false)
                    .length,
                of: TourStop.values
                    .where((s) => _TourTargetState._shown[s]?.mounted ?? false)
                    .length,
                first: at == 0,
                last: _last,
                onBack: () => _go(at - 1, -1),
                onNext: () => _go(at + 1, 1),
                onSkip: _end,
              ),
            ),
          ),
      ],
    );
  }
}

class _Spotlight extends StatelessWidget {
  const _Spotlight({
    required this.hole,
    required this.stop,
    required this.number,
    required this.of,
    required this.first,
    required this.last,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final Rect? hole;
  final TourStop stop;
  final int number, of;
  final bool first, last;
  final VoidCallback onBack, onNext, onSkip;

  static const _bubbleWidth = 340.0;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final cut = hole?.inflate(6);
        // Beside the stop: below it where there is room, else above it.
        final below = cut == null || cut.bottom + 200 < size.height;
        final left = cut == null
            ? (size.width - _bubbleWidth) / 2
            : (cut.center.dx - _bubbleWidth / 2)
                  .clamp(16.0, math.max(16.0, size.width - _bubbleWidth - 16))
                  .toDouble();
        return Stack(
          children: [
            // Clicks on the dimmed window do nothing; the tour is in front.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(
                size: size,
                painter: _Dim(hole: cut, radius: t.radiusLg, ring: c.primary),
              ),
            ),
            if (cut != null)
              Positioned(
                left: left,
                top: below ? cut.bottom + 12 : null,
                bottom: below ? null : size.height - cut.top + 12,
                width: _bubbleWidth,
                child: _Bubble(
                  stop: stop,
                  number: number,
                  of: of,
                  first: first,
                  last: last,
                  onBack: onBack,
                  onNext: onNext,
                  onSkip: onSkip,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The window dimmed, with a lit hole round the stop and a ring on it.
class _Dim extends CustomPainter {
  _Dim({required this.hole, required this.radius, required this.ring});
  final Rect? hole;
  final double radius;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(all, Paint()..color = const Color(0xA6000000));
      return;
    }
    final r = RRect.fromRectAndRadius(h, Radius.circular(radius));
    canvas.drawPath(
      Path.combine(PathOperation.difference, all, Path()..addRRect(r)),
      Paint()..color = const Color(0xA6000000),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_Dim old) => old.hole != hole || old.ring != ring;
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.stop,
    required this.number,
    required this.of,
    required this.first,
    required this.last,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final TourStop stop;
  final int number, of;
  final bool first, last;
  final VoidCallback onBack, onNext, onSkip;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Container(
      padding: const .fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: c.popover,
        border: Border.all(color: c.border),
        borderRadius: .circular(t.radiusLg),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: 12,
        children: [
          Row(
            crossAxisAlignment: .start,
            spacing: 12,
            children: [
              Image.asset('assets/helmy/hello.png', width: 40, height: 40, semanticLabel: 'Helmy'),
              Expanded(
                child: Text(stop.line, style: t.text.sm.copyWith(color: c.popoverForeground)),
              ),
            ],
          ),
          Row(
            spacing: 8,
            children: [
              Text('$number of $of', style: t.text.xs.copyWith(color: c.mutedForeground)),
              const Spacer(),
              if (!last)
                Button(variant: .ghost, size: .sm, onPressed: onSkip, child: const Text('Skip')),
              if (!first)
                Button(variant: .outline, size: .sm, onPressed: onBack, child: const Text('Back')),
              Button(
                size: .sm,
                onPressed: last ? onSkip : onNext,
                child: Text(last ? 'Done' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
