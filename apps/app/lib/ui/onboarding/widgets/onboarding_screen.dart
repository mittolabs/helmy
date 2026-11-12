import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/connections_setup.dart';
import '../../../data/services/engines/acp/free_agent.dart';
import '../../../data/services/desktop_service.dart';
import '../../../utils/format.dart';
import '../../../utils/platform.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/dialog.dart';
import '../../core/ashlar/input.dart';
import '../../core/helmy_dialog.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/switch.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/toast.dart';
import '../../core/connection_logo.dart';
import '../../../data/services/engines/acp/acp_engine.dart' show subscriptionAgents;
import '../../import/import_list.dart';
import '../view_models/onboarding_view_model.dart';

/// The first run, after the splash, in a small window of one size: Helmy
/// at the top left saying what to do now, the steps beside it, as T3 Code
/// has them, and a word on what was set up before Helmy opens. Every color
/// is the theme's own.
class OnboardingScreen extends StatefulWidget {
  const new({super.key, required this.vm});
  final OnboardingViewModel vm;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  OnboardingViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    unawaited(vm.check());
  }

  /// On into Helmy, in its usual window.
  void _open() {
    unawaited(DesktopService.compactWindow(false));
    context.go('/');
  }

  void _skip() {
    unawaited(vm.skip());
    _open();
  }

  Future<void> _bringIn() async {
    final importer = vm.import;
    if (importer == null) return vm.next();
    final n = await importer.importChosen();
    if (!mounted) return;
    if (n > 0) {
      showToast(
        context,
        title: '$n chat${n == 1 ? '' : 's'} brought in',
        description: 'Each is a chat in the sidebar, and goes on where it left off.',
        type: .success,
      );
    }
    vm.next();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return ColoredBox(
      color: t.colors.background,
      child: ListenableBuilder(
        listenable: Listenable.merge([vm, ?vm.import]),
        builder: (context, _) => vm.finished
            ? _Finished(vm: vm, onOpen: _open)
            : switch (vm.step) {
                .connections => _ConnectionsStep(vm: vm, onSkip: _skip),
                .chats => _ChatsStep(vm: vm, onBringIn: _bringIn),
                .folders => _FoldersStep(vm: vm, onDone: vm.finish),
              },
      ),
    );
  }
}

/// What Helmy says on each step, and the picture of it doing so.
const _guide = {
  OnboardingStep.connections: (
    image: 'assets/helmy/onboarding-connect.png',
    title: 'Connect your AI tools',
    say:
        'I start with a free connection, with no account needed. You can also choose '
        'to use your subscriptions: switch on a connection found on this Mac, or press '
        'Install or Sign in to add one, then Continue.',
  ),
  OnboardingStep.chats: (
    image: 'assets/helmy/onboarding-chats.png',
    title: 'Import your chats',
    say:
        'I found your Claude Code and Codex chats on this Mac. Tick the folders to '
        "import, and I'll go on from where each left off. Or skip it; you can do it later.",
  ),
  OnboardingStep.folders: (
    image: 'assets/helmy/onboarding-folders.png',
    title: 'Where should new chats start?',
    say:
        'Every chat works in a folder. Pick where a new one opens. You can move any chat to '
        'another folder later.',
  ),
};

/// The top of every step: Helmy at the left with the steps beside it, and
/// under Helmy, in a speech bubble, what to do now.
class _Header extends StatelessWidget {
  const new({required this.vm});
  final OnboardingViewModel vm;

  @override
  Widget build(BuildContext context) {
    final g = _guide[vm.step]!;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        Row(
          crossAxisAlignment: .end,
          spacing: 20,
          children: [
            _Art(g.image, size: 72),
            Expanded(
              child: Padding(
                padding: const .only(bottom: 8),
                child: _Stepper(vm: vm),
              ),
            ),
          ],
        ),
        _Bubble(
          tag: 'Step ${vm.step.index + 1} of ${OnboardingStep.values.length}',
          title: g.title,
          say: g.say,
        ),
      ],
    );
  }
}

/// A picture of Helmy; the waving one where a step's own is missing.
class _Art extends StatelessWidget {
  const new(this.path, {required this.size});
  final String path;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    path,
    width: size,
    height: size,
    semanticLabel: 'Helmy',
    errorBuilder: (_, _, _) =>
        Image.asset('assets/helmy/hello.png', width: size, height: size, semanticLabel: 'Helmy'),
  );
}

/// What Helmy says: a tag for where you are, the step's name, and plainly
/// what to do, in a bubble whose tail points up at Helmy.
class _Bubble extends StatelessWidget {
  const new({required this.tag, required this.title, required this.say});
  final String tag, title, say;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Column(
      crossAxisAlignment: .start,
      children: [
        Padding(
          padding: const .only(left: 28),
          child: CustomPaint(
            size: const Size(16, 8),
            painter: _Tail(fill: c.muted),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const .fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(color: c.muted, borderRadius: .circular(t.radiusLg + 4)),
          child: Column(
            crossAxisAlignment: .start,
            spacing: 6,
            children: [
              Container(
                padding: const .symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.background,
                  border: Border.all(color: c.border),
                  borderRadius: .circular(99),
                ),
                child: Text(
                  tag.toUpperCase(),
                  style: t.text.xs.copyWith(
                    fontSize: 10,
                    fontWeight: .w600,
                    letterSpacing: .6,
                    color: c.mutedForeground,
                  ),
                ),
              ),
              Text(title, style: t.text.lg.copyWith(fontWeight: .w600)),
              Text(say, style: t.text.sm.copyWith(color: c.foreground.withValues(alpha: .8))),
            ],
          ),
        ),
      ],
    );
  }
}

/// The little triangle that makes the bubble Helmy's.
class _Tail extends CustomPainter {
  _Tail({required this.fill});
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_Tail old) => old.fill != fill;
}

/// The steps, joined by a line: a filled number for the one being done, a
/// tick for those passed, a quiet number for those to come. A step already
/// reached is a press away.
class _Stepper extends StatelessWidget {
  const new({required this.vm});
  final OnboardingViewModel vm;

  @override
  Widget build(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    // Each label is centered under its circle and spills evenly either side.
    return Padding(
      padding: const .symmetric(horizontal: 28),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          for (final s in OnboardingStep.values) ...[
            if (s.index > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const .only(top: 13, left: 6, right: 6),
                  decoration: BoxDecoration(
                    color: s.index <= vm.reached.index ? c.primary : c.border,
                    borderRadius: .circular(1),
                  ),
                ),
              ),
            _StepDot(vm: vm, step: s),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const new({required this.vm, required this.step});
  final OnboardingViewModel vm;
  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final s = step;
    final count = OnboardingStep.values.length;
    final current = s == vm.step;
    final done = s.index < vm.reached.index && !current;
    final upcoming = s.index > vm.reached.index;
    return Pressable(
      onPressed: s.index <= vm.reached.index && !current ? () => vm.goTo(s) : null,
      selected: current,
      semanticLabel: 'Step ${s.index + 1} of $count, ${s.label}${done ? ', done' : ''}',
      builder: (context, state) => SizedBox(
        width: 28,
        child: Column(
          spacing: 6,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 28,
              height: 28,
              alignment: .center,
              decoration: BoxDecoration(
                shape: .circle,
                color: current || done ? c.primary : c.background,
                border: Border.all(color: current || done ? c.primary : c.border, width: 1.5),
                boxShadow: current
                    ? [BoxShadow(color: c.primary.withValues(alpha: .25), spreadRadius: 4)]
                    : null,
              ),
              child: done
                  ? AshlarIcon(AshlarIconsRoundedStroke.check, size: 14, color: c.primaryForeground)
                  : Text(
                      '${s.index + 1}',
                      style: t.text.xs.copyWith(
                        fontWeight: .w600,
                        color: current ? c.primaryForeground : c.mutedForeground,
                      ),
                    ),
            ),
            SizedBox(
              height: 16,
              child: OverflowBox(
                maxWidth: 120,
                child: Text(
                  s.label,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: .center,
                  style: t.text.xs.copyWith(
                    fontWeight: current ? .w600 : .w500,
                    color: upcoming
                        ? c.mutedForeground
                        : state.hovered && state.enabled
                        ? c.foreground.withValues(alpha: .7)
                        : c.foreground,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One step: Helmy and the steps at the top, the step's own content under
/// them (scrolling when it is long), and its actions in a bar along the foot.
class _Step extends StatelessWidget {
  const new({required this.vm, required this.body, required this.footer});
  final OnboardingViewModel vm;
  final List<Widget> body;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Expanded(
          child: ScrollArea(
            child: Padding(
              // Room at the top for the window's buttons.
              padding: const .fromLTRB(28, 36, 28, 20),
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 14,
                children: [
                  _Header(vm: vm),
                  ...body,
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const .fromLTRB(28, 12, 28, 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.colors.border)),
          ),
          child: footer,
        ),
      ],
    );
  }
}

/// Rows of a step's choices, in a bordered box.
class _Box extends StatelessWidget {
  const new({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusLg),
      ),
      clipBehavior: .antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          for (final (i, w) in children.indexed) ...[
            if (i > 0) Container(height: 1, color: t.colors.border),
            w,
          ],
        ],
      ),
    );
  }
}

/// A square of the theme's quiet color with an icon in it, at the start of
/// a row.
class _Tile extends StatelessWidget {
  const new(this.icon, {this.logo});
  final IconData icon;

  /// A connection's id, for its own logo in place of [icon] (ConnectionLogo).
  final String? logo;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Container(
      width: 34,
      height: 34,
      alignment: .center,
      decoration: BoxDecoration(color: t.colors.muted, borderRadius: .circular(t.radiusMd + 2)),
      child: logo != null && ConnectionLogo.assetFor(logo!) != null
          ? ConnectionLogo(logo!, size: 17)
          : AshlarIcon(icon, size: 17, color: t.colors.foreground),
    );
  }
}

/// A step's actions: a quiet way out at the start, Back and the main action
/// together at the end.
class _Footer extends StatelessWidget {
  const new({this.start, this.onBack, required this.main});
  final Widget? start;
  final VoidCallback? onBack;
  final Widget main;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 8,
    children: [
      ?start,
      const Spacer(),
      if (onBack case final back?)
        Button(
          variant: .secondary,
          onPressed: back,
          leading: const AshlarIcon(AshlarIconsRoundedStroke.arrowLeft, size: 14),
          child: const Text('Back'),
        ),
      main,
    ],
  );
}

// Step 1.

class _ConnectionsStep extends StatelessWidget {
  const new({required this.vm, required this.onSkip});
  final OnboardingViewModel vm;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final checks = vm.checks;
    return _Step(
      vm: vm,
      body: [
        if (checks == null)
          const Padding(
            padding: .all(16),
            child: Center(child: Spinner(size: 18)),
          )
        else
          _Box(
            children: [
              for (final c in checks) _ConnectionRow(vm: vm, c: c),
              if (vm.offersFree) _FreeRow(vm: vm),
              if (vm.offersAgents)
                for (final MapEntry(key: id, value: name) in subscriptionAgents.entries)
                  _AgentRow(vm: vm, id: id, name: name),
            ],
          ),
        // More accounts, more room: each has its own limits.
        if (checks != null)
          Wrap(
            spacing: 4,
            children: [
              for (final c in checks)
                if (c.state == .ready && (c.id == 'claude' || c.id == 'codex'))
                  Button(
                    variant: .ghost,
                    size: .sm,
                    onPressed: vm.adding != null
                        ? null
                        : () async {
                            final ok = await vm.addAccount(c.id);
                            if (!context.mounted || ok) return;
                            showToast(
                              context,
                              title: "The account wasn't added",
                              description:
                                  'Sign-in in the browser did not finish. Try again when ready.',
                              type: .error,
                            );
                          },
                    leading: vm.adding == c.id
                        ? const Spinner(size: 14)
                        : const AshlarIcon(AshlarIconsRoundedStroke.plus, size: 14),
                    child: Text(
                      vm.adding == c.id
                          ? 'Signing in, in your browser…'
                          : 'Add another ${c.name} account',
                    ),
                  ),
            ],
          ),
      ],
      footer: _Footer(
        start: vm.anyReady
            ? null
            : Button(variant: .ghost, onPressed: onSkip, child: const Text('Skip for now')),
        main: Button(
          onPressed: vm.anyReady && vm.busy == null ? vm.next : null,
          trailing: const AshlarIcon(AshlarIconsRoundedStroke.arrowRight, size: 14),
          child: const Text('Continue'),
        ),
      ),
    );
  }
}

/// Cursor, Grok or Antigravity: added when the person pays for it and asks,
/// installed by Helmy and signed in the agent's own way. On once added.
class _AgentRow extends StatelessWidget {
  const new({required this.vm, required this.id, required this.name});
  final OnboardingViewModel vm;
  final String id, name;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final busy = vm.agentBusy[id];
    final trouble = vm.agentTrouble[id];
    final added = vm.agentAdded(id);
    final on = vm.used('acp.$id');
    final status =
        busy ??
        trouble ??
        (!added
            ? 'If you pay for $name, add it: Helmy installs it, you sign in once'
            : on
            ? 'Ready'
            : 'Not used by Helmy. Switch it on to use it.');
    return Padding(
      padding: const .symmetric(horizontal: 14, vertical: 12),
      child: Row(
        spacing: 12,
        children: [
          _Tile(AshlarIconsRoundedStroke.aiAgent, logo: 'acp.$id'),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(name, style: t.text.sm.copyWith(fontWeight: .w600)),
                Text(
                  status,
                  style: t.text.xs.copyWith(
                    color: trouble != null && busy == null
                        ? t.colors.destructive
                        : t.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          if (busy != null)
            const Spinner(size: 16)
          else if (added && trouble == null)
            Switch(
              value: on,
              semanticLabel: 'Use $name',
              onChanged: (v) => vm.setUsed('acp.$id', v),
            )
          else
            Button(
              variant: .outline,
              size: .sm,
              onPressed: () => vm.addAgent(id),
              child: Text(trouble == null ? 'Add' : 'Check again'),
            ),
        ],
      ),
    );
  }
}

/// OpenCode on its free models: no account, so Helmy answers from the
/// first message. Set up by itself when nothing else could answer.
class _FreeRow extends StatelessWidget {
  const new({required this.vm});
  final OnboardingViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final trouble = vm.freeTrouble;
    final on = vm.used(freeAgentId);
    final status = vm.freeBusy
        ? 'Setting it up, a minute or so…'
        : trouble ??
              (!vm.freeAdded
                  ? 'Free models, no account needed'
                  : on
                  ? 'Ready · free models, no account needed'
                  : 'Not used by Helmy. Switch it on to use it.');
    return Padding(
      padding: const .symmetric(horizontal: 14, vertical: 12),
      child: Row(
        spacing: 12,
        children: [
          const _Tile(AshlarIconsRoundedStroke.sparkles, logo: freeAgentId),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text('OpenCode', style: t.text.sm.copyWith(fontWeight: .w600)),
                Text(
                  status,
                  style: t.text.xs.copyWith(
                    color: trouble != null && !vm.freeBusy
                        ? t.colors.destructive
                        : t.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          if (vm.freeBusy)
            const Spinner(size: 16)
          else if (vm.freeAdded)
            Switch(
              value: on,
              semanticLabel: 'Use OpenCode',
              onChanged: (v) => vm.setUsed(freeAgentId, v),
            )
          else
            Button(
              variant: .outline,
              size: .sm,
              onPressed: vm.busy == null ? vm.addFree : null,
              child: Text(trouble == null ? 'Add' : 'Try again'),
            ),
        ],
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const new({required this.vm, required this.c});
  final OnboardingViewModel vm;
  final ConnectionCheck c;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final busy = vm.busy == c.id;
    final trouble = vm.trouble[c.id];
    final added = vm.added[c.id];
    final on = vm.used(c.id);
    final who = vm.who[c.id];
    final status = busy
        ? vm.doing
        : trouble ??
              switch (c.state) {
                // Off: Helmy leaves it be. On: whose it is, so the choice is
                // plain.
                .ready when !on => 'Not used by Helmy. Switch it on to use it.',
                .ready => [
                  if (vm.found?.contains(c.id) ?? false) 'Found on this Mac',
                  who == null ? c.does : 'Signed in as $who',
                  if (added != null) '$added more account${added == 1 ? '' : 's'}',
                ].join(' · '),
                .missing => 'Not on this Mac yet',
                .signedOut =>
                  c.id == 'ollama' ? 'Installed, not running' : 'Installed, not signed in',
              };
    return Padding(
      padding: const .symmetric(horizontal: 14, vertical: 12),
      child: Row(
        spacing: 12,
        children: [
          _Tile(switch (c.id) {
            'claude' => AshlarIconsRoundedStroke.terminal,
            'codex' => AshlarIconsRoundedStroke.code,
            _ => AshlarIconsRoundedStroke.cpu,
          }, logo: c.id),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(vm.shownName(c), style: t.text.sm.copyWith(fontWeight: .w600)),
                Text(
                  status,
                  style: t.text.xs.copyWith(
                    color: trouble != null && !busy
                        ? t.colors.destructive
                        : t.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const Spinner(size: 16)
          else if (c.state == .ready)
            // A found connection is used only when the person switches it on.
            Row(
              mainAxisSize: .min,
              spacing: 8,
              children: [
                // Found as it was: its name, which account, which copy runs,
                // all changeable here.
                Button(
                  variant: .ghost,
                  size: .sm,
                  onPressed: vm.busy != null || vm.adding != null
                      ? null
                      : () => editConnection(context, vm, c),
                  child: const Text('Edit'),
                ),
                Switch(
                  value: on,
                  semanticLabel: 'Use ${c.name}',
                  onChanged: (v) => vm.setUsed(c.id, v),
                ),
              ],
            )
          else
            Button(
              variant: .outline,
              size: .sm,
              onPressed: vm.busy == null ? () => vm.act(c) : null,
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

/// Edits connection [c] as found: its name, which account Helmy uses for
/// it (another, signed in now or from a folder already signed in, in its
/// place), and which installed copy runs.
Future<void> editConnection(BuildContext context, OnboardingViewModel vm, ConnectionCheck c) =>
    showAshlarDialog<void>(
      context: context,
      builder: (context) => _EditConnection(vm: vm, c: c),
    );

class _EditConnection extends StatefulWidget {
  const _EditConnection({required this.vm, required this.c});
  final OnboardingViewModel vm;
  final ConnectionCheck c;

  @override
  State<_EditConnection> createState() => _EditConnectionState();
}

class _EditConnectionState extends State<_EditConnection> {
  late final _name = TextEditingController(text: widget.vm.nameOf(widget.c.id));
  String? _trouble;
  bool _signingIn = false;
  late Future<String?> _program = widget.vm.programOf(widget.c.id);

  OnboardingViewModel get vm => widget.vm;
  ConnectionCheck get c => widget.c;
  bool get _accounts => c.id != 'ollama';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _anotherAccount() async {
    setState(() {
      _signingIn = true;
      _trouble = null;
    });
    final ok = await vm.useAnotherAccount(c.id, _name.text);
    if (!mounted) return;
    if (ok) return Navigator.pop(context);
    setState(() {
      _signingIn = false;
      _trouble = "The sign-in didn't finish, so nothing changed. Try again when ready.";
    });
  }

  Future<void> _folder() async {
    final folder = await getDirectoryPath(
      initialDirectory: homeDir,
      confirmButtonText: 'Use this account',
    );
    if (folder == null || !mounted) return;
    final why = await vm.useAccountFolder(c.id, _name.text, folder);
    if (!mounted) return;
    if (why == null) return Navigator.pop(context);
    setState(() => _trouble = why);
  }

  Future<void> _choose() async {
    final file = await openFile(confirmButtonText: 'Use this program');
    if (file == null) return;
    await vm.setProgram(c.id, file.path);
    if (mounted) setState(() => _program = vm.programOf(c.id));
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final label = t.text.sm.copyWith(fontWeight: .w500);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground, height: 1.4);
    final who = vm.who[c.id];
    return HelmyDialog(
      title: 'Edit ${c.name}',
      icon: AshlarIconsRoundedStroke.pencil,
      maxWidth: 460,
      content: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: [
          Text('Name', style: label),
          const SizedBox(height: 2),
          Text('To tell it apart from other accounts, as "${c.name} (Personal)".', style: muted),
          const SizedBox(height: 6),
          Input(
            controller: _name,
            enabled: !_signingIn,
            placeholder: 'Personal',
            semanticLabel: 'Name',
          ),
          if (_accounts) ...[
            const SizedBox(height: 18),
            Text('Account', style: label),
            const SizedBox(height: 2),
            Text(
              who == null ? 'Signed in on this Mac.' : 'Signed in as $who on this Mac.',
              style: muted,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Button(
                  variant: .outline,
                  size: .sm,
                  onPressed: _signingIn ? null : _anotherAccount,
                  child: Text(_signingIn ? 'Signing in, in your browser...' : 'Sign in to another'),
                ),
                Button(
                  variant: .outline,
                  size: .sm,
                  onPressed: _signingIn ? null : _folder,
                  child: const Text('Use a signed-in folder...'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Another account is used in its place; this one stays signed in on your Mac '
              'for the ${c.name} you run yourself.',
              style: muted,
            ),
          ],
          const SizedBox(height: 18),
          Text('Program', style: label),
          const SizedBox(height: 6),
          FutureBuilder(
            future: _program,
            builder: (context, snap) => Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    snap.connectionState != .done
                        ? 'Finding it...'
                        : snap.data == null
                        ? 'Not found.'
                        : '${vm.programChosen(c.id) ? 'Chosen' : 'Found'}: ${tildePath(snap.data!)}',
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: muted,
                  ),
                ),
                if (vm.programChosen(c.id))
                  Button(
                    variant: .ghost,
                    size: .xs,
                    onPressed: () async {
                      await vm.setProgram(c.id, null);
                      if (mounted) setState(() => _program = vm.programOf(c.id));
                    },
                    child: const Text('Find it again'),
                  ),
                Button(
                  variant: .outline,
                  size: .xs,
                  onPressed: _choose,
                  child: const Text('Choose...'),
                ),
              ],
            ),
          ),
          if (_trouble != null) ...[
            const SizedBox(height: 12),
            Text(_trouble!, style: muted.copyWith(color: t.colors.destructive)),
          ],
        ],
      ),
      actions: [
        Button(
          variant: .outline,
          onPressed: _signingIn ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        Button(
          onPressed: _signingIn
              ? null
              : () async {
                  await vm.setName(c.id, _name.text);
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// Step 2.

class _ChatsStep extends StatelessWidget {
  const new({required this.vm, required this.onBringIn});
  final OnboardingViewModel vm;
  final Future<void> Function() onBringIn;

  @override
  Widget build(BuildContext context) {
    final importer = vm.import;
    final projects = importer?.projects;
    final busy = importer?.progress != null;
    final n = importer?.chosenConversations ?? 0;
    final t = AshlarTheme.of(context);
    return _Step(
      vm: vm,
      body: [
        if (importer != null) _Box(children: [ImportList(vm: importer, action: false)]),
        if (importer?.progress case (final done, final of))
          Text(
            'Bringing in $done of $of…',
            style: t.text.xs.copyWith(color: t.colors.mutedForeground),
          ),
      ],
      footer: _Footer(
        start: projects != null && projects.isNotEmpty
            ? Button(
                variant: .ghost,
                onPressed: busy ? null : vm.next,
                child: const Text("Don't bring any in"),
              )
            : null,
        onBack: busy ? null : () => vm.goTo(.connections),
        main: Button(
          // Waits while the folders are looked for, if there is a look.
          onPressed: busy || (importer != null && projects == null)
              ? null
              : n == 0
              ? vm.next
              : onBringIn,
          leading: busy ? const Spinner(size: 14) : null,
          trailing: busy || n > 0
              ? null
              : const AshlarIcon(AshlarIconsRoundedStroke.arrowRight, size: 14),
          child: Text(n == 0 ? 'Continue' : 'Bring in $n'),
        ),
      ),
    );
  }
}

// Step 3.

class _FoldersStep extends StatelessWidget {
  const new({required this.vm, required this.onDone});
  final OnboardingViewModel vm;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    return _Step(
      vm: vm,
      body: [
        _Box(
          children: [
            _Choice(
              icon: AshlarIconsRoundedStroke.message,
              title: 'No project',
              subtitle:
                  'Each new chat starts on its own; choose a folder from it when one is needed.',
              on: vm.start.mode == .none,
              onPressed: () => vm.choose((mode: .none, folder: null)),
            ),
            _Choice(
              icon: AshlarIconsRoundedStroke.messages,
              title: 'Where you last worked',
              subtitle: 'Each new chat opens in the folder of your last one.',
              on: vm.start.mode == .last,
              onPressed: () => vm.choose((mode: .last, folder: null)),
            ),
            for (final f in vm.folders)
              _Choice(
                icon: AshlarIconsRoundedStroke.folder,
                title: f == homeDir ? 'Home' : folderName(f),
                subtitle: 'Always in ${tildePath(f)}',
                on: vm.start.mode == .fixed && vm.start.folder == f,
                onPressed: () => vm.choose((mode: .fixed, folder: f)),
              ),
            _Choice(
              icon: AshlarIconsRoundedStroke.folderOpen,
              title: 'Choose another folder…',
              subtitle: 'Any folder on this Mac.',
              on: false,
              onPressed: () async {
                final dir = await getDirectoryPath(confirmButtonText: 'Start chats here');
                if (dir != null) vm.pick(dir);
              },
            ),
          ],
        ),
      ],
      footer: _Footer(
        onBack: () => vm.goTo(.chats),
        main: Button(
          onPressed: onDone,
          trailing: const AshlarIcon(AshlarIconsRoundedStroke.check, size: 14),
          child: const Text('Finish'),
        ),
      ),
    );
  }
}

/// One choice of several: its icon, what it is, and a dot when chosen.
class _Choice extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.on,
    required this.onPressed,
  });
  final IconData icon;
  final String title, subtitle;
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: onPressed,
      selected: on,
      semanticLabel: '$title, ${on ? 'chosen' : 'not chosen'}',
      builder: (context, state) => Container(
        padding: const .symmetric(horizontal: 14, vertical: 10),
        color: on
            ? c.accent
            : state.hovered
            ? c.accent.withValues(alpha: .5)
            : null,
        child: Row(
          spacing: 12,
          children: [
            _Tile(icon),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 1,
                children: [
                  Text(title, style: t.text.sm.copyWith(fontWeight: .w500)),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: t.text.xs.copyWith(color: c.mutedForeground),
                  ),
                ],
              ),
            ),
            Container(
              width: 16,
              height: 16,
              alignment: .center,
              decoration: BoxDecoration(
                shape: .circle,
                border: Border.all(color: on ? c.primary : c.border, width: 1.5),
              ),
              child: on
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(shape: .circle, color: c.primary),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// The end.

/// Every step done: Helmy celebrating, what was set up, and on into Helmy.
class _Finished extends StatelessWidget {
  const new({required this.vm, required this.onOpen});
  final OnboardingViewModel vm;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final ready = vm.readyCount;
    final imported = vm.import?.imported ?? 0;
    final folder = vm.start.folder;
    final lines = [
      (AshlarIconsRoundedStroke.plugConnected, '$ready AI tool${ready == 1 ? '' : 's'} ready'),
      (
        AshlarIconsRoundedStroke.messages,
        imported == 0
            ? 'No chats imported'
            : '$imported chat${imported == 1 ? '' : 's'} brought in',
      ),
      (
        AshlarIconsRoundedStroke.folder,
        switch (vm.start.mode) {
          .none => 'New chats start in no project',
          .last => 'New chats start where you last worked',
          .fixed =>
            'New chats start in ${folder == homeDir ? 'Home' : tildePath(folder ?? homeDir)}',
        },
      ),
    ];
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const .fromLTRB(40, 36, 40, 20),
              child: Column(
                mainAxisSize: .min,
                spacing: 14,
                children: [
                  const _Art('assets/helmy/onboarding-done.png', size: 140),
                  Text("You're all set", style: t.text.xl.copyWith(fontWeight: .w600)),
                  Text(
                    "Tell me what you want done, and I'll take it from there.",
                    textAlign: .center,
                    style: t.text.sm.copyWith(color: c.mutedForeground),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 380),
                    padding: const .symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: c.muted,
                      borderRadius: .circular(t.radiusLg + 4),
                    ),
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 10,
                      children: [
                        for (final (icon, text) in lines)
                          Row(
                            spacing: 10,
                            children: [
                              AshlarIcon(icon, size: 16, color: c.foreground),
                              Expanded(child: Text(text, style: t.text.sm)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const .fromLTRB(28, 12, 28, 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: _Footer(
            main: Button(
              onPressed: onOpen,
              trailing: const AshlarIcon(AshlarIconsRoundedStroke.arrowRight, size: 14),
              child: const Text('Open Helmy'),
            ),
          ),
        ),
      ],
    );
  }
}
