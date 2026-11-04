import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../utils/format.dart';
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
  await showCommandDialog(
    context: context,
    placeholder: 'Search sessions and conversations, or run an action',
    groups: [
      CommandGroup(heading: 'Actions', [
        CommandItem(
          'New session',
          leading: const AshlarIcon(AshlarIconsRoundedStroke.squarePen, size: 16),
          shortcut: Desktop.current.keys('⌘N'),
          onSelected: () => newSession(context, vm),
        ),
        CommandItem(
          'Settings',
          leading: const AshlarIcon(AshlarIconsRoundedStroke.settings, size: 16),
          shortcut: Desktop.current.keys('⌘,'),
          onSelected: () => router.go('/settings'),
        ),
        CommandItem(
          'Memory',
          keywords: const ['claude.md', 'agents.md', 'instructions'],
          leading: const AshlarIcon(AshlarIconsRoundedStroke.brain, size: 16),
          onSelected: () => router.go('/settings?section=memory'),
        ),
        CommandItem(
          'Usage',
          keywords: const ['limits', 'agents', 'accounts'],
          leading: const AshlarIcon(AshlarIconsRoundedStroke.gauge, size: 16),
          onSelected: () => router.go('/settings?section=agents'),
        ),
      ]),
      CommandGroup(heading: 'Sessions', [
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
