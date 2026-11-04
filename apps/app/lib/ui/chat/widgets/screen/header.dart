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
                        child: Text(
                          session.title,
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
                            message: 'Its own branch, in its own copy: other sessions here are not disturbed',
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
                .changes => 'What this session changed in the folder',
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
      title: 'Rename session',
      action: 'Rename',
      initial: vm.session?.title ?? '',
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

  Future<void> _delete(BuildContext context) async {
    final ok =
        !context.read<SettingsRepository>().settings.confirmDelete ||
        await confirm(
          context,
          title: 'Delete this session?',
          body: 'The conversation leaves Helmy. Files in the folder stay as they are.',
          action: 'Delete',
          destructive: true,
        );
    if (!ok) return;
    await vm.delete();
    if (context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) => DropdownMenu(
    align: .end,
    items: [
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
        child: const Text('Delete session'),
      ),
    ],
    builder: (context, menu) => Tooltip(
      message: 'Session',
      child: Button(
        variant: .ghost,
        size: .icon,
        semanticLabel: 'Session actions',
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
