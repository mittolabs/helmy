import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../data/services/editors.dart';
import '../../../domain/models/project_action.dart';
import '../../../utils/platform.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/dialog.dart';
import '../../core/ashlar/dropdown_menu.dart';
import '../../core/ashlar/input.dart';
import '../../core/ashlar/switch.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/toast.dart';
import '../../core/ashlar/tooltip.dart';
import '../../core/helmy_dialog.dart';
import '../view_models/chat_view_model.dart';

/// The keys that run the first nine actions, in the menu's order: ⌘⌥1 to ⌘⌥9.
const actionKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// The action ⌘R runs: the one run last, else the project's first.
ProjectAction? actionToRun(ChatViewModel vm) =>
    vm.actions.where((a) => a.key == vm.lastAction?.key).firstOrNull ?? vm.actions.firstOrNull;

/// An app's own icon, at [size]; [fallback] where there is none.
Widget appIcon(Editor? e, {double size = 16, IconData fallback = AshlarIconsRoundedStroke.code}) =>
    e?.icon == null
    ? AshlarIcon(fallback, size: size)
    : Image.memory(e!.icon!, width: size, height: size, filterQuality: .medium);

/// In the header: runs the project's action again (the last one run, else
/// its first), with ⌘R. Shown when the project has actions.
class ProjectRunButton extends StatelessWidget {
  const ProjectRunButton({super.key, required this.vm, this.compact = false});
  final ChatViewModel vm;

  /// Narrow: the icon alone.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final action = actionToRun(vm);
    if (action == null) return const SizedBox.shrink();
    final label = 'Run ${action.name}';
    return Tooltip(
      message: '$label: ${action.command} (${Desktop.current.keys('⌘R')})',
      child: Button(
        variant: .ghost,
        size: compact ? .icon : .sm,
        semanticLabel: label,
        onPressed: () => vm.run(action),
        leading: compact ? null : const AshlarIcon(AshlarIconsRoundedStroke.play, size: 14),
        child: compact
            ? const AshlarIcon(AshlarIconsRoundedStroke.play, size: 16)
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(action.name, maxLines: 1, overflow: .ellipsis),
              ),
      ),
    );
  }
}

/// In the header: the project, as T3 Code's menu has it but chosen for you.
/// Open it in your editor (the one you use, with the others a step away),
/// run what it is worked with, add your own, and show it in Finder.
class ProjectMenu extends StatelessWidget {
  const ProjectMenu({super.key, required this.vm});
  final ChatViewModel vm;

  Future<void> _open(BuildContext context, [Editor? app]) async {
    final e = app ?? vm.editor;
    final ok = await vm.openIn(app);
    if (!ok && context.mounted) {
      showToast(
        context,
        title: e == null ? 'No editor found' : "${e.name} didn't open",
        description: e == null
            ? 'Install an editor such as VS Code, Cursor or Zed, and it shows here.'
            : 'macOS would not open the project in it. Try again, or choose another app.',
        type: .error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final editor = vm.editor;
    final others = vm.editors.where((e) => e.id != editor?.id).toList();
    final folder = vm.session?.cwd ?? '';
    final groups = <String?, List<ProjectAction>>{};
    for (final a in vm.actions) {
      (groups[a.from] ??= []).add(a);
    }
    var n = 0;
    return DropdownMenu(
      align: .end,
      width: 340,
      items: [
        if (editor != null)
          MenuItem(
            leading: appIcon(editor),
            shortcut: Text(Desktop.current.keys('⌘⇧O')),
            onPressed: () => _open(context),
            child: Text('Open in ${editor.name}'),
          ),
        if (others.isNotEmpty)
          MenuSub(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.appWindow, size: 16),
            items: [
              for (final e in others)
                MenuItem(
                  leading: appIcon(e),
                  onPressed: () => _open(context, e),
                  child: Text(e.name),
                ),
            ],
            child: const Text('Open in'),
          ),
        if (Platform.isMacOS)
          MenuItem(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.folderOpen, size: 16),
            onPressed: () => vm.reveal(folder),
            child: const Text('Show in Finder'),
          ),
        const MenuSeparator(),
        for (final MapEntry(key: from, value: list) in groups.entries) ...[
          MenuLabel(child: Text(from ?? 'Yours')),
          for (final a in list)
            MenuItem(
              leading: const AshlarIcon(AshlarIconsRoundedStroke.play, size: 16),
              shortcut: n < actionKeys.length ? Text(Desktop.current.keys('⌘⌥${++n}')) : null,
              onPressed: () => vm.run(a),
              child: Row(
                spacing: 8,
                children: [
                  Text(a.name),
                  Flexible(
                    child: Text(
                      a.command,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: muted.copyWith(fontFamily: 'Menlo', fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (vm.actions.any((a) => a.own))
          MenuSub(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.pencil, size: 16),
            items: [
              for (final a in vm.actions.where((a) => a.own))
                MenuItem(onPressed: () => editAction(context, vm, a), child: Text(a.name)),
            ],
            child: const Text('Change an action'),
          ),
        MenuItem(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.plus, size: 16),
          onPressed: () => editAction(context, vm),
          child: const Text('Add an action...'),
        ),
      ],
      builder: (context, menu) => Tooltip(
        message: 'Project: open it, run it',
        child: Button(
          variant: .ghost,
          size: .icon,
          semanticLabel: 'Project',
          onPressed: () {
            vm.refreshActions();
            menu.open();
          },
          child: appIcon(editor),
        ),
      ),
    );
  }
}

/// Adds an action, or changes [action] (one of the user's own).
Future<void> editAction(BuildContext context, ChatViewModel vm, [ProjectAction? action]) async {
  final result = await showAshlarDialog<_Edit>(
    context: context,
    builder: (context) =>
        _ActionDialog(action: action, copies: vm.session?.repo != null || vm.inRepo),
  );
  switch (result) {
    case _Save(:final next):
      await vm.saveAction(next, replacing: action);
    case _Remove():
      await vm.removeAction(action!);
    case null:
  }
}

sealed class _Edit {}

class _Save extends _Edit {
  _Save(this.next);
  final ProjectAction next;
}

class _Remove extends _Edit {}

class _ActionDialog extends StatefulWidget {
  const _ActionDialog({this.action, required this.copies});
  final ProjectAction? action;

  /// The project is a git repository, so sessions can have their own copies.
  final bool copies;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  late final _name = TextEditingController(text: widget.action?.name ?? '');
  late final _command = TextEditingController(text: widget.action?.command ?? '');
  late bool _onNewCopy = widget.action?.onNewCopy ?? false;

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    super.dispose();
  }

  bool get _ready => _name.text.trim().isNotEmpty && _command.text.trim().isNotEmpty;

  void _save() {
    if (!_ready) return;
    Navigator.pop(
      context,
      _Save(
        ProjectAction(
          name: _name.text.trim(),
          command: _command.text.trim(),
          onNewCopy: _onNewCopy,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final label = t.text.sm.copyWith(fontWeight: .w500);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground, height: 1.4);
    final editing = widget.action != null;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: HelmyDialog(
        title: editing ? 'Change the action' : 'Add an action',
        body:
            'A command this project is worked with. It runs in a terminal beside the '
            'conversation, in the thread\'s folder.',
        icon: AshlarIconsRoundedStroke.play,
        content: ListenableBuilder(
          listenable: Listenable.merge([_name, _command]),
          builder: (context, _) => Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            children: [
              Text('Name', style: label),
              const SizedBox(height: 6),
              Input(
                controller: _name,
                autofocus: true,
                placeholder: 'dev',
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 14),
              Text('Command', style: label),
              const SizedBox(height: 6),
              Input(controller: _command, placeholder: 'npm run dev', onSubmitted: (_) => _save()),
              if (widget.copies) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: .start,
                  spacing: 12,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text('Run in each new copy', style: label),
                          const SizedBox(height: 2),
                          Text(
                            'When a thread gets its own copy of the project, this runs '
                            'there first: to install what it needs, say.',
                            style: muted,
                          ),
                        ],
                      ),
                    ),
                    Switch(value: _onNewCopy, onChanged: (v) => setState(() => _onNewCopy = v)),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (editing) ...[
            DialogButton(
              'Remove',
              destructive: true,
              onPressed: () => Navigator.pop(context, _Remove()),
            ),
            const Spacer(),
          ],
          DialogButton('Cancel', onPressed: () => Navigator.pop(context)),
          DialogButton(editing ? 'Save' : 'Add', main: true, onPressed: _save),
        ],
      ),
    );
  }
}
