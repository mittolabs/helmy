part of '../settings_screen.dart';

class _Memory extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    if (vm.loadingMemory) return const Center(child: Spinner(size: 18));
    return Padding(
      padding: const .fromLTRB(8, 0, 32, 24),
      child: LayoutBuilder(
        builder: (context, box) {
          // Narrow: the list, or the file chosen from it with a way back.
          if (box.maxWidth < 560) {
            if (vm.selected == null) return _MemoryList(vm: vm);
            return Column(
              crossAxisAlignment: .start,
              spacing: 8,
              children: [
                Button(
                  variant: .ghost,
                  size: .sm,
                  onPressed: vm.closeFile,
                  child: const Row(
                    mainAxisSize: .min,
                    spacing: 6,
                    children: [
                      AshlarIcon(AshlarIconsRoundedStroke.arrowLeft, size: 14),
                      Text('All files'),
                    ],
                  ),
                ),
                Expanded(
                  child: _MemoryEditor(key: ValueKey(vm.selected!.path), vm: vm),
                ),
              ],
            );
          }
          return _memoryBeside(t);
        },
      ),
    );
  }

  Widget _memoryBeside(AshlarThemeData t) => Row(
    crossAxisAlignment: .stretch,
    spacing: 20,
    children: [
      SizedBox(width: 300, child: _MemoryList(vm: vm)),
      Expanded(
        child: vm.selected == null
            ? Center(
                child: Text(
                  'Choose a file to read or change it.',
                  style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                ),
              )
            : _MemoryEditor(key: ValueKey(vm.selected!.path), vm: vm),
      ),
    ],
  );
}

class _MemoryList extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final names = {for (final a in vm.agents) a.info.id: a.info.name};
    final rows = <Widget>[];
    for (final engineId in names.keys) {
      final files = vm.files.where((f) => f.engineId == engineId).toList();
      final notes = vm.notes.where((n) => n.engineId == engineId);
      if (files.isEmpty && notes.isEmpty) continue;
      rows.add(
        Padding(
          padding: const .only(top: 14, bottom: 4),
          child: Text(names[engineId]!, style: t.text.sm.copyWith(fontWeight: .w600)),
        ),
      );
      String? project;
      for (final f in files) {
        if (f.project != null && f.project != project) {
          project = f.project;
          rows.add(
            Padding(
              padding: const .only(top: 8, bottom: 2, left: 8),
              child: Text(tildePath(project!), style: muted, maxLines: 1, overflow: .ellipsis),
            ),
          );
        }
        rows.add(_MemoryRow(file: f, vm: vm));
      }
      for (final n in notes) {
        rows.add(
          Padding(
            padding: const .fromLTRB(8, 8, 8, 0),
            child: Text(n.text, style: muted),
          ),
        );
      }
    }
    return ScrollArea(
      child: Column(crossAxisAlignment: .stretch, children: rows),
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const new({required this.file, required this.vm});
  final MemoryFile file;
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final selected = vm.selected?.path == file.path;
    final exists = vm.exists(file);
    final name = file.project == null ? file.kind : file.path.split('/').last;
    return Pressable(
      onPressed: () => vm.open(file),
      selected: selected,
      semanticLabel: name,
      builder: (context, state) => Container(
        padding: .fromLTRB(file.project == null ? 8 : 16, 5, 8, 5),
        decoration: BoxDecoration(
          color: selected
              ? t.colors.accent
              : state.hovered
              ? t.colors.accent.withValues(alpha: .5)
              : null,
          borderRadius: .circular(t.radiusMd),
        ),
        child: Text(
          exists ? name : '$name (not written yet)',
          maxLines: 1,
          overflow: .ellipsis,
          style: t.text.sm.copyWith(color: exists ? t.colors.foreground : t.colors.mutedForeground),
        ),
      ),
    );
  }
}

class _MemoryEditor extends StatefulWidget {
  const new({super.key, required this.vm});
  final SettingsViewModel vm;

  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<_MemoryEditor> {
  final _text = TextEditingController();
  bool _filled = false;

  /// Shown formatted until you choose to edit it.
  bool _editing = false;

  SettingsViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete this memory?',
      body: '${tildePath(vm.selected!.path)} is removed from disk. The agent no longer reads it.',
      action: 'Delete',
      destructive: true,
    );
    if (ok) await vm.remove.execute();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final original = vm.original;
    if (original == null) return const Center(child: Spinner(size: 18));
    if (!_filled) {
      _filled = true;
      _text.text = original;
    }
    final file = vm.selected!;
    final dirty = _text.text != original;
    final path = Text(
      tildePath(file.path),
      style: t.text.xs.copyWith(color: t.colors.mutedForeground),
      maxLines: 1,
      overflow: .ellipsis,
    );
    if (!_editing) {
      return Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          path,
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: t.colors.border),
                borderRadius: .circular(t.radiusLg),
              ),
              child: ScrollArea(
                child: Padding(
                  padding: const .all(16),
                  child: original.trim().isEmpty
                      ? Text(
                          'Empty. What you write here is read in every new conversation.',
                          style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                        )
                      : MarkdownPreview(original),
                ),
              ),
            ),
          ),
          Row(
            spacing: 8,
            children: [
              Button(
                variant: .outline,
                onPressed: () => setState(() => _editing = true),
                child: const Text('Edit'),
              ),
              const Spacer(),
              if (vm.exists(file))
                Button(variant: .ghost, onPressed: _delete, child: const Text('Delete')),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        path,
        Expanded(
          child: Textarea(
            controller: _text,
            autofocus: true,
            minLines: 20,
            maxLines: 40,
            resizable: false,
            placeholder: 'Empty. What you write here is read in every new conversation.',
          ),
        ),
        Row(
          spacing: 8,
          children: [
            Button(
              onPressed: dirty
                  ? () async {
                      await vm.save.execute(_text.text);
                      if (mounted) setState(() => _editing = false);
                    }
                  : null,
              child: const Text('Save'),
            ),
            Button(
              variant: .ghost,
              onPressed: () => setState(() {
                _text.text = original;
                _editing = false;
              }),
              child: Text(dirty ? 'Discard changes' : 'Done'),
            ),
          ],
        ),
      ],
    );
  }
}
