// Ashlar UI: Skeleton. Copied into your app by `ashlar add skeleton`; it is yours to change.

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// A placeholder in the shape of content that is still loading. It pulses, unless the
/// device asks for less motion.
///
/// ```dart
/// Row(children: [Skeleton(width: 40, height: 40, circle: true), SizedBox(width: 12), Skeleton(width: 160, height: 16)])
/// ```
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 16,
    this.circle = false,
  });

  /// Null fills the width it is given.
  final double? width;

  /// Its height.
  final double height;

  /// Round, for where an avatar will be.
  final bool circle;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final box = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: t.colors.accent,
        shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: widget.circle ? null : BorderRadius.circular(t.radiusMd),
      ),
    );
    return ExcludeSemantics(
      child: still
          ? box
          : FadeTransition(
              opacity: Tween(begin: 1.0, end: .5).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: box,
            ),
    );
  }
}
