import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/settings_repository.dart';
import '../../data/services/connections_setup.dart';
import '../core/ashlar/button.dart';
import '../core/ashlar/scroll_area.dart';
import '../core/ashlar/spinner.dart';
import '../core/ashlar/theme.dart';
import '../core/window_layout.dart';

/// Getting Helmy ready: the AI tools it works through, each installed and
/// signed in with one press, no terminal. Shown on first launch, and from
/// Settings whenever wanted.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  List<ConnectionCheck>? _checks;

  /// The connection being installed or signed in now, and what it is doing.
  String? _busy;
  String _doing = '';
  final Map<String, String> _trouble = {};

  ConnectionsSetup get _setup => context.read<ConnectionsSetup>();

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final checks = await _setup.check();
    if (mounted) setState(() => _checks = checks);
  }

  Future<void> _act(ConnectionCheck c) async {
    setState(() {
      _busy = c.id;
      _trouble.remove(c.id);
      _doing = switch (c.state) {
        .missing => 'Installing…',
        .signedOut => c.id == 'ollama' ? 'Starting…' : 'Finish signing in in your browser…',
        .ready => '',
      };
    });
    final ok = switch (c.state) {
      .missing => await _setup.install(c.id),
      .signedOut => await _setup.signIn(c.id),
      .ready => true,
    };
    if (!ok && mounted) {
      _trouble[c.id] = c.state == .missing
          ? "It didn't install from here. Its install page is open in your browser."
          : "That didn't finish. Try again.";
    }
    await _refresh();
    if (mounted) setState(() => _busy = null);
  }

  /// On into Helmy at once; that setup is done is saved meanwhile.
  void _done() {
    final settings = context.read<SettingsRepository>();
    unawaited(settings.save(settings.settings.copyWith(setupDone: true)));
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final checks = _checks;
    final anyReady = checks?.any((c) => c.state == .ready) ?? false;
    return ColoredBox(
      color: t.colors.background,
      child: ScrollArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: .fromLTRB(sideMargin(context), 56, sideMargin(context), 32),
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 12,
                children: [
                  Image.asset('assets/helmy/hello.png', height: 112, semanticLabel: 'Helmy'),
                  Text(
                    "Let's get Helmy ready",
                    textAlign: .center,
                    style: t.text.xl.copyWith(fontWeight: .w600),
                  ),
                  Text(
                    'Helmy gets things done through the AI tools you already use. Set up at '
                    'least one; you can change them any time in Settings.',
                    textAlign: .center,
                    style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                  ),
                  const SizedBox(height: 8),
                  if (checks == null)
                    const Center(child: Spinner(size: 18))
                  else
                    for (final c in checks) _row(t, c),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: .end,
                    spacing: 8,
                    children: [
                      if (!anyReady)
                        Button(
                          variant: .ghost,
                          onPressed: _done,
                          child: const Text('Skip for now'),
                        ),
                      Button(onPressed: anyReady ? _done : null, child: const Text("Let's go")),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(AshlarThemeData t, ConnectionCheck c) {
    final busy = _busy == c.id;
    final trouble = _trouble[c.id];
    return Container(
      padding: const .all(14),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(c.name, style: t.text.sm.copyWith(fontWeight: .w600)),
                Text(c.does, style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
                if (busy)
                  Text(_doing, style: t.text.xs.copyWith(color: t.colors.foreground))
                else if (trouble != null)
                  Text(trouble, style: t.text.xs.copyWith(color: t.colors.destructive)),
              ],
            ),
          ),
          if (busy)
            const Spinner(size: 16)
          else if (c.state == .ready)
            Row(
              mainAxisSize: .min,
              spacing: 4,
              children: [
                AshlarIcon(AshlarIconsRoundedStroke.check, size: 14, color: t.colors.foreground),
                Text('Ready', style: t.text.sm),
              ],
            )
          else
            Button(
              variant: .outline,
              size: .sm,
              onPressed: _busy == null ? () => _act(c) : null,
              child: Text(switch (c.state) {
                .missing => 'Install',
                .signedOut => c.id == 'ollama' ? 'Start' : 'Sign in',
                .ready => 'Ready',
              }),
            ),
        ],
      ),
    );
  }
}
