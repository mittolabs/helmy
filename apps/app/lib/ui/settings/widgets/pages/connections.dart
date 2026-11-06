part of '../settings_screen.dart';

class _Agents extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = vm.settings;
    return _Page(
      children: [
        const _Heading('Connections', first: true),
        _Connections(vm: vm),
        const _Heading('Routing'),
        _Row(
          title: 'Move to a connection with more room',
          description:
              'Each message goes to a connection that can do what it asks, then to the one with '
              'the most of its usage limit left. A thread stays on its connection unless another '
              'has clearly more room, since each switch hands the conversation across.',
          control: SizedBox(
            width: 150,
            child: Select<Switching>(
              size: .sm,
              value: s.switching,
              semanticLabel: 'How readily to switch',
              options: [for (final w in Switching.values) SelectOption(w, w.label)],
              onChanged: (w) => vm.update(s.copyWith(switching: w)),
            ),
          ),
        ),
        const _Heading('Advanced'),
        ..._bestAt(vm),
        const _Heading('Local model'),
        _Row(
          title: 'Ollama model',
          description: vm.localModels == null
              ? 'Ollama is not running on ${Desktop.current.thisComputer}. With it running and a model pulled, '
                    'chats keep working with no internet, on that model.'
              : vm.localModels!.isEmpty
              ? 'Ollama is running but has no model. Pull one, for example: ollama pull gpt-oss:20b'
              : 'Answers only when no online connection can: when offline, or out of room. '
                    "Chats' names, summaries and briefs are written on the largest model here, at no "
                    'cost in usage.',
          control: vm.localModels == null || vm.localModels!.isEmpty
              ? const SizedBox.shrink()
              : SizedBox(
                  width: 220,
                  child: Select<String>(
                    size: .sm,
                    value: s.ollamaModel != null && vm.localModels!.contains(s.ollamaModel)
                        ? s.ollamaModel
                        : vm.localModels!.first,
                    semanticLabel: 'Ollama model',
                    options: [for (final m in vm.localModels!) SelectOption(m, m)],
                    onChanged: (m) => vm.update(s.copyWith(ollamaModel: m)),
                  ),
                ),
        ),
        const _Heading('Always allowed'),
        if (s.rules.isEmpty)
          const _Row(
            title: 'No rules yet',
            description:
                'Choose "Always allow" on an approval, and steps like it are allowed from then on.',
            control: SizedBox.shrink(),
          )
        else
          for (final r in s.rules)
            _Row(
              title: r.label,
              control: Button(
                size: .sm,
                variant: .ghost,
                onPressed: () => vm.update(s.copyWith(rules: [...s.rules]..remove(r))),
                child: const Text('Remove'),
              ),
            ),
      ],
    );
  }
}

/// The connections in a list, and the chosen one's details beside it.
class _Connections extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final chosen = vm.chosen;
    final outdated = vm.outdated;
    String nameOf(String k) => switch (k) {
      'claude' => 'Claude Code',
      'codex' => 'Codex',
      _ => 'Ollama',
    };
    final list = Column(
      crossAxisAlignment: .stretch,
      children: [
        // Newer versions out: all of them a press away, as T3 Code has it.
        if (outdated.isNotEmpty)
          Container(
            padding: const .fromLTRB(16, 10, 10, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    'Updates for ${[for (final k in outdated) nameOf(k)].join(', ')}',
                    style: t.text.xs.copyWith(color: c.mutedForeground),
                  ),
                ),
                Button(
                  size: .xs,
                  onPressed: vm.updating.isNotEmpty
                      ? null
                      : () async {
                          final wanted = outdated.length;
                          final done = await vm.updateAll();
                          if (!context.mounted) return;
                          showToast(
                            context,
                            title: done == wanted ? 'Up to date' : 'Not every update went',
                            description: done == wanted
                                ? 'Each connection is on its newest version.'
                                : 'Choose the one still behind to see why, and update it there.',
                            type: done == wanted ? .success : .error,
                          );
                        },
                  child: Text(vm.updating.isNotEmpty ? 'Updating...' : 'Update all'),
                ),
              ],
            ),
          ),
        for (final a in vm.used)
          _ConnectionItem(
            row: a,
            icon: vm.iconOf(a.info.id),
            checked: vm.checked,
            selected: a.info.id == chosen?.info.id,
            onPressed: () => vm.chooseAgent(a.info.id),
          ),
        _AddConnection(vm: vm),
      ],
    );
    final detail = chosen == null
        ? Padding(
            padding: const .all(18),
            child: Text(
              'No connection yet. Add one, and it is installed and signed in with one press.',
              style: t.text.sm.copyWith(color: c.mutedForeground),
            ),
          )
        : _AgentCard(row: chosen, checked: vm.checked, vm: vm);
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: .circular(t.radiusLg),
      ),
      clipBehavior: .antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          // Narrow: the details under the list.
          if (box.maxWidth < 560) {
            return Column(
              crossAxisAlignment: .stretch,
              children: [
                list,
                Container(height: 1, color: c.border),
                detail,
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: .stretch,
              children: [
                Container(
                  width: 250,
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: c.border)),
                  ),
                  child: list,
                ),
                Expanded(child: detail),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The list's last row: adding a connection, in a dialog over Settings.
class _AddConnection extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: () => addConnection(context, vm),
      semanticLabel: 'Add a connection',
      builder: (context, state) => Container(
        padding: const .symmetric(horizontal: 16, vertical: 14),
        color: state.hovered ? c.accent.withValues(alpha: .5) : null,
        child: Row(
          spacing: 10,
          children: [
            AshlarIcon(AshlarIconsRoundedStroke.plus, size: 16, color: c.mutedForeground),
            Flexible(child: Text('Add a connection', style: t.text.sm)),
          ],
        ),
      ),
    );
  }
}

/// One connection in the list: its name and how it is.
class _ConnectionItem extends StatelessWidget {
  const new({
    required this.row,
    required this.checked,
    required this.selected,
    required this.onPressed,
    this.icon,
  });
  final AgentRow row;

  /// An agent's icon, from the registry.
  final String? icon;
  final bool checked, selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: row.info.name,
      builder: (context, state) => Container(
        padding: const .fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: selected
              ? c.accent
              : state.hovered
              ? c.accent.withValues(alpha: .5)
              : null,
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(
          spacing: 10,
          children: [
            ConnectionLogo(row.info.id, icon: icon, size: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text(
                    row.info.name,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: t.text.sm.copyWith(fontWeight: .w500),
                  ),
                  Text(
                    _AgentCard.statusOf(row, checked),
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: t.text.xs.copyWith(color: c.mutedForeground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const new({required this.row, required this.checked, required this.vm});
  final AgentRow row;
  final bool checked;
  final SettingsViewModel vm;

  static String _until(DateTime when, DateTime now) {
    final d = when.difference(now);
    if (d.inMinutes < 1) return 'in a moment';
    if (d.inHours < 1) return 'in ${d.inMinutes}m';
    if (d.inDays < 1) return 'in ${d.inHours}h ${d.inMinutes % 60}m';
    return 'in ${d.inDays}d ${d.inHours % 24}h';
  }

  /// How [row] is, in a few words.
  static String statusOf(AgentRow row, bool checked) => !checked
      ? 'Checking...'
      : row.problem ??
            (row.downUntil != null
                ? 'Resting after a failure, back ${_until(row.downUntil!, DateTime.now())}'
                : row.enabled
                ? 'Ready'
                : 'Turned off: no messages go to it');

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground);
    final now = DateTime.now();
    final usage = row.usage;
    // Ready rests on a sign-in: whose, said with it.
    final signedIn = vm.who[row.info.id];
    final status = statusOf(row, checked) == 'Ready' && signedIn != null
        ? 'Ready, signed in as $signedIn'
        : statusOf(row, checked);
    final can = [
      for (final c in row.info.capabilities)
        if (c != Capability.tools) c.label,
    ];
    final connections = vm.connectionsOf(row.info.id);
    return Padding(
      padding: const .all(18),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 12,
            children: [
              ConnectionLogo(row.info.id, icon: vm.iconOf(row.info.id), size: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(row.info.name, style: t.text.base.copyWith(fontWeight: .w600)),
                    Text(status, style: muted),
                  ],
                ),
              ),
              // A problem says its fix where it shows, and the fix runs here.
              if (row.problem != null)
                if (vm.fixFor(row.info.id) case final fix?)
                  Button(
                    variant: .outline,
                    size: .sm,
                    onPressed: vm.working != null
                        ? null
                        : () async {
                            final why = await vm.fixConnection(row.info.id);
                            if (!context.mounted || why == null) return;
                            showToast(
                              context,
                              title: "${row.info.name} isn't ready",
                              description: why,
                              type: .error,
                            );
                          },
                    leading: vm.working == row.info.id ? const Spinner(size: 14) : null,
                    child: Text(fix),
                  ),
            ],
          ),
          if (ConnectionsSetup.kindOf(row.info.id) case final kind?) ...[
            _Version(vm: vm, kind: kind),
            _Program(vm: vm, kind: kind),
          ],
          if (row.info.localOnly)
            Text('No usage limit: it runs on ${Desktop.current.thisComputer}.', style: muted)
          else if (row.info.assignedOnly)
            Text(
              'It reports no usage limits, so Helmy cannot tell how much room it has.',
              style: muted,
            )
          else if (usage == null)
            Text('No usage reported yet. It reports with its first answer.', style: muted)
          else ...[
            for (final w
                in usage.windows.isEmpty
                    ? [UsageWindow(name: 'Limit', used: usage.used, resetsAt: usage.resetsAt)]
                    : usage.windows)
              _Window(window: w, now: now, until: _until),
            if (usage.reportedAt != null)
              Text(
                'As of ${ago(usage.reportedAt!, now: now)} ago'.replaceAll(
                  'As of now ago',
                  'As of just now',
                ),
                style: muted,
              ),
          ],
          if (can.isNotEmpty) Text('Also can: ${can.join(', ')}', style: muted),
          if (!row.info.localOnly)
            Text(
              connections == null
                  ? 'Checking connections...'
                  : connections.isEmpty
                  ? 'No connected services'
                  : 'Connected: ${[for (final c in connections) c.label].join(', ')}',
              style: muted,
            ),
          // An agent added from the registry: what it is set best at.
          if (row.info.assignedOnly)
            Text(switch ([
              for (final k in WorkKind.values)
                if (vm.settings.bestFor(k) == row.info.id) k.label,
            ]) {
              [] => 'Answers nothing yet: set what it is best at under Advanced.',
              final kinds => 'Answers: ${kinds.join(', ')}.',
            }, style: muted),
          Padding(
            padding: const .only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // More accounts, more room: each has its own limits, and
                // Helmy moves between them as one runs low.
                if (SettingsViewModel.kindOf(row.info.id) case final kind?)
                  Button(
                    variant: .outline,
                    size: .sm,
                    onPressed: vm.adding != null ? null : () => addAccount(context, vm, kind),
                    leading: const AshlarIcon(AshlarIconsRoundedStroke.plus, size: 14),
                    child: const Text('Add an account'),
                  ),
                Button(
                  variant: .ghost,
                  size: .sm,
                  onPressed: () async {
                    final registry = row.info.assignedOnly;
                    final ours = vm.canRemove(row.info.id) || vm.madeByHelmy(row.info.id);
                    final group = vm.groupOf(row.info.id);
                    final sure = await confirm(
                      context,
                      title: 'Remove ${group.length > 1 ? 'Ollama' : row.info.name}?',
                      body: registry
                          ? (vm.madeByHelmy(row.info.id)
                                ? 'Helmy stops using it, and the copy Helmy installed goes.'
                                : 'Helmy stops using it. The program itself stays.')
                          : ours
                          ? 'Its sign-in on this Mac goes, and Helmy stops using it. '
                                'The account itself is not touched.'
                          : 'Helmy stops using it. It stays installed and signed in on this '
                                'Mac, and you can add it back from "Add a connection".',
                      action: 'Remove',
                      destructive: true,
                    );
                    if (!sure) return;
                    await (registry
                        ? vm.removeAccount(row.info.id)
                        : vm.removeConnection(row.info.id));
                  },
                  child: const Text('Remove from Helmy'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One usage window: how much is left, a bar with a mark where use would be
/// if spread evenly over the window, and when it resets.
class _Window extends StatelessWidget {
  const _Window({required this.window, required this.now, required this.until});
  final UsageWindow window;
  final DateTime now;
  final String Function(DateTime, DateTime) until;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final left = (1 - window.used).clamp(0.0, 1.0);
    final pace = window.paceAt(now);
    final ahead = pace != null && window.used > pace + .05;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 4,
      children: [
        // Name and what is left share the line; on a narrow window what is
        // left goes under the name rather than past the edge.
        Wrap(
          alignment: .spaceBetween,
          spacing: 8,
          children: [
            Text(window.name, style: t.text.xs.copyWith(fontWeight: .w500)),
            Text(
              [
                '${(left * 100).round()}% left',
                if (window.resetsAt != null && window.resetsAt!.isAfter(now))
                  'resets ${until(window.resetsAt!, now)}',
              ].join('  ·  '),
              style: t.text.xs.copyWith(color: t.colors.mutedForeground),
            ),
          ],
        ),
        // No LayoutBuilder here: the card around it sizes by intrinsic
        // height, which cannot ask one.
        Builder(
          builder: (context) => SizedBox(
            height: 8,
            child: Stack(
              clipBehavior: .none,
              children: [
                Container(
                  decoration: BoxDecoration(color: t.colors.muted, borderRadius: .circular(4)),
                ),
                FractionallySizedBox(
                  widthFactor: window.used.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: ahead ? t.colors.destructive : t.colors.foreground,
                      borderRadius: .circular(4),
                    ),
                  ),
                ),
                if (pace != null)
                  Align(
                    alignment: FractionalOffset(pace.clamp(0.0, 1.0), .5),
                    child: OverflowBox(
                      maxHeight: 14,
                      child: Container(width: 2, height: 14, color: t.colors.mutedForeground),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Only worth saying when it matters; Helmy moves work elsewhere then.
        if (ahead)
          Text(
            'Used faster than this window allows; at this rate it runs out before it resets, '
            'and I lean on your other connections.',
            style: t.text.xs.copyWith(color: t.colors.mutedForeground),
          ),
      ],
    );
  }
}

/// Which version of a connection is installed, and whether a newer one is
/// out, with the update a press away. Unknown is said as unknown.
class _Version extends StatelessWidget {
  const _Version({required this.vm, required this.kind});
  final SettingsViewModel vm;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground);
    final v = vm.versions[kind];
    if (v == null) return Text('Checking its version...', style: muted);
    final installed = v.installed;
    if (installed == null) return const SizedBox.shrink();
    final latest = v.latest;
    if (latest == null) {
      return Text("Version $installed. Couldn't check for a newer one.", style: muted);
    }
    if (!ConnectionsSetup.newer(latest, installed)) {
      return Text('Version $installed, the newest.', style: muted);
    }
    final busy = vm.updating.contains(kind);
    return Row(
      spacing: 10,
      children: [
        Expanded(child: Text('Version $installed. $latest is out.', style: muted)),
        Button(
          variant: .outline,
          size: .sm,
          onPressed: busy
              ? null
              : () async {
                  final ok = await vm.updateConnection(kind);
                  if (!context.mounted || ok) return;
                  showToast(
                    context,
                    title: "The update didn't finish",
                    description: kind == 'ollama'
                        ? 'Its download page is open: install the newest from there.'
                        : 'Try again in a moment. If it keeps failing, reinstall it in setup.',
                    type: .error,
                  );
                },
          leading: busy ? const Spinner(size: 14) : null,
          child: Text(busy ? 'Updating...' : 'Update to $latest'),
        ),
      ],
    );
  }
}

/// Which kind of connection is best at each kind of work: Mittolabs's
/// choice until the user makes their own. Folded away until asked for.
List<Widget> _bestAt(SettingsViewModel vm) {
  final s = vm.settings;
  final families = vm.families;
  return [
    _Row(
      title: 'Best at',
      description:
          'Which connection each kind of message goes to first, while it has room. '
          "Helmy's choices are Mittolabs's judgment, not a measurement: change any of them.",
      control: Button(
        variant: .outline,
        size: .sm,
        onPressed: vm.toggleBestAt,
        child: Text(vm.bestAtOpen ? 'Hide' : 'Show'),
      ),
    ),
    if (vm.bestAtOpen)
      for (final kind in WorkKind.values)
        _Row(
          title: kind.label,
          description: kind.description,
          control: SizedBox(
            width: 150,
            child: Select<String>(
              size: .sm,
              value: s.bestFor(kind) ?? 'any',
              semanticLabel: 'Best at ${kind.label}',
              options: [
                const SelectOption('any', 'Any, by room'),
                for (final MapEntry(:key, :value) in families.entries) SelectOption(key, value),
                // Chosen once, though not here now: kept, and named.
                if (s.bestFor(kind) case final f? when !families.containsKey(f)) SelectOption(f, f),
              ],
              onChanged: (v) => vm.setBestAt(kind, v == 'any' ? null : v),
            ),
          ),
        ),
  ];
}

/// Where a connection's program is, as found; and, for when it is not
/// found or the wrong one is, a program chosen by hand.
class _Program extends StatelessWidget {
  const _Program({required this.vm, required this.kind});
  final SettingsViewModel vm;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final chosen = vm.settings.programs[kind];
    return FutureBuilder(
      future: vm.setup?.programOf(kind),
      builder: (context, snap) => Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              snap.connectionState != .done
                  ? 'Finding its program...'
                  : snap.data == null
                  ? 'Its program was not found.'
                  : '${chosen != null ? 'Chosen' : 'Found'}: ${tildePath(snap.data!)}',
              style: muted,
              maxLines: 2,
              overflow: .ellipsis,
            ),
          ),
          if (chosen != null)
            Button(
              variant: .ghost,
              size: .xs,
              onPressed: () => vm.update(
                vm.settings.copyWith(programs: {...vm.settings.programs}..remove(kind)),
              ),
              child: const Text('Find it again'),
            ),
          Button(
            variant: .outline,
            size: .xs,
            onPressed: () async {
              final file = await openFile(confirmButtonText: 'Use this program');
              if (file == null) return;
              await vm.update(
                vm.settings.copyWith(programs: {...vm.settings.programs, kind: file.path}),
              );
            },
            child: const Text('Choose...'),
          ),
        ],
      ),
    );
  }
}
