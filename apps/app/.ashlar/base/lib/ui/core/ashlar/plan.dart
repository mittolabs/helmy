// Ashlar UI: Plan. Copied into your app by `ashlar add plan`; it is yours to change.

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import 'shimmer.dart';
import 'spinner.dart';
import 'theme.dart';

/// Where a step of a plan has got to.
enum PlanStepStatus { pending, active, done, skipped, failed }

/// One step of a plan: what it is, where it has got to, and a line more if it needs one.
class PlanStep {
  const PlanStep(
    this.title, {
    this.status = PlanStepStatus.pending,
    this.detail,
  });

  final String title;
  final PlanStepStatus status;

  /// A line under the title: what was found, why it failed.
  final String? detail;
}

/// The steps an assistant set itself, ticked off as it works: done ones ticked, the one it
/// is on turning and shimmering, those to come as empty rings, and how many are done at
/// the top.
///
/// ```dart
/// Plan(
///   title: 'Move the orders table',
///   steps: [
///     PlanStep('Back up the table', status: PlanStepStatus.done),
///     PlanStep('Copy the rows across', status: PlanStepStatus.active, detail: '1.2M of 2M'),
///     PlanStep('Switch reads over'),
///   ],
/// )
/// ```
class Plan extends StatelessWidget {
  const Plan({super.key, required this.steps, this.title});

  final List<PlanStep> steps;

  /// What the plan is for, above the steps.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final done = steps.where((s) => s.status == PlanStepStatus.done).length;
    final count = '$done of ${steps.length} done';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title ?? 'Plan',
                  style: t.text.sm.copyWith(
                    color: c.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                count,
                style: t.text.xs.copyWith(
                  color: c.mutedForeground,
                  height: 20 / 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // How far along, as a thin bar: read out as the count above.
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: c.muted)),
                    FractionallySizedBox(
                      widthFactor: steps.isEmpty ? 0 : done / steps.length,
                      heightFactor: 1,
                      alignment: AlignmentDirectional.centerStart,
                      child: ColoredBox(color: c.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          for (final s in steps) _Step(step: s),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.step});

  final PlanStep step;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final (Widget mark, String said) = switch (step.status) {
      PlanStepStatus.pending => (
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.input, width: 1.5),
          ),
        ),
        'to do',
      ),
      PlanStepStatus.active => (
        Spinner(size: 14, color: c.foreground, semanticLabel: ''),
        'in progress',
      ),
      PlanStepStatus.done => (
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary),
          child: AshlarIcon(
            AshlarIconsRoundedStroke.check,
            size: 11,
            color: c.primaryForeground,
          ),
        ),
        'done',
      ),
      PlanStepStatus.skipped => (
        AshlarIcon(
          AshlarIconsRoundedStroke.circleMinus,
          size: 16,
          color: c.mutedForeground,
        ),
        'skipped',
      ),
      PlanStepStatus.failed => (
        AshlarIcon(
          AshlarIconsRoundedStroke.circleX,
          size: 16,
          color: c.destructive,
        ),
        'failed',
      ),
    };
    final quiet =
        step.status == PlanStepStatus.pending ||
        step.status == PlanStepStatus.skipped;
    final title = Text(
      step.title,
      style: t.text.sm.copyWith(
        color: quiet ? c.mutedForeground : c.foreground,
        fontWeight: step.status == PlanStepStatus.active
            ? FontWeight.w500
            : null,
        decoration: step.status == PlanStepStatus.skipped
            ? TextDecoration.lineThrough
            : null,
        decorationColor: c.mutedForeground,
      ),
    );
    return MergeSemantics(
      child: Semantics(
        value: said,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 16,
                height: 20,
                child: Center(child: ExcludeSemantics(child: mark)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (step.status == PlanStepStatus.active)
                      Shimmer(child: title)
                    else
                      title,
                    if (step.detail != null)
                      Text(
                        step.detail!,
                        style: t.text.xs.copyWith(
                          color: step.status == PlanStepStatus.failed
                              ? c.destructive
                              : c.mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
