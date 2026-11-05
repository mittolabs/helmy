import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/engine.dart';
import '../../../domain/models/scheduled_task.dart';
import '../../../utils/format.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/dialog.dart';
import '../../core/ashlar/dropdown_menu.dart';
import '../../core/ashlar/input.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/select.dart';
import '../../core/ashlar/switch.dart';
import '../../core/ashlar/textarea.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../../core/helmy_dialog.dart';
import '../view_models/schedule_view_model.dart';

/// Messages sent by themselves on a schedule, each run in a session of its
/// own. They run while Helmy is open, which it stays in the background.
class ScheduleScreen extends StatelessWidget {
  const new({super.key, required this.viewModel});
  final ScheduleViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.5);
    return ColoredBox(
      color: t.colors.background,
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) => ScrollArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const .fromLTRB(32, 40, 32, 40),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Scheduled', style: t.text.xl.copyWith(fontWeight: .w600)),
                        ),
                        Button(
                          onPressed: () => editTask(context, viewModel),
                          leading: const AshlarIcon(AshlarIconsRoundedStroke.plus, size: 14),
                          child: const Text('New task'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A message sent by itself on a schedule, each run a chat of its own. '
                      'Tasks run while Helmy is open; closing the window keeps it running. '
                      'A run missed while it was quit happens once when it opens again.',
                      style: muted,
                    ),
                    const SizedBox(height: 24),
                    if (viewModel.tasks.isEmpty)
                      Container(
                        padding: const .all(32),
                        decoration: BoxDecoration(
                          border: Border.all(color: t.colors.border),
                          borderRadius: .circular(t.radiusLg),
                        ),
                        child: Text('No scheduled tasks yet.', textAlign: .center, style: muted),
                      )
                    else
                      for (final task in viewModel.tasks) ...[
                        _TaskCard(task: task, vm: viewModel),
                        const SizedBox(height: 12),
                      ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const new({required this.task, required this.vm});
  final ScheduledTask task;
  final ScheduleViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final next = task.next;
    final runs = vm.runsOf(task.id);
    return Container(
      padding: const .fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 6,
        children: [
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: Text(task.name, style: t.text.sm.copyWith(fontWeight: .w600)),
              ),
              Tooltip(
                message: task.enabled ? 'Turn off' : 'Turn on',
                child: Switch(
                  value: task.enabled,
                  semanticLabel: 'Run ${task.name} on its schedule',
                  onChanged: (on) => vm.setEnabled(task, on),
                ),
              ),
              DropdownMenu(
                align: .end,
                items: [
                  MenuItem(
                    leading: const AshlarIcon(AshlarIconsRoundedStroke.play, size: 14),
                    onPressed: () async {
                      final id = await vm.runNow(task);
                      if (id != null && context.mounted) context.go('/s/$id');
                    },
                    child: const Text('Run now'),
                  ),
                  MenuItem(
                    leading: const AshlarIcon(AshlarIconsRoundedStroke.pencil, size: 14),
                    onPressed: () => editTask(context, vm, task: task),
                    child: const Text('Edit'),
                  ),
                  const MenuSeparator(),
                  MenuItem(
                    destructive: true,
                    leading: const AshlarIcon(AshlarIconsRoundedStroke.trash, size: 14),
                    onPressed: () async {
                      final ok = await confirm(
                        context,
                        title: 'Delete "${task.name}"?',
                        body: 'It stops running. Chats from its earlier runs stay.',
                        action: 'Delete',
                        destructive: true,
                      );
                      if (ok) await vm.remove(task);
                    },
                    child: const Text('Delete'),
                  ),
                ],
                builder: (context, menu) => Button(
                  variant: .ghost,
                  size: .iconSm,
                  semanticLabel: 'More for ${task.name}',
                  onPressed: menu.isOpen ? menu.close : menu.open,
                  child: const AshlarIcon(AshlarIconsRoundedStroke.ellipsis, size: 14),
                ),
              ),
            ],
          ),
          Text(
            [
              task.schedule.label,
              if (next != null)
                'next ${monthDay(next)} at ${clock(next)}'
              else if (!task.enabled)
                'off'
              else
                'done',
              tildePath(task.cwd),
              task.level.label,
            ].join('  ·  '),
            style: muted,
          ),
          Text(
            task.prompt,
            maxLines: 2,
            overflow: .ellipsis,
            style: t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.45),
          ),
          if (runs.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final s in runs.take(5))
              Pressable(
                onPressed: () => context.go('/s/${s.id}'),
                semanticLabel: 'Open the run of ${monthDay(s.createdAt)}',
                builder: (context, state) => Padding(
                  padding: const .symmetric(vertical: 2),
                  child: Row(
                    spacing: 8,
                    children: [
                      AshlarIcon(
                        AshlarIconsRoundedStroke.messageSquare,
                        size: 12,
                        color: t.colors.mutedForeground,
                      ),
                      Text(
                        'Ran ${monthDay(s.createdAt)} at ${clock(s.createdAt)}',
                        style: muted.copyWith(
                          color: state.hovered ? t.colors.foreground : null,
                          decoration: state.hovered ? TextDecoration.underline : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (runs.length > 5)
              Text('and ${runs.length - 5} earlier, in the chat list', style: muted),
          ],
        ],
      ),
    );
  }
}

/// Opens the editor for a new task, or for [task].
Future<void> editTask(BuildContext context, ScheduleViewModel vm, {ScheduledTask? task}) =>
    showAshlarDialog<void>(
      context: context,
      builder: (context) => _TaskEditor(vm: vm, task: task),
    );

class _TaskEditor extends StatefulWidget {
  const new({required this.vm, this.task});
  final ScheduleViewModel vm;
  final ScheduledTask? task;

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final _name = TextEditingController(text: widget.task?.name ?? '');
  late final _prompt = TextEditingController(text: widget.task?.prompt ?? '');
  late String _cwd = widget.task?.cwd ?? widget.vm.defaultFolder;
  late PermissionLevel _level = widget.task?.level ?? .readOnly;
  late Repeat _repeat = widget.task?.schedule.repeat ?? .daily;

  /// Minutes after midnight.
  late int _time = widget.task == null
      ? 9 * 60
      : widget.task!.schedule.at.hour * 60 + widget.task!.schedule.at.minute;
  late int _weekday = widget.task?.schedule.at.weekday ?? DateTime.monday;

  /// For chosen days: which, Monday 1 to Sunday 7.
  late Set<int> _days = {...?widget.task?.schedule.days};

  /// For a one-off: days from today.
  int _inDays = 0;

  @override
  void initState() {
    super.initState();
    if (widget.task?.schedule case Schedule(repeat: .once, :final at)) {
      final today = DateTime.now();
      _inDays = DateTime(
        at.year,
        at.month,
        at.day,
      ).difference(DateTime(today.year, today.month, today.day)).inDays.clamp(0, 13);
    }
    _name.addListener(() => setState(() {}));
    _prompt.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Schedule get _schedule {
    final h = _time ~/ 60, m = _time % 60;
    final today = DateTime.now();
    return Schedule(_repeat, switch (_repeat) {
      .once => DateTime(today.year, today.month, today.day + _inDays, h, m),
      // 2026-01-05 is a Monday: the weekday is carried in the date.
      .weekly => DateTime(2026, 1, 4 + _weekday, h, m),
      _ => DateTime(2026, 1, 1, h, m),
    }, days: _repeat == .days ? _days : const {});
  }

  Future<void> _save() async {
    final name = _name.text.trim(), prompt = _prompt.text.trim();
    if (name.isEmpty || prompt.isEmpty || (_repeat == .days && _days.isEmpty)) return;
    final task = widget.task;
    if (task == null) {
      await widget.vm.add(
        name: name,
        prompt: prompt,
        cwd: _cwd,
        level: _level,
        schedule: _schedule,
      );
    } else {
      await widget.vm.save(
        task.copyWith(name: name, prompt: prompt, cwd: _cwd, level: _level, schedule: _schedule),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final label = t.text.xs.copyWith(color: t.colors.mutedForeground, fontWeight: .w500);
    Widget field(String name, Widget child) => Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        Text(name, style: label),
        child,
      ],
    );
    final times = [
      for (var m = 0; m < 24 * 60; m += 15)
        SelectOption(
          m,
          _repeat == .hourly
              ? ':${(m % 60).toString().padLeft(2, '0')}'
              : clock(DateTime(2026, 1, 1, m ~/ 60, m % 60)),
        ),
    ];
    final ready =
        _name.text.trim().isNotEmpty &&
        _prompt.text.trim().isNotEmpty &&
        (_repeat != .days || _days.isNotEmpty);
    final next = _schedule.nextAfter(DateTime.now());
    return HelmyDialog(
      title: widget.task == null ? 'New scheduled task' : 'Edit scheduled task',
      icon: AshlarIconsRoundedStroke.clock,
      content: Column(
        crossAxisAlignment: .stretch,
        spacing: 14,
        children: [
          field('Name', Input(controller: _name, autofocus: true, placeholder: 'Morning summary')),
          field(
            'Message',
            Textarea(
              controller: _prompt,
              minLines: 3,
              maxLines: 8,
              placeholder: 'What Helmy is asked each time',
            ),
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: field(
                  'Repeats',
                  Select<Repeat>(
                    value: _repeat,
                    options: [for (final r in Repeat.values) SelectOption(r, r.label)],
                    onChanged: (r) => setState(() => _repeat = r),
                  ),
                ),
              ),
              if (_repeat == .weekly)
                Expanded(
                  child: field(
                    'On',
                    Select<int>(
                      value: _weekday,
                      options: [
                        for (var d = 1; d <= 7; d++)
                          SelectOption(
                            d,
                            const [
                              'Monday',
                              'Tuesday',
                              'Wednesday',
                              'Thursday',
                              'Friday',
                              'Saturday',
                              'Sunday',
                            ][d - 1],
                          ),
                      ],
                      onChanged: (d) => setState(() => _weekday = d),
                    ),
                  ),
                ),
              if (_repeat == .days)
                Expanded(
                  child: field(
                    'On',
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (var d = 1; d <= 7; d++)
                          Button(
                            size: .xs,
                            variant: _days.contains(d) ? .secondary : .ghost,
                            semanticLabel: const [
                              'Mon',
                              'Tue',
                              'Wed',
                              'Thu',
                              'Fri',
                              'Sat',
                              'Sun',
                            ][d - 1],
                            onPressed: () => setState(() {
                              _days = {..._days};
                              _days.contains(d) ? _days.remove(d) : _days.add(d);
                            }),
                            child: Text(const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d - 1]),
                          ),
                      ],
                    ),
                  ),
                ),
              if (_repeat == .once)
                Expanded(
                  child: field(
                    'On',
                    Select<int>(
                      value: _inDays,
                      options: [
                        for (var d = 0; d < 14; d++)
                          SelectOption(
                            d,
                            d == 0
                                ? 'Today'
                                : d == 1
                                ? 'Tomorrow'
                                : monthDay(DateTime.now().add(Duration(days: d))),
                          ),
                      ],
                      onChanged: (d) => setState(() => _inDays = d),
                    ),
                  ),
                ),
              Expanded(
                child: field(
                  _repeat == .hourly ? 'At minute' : 'At',
                  Select<int>(
                    value: _repeat == .hourly ? _time % 60 : _time,
                    options: _repeat == .hourly ? times.take(4).toList() : times,
                    onChanged: (m) => setState(() => _time = _repeat == .hourly ? m : m),
                  ),
                ),
              ),
            ],
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: field(
                  'Folder',
                  Pressable(
                    onPressed: () async {
                      final dir = await getDirectoryPath(
                        initialDirectory: _cwd,
                        confirmButtonText: 'Work here',
                      );
                      if (dir != null) setState(() => _cwd = dir);
                    },
                    semanticLabel: 'Folder: ${tildePath(_cwd)}. Change',
                    builder: (context, state) => Container(
                      height: 36,
                      padding: const .symmetric(horizontal: 12),
                      alignment: AlignmentDirectional.centerStart,
                      decoration: BoxDecoration(
                        color: state.hovered ? t.colors.accent : null,
                        border: Border.all(color: t.colors.input),
                        borderRadius: .circular(t.radiusMd),
                      ),
                      child: Row(
                        spacing: 8,
                        children: [
                          const AshlarIcon(AshlarIconsRoundedStroke.folder, size: 14),
                          Expanded(
                            child: Text(
                              tildePath(_cwd),
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: t.text.sm,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: field(
                  'Helmy may',
                  Select<PermissionLevel>(
                    value: _level,
                    options: [for (final l in PermissionLevel.values) SelectOption(l, l.label)],
                    onChanged: (l) => setState(() => _level = l),
                  ),
                ),
              ),
            ],
          ),
          Text(
            [
              if (next == null)
                'That time has passed.'
              else
                'Runs next ${monthDay(next)} at ${clock(next)}.',
              if (_level == .ask) 'Each approval it needs waits for you, with a notification.',
            ].join(' '),
            style: t.text.xs.copyWith(color: t.colors.mutedForeground),
          ),
        ],
      ),
      actions: [
        DialogButton('Cancel', onPressed: () => Navigator.pop(context)),
        DialogButton(
          widget.task == null ? 'Create' : 'Save',
          main: true,
          onPressed: ready && next != null ? _save : () {},
        ),
      ],
    );
  }
}
