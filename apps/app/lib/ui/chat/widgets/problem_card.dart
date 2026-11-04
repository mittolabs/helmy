import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/problem.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/collapsible.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/theme.dart';
import '../view_models/chat_view_model.dart';

/// A problem, where it happened: what went wrong and why, the one action
/// that fixes it, and the raw details a press away.
class ProblemCard extends StatefulWidget {
  const ProblemCard({super.key, required this.problem, required this.vm, this.last = true});
  final Problem problem;
  final ChatViewModel vm;

  /// Whether it is the latest thing in the conversation. An earlier problem
  /// keeps its words but no longer offers to act: what came after moved on.
  final bool last;

  @override
  State<ProblemCard> createState() => _ProblemCardState();
}

class _ProblemCardState extends State<ProblemCard> {
  bool _working = false;
  String? _after;

  Future<void> _act() async {
    final p = widget.problem;
    setState(() {
      _working = true;
      _after = null;
    });
    await runFix(context, p.fix, widget.vm, engineId: p.engineId, onNote: (n) => _after = n);
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final p = widget.problem;
    final act = widget.last && p.fix != .wait && !widget.vm.busy;
    return Container(
      padding: const .all(12),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 8,
        children: [
          Row(
            crossAxisAlignment: .start,
            spacing: 10,
            children: [
              Padding(
                padding: const .only(top: 2),
                child: AshlarIcon(
                  AshlarIconsRoundedStroke.circleAlert,
                  size: 14,
                  color: t.colors.mutedForeground,
                ),
              ),
              Expanded(child: Text(p.what, style: t.text.sm)),
            ],
          ),
          if (act || _after != null)
            Padding(
              padding: const .only(left: 24),
              child: Row(
                spacing: 10,
                children: [
                  if (act)
                    Button(
                      variant: .outline,
                      size: .sm,
                      onPressed: _working ? null : _act,
                      leading: _working ? const Spinner(size: 12) : null,
                      child: Text(p.fix.label),
                    ),
                  if (_after case final note?)
                    Flexible(
                      child: Text(note, style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
                    ),
                ],
              ),
            ),
          if (p.details case final details?)
            Padding(
              padding: const .only(left: 24),
              child: Collapsible(
                builder: (context, open, toggle) => Button(
                  variant: .ghost,
                  size: .xs,
                  onPressed: toggle,
                  child: Text(open ? 'Hide details' : 'Details'),
                ),
                child: Padding(
                  padding: const .only(top: 6),
                  child: Text(
                    details,
                    style: t.text.xs.copyWith(
                      fontFamily: 'monospace',
                      fontFamilyFallback: const ['Menlo', 'Consolas', 'Roboto Mono'],
                      color: t.colors.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Carries out [fix] for this conversation. Signing in or starting what
/// stopped, when it works, sends the message again; [onNote] hears what to
/// say when the user has to finish it elsewhere.
Future<void> runFix(
  BuildContext context,
  Fix fix,
  ChatViewModel vm, {
  String? engineId,
  void Function(String note)? onNote,
}) async {
  switch (fix) {
    case .retry:
      await vm.retry();
    case .setup:
      context.go('/setup');
    case .wait:
      break;
    case .signIn || .startLocal:
      final ok = await vm.applyFix(fix, engineId: engineId);
      if (ok) {
        await vm.retry();
      } else {
        onNote?.call(
          fix == .signIn
              ? "That didn't finish. Set up has every sign-in."
              : "It didn't start. Set up can install it.",
        );
      }
    case .allowSpeech || .allowNotifications:
      final ok = await vm.applyFix(fix);
      onNote?.call(
        ok
            ? 'Turn Helmy on in the window that opened, then try again.'
            : "This system has no setting for it that I can open.",
      );
    case .installDeviceInput:
      final ok = await vm.applyFix(fix);
      onNote?.call(
        ok
            ? 'Installed. Taps and typing reach iOS simulators now.'
            : "It didn't install. It comes through Homebrew, from brew.sh.",
      );
  }
}

/// Opens a link an answer gave: a `helmy://fix/...` link does its fix here,
/// anything else opens in its own app.
void openAnswerLink(BuildContext context, String url, ChatViewModel vm) {
  if (Fix.fromLink(url) case final fix?) {
    unawaited(runFix(context, fix, vm));
    return;
  }
  unawaited(vm.open(url));
}
