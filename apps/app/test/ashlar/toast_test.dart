// Tests for Toast. Copied into your app by `ashlar add toast` with the component: they
// check what it promises, so change them as you change it.
import 'dart:async';

import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/button.dart';
import 'package:helmy/ui/core/ashlar/toast.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {AshlarThemeMode mode = AshlarThemeMode.light}) => AshlarApp(
  themeMode: mode,
  home: Center(child: child),
);

Future<BuildContext> page(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    AshlarApp(
      home: Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        },
      ),
    ),
  );
  return ctx;
}

void main() {
  group('Toast', () {
    testWidgets('shows, then goes by itself', (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Button(
              onPressed: () => showToast(context, title: 'Payment sent', description: '\$240'),
              child: const Text('Pay'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();
      expect(find.text('Payment sent'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Payment sent'), findsNothing);
    });

    testWidgets('keeps the newest three', (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) {
              var n = 0;
              return Button(
                onPressed: () => showToast(context, title: 'Toast ${++n}'),
                child: const Text('Go'),
              );
            },
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Go'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(find.text('Toast 1'), findsNothing);
      expect(find.text('Toast 4'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a swipe sends it away', (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Button(
              onPressed: () =>
                  showToast(context, title: 'Swipe me', duration: const Duration(minutes: 1)),
              child: const Text('Go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      await tester.fling(find.text('Swipe me'), const Offset(400, 0), 2000);
      await tester.pumpAndSettle();
      expect(find.text('Swipe me'), findsNothing);
    });
  });

  testWidgets('a promise toast loads, then says how it went', (tester) async {
    final ctx = await page(tester);
    final done = Completer<int>();
    showToastPromise<int>(
      ctx,
      done.future,
      loading: 'Saving…',
      success: (n) => 'Saved $n items',
      error: (e) => 'Could not save',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saving…'), findsOneWidget);
    // Loading waits however long it takes.
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Saving…'), findsOneWidget);
    done.complete(3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saved 3 items'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Saved 3 items'), findsNothing);
  });

  testWidgets('a failed promise says so', (tester) async {
    final ctx = await page(tester);
    showToastPromise<int>(
      ctx,
      Future.error('down'),
      loading: 'Saving…',
      success: (n) => 'Saved',
      error: (e) => 'Could not save: $e',
    ).ignore();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Could not save: down'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('the close button sends it away; a handle can too', (tester) async {
    final semantics = tester.ensureSemantics();
    final ctx = await page(tester);
    showToast(ctx, title: 'Closable', closeButton: true, duration: const Duration(minutes: 1));
    await tester.pumpAndSettle();
    // Its own button, apart from the toast, so the message is not read as a button.
    expect(
      tester.getSemantics(find.text('Closable')).getSemanticsData().flagsCollection.isButton,
      isFalse,
    );
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Closable'), findsNothing);
    final h = showToast(ctx, title: 'Handled', duration: const Duration(minutes: 1));
    await tester.pumpAndSettle();
    h.dismiss();
    await tester.pumpAndSettle();
    expect(find.text('Handled'), findsNothing);
    semantics.dispose();
  });

  testWidgets('toasts go where asked', (tester) async {
    final ctx = await page(tester);
    showToast(
      ctx,
      title: 'Top left',
      position: ToastPosition.topLeft,
      duration: const Duration(minutes: 1),
    );
    showToast(
      ctx,
      title: 'Bottom centre',
      position: ToastPosition.bottomCenter,
      duration: const Duration(minutes: 1),
    );
    await tester.pumpAndSettle();
    final tl = tester.getRect(find.text('Top left')),
        bc = tester.getRect(find.text('Bottom centre'));
    expect(tl.top, lessThan(80));
    expect(tl.left, lessThan(100));
    expect(bc.bottom, greaterThan(500));
    expect(bc.center.dx, closeTo(400, 180));
  });

  testWidgets('stacked, only the newest shows; the pointer fans them out and holds them', (
    tester,
  ) async {
    final ctx = await page(tester);
    for (final n in ['One', 'Two', 'Three']) {
      showToast(
        ctx,
        title: n,
        type: ToastType.success,
        action: Button(size: ButtonSize.sm, onPressed: () {}, child: Text('Undo $n')),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    // Behind the front card, the others keep their content out of sight.
    expect(find.text('Three'), findsOneWidget);
    expect(find.text('Two'), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Three')));
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    expect(
      tester.getRect(find.text('Two')).bottom,
      lessThan(tester.getRect(find.text('Three')).top),
    );
    // Held past their time while the pointer is over them.
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('One'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Three'), findsNothing);
  });
}
