import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/settings_route.dart';

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
import '../../core/window_layout.dart';
import '../../../utils/platform.dart';
import '../../chat/widgets/player.dart';

/// The sessions down the side, the open one beside them.
class ShellScreen extends StatelessWidget {
  const new({
    super.key,
    required this.viewModel,
    required this.selectedId,
    required this.child,
    this.inSchedule = false,
  });

  final bool inSchedule;

  final SidebarViewModel viewModel;
  final String? selectedId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return _InAppNotes(
      viewModel: viewModel,
      child: CallbackShortcuts(
        // Keys reach here from wherever focus is in the window.
        bindings: {
          Desktop.current.shortcut(LogicalKeyboardKey.keyK): () => showPalette(context, viewModel),
          Desktop.current.shortcut(LogicalKeyboardKey.keyN): () => newSession(context, viewModel),
          Desktop.current.shortcut(LogicalKeyboardKey.comma): () =>
              openSettings(GoRouter.of(context)),
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
            Desktop.current.shortcut(key): () {
              final list = viewModel.inOrder;
              if (i < list.length) context.go('/s/${list[i].id}');
            },
          // Back and forward through where you have been.
          Desktop.current.shortcut(LogicalKeyboardKey.bracketLeft): () =>
              NavHistory.current?.back(),
          Desktop.current.shortcut(LogicalKeyboardKey.bracketRight): () =>
              NavHistory.current?.forward(),
          // Undo the last archive (a text field's own undo comes first).
          Desktop.current.shortcut(LogicalKeyboardKey.keyZ): viewModel.undoArchive,
          // A Mac's menu quits with ⌘Q; elsewhere Ctrl+Q is the app's to give.
          if (!Desktop.current.commandIsMeta)
            Desktop.current.shortcut(LogicalKeyboardKey.keyQ): () =>
                ServicesBinding.instance.exitApplication(AppExitType.required),
        },
        child: ListenableBuilder(
          listenable: viewModel,
          builder: (context, _) => SidebarLayout(
            rail: false,
            // Hides off the side; its button or ⌘B brings it back.
            collapse: .offcanvas,
            narrow: narrowWindow,
            open: viewModel.settings.sidebarOpen,
            onOpenChanged: (open) =>
                viewModel.updateSettings(viewModel.settings.copyWith(sidebarOpen: open)),
            width: 272,
            header: TitleBar(
              child: Padding(
                // Clears the window's buttons, which sit over the sidebar.
                padding: const EdgeInsetsDirectional.only(start: 8, top: 30, end: 2),
                child: Row(
                  children: [
                    Image.asset(
                      t.brightness == .dark
                          ? 'assets/helmy/head-dark.png'
                          : 'assets/helmy/head-light.png',
                      width: 22,
                      height: 22,
                      semanticLabel: 'Helmy',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Helmy', style: t.text.base.copyWith(fontWeight: .w600)),
                    ),
                    Tooltip(
                      message: 'Hide sidebar (${Desktop.current.keys('⌘B')})',
                      child: const SidebarTrigger(),
                    ),
                  ],
                ),
              ),
            ),
            footer: Padding(
              padding: const .fromLTRB(0, 4, 0, 8),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                children: [
                  if (viewModel.notificationsBlocked) _NotificationsBlocked(viewModel: viewModel),
                  _NavRow(
                    icon: AshlarIconsRoundedStroke.settings,
                    label: 'Settings',
                    shortcut: Desktop.current.keys('⌘,'),
                    onPressed: () => openSettings(GoRouter.of(context)),
                  ),
                ],
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
                      shortcut: Desktop.current.keys('⌘N'),
                      onPressed: () => newSession(context, viewModel),
                    ),
                    _NavRow(
                      icon: AshlarIconsRoundedStroke.search,
                      label: 'Search',
                      shortcut: Desktop.current.keys('⌘K'),
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
                                      if (s.snoozed)
                                        MenuItem(
                                          leading: const AshlarIcon(
                                            AshlarIconsRoundedStroke.clock,
                                            size: 16,
                                          ),
                                          onPressed: () => viewModel.wake(s),
                                          child: const Text('Wake now'),
                                        )
                                      else ...[
                                        for (final (label, until) in [
                                          (
                                            'Snooze for an hour',
                                            DateTime.now().add(const Duration(hours: 1)),
                                          ),
                                          (
                                            'Snooze until tomorrow',
                                            SidebarViewModel.tomorrowMorning(),
                                          ),
                                        ])
                                          MenuItem(
                                            leading: const AshlarIcon(
                                              AshlarIconsRoundedStroke.clock,
                                              size: 16,
                                            ),
                                            onPressed: () async {
                                              await viewModel.snooze(s, until);
                                              if (!context.mounted) return;
                                              showToast(
                                                context,
                                                title: 'Snoozed "${s.title}" until ${_when(until)}',
                                                action: Button(
                                                  size: .sm,
                                                  variant: .outline,
                                                  onPressed: viewModel.undoSnooze,
                                                  child: const Text('Undo'),
                                                ),
                                              );
                                            },
                                            child: Text(label),
                                          ),
                                      ],
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
                                              child: Text('Undo (${Desktop.current.keys('⌘Z')})'),
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
            // (The view model's settings, as this screen is given no provider.)
            // A video popped out of a conversation plays over the page's corner,
            // whatever page is showing.
            child:
                viewModel.settings.sidebarOpen && MediaQuery.sizeOf(context).width >= narrowWindow
                ? Stack(children: [child, const CornerPlayer()])
                : Stack(
                    children: [
                      child,
                      const CornerPlayer(),
                      // In line with the window's buttons, just after them,
                      // as a Mac app's sidebar button sits.
                      // (At the edge in full screen, where the window's buttons hide.)
                      ListenableBuilder(
                        listenable: windowFullScreen,
                        builder: (context, button) => PositionedDirectional(
                          start: titleRowStart,
                          top: titleLine - 16,
                          child: button!,
                        ),
                        child: Tooltip(
                          message: 'Show sidebar (${Desktop.current.keys('⌘B')})',
                          child: Builder(
                            builder: (context) => Button(
                              variant: .ghost,
                              size: .iconSm,
                              semanticLabel: 'Show sidebar',
                              onPressed: () => SidebarLayout.of(context).toggle(),
                              // The title's size, so the two read as one line.
                              child: const AshlarIcon(AshlarIconsRoundedStroke.panelLeft, size: 16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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

/// A snooze's end as people say it: "6:40 PM", or "tomorrow at 9:00 AM".
String _when(DateTime t) {
  final now = DateTime.now();
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final time = '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day).difference(today).inDays;
  return switch (day) {
    0 => time,
    1 => 'tomorrow at $time',
    _ => '${t.month}/${t.day} at $time',
  };
}

/// Notifications are on in Helmy, but the system blocks them: said where it
/// shows, with the way to allow them, or to stop asking.
class _NotificationsBlocked extends StatelessWidget {
  const _NotificationsBlocked({required this.viewModel});
  final SidebarViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Container(
      margin: const .only(bottom: 8),
      padding: const .all(10),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 8,
        children: [
          Text(
            "Notifications are blocked for Helmy, so I can't tell you when work finishes "
            'or needs you.',
            style: t.text.xs,
          ),
          Row(
            spacing: 6,
            children: [
              Button(
                variant: .outline,
                size: .xs,
                onPressed: viewModel.allowNotifications,
                child: const Text('Allow'),
              ),
              Button(
                variant: .ghost,
                size: .xs,
                onPressed: viewModel.turnOffNotifications,
                child: const Text("I don't want them"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// While Helmy is in front, another session finishing or needing you is said
/// here, as a toast that opens it, rather than as a system notification.
class _InAppNotes extends StatefulWidget {
  const _InAppNotes({required this.viewModel, required this.child});
  final SidebarViewModel viewModel;
  final Widget child;

  @override
  State<_InAppNotes> createState() => _InAppNotesState();
}

class _InAppNotesState extends State<_InAppNotes> {
  StreamSubscription<({String sessionId, String title, String body})>? _notes;

  @override
  void initState() {
    super.initState();
    _notes = widget.viewModel.inApp.listen((n) {
      if (!mounted) return;
      showToast(
        context,
        title: n.title,
        description: n.body,
        action: Button(
          size: .sm,
          variant: .outline,
          onPressed: () => context.go('/s/${n.sessionId}'),
          child: const Text('Open'),
        ),
      );
    });
  }

  @override
  void dispose() {
    unawaited(_notes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
