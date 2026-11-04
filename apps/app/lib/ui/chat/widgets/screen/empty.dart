part of '../chat_screen.dart';

/// An empty session's welcome: Helmy waving, or rubbing its eyes when only
/// the model on this Mac can answer.
class _Hello extends StatelessWidget {
  const new({required this.offline});
  final bool offline;

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
            Text(
              offline
                  ? "I'm working on ${Desktop.current.thisComputer} only"
                  : 'What should we get done?',
              style: t.text.lg.copyWith(fontWeight: .w600),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                offline
                    ? "Nothing online is available right now, so I'm slower, and "
                          "your accounts are out of reach. Your folders aren't."
                    : 'Dream it, do it: tell me what you want, in this folder or '
                          'in your accounts.',
                textAlign: .center,
                style: t.text.sm.copyWith(color: t.colors.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
