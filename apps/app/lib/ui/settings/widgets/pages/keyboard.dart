part of '../settings_screen.dart';

class _Keyboard extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  static const _keys = [
    ('⌘1 to ⌘9', 'Open the chats in the order the list shows them'),
    ('⌘Z', 'Undo marking done, archiving or snoozing a chat (outside a text box)'),
    ('Enter', 'Send (or ⌘Enter, as set in General)'),
    ('Shift+Enter', 'New line in a message'),
    ('⇧⌘Enter', 'While Helmy works: send now, redirecting it'),
    ('⌘Enter', 'Send, and start another chat while it works (⌥⌘Enter when ⌘Enter sends)'),
    ('/', 'Commands and skills, at the start of a message'),
    ('@', "Pick a file from the thread's folder"),
    ('Tab', 'Take the first suggestion'),
    ('↑ / ↓', 'Your earlier messages, from an empty box'),
    ('⌘V', 'Paste a picture as an attachment, or text'),
    ('!', 'Run a command in the folder yourself, at the start of a message'),
    ('Esc', 'Close a dialog or the suggestions'),
    ('⌘Q', 'Quit, stopping every chat at work'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return _Page(
      children: [
        const _Heading('Shortcuts', first: true),
        for (final c in AppCommand.values) _KeyRow(vm: vm, command: c),
        const _Heading('Always these'),
        for (final (key, what) in _keys)
          _Row(
            title: Desktop.current.keys(what),
            control: Container(
              padding: const .symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: t.colors.muted,
                borderRadius: .circular(t.radiusMd),
                border: Border.all(color: t.colors.border),
              ),
              child: Text(
                Desktop.current.keys(key),
                style: t.text.xs.copyWith(fontFamily: 'monospace', fontFamilyFallback: monoFonts),
              ),
            ),
          ),
      ],
    );
  }
}

/// A command and its keys: press the keys to record others, Esc to keep
/// them; the arrow puts back Helmy's own.
class _KeyRow extends StatefulWidget with _Setting {
  const _KeyRow({required this.vm, required this.command});
  final SettingsViewModel vm;
  final AppCommand command;

  @override
  State<_KeyRow> createState() => _KeyRowState();
}

class _KeyRowState extends State<_KeyRow> {
  final _focus = FocusNode();
  bool _recording = false;
  String? _problem;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (!_recording || e is! KeyDownEvent) return .ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _recording = false;
        _problem = null;
      });
      return .handled;
    }
    final b = KeyBinding.of(e);
    if (b == null) {
      setState(
        () => _problem =
            'Hold ${Desktop.current.keys('⌘')} or ${Desktop.current.keys('⌥')} with a key.',
      );
      return .handled;
    }
    final taken = widget.vm.keyTakenBy(widget.command, b);
    if (taken != null) {
      setState(() => _problem = '${b.label} is ${taken.label}\'s.');
      return .handled;
    }
    widget.vm.setKey(widget.command, b);
    setState(() {
      _recording = false;
      _problem = null;
    });
    return .handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final b = bindingOf(widget.command, widget.vm.settings.keys);
    final changed = widget.vm.settings.keys.containsKey(widget.command.name);
    return _Lit(
      title: widget.command.label,
      child: Padding(
        padding: const .symmetric(horizontal: 18, vertical: 12),
        child: Row(
          spacing: 10,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text(widget.command.label, style: t.text.sm.copyWith(fontWeight: .w500)),
                  if (_recording || _problem != null)
                    Text(
                      _problem ?? 'Press the keys, or Esc to keep these.',
                      style: t.text.xs.copyWith(
                        color: _problem == null ? t.colors.mutedForeground : t.colors.destructive,
                      ),
                    ),
                ],
              ),
            ),
            if (changed)
              Tooltip(
                message: "Back to Helmy's own",
                child: Pressable(
                  onPressed: () => widget.vm.setKey(widget.command, null),
                  semanticLabel: 'Reset ${widget.command.label}',
                  builder: (context, state) => AshlarIcon(
                    AshlarIconsRoundedStroke.undo2,
                    size: 14,
                    color: t.colors.mutedForeground,
                  ),
                ),
              ),
            Focus(
              focusNode: _focus,
              onKeyEvent: _onKey,
              onFocusChange: (on) {
                if (!on && _recording) setState(() => _recording = false);
              },
              child: Pressable(
                onPressed: () {
                  setState(() {
                    _recording = true;
                    _problem = null;
                  });
                  _focus.requestFocus();
                },
                semanticLabel: 'Change keys for ${widget.command.label}',
                builder: (context, state) => Container(
                  constraints: const BoxConstraints(minWidth: 64),
                  alignment: .center,
                  padding: const .symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _recording ? t.colors.accent : t.colors.muted,
                    borderRadius: .circular(t.radiusMd),
                    border: Border.all(
                      color: _recording || state.hovered ? t.colors.ring : t.colors.border,
                    ),
                  ),
                  child: Text(
                    _recording ? 'Recording' : b.label,
                    style: t.text.xs.copyWith(
                      fontFamily: 'monospace',
                      fontFamilyFallback: monoFonts,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
