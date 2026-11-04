import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/pull_requests.dart';
import '../../utils/format.dart';
import '../core/ashlar/button.dart';
import '../core/ashlar/input.dart';
import '../core/ashlar/pressable.dart';
import '../core/ashlar/scroll_area.dart';
import '../core/ashlar/select.dart';
import '../core/ashlar/spinner.dart';
import '../core/ashlar/theme.dart';
import '../core/ashlar/tooltip.dart';
import 'pull_requests_view_model.dart';

/// Every open pull request in the projects worked in here, newest first:
/// searched, sorted, the user's own or everyone's, as T3 Code's list. A
/// press opens the session that made one, else it on GitHub; Review asks
/// Helmy to review it in a session of its own.
class PullRequestsScreen extends StatefulWidget {
  const PullRequestsScreen({super.key, required this.viewModel});
  final PullRequestsViewModel viewModel;

  @override
  State<PullRequestsScreen> createState() => _PullRequestsScreenState();
}

class _PullRequestsScreenState extends State<PullRequestsScreen> {
  PullRequestsViewModel get vm => widget.viewModel;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (vm.all == null) vm.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.sm.copyWith(color: c.mutedForeground, height: 1.5);
    return ColoredBox(
      color: c.background,
      child: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          final shown = vm.shown;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Padding(
                padding: const .fromLTRB(32, 40, 32, 0),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    Text('Pull requests', style: t.text.xl.copyWith(fontWeight: .w600)),
                    const SizedBox(height: 8),
                    Text(
                      'Open in every project your sessions work in. Search by words, or '
                      'label:, author:, repo:, is:draft.',
                      style: muted,
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, box) {
                        final narrow = box.maxWidth < 560;
                        final controls = [
                          SizedBox(
                            width: 170,
                            child: Select<PrSort>(
                              value: vm.sort,
                              semanticLabel: 'Sort',
                              options: [for (final s in PrSort.values) SelectOption(s, s.label)],
                              onChanged: vm.sortBy,
                            ),
                          ),
                          _Segment(
                            options: const ['All', 'Yours'],
                            chosen: vm.mine ? 1 : 0,
                            onChosen: (i) => vm.showMine(i == 1),
                          ),
                          Tooltip(
                            message: 'Look again',
                            child: Button(
                              variant: .outline,
                              size: .icon,
                              semanticLabel: 'Look again',
                              onPressed: vm.loading ? null : vm.load,
                              child: vm.loading
                                  ? const Spinner(size: 14)
                                  : const AshlarIcon(AshlarIconsRoundedStroke.refreshCw, size: 14),
                            ),
                          ),
                        ];
                        final search = Input(
                          controller: _search,
                          placeholder: 'Search pull requests, or label:bug',
                          leading: const AshlarIcon(AshlarIconsRoundedStroke.search, size: 14),
                          onChanged: vm.search,
                        );
                        return narrow
                            ? Column(
                                crossAxisAlignment: .stretch,
                                spacing: 8,
                                children: [
                                  search,
                                  Wrap(spacing: 8, runSpacing: 8, children: controls),
                                ],
                              )
                            : Row(
                                spacing: 8,
                                children: [
                                  Expanded(child: search),
                                  ...controls,
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(child: _body(context, shown)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, List<PullRequest> shown) {
    final t = AshlarTheme.of(context);
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.5);
    Widget empty(String title, String body, {Widget? action}) => Center(
      child: Column(
        mainAxisSize: .min,
        spacing: 8,
        children: [
          AshlarIcon(
            AshlarIconsRoundedStroke.gitPullRequest,
            size: 28,
            color: t.colors.mutedForeground,
          ),
          Text(title, style: t.text.base.copyWith(fontWeight: .w600)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(body, textAlign: .center, style: muted),
          ),
          ?action,
        ],
      ),
    );
    if (vm.all == null) return const Center(child: Spinner(size: 18));
    switch (vm.problem) {
      case 'missing':
        return empty(
          "GitHub's command isn't installed",
          'Helmy reads pull requests through it (gh). Install it, then look again.',
          action: Button(
            size: .sm,
            onPressed: () => vm.openUrl('https://cli.github.com'),
            child: const Text('Get it'),
          ),
        );
      case 'signedOut':
        return empty(
          'Sign in to GitHub',
          "GitHub's command is installed but not signed in, so pull requests can't be read.",
          action: Button(size: .sm, onPressed: vm.signIn, child: const Text('Sign in')),
        );
    }
    if (vm.folders.isEmpty) {
      return empty(
        'No projects yet',
        'Pull requests show here for the projects your sessions work in.',
      );
    }
    if (vm.all!.isEmpty) {
      return empty(
        'No pull requests',
        'None open in the projects your sessions work in.',
        action: Button(
          variant: .outline,
          size: .sm,
          onPressed: vm.load,
          child: const Text('Look again'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Padding(
          padding: const .only(bottom: 6),
          child: Text(
            ['${shown.length} of ${vm.all!.length} open', ?vm.problem].join('. '),
            style: t.text.xs.copyWith(color: t.colors.mutedForeground),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text('None match.', style: muted))
              : ScrollArea.builder(
                  padding: const .only(bottom: 24),
                  itemCount: shown.length,
                  itemBuilder: (context, i) => _Row(pr: shown[i], vm: vm),
                ),
        ),
      ],
    );
  }
}

/// One pull request: its project and number, title, branch and author, how
/// its checks and review stand; Review and GitHub under the mouse.
class _Row extends StatelessWidget {
  const _Row({required this.pr, required this.vm});
  final PullRequest pr;
  final PullRequestsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.xs.copyWith(color: c.mutedForeground);
    final session = vm.sessionOf(pr);
    final now = DateTime.now();
    return Pressable(
      onPressed: () => session == null ? vm.openOnGitHub(pr) : context.go('/s/${session.id}'),
      semanticLabel: '#${pr.number} ${pr.title}',
      builder: (context, state) => Container(
        padding: const .symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: state.hovered ? c.accent.withValues(alpha: .5) : null,
          borderRadius: .circular(t.radiusMd),
        ),
        child: Row(
          spacing: 12,
          children: [
            _ChecksMark(state: pr.checks),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 3,
                children: [
                  Text(
                    pr.title,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: t.text.sm.copyWith(fontWeight: .w500),
                  ),
                  Text(
                    [
                      '${pr.repo.split('/').last} #${pr.number}',
                      pr.branch,
                      pr.author,
                      ago(pr.updatedAt, now: now),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: muted,
                  ),
                ],
              ),
            ),
            // Under the mouse, what can be done with it, in place of how it stands.
            if (state.hovered || state.focused) ...[
              Button(
                variant: .outline,
                size: .xs,
                onPressed: () async {
                  final id = await vm.review(pr);
                  if (id != null && context.mounted) context.go('/s/$id');
                },
                child: const Text('Review'),
              ),
              Tooltip(
                message: 'Open on GitHub',
                child: Button(
                  variant: .ghost,
                  size: .iconXs,
                  semanticLabel: 'Open on GitHub',
                  onPressed: () => vm.openOnGitHub(pr),
                  child: const AshlarIcon(AshlarIconsRoundedStroke.externalLink, size: 13),
                ),
              ),
            ] else ...[
              if (pr.draft) _Chip('Draft', color: c.mutedForeground),
              if (pr.review case final r?)
                _Chip(
                  switch (r) {
                    'APPROVED' => 'Approved',
                    'CHANGES_REQUESTED' => 'Changes asked',
                    _ => 'Review needed',
                  },
                  color: r == 'APPROVED'
                      ? const Color(0xFF57AB5A)
                      : r == 'CHANGES_REQUESTED'
                      ? c.destructive
                      : c.mutedForeground,
                ),
              for (final l in pr.labels.take(2)) _Chip(l, color: c.mutedForeground),
              if (session != null)
                Tooltip(
                  message: 'Made in a session here: opens it',
                  child: AshlarIcon(
                    AshlarIconsRoundedStroke.messageSquareText,
                    size: 14,
                    color: c.mutedForeground,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// How the checks stand, as a mark: unknown while they are read.
class _ChecksMark extends StatelessWidget {
  const _ChecksMark({required this.state});
  final ChecksState? state;

  @override
  Widget build(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    final (icon, color, words) = switch (state) {
      null => (null, c.mutedForeground, 'Reading its checks...'),
      .passing => (AshlarIconsRoundedStroke.circleCheck, const Color(0xFF57AB5A), 'Checks pass'),
      .failing => (AshlarIconsRoundedStroke.circleX, c.destructive, 'A check failed'),
      .running => (AshlarIconsRoundedStroke.loader, const Color(0xFFC69026), 'Checks running'),
      .none => (AshlarIconsRoundedStroke.circleDashed, c.mutedForeground, 'No checks'),
    };
    return Tooltip(
      message: words,
      child: SizedBox.square(
        dimension: 16,
        child: icon == null ? const Spinner(size: 12) : AshlarIcon(icon, size: 16, color: color),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Container(
      padding: const .symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: .45)),
        borderRadius: .circular(999),
      ),
      child: Text(text, style: t.text.xs.copyWith(color: color, fontSize: 11)),
    );
  }
}

/// Two or more choices side by side, one chosen.
class _Segment extends StatelessWidget {
  const _Segment({required this.options, required this.chosen, required this.onChosen});
  final List<String> options;
  final int chosen;
  final ValueChanged<int> onChosen;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Container(
      padding: const .all(2),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: .circular(t.radiusMd),
      ),
      child: Row(
        mainAxisSize: .min,
        children: [
          for (final (i, o) in options.indexed)
            Pressable(
              onPressed: () => onChosen(i),
              semanticLabel: o,
              builder: (context, state) => Container(
                padding: const .symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: i == chosen
                      ? c.accent
                      : (state.hovered ? c.accent.withValues(alpha: .4) : null),
                  borderRadius: .circular(t.radiusSm),
                ),
                child: Text(o, style: t.text.sm.copyWith(fontWeight: i == chosen ? .w500 : .w400)),
              ),
            ),
        ],
      ),
    );
  }
}
