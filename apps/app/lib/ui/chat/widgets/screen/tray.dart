part of '../chat_screen.dart';

/// The strip under the message box: the chat's project (choose one, or none),
/// its files, and Helmy's skills to pick from.
class _Tray extends StatelessWidget {
  const _Tray({required this.vm, required this.session, required this.onSkills});
  final ChatViewModel vm;
  final Session session;

  /// Opens the skills list in the message box, as typing / does.
  final VoidCallback onSkills;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final style = t.text.xs.copyWith(color: c.mutedForeground, height: 1);
    // Narrow (a phone's width), the buttons keep their icons and lose their words.
    return LayoutBuilder(
      builder: (context, box) {
        final words = box.maxWidth >= 380;
        return Row(
          spacing: 2,
          children: [
            Flexible(
              child: Padding(
                padding: const .symmetric(horizontal: 6, vertical: 4),
                child: TourTarget(
                  stop: .folder,
                  child: _FolderButton(
                    vm: vm,
                    cwd: session.ownCopy ? session.repo! : session.cwd,
                    style: style,
                  ),
                ),
              ),
            ),
            _TrayButton(
              icon: AshlarIconsRoundedStroke.files,
              label: 'Files',
              words: words,
              onPressed: () => vm.show(.files),
            ),
            _TrayButton(
              icon: AshlarIconsRoundedStroke.puzzle,
              label: 'Skills',
              words: words,
              onPressed: onSkills,
            ),
          ],
        );
      },
    );
  }
}

class _TrayButton extends StatelessWidget {
  const _TrayButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.words = true,
  });
  final IconData icon;
  final String label;
  final bool words;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => Container(
        padding: const .symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: state.hovered ? c.foreground.withValues(alpha: .06) : null,
          borderRadius: .circular(t.radiusMd),
        ),
        child: Row(
          mainAxisSize: .min,
          spacing: 5,
          children: [
            AshlarIcon(icon, size: 13, color: state.hovered ? c.foreground : c.mutedForeground),
            if (words)
              Text(
                label,
                style: t.text.xs.copyWith(
                  color: state.hovered ? c.foreground : c.mutedForeground,
                  height: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
