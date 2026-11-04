import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/ship_repository.dart';
import '../../../data/services/shipping.dart';
import '../../../domain/models/session.dart';
import '../../../utils/format.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/switch.dart';
import '../../core/ashlar/theme.dart';
import '../view_models/chat_view_model.dart';

/// Beside the conversation: this session's work on its way to merged. The
/// branch, what is not committed or pushed, the pull request and its
/// checks; the agent asked to commit and to open the pull request; and the
/// checks watched, a failure going back to the agent to fix.
class ShipPanel extends StatefulWidget {
  const ShipPanel({super.key, required this.vm});
  final ChatViewModel vm;

  @override
  State<ShipPanel> createState() => _ShipPanelState();
}

class _ShipPanelState extends State<ShipPanel> {
  bool _busyBefore = false;

  @override
  void initState() {
    super.initState();
    widget.vm.addListener(_onVm);
    _refresh();
  }

  /// Asked again whenever a turn ends: the agent may have committed or pushed.
  void _onVm() {
    final busy = widget.vm.busy;
    if (_busyBefore && !busy) _refresh();
    _busyBefore = busy;
  }

  void _refresh() {
    final s = widget.vm.session;
    if (s != null) unawaited(context.read<ShipRepository>().refresh(s));
  }

  @override
  void dispose() {
    widget.vm.removeListener(_onVm);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final ship = context.watch<ShipRepository>();
    final session = widget.vm.session;
    if (session == null) return const SizedBox.shrink();
    final s = ship.stateOf(session.id);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final busy = widget.vm.busy;
    Widget line(IconData icon, String text, {Color? color}) => Row(
      spacing: 8,
      children: [
        AshlarIcon(icon, size: 14, color: color ?? t.colors.mutedForeground),
        Expanded(child: Text(text, style: t.text.sm)),
      ],
    );
    return ScrollArea(
      child: Padding(
        padding: const .all(16),
        child: s == null
            ? const Center(child: Spinner(size: 16))
            : Column(
                crossAxisAlignment: .stretch,
                spacing: 12,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Ship', style: t.text.base.copyWith(fontWeight: .w600)),
                      ),
                      Button(
                        variant: .ghost,
                        size: .iconXs,
                        semanticLabel: 'Look again',
                        onPressed: _refresh,
                        child: const AshlarIcon(AshlarIconsRoundedStroke.refreshCw, size: 14),
                      ),
                    ],
                  ),
                  line(AshlarIconsRoundedStroke.gitBranch, s.branch),
                  if (session.ownCopy)
                    Text('Its own copy of ${folderName(session.repo!)}.', style: muted),
                  line(
                    AshlarIconsRoundedStroke.fileDiff,
                    s.uncommitted == 0
                        ? 'Everything is committed'
                        : '${s.uncommitted} ${s.uncommitted == 1 ? 'file' : 'files'} not committed',
                  ),
                  if (s.uncommitted > 0)
                    Button(
                      variant: .outline,
                      size: .sm,
                      onPressed: busy ? null : () => ship.commit(session),
                      child: const Text('Commit'),
                    ),
                  line(
                    AshlarIconsRoundedStroke.gitCommitHorizontal,
                    !s.pushed
                        ? 'Not pushed yet'
                        : s.unpushed == 0
                        ? 'Pushed'
                        : '${s.unpushed} ${s.unpushed == 1 ? 'commit' : 'commits'} not pushed',
                  ),
                  if (s.pr case final pr?) ...[
                    _PullRequest(pr: pr, vm: widget.vm),
                    _Watch(session: session),
                  ] else
                    Button(
                      size: .sm,
                      onPressed: busy || s.uncommitted > 0
                          ? null
                          : () => ship.openPullRequest(session),
                      child: const Text('Push and open a pull request'),
                    ),
                  if (s.pr == null && s.uncommitted > 0)
                    Text('Commit first: a pull request takes what is committed.', style: muted),
                ],
              ),
      ),
    );
  }
}

/// The pull request, opened in the browser on a press, and its checks.
class _PullRequest extends StatelessWidget {
  const _PullRequest({required this.pr, required this.vm});
  final PullRequest pr;
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Container(
      padding: const .all(12),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              AshlarIcon(
                AshlarIconsRoundedStroke.gitPullRequest,
                size: 14,
                color: t.colors.foreground,
              ),
              Expanded(
                child: Text(
                  '#${pr.number} ${pr.title}',
                  maxLines: 2,
                  overflow: .ellipsis,
                  style: t.text.sm.copyWith(fontWeight: .w500),
                ),
              ),
              Button(
                variant: .ghost,
                size: .xs,
                onPressed: () => vm.open(pr.url),
                child: Text(pr.state == 'OPEN' ? 'Open' : pr.state.toLowerCase()),
              ),
            ],
          ),
          if (pr.checks.isEmpty)
            Text('No checks.', style: t.text.xs.copyWith(color: t.colors.mutedForeground))
          else
            for (final c in pr.checks)
              Row(
                spacing: 8,
                children: [
                  switch (c.state) {
                    .pending => const Spinner(size: 12),
                    .passed => AshlarIcon(
                      AshlarIconsRoundedStroke.check,
                      size: 12,
                      color: t.colors.foreground,
                    ),
                    .failed => AshlarIcon(
                      AshlarIconsRoundedStroke.x,
                      size: 12,
                      color: t.colors.destructive,
                    ),
                    .skipped => AshlarIcon(
                      AshlarIconsRoundedStroke.minus,
                      size: 12,
                      color: t.colors.mutedForeground,
                    ),
                  },
                  Expanded(
                    child: Text(c.name, maxLines: 1, overflow: .ellipsis, style: t.text.xs),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

/// Watching the checks: on, a failure goes to the agent to fix, a pass to
/// the user.
class _Watch extends StatelessWidget {
  const _Watch({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Row(
      spacing: 12,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 2,
            children: [
              Text('Watch the checks', style: t.text.sm.copyWith(fontWeight: .w500)),
              Text(
                "When one fails, I fix it. When they all pass, you'll hear.",
                style: t.text.xs.copyWith(color: t.colors.mutedForeground),
              ),
            ],
          ),
        ),
        Switch(
          value: session.watchChecks,
          semanticLabel: 'Watch the checks',
          onChanged: (v) => context.read<ShipRepository>().watch(session, v),
        ),
      ],
    );
  }
}
