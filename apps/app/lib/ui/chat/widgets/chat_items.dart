import 'dart:async';

import '../../../domain/helmy_voice.dart';
import '../../../domain/folder_move.dart';

import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart' show kDoubleTapSlop, kDoubleTapTimeout;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/chat_item.dart';
import '../../../utils/diffs.dart';
import '../../../utils/format.dart';
import '../../core/ashlar/plan.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/desktop_service.dart';
import '../../../data/services/engines/attachments.dart';
import '../../core/ashlar/dialog.dart';
import '../../core/ashlar/dropdown_menu.dart';
import '../../core/ashlar/attachment.dart';
import '../../core/ashlar/bubble.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/collapsible.dart';
import '../../core/ashlar/markdown.dart';
import '../../core/ashlar/message.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/questionnaire.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/toast.dart';
import '../../core/ashlar/tooltip.dart';
import '../../core/helmy_dialog.dart';
import '../../core/markdown_preview.dart';
import '../../../domain/models/permission_rule.dart';
import 'step_input.dart';
import '../../../utils/result.dart';
import '../view_models/chat_view_model.dart';
import 'problem_card.dart';
import 'saved_toast.dart';
import '../../../domain/problem.dart';
import '../../../utils/platform.dart';

typedef ChatRow = ({Object id, bool anchor, Widget child});

/// The conversation as rows. A tool's approval is drawn on the tool's own step,
/// so an approval with a step to go on gets no row of its own.
List<ChatRow> buildRows(ChatViewModel vm) {
  final items = vm.items;
  final promptsByTool = {
    for (final p in items.whereType<PermissionPrompt>())
      if (p.toolUseId != null && !p.isQuestion) p.toolUseId!: p,
  };
  final toolIds = {for (final c in items.whereType<ToolCall>()) c.id};
  final rows = <ChatRow>[];
  final lastAsk = vm.lastAsk;
  int? ask;
  // Steps in a row, held back so two or more fold into one line.
  final run = <(int, ToolCall, PermissionPrompt?)>[];
  void flush() {
    if (run.length == 1) {
      final (i, call, p) = run.single;
      rows.add((id: i, anchor: false, child: _Step(call, p, vm)));
    } else if (run.length > 1) {
      rows.add((id: 'g${run.first.$1}', anchor: false, child: _StepGroup([...run], vm)));
    }
    run.clear();
  }

  for (final (i, item) in items.indexed) {
    final p = item is ToolCall ? promptsByTool[item.id] : null;
    final quiet =
        (item is ToolCall && p?.decision != PermissionDecision.pending) ||
        (item is AssistantText && item.text.isEmpty) ||
        (item is PermissionPrompt &&
            !item.isQuestion &&
            item.toolUseId != null &&
            toolIds.contains(item.toolUseId));
    if (!quiet) flush();
    switch (item) {
      case UserMessage(:final text, :final attachments):
        ask = i;
        rows.add((
          id: i,
          anchor: true,
          child: _User(
            text,
            i,
            vm,
            attachments: attachments,
            sentAt: item.sentAt,
            key: ObjectKey(item),
          ),
        ));
      case AssistantText(:final text):
        final streaming = vm.busy && i == items.length - 1;
        // A folder move is Helmy's to act on, not the user's to read.
        final shown = withoutFolderLines(text, streaming: streaming);
        if (shown.isEmpty) continue;
        rows.add((
          id: i,
          anchor: false,
          child: Builder(
            builder: (context) => Markdown(
              shown,
              streaming: streaming,
              onLink: (url) => openAnswerLink(context, url, vm),
            ),
          ),
        ));
      case ToolCall call when call.name == 'ExitPlanMode':
        rows.add((id: i, anchor: false, child: _PlanApproval(call, p, vm)));
      case ToolCall call:
        if (quiet) {
          run.add((i, call, p));
        } else {
          rows.add((id: i, anchor: false, child: _Step(call, p, vm)));
        }
      case PermissionPrompt p when p.isQuestion:
        rows.add((id: i, anchor: false, child: _Question(p, vm)));
      case PermissionPrompt p:
        if (p.toolUseId != null && toolIds.contains(p.toolUseId)) continue;
        // An approval for something that has no step: draw one from the request.
        final call = ToolCall(id: p.requestId, name: p.toolName, input: p.input);
        rows.add((id: i, anchor: false, child: _Step(call, p, vm)));
      case ImageItem image:
        rows.add((id: i, anchor: false, child: _Image(image, vm)));
      case TaskList list:
        rows.add((id: i, anchor: false, child: _Tasks(list)));
      case TurnSummary s:
        if (!s.ok) {
          rows.add((
            id: i,
            anchor: false,
            child: ProblemCard(
              problem: diagnose(s.error, engineId: s.engineId),
              vm: vm,
              last: i == items.length - 1,
            ),
          ));
        }
        if (ask != null) {
          rows.add((
            id: 'a$i',
            anchor: false,
            child: _AnswerActions(
              ask,
              ask == lastAsk,
              vm,
              sentAt: (items[ask] as UserMessage).sentAt,
              endedAt: s.endedAt,
            ),
          ));
        }
      case Notice(:final text, :final fix?) when Fix.values.any((f) => f.link == fix):
        rows.add((
          id: i,
          anchor: false,
          child: ProblemCard(
            problem: Problem(
              text,
              Fix.values.firstWhere((f) => f.link == fix),
              details: (items[i] as Notice).details,
            ),
            vm: vm,
            last: i == items.length - 1,
          ),
        ));
      case Notice(:final text):
        rows.add((id: i, anchor: false, child: _Notice(text)));
    }
  }
  flush();
  return rows;
}

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
                if (s.summary.isNotEmpty) s.summary,
                if (s.isError) 'failed',
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

/// A file's change: lines removed faint and struck through, lines added bold.
/// Long ones are cut, as other output is, so the page keeps one scroll.
class _Diff extends StatelessWidget {
  const new(this.diff);
  final FileDiff diff;

  static const _maxLines = 60;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final base = t.text.xs.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: monoFonts,
      height: 1.5,
    );
    final shown = diff.lines.take(_maxLines).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: .circular(t.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Container(
            padding: const .symmetric(horizontal: 12, vertical: 6),
            color: c.muted.withValues(alpha: .5),
            child: Text(
              '${tildePath(diff.path)}   +${diff.added} -${diff.removed}',
              style: base.copyWith(color: c.mutedForeground),
            ),
          ),
          for (final l in shown)
            Container(
              color: l.startsWith('+')
                  ? c.foreground.withValues(alpha: .07)
                  : l.startsWith('-')
                  ? c.foreground.withValues(alpha: .03)
                  : null,
              padding: const .symmetric(horizontal: 12),
              child: Text(
                l.isEmpty ? ' ' : l,
                style: l.startsWith('+')
                    ? base.copyWith(color: c.foreground, fontWeight: .w600)
                    : l.startsWith('-')
                    ? base.copyWith(
                        color: c.mutedForeground,
                        decoration: TextDecoration.lineThrough,
                      )
                    : base.copyWith(color: c.mutedForeground),
              ),
            ),
          if (diff.lines.length > _maxLines)
            Padding(
              padding: const .symmetric(horizontal: 12, vertical: 6),
              child: Text(
                '... ${diff.lines.length - _maxLines} more lines',
                style: base.copyWith(color: c.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }
}

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

/// "Ran 2 commands, read 3 files and edited a file": what a run of steps did.
String stepsSummary(List<ToolCall> calls) {
  final counts = <String, int>{};
  for (final c in calls) {
    final kind = switch (c.name) {
      'Bash' || 'Shell' => 'command',
      'Read' => 'read',
      'Write' || 'Edit' || 'NotebookEdit' => 'edit',
      'Glob' || 'Grep' || 'WebSearch' => 'search',
      'WebFetch' => 'page',
      'Task' || 'Agent' => 'helper',
      'ImageGeneration' => 'image',
      _ => 'tool',
    };
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  String n(int k, String one, String many) => k == 1 ? one : '$k $many';
  final parts = [
    for (final MapEntry(:key, :value) in counts.entries)
      switch (key) {
        'command' => 'ran ${n(value, 'a command', 'commands')}',
        'read' => 'read ${n(value, 'a file', 'files')}',
        'edit' => 'edited ${n(value, 'a file', 'files')}',
        'search' => 'searched ${n(value, 'once', 'times')}',
        'page' => 'read ${n(value, 'a page', 'pages')}',
        'helper' => 'asked ${n(value, 'a helper', 'helpers')}',
        'image' => 'made ${n(value, 'an image', 'images')}',
        _ => 'used ${n(value, 'a tool', 'tools')}',
      },
  ];
  final text = parts.length == 1
      ? parts.single
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  return text[0].toUpperCase() + text.substring(1);
}

/// Several steps in a row as one quiet line that opens to each of them.
class _StepGroup extends StatelessWidget {
  const new(this.steps, this.vm);
  final List<(int, ToolCall, PermissionPrompt?)> steps;
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final calls = [for (final s in steps) s.$2];
    final running = vm.busy && calls.any((c) => !c.done);
    final failed = calls.where((c) => c.isError).length;
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
        padding: const .only(left: 22, top: 2),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [for (final (_, call, p) in steps) _Step(call, p, vm)],
        ),
      ),
    );
  }
}

/// What a step did, in words, whichever engine took it: "Ran a command",
/// "Edited notes.md". [done] picks the tense.
String stepTitle(ToolCall call, {required bool done}) {
  String file() {
    final path = '${call.input['file_path'] ?? call.input['notebook_path'] ?? ''}';
    final first = path.split(', ').first;
    return first.isEmpty ? 'a file' : first.split('/').last;
  }

  String pick(String did, String doing) => done ? did : doing;
  if (call.input['by'] == 'you') return pick('You ran a command', 'Running your command');
  return switch (call.name) {
    'Bash' || 'Shell' => pick('Ran a command', 'Running a command'),
    'Read' => pick('Read ${file()}', 'Reading ${file()}'),
    'Write' => pick('Wrote ${file()}', 'Writing ${file()}'),
    'Edit' || 'NotebookEdit' => pick('Edited ${file()}', 'Editing ${file()}'),
    'Glob' || 'Grep' => pick('Searched the files', 'Searching the files'),
    'WebSearch' => pick('Searched the web', 'Searching the web'),
    'WebFetch' => pick('Read a web page', 'Reading a web page'),
    'Task' || 'Agent' => pick('Asked a helper', 'Asking a helper'),
    'TodoWrite' => pick('Updated the plan', 'Updating the plan'),
    'ImageGeneration' => pick('Made an image', 'Making an image'),
    _ => pick('Used ${toolLabel(call.name)}', 'Using ${toolLabel(call.name)}'),
  };
}

/// A message of yours, with Copy and Edit under it while the pointer is near.
/// Edit opens it in place; sending it again takes back what came after.
class _User extends StatefulWidget {
  const new(this.text, this.index, this.vm, {super.key, this.attachments = const [], this.sentAt});
  final String text;

  /// When it was sent; unknown for older messages.
  final DateTime? sentAt;
  final List<String> attachments;
  final int index;
  final ChatViewModel vm;

  @override
  State<_User> createState() => _UserState();
}

class _UserState extends State<_User> {
  bool _hovered = false;
  ({Duration at, Offset where})? _lastClick;

  /// A second click soon after the first, near it, opens the message to edit.
  void _clicked(Offset where) {
    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    final last = _lastClick;
    _lastClick = (at: now, where: where);
    if (last == null ||
        now - last.at > kDoubleTapTimeout ||
        (where - last.where).distance > kDoubleTapSlop) {
      return;
    }
    _lastClick = null;
    if (!widget.vm.busy) widget.vm.startEdit(widget.index);
  }

  /// Puts the folder's files back as they were before this message.
  Future<void> _undo(BuildContext context) async {
    final vm = widget.vm;
    final changed = await vm.changesFrom(widget.index);
    if (!context.mounted) return;
    if (changed.isEmpty) {
      showToast(context, title: 'No files changed since this message');
      return;
    }
    final names = changed.take(4).map((c) => c.path).join(', ');
    final ok = await confirm(
      context,
      title: 'Undo file changes from here?',
      body:
          '${changed.length} file${changed.length == 1 ? '' : 's'} go back to how they were '
          'before this message: $names${changed.length > 4 ? ', ...' : ''}. The conversation '
          'stays as it is.',
      action: 'Undo changes',
      icon: AshlarIconsRoundedStroke.undo2,
    );
    if (!ok) return;
    final n = await vm.undoFrom(widget.index);
    if (context.mounted) showToast(context, title: '$n file${n == 1 ? '' : 's'} put back');
  }

  late final _edit = TextEditingController(text: widget.text)..addListener(_editChanged);

  /// Enter saves and Esc cancels; Shift+Enter is a new line.
  late final _editFocus = FocusNode(
    onKeyEvent: (node, e) {
      if (e is! KeyDownEvent) return .ignored;
      if (e.logicalKey == LogicalKeyboardKey.escape) {
        _cancelEdit();
        return .handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
        _saveEdit();
        return .handled;
      }
      return .ignored;
    },
  );

  void _editChanged() => setState(() {});

  /// Whether the editor was showing at the last build, to focus it once.
  bool _editing = false;

  void _cancelEdit() {
    _edit.text = widget.text;
    widget.vm.cancelEdit();
  }

  void _saveEdit() {
    final text = _edit.text.trim();
    if (text.isEmpty || text == widget.text.trim()) return;
    widget.vm.resend(widget.index, text);
  }

  /// The message edited in place: the bubble itself, with a ring, as wide as
  /// its words up to the bubble's own limit; Cancel and Save under it.
  Widget _editor(BuildContext context) {
    // Typing goes here at once: autofocus alone yields to the composer,
    // which already has focus.
    if (!_editing) {
      _editing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _editFocus.requestFocus();
        _edit.selection = TextSelection.collapsed(offset: _edit.text.length);
      });
    }
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final changed = _edit.text.trim().isNotEmpty && _edit.text.trim() != widget.text.trim();
    return Padding(
      padding: const .only(top: 12, bottom: 4),
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: .end,
          spacing: 6,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: 160, maxWidth: box.maxWidth * .8),
              child: IntrinsicWidth(
                child: Container(
                  padding: const .symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: c.muted,
                    borderRadius: .circular(t.radiusXl),
                    border: Border.all(color: c.ring, width: 1.5),
                  ),
                  child: EditableText(
                    controller: _edit,
                    focusNode: _editFocus,
                    autofocus: true,
                    maxLines: null,
                    style: t.text.sm.copyWith(color: c.foreground, height: 1.6),
                    cursorColor: c.foreground,
                    backgroundCursorColor: c.mutedForeground,
                    selectionColor: c.foreground.withValues(alpha: .2),
                    keyboardType: TextInputType.multiline,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisSize: .min,
              spacing: 4,
              children: [
                Tooltip(
                  message: 'Saving sends it again. What came after stays as a version you can go back to; files are not changed.',
                  child: AshlarIcon(
                    AshlarIconsRoundedStroke.info,
                    size: 14,
                    color: c.mutedForeground,
                  ),
                ),
                Button(
                  size: .sm,
                  variant: .ghost,
                  onPressed: _cancelEdit,
                  child: const Text('Cancel'),
                ),
                Button(
                  size: .sm,
                  variant: .secondary,
                  onPressed: changed ? _saveEdit : null,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _edit.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    if (vm.editing == widget.index) return _editor(context);
    _editing = false;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const .only(top: 12, bottom: 4),
        child: Column(
          crossAxisAlignment: .end,
          spacing: 2,
          children: [
            if (widget.attachments.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: .end,
                children: [
                  for (final path in widget.attachments)
                    Attachment(
                      title: path.split('/').last,
                      size: .sm,
                      image:
                          imageTypes.containsKey(path.split('.').last.toLowerCase()) &&
                              File(path).existsSync()
                          ? FileImage(File(path))
                          : null,
                    ),
                ],
              ),
            if (widget.text.isNotEmpty)
              // Double-click to edit. Read from raw pointer events, since the
              // conversation's text selection claims double-clicks for itself.
              Listener(
                onPointerDown: (e) => _clicked(e.position),
                child: Message(
                  align: .end,
                  child: Bubble(variant: .muted, child: Text(widget.text)),
                ),
              ),
            Row(
              mainAxisSize: .min,
              children: [
                // Kept in the layout while hidden, so nothing below jumps.
                Opacity(
                  opacity: _hovered ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_hovered,
                    child: Row(
                      mainAxisSize: .min,
                      children: [
                        if (widget.sentAt case final at?)
                          Tooltip(
                            message: 'Sent ${fullTime(at)}',
                            child: Padding(
                              padding: const .symmetric(horizontal: 6),
                              child: Text(
                                shortWhen(at),
                                style: AshlarTheme.of(context).text.xs.copyWith(
                                  color: AshlarTheme.of(context).colors.mutedForeground,
                                ),
                              ),
                            ),
                          ),
                        _IconAction(
                          icon: AshlarIconsRoundedStroke.copy,
                          label: 'Copy',
                          onPressed: () => copyWithToast(context, vm, widget.text),
                        ),
                        _IconAction(
                          icon: AshlarIconsRoundedStroke.pencil,
                          label: 'Edit',
                          onPressed: vm.busy ? null : () => vm.startEdit(widget.index),
                        ),
                        if (vm.canUndoFrom(widget.index))
                          _IconAction(
                            icon: AshlarIconsRoundedStroke.fileDiff,
                            label: "Show this message's changes",
                            onPressed: () => vm.showChanges(from: widget.index),
                          ),
                        if (vm.canUndoFrom(widget.index))
                          _IconAction(
                            icon: AshlarIconsRoundedStroke.undo2,
                            label: 'Undo file changes from here',
                            onPressed: vm.busy ? null : () => _undo(context),
                          ),
                      ],
                    ),
                  ),
                ),
                // Always shown: that there are other versions is worth knowing.
                if (vm.branchesAt(widget.index) != null) _BranchSwitch(index: widget.index, vm: vm),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Copy, and Retry on the latest answer, at the end of each answer.
class _AnswerActions extends StatelessWidget {
  const new(this.ask, this.latest, this.vm, {this.sentAt, this.endedAt});

  /// When the message went and when the answer finished: how long it took.
  final DateTime? sentAt, endedAt;

  /// The index of the message this answers.
  final int ask;
  final bool latest;
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _IconAction(
        icon: AshlarIconsRoundedStroke.copy,
        label: 'Copy answer',
        onPressed: () => copyWithToast(context, vm, vm.answerAfter(ask)),
      ),
      if (latest)
        _IconAction(
          icon: AshlarIconsRoundedStroke.refreshCw,
          label: 'Retry',
          onPressed: vm.busy ? null : vm.retry,
        ),
      if ((sentAt, endedAt) case (final from?, final to?) when !to.isBefore(from))
        Padding(
          padding: const .only(left: 8),
          child: Tooltip(
            message: 'Sent ${fullTime(from)}\nAnswered ${fullTime(to)}',
            child: Text(
              'Took ${tookLabel(to.difference(from))}',
              style: AshlarTheme.of(context).text.xs
                  .copyWith(color: AshlarTheme.of(context).colors.mutedForeground),
            ),
          ),
        ),
    ],
  );
}

/// "4s", "1m 5s", "1h 2m": how long, as a person says it.
String tookLabel(Duration d) {
  final s = d.inSeconds;
  if (s < 1) return 'under a second';
  if (s < 60) return '${s}s';
  if (d.inHours < 1) return '${d.inMinutes}m${s % 60 == 0 ? '' : ' ${s % 60}s'}';
  return '${d.inHours}h${d.inMinutes % 60 == 0 ? '' : ' ${d.inMinutes % 60}m'}';
}

/// "10:42 PM" today, "Oct 12" this year, "Oct 12, 2025" before.
String shortWhen(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  if (t.year == n.year && t.month == n.month && t.day == n.day) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }
  return t.year == n.year
      ? '${months[t.month - 1]} ${t.day}'
      : '${months[t.month - 1]} ${t.day}, ${t.year}';
}

/// "Tue, Nov 3, 2026 at 10:42:05 PM".
String fullTime(DateTime t) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[t.weekday - 1]}, ${months[t.month - 1]} ${t.day}, ${t.year} at '
      '$h:${two(t.minute)}:${two(t.second)} ${t.hour < 12 ? 'AM' : 'PM'}';
}

class _IconAction extends StatelessWidget {
  const new({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Button(
      variant: .ghost,
      size: .iconSm,
      semanticLabel: label,
      onPressed: onPressed,
      child: AshlarIcon(icon, size: 14),
    ),
  );
}

/// Under an edited message: which version of the conversation is showing,
/// arrows to step between them, and the count opening a list of them all.
class _BranchSwitch extends StatelessWidget {
  const new({required this.index, required this.vm});
  final int index;
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final b = vm.branchesAt(index)!;
    final versions = vm.versionsAt(index);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    void go(int to) => vm.showBranch(index, to);
    return Row(
      mainAxisSize: .min,
      children: [
        _IconAction(
          icon: AshlarIconsRoundedStroke.chevronLeft,
          label: 'Previous version',
          onPressed: vm.busy || b.active == 0 ? null : () => go(b.active - 1),
        ),
        DropdownMenu(
          align: .end,
          width: 300,
          items: [
            MenuLabel(child: Text('Versions from this message')),
            for (var i = 0; i < versions.length; i++)
              MenuItem(
                onPressed: vm.busy || i == b.active ? null : () => go(i),
                leading: i == b.active
                    ? const AshlarIcon(AshlarIconsRoundedStroke.check, size: 14)
                    : const SizedBox(width: 14),
                trailing: Text(
                  '${versions[i].asks} message${versions[i].asks == 1 ? '' : 's'}',
                  style: muted,
                ),
                child: Text(
                  '${i + 1}  ${versions[i].first.replaceAll('\n', ' ')}',
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
              ),
            const MenuSeparator(),
            Padding(
              padding: const .fromLTRB(8, 4, 8, 6),
              child: Text(
                "Switching changes the conversation, not your files. Use undo file "
                'changes for those.',
                style: muted,
              ),
            ),
          ],
          builder: (context, menu) => Tooltip(
            message: 'All versions',
            child: Pressable(
              onPressed: menu.isOpen ? menu.close : menu.open,
              semanticLabel: 'Version ${b.active + 1} of ${b.length}, show all',
              builder: (context, state) => Container(
                padding: const .symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: state.hovered ? t.colors.accent : null,
                  borderRadius: .circular(t.radiusMd),
                ),
                child: Text(
                  '${b.active + 1} / ${b.length}',
                  style: muted.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ),
          ),
        ),
        _IconAction(
          icon: AshlarIconsRoundedStroke.chevronRight,
          label: 'Next version',
          onPressed: vm.busy || b.active == b.length - 1 ? null : () => go(b.active + 1),
        ),
      ],
    );
  }
}

/// How a step moved to the background stands, beside its title.
class BackgroundBadge extends StatelessWidget {
  const new(this.task, {super.key});
  final BackgroundTask task;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final label = switch (task.status) {
      .running => 'Running in the background',
      .completed => 'Finished in the background',
      .failed => 'Failed in the background',
      .stopped => 'Stopped',
      .unknown => 'Ran in the background, end not seen',
    };
    return Container(
      padding: const .symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusMd),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 5,
        children: [
          if (task.status == .running) const Spinner(size: 9),
          Text(label, style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
        ],
      ),
    );
  }
}

/// What a background step has printed so far, read from where the agent
/// writes it and read again while it runs; Stop while it does.
class BackgroundOutput extends StatefulWidget {
  const new({super.key, required this.task, required this.call, required this.vm});
  final BackgroundTask task;
  final ToolCall call;
  final ChatViewModel vm;

  /// Where the output is: as the agent last said, or as the step's result put it.
  String? get file =>
      task.outputFile ??
      RegExp(r'written to: (\S+\.output)').firstMatch(call.result ?? '')?.group(1);

  @override
  State<BackgroundOutput> createState() => BackgroundOutputState();
}

class BackgroundOutputState extends State<BackgroundOutput> {
  String? _text;
  Timer? _timer;

  static const _maxChars = 6000;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (widget.task.status == .running) _read();
    });
  }

  @override
  void didUpdateWidget(BackgroundOutput oldWidget) {
    super.didUpdateWidget(oldWidget);
    _read();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    final path = widget.file;
    if (path == null) return;
    try {
      final all = await File(path).readAsString();
      final text = all.length > _maxChars ? '...\n${all.substring(all.length - _maxChars)}' : all;
      if (mounted && text != _text) setState(() => _text = text);
    } on FileSystemException {
      // Not written yet, or cleared away since: nothing to show.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final task = widget.task;
    final text = _text?.trimRight() ?? '';
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        if (text.isNotEmpty)
          _Code(text, error: task.status == .failed)
        else
          Text(
            task.status == .running
                ? 'Nothing printed yet.'
                : widget.file == null
                ? 'Where its output went is not known.'
                : 'No output to show. It may have been cleared away.',
            style: t.text.xs.copyWith(color: t.colors.mutedForeground),
          ),
        if (task.status == .running)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Button(
              size: .sm,
              variant: .outline,
              onPressed: () => widget.vm.stopTask(task.id),
              child: const Text('Stop'),
            ),
          ),
      ],
    );
  }
}

/// Puts [text] on the clipboard and says so.
Future<void> copyWithToast(BuildContext context, ChatViewModel vm, String text) async {
  await vm.copy(text);
  if (context.mounted) showToast(context, title: 'Copied', duration: const Duration(seconds: 2));
}

/// One step the agent took, as a quiet line that opens to what went in and
/// what came out. An approval it waits on shows open, with its answers.
class _Step extends StatelessWidget {
  const new(this.call, this.prompt, this.vm);
  final ToolCall call;
  final PermissionPrompt? prompt;
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final p = prompt;
    final asking = p != null && p.decision == .pending;
    final denied = p?.decision == .denied;
    final failed = call.isError || denied;
    final running = !call.done && !asking && !denied && vm.busy;
    final muted = t.text.sm.copyWith(color: c.mutedForeground);
    final detail = call.summary;
    final title = asking
        ? 'Wants to ${stepTitle(call, done: false).replaceFirst(RegExp(r'^\w+ing'), _verb(call))}'
        : stepTitle(call, done: !running);
    final step = Collapsible(
      initiallyOpen: asking || context.read<SettingsRepository>().settings.stepsOpen,
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
                    : AshlarIcon(
                        failed ? AshlarIconsRoundedStroke.x : AshlarIconsRoundedStroke.chevronRight,
                        size: 14,
                        color: c.mutedForeground,
                      ),
              ),
              Text(
                failed ? '$title, failed' : title,
                style: muted.copyWith(
                  color: state.hovered || asking ? c.foreground : c.mutedForeground,
                  fontWeight: asking ? .w500 : null,
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
              if (detail.isNotEmpty && detail != title)
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
        padding: const .only(left: 22, top: 4, bottom: 6),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 8,
          children: [
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
          step,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Button(size: .sm, onPressed: () => vm.allow(p), child: const Text('Allow')),
              if (p.suggestions.isNotEmpty)
                Button(
                  size: .sm,
                  variant: .outline,
                  onPressed: () => vm.allow(p, forSession: true),
                  child: const Text('Allow for this session'),
                ),
              if (vm.ruleFor(p) case final rule?)
                Button(
                  size: .sm,
                  variant: .outline,
                  onPressed: () => vm.allowAlways(p, rule),
                  child: Text('Always allow: ${rule.label.toLowerCase()}'),
                ),
              Button(
                size: .sm,
                variant: .ghost,
                onPressed: () => vm.deny(p),
                child: const Text('Deny'),
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

  /// "Wants to run a command", "wants to edit notes.md".
  static String _verb(ToolCall call) => switch (call.name) {
    'Bash' || 'Shell' => 'run',
    'Read' => 'read',
    'Write' => 'write',
    'Edit' || 'NotebookEdit' => 'edit',
    'Glob' || 'Grep' || 'WebSearch' => 'search',
    'WebFetch' => 'read',
    'Task' || 'Agent' => 'ask',
    'ImageGeneration' => 'make',
    _ => 'use',
  };
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
                    _error ?? 'Asks a small model once, outside this conversation.',
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

class _Question extends StatelessWidget {
  const new(this.prompt, this.vm);
  final PermissionPrompt prompt;
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    if (prompt.decision != .pending) {
      final answered = prompt.answers.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      return Text(
        answered.isEmpty ? 'A question that was not answered' : answered,
        style: t.text.sm.copyWith(color: t.colors.mutedForeground),
      );
    }
    return Questionnaire(
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
  }
}

/// A picture the agent made, from the file it saved: click it to see it whole,
/// and copy, save, open or find it.
class _Image extends StatelessWidget {
  const new(this.image, this.vm);
  final ImageItem image;
  final ChatViewModel vm;

  Future<void> _copy(BuildContext context) async {
    final ok = await context.read<DesktopService>().copyImage(image.path);
    if (context.mounted) {
      showToast(
        context,
        title: ok ? 'Image copied' : 'Could not copy the image',
        type: ok ? .normal : .error,
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _save(BuildContext context) async {
    final name = image.path.split('/').last;
    final where = await getSaveLocation(suggestedName: name, confirmButtonText: 'Save');
    if (where == null) return;
    try {
      await File(image.path).copy(where.path);
      if (context.mounted) showSavedToast(context, where.path);
    } on FileSystemException catch (e) {
      if (context.mounted) {
        showToast(context, title: 'Could not save', description: e.message, type: .error);
      }
    }
  }

  void _view(BuildContext context) => showAshlarDialog<void>(
    context: context,
    builder: (context) => GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Padding(
        padding: const .all(40),
        child: Center(
          child: Image.file(
            File(image.path),
            fit: BoxFit.contain,
            semanticLabel: image.prompt ?? 'Generated image',
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final file = File(image.path);
    if (!file.existsSync()) {
      return Container(
        padding: const .all(16),
        decoration: BoxDecoration(color: t.colors.muted, borderRadius: .circular(t.radiusLg)),
        child: Text('The image is no longer at ${tildePath(image.path)}', style: muted),
      );
    }
    final desktop = context.read<DesktopService>();
    return Column(
      crossAxisAlignment: .start,
      spacing: 4,
      children: [
        Pressable(
          onPressed: () => _view(context),
          semanticLabel: 'View ${image.prompt ?? 'the image'} full size',
          builder: (context, state) => ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
            child: ClipRRect(
              borderRadius: .circular(t.radiusLg),
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
        ),
        Row(
          mainAxisSize: .min,
          children: [
            _IconAction(
              icon: AshlarIconsRoundedStroke.wandSparkles,
              label: 'Refine: describe a change to this image',
              onPressed: vm.busy ? null : () => vm.refine(image.path),
            ),
            _IconAction(
              icon: AshlarIconsRoundedStroke.shuffle,
              label: 'Variation: another take on this image',
              onPressed: vm.busy ? null : () => vm.variation(image.path),
            ),
            _IconAction(
              icon: AshlarIconsRoundedStroke.copy,
              label: 'Copy image',
              onPressed: () => _copy(context),
            ),
            _IconAction(
              icon: AshlarIconsRoundedStroke.download,
              label: 'Save as...',
              onPressed: () => _save(context),
            ),
            _IconAction(
              icon: AshlarIconsRoundedStroke.externalLink,
              label: 'Open',
              onPressed: () => desktop.open(image.path),
            ),
            _IconAction(
              icon: AshlarIconsRoundedStroke.folderOpen,
              label: 'Show in ${Desktop.current.fileManager}: ${tildePath(image.path)}',
              onPressed: () => desktop.reveal(image.path),
            ),
          ],
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const new(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Text(text, style: t.text.sm.copyWith(color: t.colors.mutedForeground));
  }
}
