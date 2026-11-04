import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../utils/format.dart';
import '../../utils/platform.dart';
import '../core/ashlar/button.dart';
import '../core/ashlar/pressable.dart';
import '../core/ashlar/spinner.dart';
import '../core/ashlar/theme.dart';
import '../core/ashlar/toast.dart';
import 'history_import_view_model.dart';

/// The folders with conversations from Claude Code and Codex on this Mac,
/// each to bring in or not, as T3 Code's import shows them: recent work
/// chosen to start with, all or none a press away.
class ImportList extends StatefulWidget {
  const ImportList({super.key, required this.vm});
  final HistoryImportViewModel vm;

  @override
  State<ImportList> createState() => _ImportListState();
}

class _ImportListState extends State<ImportList> {
  @override
  void initState() {
    super.initState();
    if (widget.vm.projects == null) widget.vm.load();
  }

  Future<void> _import() async {
    final n = await widget.vm.importChosen();
    if (!mounted) return;
    showToast(
      context,
      title: n == 0 ? 'Nothing was brought in' : '$n conversation${n == 1 ? '' : 's'} brought in',
      description: n == 0
          ? "Those conversations couldn't be read."
          : 'Each is a session in the sidebar, and goes on where it left off.',
      type: n == 0 ? .error : .success,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.vm,
    builder: (context, _) {
      final vm = widget.vm;
      final t = AshlarTheme.of(context);
      final c = t.colors;
      final muted = t.text.xs.copyWith(color: c.mutedForeground);
      final projects = vm.projects;
      if (projects == null) {
        return const Padding(
          padding: .all(16),
          child: Center(child: Spinner(size: 16)),
        );
      }
      if (projects.isEmpty) {
        return Padding(
          padding: const .all(16),
          child: Text(
            vm.imported != null
                ? 'Everything here has been brought in.'
                : 'Nothing to bring in: no conversations from Claude Code or Codex in folders '
                      'on this Mac.',
            style: t.text.sm.copyWith(color: c.mutedForeground),
          ),
        );
      }
      final progress = vm.progress;
      final now = DateTime.now();
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const .fromLTRB(16, 12, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text('${vm.chosen.length} of ${projects.length} chosen', style: muted),
                ),
                Button(
                  variant: .ghost,
                  size: .xs,
                  onPressed: progress == null ? () => vm.chooseAll(true) : null,
                  child: const Text('Choose all'),
                ),
                Button(
                  variant: .ghost,
                  size: .xs,
                  onPressed: progress == null ? () => vm.chooseAll(false) : null,
                  child: const Text('Choose none'),
                ),
              ],
            ),
          ),
          for (final p in projects)
            Pressable(
              onPressed: progress == null ? () => vm.toggle(p.cwd) : null,
              semanticLabel:
                  '${_name(p.cwd)}, ${vm.chosen.contains(p.cwd) ? 'chosen' : 'not chosen'}',
              builder: (context, state) => Container(
                padding: const .symmetric(horizontal: 16, vertical: 9),
                color: state.hovered ? c.accent.withValues(alpha: .5) : null,
                child: Row(
                  spacing: 10,
                  children: [
                    _Tick(on: vm.chosen.contains(p.cwd)),
                    Flexible(
                      flex: 0,
                      child: Text(
                        _name(p.cwd),
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: t.text.sm.copyWith(fontWeight: .w500),
                      ),
                    ),
                    Expanded(
                      child: Text(tildePath(p.cwd), maxLines: 1, overflow: .ellipsis, style: muted),
                    ),
                    Text(
                      [
                        if (p.kinds.contains('claude')) 'Claude Code',
                        if (p.kinds.contains('codex')) 'Codex',
                      ].join(' · '),
                      style: muted,
                    ),
                    SizedBox(
                      width: 28,
                      child: Text('${p.conversations.length}', textAlign: .right, style: muted),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        ago(p.latest, now: now),
                        textAlign: .right,
                        maxLines: 1,
                        softWrap: false,
                        style: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const .fromLTRB(16, 10, 16, 14),
            child: Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Text(
                    progress == null
                        ? 'Each comes in as a session, and goes on where it left off.'
                        : 'Bringing in ${progress.$1} of ${progress.$2}...',
                    style: muted,
                  ),
                ),
                Button(
                  size: .sm,
                  onPressed: progress == null && vm.chosen.isNotEmpty ? _import : null,
                  leading: progress == null
                      ? const AshlarIcon(AshlarIconsRoundedStroke.download, size: 14)
                      : const Spinner(size: 14),
                  child: Text(
                    vm.chosenConversations == 0
                        ? 'Bring in'
                        : 'Bring in ${vm.chosenConversations} conversation${vm.chosenConversations == 1 ? '' : 's'}',
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// A folder's name; the home folder is Home, not the user's name.
String _name(String cwd) => cwd == homeDir ? 'Home' : folderName(cwd);

/// A box ticked or not.
class _Tick extends StatelessWidget {
  const _Tick({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: on ? c.primary : null,
        border: Border.all(color: on ? c.primary : c.border, width: 1.5),
        borderRadius: .circular(4),
      ),
      alignment: .center,
      child: on
          ? AshlarIcon(AshlarIconsRoundedStroke.check, size: 11, color: c.primaryForeground)
          : null,
    );
  }
}
