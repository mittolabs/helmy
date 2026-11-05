part of '../settings_screen.dart';

/// Adds another Claude Code or Codex account, the way T3 does: pick the
/// connection, name the account, then sign in through the browser or point
/// at a folder that is already signed in. Nothing is kept until it is.
Future<void> addAccount(BuildContext context, SettingsViewModel vm, String kind) async {
  final added = await showAshlarDialog<String>(
    context: context,
    builder: (context) => _AddAccount(vm: vm, kind: kind),
  );
  if (added == null || !context.mounted) return;
  showToast(
    context,
    title: '$added added',
    description: 'Helmy uses it from the next message, alongside the others.',
    type: .success,
  );
}

class _AddAccount extends StatefulWidget {
  const _AddAccount({required this.vm, required this.kind});
  final SettingsViewModel vm;
  final String kind;

  @override
  State<_AddAccount> createState() => _AddAccountState();
}

enum _How { browser, folder }

class _AddAccountState extends State<_AddAccount> {
  late String _kind = widget.kind;
  final _name = TextEditingController();
  final _folder = TextEditingController();
  _How _how = .browser;

  /// Who the folder is signed in as, once checked; '' when nobody is.
  String? _who;
  bool _checking = false;
  bool _signingIn = false;
  bool _failed = false;

  String get _product => _kind == 'claude' ? 'Claude Code' : 'Codex';
  String get _usual => _kind == 'claude' ? '~/.claude' : '~/.codex';

  @override
  void dispose() {
    if (_signingIn) widget.vm.cancelAdding();
    _name.dispose();
    _folder.dispose();
    super.dispose();
  }

  bool get _ready =>
      _name.text.trim().isNotEmpty &&
      !_signingIn &&
      (_how == .browser || (_who?.isNotEmpty ?? false));

  Future<void> _check() async {
    final f = _folder.text.trim();
    if (f.isEmpty) return;
    setState(() {
      _checking = true;
      _who = null;
    });
    final who = await widget.vm.signedInAs(_kind, f);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _who = who ?? '';
    });
  }

  Future<void> _add() async {
    if (!_ready) return;
    final name = _name.text.trim();
    if (_how == .folder) {
      await widget.vm.addFolder(_kind, name, _folder.text);
      if (mounted) Navigator.pop(context, '$_product ($name)');
      return;
    }
    setState(() {
      _signingIn = true;
      _failed = false;
    });
    final ok = await widget.vm.addAccount(_kind, name);
    if (!mounted) return;
    if (ok) {
      _signingIn = false;
      Navigator.pop(context, '$_product ($name)');
    } else {
      setState(() {
        _signingIn = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final label = t.text.sm.copyWith(fontWeight: .w500);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground, height: 1.4);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: HelmyDialog(
        title: 'Add an account',
        body:
            'Each account has its own usage limits, and Helmy moves between them as one '
            'runs low.',
        icon: AshlarIconsRoundedStroke.plus,
        content: ListenableBuilder(
          listenable: Listenable.merge([_name, _folder]),
          builder: (context, _) => Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            children: [
              Row(
                spacing: 8,
                children: [
                  for (final (k, name) in [('claude', 'Claude Code'), ('codex', 'Codex')])
                    Expanded(
                      child: _Pick(
                        logo: k,
                        label: name,
                        on: _kind == k,
                        onPressed: _signingIn
                            ? null
                            : () => setState(() {
                                _kind = k;
                                _who = null;
                              }),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Name', style: label),
              const SizedBox(height: 2),
              Text('Shown in Settings, beside $_product.', style: muted),
              const SizedBox(height: 6),
              Input(
                controller: _name,
                autofocus: true,
                enabled: !_signingIn,
                placeholder: 'Work',
                semanticLabel: 'Account name',
                onSubmitted: (_) => _add(),
              ),
              const SizedBox(height: 16),
              Text('Sign-in', style: label),
              const SizedBox(height: 6),
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: _Pick(
                      label: 'In the browser',
                      on: _how == .browser,
                      onPressed: _signingIn ? null : () => setState(() => _how = .browser),
                    ),
                  ),
                  Expanded(
                    child: _Pick(
                      label: 'A signed-in folder',
                      on: _how == .folder,
                      onPressed: _signingIn ? null : () => setState(() => _how = .folder),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_how == .browser)
                Text(
                  _signingIn
                      ? 'Waiting for the sign-in in your browser. Choose the other account '
                            'there, not the one $_usual is signed in to.'
                      : _failed
                      ? "The sign-in didn't finish, so nothing was added. Try again when ready."
                      : 'Your browser opens to sign in. Choose the other account there; '
                            'its sign-in is kept in a folder of its own.',
                  style: muted.copyWith(color: _failed ? t.colors.destructive : null),
                )
              else ...[
                Text(
                  'A folder $_product keeps a sign-in in, as '
                  '${_kind == 'claude' ? 'CLAUDE_CONFIG_DIR' : 'CODEX_HOME'} points to.',
                  style: muted,
                ),
                const SizedBox(height: 6),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Focus(
                        onFocusChange: (f) {
                          if (!f) _check();
                        },
                        child: Input(
                          controller: _folder,
                          placeholder: '$_usual-work',
                          semanticLabel: 'Folder',
                          onChanged: (_) => setState(() => _who = null),
                          onSubmitted: (_) => _check(),
                        ),
                      ),
                    ),
                    Button(
                      variant: .outline,
                      size: .sm,
                      onPressed: () async {
                        final dir = await getDirectoryPath(
                          initialDirectory: homeDir,
                          confirmButtonText: 'Use this folder',
                        );
                        if (dir == null) return;
                        _folder.text = dir;
                        await _check();
                      },
                      child: const Text('Choose...'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_checking)
                  Text('Checking who is signed in there...', style: muted)
                else if (_who case final who?)
                  Text(
                    who.isEmpty
                        ? 'Nobody is signed in to $_product there.'
                        : who == 'signed in'
                        ? 'Signed in.'
                        : 'Signed in as $who.',
                    style: muted.copyWith(color: who.isEmpty ? t.colors.destructive : null),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          DialogButton(
            'Cancel',
            onPressed: () {
              if (_signingIn) {
                widget.vm.cancelAdding();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          ListenableBuilder(
            listenable: Listenable.merge([_name, _folder]),
            builder: (context, _) => Opacity(
              opacity: _ready ? 1 : .4,
              child: DialogButton(
                _signingIn
                    ? 'Signing in...'
                    : _how == .browser
                    ? 'Sign in'
                    : 'Add',
                main: true,
                onPressed: _add,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of two or three choices, side by side: the chosen one outlined.
class _Pick extends StatelessWidget {
  const _Pick({required this.label, required this.on, required this.onPressed, this.logo});
  final String label;

  /// A connection whose logo goes before the label.
  final String? logo;
  final bool on;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => AnimatedContainer(
        duration: t.duration,
        padding: const .symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: on
              ? c.foreground.withValues(alpha: .06)
              : c.foreground.withValues(alpha: state.hovered ? .04 : 0),
          borderRadius: .circular(10),
          border: Border.all(
            color: on ? c.foreground.withValues(alpha: .5) : c.border,
            width: on ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: .center,
          spacing: 8,
          children: [
            if (logo case final l?) ConnectionLogo(l, size: 16),
            Flexible(
              child: Text(
                label,
                textAlign: .center,
                style: t.text.sm.copyWith(
                  fontWeight: on ? .w500 : .w400,
                  color: onPressed == null ? c.mutedForeground : c.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
