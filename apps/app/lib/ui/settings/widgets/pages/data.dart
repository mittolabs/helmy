part of '../settings_screen.dart';

String _size(int? bytes) {
  if (bytes == null) return 'Nothing yet';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

class _Data extends StatefulWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_Data> createState() => _DataState();
}

class _DataState extends State<_Data> {
  SettingsViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = await getApplicationSupportDirectory();
    await vm.loadPlaces(dir.path);
  }

  Future<void> _export() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Export here');
    if (dir == null || !mounted) return;
    final n = await context.read<ChatExport>().exportAll(dir);
    if (mounted) {
      showSavedToast(
        context,
        dir,
        files: widget.vm.fileActions,
        title: '$n conversation${n == 1 ? '' : 's'} exported',
      );
    }
  }

  Future<void> _clear(String label, String path) async {
    final ok = await confirm(
      context,
      title: 'Clear ${label.toLowerCase()}?',
      body: '${tildePath(path)} is emptied. This cannot be undone.',
      action: 'Clear',
      destructive: true,
    );
    if (!ok) return;
    final dir = Directory(path);
    if (dir.existsSync()) {
      for (final e in dir.listSync()) {
        e.deleteSync(recursive: true);
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    return _Page(
      children: [
        const _Heading('Where things are', first: true),
        if (vm.places.isEmpty) const Padding(padding: .all(16), child: Spinner(size: 16)),
        for (final p in vm.places)
          _Row(
            title: '${p.label}  ·  ${_size(p.bytes)}',
            description: '${p.note}\n${tildePath(p.path)}',
            control: Row(
              spacing: 8,
              children: [
                if (p.label == 'Pasted pictures' && (p.bytes ?? 0) > 0)
                  Button(
                    size: .sm,
                    variant: .ghost,
                    onPressed: () => _clear(p.label, p.path),
                    child: const Text('Clear'),
                  ),
                if (p.bytes != null)
                  Button(
                    size: .sm,
                    variant: .outline,
                    onPressed: () => vm.reveal(p.path),
                    child: Text('Show in ${Desktop.current.fileManager}'),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const .only(top: 8),
          child: Text(
            "Deleting a session in Helmy does not delete the agent's own copy. Those stay in the "
            'folders above until you remove them there.',
            style: muted,
          ),
        ),
        const _Heading('Your conversations'),
        _Row(
          title: 'Export all conversations',
          description: 'Each session as a Markdown file, in a folder you choose.',
          control: Button(
            size: .sm,
            variant: .outline,
            onPressed: _export,
            child: const Text('Export...'),
          ),
        ),
        _Heading('What leaves ${Desktop.current.thisComputer}'),
        Text(
          'Each message goes to the company behind the agent that answers it (Anthropic for '
          'Claude Code, OpenAI for Codex), with the files and command output that agent reads to '
          'answer. With a model on Ollama, nothing leaves. Helmy itself sends nothing anywhere: '
          'its sessions, settings and logs stay in the folders above.',
          style: t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.5),
        ),
      ],
    );
  }
}
