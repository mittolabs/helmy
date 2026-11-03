// Ashlar UI: joined controls. Copied in by `ashlar add` with Button Group or Toggle
// Group; it is yours to change.

import 'package:flutter/widgets.dart';

/// Sets controls side by side as one piece: only the outer corners are round, and
/// neighbours share one border between them. Button and Toggle read where they sit.
class JoinedGroup extends StatelessWidget {
  const JoinedGroup({
    super.key,
    required this.children,
    this.axis = Axis.horizontal,
  });

  /// What it holds, in order.
  final List<Widget> children;

  /// Horizontal lays it out across; vertical, down.
  final Axis axis;

  @override
  Widget build(BuildContext context) => Flex(
    direction: axis,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, child) in children.indexed)
        JoinedPosition(
          first: i == 0,
          last: i == children.length - 1,
          axis: axis,
          child: child,
        ),
    ],
  );
}

/// Where a control sits in a [JoinedGroup].
class JoinedPosition extends InheritedWidget {
  const JoinedPosition({
    super.key,
    required this.first,
    required this.last,
    required this.axis,
    required super.child,
  });

  /// Whether it starts the group, which rounds its leading corners.
  final bool first;

  /// Whether it ends the group, which rounds its trailing corners.
  final bool last;

  /// The direction the group runs.
  final Axis axis;

  static JoinedPosition? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<JoinedPosition>();

  /// Round only on the group's outer corners.
  BorderRadiusGeometry radius(double r) {
    final start = first ? Radius.circular(r) : Radius.zero,
        end = last ? Radius.circular(r) : Radius.zero;
    return axis == Axis.horizontal
        ? BorderRadiusDirectional.horizontal(start: start, end: end)
        : BorderRadius.vertical(top: start, bottom: end);
  }

  /// A border with no leading edge after the first, so neighbours share one line. The
  /// leading edge is the right in right-to-left text. (A plain [Border], resolved here,
  /// because only it can round corners with an edge missing.)
  Border border(Color color, TextDirection direction) {
    final side = BorderSide(color: color);
    final lead = first ? side : BorderSide.none;
    final rtl = direction == TextDirection.rtl;
    return axis == Axis.horizontal
        ? Border(
            top: side,
            bottom: side,
            left: rtl ? side : lead,
            right: rtl ? lead : side,
          )
        : Border(
            left: side,
            right: side,
            bottom: side,
            top: first ? side : BorderSide.none,
          );
  }

  @override
  bool updateShouldNotify(JoinedPosition old) =>
      old.first != first || old.last != last || old.axis != axis;
}

/// A control's corners: [r] all round, or only the outer ones inside a [JoinedGroup].
BorderRadiusGeometry joinedRadius(BuildContext context, double r) =>
    JoinedPosition.maybeOf(context)?.radius(r) ?? BorderRadius.circular(r);

/// A control's border: all round, or sharing edges inside a [JoinedGroup].
Border joinedBorder(BuildContext context, Color color) =>
    JoinedPosition.maybeOf(context)
        ?.border(color, Directionality.maybeOf(context) ?? TextDirection.ltr) ??
    Border.all(color: color);
