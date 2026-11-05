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

  /// Conversations from Claude Code and Codex, to bring in.
  late final HistoryImportViewModel? _import = () {
    try {
      return HistoryImportViewModel(
        import: context.read(),
        sessions: context.read(),
        conversations: context.read(),
      );
    } on ProviderNotFoundException {
      return null; // Where the app's services are not all given (a test).
    }
  }();

  @override
  void dispose() {
    _import?.dispose();
    super.dispose();
  }

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
            "Deleting a chat in Helmy does not delete a connection's own copy. Those stay in the "
            'folders above until you remove them there.',
            style: t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.5),
          ),
        ),
        const _Heading('What Helmy is running'),
        const _Running(),
        const _Heading('Your conversations'),
        _Row(
          title: 'Export all conversations',
          description: 'Each thread as a Markdown file, in a folder you choose.',
          control: Button(
            size: .sm,
            variant: .outline,
            onPressed: _export,
            child: const Text('Export...'),
          ),
        ),
        if (_import case final importer?) ...[
          const _Heading('Bring in conversations'),
          Text(
            'The conversations you had in Claude Code and Codex on this Mac, by folder. Each '
            'comes in as a chat that goes on where it left off; the originals stay as they are.',
            style: muted,
          ),
          Container(
            decoration: BoxDecoration(
              color: t.colors.card,
              border: Border.all(color: t.colors.border),
              borderRadius: .circular(t.radiusLg),
            ),
            clipBehavior: .antiAlias,
            child: ImportList(vm: importer),
          ),
        ],
        _Heading('What leaves ${Desktop.current.thisComputer}'),
        Text(
          'Each message goes to the company behind the connection that answers it (Anthropic for '
          'Claude Code, OpenAI for Codex), with the files and command output it reads to '
          'answer. With a model on Ollama, nothing leaves. Naming chats and keeping their '
          'summaries runs on the model here; with none, a few lines of each chat go to the '
          'cheapest connection. Of its own, Helmy sends only error reports, while they are on '
          'in General; its chats, settings and logs stay in the folders above.',
          style: t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.5),
        ),
      ],
    );
  }
}

/// The programs Helmy started that are still running, with their CPU and
/// memory, each stoppable; and the logs. Read again every few seconds.
class _Running extends StatefulWidget with _Setting {
  const _Running();

  @override
  State<_Running> createState() => _RunningState();
}

class _RunningState extends State<_Running> {
  List<({int pid, String name, String command, double cpu, int bytes})>? _list;
  Timer? _every;

  DesktopService get _desktop => context.read<DesktopService>();

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _every = Timer.periodic(const Duration(seconds: 3), (_) => unawaited(_read()));
  }

  Future<void> _read() async {
    final list = await _desktop.helmysProcesses();
    if (mounted) setState(() => _list = list);
  }

  @override
  void dispose() {
    _every?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final list = _list;
    return _Block(
      title: list == null
          ? 'Looking...'
          : list.isEmpty
          ? 'Nothing running besides Helmy'
          : '${list.length} running',
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 6,
        children: [
          for (final p
              in list ?? const <({int pid, String name, String command, double cpu, int bytes})>[])
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Tooltip(
                    message: p.command.length > 300
                        ? '${p.command.substring(0, 300)}...'
                        : p.command,
                    child: Text(p.name, maxLines: 1, overflow: .ellipsis, style: t.text.sm),
                  ),
                ),
                Text('${p.cpu.toStringAsFixed(1)}% CPU', style: muted),
                SizedBox(
                  width: 70,
                  child: Text(_size(p.bytes), textAlign: .right, style: muted),
                ),
                Button(
                  variant: .ghost,
                  size: .xs,
                  semanticLabel: 'Stop ${p.name}',
                  onPressed: () async {
                    final sure = await confirm(
                      context,
                      title: 'Stop ${p.name}?',
                      body:
                          'Whatever it was doing for a chat stops; the chat says so and can '
                          'be sent again.',
                      action: 'Stop',
                      destructive: true,
                    );
                    if (sure) {
                      await _desktop.stopProcess(p.pid);
                      await _read();
                    }
                  },
                  child: const Text('Stop'),
                ),
              ],
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Button(
              variant: .outline,
              size: .sm,
              onPressed: () async {
                final dir = await context.read<TurnLog>().folder();
                _desktop.reveal(dir.path);
              },
              child: Text('Show the logs in ${Desktop.current.fileManager}'),
            ),
          ),
        ],
      ),
    );
  }
}
