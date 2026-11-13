// Tests for Color Picker. Copied into your app by `ashlar add color-picker` with the
// component: they check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/color_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) => AshlarApp(
  themeMode: mode,
  home: Center(child: child),
);

/// A picker that keeps what it is given.
class Held extends StatefulWidget {
  const Held({super.key, this.alpha = false, this.start = const Color(0xFF2563EB)});

  final bool alpha;
  final Color start;

  @override
  State<Held> createState() => HeldState();
}

class HeldState extends State<Held> {
  late Color color = widget.start;

  @override
  Widget build(BuildContext context) => ColorPicker(
    value: color,
    alpha: widget.alpha,
    swatches: const [Color(0xFFDC2626), Color(0xFF16A34A)],
    onChanged: (c) => setState(() => color = c),
  );
}

Color held(WidgetTester tester) => tester.state<HeldState>(find.byType(Held)).color;

void main() {
  test('hex reads and writes', () {
    expect(colorHex(const Color(0xFF2563EB)), '2563EB');
    expect(colorHex(const Color(0x802563EB), alpha: true), '802563EB');
    expect(parseColorHex('#2563eb'), const Color(0xFF2563EB));
    expect(parseColorHex('fff'), const Color(0xFFFFFFFF));
    expect(parseColorHex('802563EB'), const Color(0x802563EB));
    expect(parseColorHex('blue'), isNull);
  });

  testWidgets('it draws in light and dark, with opacity', (tester) async {
    for (final mode in AshlarThemeMode.values) {
      await tester.pumpWidget(app(const Held(alpha: true), mode: mode));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a tap in the square sets saturation and brightness', (tester) async {
    await tester.pumpWidget(app(const Held()));
    final square = tester.getRect(find.byType(CustomPaint).first);
    // The top right corner: fully saturated, fully bright.
    await tester.tapAt(square.topRight + const Offset(-1, 1));
    final hsv = HSVColor.fromColor(held(tester));
    expect(hsv.saturation, greaterThan(.98));
    expect(hsv.value, greaterThan(.98));
    // The bottom: black.
    await tester.tapAt(square.bottomCenter - const Offset(0, 1));
    expect(HSVColor.fromColor(held(tester)).value, lessThan(.02));
  });

  testWidgets('the keys move the hue', (tester) async {
    await tester.pumpWidget(app(const Held()));
    final before = HSVColor.fromColor(held(tester)).hue;
    // The square, then the hue strip.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(HSVColor.fromColor(held(tester)).hue, closeTo(before + 10, 1));
  });

  testWidgets('typing a hex chooses it; a swatch chooses at a tap', (tester) async {
    await tester.pumpWidget(app(const Held()));
    await tester.enterText(find.byType(EditableText), '16a34a');
    await tester.pump();
    expect(held(tester), const Color(0xFF16A34A));
    await tester.tap(find.bySemanticsLabel('#DC2626'));
    await tester.pump();
    expect(held(tester), const Color(0xFFDC2626));
  });

  testWidgets('the button shows the colour and opens the picker', (tester) async {
    var color = const Color(0xFF2563EB);
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, set) => ColorPickerButton(
            value: color,
            label: 'Primary',
            onChanged: (c) => set(() => color = c),
          ),
        ),
      ),
    );
    expect(find.text('#2563EB'), findsOneWidget);
    await tester.tap(find.text('Primary'));
    await tester.pumpAndSettle();
    expect(find.byType(ColorPicker), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'dc2626');
    await tester.pump();
    expect(color, const Color(0xFFDC2626));
  });
}
