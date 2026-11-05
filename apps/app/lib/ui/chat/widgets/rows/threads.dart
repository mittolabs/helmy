part of '../chat_items.dart';

/// The chat's other threads, above this one (decision 0014): each under a
/// separator, folded to what it came to until opened; then this thread's
/// own separator. Nothing when the chat has one thread.
List<ChatRow> threadRows(ChatViewModel vm) {
  final earlier = vm.earlierThreads;
  final s = vm.session;
  if (earlier.isEmpty || s == null) return const [];
  return [
    for (final t in earlier) ...[
      (
        id: 'ts${t.id}',
        anchor: false,
        child: _ThreadSeparator(
          title: t.title,
          when: t.createdAt,
          open: vm.unfolded.contains(t.id),
          onToggle: () => vm.toggleThread(t.id),
        ),
      ),
      if (vm.unfolded.contains(t.id))
        for (final (i, item) in vm.itemsOf(t.id).indexed)
          if (_pastRow(item) case final row?) (id: 'tp${t.id}-$i', anchor: false, child: row),
      (id: 'tg${t.id}', anchor: false, child: _ThreadGist(vm: vm, thread: t)),
    ],
    (id: 'ts${s.id}', anchor: false, child: _ThreadSeparator(title: s.title, when: s.createdAt)),
  ];
}

/// One part of an earlier thread, to read: what was said and answered.
Widget? _pastRow(ChatItem item) => switch (item) {
  UserMessage(:final text) when text.trim().isNotEmpty => Message(
    align: .end,
    child: Bubble(variant: .muted, child: Text(text)),
  ),
  AssistantText(:final text) when withoutFolderLines(text).trim().isNotEmpty => Builder(
    builder: (context) => Markdown(withoutFolderLines(text)),
  ),
  _ => null,
};

/// Where a thread begins: its title (a press folds or opens an earlier one)
/// and when it started, over a hairline across the conversation.
class _ThreadSeparator extends StatelessWidget {
  const _ThreadSeparator({required this.title, required this.when, this.open, this.onToggle});

  final String title;
  final DateTime when;

  /// Open or folded; null for the thread being written in, which is always open.
  final bool? open;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final label = Row(
      mainAxisSize: .min,
      spacing: 4,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: .ellipsis,
            style: t.text.sm.copyWith(color: c.mutedForeground, fontWeight: .w500),
          ),
        ),
        if (open != null)
          AshlarIcon(
            open! ? AshlarIconsRoundedStroke.chevronUp : AshlarIconsRoundedStroke.chevronDown,
            size: 14,
            color: c.mutedForeground,
          ),
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const .only(top: 14, bottom: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(
          spacing: 12,
          children: [
            Expanded(
              child: onToggle == null
                  ? Align(alignment: AlignmentDirectional.centerStart, child: label)
                  : Pressable(
                      onPressed: onToggle,
                      semanticLabel: open! ? 'Fold "$title"' : 'Open "$title"',
                      builder: (context, state) => Opacity(
                        opacity: state.hovered ? .8 : 1,
                        child: Align(alignment: AlignmentDirectional.centerStart, child: label),
                      ),
                    ),
            ),
            Text(threadStamp(when), style: t.text.xs.copyWith(color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}

/// An earlier thread, folded: what it came to; and a way to take it up again.
class _ThreadGist extends StatelessWidget {
  const _ThreadGist({required this.vm, required this.thread});
  final ChatViewModel vm;
  final Session thread;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final open = vm.unfolded.contains(thread.id);
    final gist = vm.gistOf(thread);
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground);
    return Column(
      crossAxisAlignment: .start,
      spacing: 6,
      children: [
        // Folded: what it came to, unless that is only its title again.
        if (!open && gist.isNotEmpty && gist != thread.title)
          Text(gist, maxLines: 2, overflow: .ellipsis, style: muted),
        Pressable(
          onPressed: () => context.go('/s/${thread.id}'),
          semanticLabel: 'Continue "${thread.title}"',
          builder: (context, state) => Row(
            mainAxisSize: .min,
            spacing: 4,
            children: [
              AshlarIcon(
                AshlarIconsRoundedStroke.cornerDownRight,
                size: 13,
                color: state.hovered ? t.colors.foreground : t.colors.mutedForeground,
              ),
              Text(
                'Continue this thread',
                style: t.text.xs.copyWith(
                  color: state.hovered ? t.colors.foreground : t.colors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// When a thread began, as a separator says it: "3:40 PM" today, else
/// "Nov 4, 3:40 PM" (with the year when it is not this one).
String threadStamp(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final clock = '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  if (t.year == n.year && t.month == n.month && t.day == n.day) return clock;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final day = '${months[t.month - 1]} ${t.day}';
  return t.year == n.year ? '$day, $clock' : '$day ${t.year}, $clock';
}
