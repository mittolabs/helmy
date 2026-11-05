part of '../settings_screen.dart';

class _General extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = vm.settings;
    return _Page(
      children: [
        const _Heading('Notifications', first: true),
        _Row(
          title: 'When a chat needs you or finishes',
          description:
              'A notification when a chat in the background finishes or waits for '
              'your approval, and a count on Helmy\'s icon.',
          control: Switch(
            value: s.notify,
            semanticLabel: 'Notifications',
            onChanged: (v) => vm.update(s.copyWith(notify: v)),
          ),
        ),
        if (s.notify) ...[
          _Row(
            title: 'How it tells you',
            control: SizedBox(
              width: 230,
              child: Select<AlertStyle>(
                size: .sm,
                value: s.alertStyle,
                semanticLabel: 'How it tells you',
                options: [for (final a in AlertStyle.values) SelectOption(a, a.label)],
                onChanged: (a) => vm.update(s.copyWith(alertStyle: a)),
              ),
            ),
          ),
          _Row(
            title: 'Notices inside Helmy',
            description:
                'While Helmy is in front, a notice in its corner when another chat finishes '
                'or needs you.',
            control: Switch(
              value: s.inAppNotices,
              semanticLabel: 'Notices inside Helmy',
              onChanged: (v) => vm.update(s.copyWith(inAppNotices: v)),
            ),
          ),
        ],
        const _Heading('Behavior'),
        _Row(
          title: 'Keep chats working when the window closes',
          description:
              'Closing the window hides it and chats keep working. Click Helmy in '
              '${Desktop.current.appBar} to bring it back; Quit (${Desktop.current.keys('⌘Q')}) ends them. Off, '
              'closing the window quits.',
          control: Switch(
            value: s.keepRunning,
            semanticLabel: 'Keep chats working when the window closes',
            onChanged: (v) => vm.update(s.copyWith(keepRunning: v)),
          ),
        ),
        // The Mac's own Quit is held back natively; elsewhere there is none.
        if (Desktop.current == .mac)
          _Row(
            title: 'Quit on a second press while chats work',
            description:
                'Quitting stops every chat at work. While one is, the first '
                '${Desktop.current.keys('⌘Q')} only says so; a second quits.',
            control: Switch(
              value: s.quitTwice,
              semanticLabel: 'Quit on a second press while chats work',
              onChanged: (v) => vm.update(s.copyWith(quitTwice: v)),
            ),
          ),
        _Row(
          title: 'The assistant uses devices',
          description:
              'Simulators, emulators and phones in the Device panel: it opens apps there, taps '
              'through them and reads the screen. Off, it asks you to.',
          control: Switch(
            value: s.agentDevices,
            semanticLabel: 'The assistant uses devices',
            onChanged: (v) => vm.update(s.copyWith(agentDevices: v)),
          ),
        ),
        _Row(
          title: 'Carry on after a restart',
          description:
              'Chats at work when Helmy closed (quit, an update, a crash) pick up where they '
              'stopped when it opens again.',
          control: Switch(
            value: s.carryOnAfterRestart,
            semanticLabel: 'Carry on after a restart',
            onChanged: (v) => vm.update(s.copyWith(carryOnAfterRestart: v)),
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
          title: 'Each thread on its own branch',
          description:
              'In a git repository, each thread works on its own branch in its own copy, '
              'so several can work at once without changing each other\'s files. '
              'Projects can say otherwise.',
          control: Switch(
            value: s.ownCopies,
            semanticLabel: 'Each thread on its own branch',
            onChanged: (v) => vm.update(s.copyWith(ownCopies: v)),
          ),
        ),
        if (Platform.isMacOS) _SnapshotRow(vm: vm),
        _Row(
          title: 'Keep default branches current',
          description:
              "A project's main branch is brought up to date in the background when its "
              'checkout is on it with nothing of its own: no changes, no commits. Never a '
              'merge, never anything of yours touched.',
          control: Switch(
            value: s.keepDefaultCurrent,
            semanticLabel: 'Keep default branches current',
            onChanged: (v) => vm.update(s.copyWith(keepDefaultCurrent: v)),
          ),
        ),
        _Row(
          title: 'Send error reports',
          description: ErrorReports.configured
              ? "When something in Helmy itself goes wrong, what went wrong in its code goes "
                    "to Mittolabs, to be fixed. Never a conversation, a file, or a path in your home."
              : 'This build sends no reports anywhere.',
          // Shown off where this build cannot send: never on and greyed.
          control: Switch(
            value: ErrorReports.configured && s.sendErrors,
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
              : 'Helmy opens when you log in, so chats are there to pick up.',
          control: vm.openAtLogin == null
              ? const SizedBox.shrink()
              : Switch(
                  value: vm.openAtLogin!,
                  semanticLabel: 'Open at login',
                  onChanged: vm.setOpenAtLogin,
                ),
        ),
        _Row(
          title: 'Ask before deleting a chat',
          control: Switch(
            value: s.confirmDelete,
            semanticLabel: 'Ask before deleting a chat',
            onChanged: (v) => vm.update(s.copyWith(confirmDelete: v)),
          ),
        ),
        _Row(
          title: 'Mark chats done on their own',
          description:
              'A chat moves to Done when its pull request merges, or after ${s.settleDays} '
              'day${s.settleDays == 1 ? '' : 's'} untouched. Anything new in it brings it back.',
          control: Row(
            mainAxisSize: .min,
            spacing: 10,
            children: [
              if (s.settleOnItsOwn)
                SizedBox(
                  width: 110,
                  child: Select<int>(
                    size: .sm,
                    value: s.settleDays,
                    semanticLabel: 'Days untouched',
                    options: [
                      for (final d in {1, 2, 3, 5, 7, 14, 30, s.settleDays}.toList()..sort())
                        SelectOption(d, '$d day${d == 1 ? '' : 's'}'),
                    ],
                    onChanged: (d) => vm.update(s.copyWith(settleDays: d)),
                  ),
                ),
              Switch(
                value: s.settleOnItsOwn,
                semanticLabel: 'Mark chats done on their own',
                onChanged: (v) => vm.update(s.copyWith(settleOnItsOwn: v)),
              ),
            ],
          ),
        ),
        if (s.settleOnItsOwn)
          _Row(
            title: 'Keep chats with an open pull request',
            description:
                'A pull request still open means the work is not done: it does not settle.',
            control: Switch(
              value: s.keepWithPr,
              semanticLabel: 'Keep chats with an open pull request',
              onChanged: (v) => vm.update(s.copyWith(keepWithPr: v)),
            ),
          ),
        _Row(
          title: 'Format as you type',
          description:
              'Markdown in the message box shows as it is typed: **bold**, *italic*, '
              '`code`. What is sent is what was typed.',
          control: Switch(
            value: s.formatAsYouType,
            semanticLabel: 'Format as you type',
            onChanged: (v) => vm.update(s.copyWith(formatAsYouType: v)),
          ),
        ),
        _Row(
          title: 'A message sent while a chat works',
          description: s.steerByDefault
              ? 'Goes in now and redirects it. ${Desktop.current.keys('⇧⌘Enter')} has one wait its turn.'
              : 'Waits its turn. ${Desktop.current.keys('⇧⌘Enter')} sends one now, redirecting it.',
          control: _Choice<bool>(
            value: s.steerByDefault,
            label: 'A message sent while a chat works',
            options: const {false: 'Waits', true: 'Redirects'},
            onChanged: (v) => vm.update(s.copyWith(steerByDefault: v)),
          ),
        ),
        _NamingNote(vm: vm),
        const _Heading('New chats'),
        _Row(
          title: 'Permissions',
          description: 'What Helmy may do without asking, until you change it in a chat.',
          control: SizedBox(
            width: 180,
            child: Select<PermissionLevel>(
              size: .sm,
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
              : 'Each new chat opens in the folder you last worked in.',
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
                  size: .sm,
                  value: s.folderMode,
                  semanticLabel: 'Where new chats start',
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
                border: Border.all(
                  color: t.colors.border.withValues(alpha: t.colors.border.a * .7),
                  width: .5,
                ),
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

/// Snapshots with both Shift keys: on or off, and what macOS still has to
/// allow, each with the pane that allows it.
class _SnapshotRow extends StatefulWidget with _Setting {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_SnapshotRow> createState() => _SnapshotRowState();
}

class _SnapshotRowState extends State<_SnapshotRow> {
  SnapshotAccess? _access;

  WindowSnapshots? get _snaps {
    try {
      return context.read<WindowSnapshots>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final a = await _snaps?.access();
    if (mounted) setState(() => _access = a);
  }

  Future<void> _turn(bool on) async {
    final s = widget.vm.settings;
    await widget.vm.update(s.copyWith(snapshotKeys: on));
    if (on) {
      // macOS shows its own prompts; each is asked once, then only its pane grants it.
      await _snaps?.askRecord();
      await _snaps?.askRead();
    }
    await _check();
  }

  /// A snapshot of the first other app's window: a check that macOS lets
  /// it be taken, said in a notice.
  Future<void> _try() async {
    final snaps = _snaps;
    if (snaps == null) return;
    final windows = await snaps.windows();
    final w = windows.where((w) => w.app != 'Helmy').firstOrNull;
    final shot = w == null ? null : await snaps.take(w);
    if (!mounted) return;
    if (shot != null) {
      final s = widget.vm.settings;
      if (s.snapshotSound.isNotEmpty) unawaited(snaps.sound(s.snapshotSound));
    }
    showToast(
      context,
      title: shot != null
          ? 'Snapshot of ${shot.window.app} taken'
          : w == null
          ? 'No other window to snapshot'
          : "macOS didn't let Helmy see that window",
      description: shot != null
          ? (shot.text != null
                ? 'Its text came too.'
                : 'Its picture only: Accessibility would give its text.')
          : w == null
          ? 'Open another app\'s window and try again.'
          : 'Allow Helmy under Screen Recording in Privacy & Security.',
      type: shot != null ? .success : .error,
    );
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final on = widget.vm.settings.snapshotKeys;
    final a = _access;
    Widget need(String what, String pane) => Padding(
      padding: const .only(top: 6),
      child: Row(
        spacing: 8,
        children: [
          AshlarIcon(AshlarIconsRoundedStroke.circleAlert, size: 14, color: t.colors.destructive),
          Expanded(
            child: Text(what, style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
          ),
          Button(
            variant: .outline,
            size: .xs,
            onPressed: () async {
              await widget.vm.fileActions.open(pane);
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        _Row(
          title: 'Snapshots with both Shift keys',
          description:
              'Press both Shift keys in any app: its window goes into the message you are writing, '
              'with the text in it, so Helmy can read the window and not only look at it.',
          control: Switch(
            value: on,
            semanticLabel: 'Snapshots with both Shift keys',
            onChanged: _turn,
          ),
        ),
        if (on)
          _Row(
            title: 'When a snapshot is taken',
            description:
                'A sound and a flash say it went in. Try it takes a snapshot of the '
                'window behind Settings, to check everything is allowed.',
            control: SizedBox(
              width: 250,
              child: Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 6,

                spacing: 8,
                children: [
                  Button(
                    variant: .outline,
                    size: .sm,
                    onPressed: _try,
                    child: const Text('Try it'),
                  ),
                  SizedBox(
                    width: 100,
                    child: Select<String>(
                      size: .sm,
                      value: widget.vm.settings.snapshotSound,
                      semanticLabel: 'Snapshot sound',
                      options: const [
                        SelectOption('Pop', 'Pop'),
                        SelectOption('Tink', 'Tink'),
                        SelectOption('', 'No sound'),
                      ],
                      onChanged: (v) {
                        widget.vm.update(widget.vm.settings.copyWith(snapshotSound: v));
                        if (v.isNotEmpty) unawaited(_snaps?.sound(v));
                      },
                    ),
                  ),
                  _SnapKey(vm: widget.vm),
                  Tooltip(
                    message: 'Flash',
                    child: Switch(
                      value: widget.vm.settings.snapshotFlash,
                      semanticLabel: 'Snapshot flash',
                      onChanged: (v) =>
                          widget.vm.update(widget.vm.settings.copyWith(snapshotFlash: v)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (on && a != null && (!a.record || !a.read))
          Padding(
            padding: const .fromLTRB(18, 0, 18, 14),
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                if (!a.record)
                  need(
                    'Screen Recording: macOS must allow Helmy to see other apps\' windows.',
                    screenRecordingPane,
                  ),
                if (!a.read)
                  need(
                    'Accessibility: for both Shift keys in other apps, and the text in windows.',
                    accessibilityPane,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// What the person wants of chats' names, in their words, added to how
/// Helmy names them. Saved as it is typed.
class _NamingNote extends StatefulWidget with _Setting {
  const _NamingNote({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_NamingNote> createState() => _NamingNoteState();
}

class _NamingNoteState extends State<_NamingNote> {
  late final _text = TextEditingController(text: widget.vm.settings.namingNote);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Block(
    title: 'How chats are named',
    child: Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        Text(
          'Anything you want of the names Helmy gives chats, in your own words: '
          '"Short, no articles", "In Spanish", "Start with the client\'s name".',
          style: AshlarTheme.of(context).text.xs
              .copyWith(color: AshlarTheme.of(context).colors.mutedForeground),
        ),
        Textarea(
          controller: _text,
          minLines: 2,
          maxLines: 4,
          placeholder: 'Nothing: as Helmy names them',
          onChanged: (v) => widget.vm.update(widget.vm.settings.copyWith(namingNote: v)),
        ),
      ],
    ),
  );
}

/// Another shortcut for a snapshot, beside both Shift keys: pressed to
/// record it, cleared with its x.
class _SnapKey extends StatefulWidget {
  const _SnapKey({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_SnapKey> createState() => _SnapKeyState();
}

class _SnapKeyState extends State<_SnapKey> {
  final _focus = FocusNode();
  bool _recording = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (!_recording || e is! KeyDownEvent) return .ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _recording = false);
      return .handled;
    }
    final b = KeyBinding.of(e);
    if (b == null) return .handled;
    widget.vm.update(widget.vm.settings.copyWith(snapshotKey: b.saved));
    setState(() => _recording = false);
    return .handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final saved = widget.vm.settings.snapshotKey;
    final b = saved.isEmpty ? null : KeyBinding.parse(saved);
    return Row(
      mainAxisSize: .min,
      spacing: 2,
      children: [
        Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          onFocusChange: (on) {
            if (!on && _recording) setState(() => _recording = false);
          },
          child: Tooltip(
            message: 'Another shortcut for a snapshot, beside both Shift keys',
            child: Button(
              variant: .outline,
              size: .sm,
              semanticLabel: 'Snapshot shortcut',
              onPressed: () {
                setState(() => _recording = true);
                _focus.requestFocus();
              },
              child: Text(
                _recording ? 'Press keys' : b?.label ?? 'Add keys',
                style: t.text.xs.copyWith(fontFamily: 'monospace', fontFamilyFallback: monoFonts),
              ),
            ),
          ),
        ),
        if (b != null)
          Button(
            variant: .ghost,
            size: .iconXs,
            semanticLabel: 'No other shortcut',
            onPressed: () => widget.vm.update(widget.vm.settings.copyWith(snapshotKey: '')),
            child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 12),
          ),
      ],
    );
  }
}
