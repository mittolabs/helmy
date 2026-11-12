part of '../settings_screen.dart';

/// Chats put away: each can be brought back to the list or deleted.
class _Archive extends StatelessWidget {
  const _Archive();

  @override
  Widget build(BuildContext context) {
    final list = context.watch<SidebarViewModel?>();
    // Settings opened before the app's list was made (at launch, straight
    // here): what is archived is not known, so it is not said to be empty.
    if (list == null) {
      return const _Page(
        children: [
          _Heading('Archived chats', first: true),
          Empty(
            border: true,
            icon: AshlarIcon(AshlarIconsRoundedStroke.archive),
            title: Text('Archived chats show here'),
            description: Text('Close Settings and open it again to see them.'),
          ),
        ],
      );
    }
    final archived = list.entriesOf([
      for (final s in list.sessions)
        if (s.archived) s,
    ]);
    final confirmDelete = context.watch<SettingsRepository>().settings.confirmDelete;
    return _Page(
      children: [
        const _Heading('Archived chats', first: true),
        if (archived.isEmpty)
          const Empty(
            border: true,
            icon: AshlarIcon(AshlarIconsRoundedStroke.archive),
            title: Text('Nothing archived'),
            description: Text(
              'Chats you archive come here, out of the list, until you bring them back.',
            ),
          )
        else
          for (final e in archived)
            _Row(
              title: list.titleOf(e),
              description: [
                ago(e.threads.first.updatedAt, now: DateTime.now()),
                if (e.threads.length > 1) '${e.threads.length} threads',
                pathEnd(e.threads.first.cwd),
              ].join(' · '),
              control: Row(
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  Button(
                    variant: .outline,
                    size: .sm,
                    onPressed: () => list.setChatArchived(e.threads, false),
                    child: const Text('Unarchive'),
                  ),
                  Button(
                    variant: .ghost,
                    size: .sm,
                    semanticLabel: 'Delete ${list.titleOf(e)}',
                    onPressed: () async {
                      if (confirmDelete &&
                          !await confirm(
                            context,
                            title: 'Delete "${list.titleOf(e)}"?',
                            body: 'It is deleted for good.',
                            action: 'Delete',
                            destructive: true,
                          )) {
                        return;
                      }
                      await list.deleteChat(e.threads);
                    },
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
