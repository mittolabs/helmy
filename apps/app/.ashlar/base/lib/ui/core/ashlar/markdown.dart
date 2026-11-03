// Ashlar UI: Markdown. Copied into your app by `ashlar add markdown`; it is yours to change.
//
// Formatted text as models and people write it: headings, paragraphs, bold, italic and
// struck words, links, lists (nested, and with boxes to tick), quotes, tables, rules,
// pictures, and code, inline and in blocks with their language and a copy button. Read
// here, with no package. It draws text that is still arriving as well as text that is
// whole: a code block or a ** not yet closed is drawn as if it were, so nothing jumps when
// the rest comes, and [Markdown.streaming] shows a caret at the end.

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pressable.dart';
import 'theme.dart';

/// How large markdown is drawn.
enum MarkdownSize {
  /// For messages: body text small, headings a step or two above it.
  chat,

  /// For a page: body text at its normal size, headings as a document has them.
  document,
}

/// Markdown, drawn.
///
/// ```dart
/// Markdown(answer, streaming: !done, onLink: (url) => launch(url))
/// ```
class Markdown extends StatelessWidget {
  const Markdown(
    this.data, {
    super.key,
    this.streaming = false,
    this.size = MarkdownSize.chat,
    this.onLink,
    this.codeBuilder,
  });

  /// The text, in markdown.
  final String data;

  /// Still arriving: a caret blinks at its end.
  final bool streaming;
  final MarkdownSize size;

  /// Called with a link's address when it is tapped; links are drawn as text without it.
  final ValueChanged<String>? onLink;

  /// Draws a code block your way (to colour its words, say); null draws it plainly.
  final Widget Function(BuildContext context, String code, String? language)?
  codeBuilder;

  @override
  Widget build(BuildContext context) {
    final blocks = parseMarkdown(data);
    final out = <Widget>[];
    for (final (i, b) in blocks.indexed) {
      if (i > 0) out.add(SizedBox(height: _gap(b)));
      out.add(
        _BlockView(
          block: b,
          md: this,
          caret: streaming && i == blocks.length - 1,
        ),
      );
    }
    if (streaming && blocks.isEmpty) out.add(const _Caret());
    return Semantics(
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: out,
      ),
    );
  }

  double _gap(MdBlock b) => switch (b) {
    MdHeading() => size == MarkdownSize.chat ? 16 : 28,
    _ => size == MarkdownSize.chat ? 10 : 16,
  };
}

// ---------------------------------------------------------------------------------------
// Reading markdown
// ---------------------------------------------------------------------------------------

/// A block of markdown: what [parseMarkdown] reads text into.
sealed class MdBlock {
  const MdBlock();
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.text);
  final String text;
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.text);
  final int level;
  final String text;
}

class MdCode extends MdBlock {
  const MdCode(this.code, this.language, {this.open = false});
  final String code;
  final String? language;

  /// Not yet closed: more is coming.
  final bool open;
}

class MdQuote extends MdBlock {
  const MdQuote(this.children);
  final List<MdBlock> children;
}

class MdList extends MdBlock {
  const MdList(this.items, {this.ordered = false, this.start = 1});
  final List<MdItem> items;
  final bool ordered;
  final int start;
}

/// One point of a list: its blocks, and whether its box is ticked, when it has one.
class MdItem {
  const MdItem(this.children, {this.checked});
  final List<MdBlock> children;
  final bool? checked;
}

class MdTable extends MdBlock {
  const MdTable(this.head, this.rows, this.align);
  final List<String> head;
  final List<List<String>> rows;

  /// Each column's alignment: -1 start, 0 centre, 1 end.
  final List<int> align;
}

class MdRule extends MdBlock {
  const MdRule();
}

class MdImage extends MdBlock {
  const MdImage(this.url, this.alt);
  final String url, alt;
}

final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})\s*([\w+#.-]*)');
final _heading = RegExp(r'^ {0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
final _rule = RegExp(r'^ {0,3}([-*_])(\s*\1){2,}\s*$');
final _bullet = RegExp(r'^( *)([-*+])\s+(.*)$');
final _numbered = RegExp(r'^( *)(\d{1,9})[.)]\s+(.*)$');
final _image = RegExp(r'^\s*!\[([^\]]*)\]\(([^)\s]+)[^)]*\)\s*$');
final _tableSep = RegExp(r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$');

/// Reads [text] into blocks. What is not closed at the end is taken as closed there.
List<MdBlock> parseMarkdown(String text) =>
    _blocks(text.replaceAll('\r\n', '\n').split('\n'));

List<MdBlock> _blocks(List<String> lines) {
  final out = <MdBlock>[];
  var i = 0;
  bool blank(String l) => l.trim().isEmpty;
  bool starts(String l) =>
      _fence.hasMatch(l) ||
      _heading.hasMatch(l) ||
      _rule.hasMatch(l) ||
      l.trimLeft().startsWith('>') ||
      _bullet.hasMatch(l) ||
      _numbered.hasMatch(l);
  while (i < lines.length) {
    final l = lines[i];
    if (blank(l)) {
      i++;
      continue;
    }
    if (_fence.firstMatch(l) case final m?) {
      final mark = m[1]!;
      final lang = m[2]!.isEmpty ? null : m[2];
      final code = <String>[];
      i++;
      var closed = false;
      while (i < lines.length) {
        if (lines[i].trimLeft().startsWith(mark[0] * mark.length) &&
            lines[i].trim().replaceAll(mark[0], '').isEmpty) {
          closed = true;
          i++;
          break;
        }
        code.add(lines[i]);
        i++;
      }
      out.add(MdCode(code.join('\n'), lang, open: !closed));
      continue;
    }
    if (_heading.firstMatch(l) case final m?) {
      out.add(MdHeading(m[1]!.length, m[2]!));
      i++;
      continue;
    }
    if (_rule.hasMatch(l)) {
      out.add(const MdRule());
      i++;
      continue;
    }
    if (_image.firstMatch(l) case final m?) {
      out.add(MdImage(m[2]!, m[1]!));
      i++;
      continue;
    }
    if (l.trimLeft().startsWith('>')) {
      final inner = <String>[];
      while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
        inner.add(
          lines[i].trimLeft().substring(1).replaceFirst(RegExp('^ '), ''),
        );
        i++;
      }
      out.add(MdQuote(_blocks(inner)));
      continue;
    }
    if (_bullet.hasMatch(l) || _numbered.hasMatch(l)) {
      final ordered = !_bullet.hasMatch(l);
      final first = (ordered ? _numbered : _bullet).firstMatch(l)!;
      final indent = first[1]!.length;
      final items = <List<String>>[];
      while (i < lines.length) {
        final line = lines[i];
        final m = (ordered ? _numbered : _bullet).firstMatch(line);
        if (m != null && m[1]!.length == indent) {
          items.add([m[3]!]);
          i++;
          continue;
        }
        // A line indented under the item, or a blank line inside the list, belongs to it.
        if (blank(line)) {
          final next = i + 1 < lines.length ? lines[i + 1] : '';
          if (next.startsWith(' ' * (indent + 2)) ||
              ((ordered ? _numbered : _bullet).firstMatch(next)?[1]?.length ==
                  indent)) {
            items.last.add('');
            i++;
            continue;
          }
          break;
        }
        if (line.startsWith(' ' * (indent + 1)) ||
            (!starts(line) && items.isNotEmpty)) {
          items.last.add(
            line.length > indent + 2 && line.startsWith(' ' * (indent + 2))
                ? line.substring(indent + 2)
                : line.trimLeft(),
          );
          i++;
          continue;
        }
        break;
      }
      out.add(
        MdList(
          [
            for (final it in items)
              () {
                var head = it.first;
                bool? checked;
                final box = RegExp(r'^\[( |x|X)\]\s+').firstMatch(head);
                if (box != null) {
                  checked = box[1] != ' ';
                  head = head.substring(box.end);
                }
                return MdItem(_blocks([head, ...it.skip(1)]), checked: checked);
              }(),
          ],
          ordered: ordered,
          start: ordered ? int.parse(first[2]!) : 1,
        ),
      );
      continue;
    }
    if (l.contains('|') &&
        i + 1 < lines.length &&
        _tableSep.hasMatch(lines[i + 1])) {
      List<String> cells(String row) {
        var r = row.trim();
        if (r.startsWith('|')) r = r.substring(1);
        if (r.endsWith('|') && !r.endsWith(r'\|')) {
          r = r.substring(0, r.length - 1);
        }
        return [
          for (final c in r.split(RegExp(r'(?<!\\)\|')))
            c.trim().replaceAll(r'\|', '|'),
        ];
      }

      final head = cells(l);
      final align = [
        for (final c in cells(lines[i + 1]))
          c.startsWith(':') && c.endsWith(':')
              ? 0
              : c.endsWith(':')
              ? 1
              : -1,
      ];
      i += 2;
      final rows = <List<String>>[];
      while (i < lines.length && !blank(lines[i]) && lines[i].contains('|')) {
        rows.add(cells(lines[i]));
        i++;
      }
      out.add(MdTable(head, rows, align));
      continue;
    }
    // A paragraph: lines until a blank or the start of something else.
    final para = <String>[l];
    i++;
    while (i < lines.length && !blank(lines[i]) && !starts(lines[i])) {
      para.add(lines[i]);
      i++;
    }
    out.add(MdParagraph(para.join('\n')));
  }
  return out;
}

/// A run of inline text with its marks.
class MdSpan {
  const MdSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.link,
  });

  final String text;
  final bool bold, italic, strike, code;
  final String? link;

  MdSpan mark({bool? bold, bool? italic, bool? strike, String? link}) => MdSpan(
    text,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    strike: strike ?? this.strike,
    code: code,
    link: link ?? this.link,
  );
}

const _emphasis = ['**', '__', '~~', '*', '_'];
final _word = RegExp(r'\w');
final _autolink = RegExp(r'^<?(https?://[^\s<>]*[^\s<>.,;:!?)\]])>?');

/// Reads a paragraph's [text] into marked runs. A mark not closed is taken to run to the
/// end, as when the text is still arriving.
List<MdSpan> parseInline(String text) {
  final out = <MdSpan>[];
  final plain = StringBuffer();
  void flush() {
    if (plain.isNotEmpty) {
      out.add(MdSpan(plain.toString()));
      plain.clear();
    }
  }

  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    final rest = text.substring(i);
    // An escaped character is itself.
    if (ch == r'\' &&
        i + 1 < text.length &&
        r'\`*_{}[]()#+-.!|~<>'.contains(text[i + 1])) {
      plain.write(text[i + 1]);
      i += 2;
      continue;
    }
    // Two spaces or a backslash at a line's end: a line break; else a newline is a space.
    if (ch == '\n') {
      final s = plain.toString();
      if (s.endsWith('  ') || s.endsWith(r'\')) {
        plain
          ..clear()
          ..write(s.replaceFirst(RegExp(r'( {2,}|\\)$'), ''))
          ..write('\n');
      } else {
        plain.write(' ');
      }
      i++;
      continue;
    }
    if (ch == '`') {
      final ticks = RegExp('^`+').firstMatch(rest)![0]!;
      final end = text.indexOf(ticks, i + ticks.length);
      flush();
      final inner = end < 0
          ? text.substring(i + ticks.length)
          : text.substring(i + ticks.length, end);
      out.add(MdSpan(inner.trim().isEmpty ? inner : inner.trim(), code: true));
      i = end < 0 ? text.length : end + ticks.length;
      continue;
    }
    if (ch == '[') {
      final m = RegExp(
        r'^\[((?:[^\[\]]|\[[^\]]*\])*)\]\(([^)\s]*)(?:\s+"[^"]*")?\)',
      ).firstMatch(rest);
      if (m != null) {
        flush();
        out.addAll([for (final s in parseInline(m[1]!)) s.mark(link: m[2])]);
        i += m[0]!.length;
        continue;
      }
    }
    if (ch == '!' && rest.startsWith('![')) {
      final m = RegExp(r'^!\[([^\]]*)\]\(([^)\s]*)[^)]*\)').firstMatch(rest);
      if (m != null) {
        flush();
        out.add(MdSpan(m[1]!.isEmpty ? m[2]! : m[1]!, link: m[2]));
        i += m[0]!.length;
        continue;
      }
    }
    if ((ch == 'h' || ch == '<') && (i == 0 || !_word.hasMatch(text[i - 1]))) {
      final m = _autolink.firstMatch(rest);
      if (m != null) {
        flush();
        out.add(MdSpan(m[1]!, link: m[1]));
        i += m[0]!.length;
        continue;
      }
    }
    // Emphasis: ** and __ bold, * and _ italic, ~~ struck. _ inside a word is a letter.
    final mark = _emphasis.firstWhere(rest.startsWith, orElse: () => '');
    final after = i + mark.length;
    if (mark.isNotEmpty &&
        after < text.length &&
        text[after] != ' ' &&
        !(mark[0] == '_' && i > 0 && _word.hasMatch(text[i - 1]))) {
      var end = text.indexOf(mark, after);
      // A single * must not close on the first of a **.
      while (end > 0 &&
          mark.length == 1 &&
          end + 1 < text.length &&
          text[end + 1] == mark) {
        end = text.indexOf(mark, end + 2);
      }
      flush();
      final inner = end < 0
          ? text.substring(after)
          : text.substring(after, end);
      out.addAll([
        for (final s in parseInline(inner))
          s.mark(
            bold: mark.length == 2 && mark != '~~' ? true : null,
            italic: mark.length == 1 ? true : null,
            strike: mark == '~~' ? true : null,
          ),
      ]);
      i = end < 0 ? text.length : end + mark.length;
      continue;
    }
    plain.write(ch);
    i++;
  }
  flush();
  return out;
}

// ---------------------------------------------------------------------------------------
// Drawing it
// ---------------------------------------------------------------------------------------

class _Styles {
  _Styles(BuildContext context, MarkdownSize size)
    : t = AshlarTheme.of(context),
      chat = size == MarkdownSize.chat,
      quoted = context.dependOnInheritedWidgetOfExactType<_Quoted>() != null;

  final AshlarThemeData t;
  final bool chat;

  /// Inside a quote: drawn quieter.
  final bool quoted;

  TextStyle get body => (chat ? t.text.sm : t.text.base).copyWith(
    color: quoted ? t.colors.mutedForeground : t.colors.foreground,
    height: chat ? 22 / 14 : 28 / 16,
  );

  TextStyle heading(int level) {
    final sizes = chat
        ? <double>[20, 18, 16, 15, 14, 14]
        : <double>[30, 24, 20, 18, 16, 16];
    return body.copyWith(
      fontSize: sizes[level - 1],
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: level <= 2 ? -.4 : -.2,
    );
  }

  TextStyle get mono => body.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Consolas', 'Roboto Mono', 'monospace'],
    fontSize: (body.fontSize ?? 14) * .92,
  );
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block, required this.md, this.caret = false});

  final MdBlock block;
  final Markdown md;
  final bool caret;

  @override
  Widget build(BuildContext context) {
    final s = _Styles(context, md.size);
    final c = s.t.colors;
    switch (block) {
      case MdParagraph(:final text):
        return _Inline(text: text, style: s.body, md: md, caret: caret);
      case MdHeading(:final level, :final text):
        return Semantics(
          container: true,
          header: true,
          child: _Inline(
            text: text,
            style: s.heading(level),
            md: md,
            caret: caret,
          ),
        );
      case MdCode(:final code, :final language):
        final drawn =
            md.codeBuilder?.call(context, code, language) ??
            _CodeBlock(code: code, language: language, style: s.mono);
        return caret
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [drawn, const SizedBox(height: 6), const _Caret()],
              )
            : drawn;
      case MdQuote(:final children):
        return Container(
          padding: const EdgeInsetsDirectional.only(start: 14),
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: c.border, width: 3),
            ),
          ),
          child: _Quoted(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, b) in children.indexed) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _BlockView(
                    block: b,
                    md: md,
                    caret: caret && i == children.length - 1,
                  ),
                ],
              ],
            ),
          ),
        );
      case MdList(:final items, :final ordered, :final start):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, item) in items.indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: item.checked != null ? 24 : (ordered ? 26 : 18),
                      child: item.checked != null
                          ? Padding(
                              padding: EdgeInsets.only(
                                top:
                                    (s.body.fontSize! * s.body.height! - 14) /
                                    2,
                              ),
                              child: Align(
                                alignment: AlignmentDirectional.topStart,
                                child: _Tick(checked: item.checked!),
                              ),
                            )
                          : Text(
                              ordered ? '${start + i}.' : '•',
                              style: s.body.copyWith(color: c.mutedForeground),
                            ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (k, b) in item.children.indexed) ...[
                            if (k > 0) const SizedBox(height: 6),
                            _BlockView(
                              block: b,
                              md: md,
                              caret:
                                  caret &&
                                  i == items.length - 1 &&
                                  k == item.children.length - 1,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case MdTable(:final head, :final rows, :final align):
        TextAlign alignOf(int k) => switch (k < align.length ? align[k] : -1) {
          0 => TextAlign.center,
          1 => TextAlign.end,
          _ => TextAlign.start,
        };
        Widget cell(String text, int k, {bool header = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _Inline(
            text: text,
            style: header
                ? s.body.copyWith(fontWeight: FontWeight.w600)
                : s.body,
            md: md,
            align: alignOf(k),
          ),
        );
        final width = [
          head.length,
          ...rows.map((r) => r.length),
        ].reduce((a, b) => a > b ? a : b);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(s.t.radiusMd),
            ),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder(
                horizontalInside: BorderSide(color: c.border),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: c.muted),
                  children: [
                    for (var k = 0; k < width; k++)
                      cell(k < head.length ? head[k] : '', k, header: true),
                  ],
                ),
                for (final r in rows)
                  TableRow(
                    children: [
                      for (var k = 0; k < width; k++)
                        cell(k < r.length ? r[k] : '', k),
                    ],
                  ),
              ],
            ),
          ),
        );
      case MdRule():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(height: 1, color: c.border),
        );
      case MdImage(:final url, :final alt):
        return Semantics(
          image: true,
          label: alt,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(s.t.radiusMd),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                alignment: AlignmentDirectional.centerStart,
                errorBuilder: (context, _, _) =>
                    Text(alt, style: s.body.copyWith(color: c.mutedForeground)),
              ),
            ),
          ),
        );
    }
  }
}

/// A paragraph's runs as one piece of text, links tappable, the caret at its end.
class _Inline extends StatefulWidget {
  const _Inline({
    required this.text,
    required this.style,
    required this.md,
    this.caret = false,
    this.align = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final Markdown md;
  final bool caret;
  final TextAlign align;

  @override
  State<_Inline> createState() => _InlineState();
}

class _InlineState extends State<_Inline> {
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _taps) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _taps) {
      r.dispose();
    }
    _taps.clear();
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final s = _Styles(context, widget.md.size);
    final spans = <InlineSpan>[
      for (final run in parseInline(widget.text))
        if (run.code)
          TextSpan(
            text: ' ${run.text} ',
            style: s.mono.copyWith(
              fontSize: (widget.style.fontSize ?? 14) * .9,
              backgroundColor: c.muted,
              fontWeight: FontWeight.w500,
            ),
          )
        else
          TextSpan(
            text: run.text,
            style: TextStyle(
              fontWeight: run.bold ? FontWeight.w600 : null,
              fontStyle: run.italic ? FontStyle.italic : null,
              decoration: TextDecoration.combine([
                if (run.strike) TextDecoration.lineThrough,
                if (run.link != null) TextDecoration.underline,
              ]),
              decorationColor: run.link != null
                  ? c.primary.withValues(alpha: .5)
                  : null,
              color: run.link != null ? c.primary : null,
            ),
            recognizer: run.link != null && widget.md.onLink != null
                ? (TapGestureRecognizer()
                        ..onTap = () => widget.md.onLink!(run.link!))
                      .also(_taps.add)
                : null,
            mouseCursor: run.link != null && widget.md.onLink != null
                ? SystemMouseCursors.click
                : null,
          ),
      if (widget.caret)
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _Caret(),
        ),
    ];
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      textAlign: widget.align,
    );
  }
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}

/// A box a task list ticks.
class _Tick extends StatelessWidget {
  const _Tick({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    return Semantics(
      checked: checked,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: checked ? c.primary : c.background,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: checked ? c.primary : c.input),
        ),
        child: checked
            ? AshlarIcon(
                AshlarIconsRoundedStroke.check,
                size: 11,
                color: c.primaryForeground,
              )
            : null,
      ),
    );
  }
}

/// A block of code: its language and a copy button above, the code scrolling along.
class _CodeBlock extends StatefulWidget {
  const _CodeBlock({
    required this.code,
    required this.language,
    required this.style,
  });

  final String code;
  final String? language;
  final TextStyle style;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.language ?? '',
                    style: t.text.xs.copyWith(color: c.mutedForeground),
                  ),
                ),
                Pressable(
                  onPressed: _copy,
                  semanticLabel: _copied ? 'Copied' : 'Copy the code',
                  builder: (context, state) => AnimatedContainer(
                    duration: t.duration,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: state.hovered
                          ? c.accent
                          : c.accent.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(t.radiusSm),
                      border: Border.all(
                        color: state.focused
                            ? c.ring
                            : c.ring.withValues(alpha: 0),
                      ),
                    ),
                    child: AshlarIcon(
                      _copied
                          ? AshlarIconsRoundedStroke.check
                          : AshlarIconsRoundedStroke.copy,
                      size: 14,
                      color: c.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Text(
              widget.code,
              style: widget.style.copyWith(height: 1.55),
              textDirection: TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
  }
}

/// The caret at the end of text still arriving.
class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _blink.value = 1;
    } else if (!_blink.isAnimating) {
      _blink.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: _blink,
        child: Container(
          width: 7,
          height: 14,
          margin: const EdgeInsetsDirectional.only(start: 2),
          decoration: BoxDecoration(
            color: c.foreground,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}

/// Marks what is inside a quote, which is drawn quieter.
class _Quoted extends InheritedWidget {
  const _Quoted({required super.child});

  @override
  bool updateShouldNotify(_Quoted oldWidget) => false;
}
