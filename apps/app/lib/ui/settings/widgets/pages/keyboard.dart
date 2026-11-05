part of '../settings_screen.dart';

class _Keyboard extends StatelessWidget {
  const new();

  static const _keys = [
    ('⌘N', 'New chat'),
    ('⇧⌘N', 'New thread in this chat'),
    ('⌘K', 'Search chats and run actions'),
    ('⌘B', 'Show or hide the sidebar'),
    ('⌘,', 'Settings'),
    ('⌘1 to ⌘9', 'Open the chats in the order the list shows them'),
    ('⌘[ / ⌘]', 'Back and forward through where you have been'),
    ('⌘F', 'Find in this thread; Enter for the next, Shift+Enter the one before'),
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
