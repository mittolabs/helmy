part of '../chat_screen.dart';

/// What the last answer leaves this chat waiting on, outside it (someone's
/// reply, a command run elsewhere), with one press to set it aside until
/// then: out of the list into Waiting, back as needing you at the time
/// chosen, or as soon as you write in it.
class _WaitOffer extends StatelessWidget {
  const _WaitOffer({required this.vm, required this.on});
  final ChatViewModel vm;
  final String on;

  Future<void> _aside(BuildContext context, DateTime until) async {
    await vm.setAside(on, until);
    if (!context.mounted) return;
    showToast(
      context,
      title: 'Set aside, waiting on ${_lower(on)}',
      description:
          "It's in Waiting, and comes back ${whenSaid(until)}, or as soon as you write in it.",
    );
  }

  /// [s] to read inside a sentence: "What the log prints" as "what the log
  /// prints", while a name ("Debby to say which project") stays as it is.
  static String _lower(String s) {
    final first = s.split(' ').first;
    const plain = {'what', 'the', 'a', 'an', 'your', 'you', 'output', 'results', 'reply', 'answer'};
    return plain.contains(first.toLowerCase()) ? s[0].toLowerCase() + s.substring(1) : s;
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final choices = SidebarViewModel.waitChoices();
    final (label, until) = choices.first;
    return Container(
      margin: const .only(bottom: 10),
      padding: const .fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: .35),
        border: .all(color: c.border),
        borderRadius: .circular(t.radiusLg),
      ),
      // Narrow (a phone's width): the buttons under the words.
      child: LayoutBuilder(
        builder: (context, box) {
          final words = Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Waiting on ',
                  style: t.text.sm.copyWith(color: c.mutedForeground),
                ),
                TextSpan(
                  text: _lower(on),
                  style: t.text.sm.copyWith(fontWeight: .w500),
                ),
                TextSpan(
                  text: '? Set it aside and Helmy brings it back.',
                  style: t.text.sm.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
            maxLines: 2,
            overflow: .ellipsis,
          );
          final presses = <Widget>[
            Button(
              size: .sm,
              variant: .outline,
              onPressed: () => unawaited(_aside(context, until)),
              child: Text(label),
            ),
            DropdownMenu(
              side: .top,
              align: .end,
              items: [
                const MenuLabel(child: Text('Back')),
                for (final (label, at) in choices.skip(1))
                  MenuItem(onPressed: () => unawaited(_aside(context, at)), child: Text(label)),
              ],
              builder: (context, menu) => Button(
                size: .iconSm,
                variant: .ghost,
                semanticLabel: 'Another time',
                onPressed: menu.open,
                child: const AshlarIcon(AshlarIconsRoundedStroke.chevronDown, size: 14),
              ),
            ),
            Button(
              size: .iconSm,
              variant: .ghost,
              semanticLabel: "It isn't waiting",
              onPressed: () => unawaited(vm.dismissWaitOffer()),
              child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 14),
            ),
          ];
          if (box.maxWidth >= 480) {
            return Row(
              spacing: 10,
              children: [
                AshlarIcon(AshlarIconsRoundedStroke.hourglass, size: 15, color: c.mutedForeground),
                Expanded(child: words),
                ...presses,
              ],
            );
          }
          return Column(
            crossAxisAlignment: .stretch,
            spacing: 6,
            children: [
              Row(
                spacing: 10,
                crossAxisAlignment: .start,
                children: [
                  AshlarIcon(
                    AshlarIconsRoundedStroke.hourglass,
                    size: 15,
                    color: c.mutedForeground,
                  ),
                  Expanded(child: words),
                ],
              ),
              Row(mainAxisAlignment: .end, spacing: 4, children: presses),
            ],
          );
        },
      ),
    );
  }
}
