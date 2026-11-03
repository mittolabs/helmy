import 'package:flutter/widgets.dart';

import 'ashlar/markdown.dart';
import 'ashlar/theme.dart';

/// A Markdown file's front matter (the `---` block at its top) as fields, and
/// the rest. Nested fields read as "metadata type". No front matter, no fields.
({List<(String, String)> fields, String body}) splitFrontmatter(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') return (fields: const [], body: text);
  final end = lines.indexWhere((l) => l.trim() == '---', 1);
  if (end < 0) return (fields: const [], body: text);
  final fields = <(String, String)>[];
  String? parent;
  for (final line in lines.sublist(1, end)) {
    final m = RegExp(r'^(\s*)([\w.-]+):\s*(.*)$').firstMatch(line);
    if (m == null) continue;
    final nested = m[1]!.isNotEmpty;
    var value = m[3]!.trim();
    if (value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    if (!nested) parent = value.isEmpty ? m[2] : null;
    if (value.isEmpty) continue;
    fields.add((nested && parent != null ? '$parent ${m[2]}' : m[2]!, value));
  }
  return (fields: fields, body: lines.sublist(end + 1).join('\n').trimLeft());
}

/// Markdown as it reads: front matter as quiet fields, then the formatted text.
class MarkdownPreview extends StatelessWidget {
  const new(this.text, {super.key, this.size = MarkdownSize.chat});
  final String text;
  final MarkdownSize size;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final (:fields, :body) = splitFrontmatter(text);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 14,
      children: [
        if (fields.isNotEmpty)
          Container(
            padding: const .symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: t.colors.border),
              borderRadius: .circular(t.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 4,
              children: [
                for (final (key, value) in fields)
                  Row(
                    crossAxisAlignment: .start,
                    spacing: 12,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          key,
                          style: t.text.xs.copyWith(color: t.colors.mutedForeground, height: 1.5),
                        ),
                      ),
                      Expanded(child: Text(value, style: t.text.xs.copyWith(height: 1.5))),
                    ],
                  ),
              ],
            ),
          ),
        if (body.trim().isNotEmpty) Markdown(body, size: size),
      ],
    );
  }
}

/// A step's result as Markdown, when it is the text of a Markdown file the
/// step read; null otherwise. Line numbers a reading tool added are taken off.
String? markdownResult({
  required String name,
  required Map<String, Object?> input,
  required String? result,
  required String command,
}) {
  if (result == null || result.trim().isEmpty) return null;
  final path = '${input['file_path'] ?? ''}';
  final isMd = RegExp(r'\.(md|markdown|mdx)$', caseSensitive: false);
  final readsMd = switch (name) {
    'Read' => isMd.hasMatch(path),
    'Bash' || 'Shell' => RegExp(
      r'^\s*(cat|head|tail|bat|less)\b[^;|&]*\.(md|markdown|mdx)\b[^;|&]*$',
      caseSensitive: false,
    ).hasMatch(command.replaceFirst(RegExp(r'^\s*cd\s+\S+\s*(&&|;)'), '')),
    _ => false,
  };
  if (!readsMd) return null;
  final lines = result.split('\n');
  final numbered = RegExp(r'^\s*\d+(\t|→)');
  final allNumbered = lines.where((l) => l.trim().isNotEmpty).every(numbered.hasMatch);
  return allNumbered ? [for (final l in lines) l.replaceFirst(numbered, '')].join('\n') : result;
}
