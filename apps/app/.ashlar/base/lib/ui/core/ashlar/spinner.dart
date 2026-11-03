// Ashlar UI: Spinner. Copied into your app by `ashlar add spinner`; it is yours to change.

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

/// A turning ring that says something is working. Its colour and size come from the
/// IconTheme, so inside a Button it matches the label.
///
/// ```dart
/// Button(onPressed: null, leading: Spinner(), child: Text('Saving'))
/// ```
class Spinner extends StatefulWidget {
  const Spinner({
    super.key,
    this.size,
    this.color,
    this.semanticLabel = 'Loading',
  });

  /// Its width and height; the icon size around it when not given.
  final double? size;

  /// Its colour; the icon colour around it when not given.
  final Color? color;

  /// What a screen reader calls it when its visible text does not say, as for an icon
  /// alone.
  final String semanticLabel;

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.semanticLabel,
    liveRegion: true,
    child: ExcludeSemantics(
      child: RotationTransition(
        turns: _turn,
        child: AshlarIcon(
          AshlarIconsRoundedStroke.loaderCircle,
          size: widget.size,
          color: widget.color,
        ),
      ),
    ),
  );
}
