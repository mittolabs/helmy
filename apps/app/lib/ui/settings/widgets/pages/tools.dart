part of '../settings_screen.dart';

class _Tools extends StatefulWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_Tools> createState() => _ToolsState();
}

class _ToolsState extends State<_Tools> {
  @override
  void initState() {
    super.initState();
    // After this frame: with nothing to ask (no connection online), loading
    // finishes at once, and would tell the page while it is being built.
    if (!widget.vm.toolsLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.vm.loadTools());
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    return _Page(
      children: [
        Text(
          "What each agent can run when a message starts with /, and the MCP servers it "
          'reaches. A /command goes to an agent that has it. Add or change them in each '
          "agent's own settings; this page shows them as the agents report.",
          style: t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.5),
        ),
        for (final a in vm.agents.where((a) => !a.info.localOnly)) ...[
          _Heading(a.info.name),
          if (vm.tools[a.info.id] case final tools?) ...[
            _Block(
              title: 'MCP servers',
              child: tools.servers.isEmpty
                  ? Text('None', style: muted)
                  : Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        for (final s in tools.servers)
                          Padding(
                            padding: const .symmetric(vertical: 3),
                            child: Row(
                              spacing: 8,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: .circle,
                                    color: s.status == 'connected'
                                        ? t.colors.foreground
                                        : t.colors.mutedForeground.withValues(alpha: .4),
                                  ),
                                ),
                                Expanded(child: Text(s.name, style: t.text.sm)),
                                Text(switch (s.status) {
                                  'connected' => 'Connected',
                                  'needs-auth' => 'Needs sign-in',
                                  'pending' => 'Connecting',
                                  'failed' => 'Failed',
                                  final other => other,
                                }, style: muted),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            _Block(
              title: tools.commands.isEmpty
                  ? 'Skills and commands'
                  : 'Skills and commands (${tools.commands.length})',
              child: tools.commands.isEmpty
                  ? Text('None', style: muted)
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in tools.commands)
                          Tooltip(
                            message: c.description.isEmpty ? c.name : c.description,
                            child: Container(
                              padding: const .symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                border: Border.all(color: t.colors.border),
                                borderRadius: .circular(t.radiusMd),
                              ),
                              child: Text(
                                '/${c.name}',
                                style: t.text.xs.copyWith(
                                  fontFamily: 'monospace',
                                  fontFamilyFallback: monoFonts,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ] else
            const Padding(padding: .all(8), child: Spinner(size: 14)),
        ],
      ],
    );
  }
}
