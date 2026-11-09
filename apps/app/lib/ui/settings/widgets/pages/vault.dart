part of '../settings_screen.dart';

/// The vault: the names of the secrets kept for the assistant to use and
/// never see, by project and for every project. Values are never shown
/// here either: one is replaced or removed, not read.
class _VaultPage extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final Vault vault;
    try {
      vault = context.watch<Vault>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final all = vault.all;
    final scopes = [
      if (all.containsKey(sharedScope)) sharedScope,
      ...all.keys.where((k) => k != sharedScope).toList()..sort(),
    ];
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        const _Heading('Vault', first: true),
        _Row(
          title: 'Secrets the assistant uses, never sees',
          description:
              "API keys, passwords and tokens, kept in your Mac's Keychain. The assistant gets "
              'their names and runs what needs them through Helmy, which blanks every value in '
              'what comes back. It cannot read .env files or other files of secrets.',
          control: Button(
            variant: .outline,
            size: .sm,
            leading: const AshlarIcon(AshlarIconsRoundedStroke.plus, size: 14),
            onPressed: () => unawaited(_edit(context, vault, scopes: scopes)),
            child: const Text('Add a secret'),
          ),
        ),
        if (scopes.isEmpty)
          const _Row(
            title: 'None yet',
            description:
                'When the assistant needs one, it asks you for it in a private field; or add one '
                'here.',
            control: SizedBox.shrink(),
          ),
        for (final scope in scopes) ...[
          _Heading(scope == sharedScope ? 'Every project' : tildePath(scope)),
          for (final name in all[scope]!)
            _Row(
              title: name,
              control: Row(
                mainAxisSize: .min,
                spacing: 4,
                children: [
                  Button(
                    variant: .ghost,
                    size: .sm,
                    onPressed: () =>
                        unawaited(_edit(context, vault, scopes: scopes, scope: scope, name: name)),
                    child: const Text('Replace'),
                  ),
                  Button(
                    variant: .ghost,
                    size: .sm,
                    onPressed: () async {
                      final sure = await confirm(
                        context,
                        title: 'Remove $name?',
                        body:
                            'It leaves the vault and your Keychain. What uses it stops working '
                            'until it is added again.',
                        action: 'Remove',
                        destructive: true,
                      );
                      if (sure) await vault.remove(scope, name);
                    },
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
        ],
        const _Heading('In a terminal'),
        _Row(
          title: 'helmy run',
          description:
              'Runs a command with your secrets, as Helmy does: helmy run npm run dev. In a '
              "project's folder it gets that project's secrets and the shared ones. Helmy has "
              'to be open.',
          control: _HelmyRunInstall(),
        ),
      ],
    );
  }

  /// Adds a secret, or replaces [name]'s value in [scope].
  static Future<void> _edit(
    BuildContext context,
    Vault vault, {
    required List<String> scopes,
    String? scope,
    String? name,
  }) => showAshlarDialog<void>(
    context: context,
    builder: (_) => _SecretDialog(vault: vault, scopes: scopes, scope: scope, name: name),
  );
}

class _SecretDialog extends StatefulWidget {
  const new({required this.vault, required this.scopes, this.scope, this.name});
  final Vault vault;
  final List<String> scopes;
  final String? scope, name;

  @override
  State<_SecretDialog> createState() => _SecretDialogState();
}

class _SecretDialogState extends State<_SecretDialog> {
  late final _name = TextEditingController(text: widget.name ?? '');
  final _value = TextEditingController();
  late String _scope = widget.scope ?? sharedScope;
  String? _trouble;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (!Vault.validName(name)) {
      setState(() => _trouble = 'A name in capitals, digits and _, such as STRIPE_SECRET_KEY.');
      return;
    }
    if (_value.text.isEmpty) {
      setState(() => _trouble = 'Paste or type the secret.');
      return;
    }
    setState(() {
      _saving = true;
      _trouble = null;
    });
    final ok = await widget.vault.put(_scope, name, _value.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _trouble = "It wasn't kept: the Keychain refused it. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final replacing = widget.name != null;
    final scopes = {sharedScope, ...widget.scopes};
    return HelmyDialog(
      title: replacing ? 'Replace ${widget.name}' : 'Add a secret',
      icon: AshlarIconsRoundedStroke.lock,
      body: "It goes into your Mac's Keychain. The assistant gets its name, never the value.",
      content: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: 10,
        children: [
          if (!replacing)
            Input(
              controller: _name,
              size: .sm,
              autofocus: true,
              placeholder: 'STRIPE_SECRET_KEY',
              semanticLabel: 'Name',
            ),
          Input(
            controller: _value,
            size: .sm,
            obscureText: true,
            autofocus: replacing,
            placeholder: 'The secret',
            semanticLabel: 'The secret',
            onSubmitted: (_) => unawaited(_save()),
          ),
          if (!replacing && scopes.length > 1)
            Select<String>(
              size: .sm,
              value: _scope,
              semanticLabel: 'For',
              options: [
                for (final s in scopes)
                  SelectOption(s, s == sharedScope ? 'Every project' : tildePath(s)),
              ],
              onChanged: (v) => setState(() => _scope = v),
            ),
          if (_trouble case final why?)
            Text(why, style: t.text.xs.copyWith(color: t.colors.destructive)),
        ],
      ),
      actions: [
        Button(
          variant: .outline,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Button(
          onPressed: _saving ? null : () => unawaited(_save()),
          child: Text(replacing ? 'Replace' : 'Add'),
        ),
      ],
    );
  }
}

/// Whether `helmy run` is set up in the terminal, and the press that does it.
class _HelmyRunInstall extends StatefulWidget {
  @override
  State<_HelmyRunInstall> createState() => _HelmyRunInstallState();
}

class _HelmyRunInstallState extends State<_HelmyRunInstall> {
  late bool _there = HelmyRunCli.installed();
  String? _trouble;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    if (_there) {
      return Text('Set up', style: t.text.sm.copyWith(color: t.colors.mutedForeground));
    }
    return Column(
      crossAxisAlignment: .end,
      mainAxisSize: .min,
      spacing: 4,
      children: [
        Button(
          variant: .outline,
          size: .sm,
          onPressed: () async {
            final why = await HelmyRunCli.install();
            if (!mounted) return;
            setState(() {
              _trouble = why;
              _there = HelmyRunCli.installed();
            });
          },
          child: const Text('Set it up'),
        ),
        if (_trouble case final why?)
          SizedBox(
            width: 220,
            child: Text(why, style: t.text.xs.copyWith(color: t.colors.destructive)),
          ),
      ],
    );
  }
}
