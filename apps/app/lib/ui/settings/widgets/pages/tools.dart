part of '../settings_screen.dart';

/// What Helmy can do beyond talking, as Helmy's: its skills, the accounts it
/// reaches, its own tools and the tool servers added to it. One list each,
/// whichever connection answers a message; none of it named by connection.
class _Tools extends StatefulWidget {
  const new({super.key, required this.vm, required this.skills});
  final SettingsViewModel vm;

  /// Skills, or the tools: the accounts Helmy reaches, its own tools and the
  /// tool servers added to it.
  final bool skills;

  @override
  State<_Tools> createState() => _ToolsState();
}

/// Helmy's own tools, served to every connection (HelmyTools): what each
/// lets it do, in the person's words.
const _ownTools = [
  ('Vault', 'Runs what needs your keys and passwords, without the assistant seeing them.'),
  ('Your chats', 'Starts other chats, sends them messages and reads what they did.'),
  ('Apps in the chat', 'Makes small apps and games that run right in the conversation.'),
  ('Preview', 'Opens pages in the Preview panel, and reads and uses them.'),
  ('Phones and simulators', 'Sees and uses a simulator or emulator in the Device panel.'),
  ('Videos', 'Watches a video and says what happens in it.'),
  ('Links', 'Opens a link in your browser.'),
];

class _ToolsState extends State<_Tools> {
  @override
  void initState() {
    super.initState();
    // After this frame: with nothing to ask (no connection online), loading
    // finishes at once, and would tell the page while it is being built.
    if (!widget.vm.toolsLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.vm.loadTools());
    }
    if (widget.skills) WidgetsBinding.instance.addPostFrameCallback((_) => _lookOnComputer());
  }

  /// Skills kept on this computer for every project that Helmy does not
  /// have yet; null until looked for.
  List<Skill>? _onComputer;

  Future<void> _lookOnComputer() async {
    final SkillStore store;
    try {
      store = context.read<SkillStore>();
    } on ProviderNotFoundException {
      return;
    }
    final found = await store.onThisComputer(homeDir);
    if (mounted) setState(() => _onComputer = found);
  }

  Future<void> _addFromComputer(SkillStore store) async {
    final n = await store.addAll(_onComputer ?? const []);
    await _lookOnComputer();
    if (mounted) _added(n);
  }

  void _added(int n) => showToast(
    context,
    title: n == 1 ? 'Added a skill' : 'Added $n skills',
    description: 'Every chat has them, however Helmy answers.',
  );

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final SkillStore store;
    try {
      store = context.watch<SkillStore>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final found = vm.skillsFound(store.names);
    final accounts = vm.accounts;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (widget.skills) ...[
          const _Heading('Skills', first: true),
          _Row(
            title: "Helmy's skills",
            description:
                'Instructions for a kind of task, which Helmy follows whenever it fits, or when '
                'you type / and its name. Every chat has them, however Helmy answers.',
            control: Row(
              mainAxisSize: .min,
              spacing: 4,
              children: [
                Button(
                  variant: .ghost,
                  size: .sm,
                  onPressed: () => unawaited(_addFolder(context, store)),
                  child: const Text('Add from a folder'),
                ),
                Button(
                  variant: .outline,
                  size: .sm,
                  leading: const AshlarIcon(AshlarIconsRoundedStroke.plus, size: 14),
                  onPressed: () => unawaited(
                    showAshlarDialog<void>(
                      context: context,
                      builder: (_) => _SkillDialog(store: store),
                    ),
                  ),
                  child: const Text('New skill'),
                ),
              ],
            ),
          ),
          if (_onComputer case final local? when local.isNotEmpty)
            _Row(
              title: local.length == 1
                  ? 'A skill on this computer'
                  : '${local.length} skills on this computer',
              description:
                  '${local.take(4).map((s) => '/${s.name}').join(', ')}${local.length > 4 ? ' and ${local.length - 4} more' : ''}. '
                  'Added to Helmy, every chat has them, not only some.',
              control: Button(
                variant: .outline,
                size: .sm,
                onPressed: () => unawaited(_addFromComputer(store)),
                child: Text(local.length == 1 ? 'Add it' : 'Add all'),
              ),
            ),
          if (store.skills.isEmpty)
            const _Row(
              title: 'None yet',
              description:
                  'Write one, or add a folder with a SKILL.md, the format skills are shared in.',
              control: SizedBox.shrink(),
            ),
          for (final s in store.skills)
            _Row(
              title: '/${s.name}',
              description: s.description,
              control: Row(
                mainAxisSize: .min,
                spacing: 4,
                children: [
                  Button(
                    variant: .ghost,
                    size: .sm,
                    onPressed: () => unawaited(context.read<DesktopService>().reveal(s.folder)),
                    child: const Text('Show'),
                  ),
                  Button(
                    variant: .ghost,
                    size: .sm,
                    onPressed: () async {
                      final sure = await confirm(
                        context,
                        title: 'Remove /${s.name}?',
                        body: 'Its folder is deleted, and no chat has it after this.',
                        action: 'Remove',
                        destructive: true,
                      );
                      if (sure) await store.remove(s.name);
                    },
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
          if (vm.toolsLoaded && found.isNotEmpty) ...[
            _Heading('Also there (${found.length})'),
            Padding(
              padding: const .symmetric(vertical: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in found)
                    Tooltip(
                      message: c.description.isEmpty ? c.name : withoutNames(c.description),
                      child: Container(
                        padding: const .symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          border: Border.all(color: t.colors.border),
                          borderRadius: .circular(t.radiusMd),
                        ),
                        child: Text(
                          '/${c.name}',
                          style: t.text.xs.copyWith(
                            fontFamily: 'monospace',
                            fontFamilyFallback: monoFonts,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
        if (!widget.skills) ...[
          const _Heading('Accounts', first: true),
          if (!vm.toolsLoaded)
            const Padding(padding: .all(8), child: Spinner(size: 14))
          else if (accounts.isEmpty)
            const _Row(
              title: 'None yet',
              description: 'Gmail, Calendar, Slack and others show here once they are connected.',
              control: SizedBox.shrink(),
            )
          else
            for (final a in accounts)
              _Row(
                title: a.name,
                control: Text(switch (a.status) {
                  'connected' => 'Connected',
                  'needs-auth' => 'Needs sign-in',
                  'pending' => 'Connecting',
                  'failed' => 'Not working',
                  final other => other,
                }, style: muted),
              ),
          const _Heading("Helmy's tools"),
          for (final (name, what) in _ownTools)
            _Row(title: name, description: what, control: const SizedBox.shrink()),
          for (final s in vm.settings.toolServers)
            _Row(
              title: s.name,
              description: s.url ?? [s.command!, ...s.args].join(' '),
              control: Button(
                variant: .ghost,
                size: .sm,
                onPressed: () async {
                  final sure = await confirm(
                    context,
                    title: 'Remove ${s.name}?',
                    body: 'New chats stop getting its tools.',
                    action: 'Remove',
                    destructive: true,
                  );
                  if (sure) await vm.removeToolServer(s.name);
                },
                child: const Text('Remove'),
              ),
            ),
          _Row(
            title: 'Add a tool server',
            description:
                'An MCP server, by its address or the command that starts it. Helmy gives its '
                'tools to every chat.',
            control: Button(
              variant: .outline,
              size: .sm,
              leading: const AshlarIcon(AshlarIconsRoundedStroke.plus, size: 14),
              onPressed: () => unawaited(
                showAshlarDialog<void>(
                  context: context,
                  builder: (_) => _ServerDialog(vm: vm),
                ),
              ),
              child: const Text('Add'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _addFolder(BuildContext context, SkillStore store) async {
    // A skill's own folder, or one holding several (skills/, .agents/).
    final dir = await getDirectoryPath(confirmButtonText: 'Add skills');
    if (dir == null) return;
    final found = await store.skillsIn(dir);
    final added = found.isEmpty ? 0 : await store.addAll(found);
    if (!context.mounted) return;
    if (added > 0) {
      _added(added);
      unawaited(_lookOnComputer());
    } else {
      await confirm(
        context,
        title: 'No skill in that folder',
        body:
            'A skill is a folder with a SKILL.md in it, which starts with its name and '
            'description. Choose one, or a folder of them.',
        action: 'OK',
      );
    }
  }
}

/// Writes a new skill: its name, when to use it, and what to do.
class _SkillDialog extends StatefulWidget {
  const new({required this.store});
  final SkillStore store;

  @override
  State<_SkillDialog> createState() => _SkillDialogState();
}

class _SkillDialogState extends State<_SkillDialog> {
  final _name = TextEditingController();
  final _when = TextEditingController();
  final _what = TextEditingController();
  String? _trouble;

  @override
  void dispose() {
    _name.dispose();
    _when.dispose();
    _what.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (SkillStore.slug(_name.text).isEmpty) {
      return setState(() => _trouble = 'Give it a name, such as release-notes.');
    }
    if (_when.text.trim().isEmpty || _what.text.trim().isEmpty) {
      return setState(() => _trouble = 'Say when to use it, and what to do.');
    }
    await widget.store.create(name: _name.text, description: _when.text, instructions: _what.text);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return HelmyDialog(
      title: 'New skill',
      icon: AshlarIconsRoundedStroke.puzzle,
      body:
          'Every chat gets it. Helmy uses it when the task fits, or when you type / and its name.',
      content: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: 10,
        children: [
          Input(
            controller: _name,
            size: .sm,
            autofocus: true,
            placeholder: 'Its name: release-notes',
            semanticLabel: 'Name',
          ),
          Input(
            controller: _when,
            size: .sm,
            placeholder: 'When to use it: writing release notes from merged work',
            semanticLabel: 'When to use it',
          ),
          Textarea(
            controller: _what,
            minLines: 5,
            maxLines: 12,
            placeholder: 'What to do, step by step',
            semanticLabel: 'What to do',
          ),
          if (_trouble case final why?)
            Text(why, style: t.text.xs.copyWith(color: t.colors.destructive)),
        ],
      ),
      actions: [
        Button(
          variant: .outline,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Button(onPressed: () => unawaited(_save()), child: const Text('Add')),
      ],
    );
  }
}

/// Adds a tool server: a name, and its address or the command that starts it.
class _ServerDialog extends StatefulWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  final _name = TextEditingController();
  final _where = TextEditingController();
  String? _trouble;

  @override
  void dispose() {
    _name.dispose();
    _where.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = SkillStore.slug(_name.text).replaceAll('-', '_');
    final where = _where.text.trim();
    if (name.isEmpty || name == 'helmy') {
      return setState(() => _trouble = 'Give it a name, such as github.');
    }
    if (where.isEmpty) {
      return setState(() => _trouble = 'Its address (https://…) or the command that starts it.');
    }
    final url = RegExp(r'^https?://').hasMatch(where);
    final words = where.split(RegExp(r'\s+'));
    await widget.vm.addToolServer(
      url
          ? ToolServer(name: name, url: where)
          : ToolServer(name: name, command: words.first, args: words.skip(1).toList()),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return HelmyDialog(
      title: 'Add a tool server',
      icon: AshlarIconsRoundedStroke.puzzle,
      body: 'Its tools go to every new chat.',
      content: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: 10,
        children: [
          Input(
            controller: _name,
            size: .sm,
            autofocus: true,
            placeholder: 'Its name: github',
            semanticLabel: 'Name',
          ),
          Input(
            controller: _where,
            size: .sm,
            placeholder: 'https://… or npx -y @modelcontextprotocol/server-github',
            semanticLabel: 'Address or command',
            onSubmitted: (_) => unawaited(_save()),
          ),
          if (_trouble case final why?)
            Text(why, style: t.text.xs.copyWith(color: t.colors.destructive)),
        ],
      ),
      actions: [
        Button(
          variant: .outline,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Button(onPressed: () => unawaited(_save()), child: const Text('Add')),
      ],
    );
  }
}
