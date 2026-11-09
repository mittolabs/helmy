import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Which way a [Scribble]'s arrow runs from its note.
enum ScribbleDirection {
  /// Leaves the note on the left, bends over and comes down on the right.
  downRight(
    'downRight',
    '0 0 150 84',
    'M6 12 C 44 3, 92 9, 118 30 C 132 41, 136 55, 131 74',
    'M118 60 L131 75 L142 58',
  ),

  /// Rises from the note to something sitting above it.
  upRight(
    'upRight',
    '0 0 132 76',
    'M8 70 C 22 44, 52 22, 96 13 C 106 11, 114 11, 121 13',
    'M104 4 L122 13 L106 25',
  ),

  /// Rises from the note to something sitting above it and to the left.
  upLeft(
    'upLeft',
    '0 0 132 76',
    'M124 70 C 110 44, 80 22, 36 13 C 26 11, 18 11, 11 13',
    'M28 4 L10 13 L26 25',
  ),

  /// Leaves the note on the right, bends back down to the left.
  downLeft(
    'downLeft',
    '0 0 150 84',
    'M144 12 C 106 3, 58 9, 32 30 C 18 41, 14 55, 19 74',
    'M32 60 L19 75 L8 58',
  );

  const ScribbleDirection(this.className, this.viewBox, this.stroke, this.head);

  final String className;
  final String viewBox;
  final String stroke;
  final String head;
}

/// A drawn arrow with a note beside it, of the sort somebody would scrawl on a
/// printout. Drawn here rather than pulled from a stock set: the curve wants to
/// suit the thing it points at, and a bought squiggle never quite does.
///
/// The wobble is deliberate. A perfect bezier reads as a diagram; the give in
/// these control points is what makes it read as a hand.
class Scribble extends StatelessComponent {
  const Scribble({
    required this.text,
    this.direction = ScribbleDirection.downRight,
    this.classes,
    super.key,
  });

  final String text;
  final ScribbleDirection direction;
  final String? classes;

  @override
  Component build(BuildContext context) => span(
    classes: ['scribble', direction.className, ?classes].join(' '),
    attributes: {'aria-hidden': 'true'},
    [
      span(classes: 'scribble-note', [Component.text(text)]),
      svg(
        viewBox: direction.viewBox,
        attributes: {
          'fill': 'none',
          'stroke': 'currentColor',
          'stroke-width': '2.1',
          'stroke-linecap': 'round',
          'stroke-linejoin': 'round',
        },
        [
          path(d: direction.stroke, []),
          path(d: direction.head, []),
        ],
      ),
    ],
  );
}
