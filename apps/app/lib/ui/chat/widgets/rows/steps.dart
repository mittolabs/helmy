part of '../chat_items.dart';

/// What a helper agent did, one quiet line per step, in order.
class _HelperSteps extends StatelessWidget {
  const new(this.steps);
  final List<ToolCall> steps;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    return Container(
      padding: const .fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.colors.border, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 3,
        children: [
          Text('What the helper did', style: muted.copyWith(fontWeight: .w600)),
          for (final s in steps)
            Text(
              [
                stepTitle(s, done: s.done),
                if (s.summary.isNotEmpty && s.input['command'] == null && s.activityLabel == null)
                  s.summary,
                if (s.isError && !s.declined) 'failed',
              ].join('  ·  '),
              maxLines: 1,
              overflow: .ellipsis,
              style: muted,
            ),
        ],
      ),
    );
  }
}

/// A file's change, as the Changes panel shows it, cut shorter: the page
/// keeps one scroll.
class _Diff extends StatelessWidget {
  const new(this.diff);
  final FileDiff diff;

  @override
  Widget build(BuildContext context) => DiffView(diff: diff, maxRows: 60);
}

/// A concrete account of the work, with factual per-action labels as a fallback.
String stepsSummary(List<ToolCall> calls) {
  if (calls.isEmpty) return 'Work';
  if (calls.last.activitySummary != null &&
      listEquals(calls.last.activityIds, [for (final c in calls) c.id])) {
    return calls.last.activitySummary!;
  }
  final labels = {for (final c in calls) stepTitle(c, done: c.done)}.toList();
  String lower(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
  if (labels.length == 1) return labels.single;
  if (labels.length == 2) return '${labels.first} and ${lower(labels[1])}';
  return '${labels.first}, ${labels.skip(1).take(labels.length - 2).map(lower).join(', ')} and ${lower(labels.last)}';
}

/// Several steps in a row as one quiet line that opens to each of them.
class _StepGroup extends StatelessWidget {
  const new(this.steps, this.vm);
  final List<(int, ToolCall, PermissionPrompt?)> steps;
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) => FutureBuilder<ActivitySummary?>(
    future: vm.describeActivities([for (final s in steps) s.$2]),
    builder: (context, _) => _body(context),
  );

  Widget _body(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final calls = [for (final s in steps) s.$2];
    final running = vm.busy && calls.any((c) => !c.done);
    // A step turned down says so in its own words; it has not failed.
    final failed = calls.where((c) => c.isError && !c.declined).length;
    final muted = t.text.sm.copyWith(color: c.mutedForeground);
    final title = stepsSummary(calls);
    return Collapsible(
      builder: (context, open, toggle) => Pressable(
        onPressed: toggle,
        semanticLabel: '$title. ${open ? 'Hide' : 'Show'} steps',
        builder: (context, state) => Padding(
          padding: const .symmetric(vertical: 3),
          child: Row(
            spacing: 8,
            children: [
              SizedBox.square(
                dimension: 14,
                child: running
                    ? const Spinner(size: 12, semanticLabel: 'Running')
                    : AshlarIcon(
                        open
                            ? AshlarIconsRoundedStroke.chevronDown
                            : AshlarIconsRoundedStroke.chevronRight,
                        size: 14,
                        color: c.mutedForeground,
                      ),
              ),
              Flexible(
                child: Text(
                  failed > 0 ? '$title, $failed failed' : title,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: muted.copyWith(color: state.hovered ? c.foreground : c.mutedForeground),
                ),
              ),
            ],
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 22, top: 2),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [for (final (_, call, p) in steps) _Step(call, p, vm, describe: false)],
        ),
      ),
    );
  }
}

/// What a step did, in words, whichever engine took it: "Ran a command",
/// "Edited notes.md". [done] picks the tense.
String stepTitle(ToolCall call, {required bool done}) {
  // Turned down: what it would have done, not done.
  if (call.declined) return declinedLabel(_title(call, done: true));
  return _title(call, done: done);
}

String _title(ToolCall call, {required bool done}) {
  if (done && (call.activityLabel ?? '').isNotEmpty) return call.activityLabel!;
  final description = call.input['description'];
  // A description that is only the command again says nothing a person reads: the
  // step's own words instead.
  if (call.input['command'] is String &&
      description is String &&
      description.trim().isNotEmpty &&
      description.trim() != (call.input['command']! as String).trim() &&
      description.length <= 140 &&
      !description.contains('\n')) {
    return description.trim();
  }
  if (call.input['actions'] case final List actions) {
    if (actionsLabel(actions, done: done) case final label?) return label;
  }
  String file() {
    final path = '${call.input['file_path'] ?? call.input['notebook_path'] ?? ''}';
    final first = path.split(', ').first;
    return first.isEmpty ? 'a file' : first.split('/').last;
  }

  String pick(String did, String doing) => done ? did : doing;
  if (call.input['by'] == 'you') return pick('You ran a command', 'Running your command');
  return switch (call.name) {
    'Bash' || 'Shell' => specificCommandLabel(
      PermissionRule.plainCommand('${call.input['command'] ?? ''}'),
      done: done,
      result: call.result,
    ),
    // Run with the Vault's keys: said as the command it ran.
    _ when call.name.endsWith('vault_run') && call.input['command'] is String =>
      specificCommandLabel(
        PermissionRule.plainCommand(call.input['command']! as String),
        done: done,
        result: call.result,
      ),
    'Read' => pick('Read ${file()}', 'Reading ${file()}'),
    'Write' => pick('Wrote ${file()}', 'Writing ${file()}'),
    'Edit' || 'NotebookEdit' => pick('Edited ${file()}', 'Editing ${file()}'),
    'Glob' || 'Grep' => pick('Searched the files', 'Searching the files'),
    'WebSearch' => pick('Searched the web', 'Searching the web'),
    'WebFetch' => pick('Read a web page', 'Reading a web page'),
    'Task' || 'Agent' => pick('Asked a helper', 'Asking a helper'),
    'TodoWrite' => pick('Updated the plan', 'Updating the plan'),
    'ImageGeneration' => pick('Made an image', 'Making an image'),
    _ when ownStep(call.name) != null => pick(ownStep(call.name)!.$1, ownStep(call.name)!.$2),
    _ => pick('Used ${toolLabel(call.name)}', 'Using ${toolLabel(call.name)}'),
  };
}

/// One step the agent took, as a quiet line that opens to what went in and
/// what came out. An approval it waits on shows open, with its answers.
class _Step extends StatelessWidget {
  const new(this.call, this.prompt, this.vm, {this.describe = true});
  final ToolCall call;
  final PermissionPrompt? prompt;
  final ChatViewModel vm;
  final bool describe;

  @override
  Widget build(BuildContext context) => !describe
      ? _body(context)
      : FutureBuilder<ActivitySummary?>(
          future: vm.describeActivities([call]),
          builder: (context, _) => _body(context),
        );

  Widget _body(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final p = prompt;
    final asking = p != null && p.decision == .pending;
    final denied = p?.decision == .denied || p?.decision == .blockedByHelmy;
    final failed = call.isError || denied;
    final running = !call.done && !asking && !denied && vm.busy;
    final muted = t.text.sm.copyWith(color: c.mutedForeground);
    final shell = call.input['command'] is String;
    final activity = commandActivity(PermissionRule.plainCommand('${call.input['command'] ?? ''}'));
    final detail = shell || call.activityLabel != null ? '' : call.summary;
    final title = asking ? 'Technical details' : stepTitle(call, done: !running);
    final step = Collapsible(
      initiallyOpen: !asking && context.read<SettingsRepository>().settings.stepsOpen,
      builder: (context, open, toggle) => Pressable(
        onPressed: toggle,
        semanticLabel: '$title. ${open ? 'Hide' : 'Show'} details',
        builder: (context, state) => Padding(
          padding: const .symmetric(vertical: 3),
          child: Row(
            spacing: 8,
            children: [
              SizedBox.square(
                dimension: 14,
                child: running
                    ? const Spinner(size: 12, semanticLabel: 'Running')
                    // Down while open, as the step groups' arrows are; a
                    // failed step keeps its mark.
                    : AshlarIcon(
                        failed
                            ? AshlarIconsRoundedStroke.x
                            : open
                            ? AshlarIconsRoundedStroke.chevronDown
                            : AshlarIconsRoundedStroke.chevronRight,
                        size: 14,
                        color: c.mutedForeground,
                      ),
              ),
              // A long title ends in an ellipsis, as a step group's does, rather than
              // running past the column.
              Flexible(
                flex: 2,
                child: Text(
                  denied && !call.declined
                      ? '$title, stopped'
                      : failed && !call.declined
                      ? '$title, failed'
                      : title,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: muted.copyWith(
                    color: state.hovered || asking ? c.foreground : c.mutedForeground,
                    fontWeight: asking ? .w500 : null,
                  ),
                ),
              ),
              if (call.background case final task?) BackgroundBadge(task),
              if (call.children.isNotEmpty)
                Text(
                  '${call.children.length} step${call.children.length == 1 ? '' : 's'}',
                  style: muted.copyWith(fontSize: 12),
                ),
              if (diffsOf(call) case final ds when ds.isNotEmpty)
                Text(
                  '+${ds.fold(0, (n, d) => n + d.added)} -${ds.fold(0, (n, d) => n + d.removed)}',
                  style: muted.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: monoFonts,
                    fontSize: 12,
                  ),
                ),
              // Open, what it ran shows in full below: not twice.
              if (!open && detail.isNotEmpty && detail != title)
                Flexible(
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: muted.copyWith(color: c.mutedForeground.withValues(alpha: .7)),
                  ),
                ),
            ],
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 22, top: 4, bottom: 6),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 8,
          children: [
            if (asking && (p.why ?? '').isNotEmpty) Text(p.why!, style: t.text.sm),
            if (call.children.isNotEmpty) _HelperSteps(call.children),
            if (diffsOf(call).isNotEmpty)
              for (final d in diffsOf(call)) _Diff(d)
            else if (call.input['by'] == 'you')
              _Code('\$ ${call.input['command']}')
            else if (call.input.isNotEmpty)
              StepInput(call.input),
            if (call.input['command'] is String && call.input['by'] != 'you')
              _Explain(call: call, vm: vm),
            if (call.background case final task?)
              BackgroundOutput(task: task, call: call, vm: vm)
            else if (_markdownOf(call) case final md?)
              _MarkdownResult(md)
            else if (call.result != null && call.result!.isNotEmpty && diffsOf(call).isEmpty)
              _Code(stepResult(call.result!), error: call.isError),
            // What Helmy decided about it, on its own, and why.
            if (p != null && (p.decision == .allowedByHelmy || p.decision == .blockedByHelmy))
              Text(
                [
                  p.decision == .allowedByHelmy ? 'I let this go ahead' : "I didn't let this run",
                  if ((p.why ?? '').isNotEmpty) p.why!,
                ].join(': '),
                style: t.text.xs.copyWith(color: c.mutedForeground),
              ),
            _StepCopy(call: call, vm: vm),
          ],
        ),
      ),
    );
    if (!asking) return step;
    return Container(
      padding: const .fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [
          // Only what cannot be undone, or leaves this Mac, comes here: Helmy's
          // question about the outcome, then the step itself.
          Text(
            shell && activity.group == 'prepared a restart'
                ? '${activity.action}?'
                : (p.why ?? '').isNotEmpty
                ? p.why!
                : 'Let this go ahead?',
            style: t.text.sm.copyWith(fontWeight: .w500),
          ),
          step,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Button(
                size: .sm,
                onPressed: () => vm.allow(p),
                child: Text(
                  shell && activity.group == 'prepared a restart' ? 'Prepare restart' : 'Go ahead',
                ),
              ),
              Button(
                size: .sm,
                variant: .ghost,
                onPressed: () => vm.deny(p),
                child: const Text("Don't"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The step's result as Markdown, when it read a Markdown file.
  static String? _markdownOf(ToolCall call) => call.isError
      ? null
      : markdownResult(
          name: call.name,
          input: call.input,
          result: call.result,
          command: PermissionRule.plainCommand('${call.input['command'] ?? ''}'),
        );
}

/// Text from a tool, in the mono face. Long output is cut rather than given a
/// scroll of its own: a scroll inside the conversation traps the wheel at its end.
/// Under a command: what it does. First from the Mac's manual pages, free and
/// at once; then, when asked, in plain words from an agent, kept on the step.
class _Explain extends StatefulWidget {
  const new({required this.call, required this.vm});
  final ToolCall call;
  final ChatViewModel vm;

  @override
  State<_Explain> createState() => _ExplainState();
}

class _ExplainState extends State<_Explain> {
  bool _open = false;
  bool _asking = false;
  String? _error;

  Future<void> _ask() async {
    setState(() {
      _asking = true;
      _error = null;
    });
    final r = await widget.vm.explain(widget.call);
    if (!mounted) return;
    setState(() {
      _asking = false;
      if (r case Error(:final error)) _error = '$error'.replaceFirst('Exception: ', '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.xs.copyWith(color: c.mutedForeground, height: 1.5);
    final mono = t.text.xs.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: monoFonts,
      height: 1.5,
    );
    final call = widget.call;
    if (!_open) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Pressable(
          onPressed: () => setState(() => _open = true),
          semanticLabel: 'Explain this command',
          builder: (context, state) => Row(
            mainAxisSize: .min,
            spacing: 6,
            children: [
              AshlarIcon(
                AshlarIconsRoundedStroke.circleQuestionMark,
                size: 13,
                color: state.hovered ? c.foreground : c.mutedForeground,
              ),
              Text(
                call.explanation == null ? 'Explain this command' : 'Show the explanation',
                style: muted.copyWith(color: state.hovered ? c.foreground : null),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const .fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: .circular(t.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('From the manual', style: muted.copyWith(fontWeight: .w600)),
              ),
              Pressable(
                onPressed: () => setState(() => _open = false),
                semanticLabel: 'Hide the explanation',
                builder: (context, state) =>
                    Text('Hide', style: muted.copyWith(color: state.hovered ? c.foreground : null)),
              ),
            ],
          ),
          FutureBuilder(
            future: widget.vm.manual('${call.input['command']}'),
            builder: (context, snap) {
              final parts = snap.data;
              if (parts == null) {
                return const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Spinner(size: 12),
                );
              }
              if (parts.isEmpty) return Text('Nothing in it has a manual page.', style: muted);
              return Column(
                crossAxisAlignment: .stretch,
                spacing: 3,
                children: [
                  for (final p in parts)
                    Padding(
                      padding: EdgeInsetsDirectional.only(start: p.program ? 0 : 16),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: p.text,
                              style: mono.copyWith(
                                fontWeight: p.program ? .w700 : null,
                                color: p.program ? c.foreground : CodeColors.of(context).flag,
                              ),
                            ),
                            TextSpan(
                              text: '  ${p.help ?? 'not in the manual'}',
                              style: muted.copyWith(
                                fontStyle: p.help == null ? FontStyle.italic : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (call.explanation case final text?) ...[
            const SizedBox(height: 4),
            Text('In plain words', style: muted.copyWith(fontWeight: .w600)),
            Markdown(text),
          ] else
            Row(
              spacing: 10,
              children: [
                Button(
                  size: .sm,
                  variant: .outline,
                  onPressed: _asking ? null : _ask,
                  leading: _asking ? const Spinner(size: 12) : null,
                  child: Text(_asking ? 'Asking' : 'Explain in plain words'),
                ),
                Expanded(
                  child: Text(
                    _error ?? 'Asks a small model once, outside this thread.',
                    style: muted.copyWith(color: _error == null ? null : c.destructive),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A Markdown file a step read, formatted, with its source a press away.
class _MarkdownResult extends StatefulWidget {
  const new(this.text);
  final String text;

  @override
  State<_MarkdownResult> createState() => _MarkdownResultState();
}

class _MarkdownResultState extends State<_MarkdownResult> {
  bool _raw = false;
  bool _all = false;

  static const _maxLines = 120;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final lines = widget.text.split('\n');
    final long = lines.length > _maxLines && !_all;
    final text = long ? lines.take(_maxLines).join('\n') : widget.text;
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    Widget link(String label, VoidCallback onPressed) => Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => Text(
        label,
        style: muted.copyWith(
          color: state.hovered ? t.colors.foreground : null,
          decoration: TextDecoration.underline,
          decorationColor: t.colors.border,
        ),
      ),
    );
    return Container(
      padding: const .fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 12,
            children: [
              Expanded(child: Text(_raw ? 'Source' : 'Formatted', style: muted)),
              link(_raw ? 'Show formatted' : 'Show source', () => setState(() => _raw = !_raw)),
            ],
          ),
          if (_raw) _Code(text) else MarkdownPreview(text),
          if (long)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: link('Show all ${lines.length} lines', () => setState(() => _all = true)),
            ),
        ],
      ),
    );
  }
}

class _Code extends StatelessWidget {
  const new(this.text, {this.error = false});
  final String text;
  final bool error;

  static const _maxLines = 30;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final lines = text.split('\n');
    final shown = lines.length > _maxLines
        ? '${lines.take(_maxLines).join('\n')}\n... ${lines.length - _maxLines} more lines'
        : text;
    return Container(
      padding: const .symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.colors.muted.withValues(alpha: .5),
        borderRadius: .circular(t.radiusMd),
      ),
      child: Text(
        shown.length > 6000 ? '${shown.substring(0, 6000)}\n...' : shown,
        style: t.text.xs.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: monoFonts,
          height: 1.5,
          color: error ? t.colors.destructive : t.colors.foreground,
        ),
      ),
    );
  }
}

/// Under an open step: copy what went in, what came out, or the whole step
/// as JSON.
class _StepCopy extends StatelessWidget {
  const _StepCopy({required this.call, required this.vm});
  final ToolCall call;
  final ChatViewModel vm;

  String get _input => call.input['command'] is String
      ? '${call.input['command']}'
      : const JsonEncoder.withIndent('  ').convert(call.input);

  String get _json => const JsonEncoder.withIndent('  ').convert({
    'tool': call.name,
    'input': call.input,
    if (call.result != null) 'output': call.result,
    if (call.isError) 'error': true,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if ((call.input['file_path'] ?? call.input['notebook_path'] ?? call.input['path'])
          case final String path when path.isNotEmpty)
        _IconAction(
          icon: AshlarIconsRoundedStroke.filePen,
          label: 'Open file in editor',
          onPressed: () => vm.editFile(path),
        ),
      if (call.input['command'] case final String command when command.isNotEmpty)
        _IconAction(
          icon: AshlarIconsRoundedStroke.squareTerminal,
          label: 'Edit command in side panel',
          onPressed: () => vm.editCode(command, 'bash'),
        ),
      if (call.result case final String result when result.isNotEmpty)
        _IconAction(
          icon: AshlarIconsRoundedStroke.fileCode,
          label: 'Open output in editor',
          onPressed: () => vm.editCode(stepResult(result), null),
        ),
      if (call.input.isNotEmpty)
        _IconAction(
          icon: AshlarIconsRoundedStroke.copy,
          label: 'Copy what went in',
          onPressed: () => copyWithToast(context, vm, _input),
        ),
      if (call.result != null && call.result!.isNotEmpty)
        _IconAction(
          icon: AshlarIconsRoundedStroke.clipboardCopy,
          label: 'Copy what came out',
          onPressed: () => copyWithToast(context, vm, stepResult(call.result!)),
        ),
      _IconAction(
        icon: AshlarIconsRoundedStroke.braces,
        label: 'Copy the step as JSON',
        onPressed: () => copyWithToast(context, vm, _json),
      ),
    ],
  );
}
