part of '../settings_screen.dart';

/// Chats put away: each can be brought back to the list or deleted.
class _Archive extends StatelessWidget {
  const _Archive();

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final list = context.watch<SidebarViewModel?>();
    if (list == null) return const _Page(children: []);
    final archived = list.entriesOf([
      for (final s in list.sessions)
        if (s.archived) s,
    ]);
    final confirmDelete = context.watch<SettingsRepository>().settings.confirmDelete;
    return _Page(
      children: [
        const _Heading('Archived chats', first: true),
        if (archived.isEmpty)
          _Block(
            title: 'Nothing archived',
            child: Text(
              'Chats you archive come here, out of the list, until you bring them back.',
              style: muted,
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
                            body: 'Its conversation goes for good.',
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
