// Tests for ToolCall. Copied into your app by `ashlar add tool-call` with the component:
// they check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/shimmer.dart';
import 'package:helmy/ui/core/ashlar/tool_call.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(
  home: Padding(padding: const EdgeInsets.all(16), child: child),
);

void main() {
  group('ToolCall', () {
    testWidgets('says what it did and where it got to', (tester) async {
      await tester.pumpWidget(
        app(
          const ToolCall(
            title: 'Look up order 1042',
            name: 'get_order',
            input: '{"order": 1042}',
            output: '{"status": "paid"}',
          ),
        ),
      );
      expect(find.text('Look up order 1042'), findsOneWidget);
      expect(find.text('get_order'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      // Folded until asked for.
      expect(find.text('{"status": "paid"}').hitTestable(), findsNothing);
      await tester.tap(find.text('Look up order 1042'));
      await tester.pumpAndSettle();
      expect(find.text('{"order": 1042}').hitTestable(), findsOneWidget);
      expect(find.text('{"status": "paid"}').hitTestable(), findsOneWidget);
    });

    testWidgets('shimmers while running', (tester) async {
      await tester.pumpWidget(
        app(const ToolCall(name: 'search', status: ToolCallStatus.running)),
      );
      expect(find.text('Running'), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
    });

    testWidgets('opens to ask the person, and tells their answer', (
      tester,
    ) async {
      var approved = 0, denied = 0;
      await tester.pumpWidget(
        app(
          ToolCall(
            title: 'Refund \$25',
            name: 'refund_order',
            status: ToolCallStatus.approval,
            approval: 'Refund \$25 to Maya?',
            onApprove: () => approved++,
            onDeny: () => denied++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Needs approval'), findsOneWidget);
      expect(
        find.text('Refund \$25 to Maya?').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('Approve'));
      await tester.tap(find.text('Deny'));
      expect((approved, denied), (1, 1));
    });

    testWidgets('shows what went wrong', (tester) async {
      await tester.pumpWidget(
        app(
          const ToolCall(
            name: 'send_sms',
            status: ToolCallStatus.error,
            error: 'The number is not on the account.',
            initiallyOpen: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('The number is not on the account.'), findsOneWidget);
    });

    testWidgets('reads as one line to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(const ToolCall(name: 'get_order', input: '{}')),
      );
      expect(find.bySemanticsLabel('get_order, Done'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('fits a phone with a long name', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          const ToolCall(
            title: 'Look up every order placed from the Downtown branch',
            name: 'list_orders_for_branch_with_items',
            status: ToolCallStatus.approval,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
