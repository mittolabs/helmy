part of '../settings_screen.dart';

class _Agents extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = vm.settings;
    return _Page(
      children: [
        const _Heading('Set up', first: true),
        _Row(
          title: 'Install and sign in',
          description: 'Each connection installed and signed in with one press, no terminal.',
          control: Button(
            variant: .outline,
            size: .sm,
            onPressed: () => context.go('/setup'),
            child: const Text('Open setup'),
          ),
        ),
        const _Heading('Routing'),
        _Row(
          title: 'Move to an agent with more room',
          description:
              'Each message goes to an agent that can do what it asks, then to the one with '
              'the most of its usage limit left. A session stays with its agent unless another '
              'has clearly more room, since each switch hands the conversation across.',
          control: SizedBox(
            width: 150,
            child: Select<Switching>(
              value: s.switching,
              semanticLabel: 'How readily to switch',
              options: [for (final w in Switching.values) SelectOption(w, w.label)],
              onChanged: (w) => vm.update(s.copyWith(switching: w)),
            ),
          ),
        ),
        const _Heading('Agents'),
        for (final a in vm.agents) _AgentCard(row: a, checked: vm.checked, vm: vm),
        const _Heading('Local model'),
        _Row(
          title: 'Ollama model',
          description: vm.localModels == null
              ? 'Ollama is not running on ${Desktop.current.thisComputer}. With it running and a model pulled, '
                    'sessions keep working with no internet, on that model.'
              : vm.localModels!.isEmpty
              ? 'Ollama is running but has no model. Pull one, for example: ollama pull gpt-oss:20b'
              : 'Used only when no online agent can answer: when offline, or out of room.',
          control: vm.localModels == null || vm.localModels!.isEmpty
              ? const SizedBox.shrink()
              : SizedBox(
                  width: 220,
                  child: Select<String>(
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

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground);
    final now = DateTime.now();
    final usage = row.usage;
    final status = !checked
        ? 'Checking...'
        : row.problem ??
              (row.downUntil != null
                  ? 'Resting after a failure, back ${_until(row.downUntil!, now)}'
                  : row.enabled
                  ? 'Ready'
                  : 'Turned off: no messages go to it');
    final can = [
      for (final c in row.info.capabilities)
        if (c != Capability.tools) c.label,
    ];
    final connections = vm.connectionsOf(row.info.id);
    return Container(
      margin: const .only(top: 12),
      padding: const .all(16),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(row.info.name, style: t.text.sm.copyWith(fontWeight: .w600)),
                    Text(status, style: muted),
                  ],
                ),
              ),
              Switch(
                value: row.enabled,
                semanticLabel: 'Use ${row.info.name}',
                onChanged: (on) => vm.setEnabled(row.info.id, on),
              ),
            ],
          ),
          if (row.info.localOnly)
            Text('No usage limit: it runs on ${Desktop.current.thisComputer}.', style: muted)
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
        Row(
          children: [
            Expanded(
              child: Text(window.name, style: t.text.xs.copyWith(fontWeight: .w500)),
            ),
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
        LayoutBuilder(
          builder: (context, box) => SizedBox(
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
                  Positioned(
                    left: (box.maxWidth * pace - 1).clamp(0, box.maxWidth - 2),
                    top: -3,
                    bottom: -3,
                    child: Container(width: 2, color: t.colors.mutedForeground),
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
