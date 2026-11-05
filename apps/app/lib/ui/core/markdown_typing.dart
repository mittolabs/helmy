import 'package:flutter/widgets.dart';

/// A text box's text with its Markdown shown as it is typed: **bold**,
/// *italic* and _italic_, `code`, ~~struck~~, and [links](...). The marks
/// stay in the text, quieter, so what is sent is what was typed.
class MarkdownTypingController extends TextEditingController {
  MarkdownTypingController({super.text, this.enabled = true});

  /// Off, it is a plain text box.
  bool enabled;

  /// Colors for the quiet marks and code's background; set where drawn.
  Color marks = const Color(0x80808080);
  Color codeBackground = const Color(0x1A808080);

  static final _spans = RegExp(
    r'(\*\*[^*\n]+\*\*)|(~~[^~\n]+~~)|(`[^`\n]+`)|(\[[^\]\n]+\]\([^)\s]+\))|(\*[^*\s][^*\n]*\*)|(\b_[^_\s][^_\n]*_\b)',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!enabled || !value.composing.isCollapsed && withComposing) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final quiet = TextStyle(color: marks);
    final out = <InlineSpan>[];
    var at = 0;
    for (final m in _spans.allMatches(text)) {
      if (m.start > at) out.add(TextSpan(text: text.substring(at, m.start)));
      final s = m[0]!;
      if (m[1] != null) {
        out.add(_wrapped(s, 2, quiet, const TextStyle(fontWeight: FontWeight.w700)));
      } else if (m[2] != null) {
        out.add(_wrapped(s, 2, quiet, const TextStyle(decoration: TextDecoration.lineThrough)));
      } else if (m[3] != null) {
        out.add(
          _wrapped(
            s,
            1,
            quiet,
            TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
              backgroundColor: codeBackground,
            ),
          ),
        );
      } else if (m[4] != null) {
        final close = s.indexOf('](');
        out.add(
          TextSpan(
            children: [
              TextSpan(text: '[', style: quiet),
              TextSpan(
                text: s.substring(1, close),
                style: const TextStyle(decoration: TextDecoration.underline),
              ),
              TextSpan(text: s.substring(close), style: quiet),
            ],
          ),
        );
      } else {
        out.add(_wrapped(s, 1, quiet, const TextStyle(fontStyle: FontStyle.italic)));
      }
      at = m.end;
    }
    if (at < text.length) out.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: out);
  }

  /// [s] with its [n]-character marks either side quiet and its inside in
  /// [inner].
  static TextSpan _wrapped(String s, int n, TextStyle quiet, TextStyle inner) => TextSpan(
    children: [
      TextSpan(text: s.substring(0, n), style: quiet),
      TextSpan(text: s.substring(n, s.length - n), style: inner),
      TextSpan(text: s.substring(s.length - n), style: quiet),
    ],
  );
}
