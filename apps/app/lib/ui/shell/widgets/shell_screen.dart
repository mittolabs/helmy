import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/session.dart';
import '../../../utils/format.dart';
import '../../../domain/models/settings.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/context_menu.dart';
import '../../core/ashlar/dropdown_menu.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/sidebar.dart';
import '../../core/helmy_dialog.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/toast.dart';
import '../../../routing/nav_history.dart';
import '../../core/ashlar/tooltip.dart';
import '../view_models/sidebar_view_model.dart';
import 'command_palette.dart';
import 'new_session.dart';

/// The sessions down the side, the open one beside them.
class ShellScreen extends StatelessWidget {
  const new({
    super.key,
    required this.viewModel,
    required this.selectedId,
    required this.child,
    this.inSettings = false,
    this.inSchedule = false,
  });

  final bool inSettings;
  final bool inSchedule;

  final SidebarViewModel viewModel;
  final String? selectedId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return CallbackShortcuts(
      // Keys reach here from wherever focus is in the window.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            showPalette(context, viewModel),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            newSession(context, viewModel),
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () => context.go('/settings'),
        // ⌘1 to ⌘9: the sessions in the order the list shows them.
        for (final (i, key) in const [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.digit6,
          LogicalKeyboardKey.digit7,
          LogicalKeyboardKey.digit8,
          LogicalKeyboardKey.digit9,
        ].indexed)
          SingleActivator(key, meta: true): () {
            final list = viewModel.inOrder;
            if (i < list.length) context.go('/s/${list[i].id}');
          },
        // Back and forward through where you have been.
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true): () =>
            NavHistory.current?.back(),
        const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true): () =>
            NavHistory.current?.forward(),
        // Undo the last archive (a text field's own undo comes first).
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): viewModel.undoArchive,
      },
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) => SidebarLayout(
          rail: false,
          // Hides off the side; its button or ⌘B brings it back.
          collapse: .offcanvas,
          open: viewModel.settings.sidebarOpen,
          onOpenChanged: (open) =>
              viewModel.updateSettings(viewModel.settings.copyWith(sidebarOpen: open)),
          width: 272,
          header: Padding(
            // Clears the window's buttons, which sit over the sidebar.
            padding: const EdgeInsetsDirectional.only(start: 8, top: 30, end: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text('Helmy', style: t.text.base.copyWith(fontWeight: .w600)),
                ),
                const Tooltip(message: 'Hide sidebar (⌘B)', child: SidebarTrigger()),
              ],
            ),
          ),
          footer: Padding(
            padding: const .fromLTRB(0, 4, 0, 8),
            child: _NavRow(
              icon: AshlarIconsRoundedStroke.settings,
              label: 'Settings',
              shortcut: '⌘,',
              selected: inSettings,
              onPressed: () => context.go('/settings'),
            ),
          ),
          groups: [
            // What you do, as labelled rows, the way other chat apps lay it out.
            SidebarGroup.custom(
              Column(
                crossAxisAlignment: .stretch,
                spacing: 2,
                children: [
                  _NavRow(
                    icon: AshlarIconsRoundedStroke.squarePen,
                    label: 'New session',
                    shortcut: '⌘N',
                    onPressed: () => newSession(context, viewModel),
                  ),
                  _NavRow(
                    icon: AshlarIconsRoundedStroke.search,
                    label: 'Search',
                    shortcut: '⌘K',
                    onPressed: () => showPalette(context, viewModel),
                  ),
                  _NavRow(
                    icon: AshlarIconsRoundedStroke.clock,
                    label: 'Scheduled',
                    selected: inSchedule,
                    onPressed: () => context.go('/scheduled'),
                  ),
                ],
              ),
            ),
            SidebarGroup.custom(
              Column(
                crossAxisAlignment: .stretch,
                children: [
                  // The list's heading, with how it is shown at its end.
                  Padding(
                    padding: const .fromLTRB(10, 4, 0, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            switch (viewModel.settings.show) {
                              .active => 'Sessions',
                              .archived => 'Archived',
                              .all => 'All sessions',
                            },
                            style: t.text.xs.copyWith(
                              color: t.colors.mutedForeground,
                              fontWeight: .w500,
                            ),
                          ),
                        ),
                        _ListMenu(viewModel: viewModel),
                      ],
                    ),
                  ),
                  viewModel.shown.isEmpty
                      ? Padding(
                          padding: const .symmetric(horizontal: 10, vertical: 4),
                          child: Text(
                            'Nothing yet.',
                            style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                          ),
                        )
                      : Column(
                          spacing: 2,
                          crossAxisAlignment: .stretch,
                          children: [
                            for (final g in viewModel.groups) ...[
                              if (g.label case final label?)
                                Padding(
                                  padding: const .fromLTRB(10, 10, 10, 2),
                                  child: Text(
                                    label,
                                    style: t.text.xs.copyWith(
                                      color: t.colors.mutedForeground,
                                      fontWeight: .w600,
                                    ),
                                  ),
                                ),
                              if (g.folder != null)
                                Padding(
                                  padding: const .fromLTRB(10, 10, 10, 2),
                                  child: Text(
                                    tildePath(g.folder!),
                                    maxLines: 1,
                                    overflow: .ellipsis,
                                    style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                                  ),
                                ),
                              for (final s in g.sessions)
                                ContextMenu(
                                  items: [
                                    if (viewModel.isUnread(s.id))
                                      MenuItem(
                                        leading: const AshlarIcon(
                                          AshlarIconsRoundedStroke.check,
                                          size: 16,
                                        ),
                                        onPressed: () => viewModel.markRead(s.id),
                                        child: const Text('Mark as read'),
                                      ),
                                    MenuItem(
                                      leading: const AshlarIcon(
                                        AshlarIconsRoundedStroke.pin,
                                        size: 16,
                                      ),
                                      onPressed: () => viewModel.setPinned(s, !s.pinned),
                                      child: Text(s.pinned ? 'Unpin' : 'Pin'),
                                    ),
                                    MenuItem(
                                      leading: const AshlarIcon(
                                        AshlarIconsRoundedStroke.archive,
                                        size: 16,
                                      ),
                                      onPressed: () async {
                                        final archiving = !s.archived;
                                        await viewModel.setArchived(s, archiving);
                                        if (!archiving || !context.mounted) return;
                                        showToast(
                                          context,
                                          title: 'Archived "${s.title}"',
                                          action: Button(
                                            size: .sm,
                                            variant: .outline,
                                            onPressed: viewModel.undoArchive,
                                            child: const Text('Undo (⌘Z)'),
                                          ),
                                        );
                                      },
                                      child: Text(s.archived ? 'Unarchive' : 'Archive'),
                                    ),
                                    const MenuSeparator(),
                                    MenuItem(
                                      destructive: true,
                                      leading: const AshlarIcon(
                                        AshlarIconsRoundedStroke.trash,
                                        size: 16,
                                      ),
                                      onPressed: () => _delete(context, s),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                  child: _SessionRow(
                                    session: s,
                                    activity: viewModel.activityOf(s.id),
                                    selected: s.id == selectedId,
                                    onOpen: () => context.go('/s/${s.id}'),
                                    onDelete: () => _delete(context, s),
                                  ),
                                ),
                            ],
                          ],
                        ),
                ],
              ),
            ),
          ],
          // Hidden, its button sits beside the window's own buttons, over the page.
          child: viewModel.settings.sidebarOpen
              ? child
              : Stack(
                  children: [
                    child,
                    const PositionedDirectional(
                      start: 76,
                      top: 18,
                      child: Tooltip(message: 'Show sidebar (⌘B)', child: SidebarTrigger()),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, Session s) async {
    final ok =
        !viewModel.settings.confirmDelete ||
        await confirm(
          context,
          title: 'Delete this session?',
          body:
              '"${s.title}" and its conversation leave Helmy. Files in the folder stay as they are.',
          action: 'Delete',
          destructive: true,
        );
    if (!ok) return;
    await viewModel.delete.execute(s.id);
    if (context.mounted && selectedId == s.id) context.go('/');
  }
}

/// What the list shows and how: active, archived or all; grouped by folder or
/// not; newest first or by name.
class _ListMenu extends StatelessWidget {
  const new({required this.viewModel});
  final SidebarViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final s = viewModel.settings;

    /// One setting: its name, its value faint at the end, its choices a level in.
    Widget setting<T>(String name, T value, Map<T, String> choices, AppSettings Function(T) next) =>
        MenuSub(
          items: [
            MenuRadioGroup<T>(
              value: value,
              onChanged: (v) => viewModel.updateSettings(next(v)),
              children: [
                for (final e in choices.entries) MenuRadioItem(value: e.key, child: Text(e.value)),
              ],
            ),
          ],
          child: Row(
            children: [
              Expanded(child: Text(name)),
              Text(choices[value]!, style: t.text.sm.copyWith(color: t.colors.mutedForeground)),
            ],
          ),
        );

    return DropdownMenu(
      align: .end,
      width: 240,
      items: [
        setting<ShowSessions>('Show', s.show, const {
          ShowSessions.active: 'Active',
          ShowSessions.archived: 'Archived',
          ShowSessions.all: 'All',
        }, (v) => s.copyWith(show: v)),
        setting<Recency>('Last activity', s.recency, const {
          Recency.all: 'All',
          Recency.today: 'Today',
          Recency.week: 'Last 7 days',
          Recency.month: 'Last 30 days',
        }, (v) => s.copyWith(recency: v)),
        const MenuSeparator(),
        setting<GroupSessions>('Group by', s.group, const {
          GroupSessions.none: 'None',
          GroupSessions.folder: 'Folder',
        }, (v) => s.copyWith(group: v)),
        setting<SortSessions>('Sort by', s.sort, const {
          SortSessions.recent: 'Last activity',
          SortSessions.name: 'Name',
        }, (v) => s.copyWith(sort: v)),
      ],
      builder: (context, menu) => Tooltip(
        message: 'Show, group and sort',
        child: Button(
          variant: .ghost,
          size: .iconSm,
          semanticLabel: 'Show, group and sort sessions',
          onPressed: menu.open,
          child: const AshlarIcon(AshlarIconsRoundedStroke.listFilter, size: 16),
        ),
      ),
    );
  }
}

/// An action in the sidebar: its icon, its name, and its shortcut faint at the end.
class _NavRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.shortcut,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final String? shortcut;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: label,
      builder: (context, state) => Container(
        padding: const .symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? c.sidebarAccent
              : state.hovered
              ? c.sidebarAccent.withValues(alpha: .5)
              : null,
          borderRadius: .circular(t.radiusMd),
        ),
        child: Row(
          spacing: 10,
          children: [
            AshlarIcon(icon, size: 16, color: c.sidebarForeground),
            Expanded(
              child: Text(label, style: t.text.sm.copyWith(color: c.sidebarForeground)),
            ),
            if (shortcut != null && state.hovered)
              Text(shortcut!, style: t.text.xs.copyWith(color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatefulWidget {
  const new({
    required this.session,
    required this.activity,
    required this.selected,
    required this.onOpen,
    required this.onDelete,
  });

  final Session session;
  final SessionActivity activity;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final s = widget.session;
    final muted = t.text.xs.copyWith(color: c.mutedForeground);
    final status = switch (widget.activity) {
      .working => const Spinner(size: 12, semanticLabel: 'Working'),
      .needsYou => Tooltip(
        message: 'Waiting for your approval',
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c.primary, shape: .circle),
        ),
      ),
      .unread => Tooltip(
        message: 'Finished while you were away',
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c.foreground, shape: .circle),
        ),
      ),
      .idle => Text(ago(s.updatedAt), style: muted),
    };
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Pressable(
        onPressed: widget.onOpen,
        semanticLabel: '${s.title}, in ${folderName(s.cwd)}',
        selected: widget.selected,
        builder: (context, state) => AnimatedContainer(
          duration: t.duration,
          padding: const .symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? c.sidebarAccent
                : state.hovered
                ? c.sidebarAccent.withValues(alpha: .5)
                : c.sidebarAccent.withValues(alpha: 0),
            borderRadius: .circular(t.radiusMd),
            boxShadow: [if (state.focused) BoxShadow(color: c.sidebarRing, spreadRadius: 2)],
          ),
          child: Row(
            spacing: 10,
            children: [
              if (s.pinned)
                AshlarIcon(AshlarIconsRoundedStroke.pin, size: 12, color: c.mutedForeground),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      s.title,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: t.text.sm.copyWith(
                        color: c.sidebarForeground,
                        fontWeight: widget.selected ? .w500 : .w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hovered && (widget.activity == .idle || widget.activity == .unread))
                Button(
                  variant: .ghost,
                  size: .iconXs,
                  semanticLabel: 'Delete ${s.title}',
                  onPressed: widget.onDelete,
                  child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 14),
                )
              else
                status,
            ],
          ),
        ),
      ),
    );
  }
}
