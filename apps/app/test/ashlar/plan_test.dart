// Tests for Plan. Copied into your app by `ashlar add plan` with the component: they check
// what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/plan.dart';
import 'package:helmy/ui/core/ashlar/shimmer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(
  home: Padding(padding: const EdgeInsets.all(16), child: child),
);

const _steps = [
  PlanStep('Back up the table', status: PlanStepStatus.done),
  PlanStep('Copy the rows', status: PlanStepStatus.active, detail: '1.2M of 2M'),
  PlanStep('Switch reads over'),
  PlanStep('Drop the old table', status: PlanStepStatus.skipped),
];

void main() {
  group('Plan', () {
    testWidgets('counts what is done and shimmers the step it is on', (tester) async {
      await tester.pumpWidget(app(const Plan(title: 'Move orders', steps: _steps)));
      expect(find.text('Move orders'), findsOneWidget);
      expect(find.text('1 of 4 done'), findsOneWidget);
      expect(find.text('1.2M of 2M'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('Copy the rows'), matching: find.byType(Shimmer)),
        findsOneWidget,
      );
    });

    testWidgets('tells a screen reader where each step has got to', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const Plan(steps: _steps)));
      expect(
        tester.getSemantics(find.text('Back up the table')),
        matchesSemantics(label: 'Back up the table', value: 'done'),
      );
      expect(
        tester.getSemantics(find.text('Switch reads over')),
        matchesSemantics(label: 'Switch reads over', value: 'to do'),
      );
      handle.dispose();
    });

    testWidgets('shows why a step failed', (tester) async {
      await tester.pumpWidget(
        app(
          const Plan(
            steps: [
              PlanStep(
                'Send the receipt',
                status: PlanStepStatus.failed,
                detail: 'No email on the account',
              ),
            ],
          ),
        ),
      );
      expect(find.text('0 of 1 done'), findsOneWidget);
      expect(find.text('No email on the account'), findsOneWidget);
    });
  });
}
