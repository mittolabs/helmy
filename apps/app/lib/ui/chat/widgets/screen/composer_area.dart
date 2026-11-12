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

/// Commands or files matching what is typed, as many as match: about eight
/// show and the rest scroll. The arrows walk them; Enter or Tab takes the one
/// picked.
class _SuggestionList extends StatefulWidget {
  const new({required this.items, required this.picked, required this.onPick});
  final List<_Suggestion> items;
  final int picked;
  final ValueChanged<_Suggestion> onPick;

  @override
  State<_SuggestionList> createState() => _SuggestionListState();
}

class _SuggestionListState extends State<_SuggestionList> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(_SuggestionList old) {
    super.didUpdateWidget(old);
    if (old.items != widget.items) _keys.clear();
    if (old.picked != widget.picked || old.items != widget.items) {
      // The picked row brought into view once it is laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _keys[widget.picked]?.currentContext;
        if (row != null && row.mounted) {
          Scrollable.ensureVisible(
            row,
            duration: const Duration(milliseconds: 80),
            alignmentPolicy: widget.picked > old.picked ? .keepVisibleAtEnd : .keepVisibleAtStart,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final items = widget.items;
    return Padding(
      padding: .fromLTRB(sideMargin(context), 0, sideMargin(context), 6),
      child: Container(
        padding: const .all(4),
        constraints: const BoxConstraints(maxHeight: 280),
        decoration: BoxDecoration(
          color: t.colors.popover,
          border: Border.all(color: t.colors.border),
          borderRadius: .circular(t.radiusLg),
        ),
        child: SingleChildScrollView(
          controller: _scroll,
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              for (final (i, s) in items.indexed)
                Pressable(
                  key: _keys.putIfAbsent(i, GlobalKey.new),
                  onPressed: () => widget.onPick(s),
                  semanticLabel: s.label,
                  builder: (context, state) => Container(
                    padding: const .symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: state.hovered || i == widget.picked ? t.colors.accent : null,
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
                        if (i == widget.picked)
                          Text('Tab', style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
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
      onPressed: () => showFilePopup(context, path, vm, editors: vm.editorChoice),
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

/// A comment on part of the conversation, waiting to go with the next
/// message: the words chosen, and a line to say what about them.
class _Comment extends StatefulWidget {
  const new({super.key, required this.i, required this.vm, required this.latest});
  final int i;
  final ChatViewModel vm;

  /// The newest comment takes the keyboard, ready for its words.
  final bool latest;

  @override
  State<_Comment> createState() => _CommentState();
}

class _CommentState extends State<_Comment> {
  // Its words as they came (a comment made on the design canvas has them).
  late final _words = TextEditingController(text: widget.vm.comments[widget.i].note);

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  /// How the chip names what the comment is on: a screen of the design
  /// and its element ("Today", "Heading · "Today, 3 habits""), else the
  /// words quoted from the conversation. The full quote, file and path
  /// included, is what the agent gets.
  static ({IconData icon, String title, String? detail}) _shown(String quote) {
    final design = RegExp(
      r'^Design · "(.*)" \(design/[^)]*\), (?:the whole screen|the (\w+)(?: "(.*)")? at .*)$',
    ).firstMatch(quote);
    if (design == null) {
      return (
        icon: AshlarIconsRoundedStroke.quote,
        title: quote.replaceAll(RegExp(r'\s+'), ' '),
        detail: null,
      );
    }
    final tag = design.group(2);
    final words = design.group(3);
    return (
      icon: AshlarIconsRoundedStroke.layoutDashboard,
      title: design.group(1)!,
      detail: tag == null
          ? 'The whole screen'
          : [_tagName(tag), if (words != null && words.isNotEmpty) '"$words"'].join(' · '),
    );
  }

  static String _tagName(String tag) => switch (tag) {
    'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' => 'Heading',
    'p' => 'Text',
    'span' || 'b' || 'strong' || 'em' || 'i' || 'small' || 'label' => 'Text',
    'a' => 'Link',
    'button' => 'Button',
    'input' || 'textarea' || 'select' => 'Field',
    'img' || 'svg' || 'picture' => 'Picture',
    'li' => 'List item',
    'ul' || 'ol' => 'List',
    'nav' => 'Navigation',
    'header' => 'Header',
    'footer' => 'Footer',
    _ => 'Box',
  };

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final (i, vm, latest) = (widget.i, widget.vm, widget.latest);
    final comment = vm.comments[i];
    final shown = _shown(comment.quote);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        padding: const .fromLTRB(8, 8, 4, 8),
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: .35),
          border: .all(color: c.border),
          borderRadius: .circular(t.radiusLg),
        ),
        child: Row(
          crossAxisAlignment: .start,
          spacing: 10,
          children: [
            // What it is on, at a glance.
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c.background,
                border: .all(color: c.border),
                borderRadius: .circular(t.radiusMd),
              ),
              child: Center(child: AshlarIcon(shown.icon, size: 15, color: c.mutedForeground)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 2,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: shown.title,
                          style: TextStyle(color: c.foreground, fontWeight: .w500),
                        ),
                        if (shown.detail != null) TextSpan(text: '  ${shown.detail}'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: t.text.xs.copyWith(color: c.mutedForeground),
                  ),
                  // The words, as plain text to write in: no box in a box.
                  Input(
                    key: ValueKey('comment-${comment.id}'),
                    controller: _words,
                    size: .sm,
                    decorated: false,
                    // Its words already written: the keyboard stays where it is.
                    autofocus: latest && _words.text.isEmpty,
                    placeholder: 'What about it?',
                    semanticLabel: 'Comment ${i + 1}',
                    onChanged: (v) => vm.noteComment(i, v),
                  ),
                ],
              ),
            ),
            Button(
              variant: .ghost,
              size: .iconXs,
              semanticLabel: 'Remove comment ${i + 1}',
              onPressed: () => vm.dropComment(i),
              child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the turn is doing, and for how long once it has taken a while.
class _Working extends StatefulWidget {
  const new({required this.vm});
  final ChatViewModel vm;

  @override
  State<_Working> createState() => _WorkingState();
}

class _WorkingState extends State<_Working> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  /// Under five seconds, no count: a quick answer should not flicker one.
  static const _countAfter = Duration(seconds: 5);

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final t = AshlarTheme.of(context);
    final waiting = vm.items.whereType<PermissionPrompt>().any((p) => p.decision == .pending);
    final held = vm.heldUntil;
    final since = vm.items.whereType<UserMessage>().lastOrNull?.sentAt;
    final took = since == null ? null : DateTime.now().difference(since);
    final doing = vm.thinking ? 'Thinking' : 'Working';
    final label = held != null
        ? 'Waiting for room, until ${clockAt(held, null)}'
        : waiting
        ? 'Waiting for you'
        : took != null && took >= _countAfter
        ? '$doing · ${tookLabel(took)}'
        : doing;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Shimmer(
        enabled: !waiting && held == null,
        child: Text(label, style: t.text.sm.copyWith(color: t.colors.mutedForeground)),
      ),
    );
  }
}

/// The latest draft put aside (⌘S), offered back while the box is empty.
class _StashChip extends StatelessWidget {
  const _StashChip({required this.onTake});
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    final StashRepository stash;
    try {
      stash = context.watch<StashRepository>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final latest = stash.items.firstOrNull;
    if (latest == null) return const SizedBox.shrink();
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final words = latest.text.trim().split('\n').first;
    final more = stash.items.length - 1;
    return Padding(
      padding: const .only(bottom: 6),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Pressable(
          onPressed: onTake,
          semanticLabel: 'Restore draft',
          builder: (context, state) => Container(
            padding: const .symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: state.hovered ? c.muted : c.muted.withValues(alpha: .5),
              borderRadius: .circular(t.radiusMd),
            ),
            child: Row(
              mainAxisSize: .min,
              spacing: 6,
              children: [
                AshlarIcon(
                  AshlarIconsRoundedStroke.cornerUpLeft,
                  size: 13,
                  color: c.mutedForeground,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    [
                      'Draft${latest.from.isEmpty ? '' : ' from ${latest.from}'}: '
                          '${words.isEmpty ? '${latest.attachments.length} files' : words}',
                      if (more > 0) '$more more',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: t.text.xs.copyWith(color: c.mutedForeground),
                  ),
                ),
                Text(
                  Desktop.current.keys('⌘S'),
                  style: t.text.xs.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
