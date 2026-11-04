part of '../chat_items.dart';

/// The agent's task list, as it last stood.
class _Tasks extends StatelessWidget {
  const new(this.list);
  final TaskList list;

  @override
  Widget build(BuildContext context) => Plan(
    title: list.note,
    steps: [
      for (final t in list.tasks)
        PlanStep(
          t.text,
          status: switch (t.status) {
            .pending => PlanStepStatus.pending,
            .active => PlanStepStatus.active,
            .done => PlanStepStatus.done,
          },
        ),
    ],
  );
}
