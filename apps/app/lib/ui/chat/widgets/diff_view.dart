import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../domain/models/settings.dart';
import '../../../utils/diff_rows.dart';
import '../../../utils/diffs.dart';
import '../../../utils/platform.dart';
import '../../core/ashlar/theme.dart';

/// One file's change: side by side where there is room for both, in one
/// column where there is not, in the colors chosen in Settings. Within a
/// changed line, what changed is marked. Long changes are cut, so the page
/// keeps a single scroll.
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.diff, this.maxRows = 200});
  final FileDiff diff;
  final int maxRows;

  /// From this wide, before and after side by side.
  static const sideBySideFrom = 640.0;

  @override
  Widget build(BuildContext context) {
    final settings = _settings(context);
    final hide = settings.diffHideSpace;
    final ink = _Ink.of(context, settings.diffColors);
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= sideBySideFrom;
        final t = AshlarTheme.of(context);
        final c = t.colors;
        final base = t.text.xs.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: monoFonts,
          height: 1.45,
        );
        final rows = wide ? sideBySide(diff.lines, hideSpace: hide) : null;
        final uni = wide ? null : unified(diff.lines, hideSpace: hide);
        final count = rows?.length ?? uni!.length;
        final numbered =
            (rows ?? const <SideRow>[]).any((r) => r.oldNo != null || r.newNo != null) ||
            (uni ?? const <UniRow>[]).any((r) => r.oldNo != null || r.newNo != null);
        // Wide enough for the largest line number.
        final last = diff.lines.length + 9999;
        final numberWidth = numbered ? 8.0 * '$last'.length.clamp(3, 6) : 0.0;
        Widget number(int? n) => numbered
            ? SizedBox(
                width: numberWidth,
                child: Text(
                  n == null ? '' : '$n',
                  textAlign: .right,
                  style: base.copyWith(color: c.mutedForeground.withValues(alpha: .6)),
                ),
              )
            : const SizedBox.shrink();
        Widget cell(String? text, DiffKind kind, {required bool before, String? other}) {
          final tone = switch (kind) {
            .added => ink.added,
            .removed => ink.removed,
            .changed => before ? ink.removed : ink.added,
            _ => null,
          };
          final style = base.copyWith(
            color: kind == .same || kind == .hunk ? c.mutedForeground : c.foreground,
            decoration: ink.none && (kind == .removed || (kind == .changed && before))
                ? TextDecoration.lineThrough
                : null,
          );
          final words = text ?? '';
          // In a changed pair, just what changed stands out.
          InlineSpan span = TextSpan(text: words.isEmpty ? ' ' : words, style: style);
          // Struck through: the code, not the indent before it.
          if (style.decoration == TextDecoration.lineThrough) {
            final indent = RegExp(r'^\s*').firstMatch(words)![0]!;
            span = TextSpan(
              style: style,
              children: [
                TextSpan(text: indent, style: const TextStyle(decoration: TextDecoration.none)),
                TextSpan(text: words.substring(indent.length)),
              ],
            );
          }
          if (kind == .changed && other != null && tone != null) {
            final s = before ? changedSpan(words, other) : changedSpan(other, words);
            final end = before ? s.aEnd : s.bEnd;
            if (end > s.start && (s.start > 0 || end < words.length)) {
              span = TextSpan(
                style: style,
                children: [
                  TextSpan(text: words.substring(0, s.start)),
                  TextSpan(
                    text: words.substring(s.start, end),
                    style: TextStyle(
                      backgroundColor: tone.strong,
                      fontWeight: ink.none ? .w700 : null,
                    ),
                  ),
                  TextSpan(text: words.substring(end)),
                ],
              );
            }
          }
          return Container(
            color: text == null ? c.muted.withValues(alpha: .25) : tone?.soft,
            padding: const .symmetric(horizontal: 8),
            child: Text.rich(span),
          );
        }

        final shown = count > maxRows ? maxRows : count;
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: .circular(t.radiusMd),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              for (var i = 0; i < shown; i++)
                if (rows != null)
                  rows[i].kind == .hunk
                      ? _Hunk(text: rows[i].oldText!, style: base, color: c.mutedForeground)
                      : IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: .stretch,
                            children: [
                              number(rows[i].oldNo),
                              Expanded(
                                child: cell(
                                  rows[i].oldText,
                                  rows[i].kind == .added ? .added : rows[i].kind,
                                  before: true,
                                  other: rows[i].newText,
                                ),
                              ),
                              Container(width: 1, color: c.border),
                              number(rows[i].newNo),
                              Expanded(
                                child: cell(
                                  rows[i].newText,
                                  rows[i].kind == .removed ? .removed : rows[i].kind,
                                  before: false,
                                  other: rows[i].oldText,
                                ),
                              ),
                            ],
                          ),
                        )
                else
                  uni![i].kind == .hunk
                      ? _Hunk(text: uni[i].text, style: base, color: c.mutedForeground)
                      : Row(
                          crossAxisAlignment: .start,
                          children: [
                            number(uni[i].oldNo),
                            number(uni[i].newNo),
                            Expanded(
                              child: cell(
                                uni[i].text,
                                uni[i].kind,
                                before: uni[i].kind == .removed,
                              ),
                            ),
                          ],
                        ),
              if (count > maxRows)
                Padding(
                  padding: const .all(8),
                  child: Text(
                    '... ${count - maxRows} more lines',
                    style: base.copyWith(color: c.mutedForeground),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static AppSettings _settings(BuildContext context) {
    try {
      return context.watch<SettingsRepository>().settings;
    } on ProviderNotFoundException {
      return const AppSettings();
    }
  }
}

/// Where a part of the file starts.
class _Hunk extends StatelessWidget {
  const _Hunk({required this.text, required this.style, required this.color});
  final String text;
  final TextStyle style;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    color: AshlarTheme.of(context).colors.muted.withValues(alpha: .4),
    padding: const .symmetric(horizontal: 8, vertical: 2),
    child: Text(
      text,
      maxLines: 1,
      overflow: .ellipsis,
      style: style.copyWith(color: color),
    ),
  );
}

typedef _Tone = ({Color soft, Color strong});

/// The colors added and removed lines are shown in.
class _Ink {
  const _Ink(this.added, this.removed, {this.none = false});
  final _Tone added, removed;

  /// No color: shades of the text, removed struck through.
  final bool none;

  static _Ink of(BuildContext context, DiffColors choice) {
    final c = AshlarTheme.of(context).colors;
    final dark = c.background.computeLuminance() < .3;
    _Tone tone(Color base) => (
      soft: base.withValues(alpha: dark ? .14 : .12),
      strong: base.withValues(alpha: dark ? .38 : .30),
    );
    return switch (choice) {
      .greenRed => _Ink(tone(const Color(0xFF3FB950)), tone(const Color(0xFFF85149))),
      // Blue and orange read apart for the commonest kinds of color blindness.
      .blueOrange => _Ink(tone(const Color(0xFF388BFD)), tone(const Color(0xFFDB6D28))),
      .none => _Ink(
        (soft: c.foreground.withValues(alpha: .07), strong: c.foreground.withValues(alpha: .18)),
        (soft: c.foreground.withValues(alpha: .03), strong: c.foreground.withValues(alpha: .12)),
        none: true,
      ),
    };
  }
}
