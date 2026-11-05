part of '../chat_screen.dart';

/// Softens the top of the conversation into the header, so text scrolling up
/// fades out rather than meeting a line.
class _FadeUnderHeader extends StatelessWidget {
  const new({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bg = AshlarTheme.of(context).colors.background;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 28,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bg, bg.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const new({required this.vm, required this.session});
  final ChatViewModel vm;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.xs.copyWith(color: c.mutedForeground);
    return Container(
      // The title on the window buttons' line; past the sidebar's button
      // when the sidebar is not beside the page.
      // One row, centered on the window buttons' line, as a Mac title bar is:
      // the title, its folder, and the controls.
      padding: .fromLTRB(sidebarBeside(context) ? 24 : titleRowStart + 40, titleLine - 16, 20, 8),
      child: Row(
        spacing: 16,
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              // Text keeps room under its letters for descenders, so centered it
              // reads low: lifted, its capitals center on the line the window's
              // buttons and the sidebar's share (measured: 1.5 points low).
              child: Transform.translate(
                offset: const Offset(0, -1.5),
                child: LayoutBuilder(
                  builder: (context, box) => Row(
                    spacing: 8,
                    children: [
                      // A breadcrumb: the folder, then the session in it. In its
                      // own copy, the repository it is a copy of.
                      // The folder keeps its name whole unless it is very long;
                      // with too little room, the session's title alone.
                      if (box.maxWidth >= 140) ...[
                        Flexible(
                          flex: 2,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: _FolderButton(
                              vm: vm,
                              cwd: session.ownCopy ? session.repo! : session.cwd,
                              style: t.text.sm.copyWith(color: c.mutedForeground, height: 1),
                            ),
                          ),
                        ),
                        Text('/', style: t.text.sm.copyWith(color: c.mutedForeground, height: 1)),
                      ],
                      Flexible(
                        flex: 3,
                        // The chat: its threads are in the conversation, each
                        // under its own separator.
                        child: Text(
                          vm.chatTitle ?? session.title,
                          style: t.text.sm.copyWith(
                            fontWeight: .w500,
                            height: 1,
                            leadingDistribution: .even,
                          ),
                          maxLines: 1,
                          overflow: .ellipsis,
                        ),
                      ),
                      if (session.branch case final branch?)
                        Flexible(
                          child: Tooltip(
                            message: 'Its own branch, in its own copy: other threads here are not disturbed',
                            child: Row(
                              mainAxisSize: .min,
                              spacing: 4,
                              children: [
                                AshlarIcon(
                                  AshlarIconsRoundedStroke.gitBranch,
                                  size: 12,
                                  color: muted.color,
                                ),
                                Flexible(
                                  child: Text(
                                    branch,
                                    maxLines: 1,
                                    overflow: .ellipsis,
                                    style: muted,
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
            ),
          ),
          if (vm.context case final ctx?)
            Tooltip(
              message:
                  '${(ctx.used / 1000).round()}k of ${(ctx.window / 1000).round()}k tokens, as last measured. '
                  'Compact from the menu to free some.',
              child: Text('Context ${(ctx.fraction * 100).round()}%', style: muted),
            ),
          // While the panel is hidden: what in it wants you, a press away.
          for (final p in vm.notices)
            Tooltip(
              message: switch (p) {
                .changes => 'What this thread changed in the folder',
                .background => 'Work running in the background',
                _ => '',
              },
              child: Button(
                variant: .ghost,
                size: .sm,
                onPressed: () => vm.show(p),
                leading: AshlarIcon(switch (p) {
                  .background => AshlarIconsRoundedStroke.loader,
                  _ => AshlarIconsRoundedStroke.fileDiff,
                }, size: 14),
                child: Text(switch (p) {
                  .background =>
                    '${vm.backgroundSteps.where((c) => c.background!.status == .running).length} running',
                  _ => '${vm.changedFiles} change${vm.changedFiles == 1 ? '' : 's'}',
                }),
              ),
            ),
          // The controls, close together as one cluster.
          Row(
            mainAxisSize: .min,
            spacing: 2,
            children: [
              // The project: run it again, and the menu to open it, run more, add.
              if (session.cwd.isNotEmpty) ...[
                ProjectRunButton(vm: vm, compact: MediaQuery.sizeOf(context).width < 820),
                ProjectMenu(vm: vm),
              ],
              // The terminal under the conversation, shown or hidden.
              Tooltip(
                message:
                    '${vm.bottomOpen ? 'Hide' : 'Show'} the terminal (${Desktop.current.keys('⌘J')})',
                child: Button(
                  variant: vm.bottomOpen ? .secondary : .ghost,
                  size: .icon,
                  semanticLabel: vm.bottomOpen ? 'Hide the terminal' : 'Show the terminal',
                  onPressed: vm.toggleBottom,
                  child: const AshlarIcon(AshlarIconsRoundedStroke.panelBottom, size: 16),
                ),
              ),
              // The panel beside the conversation, shown or hidden, its tabs kept.
              Tooltip(
                message: vm.panelOpen ? 'Hide the panel' : 'Show the panel',
                child: Button(
                  variant: vm.panelOpen ? .secondary : .ghost,
                  size: .icon,
                  semanticLabel: vm.panelOpen ? 'Hide the panel' : 'Show the panel',
                  onPressed: () {
                    if (vm.tabs.isEmpty) {
                      // Nothing in it yet: a page to start from.
                      webViewHere ? vm.add(.preview) : vm.show(.changes);
                    } else {
                      vm.togglePanel();
                    }
                  },
                  child: const AshlarIcon(AshlarIconsRoundedStroke.panelRight, size: 16),
                ),
              ),
              _SessionMenu(vm: vm),
            ],
          ),
        ],
      ),
    );
  }
}

/// What can be done with the whole session: rename it, copy or save the
/// conversation, delete it.
class _SessionMenu extends StatelessWidget {
  const new({required this.vm});
  final ChatViewModel vm;

  Future<void> _rename(BuildContext context) async {
    final title = await askText(
      context,
      title: 'Rename chat',
      action: 'Rename',
      initial: vm.chatTitle ?? vm.session?.title ?? '',
      icon: AshlarIconsRoundedStroke.pencil,
    );
    if (title != null) await vm.rename(title);
  }

  Future<void> _save(BuildContext context) async {
    final title = (vm.session?.title ?? 'conversation').replaceAll(RegExp(r'[/:\\]'), '-');
    final where = await getSaveLocation(
      suggestedName: '$title.md',
      initialDirectory: vm.session?.cwd,
      confirmButtonText: 'Save',
    );
    if (where == null) return;
    final result = await vm.saveMarkdown(where.path);
    if (!context.mounted) return;
    if (result is Ok) return showSavedToast(context, where.path, files: vm);
    showToast(
      context,
      title: 'Could not save',
      description: '${(result as Error).error}',
      type: .error,
    );
  }

  /// Deletes this thread: the chat, when it is its only one.
  Future<void> _delete(BuildContext context) async {
    final others = vm.earlierThreads;
    final ok =
        !context.read<SettingsRepository>().settings.confirmDelete ||
        await confirm(
          context,
          title: others.isEmpty ? 'Delete this chat?' : 'Delete this thread?',
          body: others.isEmpty
              ? 'The conversation leaves Helmy. Files in the folder stay as they are.'
              : 'This thread leaves "${vm.chatTitle}"; its other threads stay. Files in the folder stay as they are.',
          action: 'Delete',
          destructive: true,
        );
    if (!ok) return;
    await vm.delete();
    if (!context.mounted) return;
    // The chat goes on in its latest other thread.
    context.go(others.isEmpty ? '/' : '/s/${others.last.id}');
  }

  @override
  Widget build(BuildContext context) => DropdownMenu(
    align: .end,
    items: [
      if (vm.session?.chatId != null && vm.session?.sideOf == null)
        MenuItem(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.messageSquarePlus, size: 16),
          onPressed: () => newThreadIn(context, vm),
          trailing: Text(Desktop.current.keys('⇧⌘N')),
          child: const Text('New thread'),
        ),
      MenuItem(
        leading: const AshlarIcon(AshlarIconsRoundedStroke.pencil, size: 16),
        onPressed: () => _rename(context),
        child: const Text('Rename'),
      ),
      MenuItem(
        leading: const AshlarIcon(AshlarIconsRoundedStroke.copy, size: 16),
        onPressed: () => copyWithToast(context, vm, vm.markdown),
        child: const Text('Copy conversation'),
      ),
      MenuItem(
        leading: const AshlarIcon(AshlarIconsRoundedStroke.minimize2, size: 16),
        onPressed: vm.busy ? null : vm.compact,
        child: const Text('Compact conversation'),
      ),
      MenuItem(
        leading: const AshlarIcon(AshlarIconsRoundedStroke.download, size: 16),
        onPressed: () => _save(context),
        child: const Text('Save as Markdown...'),
      ),
      if (vm.session?.chatId case final chatId?)
        MenuItem(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.messagesSquare, size: 16),
          onPressed: () => context.go('/c/$chatId'),
          child: const Text('Open its chat'),
        ),
      MenuItem(
        leading: const AshlarIcon(AshlarIconsRoundedStroke.webhook, size: 16),
        onPressed: () => showWebhook(context, vm),
        child: Text(vm.session?.hasWebhook ?? false ? 'Webhook (on)...' : 'Webhook...'),
      ),
      const MenuSeparator(),
      // A question beside the session, without adding to it ("/side" too).
      MenuItem(
        leading: const AshlarIcon(AshlarIconsRoundedStroke.messageSquareText, size: 16),
        onPressed: () => unawaited(vm.sideChat()),
        child: const Text('Ask on the side'),
      ),
      if (vm.sideChats.isNotEmpty)
        MenuSub(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.messagesSquare, size: 16),
          items: [
            for (final s in vm.sideChats)
              MenuItem(onPressed: () => vm.openSide(s.id), child: Text(vm.sideTitle(s.id))),
          ],
          child: Text('Side chats (${vm.sideChats.length})'),
        ),
      const MenuSeparator(),
      MenuItem(
        destructive: true,
        leading: const AshlarIcon(AshlarIconsRoundedStroke.trash, size: 16),
        onPressed: vm.busy ? null : () => _delete(context),
        child: Text(vm.earlierThreads.isEmpty ? 'Delete chat' : 'Delete thread'),
      ),
    ],
    builder: (context, menu) => Tooltip(
      message: 'More',
      child: Button(
        variant: .ghost,
        size: .icon,
        semanticLabel: 'Chat actions',
        onPressed: menu.open,
        child: const AshlarIcon(AshlarIconsRoundedStroke.ellipsis, size: 16),
      ),
    ),
  );
}

/// The session's folder, which a click changes.
class _FolderButton extends StatelessWidget {
  const new({required this.vm, required this.cwd, required this.style});
  final ChatViewModel vm;
  final String cwd;
  final TextStyle style;

  Future<void> _pick() async {
    final dir = await getDirectoryPath(initialDirectory: cwd, confirmButtonText: 'Work here');
    if (dir != null) await vm.changeFolder(dir);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Tooltip(
      message: switch ((isScratch(cwd), vm.busy)) {
        (true, true) => 'No project: a folder of its own. Wait for the turn to end to choose one',
        (true, false) => 'No project: a folder of its own. Click to choose a folder to work in',
        (false, true) => '${tildePath(cwd)}. Wait for the turn to end to change the folder',
        (false, false) => '${tildePath(cwd)}. Click to change the folder',
      },
      child: Pressable(
        onPressed: vm.busy ? null : _pick,
        semanticLabel: 'Folder ${tildePath(cwd)}, change',
        builder: (context, state) => Row(
          mainAxisSize: .min,
          spacing: 4,
          children: [
            AshlarIcon(AshlarIconsRoundedStroke.folder, size: 14, color: style.color),
            Flexible(
              child: Text(
                // The folder's name; the whole path is in the tooltip.
                isScratch(cwd)
                    ? 'No project'
                    : tildePath(cwd).split('/').lastWhere((p) => p.isNotEmpty, orElse: () => '/'),
                maxLines: 1,
                overflow: .ellipsis,
                style: style.copyWith(
                  color: state.hovered ? t.colors.foreground : style.color,
                  decoration: state.hovered ? TextDecoration.underline : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chat a thread is in, in the breadcrumb, as a link to its page: shown
/// when the chat holds more than this thread, or was named.

/// Where filing put this new thread, said once under the header: "In
/// Finances", with Move and Undo; or, when two chats were close, the
/// question of which.
class _FilingChip extends StatelessWidget {
  const _FilingChip({required this.vm});
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final f = vm.filing;
    if (f == null) return const SizedBox.shrink();
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.xs.copyWith(color: c.mutedForeground);
    Widget pick(String? id) => Button(
      variant: .outline,
      size: .xs,
      onPressed: () => vm.fileInto(id),
      child: Text(
        id == null ? 'Neither' : vm.chatTitleOf(id) ?? 'That chat',
        maxLines: 1,
        overflow: .ellipsis,
      ),
    );
    final chatId = vm.session?.chatId;
    return Container(
      margin: const .only(bottom: 6),
      padding: const .fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: .5),
        borderRadius: .circular(t.radiusMd),
      ),
      child: Row(
        spacing: 6,
        children: [
          // What it says and does, then the way to put it away at the end.
          Expanded(
            child: Row(
              spacing: 6,
              children: [
                AshlarIcon(
                  AshlarIconsRoundedStroke.messagesSquare,
                  size: 14,
                  color: c.mutedForeground,
                ),
                if (f.kind == .ask) ...[
                  Flexible(
                    child: Text(
                      'Part of an earlier chat?',
                      style: muted,
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ),
                  Flexible(child: pick(f.best)),
                  if (f.runnerUp != null) Flexible(child: pick(f.runnerUp)),
                  pick(null),
                ] else ...[
                  Flexible(
                    child: Pressable(
                      onPressed: chatId == null ? null : () => context.go('/c/$chatId'),
                      semanticLabel: 'In ${vm.chatTitle}',
                      builder: (context, state) => Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'In '),
                            TextSpan(
                              text: vm.chatTitle ?? '',
                              style: TextStyle(
                                color: c.foreground,
                                fontWeight: .w500,
                                decoration: state.hovered ? TextDecoration.underline : null,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: muted,
                      ),
                    ),
                  ),
                  DropdownMenu(
                    items: [
                      for (final other in vm.otherChats)
                        MenuItem(
                          onPressed: () => vm.fileInto(other.id),
                          child: Text(other.title, maxLines: 1, overflow: .ellipsis),
                        ),
                      const MenuSeparator(),
                      MenuItem(onPressed: vm.undoFiling, child: const Text('A chat of its own')),
                    ],
                    builder: (context, menu) => Button(
                      variant: .ghost,
                      size: .xs,
                      onPressed: menu.open,
                      child: const Text('Move'),
                    ),
                  ),
                  Button(
                    variant: .ghost,
                    size: .xs,
                    onPressed: vm.undoFiling,
                    child: const Text('Undo'),
                  ),
                ],
              ],
            ),
          ),
          Tooltip(
            message: 'Put away',
            child: Button(
              variant: .ghost,
              size: .iconXs,
              semanticLabel: 'Put away',
              onPressed: vm.dismissFiling,
              child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Starts a new thread in [vm]'s chat and opens it.
Future<void> newThreadIn(BuildContext context, ChatViewModel vm) async {
  final id = await vm.newThread();
  if (id != null && context.mounted) context.go('/s/$id');
}

/// Said once on a thread Helmy started on its own: why, and the way back.
class _FreshThreadChip extends StatelessWidget {
  const _FreshThreadChip({required this.vm});
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Container(
      margin: const .only(bottom: 6),
      padding: const .fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: .5),
        borderRadius: .circular(t.radiusMd),
      ),
      child: Row(
        spacing: 6,
        children: [
          AshlarIcon(
            AshlarIconsRoundedStroke.messageSquarePlus,
            size: 14,
            color: c.mutedForeground,
          ),
          Expanded(
            child: Text(
              "A new thread: the last one had gone quiet, so this starts fresh with the chat's brief.",
              style: t.text.xs.copyWith(color: c.mutedForeground),
              maxLines: 2,
              overflow: .ellipsis,
            ),
          ),
          Button(
            variant: .outline,
            size: .xs,
            onPressed: () async {
              final id = await vm.keepGoingInLast();
              if (id != null && context.mounted) context.go('/s/$id');
            },
            child: const Text('Keep going in the last one'),
          ),
        ],
      ),
    );
  }
}
