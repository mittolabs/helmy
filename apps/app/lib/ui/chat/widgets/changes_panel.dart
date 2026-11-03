import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../../data/services/snapshots.dart';
import '../../../utils/diffs.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/collapsible.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/select.dart';
import '../../../domain/models/chat_item.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../view_models/chat_view_model.dart';

/// Beside the conversation: every file the session changed, each opening to
/// its diff. In a git repository that is everything changed since the session
/// started, by an agent's edit or a command alike; elsewhere, the edits the
/// agents reported, and it says so.
class ChangesPanel extends StatefulWidget {
  const new({super.key, required this.vm});
  final ChatViewModel vm;

  @override
  State<ChangesPanel> createState() => _ChangesPanelState();
}

class _ChangesPanelState extends State<ChangesPanel> {
  List<FileChange>? _changes;
  bool _loading = true;
  bool _wasBusy = false;
  int? _scope;

  ChatViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    _scope = vm.changesScope;
    vm.addListener(_onVm);
    _load();
  }

  @override
  void dispose() {
    vm.removeListener(_onVm);
    super.dispose();
  }

  /// Reads again when a turn ends, since that is when files will have changed.
  void _onVm() {
    if (_wasBusy && !vm.busy || _scope != vm.changesScope) {
      _scope = vm.changesScope;
      _load();
    }
    _wasBusy = vm.busy;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final changes = await vm.changes();
    if (!mounted) return;
    setState(() {
      _changes = changes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.xs.copyWith(color: c.mutedForeground);
    final git = _changes != null;
    final reported = git ? const <({String path, FileDiff diff})>[] : _reported();
    final count = git ? _changes!.length : reported.length;
    return ColoredBox(
      color: c.background,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const .fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    count == 0 ? 'Changes' : 'Changes ($count)',
                    style: t.text.sm.copyWith(fontWeight: .w600),
                  ),
                ),
                if (_loading) const Spinner(size: 12),
                Tooltip(
                  message: 'Read again',
                  child: Button(
                    variant: .ghost,
                    size: .iconSm,
                    semanticLabel: 'Read changes again',
                    onPressed: _load,
                    child: const AshlarIcon(AshlarIconsRoundedStroke.refreshCw, size: 14),
                  ),
                ),
                Tooltip(
                  message: 'Close',
                  child: Button(
                    variant: .ghost,
                    size: .iconSm,
                    semanticLabel: 'Close changes',
                    onPressed: vm.toggleChanges,
                    child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 14),
                  ),
                ),
              ],
            ),
          ),
          if (vm.turnsWithChanges.isNotEmpty)
            Padding(
              padding: const .fromLTRB(16, 0, 16, 10),
              child: Select<int?>(
                value: vm.changesScope,
                size: .sm,
                options: [
                  const SelectOption(null, 'Whole session'),
                  for (final i in vm.turnsWithChanges.reversed)
                    SelectOption(i, 'After "${_short((vm.items[i] as UserMessage).text)}"'),
                ],
                onChanged: vm.setChangesScope,
              ),
            ),
          Padding(
            padding: const .fromLTRB(16, 0, 16, 10),
            child: Text(
              vm.changesScope != null
                  ? git
                        ? "What this one message's turn changed, by Helmy's edits or commands."
                        : "This folder is not a git repository, so these are only Helmy's own "
                              "edits in this turn."
                  : git
                  ? 'Everything changed in this folder since the session started, by an '
                        "agent's edit or a command."
                  : "This folder is not a git repository, so these are only Helmy's own "
                        'edits. Changes made by commands are not shown.',
              style: muted,
            ),
          ),
          Expanded(
            child: count == 0 && !_loading
                ? Center(child: Text('No files changed yet.', style: muted))
                : ScrollArea(
                    child: Padding(
                      padding: const .fromLTRB(8, 0, 8, 16),
                      child: Column(
                        crossAxisAlignment: .stretch,
                        children: [
                          if (git)
                            for (final ch in _changes!) _FileRow(change: ch, vm: vm)
                          else
                            for (final r in reported)
                              _FileRow(
                                change: (
                                  path: r.path,
                                  added: r.diff.added,
                                  removed: r.diff.removed,
                                  kind: 'edited',
                                ),
                                vm: vm,
                                diff: r.diff,
                              ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// The agents' reported edits, one row per file with all its edits together.
  List<({String path, FileDiff diff})> _reported() {
    final byPath = <String, List<FileDiff>>{};
    for (final call in vm.reportedChanges) {
      for (final d in diffsOf(call)) {
        byPath.putIfAbsent(d.path, () => []).add(d);
      }
    }
    return [
      for (final e in byPath.entries)
        (
          path: e.key,
          diff: (
            path: e.key,
            lines: [for (final d in e.value) ...d.lines],
            added: e.value.fold(0, (n, d) => n + d.added),
            removed: e.value.fold(0, (n, d) => n + d.removed),
          ),
        ),
    ];
  }
}

/// A message's first words, for the scope picker.
String _short(String text) {
  final one = text.replaceAll('\n', ' ').trim();
  return one.length > 40 ? '${one.substring(0, 37)}...' : one;
}

/// A changed file: its name, how much changed, and its diff when opened.
class _FileRow extends StatefulWidget {
  const new({required this.change, required this.vm, this.diff});
  final FileChange change;
  final ChatViewModel vm;

  /// Already known, for reported edits; read from git when opened otherwise.
  final FileDiff? diff;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  FileDiff? _diff;

  Future<void> _open() async {
    if (_diff != null || widget.diff != null) return;
    final text = await widget.vm.diffOf(widget.change.path);
    if (mounted) setState(() => _diff = parseUnified(widget.change.path, text));
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final ch = widget.change;
    final name = ch.path.split('/').last;
    final folder = ch.path.contains('/') ? ch.path.substring(0, ch.path.lastIndexOf('/')) : '';
    final diff = widget.diff ?? _diff;
    return Collapsible(
      onChanged: (open) {
        if (open) _open();
      },
      builder: (context, open, toggle) => Pressable(
        onPressed: toggle,
        semanticLabel: '${ch.path}, ${ch.kind}',
        builder: (context, state) => Container(
          padding: const .symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: state.hovered || open ? c.accent.withValues(alpha: .6) : null,
            borderRadius: .circular(t.radiusMd),
          ),
          child: Row(
            spacing: 8,
            children: [
              AshlarIcon(
                switch (ch.kind) {
                  'added' => AshlarIconsRoundedStroke.filePlus,
                  'removed' => AshlarIconsRoundedStroke.fileMinus,
                  _ => AshlarIconsRoundedStroke.filePen,
                },
                size: 14,
                color: c.mutedForeground,
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name,
                        style: t.text.sm.copyWith(color: c.foreground),
                      ),
                      if (folder.isNotEmpty)
                        TextSpan(
                          text: '  $folder',
                          style: t.text.xs.copyWith(color: c.mutedForeground),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
              ),
              Text(
                '+${ch.added} -${ch.removed}',
                style: t.text.xs.copyWith(fontFamily: 'Menlo', color: c.mutedForeground),
              ),
            ],
          ),
        ),
      ),
      child: Padding(
        padding: const .fromLTRB(8, 4, 0, 10),
        child: diff == null
            ? const Align(alignment: AlignmentDirectional.centerStart, child: Spinner(size: 12))
            : _PanelDiff(diff: diff),
      ),
    );
  }
}

/// A diff in the panel's narrow column: lines wrap rather than scroll, and a
/// long one is cut so the panel keeps a single scroll.
class _PanelDiff extends StatelessWidget {
  const new({required this.diff});
  final FileDiff diff;

  static const _maxLines = 200;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final base = t.text.xs.copyWith(fontFamily: 'Menlo', height: 1.45);
    final lines = diff.lines.where((l) => !l.startsWith('\\')).take(_maxLines).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: .circular(t.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          for (final l in lines)
            Container(
              color: l.startsWith('+')
                  ? c.foreground.withValues(alpha: .07)
                  : l.startsWith('-')
                  ? c.foreground.withValues(alpha: .03)
                  : null,
              padding: const .symmetric(horizontal: 8),
              child: Text(
                l.isEmpty ? ' ' : l,
                style: l.startsWith('@@')
                    ? base.copyWith(color: c.mutedForeground)
                    : l.startsWith('+')
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
              padding: const .all(8),
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
