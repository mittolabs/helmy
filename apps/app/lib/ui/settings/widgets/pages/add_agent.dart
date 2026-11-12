part of '../settings_screen.dart';

/// Adds an agent that speaks the Agent Client Protocol: one from the ACP
/// registry, installed by Helmy, or a command of the user's own. It is
/// checked before the dialog closes, and signed in where it needs it.
///
/// With [only] (a registry id: Cursor, Grok, Antigravity), that one agent is
/// installed and checked at once, with no list to choose from.
Future<void> addAgent(BuildContext context, SettingsViewModel vm, {String? only}) async {
  final added = await showAshlarDialog<String>(
    context: context,
    builder: (context) => _AddAgent(vm: vm, only: only),
  );
  if (added == null || !context.mounted) return;
  showToast(
    context,
    title: '$added added',
    description: only != null && subscriptionAgents.containsKey(only)
        ? 'Helmy gives it any work, as it does Claude Code and Codex.'
        : 'It answers the kinds of work set for it under Advanced > Best at, and nothing else.',
    type: .success,
  );
}

class _AddAgent extends StatefulWidget {
  const _AddAgent({required this.vm, this.only});
  final SettingsViewModel vm;
  final String? only;

  @override
  State<_AddAgent> createState() => _AddAgentState();
}

enum _From { registry, command }

class _AddAgentState extends State<_AddAgent> {
  _From _from = .registry;
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _command = TextEditingController();
  late final Future<List<AcpListing>?> _listings = widget.vm.listings();

  /// What is happening: installing, checking; null when idle.
  String? _busy;

  /// The agent added, while its check found a problem.
  AcpAdded? _added;
  String? _error;

  @override
  void initState() {
    super.initState();
    // One agent asked for by name: installed at once.
    if (widget.only case final id?) {
      unawaited(
        _listings.then((all) {
          if (!mounted) return;
          final l = all?.where((x) => x.id == id).firstOrNull;
          if (l != null) {
            unawaited(_run(() => widget.vm.addAgent(l), 'Installing ${l.name}...'));
          } else {
            setState(
              () => _error = all == null
                  ? "The agent registry didn't answer. Check the internet connection and try again."
                  : "It isn't offered for this computer.",
            );
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _command.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AcpAdded> Function() add, String label) async {
    setState(() {
      _busy = label;
      _error = null;
    });
    try {
      final added = await add();
      if (!mounted) return;
      if (added.check?.ready ?? false) {
        Navigator.pop(context, added.account.name);
        return;
      }
      setState(() {
        _busy = null;
        _added = added;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _recheck() async {
    final a = _added;
    if (a == null) return;
    setState(() => _busy = 'Checking ${a.account.name}...');
    final check = await widget.vm.checkAgent(a.account.id);
    if (!mounted) return;
    if (check?.ready ?? false) {
      Navigator.pop(context, a.account.name);
      return;
    }
    setState(() {
      _busy = null;
      _added = (account: a.account, check: check);
    });
  }

  /// Leaves without the agent: one added but not working is removed.
  Future<void> _cancel() async {
    final a = _added;
    if (a != null) await widget.vm.removeAccount(a.account.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final label = t.text.sm.copyWith(fontWeight: .w500);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground, height: 1.4);
    final added = _added;
    final Widget body;
    if (_busy case final busy?) {
      body = Row(
        spacing: 10,
        children: [
          const Spinner(size: 14),
          Expanded(child: Text(busy, style: muted)),
        ],
      );
    } else if (added != null) {
      final check = added.check;
      body = Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Text(
            "${added.account.name} is installed but isn't ready: "
            '${check?.problem ?? 'it could not be checked.'}',
            style: t.text.sm.copyWith(height: 1.45),
          ),
          for (final m in check?.signIns ?? const <Map<String, Object?>>[])
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Button(
                variant: .outline,
                size: .sm,
                onPressed: () async {
                  await widget.vm.signInAgent(added.account.id, m);
                  await _recheck();
                },
                child: Text('${m['name'] ?? 'Sign in'}'),
              ),
            ),
          Text(
            'Signing in may open your browser, or Terminal. Check again once done.',
            style: muted,
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: _Pick(
                  label: 'From the ACP registry',
                  on: _from == .registry,
                  onPressed: () => setState(() => _from = .registry),
                ),
              ),
              Expanded(
                child: _Pick(
                  label: 'A command of your own',
                  on: _from == .command,
                  onPressed: () => setState(() => _from = .command),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_from == .registry) ...[
            Input(
              controller: _search,
              autofocus: true,
              placeholder: 'Search agents',
              semanticLabel: 'Search agents',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            FutureBuilder(
              future: _listings,
              builder: (context, snap) {
                if (snap.connectionState != .done) {
                  return Text('Reading the registry...', style: muted);
                }
                final all = snap.data;
                if (all == null) {
                  return Text(
                    "The registry couldn't be reached. Check the connection and open this again.",
                    style: muted,
                  );
                }
                final q = _search.text.trim().toLowerCase();
                final shown = [
                  for (final l in all)
                    if (q.isEmpty || '${l.name} ${l.description}'.toLowerCase().contains(q)) l,
                ];
                return ConstrainedBox(
                  // As tall as half the window allows: a fixed box was cramped on a big screen.
                  constraints: BoxConstraints(
                    maxHeight: (MediaQuery.sizeOf(context).height * .5).clamp(240.0, 480.0),
                  ),
                  child: ScrollArea(
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        for (final l in shown)
                          Padding(
                            padding: const .symmetric(vertical: 6),
                            child: Row(
                              spacing: 10,
                              children: [
                                ConnectionLogo('acp.${l.id}', icon: l.icon, size: 18),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: .start,
                                    spacing: 2,
                                    children: [
                                      Text(l.name, style: label),
                                      Text(
                                        l.description,
                                        maxLines: 2,
                                        overflow: .ellipsis,
                                        style: muted,
                                      ),
                                    ],
                                  ),
                                ),
                                Button(
                                  variant: .outline,
                                  size: .sm,
                                  semanticLabel: 'Add ${l.name}',
                                  onPressed: () =>
                                      _run(() => widget.vm.addAgent(l), 'Installing ${l.name}...'),
                                  child: const Text('Add'),
                                ),
                              ],
                            ),
                          ),
                        if (shown.isEmpty) Text('No agent by that name.', style: muted),
                      ],
                    ),
                  ),
                );
              },
            ),
          ] else ...[
            Text('Name', style: label),
            const SizedBox(height: 6),
            Input(controller: _name, autofocus: true, placeholder: 'My agent'),
            const SizedBox(height: 14),
            Text('Command', style: label),
            const SizedBox(height: 2),
            Text('What starts it speaking ACP, as you would type it.', style: muted),
            const SizedBox(height: 6),
            Input(controller: _command, placeholder: 'my-agent --acp', semanticLabel: 'Command'),
          ],
          if (_error case final e?) ...[
            const SizedBox(height: 10),
            Text(e, style: muted.copyWith(color: t.colors.destructive)),
          ],
        ],
      );
    }
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
      child: HelmyDialog(
        title: 'Add an agent',
        body:
            'Any agent that speaks the Agent Client Protocol. It reports no usage, so it '
            'answers only the kinds of work you set it best at.',
        icon: AshlarIconsRoundedStroke.plus,
        maxWidth: 520,
        content: body,
        actions: [
          DialogButton(added == null ? 'Cancel' : 'Remove it', onPressed: _cancel),
          if (added != null)
            DialogButton('Check again', main: true, onPressed: _recheck)
          else if (_from == .command)
            ListenableBuilder(
              listenable: Listenable.merge([_name, _command]),
              builder: (context, _) {
                final ready =
                    _busy == null &&
                    _name.text.trim().isNotEmpty &&
                    _command.text.trim().isNotEmpty;
                return Opacity(
                  opacity: ready ? 1 : .4,
                  child: DialogButton(
                    'Add',
                    main: true,
                    onPressed: () {
                      if (!ready) return;
                      _run(
                        () => widget.vm.addCommand(_name.text, _command.text),
                        'Adding ${_name.text.trim()}...',
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
