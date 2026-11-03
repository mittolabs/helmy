// Ashlar UI: Shimmer. Copied into your app by `ashlar add shimmer`; it is yours to change.

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Text, or any shape, with a light passing across it: for what is still being worked on,
/// as "Thinking…" or "Searching the orders…". Drawn in the muted colour with the foreground
/// passing over it; when the person asks for less motion it stands still, muted.
///
/// ```dart
/// Shimmer(child: Text('Thinking…'))
/// ```
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.enabled = true,
    this.period = const Duration(milliseconds: 1800),
  });

  final Widget child;

  /// False draws [child] as it is, with no light.
  final bool enabled;

  /// How long the light takes to cross.
  final Duration period;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _pass = AnimationController(vsync: this, duration: widget.period);

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Shimmer old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period) _pass.duration = widget.period;
    _sync();
  }

  void _sync() {
    if (widget.enabled && !_still) {
      if (!_pass.isAnimating) _pass.repeat();
    } else {
      _pass.stop();
    }
  }

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final c = AshlarTheme.of(context).colors;
    final base = c.mutedForeground, light = c.foreground;
    if (_still) {
      return DefaultTextStyle.merge(
        style: TextStyle(color: base),
        child: widget.child,
      );
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: _pass,
      child: widget.child,
      builder: (context, child) {
        // The light starts off one side and ends off the other, reading the way the text does.
        final at = -2.0 + 4 * _pass.value;
        final x = rtl ? -at : at;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(x - 1, 0),
            end: Alignment(x + 1, 0),
            colors: [base, light, base],
            stops: const [.3, .5, .7],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}
