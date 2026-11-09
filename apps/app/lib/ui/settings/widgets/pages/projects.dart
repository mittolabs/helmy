part of '../settings_screen.dart';

/// Each repository sessions work in, with what is set for it alone.
class _Projects extends StatelessWidget {
  const _Projects({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final s = vm.settings;
    return FutureBuilder(
      future: vm.projects(),
      builder: (context, snap) {
        final repos = snap.data ?? const <String>[];
        return _Page(
          children: [
            const _Heading('Every project', first: true),
            _Row(
              title: 'Commits and pull requests',
              description: switch (s.commitStyle) {
                'conventional' =>
                  'type(scope): subject, in lower case, as Conventional Commits has it.',
                'custom' => 'As you describe below.',
                _ => "Each repository's own way, as its history and files show.",
              },
              control: SizedBox(
                width: 200,
                child: Select<String>(
                  size: .sm,
                  value: s.commitStyle,
                  semanticLabel: 'Commits and pull requests',
                  options: const [
                    SelectOption('repository', "The repository's own"),
                    SelectOption('conventional', 'Conventional Commits'),
                    SelectOption('custom', 'Your own words'),
                  ],
                  onChanged: (v) => vm.update(s.copyWith(commitStyle: v)),
                ),
              ),
            ),
            if (s.commitStyle == 'custom') _CommitNote(vm: vm),
            const _Heading("Threads' own copies"),
            _Row(
              title: 'Branch names',
              description: s.copySemantic
                  ? 'By the kind of change: fix/the-login-3f9a, feat/dark-mode-1c2d.'
                  : 'After "${s.copyPrefix}": ${s.copyPrefix}the-login-3f9a.',
              control: Row(
                mainAxisSize: .min,
                spacing: 8,
                children: [
                  if (!s.copySemantic) _PrefixBox(vm: vm),
                  SizedBox(
                    width: 170,
                    child: Select<bool>(
                      size: .sm,
                      value: s.copySemantic,
                      semanticLabel: 'Branch names',
                      options: const [
                        SelectOption(true, 'Kind of change'),
                        SelectOption(false, 'A prefix'),
                      ],
                      onChanged: (v) => vm.update(s.copyWith(copySemantic: v)),
                    ),
                  ),
                ],
              ),
            ),
            _Row(
              title: 'Start copies from',
              description: s.copyFromRemote
                  ? "The remote's default branch, fetched first: always the newest."
                  : 'Where the checkout is: its unpushed work too, else the newest from its remote.',
              control: SizedBox(
                width: 200,
                child: Select<bool>(
                  size: .sm,
                  value: s.copyFromRemote,
                  semanticLabel: 'Start copies from',
                  options: const [
                    SelectOption(false, 'Where the checkout is'),
                    SelectOption(true, "The remote's default"),
                  ],
                  onChanged: (v) => vm.update(s.copyWith(copyFromRemote: v)),
                ),
              ),
            ),
            _Row(
              title: 'Where copies are kept',
              description: tildePath(s.copyFolder ?? '$homeDir/.helmy/worktrees'),
              control: Row(
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  if (s.copyFolder != null)
                    Button(
                      variant: .ghost,
                      size: .sm,
                      onPressed: () => vm.update(s.copyWith(copyFolder: '')),
                      child: const Text('Usual place'),
                    ),
                  Button(
                    variant: .outline,
                    size: .sm,
                    onPressed: () async {
                      final dir = await getDirectoryPath(
                        initialDirectory: s.copyFolder ?? homeDir,
                        confirmButtonText: 'Keep copies here',
                      );
                      if (dir != null) await vm.update(s.copyWith(copyFolder: dir));
                    },
                    child: const Text('Choose...'),
                  ),
                ],
              ),
            ),
            _Row(
              title: 'Tidy away copies of settled chats',
              description:
                  'Copies go when their chat is archived or its branch merged. On, they go when '
                  'the chat settles too. Never one with work not yet committed; branches stay.',
              control: Row(
                mainAxisSize: .min,
                spacing: 10,
                children: [
                  Button(
                    variant: .outline,
                    size: .sm,
                    onPressed: () async {
                      final list = context.read<SidebarViewModel?>();
                      final done = await list?.tidyNow() ?? const <String>[];
                      if (!context.mounted) return;
                      showToast(
                        context,
                        title: done.isEmpty ? 'Nothing to tidy' : 'Tidied ${done.length}',
                        description: done.isEmpty ? null : done.take(4).join('\n'),
                      );
                    },
                    child: const Text('Tidy now'),
                  ),
                  Switch(
                    value: s.tidySettled,
                    semanticLabel: 'Tidy away copies of settled chats',
                    onChanged: (v) => vm.update(s.copyWith(tidySettled: v)),
                  ),
                ],
              ),
            ),
            const _Heading('Each project'),
            Text(
              'Every git repository your chats have worked in. What is set here is for '
              'that project alone; "As everywhere" follows General.',
              style: t.text.sm.copyWith(color: t.colors.mutedForeground),
            ),
            if (snap.connectionState != .done)
              const Padding(
                padding: .all(16),
                child: Center(child: Spinner(size: 16)),
              )
            else if (repos.isEmpty)
              Padding(
                padding: const .symmetric(vertical: 16),
                child: Text(
                  'None yet: start a chat in a git repository and it shows here.',
                  style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                ),
              ),
            for (final repo in repos) ...[
              _Heading(folderName(repo)),
              Padding(
                padding: const .only(bottom: 10),
                child: Text(
                  tildePath(repo),
                  style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                ),
              ),
              _Row(
                title: 'Each thread on its own branch',
                description: 'Its own branch and copy, so threads here do not collide.',
                control: _Choice<bool?>(
                  value: s.project(repo).ownCopies,
                  label: 'Each thread on its own branch in ${folderName(repo)}',
                  options: {
                    null: 'As everywhere (${s.ownCopies ? 'on' : 'off'})',
                    true: 'On',
                    false: 'Off',
                  },
                  onChanged: (v) => vm.setProject(repo, ownCopies: v, clearOwn: v == null),
                ),
              ),
              _Row(
                title: 'Icon and pin',
                description:
                    'An emoji it goes by in the list, and pinned, its chats first when the list '
                    'is grouped by folder.',
                control: Row(
                  mainAxisSize: .min,
                  spacing: 8,
                  children: [
                    _IconBox(vm: vm, repo: repo),
                    Tooltip(
                      message: 'Pinned',
                      child: Switch(
                        value: s.project(repo).pinned,
                        semanticLabel: 'Pin ${folderName(repo)}',
                        onChanged: (v) => vm.setProject(repo, pinned: v),
                      ),
                    ),
                  ],
                ),
              ),
              _Row(
                title: "The assistant's browser",
                description: 'Opening and using web pages in the Preview panel, in chats here.',
                control: Switch(
                  value: s.project(repo).browser ?? true,
                  semanticLabel: "The assistant's browser in ${folderName(repo)}",
                  onChanged: (v) => vm.setProject(repo, browser: v),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// How commits and pull requests are written, in the user's words.
class _CommitNote extends StatefulWidget with _Setting {
  const _CommitNote({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_CommitNote> createState() => _CommitNoteState();
}

class _CommitNoteState extends State<_CommitNote> {
  late final _text = TextEditingController(text: widget.vm.settings.commitNote);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Block(
    title: 'In your words',
    child: Textarea(
      controller: _text,
      minLines: 2,
      maxLines: 5,
      placeholder: 'Short subjects in the imperative; a body that says why.',
      onChanged: (v) => widget.vm.update(widget.vm.settings.copyWith(commitNote: v)),
    ),
  );
}

/// The prefix before branch names, saved as typed.
class _PrefixBox extends StatefulWidget {
  const _PrefixBox({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_PrefixBox> createState() => _PrefixBoxState();
}

class _PrefixBoxState extends State<_PrefixBox> {
  late final _text = TextEditingController(text: widget.vm.settings.copyPrefix);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 110,
    child: Input(
      controller: _text,
      size: .sm,
      semanticLabel: 'Branch prefix',
      placeholder: 'helmy/',
      onChanged: (v) => widget.vm.update(widget.vm.settings.copyWith(copyPrefix: v.trim())),
    ),
  );
}

/// A project's emoji, saved as typed: one character's worth.
class _IconBox extends StatefulWidget {
  const _IconBox({required this.vm, required this.repo});
  final SettingsViewModel vm;
  final String repo;

  @override
  State<_IconBox> createState() => _IconBoxState();
}

class _IconBoxState extends State<_IconBox> {
  late final _text = TextEditingController(text: widget.vm.settings.project(widget.repo).icon);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 56,
    child: Input(
      controller: _text,
      size: .sm,
      placeholder: '🚀',
      semanticLabel: 'Icon for ${folderName(widget.repo)}',
      onChanged: (v) {
        final chars = v.trim().characters;
        widget.vm.setProject(widget.repo, icon: chars.isEmpty ? '' : chars.first);
      },
    ),
  );
}
