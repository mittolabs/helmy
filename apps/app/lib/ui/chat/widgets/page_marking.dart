import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/page_marks.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';

/// What marking does with the page in the Preview panel, whichever engine
/// draws it: run a script in it, and take a picture of it.
typedef PageAccess = ({
  Future<void> Function(String script) run,
  Future<String?> Function(String path) picture,
  Future<String> Function() title,
  String Function() url,
});

/// Marking up the page for the agent: point at an element, drag over a
/// region or draw. Each mark is numbered on the page, and its note is typed
/// there beside it. The marks go to the message as a picture of the page
/// showing them, and a file that says what each is: the note, then the
/// element's selector, source file, styles and HTML.
class PageMarking extends ChangeNotifier {
  PageMarking(this._page);
  final PageAccess _page;

  /// 'pick', 'region' or 'draw' while marking; null when not.
  String? mode;
  final marks = <PageMark>[];

  static String? _script;

  /// Helmy's colors, corners and font, for the marks and notes on the page.
  Map<String, String> theme = const {};

  Future<void> _ensure() async {
    _script ??= await rootBundle.loadString('assets/helmy/annotate.js');
    await _page.run(_script!);
    await _page.run('window.__helmyAnnotate.theme(${jsonEncode(theme)})');
  }

  Future<void> use(String? to) async {
    mode = to;
    notifyListeners();
    if (to != null) await _ensure();
    await _page.run('window.__helmyAnnotate && window.__helmyAnnotate.setMode(${jsonEncode(to)})');
  }

  /// What the page sent: a mark made, a note typed, a mark removed there, or
  /// Escape pressed.
  void fromPage(String message) {
    final Object? json;
    try {
      json = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (json is! Map) return;
    final n = json['n'];
    switch (json['type']) {
      case 'mark':
        marks.add(PageMark.fromJson(json['mark'] as Map));
        notifyListeners();
      case 'note':
        for (final m in marks.where((m) => m.n == n)) {
          m.note = '${json['text'] ?? ''}';
        }
      case 'removed':
        marks.removeWhere((m) => m.n == n);
        notifyListeners();
      case 'stop':
        unawaited(use(null));
    }
  }

  Future<void> undo() async {
    if (marks.isEmpty) return;
    final n = marks.removeLast().n;
    notifyListeners();
    await _page.run('window.__helmyAnnotate && window.__helmyAnnotate.remove($n)');
  }

  /// The page moved on: its marks went with it.
  void pageMoved() {
    if (marks.isEmpty && mode == null) return;
    marks.clear();
    mode = null;
    notifyListeners();
  }

  Future<void> clear() async {
    pageMoved();
    await _page.run(
      'window.__helmyAnnotate && (window.__helmyAnnotate.clear(), window.__helmyAnnotate.setMode(null))',
    );
  }

  /// The picture and the file for the message; null when there are no marks.
  Future<List<String>?> toFiles() async {
    if (marks.isEmpty) return null;
    final dir = Directory('${Directory.systemTemp.path}/helmy-pasted')..createSync(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    // The hover outline off, so only the marks (and notes) show.
    await _page.run('window.__helmyAnnotate && window.__helmyAnnotate.setMode(null)');
    final picture = await _page.picture('${dir.path}/page-marks-$stamp.png');
    final md = File('${dir.path}/page-marks-$stamp.md');
    await md.writeAsString(
      marksMarkdown(
        url: _page.url(),
        title: await _page.title(),
        marks: marks,
        picture: picture?.split(Platform.pathSeparator).last,
      ),
    );
    return [?picture, md.path];
  }
}

/// Helmy's look for the page's marks and notes, as CSS values.
Map<String, String> markTheme(AshlarThemeData t) {
  String css(Color c) =>
      'rgba(${(c.r * 255).round()}, ${(c.g * 255).round()}, ${(c.b * 255).round()}, ${c.a.toStringAsFixed(3)})';
  final c = t.colors;
  return {
    'bg': css(c.popover),
    'fg': css(c.popoverForeground),
    'muted': css(c.mutedForeground),
    'line': css(c.border),
    'radius': '${t.radiusLg}px',
    'font': '-apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif',
  };
}

/// Under the page's toolbar while marking: how to mark, the marks so far,
/// and what to do with them.
class MarkingBar extends StatelessWidget {
  const MarkingBar({super.key, required this.marking, required this.onAdd, required this.onDone});
  final PageMarking marking;
  final VoidCallback onAdd;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: marking,
    builder: (context, _) {
      final t = AshlarTheme.of(context);
      final c = t.colors;
      final count = marking.marks.length;
      // One control, three ways: the chosen one raised, as a segmented control.
      Widget way(String mode, IconData icon, String label, String tip) {
        final on = marking.mode == mode;
        return Tooltip(
          message: tip,
          child: Pressable(
            selected: on,
            semanticLabel: label,
            onPressed: () => unawaited(marking.use(on ? null : mode)),
            builder: (context, state) => Container(
              padding: const .symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: on
                    ? c.background
                    : state.hovered
                    ? c.background.withValues(alpha: .5)
                    : null,
                borderRadius: .circular(t.radiusMd - 2),
                border: Border.all(color: on ? c.border : const Color(0x00000000)),
              ),
              child: Row(
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  AshlarIcon(icon, size: 14, color: on ? c.foreground : c.mutedForeground),
                  Text(
                    label,
                    style: t.text.xs.copyWith(
                      fontWeight: .w500,
                      color: on ? c.foreground : c.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: const .fromLTRB(8, 0, 8, 8),
        child: Row(
          spacing: 8,
          children: [
            Container(
              padding: const .all(2),
              decoration: BoxDecoration(color: c.muted, borderRadius: .circular(t.radiusMd)),
              child: Row(
                mainAxisSize: .min,
                spacing: 2,
                children: [
                  way(
                    'pick',
                    AshlarIconsRoundedStroke.mousePointerClick,
                    'Element',
                    'Click an element, or Tab to it and press Enter',
                  ),
                  way(
                    'region',
                    AshlarIconsRoundedStroke.squareDashed,
                    'Region',
                    'Drag over a region',
                  ),
                  way('draw', AshlarIconsRoundedStroke.pencil, 'Draw', 'Draw on the page'),
                ],
              ),
            ),
            Expanded(
              child: Text(
                count == 0
                    ? 'Mark what you mean; a note opens beside each mark.'
                    : '$count mark${count == 1 ? '' : 's'}',
                maxLines: 1,
                overflow: .ellipsis,
                style: t.text.xs.copyWith(color: c.mutedForeground),
              ),
            ),
            if (count > 0)
              Tooltip(
                message: 'Undo the last mark',
                child: Button(
                  variant: .ghost,
                  size: .iconXs,
                  semanticLabel: 'Undo the last mark',
                  onPressed: () => unawaited(marking.undo()),
                  child: const AshlarIcon(AshlarIconsRoundedStroke.rotateCcw, size: 14),
                ),
              ),
            Button(
              size: .xs,
              onPressed: count == 0 ? null : onAdd,
              leading: const AshlarIcon(AshlarIconsRoundedStroke.messageSquarePlus, size: 14),
              child: const Text('Add to message'),
            ),
            Button(variant: .ghost, size: .xs, onPressed: onDone, child: const Text('Done')),
          ],
        ),
      );
    },
  );
}
