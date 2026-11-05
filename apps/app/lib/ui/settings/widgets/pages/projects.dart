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
                title: 'What Helmy may do without asking',
                description: 'For new chats here.',
                control: _Choice<PermissionLevel?>(
                  value: s.project(repo).level,
                  label: 'Permission level in ${folderName(repo)}',
                  options: {
                    null: 'As everywhere (${s.defaultLevel.label})',
                    for (final l in PermissionLevel.values) l: l.label,
                  },
                  onChanged: (v) => vm.setProject(repo, level: v, clearLevel: v == null),
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
