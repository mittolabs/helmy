part of '../chat_screen.dart';

/// Find in this session: the words, how many places have them, and which one
/// is shown. Enter goes to the next, Shift+Enter back, Esc closes.
class _FindBar extends StatelessWidget {
  const new({
    required this.controller,
    required this.focus,
    required this.count,
    required this.at,
    required this.onChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final int count, at;
  final VoidCallback onChanged, onNext, onPrevious, onClose;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: const .fromLTRB(24, 0, 20, 8),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): onNext,
          const SingleActivator(LogicalKeyboardKey.enter, shift: true): onPrevious,
          const SingleActivator(LogicalKeyboardKey.escape): onClose,
        },
        child: Row(
          spacing: 6,
          children: [
            Expanded(
              child: Input(
                controller: controller,
                focusNode: focus,
                autofocus: true,
                placeholder: 'Find in this thread',
                leading: const AshlarIcon(AshlarIconsRoundedStroke.search, size: 14),
                onChanged: (_) => onChanged(),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                controller.text.trim().isEmpty
                    ? ''
                    : count == 0
                    ? 'No matches'
                    : '${at % count + 1} of $count',
                textAlign: .end,
                style: t.text.xs.copyWith(color: t.colors.mutedForeground),
              ),
            ),
            Tooltip(
              message: 'Previous (⇧Enter)',
              child: Button(
                variant: .ghost,
                size: .iconSm,
                semanticLabel: 'Previous match',
                onPressed: count == 0 ? null : onPrevious,
                child: const AshlarIcon(AshlarIconsRoundedStroke.chevronUp, size: 14),
              ),
            ),
            Tooltip(
              message: 'Next (Enter)',
              child: Button(
                variant: .ghost,
                size: .iconSm,
                semanticLabel: 'Next match',
                onPressed: count == 0 ? null : onNext,
                child: const AshlarIcon(AshlarIconsRoundedStroke.chevronDown, size: 14),
              ),
            ),
            Tooltip(
              message: 'Close (Esc)',
              child: Button(
                variant: .ghost,
                size: .iconSm,
                semanticLabel: 'Close find',
                onPressed: onClose,
                child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
