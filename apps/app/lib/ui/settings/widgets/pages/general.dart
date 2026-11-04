part of '../settings_screen.dart';

class _General extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = vm.settings;
    return _Page(
      children: [
        const _Heading('Appearance', first: true),
        _Row(
          title: 'Theme',
          control: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final choice in ThemeChoice.values)
                _ThemeCard(
                  choice: choice,
                  selected: s.theme == choice,
                  onPressed: () => vm.update(s.copyWith(theme: choice)),
                ),
            ],
          ),
        ),
        _Row(
          title: 'Text size',
          control: _Choice<TextSize>(
            value: s.textSize,
            label: 'Text size',
            options: {for (final v in TextSize.values) v: v.label},
            onChanged: (v) => vm.update(s.copyWith(textSize: v)),
          ),
        ),
        _Row(
          title: 'Conversation width',
          control: _Choice<Width>(
            value: s.width,
            label: 'Conversation width',
            options: {for (final v in Width.values) v: v.label},
            onChanged: (v) => vm.update(s.copyWith(width: v)),
          ),
        ),
        _Row(
          title: 'Wrap long code blocks',
          description: 'Long lines in code wrap onto the next line, rather than scroll sideways.',
          control: Switch(
            value: s.wrapCode,
            semanticLabel: 'Wrap long code blocks',
            onChanged: (v) => vm.update(s.copyWith(wrapCode: v)),
          ),
        ),
        const _Heading('Notifications'),
        _Row(
          title: 'When a session needs you or finishes',
          description:
              'A notification when a session in the background finishes or waits for '
              'your approval, and a count on Helmy\'s icon.',
          control: Switch(
            value: s.notify,
            semanticLabel: 'Notifications',
            onChanged: (v) => vm.update(s.copyWith(notify: v)),
          ),
        ),
        const _Heading('Behavior'),
        _Row(
          title: 'Keep sessions running when the window closes',
          description:
              'Closing the window hides it and sessions keep working. Click Helmy in '
              '${Desktop.current.appBar} to bring it back; Quit (${Desktop.current.keys('⌘Q')}) ends them. Off, '
              'closing the window quits.',
          control: Switch(
            value: s.keepRunning,
            semanticLabel: 'Keep sessions running when the window closes',
            onChanged: (v) => vm.update(s.copyWith(keepRunning: v)),
          ),
        ),
        _Row(
          title: 'Send with',
          description: s.sendWithEnter
              ? 'Enter sends; Shift+Enter starts a new line.'
              : '${Desktop.current.keys('⌘Enter')} sends; Enter starts a new line, for writing long messages.',
          control: _Choice<bool>(
            value: s.sendWithEnter,
            label: 'Send with',
            options: {true: 'Enter', false: Desktop.current.keys('⌘Enter')},
            onChanged: (v) => vm.update(s.copyWith(sendWithEnter: v)),
          ),
        ),
        _Row(
          title: 'Each session on its own branch',
          description:
              'In a git repository, each session works on its own branch in its own copy, '
              'so several can work at once without changing each other\'s files. '
              'Projects can say otherwise.',
          control: Switch(
            value: s.ownCopies,
            semanticLabel: 'Each session on its own branch',
            onChanged: (v) => vm.update(s.copyWith(ownCopies: v)),
          ),
        ),
        _Row(
          title: 'Send error reports',
          description: ErrorReports.configured
              ? "When something in Helmy itself goes wrong, what went wrong in its code goes "
                    "to Mittolabs, to be fixed. Never a conversation, a file, or a path in your home."
              : 'This build sends no reports anywhere.',
          control: Switch(
            value: s.sendErrors,
            semanticLabel: 'Send error reports',
            onChanged: ErrorReports.configured ? (v) => vm.update(s.copyWith(sendErrors: v)) : null,
          ),
        ),
        _Row(
          title: 'Show steps open',
          description: 'Each step starts open, showing what went in and came out.',
          control: Switch(
            value: s.stepsOpen,
            semanticLabel: 'Show steps open',
            onChanged: (v) => vm.update(s.copyWith(stepsOpen: v)),
          ),
        ),
        _Row(
          title: 'Open at login',
          description: vm.openAtLogin == null
              ? 'This system cannot be asked.'
              : 'Helmy opens when you log in, so sessions are there to pick up.',
          control: vm.openAtLogin == null
              ? const SizedBox.shrink()
              : Switch(
                  value: vm.openAtLogin!,
                  semanticLabel: 'Open at login',
                  onChanged: vm.setOpenAtLogin,
                ),
        ),
        _Row(
          title: 'Ask before deleting a session',
          control: Switch(
            value: s.confirmDelete,
            semanticLabel: 'Ask before deleting a session',
            onChanged: (v) => vm.update(s.copyWith(confirmDelete: v)),
          ),
        ),
        const _Heading('New sessions'),
        _Row(
          title: 'Permissions',
          description: 'What the agent may do without asking, until you change it in a session.',
          control: SizedBox(
            width: 180,
            child: Select<PermissionLevel>(
              value: s.defaultLevel,
              semanticLabel: 'Default permissions',
              options: [for (final l in PermissionLevel.values) SelectOption(l, l.label)],
              onChanged: (l) => vm.update(s.copyWith(defaultLevel: l)),
            ),
          ),
        ),
        _Row(
          title: 'Start in',
          description: s.folderMode == .fixed
              ? (s.fixedFolder == null ? 'No folder chosen yet.' : tildePath(s.fixedFolder!))
              : 'Each new session opens in the folder you last worked in.',
          control: Row(
            spacing: 8,
            children: [
              if (s.folderMode == .fixed)
                Button(
                  variant: .outline,
                  size: .sm,
                  onPressed: () async {
                    final dir = await getDirectoryPath(
                      initialDirectory: s.fixedFolder,
                      confirmButtonText: 'Use this folder',
                    );
                    if (dir != null) await vm.update(s.copyWith(fixedFolder: dir));
                  },
                  child: const Text('Choose...'),
                ),
              SizedBox(
                width: 180,
                child: Select<FolderMode>(
                  value: s.folderMode,
                  semanticLabel: 'Where new sessions start',
                  options: const [
                    SelectOption(FolderMode.last, 'Last folder'),
                    SelectOption(FolderMode.fixed, 'The same folder'),
                  ],
                  onChanged: (m) => vm.update(s.copyWith(folderMode: m)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A theme as a small picture of the app in it: light, dark, or half of each
/// for following the system.
class _ThemeCard extends StatelessWidget {
  const new({required this.choice, required this.selected, required this.onPressed});
  final ThemeChoice choice;
  final bool selected;
  final VoidCallback onPressed;

  static Widget _window(AshlarColors c) => Container(
    color: c.background,
    padding: const .all(6),
    child: Row(
      crossAxisAlignment: .stretch,
      spacing: 5,
      children: [
        Container(
          width: 18,
          decoration: BoxDecoration(color: c.muted, borderRadius: .circular(3)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 4,
            children: [
              for (final w in const [.9, .6, .75])
                FractionallySizedBox(
                  widthFactor: w,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.mutedForeground.withValues(alpha: .5),
                      borderRadius: .circular(2),
                    ),
                  ),
                ),
              const Spacer(),
              Container(
                height: 9,
                decoration: BoxDecoration(
                  border: Border.all(color: c.border),
                  borderRadius: .circular(5),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final light = _window(appTheme.colors);
    final dark = _window(appDarkTheme.colors);
    final label = switch (choice) {
      .light => 'Light',
      .dark => 'Dark',
      .system => 'System',
    };
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: '$label theme',
      builder: (context, state) => Column(
        spacing: 6,
        children: [
          // The ring sits a few points outside the picture, the way a
          // selection is drawn on the Mac, rather than as a frame on it.
          AnimatedContainer(
            duration: t.duration,
            padding: const .all(3),
            decoration: BoxDecoration(
              borderRadius: .circular(t.radiusLg + 4),
              border: Border.all(
                color: selected
                    ? t.colors.foreground.withValues(alpha: .9)
                    : state.hovered
                    ? t.colors.border
                    : const Color(0x00000000),
                width: 1.5,
              ),
            ),
            child: Container(
              width: 96,
              height: 64,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: .circular(t.radiusLg),
                border: Border.all(color: t.colors.border.withValues(alpha: .7), width: .5),
              ),
              child: switch (choice) {
                .light => light,
                .dark => dark,
                .system => Row(
                  crossAxisAlignment: .stretch,
                  children: [
                    Expanded(
                      child: ClipRect(
                        child: OverflowBox(maxWidth: 96, alignment: .centerLeft, child: dark),
                      ),
                    ),
                    Expanded(
                      child: ClipRect(
                        child: OverflowBox(maxWidth: 96, alignment: .centerRight, child: light),
                      ),
                    ),
                  ],
                ),
              },
            ),
          ),
          Text(
            label,
            style: t.text.xs.copyWith(
              color: selected ? t.colors.foreground : t.colors.mutedForeground,
              fontWeight: selected ? .w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}
