part of '../chat_screen.dart';

/// What the vault asks of the person in this chat: a secret, typed into a
/// field of Helmy's own and kept in the Keychain (the agent gets its name,
/// never the value, and it never enters the conversation); or a go-ahead
/// for a command to run with secrets.
class _VaultCard extends StatefulWidget {
  const _VaultCard({super.key, required this.request, required this.project});
  final VaultRequest request;

  /// The chat's project, which the secret belongs to unless shared.
  final String project;

  @override
  State<_VaultCard> createState() => _VaultCardState();
}

class _VaultCardState extends State<_VaultCard> {
  final _value = TextEditingController();
  late bool _shared = widget.request.shared;
  bool _saving = false;
  String? _trouble;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _keep() async {
    final value = _value.text;
    if (value.isEmpty) return;
    setState(() {
      _saving = true;
      _trouble = null;
    });
    final r = widget.request;
    final kept = await context.read<Vault>().put(
      _shared ? sharedScope : widget.project,
      r.name,
      value,
    );
    if (!mounted) return;
    _value.clear();
    if (!kept) {
      setState(() {
        _saving = false;
        _trouble = "It wasn't kept: the Keychain didn't take it. Try again.";
      });
      return;
    }
    context.read<VaultRequests>().settle(r, kept: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final r = widget.request;
    final requests = context.read<VaultRequests>();
    final asking = r.question != null;
    return Container(
      margin: const .only(bottom: 10),
      padding: const .fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: .35),
        border: .all(color: c.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 10,
            children: [
              AshlarIcon(
                asking ? AshlarIconsRoundedStroke.shieldCheck : AshlarIconsRoundedStroke.lock,
                size: 16,
                color: c.foreground,
              ),
              Expanded(
                child: Text(
                  asking ? r.question! : 'A secret for this chat: ${r.name}',
                  style: t.text.sm.copyWith(fontWeight: .w500),
                ),
              ),
            ],
          ),
          if (asking)
            Container(
              padding: const .all(8),
              decoration: BoxDecoration(color: c.background, borderRadius: .circular(t.radiusMd)),
              child: Text(
                r.why,
                style: t.text.xs.copyWith(fontFamily: 'monospace', fontFamilyFallback: monoFonts),
              ),
            )
          else ...[
            if (r.why.isNotEmpty) Text(r.why, style: t.text.xs.copyWith(color: c.mutedForeground)),
            Input(
              controller: _value,
              size: .sm,
              obscureText: true,
              autofocus: true,
              placeholder: 'Paste or type it here',
              semanticLabel: 'The secret ${r.name}',
              onSubmitted: (_) => unawaited(_keep()),
            ),
            Text(
              "It goes into your Mac's Keychain. The assistant gets its name, never the value.",
              style: t.text.xs.copyWith(color: c.mutedForeground),
            ),
            if (_trouble case final why?)
              Text(why, style: t.text.xs.copyWith(color: c.destructive)),
          ],
          Row(
            spacing: 8,
            children: [
              if (!asking)
                Expanded(
                  child: Row(
                    spacing: 8,
                    children: [
                      Switch(
                        value: _shared,
                        size: .sm,
                        semanticLabel: 'For every project',
                        onChanged: (v) => setState(() => _shared = v),
                      ),
                      Flexible(
                        child: Text(
                          _shared ? 'For every project' : 'For this project only',
                          style: t.text.xs.copyWith(color: c.mutedForeground),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              Button(
                variant: .ghost,
                size: .sm,
                onPressed: _saving ? null : () => requests.settle(r, kept: false),
                child: Text(asking ? "Don't" : 'Not now'),
              ),
              Button(
                size: .sm,
                onPressed: _saving
                    ? null
                    : asking
                    ? () => requests.settle(r, kept: true)
                    : () => unawaited(_keep()),
                child: Text(asking ? 'Go ahead' : 'Keep it'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A project with secrets still in its .env files: offered once, to move
/// them into the vault, out of the assistant's reach.
class _EnvOffer extends StatefulWidget {
  const _EnvOffer({super.key, required this.project});
  final String project;

  @override
  State<_EnvOffer> createState() => _EnvOfferState();
}

class _EnvOfferState extends State<_EnvOffer> {
  late Map<File, int> _found = EnvSecrets.find(widget.project);
  bool _moving = false;
  String? _said;

  Future<void> _move() async {
    setState(() => _moving = true);
    final r = await EnvSecrets.move(context.read<Vault>(), widget.project, _found.keys);
    if (!mounted) return;
    setState(() {
      _moving = false;
      _found = EnvSecrets.find(widget.project);
      _said = r.failed.isEmpty
          ? null
          : "${r.failed.join(', ')} ${r.failed.length == 1 ? "wasn't" : "weren't"} kept: the "
                'Keychain refused. They are still in the file.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final Vault vault;
    try {
      vault = context.watch<Vault>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    if (vault.keepsEnv(widget.project) || (_found.isEmpty && _said == null)) {
      return const SizedBox.shrink();
    }
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final count = _found.values.fold(0, (a, b) => a + b);
    final files = _found.keys.map((f) => f.path.split('/').last).join(', ');
    return Container(
      margin: const .only(bottom: 10),
      padding: const .fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: .35),
        border: .all(color: c.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 10,
            children: [
              AshlarIcon(AshlarIconsRoundedStroke.lock, size: 16, color: c.foreground),
              Expanded(
                child: Text(
                  _found.isEmpty
                      ? 'Not every secret moved'
                      : '$count secret${count == 1 ? '' : 's'} in $files',
                  style: t.text.sm.copyWith(fontWeight: .w500),
                ),
              ),
            ],
          ),
          Text(
            _said ??
                "Move them into Helmy's vault, in your Mac's Keychain, and the assistant never "
                    'sees them. The file keeps their names; what Helmy runs, and `helmy run` in a '
                    'terminal, gets the real values.',
            style: t.text.xs.copyWith(color: _said == null ? c.mutedForeground : c.destructive),
          ),
          if (_found.isNotEmpty)
            Row(
              mainAxisAlignment: .end,
              spacing: 8,
              children: [
                Button(
                  variant: .ghost,
                  size: .sm,
                  onPressed: _moving ? null : () => unawaited(vault.keepEnv(widget.project)),
                  child: const Text('Keep them in the file'),
                ),
                Button(
                  size: .sm,
                  onPressed: _moving ? null : () => unawaited(_move()),
                  leading: _moving ? const Spinner(size: 12) : null,
                  child: const Text('Move them'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Secrets found in a message about to go: kept in the vault, each sent as
/// its name (`vault:STRIPE_SECRET_KEY`), or sent as they are. Pops with the
/// message to send, or null to send nothing.
class _KeepSecrets extends StatefulWidget {
  const _KeepSecrets({
    required this.text,
    required this.secrets,
    required this.project,
    required this.vault,
  });
  final String text;
  final List<SpottedSecret> secrets;
  final String project;
  final Vault vault;

  @override
  State<_KeepSecrets> createState() => _KeepSecretsState();
}

class _KeepSecretsState extends State<_KeepSecrets> {
  late final _names = [for (final s in widget.secrets) TextEditingController(text: s.name)];
  bool _shared = false;
  bool _saving = false;
  String? _trouble;

  @override
  void dispose() {
    for (final n in _names) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _keep() async {
    setState(() {
      _saving = true;
      _trouble = null;
    });
    var text = widget.text;
    for (var i = 0; i < widget.secrets.length; i++) {
      final name = Vault.validName(_names[i].text.trim())
          ? _names[i].text.trim()
          : Vault.nameFrom(_names[i].text);
      final ok = await widget.vault.put(
        _shared ? sharedScope : widget.project,
        name,
        widget.secrets[i].value,
      );
      if (!ok) {
        if (mounted) {
          setState(() {
            _saving = false;
            _trouble = "$name wasn't kept: the Keychain refused. Nothing was sent.";
          });
        }
        return;
      }
      text = text.replaceAll(widget.secrets[i].value, 'vault:$name');
    }
    if (mounted) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final one = widget.secrets.length == 1;
    return HelmyDialog(
      title: one ? 'That looks like a secret' : 'Those look like secrets',
      icon: AshlarIconsRoundedStroke.lock,
      maxWidth: 460,
      body:
          "Keep ${one ? 'it' : 'them'} in Helmy's vault, in your Mac's Keychain, and the "
          "assistant gets ${one ? 'its name' : 'their names'}, never the value.",
      content: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: 10,
        children: [
          for (var i = 0; i < widget.secrets.length; i++)
            Column(
              crossAxisAlignment: .stretch,
              spacing: 4,
              children: [
                Text(
                  '${widget.secrets[i].kind}, ending …${widget.secrets[i].value.substring(widget.secrets[i].value.length - 4)}',
                  style: t.text.xs.copyWith(color: c.mutedForeground),
                ),
                Input(controller: _names[i], size: .sm, semanticLabel: 'Name it'),
              ],
            ),
          Row(
            spacing: 8,
            children: [
              Switch(
                value: _shared,
                size: .sm,
                semanticLabel: 'For every project',
                onChanged: (v) => setState(() => _shared = v),
              ),
              Text(
                _shared ? 'For every project' : 'For this project only',
                style: t.text.xs.copyWith(color: c.mutedForeground),
              ),
            ],
          ),
          if (_trouble case final why?) Text(why, style: t.text.xs.copyWith(color: c.destructive)),
        ],
      ),
      actions: [
        Button(
          variant: .ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(widget.text),
          child: const Text('Send it as it is'),
        ),
        Button(
          onPressed: _saving ? null : () => unawaited(_keep()),
          child: Text(one ? 'Keep it and send' : 'Keep them and send'),
        ),
      ],
    );
  }
}
