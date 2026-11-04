part of '../chat_screen.dart';

/// Messages written while the agent works, waiting their turn.
class _Queue extends StatelessWidget {
  const new({required this.vm});
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: .fromLTRB(sideMargin(context), 0, sideMargin(context), 8),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 4,
        children: [
          for (final (i, q) in vm.queue.indexed)
            Container(
              padding: const .fromLTRB(12, 6, 4, 6),
              decoration: BoxDecoration(
                border: Border.all(color: t.colors.border),
                borderRadius: .circular(t.radiusMd),
              ),
              child: Row(
                spacing: 8,
                children: [
                  AshlarIcon(
                    AshlarIconsRoundedStroke.clock,
                    size: 14,
                    color: t.colors.mutedForeground,
                  ),
                  Expanded(
                    child: Text(
                      q.text,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                    ),
                  ),
                  Text(
                    i == 0 ? 'Sends next' : 'Waiting',
                    style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                  ),
                  Tooltip(
                    message:
                        'Send now: Helmy takes this up straight away (${Desktop.current.keys('⇧⌘Enter')})',
                    child: Button(
                      variant: .ghost,
                      size: .sm,
                      semanticLabel: 'Send now',
                      onPressed: () => vm.steer(i),
                      child: const Text('Send now'),
                    ),
                  ),
                  Button(
                    variant: .ghost,
                    size: .iconXs,
                    semanticLabel: 'Do not send',
                    onPressed: () => vm.unqueue(i),
                    child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// An empty session's suggestions, from what its folder holds: one press
/// sends one. Gone once you start typing.
class _Starters extends StatelessWidget {
  const new({required this.vm, required this.text, required this.onSend});
  final ChatViewModel vm;
  final TextEditingController text;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return ValueListenableBuilder(
      valueListenable: text,
      builder: (context, value, _) => value.text.isNotEmpty
          ? const SizedBox.shrink()
          : FutureBuilder(
              future: vm.starters(),
              builder: (context, snap) => Padding(
                padding: .fromLTRB(sideMargin(context), 0, sideMargin(context), 8),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    for (final s in snap.data ?? const <Starter>[])
                      Pressable(
                        onPressed: () => onSend(s.prompt),
                        semanticLabel: s.label,
                        builder: (context, state) => Container(
                          padding: const .symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: state.hovered ? t.colors.accent : null,
                            borderRadius: .circular(t.radiusMd),
                          ),
                          child: Row(
                            spacing: 10,
                            children: [
                              AshlarIcon(
                                AshlarIconsRoundedStroke.sparkles,
                                size: 14,
                                color: t.colors.mutedForeground,
                              ),
                              Expanded(
                                child: Text(
                                  s.label,
                                  style: t.text.sm.copyWith(
                                    color: state.hovered
                                        ? t.colors.foreground
                                        : t.colors.mutedForeground,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Commands or files matching what is typed; Tab takes the first.
class _SuggestionList extends StatelessWidget {
  const new({required this.items, required this.onPick});
  final List<_Suggestion> items;
  final ValueChanged<_Suggestion> onPick;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: .fromLTRB(sideMargin(context), 0, sideMargin(context), 6),
      child: Container(
        padding: const .all(4),
        decoration: BoxDecoration(
          color: t.colors.popover,
          border: Border.all(color: t.colors.border),
          borderRadius: .circular(t.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            for (final (i, s) in items.indexed)
              Pressable(
                onPressed: () => onPick(s),
                semanticLabel: s.label,
                builder: (context, state) => Container(
                  padding: const .symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: state.hovered || i == 0 ? t.colors.accent : null,
                    borderRadius: .circular(t.radiusMd),
                  ),
                  child: Row(
                    spacing: 12,
                    children: [
                      Text(
                        s.label,
                        style: t.text.sm.copyWith(
                          fontFamily: 'monospace',
                          fontFamilyFallback: monoFonts,
                        ),
                      ),
                      if (s.detail.isNotEmpty)
                        Expanded(
                          child: Text(
                            s.detail,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                          ),
                        ),
                      if (i == 0)
                        Text('Tab', style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The permission level, as a quiet chip that opens a menu.
class _LevelChip extends StatelessWidget {
  const new({required this.vm, required this.level});
  final ChatViewModel vm;
  final PermissionLevel level;

  /// What the agent may do at [l], in a line.
  static String _what(PermissionLevel l) => switch (l) {
    .ask => 'Asks before changing files or running commands',
    .edit => 'Edits files without asking',
    .readOnly => 'Reads and plans; changes nothing',
    .full => 'Does anything without asking',
  };

  static IconData _icon(PermissionLevel l) => switch (l) {
    .ask => AshlarIconsRoundedStroke.shield,
    .edit => AshlarIconsRoundedStroke.pencil,
    .readOnly => AshlarIconsRoundedStroke.eye,
    .full => AshlarIconsRoundedStroke.zap,
  };

  @override
  Widget build(BuildContext context) => DropdownMenu(
    side: .top,
    width: 300,
    items: [
      for (final l in PermissionLevel.values)
        MenuItem(
          leading: AshlarIcon(_icon(l), size: 15),
          trailing: l == level ? const AshlarIcon(AshlarIconsRoundedStroke.check, size: 14) : null,
          onPressed: () => vm.setLevel(l),
          child: Padding(
            padding: const .symmetric(vertical: 1),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 1,
              children: [
                Text(l.label),
                Text(
                  _what(l),
                  style: AshlarTheme.of(context).text.xs
                      .copyWith(color: AshlarTheme.of(context).colors.mutedForeground),
                ),
              ],
            ),
          ),
        ),
    ],
    builder: (context, menu) => Button(
      variant: .ghost,
      size: .sm,
      semanticLabel: 'Permissions: ${level.label}',
      onPressed: vm.busy ? null : menu.open,
      leading: AshlarIcon(_icon(level), size: 14),
      trailing: const AshlarIcon(AshlarIconsRoundedStroke.chevronDown, size: 14),
      child: Text(level.label),
    ),
  );
}

/// A file waiting to go with the next message.
class _Attached extends StatelessWidget {
  const new({required this.path, required this.vm});
  final String path;
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final name = path.split('/').last;
    final picture = imageTypes.containsKey(name.split('.').last.toLowerCase());
    return Attachment(
      title: name,
      size: .sm,
      onPressed: () => vm.showFile(path),
      icon: picture ? AshlarIconsRoundedStroke.image : AshlarIconsRoundedStroke.file,
      image: picture ? FileImage(File(path)) : null,
      actions: [
        Button(
          variant: .ghost,
          size: .iconXs,
          semanticLabel: 'Remove $name',
          onPressed: () => vm.detach(path),
          child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 12),
        ),
      ],
    );
  }
}

class _Working extends StatelessWidget {
  const new({required this.vm});
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final waiting = vm.items.whereType<PermissionPrompt>().any((p) => p.decision == .pending);
    final label = waiting
        ? 'Waiting for you'
        : vm.thinking
        ? 'Thinking'
        : 'Working';
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Shimmer(
        enabled: !waiting,
        child: Text(label, style: t.text.sm.copyWith(color: t.colors.mutedForeground)),
      ),
    );
  }
}
