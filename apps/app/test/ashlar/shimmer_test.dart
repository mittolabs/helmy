// Tests for Shimmer. Copied into your app by `ashlar add shimmer` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/shimmer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {bool still = false}) => AshlarApp(
  builder: (context, page) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: still),
    child: page!,
  ),
  home: Center(child: child),
);

void main() {
  group('Shimmer', () {
    testWidgets('passes a light across its child', (tester) async {
      await tester.pumpWidget(app(const Shimmer(child: Text('Thinking…'))));
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(find.text('Thinking…'), findsOneWidget);
      // It keeps moving, so the test does not wait for it to settle.
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('stands still when less motion is asked for', (tester) async {
      await tester.pumpWidget(app(const Shimmer(child: Text('Thinking…')), still: true));
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('draws its child as it is when not enabled', (tester) async {
      await tester.pumpWidget(app(const Shimmer(enabled: false, child: Text('Done'))));
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
