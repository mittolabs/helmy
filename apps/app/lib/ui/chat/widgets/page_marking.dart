import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/page_marks.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/input.dart';
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
/// region or draw, with a note on each mark. The marks go to the message as a
/// picture of the page showing them, numbered, and a file that says what each
/// is: the user's note, then the element's selector, source file, styles and
/// HTML.
class PageMarking extends ChangeNotifier {
  PageMarking(this._page);
  final PageAccess _page;

  /// 'pick', 'region' or 'draw' while marking; null when not.
  String? mode;
  final marks = <PageMark>[];
  final notes = <int, TextEditingController>{};

  static String? _script;

  Future<void> _ensure() async {
    _script ??= await rootBundle.loadString('assets/helmy/annotate.js');
    await _page.run(_script!);
  }

  Future<void> use(String? to) async {
    mode = to;
    notifyListeners();
    if (to != null) await _ensure();
    await _page.run('window.__helmyAnnotate && window.__helmyAnnotate.setMode(${jsonEncode(to)})');
  }

  /// What the page sent: a mark made, or Escape pressed.
  void fromPage(String message) {
    final Object? json;
    try {
      json = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (json is! Map) return;
    switch (json['type']) {
      case 'mark':
        final mark = PageMark.fromJson(json['mark'] as Map);
        marks.add(mark);
        notes[mark.n] = TextEditingController();
        notifyListeners();
      case 'stop':
        unawaited(use(null));
    }
  }

  Future<void> remove(int n) async {
    marks.removeWhere((m) => m.n == n);
    notes.remove(n)?.dispose();
    notifyListeners();
    await _page.run('window.__helmyAnnotate && window.__helmyAnnotate.remove($n)');
  }

  Future<void> undo() async {
    if (marks.isNotEmpty) await remove(marks.last.n);
  }

  /// The page moved on: its marks went with it.
  void pageMoved() {
    if (marks.isEmpty && mode == null) return;
    for (final c in notes.values) {
      c.dispose();
    }
    marks.clear();
    notes.clear();
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
    for (final m in marks) {
      m.note = notes[m.n]?.text ?? '';
    }
    final dir = Directory('${Directory.systemTemp.path}/helmy-pasted')..createSync(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    // The hover outline off, so only the marks show.
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

  @override
  void dispose() {
    for (final c in notes.values) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Under the page's toolbar while marking: the ways to mark, and the marks
/// made, each with a note.
class MarkingBar extends StatelessWidget {
  const MarkingBar({super.key, required this.marking, required this.onAdd});
  final PageMarking marking;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: marking,
    builder: (context, _) {
      final t = AshlarTheme.of(context);
      final c = t.colors;
      final muted = t.text.xs.copyWith(color: c.mutedForeground);
      Widget way(String mode, IconData icon, String label, String tip) => Tooltip(
        message: tip,
        child: Button(
          variant: marking.mode == mode ? .secondary : .ghost,
          size: .xs,
          semanticLabel: label,
          onPressed: () => unawaited(marking.use(marking.mode == mode ? null : mode)),
          leading: AshlarIcon(icon, size: 14),
          child: Text(label),
        ),
      );
      return Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border)),
        ),
        padding: const .fromLTRB(8, 6, 8, 6),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 6,
          children: [
            Row(
              spacing: 2,
              children: [
                way(
                  'pick',
                  AshlarIconsRoundedStroke.mousePointerClick,
                  'Element',
                  'Point at an element and click, or Tab to it and press Enter',
                ),
                way(
                  'region',
                  AshlarIconsRoundedStroke.squareDashed,
                  'Region',
                  'Drag over a region',
                ),
                way('draw', AshlarIconsRoundedStroke.pencil, 'Draw', 'Draw on the page'),
                const Spacer(),
                Tooltip(
                  message: 'Undo the last mark',
                  child: Button(
                    variant: .ghost,
                    size: .iconXs,
                    semanticLabel: 'Undo the last mark',
                    onPressed: marking.marks.isEmpty ? null : () => unawaited(marking.undo()),
                    child: const AshlarIcon(AshlarIconsRoundedStroke.rotateCcw, size: 14),
                  ),
                ),
                Button(
                  size: .xs,
                  onPressed: marking.marks.isEmpty ? null : onAdd,
                  leading: const AshlarIcon(AshlarIconsRoundedStroke.messageSquarePlus, size: 14),
                  child: const Text('Add to message'),
                ),
              ],
            ),
            if (marking.marks.isEmpty)
              Text(
                marking.mode == null
                    ? 'Choose how to mark the page.'
                    : 'Mark what you mean; each mark takes a note here.',
                style: muted,
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 168),
                child: SingleChildScrollView(
                  child: Column(
                    spacing: 4,
                    children: [
                      for (final m in marking.marks)
                        Row(
                          spacing: 6,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2563EB),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${m.n}',
                                style: t.text.xs.copyWith(
                                  color: const Color(0xFFFFFFFF),
                                  fontWeight: .w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Input(
                                controller: marking.notes[m.n],
                                size: .sm,
                                placeholder: 'A note on ${m.summary}',
                                semanticLabel: 'Note on mark ${m.n}, ${m.summary}',
                              ),
                            ),
                            Tooltip(
                              message: 'Remove mark ${m.n}',
                              child: Button(
                                variant: .ghost,
                                size: .iconXs,
                                semanticLabel: 'Remove mark ${m.n}',
                                onPressed: () => unawaited(marking.remove(m.n)),
                                child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 14),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
