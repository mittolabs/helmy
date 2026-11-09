import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A drawn mark in the gap between two sections, to carry the eye down.
///
/// Pencil rather than pen: these are structure, not notes, so they sit at low
/// contrast in white instead of the red the annotations use.
///
/// The first attempt shared an ending: every one dropped straight to the same
/// point and finished with the same arrowhead in the same place, so the half
/// you actually notice was identical three times over. These start in
/// different places, travel differently, and finish at different points on
/// different angles. No two are the same mark.
enum DividerShape {
  /// Tail out to the left, swings right, curls back on itself, leaves down
  /// the right-hand side.
  wander(
    'M14 20 C 58 6, 96 26, 108 54 C 116 74, 86 86, 86 66 C 86 46, 124 48, 132 78 C 138 100, 141 120, 137 139',
    'M127 127 L137 142 L149 129',
    'clamp(150px, 16vw, 224px)',
  ),

  /// In from the right, a wide loop, then away down the left.
  loop(
    'M206 16 C 166 8, 128 30, 118 58 C 110 82, 142 94, 144 70 C 146 46, 104 50, 92 84 C 84 108, 80 124, 76 140',
    'M64 129 L76 143 L88 131',
    'clamp(160px, 17vw, 236px)',
  ),

  /// A small coil at the top, then away down the left of centre.
  coil(
    'M112 10 C 140 16, 148 42, 124 48 C 102 53, 104 24, 132 28 C 168 33, 176 72, 146 96 C 126 112, 104 120, 94 138',
    'M82 128 L94 142 L107 132',
    'clamp(148px, 16vw, 220px)',
  ),

  /// A tight scribble that unwinds into a long drop through the middle.
  wave(
    'M24 16 C 68 2, 80 40, 54 52 C 28 64, 22 32, 60 28 C 110 22, 142 52, 128 92 C 121 110, 106 116, 104 132',
    'M93 120 L104 135 L116 123',
    'clamp(140px, 15vw, 208px)',
  );

  const DividerShape(this.stroke, this.head, this.width);

  final String stroke;
  final String head;
  final String width;
}

class Divider extends StatelessComponent {
  const Divider(this.shape, {super.key});

  final DividerShape shape;

  @override
  Component build(BuildContext context) => div(
    classes: 'divider',
    styles: Styles(raw: {'--w': shape.width}),
    attributes: {'aria-hidden': 'true'},
    [
      svg(
        viewBox: '0 0 220 150',
        attributes: {
          'fill': 'none',
          'stroke': 'currentColor',
          'stroke-width': '2',
          'stroke-linecap': 'round',
          'stroke-linejoin': 'round',
        },
        [
          path(d: shape.stroke, []),
          path(d: shape.head, []),
        ],
      ),
    ],
  );
}
