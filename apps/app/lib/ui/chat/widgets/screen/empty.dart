part of '../chat_screen.dart';

/// An empty session's welcome: Helmy waving, or rubbing its eyes when only
/// the model on this Mac can answer.
class _Hello extends StatelessWidget {
  const new({required this.offline, required this.vm});
  final bool offline;
  final ChatViewModel vm;

  String get _folder {
    final s = vm.session;
    return s == null ? '' : (s.ownCopy ? s.repo! : s.cwd);
  }

  bool get _noProject => isScratch(_folder);

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const .all(24),
        child: Column(
          mainAxisSize: .min,
          spacing: 12,
          children: [
            Image.asset(
              offline ? 'assets/helmy/offline.png' : 'assets/helmy/hello.png',
              width: 132,
              height: 132,
              semanticLabel: 'Helmy',
            ),
            Text.rich(
              offline
                  ? TextSpan(text: "I'm working on ${Desktop.current.thisComputer} only")
                  : TextSpan(
                      children: [
                        const TextSpan(text: 'What should we get done'),
                        // In a project: which, as T3 Code says it.
                        if (!_noProject) ...[
                          const TextSpan(text: ' in '),
                          TextSpan(
                            text: folderName(_folder),
                            style: const TextStyle(fontWeight: .w600),
                          ),
                        ],
                        const TextSpan(text: '?'),
                      ],
                    ),
              textAlign: .center,
              // As T3 Code sets it: the question plain, the project in bold.
              style: t.text.lg.copyWith(fontWeight: offline ? .w600 : .w400),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                offline
                    ? "Nothing online is available right now, so I'm slower, and "
                          "your accounts are out of reach. Your folders aren't."
                    : _noProject
                    ? 'Dream it, do it: tell me what you want, here or in your accounts.'
                    : 'Dream it, do it: tell me what you want, in this folder or '
                          'in your accounts.',
                textAlign: .center,
                style: t.text.sm.copyWith(color: t.colors.mutedForeground),
              ),
            ),
            // Not every request belongs to a project; and back into one.
            if (!offline)
              _Link(
                label: _noProject ? 'Choose a folder to work in' : 'or start without a project',
                onPressed: vm.busy
                    ? null
                    : _noProject
                    ? () async {
                        final dir = await getDirectoryPath(confirmButtonText: 'Work here');
                        if (dir != null) await vm.changeFolder(dir);
                      }
                    : vm.startWithoutProject,
              ),
          ],
        ),
      ),
    );
  }
}

/// A quiet line of text that does something, underlined under the mouse.
class _Link extends StatelessWidget {
  const new({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => Text(
        label,
        style: t.text.sm.copyWith(
          color: state.hovered ? t.colors.foreground : t.colors.mutedForeground,
          decoration: state.hovered ? TextDecoration.underline : null,
        ),
      ),
    );
  }
}
