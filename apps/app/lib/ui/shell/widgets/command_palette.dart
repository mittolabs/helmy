import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/settings_route.dart';
import '../../settings/view_models/settings_view_model.dart';

import '../../../utils/format.dart';
import '../../../utils/result.dart';
import '../../core/ashlar/command.dart';
import '../view_models/sidebar_view_model.dart';
import 'new_session.dart';
import '../../../utils/platform.dart';

/// ⌘K: find a session by its name, its folder or anything said in it, or run
/// an action.
Future<void> showPalette(BuildContext context, SidebarViewModel vm) async {
  final index = await vm.searchIndex();
  if (!context.mounted) return;
  final router = GoRouter.of(context);
  // The session open now, for the actions that act on it.
  final openId =
      router.state.uri.pathSegments.length == 2 && router.state.uri.pathSegments[0] == 's'
      ? router.state.uri.pathSegments[1]
      : null;
  final open = vm.sessions.where((s) => s.id == openId).firstOrNull;
  await showCommandDialog(
    context: context,
    placeholder: 'Search chats, or run an action',
    groups: [
      if (open != null)
        CommandGroup(heading: 'This chat', [
          // (Not beside one without a project: its folder is its own.)
          if (!isScratch(open.cwd))
            CommandItem(
              'New chat in ${folderName(open.ownCopy ? open.repo! : open.cwd)}',
              description: 'Starts beside this one, in the same folder',
              leading: const AshlarIcon(AshlarIconsRoundedStroke.squarePen, size: 16),
              onSelected: () async {
                if (await vm.createIn(open.ownCopy ? open.repo! : open.cwd) case Ok(:final value)) {
                  router.go('/s/${value.id}');
                }
              },
            ),
          CommandItem(
            open.pinned ? 'Unpin' : 'Pin',
            description: open.title,
            leading: AshlarIcon(
              open.pinned ? AshlarIconsRoundedStroke.pinOff : AshlarIconsRoundedStroke.pin,
              size: 16,
            ),
            onSelected: () => vm.setPinned(open, !open.pinned),
          ),
          if (!vm.isSettled(open) && !vm.busyChat(vm.chatOf(open)))
            CommandItem(
              'Mark as done',
              description: open.title,
              keywords: const ['settle', 'finished', 'inbox'],
              leading: const AshlarIcon(AshlarIconsRoundedStroke.circleCheck, size: 16),
              onSelected: () => unawaited(vm.settleChat(vm.chatOf(open))),
            ),
          if (!open.archived)
            CommandItem(
              'Archive',
              description: open.title,
              keywords: const ['hide'],
              leading: const AshlarIcon(AshlarIconsRoundedStroke.archive, size: 16),
              onSelected: () {
                unawaited(vm.setArchived(open, true));
                router.go('/');
              },
            ),
        ]),
      CommandGroup(heading: 'Actions', [
        CommandItem(
          'New chat',
          leading: const AshlarIcon(AshlarIconsRoundedStroke.squarePen, size: 16),
          shortcut: Desktop.current.keys('⌘N'),
          onSelected: () => newSession(context, vm),
        ),
        CommandItem(
          'Pull requests',
          description: 'Open in the GitHub repositories your chats work in',
          keywords: const ['github', 'pr', 'review', 'merge'],
          leading: const AshlarIcon(AshlarIconsRoundedStroke.gitPullRequest, size: 16),
          onSelected: () => router.go('/pulls'),
        ),
        CommandItem(
          'Settings',
          leading: const AshlarIcon(AshlarIconsRoundedStroke.settings, size: 16),
          shortcut: Desktop.current.keys('⌘,'),
          onSelected: () => openSettings(router),
        ),
        CommandItem(
          'Memory',
          description: 'What every connection is told to remember',
          keywords: const ['claude.md', 'agents.md', 'instructions'],
          leading: const AshlarIcon(AshlarIconsRoundedStroke.brain, size: 16),
          onSelected: () => openSettings(router, SettingsSection.memory),
        ),
        CommandItem(
          'Usage',
          description: 'How much of each limit is left',
          keywords: const ['limits', 'agents', 'accounts'],
          leading: const AshlarIcon(AshlarIconsRoundedStroke.gauge, size: 16),
          onSelected: () => openSettings(router, SettingsSection.agents),
        ),
      ]),
      CommandGroup(heading: 'Threads', [
        for (final (s, text) in index)
          CommandItem(
            s.archived ? '${s.title} (archived)' : s.title,
            keywords: [tildePath(s.cwd), text],
            leading: const AshlarIcon(AshlarIconsRoundedStroke.messageSquare, size: 16),
            onSelected: () => router.go('/s/${s.id}'),
          ),
      ]),
    ],
  );
}
