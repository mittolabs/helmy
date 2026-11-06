part of '../settings_screen.dart';

/// Adds a connection: a dialog over Settings offering only what can be
/// added, as T3 Code's does. A connection removed from Helmy, added back
/// (made ready as it is: installed, signed in, started); another Claude
/// Code or Codex account; or another agent from the registry. Those already
/// in use are in the list it was opened from, so they are not shown again.
/// Nothing about connections opens in a chat.
Future<void> addConnection(BuildContext context, SettingsViewModel vm) async {
  final next = await showAshlarDialog<_Next>(
    context: context,
    builder: (context) => _AddConnectionDialog(vm: vm),
  );
  if (!context.mounted || next == null) return;
  switch (next) {
    case _Next(kind: final kind?):
      await addAccount(context, vm, kind);
    case _Next():
      await addAgent(context, vm);
  }
}

/// What the dialog hands on to, once it is closed: an account of [kind],
/// or, without one, another agent.
class _Next {
  const _Next([this.kind]);
  final String? kind;
}

class _AddConnectionDialog extends StatefulWidget {
  const _AddConnectionDialog({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_AddConnectionDialog> createState() => _AddConnectionDialogState();
}

class _AddConnectionDialogState extends State<_AddConnectionDialog> {
  /// What stopped one being added back, by its id, in Helmy's words.
  final _trouble = <String, String>{};

  SettingsViewModel get vm => widget.vm;

  /// Signed-in account folders on this Mac not in Helmy yet; null while
  /// they are looked for.
  List<({String kind, String name, String folder, String who})>? _found;

  @override
  void initState() {
    super.initState();
    unawaited(
      vm.foundAccounts().then((f) {
        if (mounted) setState(() => _found = f);
      }),
    );
  }

  Future<void> _addFound(({String kind, String name, String folder, String who}) f) async {
    await vm.addFolder(f.kind, f.name, f.folder);
    if (!mounted) return;
    Navigator.pop(context);
    showToast(
      context,
      title: '${f.kind == 'claude' ? 'Claude Code' : 'Codex'} (${f.name}) added',
      description: 'Helmy uses it from the next message, alongside the others.',
      type: .success,
    );
  }

  Future<void> _addBack(String id, String name) async {
    setState(() => _trouble.remove(id));
    final why = await vm.addConnection(id);
    if (!mounted) return;
    if (why != null) {
      setState(() => _trouble[id] = why);
      return;
    }
    Navigator.pop(context);
    showToast(
      context,
      title: '$name added',
      description: 'Helmy uses it from the next message.',
      type: .success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: HelmyDialog(
        title: 'Add a connection',
        body: 'Each one is made ready here, and Helmy uses it from the next message.',
        icon: AshlarIconsRoundedStroke.plus,
        maxWidth: 480,
        content: ListenableBuilder(
          listenable: vm,
          builder: (context, _) => Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            spacing: 8,
            children: [
              // Already signed in on this Mac, in a folder of its own.
              for (final f
                  in _found ?? const <({String kind, String name, String folder, String who})>[])
                _AddChoice(
                  logo: f.kind,
                  title: '${f.kind == 'claude' ? 'Claude Code' : 'Codex'} (${f.name})',
                  line: 'On this Mac, signed in as ${f.who}',
                  onPressed: vm.working != null ? null : () => _addFound(f),
                ),
              if (_found == null)
                Row(
                  spacing: 8,
                  children: [
                    const Spinner(size: 12),
                    Text(
                      'Looking for accounts on this Mac...',
                      style: AshlarTheme.of(context).text.xs
                          .copyWith(color: AshlarTheme.of(context).colors.mutedForeground),
                    ),
                  ],
                ),
              // Removed from Helmy: back with one press.
              for (final a in vm.addable)
                _AddChoice(
                  logo: a.id,
                  icon: vm.iconOf(a.id),
                  title: a.name,
                  line:
                      _trouble[a.id] ??
                      ConnectionsSetup.names[ConnectionsSetup.kindOf(a.id)]?.$2 ??
                      'Removed from Helmy; add it back.',
                  trouble: _trouble.containsKey(a.id),
                  busy: vm.working == a.id,
                  onPressed: vm.working != null ? null : () => _addBack(a.id, a.name),
                ),
              for (final (kind, name) in const [('claude', 'Claude Code'), ('codex', 'Codex')])
                _AddChoice(
                  logo: kind,
                  title: 'Another $name account',
                  line: 'Its own usage limits; Helmy moves to it as another runs low.',
                  onPressed: vm.working != null ? null : () => Navigator.pop(context, _Next(kind)),
                ),
              _AddChoice(
                symbol: AshlarIconsRoundedStroke.bot,
                title: 'Another agent',
                line: 'Gemini, Cursor, OpenCode and more, from the agent registry.',
                onPressed: vm.working != null ? null : () => Navigator.pop(context, const _Next()),
              ),
            ],
          ),
        ),
        actions: [
          Button(
            variant: .outline,
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// One thing to add: its logo, what it is, and a press that adds it.
class _AddChoice extends StatelessWidget {
  const _AddChoice({
    required this.title,
    required this.line,
    required this.onPressed,
    this.logo,
    this.icon,
    this.symbol,
    this.trouble = false,
    this.busy = false,
  });

  /// A connection's id or kind, for its logo; or [symbol] instead.
  final String? logo;
  final String? icon;
  final IconData? symbol;
  final String title, line;
  final bool trouble, busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: busy ? null : onPressed,
      semanticLabel: title,
      builder: (context, state) => Container(
        padding: const .fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: state.hovered && state.enabled ? c.accent.withValues(alpha: .5) : null,
          border: Border.all(color: trouble ? c.destructive : c.border),
          borderRadius: .circular(t.radiusLg),
        ),
        child: Row(
          spacing: 12,
          children: [
            if (logo != null)
              ConnectionLogo(logo!, icon: icon, size: 20)
            else
              AshlarIcon(symbol!, size: 20, color: c.foreground),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text(title, style: t.text.sm.copyWith(fontWeight: .w500)),
                  Text(
                    busy ? 'Making it ready...' : line,
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: t.text.xs.copyWith(color: trouble ? c.destructive : c.mutedForeground),
                  ),
                ],
              ),
            ),
            if (busy)
              const Spinner(size: 14)
            else
              AshlarIcon(AshlarIconsRoundedStroke.chevronRight, size: 16, color: c.mutedForeground),
          ],
        ),
      ),
    );
  }
}
