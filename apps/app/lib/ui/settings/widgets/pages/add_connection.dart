part of '../settings_screen.dart';

/// Adds a connection, as T3 Code's "Connect your agents" does: a dialog over
/// Settings with each connection on a row, Ready or the one thing it needs
/// (add it back, install it, sign in, start it), done there. Then another
/// account, or another agent. Nothing about connections opens in a chat.
Future<void> addConnection(BuildContext context, SettingsViewModel vm) async {
  final next = await showAshlarDialog<_Next>(
    context: context,
    builder: (context) => _AddConnectionDialog(vm: vm),
  );
  if (!context.mounted) return;
  switch (next) {
    case _Next.account:
      await addAccount(context, vm, 'claude');
    case _Next.agent:
      await addAgent(context, vm);
    case null:
  }
}

/// What the dialog hands on to, once it is closed.
enum _Next { account, agent }

class _AddConnectionDialog extends StatefulWidget {
  const _AddConnectionDialog({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_AddConnectionDialog> createState() => _AddConnectionDialogState();
}

class _AddConnectionDialogState extends State<_AddConnectionDialog> {
  /// What stopped the last one, by its id, in Helmy's words.
  final _trouble = <String, String>{};

  SettingsViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    unawaited(vm.checkSetup());
  }

  /// The usual connections, one row each (Ollama's two as one).
  List<AgentRow> get _rows {
    final out = <AgentRow>[];
    final seen = <String>{};
    for (final a in vm.agents) {
      final id = a.info.id;
      final kind = ConnectionsSetup.kindOf(id);
      if (kind == null || a.info.assignedOnly) continue;
      // Other accounts are added from "Add another account".
      if (kind != 'ollama' && id.contains('-')) continue;
      if (!seen.add(vm.groupOf(id).first)) continue;
      out.add(a);
    }
    return out;
  }

  Future<void> _do(String id, Future<String?> Function(String) act) async {
    setState(() => _trouble.remove(id));
    final why = await act(id);
    if (mounted && why != null) setState(() => _trouble[id] = why);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.xs.copyWith(color: c.mutedForeground);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: HelmyDialog(
        title: 'Add a connection',
        body:
            'Helmy gets things done through the AI tools you use. Each one marked Ready is set; '
            'the others are a press away.',
        icon: AshlarIconsRoundedStroke.plus,
        maxWidth: 520,
        content: ListenableBuilder(
          listenable: vm,
          builder: (context, _) => Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            spacing: 8,
            children: [
              for (final a in _rows) _row(context, a),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  Button(
                    variant: .ghost,
                    size: .sm,
                    leading: const AshlarIcon(AshlarIconsRoundedStroke.plus, size: 14),
                    onPressed: vm.working != null
                        ? null
                        : () => Navigator.pop(context, _Next.account),
                    child: const Text('Add another account'),
                  ),
                  Button(
                    variant: .ghost,
                    size: .sm,
                    leading: const AshlarIcon(AshlarIconsRoundedStroke.plus, size: 14),
                    onPressed: vm.working != null
                        ? null
                        : () => Navigator.pop(context, _Next.agent),
                    child: const Text('Other agents'),
                  ),
                ],
              ),
              Text(
                'Another account brings its own usage limits. Other agents are any that '
                'speak the Agent Client Protocol, such as Gemini, Cursor and OpenCode.',
                style: muted,
              ),
            ],
          ),
        ),
        actions: [Button(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      ),
    );
  }

  Widget _row(BuildContext context, AgentRow a) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final id = a.info.id;
    final ollama = ConnectionsSetup.kindOf(id) == 'ollama';
    final name = ollama ? 'Ollama' : a.info.name;
    final added = a.enabled;
    final fix = added ? vm.fixFor(id) : null;
    final busy = vm.working == id;
    final why = _trouble[id];
    final Widget end;
    if (busy) {
      end = Row(
        mainAxisSize: .min,
        spacing: 8,
        children: [
          const Spinner(size: 14),
          Text(
            vm.adding != null || fix == 'Sign in' ? 'Signing in...' : 'Setting up...',
            style: t.text.sm.copyWith(color: c.mutedForeground),
          ),
        ],
      );
    } else if (!added) {
      end = Button(
        variant: .outline,
        size: .sm,
        onPressed: vm.working != null ? null : () => _do(id, vm.addConnection),
        child: const Text('Add'),
      );
    } else if (fix != null) {
      end = Button(
        variant: .outline,
        size: .sm,
        onPressed: vm.working != null ? null : () => _do(id, vm.fixConnection),
        child: Text(fix),
      );
    } else {
      end = Row(
        mainAxisSize: .min,
        spacing: 6,
        children: [
          AshlarIcon(AshlarIconsRoundedStroke.check, size: 14, color: c.foreground),
          Text('Ready', style: t.text.sm),
        ],
      );
    }
    return Container(
      padding: const .fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: why != null ? c.destructive : c.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Row(
        spacing: 12,
        children: [
          ConnectionLogo(id, icon: vm.iconOf(id), size: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(name, style: t.text.sm.copyWith(fontWeight: .w500)),
                Text(
                  why ??
                      (!added
                          ? 'Not used by Helmy. Add it, and it is made ready here.'
                          : fix != null
                          ? _AgentCard.statusOf(a, vm.checked)
                          // Ready: what it does, as onboarding says it.
                          : ConnectionsSetup.names[ConnectionsSetup.kindOf(id)]?.$2 ??
                                _AgentCard.statusOf(a, vm.checked)),
                  maxLines: 2,
                  overflow: .ellipsis,
                  style: t.text.xs.copyWith(color: why != null ? c.destructive : c.mutedForeground),
                ),
              ],
            ),
          ),
          end,
        ],
      ),
    );
  }
}
