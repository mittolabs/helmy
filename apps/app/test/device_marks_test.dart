import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/device_marks.dart';
import 'package:helmy/domain/device_outline.dart';

ScreenElement el(String label, double x, double y, double w, double h) => (
  ref: 'd1',
  kind: 'Button',
  label: label,
  value: null,
  x: x,
  y: y,
  width: w,
  height: h,
  enabled: true,
  depth: 1,
);

void main() {
  test('a mark points at the smallest element holding its middle', () {
    final elements = [
      el('Screen', 0, 0, 400, 800),
      el('General', 20, 300, 360, 44),
      el('Icon', 24, 306, 30, 30),
    ];
    // A box around the General row, in shares of a 400 by 800 screen.
    final under = elementUnder(
      elements,
      left: .1,
      top: .37,
      width: .8,
      height: .06,
      unitsWide: 400,
      unitsHigh: 800,
    );
    expect(under?.label, 'General');
    final none = elementUnder(
      const [],
      left: 0,
      top: 0,
      width: 1,
      height: 1,
      unitsWide: 1,
      unitsHigh: 1,
    );
    expect(none, isNull);
  });

  test('the marks read as a numbered list, with what is under each', () {
    final text = deviceMarksMarkdown('iPhone 17 Pro', [
      (
        n: 1,
        left: 0,
        top: 0,
        width: .1,
        height: .1,
        note: 'Make this bigger',
        element: el('General', 0, 0, 1, 1),
      ),
      (n: 2, left: 0, top: 0, width: .1, height: .1, note: '', element: null),
    ], picture: 'marks.png');
    expect(text, contains('# Marks on iPhone 17 Pro'));
    expect(text, contains('marks.png'));
    expect(text, contains('1. Button "General": Make this bigger'));
    expect(text, contains('2. A part of the screen\n'));
  });
}
