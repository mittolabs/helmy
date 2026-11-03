// Ashlar UI: Separator. Copied into your app by `ashlar add separator`; it is yours to change.

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// A one-pixel line between things, across ([Axis.horizontal]) or down ([Axis.vertical]).
class Separator extends StatelessWidget {
  const Separator({super.key, this.axis = Axis.horizontal});

  /// Horizontal draws a line across; vertical, down.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final color = AshlarTheme.of(context).colors.border;
    return axis == Axis.horizontal
        ? SizedBox(
            height: 1,
            width: double.infinity,
            child: ColoredBox(color: color),
          )
        : SizedBox(
            width: 1,
            height: double.infinity,
            child: ColoredBox(color: color),
          );
  }
}
