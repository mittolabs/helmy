/// Marks made on a page in the Preview panel, and what they tell an agent.
library;

/// What a mark is on.
enum MarkKind { element, region, drawing }

/// An element on the page, as the page described it.
class MarkedElement {
  const MarkedElement({
    required this.tag,
    this.selector,
    this.label,
    this.text = '',
    this.html = '',
    this.styles = const {},
    this.component,
    this.file,
    this.line,
  });

  factory MarkedElement.fromJson(Map json) {
    final source = json['source'] as Map?;
    return MarkedElement(
      tag: '${json['tag'] ?? 'element'}',
      selector: json['selector'] as String?,
      label: json['label'] as String?,
      text: '${json['text'] ?? ''}',
      html: '${json['html'] ?? ''}',
      styles: {
        for (final e in ((json['styles'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
      },
      component: source?['component'] as String?,
      file: source?['file'] as String?,
      line: (source?['line'] as num?)?.toInt(),
    );
  }

  final String tag;
  final String? selector;
  final String? label;
  final String text;
  final String html;
  final Map<String, String> styles;

  /// The component and source file that drew it, when the page keeps them
  /// (a development build).
  final String? component;
  final String? file;
  final int? line;

  /// `src/Header.tsx:42 (Header)`, or null when unknown.
  String? get source {
    if (file == null && component == null) return null;
    final at = file == null ? null : (line == null ? file : '$file:$line');
    return [?at, if (component != null) at == null ? component! : '($component)'].join(' ');
  }
}

/// One mark: what it is on, what the page said of it, and the user's note.
class PageMark {
  PageMark({
    required this.n,
    required this.kind,
    required this.summary,
    this.element,
    this.elements = const [],
    this.note = '',
  });

  factory PageMark.fromJson(Map json) {
    final kind = MarkKind.values.asNameMap()[json['kind']] ?? MarkKind.element;
    return PageMark(
      n: (json['n'] as num?)?.toInt() ?? 0,
      kind: kind,
      summary: '${json['summary'] ?? kind.name}',
      element: json['element'] is Map ? MarkedElement.fromJson(json['element'] as Map) : null,
      elements: [
        for (final e in (json['elements'] as List?) ?? const [])
          if (e is Map) MarkedElement.fromJson(e),
      ],
    );
  }

  final int n;
  final MarkKind kind;
  final String summary;
  final MarkedElement? element;
  final List<MarkedElement> elements;
  String note;
}

/// The marks as an agent reads them: each by its number (as the picture
/// shows it), the user's note first, then what it is on.
String marksMarkdown({
  required String url,
  required String title,
  required List<PageMark> marks,
  String? picture,
}) {
  final out = StringBuffer()
    ..writeln('# Marks on ${title.isEmpty ? url : '$title ($url)'}')
    ..writeln()
    ..writeln(
      picture == null
          ? 'Each mark is numbered as below.'
          : 'The picture ($picture) shows the page with each mark numbered as below.',
    )
    ..writeln();
  void element(MarkedElement e, String indent) {
    final said = [?e.label, if (e.text.isNotEmpty) '"${e.text}"'].join(', ');
    out.writeln('$indent- `${e.tag}`${said.isEmpty ? '' : ' $said'}');
    if (e.selector != null) out.writeln('$indent  - Selector: `${e.selector}`');
    if (e.source != null) out.writeln('$indent  - Source: ${e.source}');
    if (e.styles.isNotEmpty) {
      out.writeln(
        '$indent  - Styles: ${[for (final s in e.styles.entries) '${s.key}: ${s.value}'].join('; ')}',
      );
    }
    if (e.html.isNotEmpty) {
      out
        ..writeln('$indent  - HTML:')
        ..writeln('$indent    ```html')
        ..writeln([for (final l in e.html.split('\n')) '$indent    $l'].join('\n'))
        ..writeln('$indent    ```');
    }
  }

  for (final m in marks) {
    final kind = switch (m.kind) {
      MarkKind.element => 'An element',
      MarkKind.region => 'A region',
      MarkKind.drawing => 'A drawing',
    };
    out.writeln('## ${m.n}. $kind: ${m.summary}');
    out.writeln();
    out.writeln(m.note.trim().isEmpty ? 'No note.' : 'Note: ${m.note.trim()}');
    out.writeln();
    if (m.element case final e?) element(e, '');
    if (m.elements.isNotEmpty) {
      out.writeln(m.kind == MarkKind.drawing ? 'Under the drawing:' : 'Inside it:');
      for (final e in m.elements) {
        element(e, '');
      }
    }
    out.writeln();
  }
  return out.toString().trimRight();
}
