import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/chat/widgets/design_inspector.dart';

void main() {
  test('colours read as the page computes them', () {
    expect(cssColor('rgb(24, 24, 20)'), const Color(0xFF181814));
    expect(cssColor('rgba(0, 0, 0, 0)'), const Color(0x00000000));
    expect(cssColor('rgba(255, 0, 0, 0.5)')!.a, closeTo(0.5, 0.01));
    expect(cssColor('rgb(24 24 20 / 50%)')!.a, closeTo(0.5, 0.01));
    expect(cssColor('#181814'), const Color(0xFF181814));
    expect(cssColor('currentcolor'), isNull);
  });

  test('colours are written back as CSS', () {
    expect(colorCss(const Color(0xFF181814)), '#181814');
    expect(colorCss(const Color(0x80FF0000)), 'rgba(255, 0, 0, 0.5)');
  });

  test('what is picked is read from the canvas, and an issue found by its property', () {
    final p = DesignPick.from({
      'file': 'home.html',
      'id': '0.2',
      'tag': 'div',
      'name': 'Group',
      'size': {'w': 120, 'h': 40},
      'sizing': {'width': 'fill', 'height': 'hug'},
      'styles': {'display': 'grid'},
      'parents': [
        {'id': '0', 'name': 'Group'},
      ],
      'issues': [
        {'what': 'display: grid', 'why': 'Use flexbox.'},
      ],
    });
    expect(p.sizingW, 'fill');
    expect(p.parents.single.id, '0');
    expect(p.issueFor('display'), 'Use flexbox.');
    expect(p.issueFor('position'), isNull);
  });
}
