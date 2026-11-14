part of '../chat_items.dart';

/// A plan the agent wants approved before it starts: the plan itself, and
/// whether to go ahead or keep planning.
class _PlanApproval extends StatelessWidget {
  const new(this.call, this.prompt, this.vm);
  final ToolCall call;
  final PermissionPrompt? prompt;
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final p = prompt;
    final asking = p != null && p.decision == .pending;
    return Container(
      padding: const .all(16),
      decoration: BoxDecoration(
        border: Border.all(color: asking ? c(t) : t.colors.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Text('Proposed plan', style: t.text.sm.copyWith(fontWeight: .w600)),
          Markdown('${call.input['plan'] ?? ''}'),
          if (asking)
            Wrap(
              spacing: 8,
              children: [
                Button(
                  size: .sm,
                  onPressed: () => vm.approvePlan(p),
                  child: const Text('Approve plan'),
                ),
                Button(
                  size: .sm,
                  variant: .outline,
                  onPressed: () => vm.deny(p),
                  child: const Text('Keep planning'),
                ),
              ],
            )
          else
            Text(switch (p?.decision) {
              PermissionDecision.allowed || PermissionDecision.allowedAlways => 'Approved',
              PermissionDecision.denied => 'You asked it to keep planning',
              _ => 'Not answered',
            }, style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
        ],
      ),
    );
  }

  static Color c(AshlarThemeData t) => t.colors.foreground;
}

class _Question extends StatelessWidget {
  const new(this.prompt, this.vm);
  final PermissionPrompt prompt;
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    if (!prompt.needsAnswer) {
      final answered = prompt.answers.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      return Text(
        answered.isEmpty ? 'A question that was not answered' : answered,
        style: t.text.sm.copyWith(color: t.colors.mutedForeground),
      );
    }
    final questionnaire = Questionnaire(
      shortcuts: .numbers,
      questions: [
        for (final q in prompt.questions)
          Question(
            name: q['question'] as String? ?? '',
            prompt: q['question'] as String? ?? '',
            description: q['header'] as String?,
            multiple: q['multiSelect'] == true,
            required: true,
            choices: [
              for (final o in ((q['options'] as List?) ?? const []).whereType<Map>())
                QuestionChoice(
                  o['label'] as String? ?? '',
                  o['label'] as String? ?? '',
                  description: o['description'] as String?,
                ),
            ],
          ),
      ],
      onSubmit: (answers) {
        for (final MapEntry(:key, :value) in answers.entries) {
          final parts = [...value.picked, if (value.text.isNotEmpty) value.text];
          vm.choose(prompt, key, parts.join(', '));
        }
        vm.submitAnswers(prompt);
      },
    );
    if (prompt.decision != .waiting) return questionnaire;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        Text(
          'You were away, so it went on with its own choice. Your answer still reaches it.',
          style: t.text.xs.copyWith(color: t.colors.mutedForeground),
        ),
        questionnaire,
      ],
    );
  }
}
