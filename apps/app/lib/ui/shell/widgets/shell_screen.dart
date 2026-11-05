import '../../core/ashlar/hover_card.dart';

import 'dart:io';
import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../routing/settings_route.dart';

import '../../../data/repositories/chat_keeper.dart';
import '../../../domain/chat_icons.dart';
import '../../core/tinted_icon.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/session.dart';
import '../../../utils/format.dart';
import '../../../domain/models/settings.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/context_menu.dart';
import '../../core/ashlar/dropdown_menu.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/sidebar.dart';
import '../../core/helmy_dialog.dart';
import '../../core/ashlar/dialog.dart';
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
    this.inPullRequests = false,
  });

  final bool inSchedule;
  final bool inPullRequests;

  final SidebarViewModel viewModel;
  final String? selectedId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return _InAppNotes(
      viewModel: viewModel,
      child: Listener(
        // A mouse's own back and forward buttons, as in a browser.
        onPointerDown: (e) {
          if (e.buttons & kBackMouseButton != 0) NavHistory.current?.back();
          if (e.buttons & kForwardMouseButton != 0) NavHistory.current?.forward();
        },
        child: CallbackShortcuts(
          // Keys reach here from wherever focus is in the window.
          bindings: {
            Desktop.current.shortcut(LogicalKeyboardKey.keyK): () =>
                showPalette(context, viewModel),
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
            // Undo the last archive, snooze or settle (a text field's own undo
            // comes first).
            Desktop.current.shortcut(LogicalKeyboardKey.keyZ): viewModel.undo,
            // Esc lets picked chats go.
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (viewModel.picking) viewModel.clearPicks();
            },
            // A Mac's menu quits with ⌘Q; elsewhere Ctrl+Q is the app's to give.
            if (!Desktop.current.commandIsMeta)
              Desktop.current.shortcut(LogicalKeyboardKey.keyQ): () =>
                  ServicesBinding.instance.exitApplication(AppExitType.required),
          },
          child: ListenableBuilder(
            listenable: viewModel,
            builder: (context, _) => _SidebarWidth(
              saved: viewModel.settings.sidebarWidth,
              beside:
                  viewModel.settings.sidebarOpen &&
                  MediaQuery.sizeOf(context).width >= narrowWindow,
              onSave: (w) => viewModel.updateSettings(viewModel.settings.copyWith(sidebarWidth: w)),
              builder: (width) => SidebarLayout(
                rail: false,
                // Hides off the side; its button or ⌘B brings it back.
                collapse: .offcanvas,
                narrow: narrowWindow,
                open: viewModel.settings.sidebarOpen,
                onOpenChanged: (open) =>
                    viewModel.updateSettings(viewModel.settings.copyWith(sidebarOpen: open)),
                width: width,
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
                        const _BackForward(),
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
                      if (viewModel.notificationsBlocked)
                        _NotificationsBlocked(viewModel: viewModel),
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
                          label: 'New chat',
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
                        // Only where pull requests mean something (or while open).
                        if (viewModel.showPullRequests || inPullRequests)
                          _NavRow(
                            icon: AshlarIconsRoundedStroke.gitPullRequest,
                            label: 'Pull requests',
                            selected: inPullRequests,
                            onPressed: () => context.go('/pulls'),
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
                          child: viewModel.picking
                              ? _PickedBar(viewModel: viewModel)
                              : Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        switch (viewModel.settings.show) {
                                          .active => 'Chats',
                                          .archived => 'Archived',
                                          .all => 'All chats',
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
                                  // Earlier threads that seem to belong together: offered once.
                                  if (viewModel.suggestions case final found when found.isNotEmpty)
                                    _GroupingNotice(
                                      count: found.length,
                                      onReview: () => _review(context),
                                    ),
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
                                          style: t.text.xs.copyWith(
                                            color: t.colors.mutedForeground,
                                          ),
                                        ),
                                      ),
                                    for (final e in viewModel.entriesOf(g.sessions))
                                      _chatEntry(context, e),
                                  ],
                                  // What nothing waits on, out of the way.
                                  if (viewModel.settled case final done when done.isNotEmpty)
                                    _SettledSection(
                                      count: done.length,
                                      open: viewModel.settledOpen,
                                      more: viewModel.settledAll ? 0 : done.length - 10,
                                      onToggle: viewModel.toggleSettled,
                                      onMore: viewModel.showAllSettled,
                                      rows: [
                                        for (final e in viewModel.settledAll ? done : done.take(10))
                                          _chatEntry(context, e, compact: true),
                                      ],
                                    ),
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
                    viewModel.settings.sidebarOpen &&
                        MediaQuery.sizeOf(context).width >= narrowWindow
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
                                  child: const AshlarIcon(
                                    AshlarIconsRoundedStroke.panelLeft,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The one-time review: each suggested move, ticked to start with.
  Future<void> _review(BuildContext context) async {
    final found = viewModel.suggestions;
    final chosen = {for (final f in found) f.thread.id};
    final apply = await showAshlarDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final t = AshlarTheme.of(context);
          return HelmyDialog(
            title: 'Put earlier threads together?',
            body:
                'Before chats, each conversation stood alone. These seem to belong with '
                'another: together, a chat knows what its threads decided. Nothing moves '
                'that you untick, and any thread can be moved back later.',
            icon: AshlarIconsRoundedStroke.messagesSquare,
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    for (final f in found)
                      Pressable(
                        onPressed: () => setState(
                          () => chosen.contains(f.thread.id)
                              ? chosen.remove(f.thread.id)
                              : chosen.add(f.thread.id),
                        ),
                        semanticLabel: '${f.thread.title} into ${f.into.title}',
                        builder: (context, state) => Padding(
                          padding: const .symmetric(vertical: 6),
                          child: Row(
                            spacing: 10,
                            children: [
                              AshlarIcon(
                                chosen.contains(f.thread.id)
                                    ? AshlarIconsRoundedStroke.squareCheck
                                    : AshlarIconsRoundedStroke.square,
                                size: 16,
                                color: t.colors.foreground,
                              ),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(text: f.thread.title),
                                      TextSpan(
                                        text: '  into  ',
                                        style: TextStyle(color: t.colors.mutedForeground),
                                      ),
                                      TextSpan(
                                        text: f.into.title,
                                        style: const TextStyle(fontWeight: .w600),
                                      ),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: .ellipsis,
                                  style: t.text.sm,
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
            actions: [
              DialogButton('Not now', onPressed: () => Navigator.pop(context, false)),
              DialogButton(
                chosen.isEmpty ? 'Leave them' : 'Put ${chosen.length} together',
                main: true,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          );
        },
      ),
    );
    if (apply == null) return;
    // "Not now" or "Leave them": the review is done, nothing moved.
    await viewModel.applySuggestions(
      apply
          ? [
              for (final f in found)
                if (chosen.contains(f.thread.id)) f,
            ]
          : const [],
    );
  }

  /// One chat's row, with what can be done with it on a right click: done
  /// to the whole chat, every thread in it.
  Widget _chatEntry(
    BuildContext context,
    ({Chat? chat, List<Session> threads}) e, {
    bool compact = false,
  }) {
    final first = e.threads.first;
    final all = viewModel.chatOf(first);
    final title = viewModel.titleOf(e);
    final pinned = e.threads.any((t) => t.pinned);
    final snoozed = e.threads.every((t) => t.snoozed);
    final archived = e.threads.every((t) => t.archived);
    final settled = e.chat?.settled ?? false;
    final canSettle = e.chat != null && !settled && !viewModel.busyChat(all);
    Future<void> settle() async {
      await viewModel.settleChat(all);
      if (!context.mounted) return;
      showToast(
        context,
        title: 'Marked "$title" as done',
        action: Button(
          size: .sm,
          variant: .outline,
          onPressed: viewModel.undo,
          child: Text('Undo (${Desktop.current.keys('⌘Z')})'),
        ),
      );
    }

    return ContextMenu(
      items: [
        if (canSettle)
          MenuItem(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.circleCheck, size: 16),
            onPressed: settle,
            child: const Text('Mark as done'),
          ),
        if (settled)
          MenuItem(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.cornerUpLeft, size: 16),
            onPressed: () => viewModel.unsettleChat(all),
            child: const Text('Not done'),
          ),
        if (e.threads.any((t) => viewModel.isUnread(t.id)))
          MenuItem(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.check, size: 16),
            onPressed: () => viewModel.markChatRead(all),
            child: const Text('Mark as read'),
          ),
        MenuItem(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.pin, size: 16),
          onPressed: () => viewModel.setChatPinned(all, !pinned),
          child: Text(pinned ? 'Unpin' : 'Pin'),
        ),
        if (snoozed)
          MenuItem(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.clock, size: 16),
            onPressed: () => viewModel.wakeChat(all),
            child: const Text('Wake now'),
          )
        else ...[
          for (final (label, until) in [
            ('Snooze for an hour', DateTime.now().add(const Duration(hours: 1))),
            ('Snooze until tomorrow', SidebarViewModel.tomorrowMorning()),
          ])
            MenuItem(
              leading: const AshlarIcon(AshlarIconsRoundedStroke.clock, size: 16),
              onPressed: () async {
                await viewModel.snoozeChat(all, until);
                if (!context.mounted) return;
                showToast(
                  context,
                  title: 'Snoozed "$title" until ${_when(until)}',
                  action: Button(
                    size: .sm,
                    variant: .outline,
                    onPressed: viewModel.undo,
                    child: Text('Undo (${Desktop.current.keys('⌘Z')})'),
                  ),
                );
              },
              child: Text(label),
            ),
        ],
        MenuItem(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.archive, size: 16),
          onPressed: () async {
            await viewModel.setChatArchived(all, !archived);
            if (archived || !context.mounted) return;
            showToast(
              context,
              title: 'Archived "$title"',
              action: Button(
                size: .sm,
                variant: .outline,
                onPressed: viewModel.undo,
                child: Text('Undo (${Desktop.current.keys('⌘Z')})'),
              ),
            );
          },
          child: Text(archived ? 'Unarchive' : 'Archive'),
        ),
        if (e.chat case final chat?)
          MenuItem(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.messagesSquare, size: 16),
            onPressed: () => context.go('/c/${chat.id}'),
            child: const Text('Brief and places'),
          ),
        const MenuSeparator(),
        MenuItem(
          destructive: true,
          leading: const AshlarIcon(AshlarIconsRoundedStroke.trash, size: 16),
          onPressed: () => _deleteChat(context, title, all),
          child: const Text('Delete'),
        ),
      ],
      child: compact
          ? _SettledRow(
              chat: e.chat,
              title: title,
              threads: e.threads,
              selected: all.any((t) => t.id == selectedId),
              onOpen: () => context.go('/s/${first.id}'),
            )
          // Rested on: a preview of it, beside the list. Dragged onto another
          // chat, it joins it.
          : _DragChat(
              viewModel: viewModel,
              chat: e.chat,
              threads: all,
              title: title,
              child: HoverCard(
                openDelay: const Duration(milliseconds: 800),
                side: .right,
                align: .start,
                width: 320,
                content: (context) => _ChatPreviewCard(
                  title: title,
                  chat: e.chat,
                  preview: viewModel.previewOf(e.threads),
                ),
                child: _ChatRow(
                  onSettle: canSettle ? settle : null,
                  title: title,
                  threads: e.threads,
                  activity: viewModel.activityOfAll(e.threads),
                  chat: e.chat,
                  line: viewModel.lineOf(first, about: e.chat?.description ?? ''),
                  selected: viewModel.picking
                      ? viewModel.isPicked(first)
                      : all.any((t) => t.id == selectedId),
                  onOpen: () => _openOrPick(context, first),
                  onDelete: () => _deleteChat(context, title, all),
                ),
              ),
            ),
    );
  }

  /// A click opens the chat; ⌘-click picks it too, ⇧-click a run up to it.
  /// While some are picked, a plain click picks as well.
  void _openOrPick(BuildContext context, Session first) {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) return viewModel.pick(first, range: true);
    if (Desktop.current.commandHeld || viewModel.picking) return viewModel.pick(first);
    context.go('/s/${first.id}');
  }

  Future<void> _deleteChat(BuildContext context, String title, List<Session> all) async {
    final threads = all.where((t) => t.sideOf == null).length;
    final ok =
        !viewModel.settings.confirmDelete ||
        await confirm(
          context,
          title: 'Delete this chat?',
          body: threads > 1
              ? '"$title" and its $threads threads leave Helmy. Files in their folders stay as they are.'
              : '"$title" and its conversation leave Helmy. Files in the folder stay as they are.',
          action: 'Delete',
          destructive: true,
        );
    if (!ok) return;
    await viewModel.deleteChat(all);
    if (context.mounted && all.any((t) => t.id == selectedId)) context.go('/');
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
          semanticLabel: 'Show, group and sort chats',
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

/// A chat's row: where it works and when, its title, and what it waits on
/// or how its latest thread last answered.
class _ChatRow extends StatefulWidget {
  const new({
    required this.title,
    required this.threads,
    required this.activity,
    required this.line,
    required this.selected,
    required this.onOpen,
    required this.onDelete,
    this.onSettle,
    this.chat,
  });

  final String title;

  /// The chat: its topic and icon; null where there are no chats.
  final Chat? chat;

  /// Settles the chat; null when something in it still goes on.
  final VoidCallback? onSettle;

  /// Its threads in the list, the one it opens to first.
  final List<Session> threads;
  final SessionActivity activity;
  final ({String text, int added, int removed}) line;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  State<_ChatRow> createState() => _ChatRowState();
}

class _ChatRowState extends State<_ChatRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final s = widget.threads.first;
    final muted = t.text.xs.copyWith(color: c.mutedForeground);
    final line = widget.line;
    final places = {for (final x in widget.threads) projectName(x.ownCopy ? x.repo! : x.cwd)};
    final count = widget.threads.where((x) => x.sideOf == null).length;
    final title = widget.title;
    final topic = widget.chat?.topic ?? '';
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Pressable(
        onPressed: widget.onOpen,
        semanticLabel: [
          title,
          'in ${places.join(', ')}',
          if (count > 1) '$count threads',
          switch (widget.activity) {
            .working => 'working',
            .needsYou => 'needs you',
            .unread => 'finished while you were away',
            .idle => '',
          },
          line.text,
        ].where((x) => x.isNotEmpty).join(', '),
        selected: widget.selected,
        builder: (context, state) => AnimatedContainer(
          duration: t.duration,
          padding: const .fromLTRB(10, 8, 10, 9),
          decoration: BoxDecoration(
            color: widget.selected
                ? c.sidebarAccent
                : state.hovered
                ? c.sidebarAccent.withValues(alpha: .5)
                : c.sidebarAccent.withValues(alpha: 0),
            borderRadius: .circular(t.radiusMd),
            boxShadow: [if (state.focused) BoxShadow(color: c.sidebarRing, spreadRadius: 2)],
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 3,
            children: [
              // The project, and when; or a way to delete, under the mouse.
              Row(
                spacing: 8,
                children: [
                  _ProjectBadge(
                    name: topic.isEmpty ? 'No project' : topic,
                    activity: widget.activity,
                    icon: chatIconOf(widget.chat?.icon),
                  ),
                  // What it falls under, in a word (the folder is in its preview);
                  // until Helmy has named it, where it works.
                  Expanded(
                    child: Text(
                      topic.isEmpty ? places.join(', ') : topic,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: muted,
                    ),
                  ),
                  if (widget.threads.any((x) => x.pinned))
                    AshlarIcon(AshlarIconsRoundedStroke.pin, size: 11, color: c.mutedForeground),
                  if (_hovered && (widget.activity == .idle || widget.activity == .unread)) ...[
                    if (widget.onSettle case final onSettle?)
                      SizedBox(
                        height: 16,
                        child: Tooltip(
                          message: 'Mark as done',
                          child: Button(
                            variant: .ghost,
                            size: .iconXs,
                            semanticLabel: 'Mark $title as done',
                            onPressed: onSettle,
                            child: const AshlarIcon(AshlarIconsRoundedStroke.circleCheck, size: 13),
                          ),
                        ),
                      ),
                    SizedBox(
                      height: 16,
                      child: Button(
                        variant: .ghost,
                        size: .iconXs,
                        semanticLabel: 'Delete $title',
                        onPressed: widget.onDelete,
                        child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 13),
                      ),
                    ),
                  ] else
                    Text(ago(s.updatedAt), style: muted),
                ],
              ),
              Text(
                title,
                maxLines: 1,
                overflow: .ellipsis,
                style: t.text.sm.copyWith(
                  color: c.sidebarForeground,
                  fontWeight: widget.selected || widget.activity == .unread ? .w600 : .w500,
                ),
              ),
              // What it waits on or does, or how it answered; and its changes.
              if (line.text.isNotEmpty || line.added + line.removed > 0 || s.branch != null)
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Text(
                        line.text.isNotEmpty ? line.text : (s.branch ?? ''),
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: muted.copyWith(
                          color: widget.activity == .needsYou ? c.foreground : c.mutedForeground,
                        ),
                      ),
                    ),
                    if (line.added + line.removed > 0)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '+${line.added}',
                              style: const TextStyle(color: Color(0xFF3FB950)),
                            ),
                            const TextSpan(text: ' '),
                            TextSpan(
                              text: '−${line.removed}',
                              style: const TextStyle(color: Color(0xFFF85149)),
                            ),
                          ],
                        ),
                        style: muted.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A project's badge: its initials on a color of its own, the same for the
/// same folder everywhere. Working, it spins; needing you, or finished while
/// you were away, it carries a dot.
class _ProjectBadge extends StatelessWidget {
  const _ProjectBadge({required this.name, required this.activity, this.icon});
  final String name;
  final SessionActivity activity;

  /// Drawn instead of the initials: a chat's icon, in its topic's color.
  final IconData? icon;

  String get _initials {
    final words = name.split(RegExp(r'[\s_\-.]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      return words.first.substring(0, words.first.length.clamp(1, 2)).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final dark = t.brightness == Brightness.dark;
    final hue = hueOf(name);
    final ink = tintInk(hue, dark: dark);
    final fill = tintFill(hue, dark: dark);
    return SizedBox.square(
      dimension: 18,
      child: Stack(
        clipBehavior: .none,
        children: [
          Positioned.fill(
            child: activity == .working
                ? Padding(
                    padding: const .all(2),
                    child: Spinner(size: 14, semanticLabel: 'Working'),
                  )
                : Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: name == 'No project' ? c.muted : fill,
                      borderRadius: .circular(4),
                    ),
                    // No project: a plain mark rather than initials, which
                    // would read as a project's.
                    child: name == 'No project'
                        ? AshlarIcon(
                            icon ?? AshlarIconsRoundedStroke.messageCircle,
                            size: icon == null ? 11 : 12,
                            color: c.mutedForeground,
                          )
                        : icon != null
                        ? AshlarIcon(icon!, size: 12, color: ink)
                        : Text(
                            _initials,
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: ink,
                              height: 1,
                              letterSpacing: .2,
                            ),
                          ),
                  ),
          ),
          if (activity == .needsYou || activity == .unread)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: activity == .needsYou ? c.primary : c.foreground,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.sidebar, width: 1.5),
                ),
              ),
            ),
        ],
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

/// The sidebar at the width last dragged to: its edge, while it sits beside
/// the page, drags it wider or narrower, and the width is kept when let go.
class _SidebarWidth extends StatefulWidget {
  const _SidebarWidth({
    required this.saved,
    required this.beside,
    required this.onSave,
    required this.builder,
  });
  final double saved;
  final bool beside;
  final ValueChanged<double> onSave;
  final Widget Function(double width) builder;

  static const min = 220.0, max = 480.0;

  @override
  State<_SidebarWidth> createState() => _SidebarWidthState();
}

class _SidebarWidthState extends State<_SidebarWidth> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    final width = (_dragging ?? widget.saved).clamp(_SidebarWidth.min, _SidebarWidth.max);
    return Stack(
      children: [
        widget.builder(width),
        if (widget.beside)
          Positioned(
            // On the page's side of the edge, clear of the sidebar's own scrollbar.
            left: width - 2,
            top: 0,
            bottom: 0,
            width: 10,
            child: Semantics(
              label: 'Sidebar width',
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                // Lit only while dragged, as the panel's edge is.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Follows the pointer from where it was pressed.
                  dragStartBehavior: DragStartBehavior.down,
                  onHorizontalDragUpdate: (d) =>
                      setState(() => _dragging = (_dragging ?? width) + d.delta.dx),
                  onHorizontalDragEnd: (_) {
                    // The width now, not as of the last frame.
                    widget.onSave(
                      (_dragging ?? widget.saved).clamp(_SidebarWidth.min, _SidebarWidth.max),
                    );
                    setState(() => _dragging = null);
                  },
                  // Double-click: back to its usual width.
                  onDoubleTap: () => widget.onSave(272),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 2,
                      color: _dragging != null
                          ? c.foreground.withValues(alpha: .3)
                          : const Color(0x00000000),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Back and forward through where you have been, as a browser's: by these,
/// by ⌘[ and ⌘], and by a mouse's own back and forward buttons.
class _BackForward extends StatelessWidget {
  const _BackForward();

  @override
  Widget build(BuildContext context) {
    final history = NavHistory.current;
    if (history == null) return const SizedBox.shrink();
    Widget arrow(String label, String keys, IconData icon, bool can, VoidCallback go) => Tooltip(
      message: '$label (${Desktop.current.keys(keys)})',
      child: Button(
        variant: .ghost,
        size: .iconSm,
        semanticLabel: label,
        onPressed: can ? go : null,
        child: AshlarIcon(icon, size: 15),
      ),
    );
    return ListenableBuilder(
      listenable: history,
      builder: (context, _) => Row(
        mainAxisSize: .min,
        children: [
          arrow('Back', '⌘[', AshlarIconsRoundedStroke.arrowLeft, history.canBack, history.back),
          arrow(
            'Forward',
            '⌘]',
            AshlarIconsRoundedStroke.arrowRight,
            history.canForward,
            history.forward,
          ),
        ],
      ),
    );
  }
}

/// A chat of several threads in the list: its title, how many threads and
/// where, the latest one's line, the busiest one's state. Opening it opens
/// the latest thread; the arrow shows its threads beneath.
/// The one-time review, offered quietly at the top of the list.
class _GroupingNotice extends StatelessWidget {
  const _GroupingNotice({required this.count, required this.onReview});
  final int count;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: onReview,
      semanticLabel: 'Review $count earlier threads that seem to belong together',
      builder: (context, state) => Container(
        margin: const .only(bottom: 6),
        padding: const .fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: state.hovered ? c.sidebarAccent : c.sidebarAccent.withValues(alpha: .5),
          borderRadius: .circular(t.radiusMd),
        ),
        child: Row(
          spacing: 8,
          children: [
            AshlarIcon(AshlarIconsRoundedStroke.messagesSquare, size: 14, color: c.mutedForeground),
            Expanded(
              child: Text(
                '$count earlier thread${count == 1 ? '' : 's'} seem${count == 1 ? 's' : ''} to belong together',
                style: t.text.xs.copyWith(color: c.sidebarForeground),
              ),
            ),
            Text(
              'Review',
              style: t.text.xs.copyWith(fontWeight: .w600, color: c.sidebarForeground),
            ),
          ],
        ),
      ),
    );
  }
}

/// The settled chats, at the bottom of the list: a line with how many,
/// opened to compact rows, the latest ten and then the rest on asking.
class _SettledSection extends StatelessWidget {
  const _SettledSection({
    required this.count,
    required this.open,
    required this.more,
    required this.onToggle,
    required this.onMore,
    required this.rows,
  });

  final int count;
  final bool open;

  /// How many more there are than shown.
  final int more;
  final VoidCallback onToggle, onMore;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final style = t.text.xs.copyWith(color: c.mutedForeground, fontWeight: .w500);
    return Padding(
      padding: const .only(top: 14),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 1,
        children: [
          Pressable(
            onPressed: onToggle,
            semanticLabel: open ? 'Hide done chats' : 'Show $count done chats',
            builder: (context, state) => Container(
              padding: const .fromLTRB(10, 6, 8, 6),
              decoration: BoxDecoration(
                color: state.hovered ? c.sidebarAccent.withValues(alpha: .5) : null,
                borderRadius: .circular(t.radiusMd),
              ),
              child: Row(
                spacing: 6,
                children: [
                  Expanded(child: Text('Done', style: style)),
                  Text('$count', style: style),
                  AshlarIcon(
                    open
                        ? AshlarIconsRoundedStroke.chevronDown
                        : AshlarIconsRoundedStroke.chevronRight,
                    size: 13,
                    color: c.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            ...rows,
            if (more > 0)
              Pressable(
                onPressed: onMore,
                semanticLabel: 'Show $more more',
                builder: (context, state) => Container(
                  padding: const .fromLTRB(10, 7, 10, 7),
                  decoration: BoxDecoration(
                    color: state.hovered ? c.sidebarAccent.withValues(alpha: .5) : null,
                    borderRadius: .circular(t.radiusMd),
                  ),
                  child: Row(
                    spacing: 8,
                    children: [
                      AshlarIcon(
                        AshlarIconsRoundedStroke.chevronDown,
                        size: 13,
                        color: c.mutedForeground,
                      ),
                      Text(
                        'Show $more more',
                        style: t.text.sm.copyWith(color: c.sidebarForeground),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// A settled chat: its project's badge, quiet; its title; how long ago.
class _SettledRow extends StatelessWidget {
  const _SettledRow({
    this.chat,
    required this.title,
    required this.threads,
    required this.selected,
    required this.onOpen,
  });

  final Chat? chat;
  final String title;
  final List<Session> threads;
  final bool selected;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final s = threads.first;
    return Pressable(
      onPressed: onOpen,
      selected: selected,
      semanticLabel: '$title, done',
      builder: (context, state) => Container(
        padding: const .fromLTRB(10, 7, 10, 7),
        decoration: BoxDecoration(
          color: selected
              ? c.sidebarAccent
              : state.hovered
              ? c.sidebarAccent.withValues(alpha: .5)
              : null,
          borderRadius: .circular(t.radiusMd),
        ),
        child: Row(
          spacing: 8,
          children: [
            Opacity(
              opacity: .55,
              child: _ProjectBadge(
                name: chat?.topic.isNotEmpty ?? false ? chat!.topic : 'No project',
                activity: .idle,
                icon: chatIconOf(chat?.icon),
              ),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: .ellipsis,
                style: t.text.sm.copyWith(color: c.mutedForeground),
              ),
            ),
            Text(ago(s.updatedAt), style: t.text.xs.copyWith(color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}

/// A chat's preview, after resting on its row: where it works, what it has
/// come to, its last exchanges, its pictures, pages and changes. Read from
/// what is on disk; nothing is asked of a model.
class _ChatPreviewCard extends StatelessWidget {
  const _ChatPreviewCard({required this.title, required this.chat, required this.preview});

  final String title;
  final Chat? chat;
  final ChatPreview preview;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.xs.copyWith(color: c.mutedForeground);
    final p = preview;
    Widget heading(String text) => Padding(
      padding: const .only(top: 4),
      child: Text(text, style: muted.copyWith(fontWeight: .w600)),
    );
    return Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      spacing: 6,
      children: [
        Row(
          spacing: 8,
          children: [
            AshlarIcon(chatIconOf(chat?.icon), size: 16, color: c.foreground),
            Expanded(
              child: Text(
                [
                  if (chat?.topic.isNotEmpty ?? false) chat!.topic,
                  p.folders.map(pathEnd).join(', '),
                  if (p.threads > 1) '${p.threads} threads',
                ].join(' · '),
                maxLines: 1,
                overflow: .ellipsis,
                style: muted,
              ),
            ),
          ],
        ),
        Text(title, style: t.text.sm.copyWith(fontWeight: .w600)),
        if (chat?.description.isNotEmpty ?? false)
          Text(chat!.description, style: t.text.sm.copyWith(color: c.mutedForeground)),
        if (p.brief.isNotEmpty) ...[
          heading('Where it stands'),
          for (final line in p.brief)
            Text(line, style: t.text.xs, maxLines: 2, overflow: .ellipsis),
        ],
        if (p.exchanges.isNotEmpty) ...[
          heading('Lately'),
          for (final x in p.exchanges) ...[
            Text(
              x.asked,
              maxLines: 1,
              overflow: .ellipsis,
              style: t.text.xs.copyWith(fontWeight: .w500),
            ),
            Text(x.answered, maxLines: 2, overflow: .ellipsis, style: muted),
          ],
        ],
        if (p.images.isNotEmpty)
          Padding(
            padding: const .only(top: 4),
            child: Row(
              spacing: 6,
              children: [
                for (final path in p.images)
                  ClipRRect(
                    borderRadius: .circular(t.radiusMd),
                    child: Image.file(
                      File(path),
                      width: 60,
                      height: 60,
                      fit: .cover,
                      cacheWidth: 120,
                      // Gone from disk: not shown.
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
        if (p.links.isNotEmpty || p.added + p.removed > 0)
          Padding(
            padding: const .only(top: 4),
            child: Text(
              [
                if (p.links.isNotEmpty) p.links.join(', '),
                if (p.added + p.removed > 0) '+${p.added} −${p.removed} in files',
              ].join(' · '),
              maxLines: 2,
              overflow: .ellipsis,
              style: muted,
            ),
          ),
      ],
    );
  }
}

/// What can be done to the chats picked, in place of the list's heading.
class _PickedBar extends StatelessWidget {
  const _PickedBar({required this.viewModel});
  final SidebarViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final n = viewModel.pickedCount;
    Widget act(IconData icon, String label, VoidCallback onPressed) => Tooltip(
      message: label,
      child: Button(
        variant: .ghost,
        size: .iconSm,
        semanticLabel: label,
        onPressed: onPressed,
        child: AshlarIcon(icon, size: 15),
      ),
    );
    ChatKeeper? keeper;
    try {
      keeper = context.read<ChatKeeper>();
    } on ProviderNotFoundException {
      keeper = null;
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            '$n ${n == 1 ? 'chat' : 'chats'} picked',
            style: t.text.xs.copyWith(color: t.colors.foreground, fontWeight: .w600),
          ),
        ),
        act(AshlarIconsRoundedStroke.circleCheck, 'Mark as done', viewModel.markPickedDone),
        act(
          AshlarIconsRoundedStroke.clock,
          'Snooze until tomorrow',
          () => viewModel.snoozePicked(SidebarViewModel.tomorrowMorning()),
        ),
        act(AshlarIconsRoundedStroke.archive, 'Archive', viewModel.archivePicked),
        if (keeper case final k?)
          act(
            AshlarIconsRoundedStroke.sparkles,
            'Name again',
            () => viewModel.renamePicked(k.describe),
          ),
        act(AshlarIconsRoundedStroke.trash, 'Delete', () async {
          final ok = await confirm(
            context,
            title: 'Delete $n ${n == 1 ? 'chat' : 'chats'}?',
            body: 'Their conversations leave Helmy. Files in their folders stay as they are.',
            action: 'Delete',
            destructive: true,
          );
          if (ok) await viewModel.deletePicked();
        }),
        act(AshlarIconsRoundedStroke.x, 'Stop picking', viewModel.clearPicks),
      ],
    );
  }
}

/// A chat's row that can be dragged onto another chat's, to join it: its
/// threads then belong to that chat, which can read and message them.
class _DragChat extends StatelessWidget {
  const _DragChat({
    required this.viewModel,
    required this.chat,
    required this.threads,
    required this.title,
    required this.child,
  });

  final SidebarViewModel viewModel;
  final Chat? chat;
  final List<Session> threads;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final target = chat;
    Widget row = Draggable<({List<Session> threads, String title})>(
      data: (threads: threads, title: title),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        padding: const .symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.popover,
          border: Border.all(color: c.border),
          borderRadius: .circular(t.radiusMd),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12)],
        ),
        child: Text(title, style: t.text.sm.copyWith(color: c.popoverForeground)),
      ),
      childWhenDragging: Opacity(opacity: .4, child: child),
      child: child,
    );
    if (target == null) return row;
    return DragTarget<({List<Session> threads, String title})>(
      onWillAcceptWithDetails: (d) => d.data.threads.first.chatId != target.id,
      onAcceptWithDetails: (d) async {
        await viewModel.mergeInto(d.data.threads, target.id);
        if (!context.mounted) return;
        showToast(
          context,
          title: 'Moved "${d.data.title}" into "${target.title}"',
          action: Button(
            size: .sm,
            variant: .outline,
            onPressed: viewModel.undo,
            child: Text('Undo (${Desktop.current.keys('⌘Z')})'),
          ),
        );
      },
      builder: (context, offered, _) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: offered.isEmpty ? const Color(0x00000000) : c.ring, width: 1.5),
          borderRadius: .circular(t.radiusMd),
        ),
        child: row,
      ),
    );
  }
}
