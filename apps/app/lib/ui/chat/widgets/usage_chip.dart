import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/connections_setup.dart';
import '../../../data/services/engines/engine_registry.dart';
import '../../../data/services/engines/usage_meter.dart';
import '../../../domain/usage_summary.dart';
import '../../../utils/format.dart';
import '../../core/ashlar/hover_card.dart';
import '../../core/ashlar/popover.dart';
import '../../core/ashlar/theme.dart';

/// How much room Helmy has, in the top bar, beside the context: the plan
/// with the most room, as a small meter, and every plan a hover away. It
/// names no connection until asked: the card that opens is the asking.
/// Only what was measured is shown; a reading from before a window reset is
/// unknown, and an old one says how old.
class UsageChip extends StatelessWidget {
  const UsageChip({super.key});

  @override
  Widget build(BuildContext context) {
    // A narrow window keeps its top bar for the title.
    if (MediaQuery.sizeOf(context).width < 640) return const SizedBox.shrink();
    final UsageSummary summary;
    try {
      final meter = context.watch<UsageMeter>();
      final settings = context.watch<SettingsRepository>().settings;
      summary = UsageSummary.of(
        engines: [for (final e in context.read<EngineRegistry>().engines) e.info],
        uses: settings.uses,
        usage: meter.usageOf,
        name: (e) => ConnectionsSetup.shownName(e.id, e.name, settings.connectionNames),
      );
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    if (summary.isEmpty) return const SizedBox.shrink();
    final t = AshlarTheme.of(context);
    final best = summary.roomiest;
    final shown = best?.windows.take(2).toList() ?? const <WindowNow>[];
    return HoverCard(
      openDelay: const Duration(milliseconds: 250),
      align: PopoverAlign.end,
      width: 300,
      content: (context) => _Card(summary: summary),
      child: Semantics(
        label: best?.used == null
            ? 'Usage not known yet'
            : 'Usage ${(best!.used! * 100).round()} percent',
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: t.colors.muted, borderRadius: BorderRadius.circular(6)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 7,
            children: [
              Text('Usage', style: t.text.xs),
              if (shown.isNotEmpty)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 3,
                  children: [for (final w in shown) _Bar(used: w.used, width: 40, height: 3)],
                ),
              Text(
                best?.used == null ? '?' : '${(best!.used! * 100).round()}%',
                style: t.text.xs.copyWith(color: t.colors.mutedForeground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.used, required this.width, required this.height, this.faded = false});
  final double? used;
  final double width, height;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    final u = used;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(height)),
      alignment: Alignment.centerLeft,
      child: u == null
          ? null
          : FractionallySizedBox(
              widthFactor: u.clamp(0.0, 1.0),
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: u >= UsageMeter.switchAt
                      ? c.destructive
                      : faded
                      ? c.mutedForeground
                      : c.foreground,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
    );
  }
}

/// Every plan, each window as it stands, when it resets, and how fresh the
/// reading is.
class _Card extends StatelessWidget {
  const _Card({required this.summary});
  final UsageSummary summary;

  /// Older than this, a reading is said with its age.
  static const _fresh = Duration(hours: 1);

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Text('Usage', style: t.text.sm.copyWith(fontWeight: FontWeight.w600)),
        Text(
          summary.plans.length > 1
              ? 'Helmy sends each message where there is room.'
              : 'How much of your plan is used.',
          style: muted,
        ),
        for (final p in summary.plans) ...[
          const SizedBox(height: 8),
          Text(p.name, style: t.text.xs.copyWith(fontWeight: FontWeight.w600)),
          if (p.windows.isEmpty)
            Text('Not known yet: it says with its first answer.', style: muted)
          else
            for (final w in p.windows) ...[
              Row(
                spacing: 10,
                children: [
                  SizedBox(width: 64, child: Text(windowName(w.name), style: muted)),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => _Bar(
                        used: w.used,
                        width: box.maxWidth,
                        height: 5,
                        faded: p.readAt != null && now.difference(p.readAt!) > _fresh,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      w.used == null ? '?' : '${(w.used! * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: w.used == null ? muted : t.text.xs,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 74),
                child: Text(_note(w, p.readAt, now), style: muted),
              ),
            ],
        ],
      ],
    );
  }

  static String _note(WindowNow w, DateTime? readAt, DateTime now) {
    if (w.used == null) {
      return readAt == null
          ? 'Not known yet'
          : 'Not known: reset since it was read ${ago(readAt, now: now)} ago';
    }
    final parts = [
      if (readAt != null && now.difference(readAt) > _fresh) 'As of ${ago(readAt, now: now)} ago',
      if (w.resetsAt case final r?) 'resets ${_when(r, now)}',
    ];
    final s = parts.join(' · ');
    return s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
  }

  static String _when(DateTime when, DateTime now) {
    final d = when.difference(now);
    if (d.inMinutes < 1) return 'in a moment';
    if (d.inHours < 1) return 'in ${d.inMinutes}m';
    if (d.inDays < 1) return 'in ${d.inHours}h ${d.inMinutes % 60}m';
    return 'in ${d.inDays}d ${d.inHours % 24}h';
  }
}
