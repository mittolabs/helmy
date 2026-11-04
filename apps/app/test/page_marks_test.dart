import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/page_marks.dart';

void main() {
  test('what the page says of a mark is read whole', () {
    final m = PageMark.fromJson({
      'n': 1,
      'kind': 'element',
      'summary': 'button "Sign in"',
      'element': {
        'tag': 'button',
        'selector': '#login > button',
        'text': 'Sign in',
        'html': '<button>Sign in</button>',
        'styles': {'font-size': '14px'},
        'source': {'component': 'Header', 'file': 'src/Header.tsx', 'line': 42},
      },
    });
    expect(m.kind, MarkKind.element);
    expect(m.element?.source, 'src/Header.tsx:42 (Header)');
    expect(PageMark.fromJson({'kind': 'nonsense'}).kind, MarkKind.element);
  });

  test('the agent reads each mark by its number, the note first', () {
    final marks = [
      PageMark(
        n: 1,
        kind: MarkKind.element,
        summary: 'button "Sign in"',
        element: const MarkedElement(
          tag: 'button',
          selector: '#login > button',
          text: 'Sign in',
          html: '<button>Sign in</button>',
          styles: {'font-size': '14px'},
          file: 'src/Header.tsx',
          line: 42,
        ),
        note: 'make it bigger',
      ),
      PageMark(
        n: 2,
        kind: MarkKind.region,
        summary: 'region, 1 element inside',
        elements: const [MarkedElement(tag: 'img', label: 'logo')],
      ),
    ];
    final md = marksMarkdown(
      url: 'http://localhost:3000/',
      title: 'Shop',
      marks: marks,
      picture: 'page-marks-1.png',
    );
    expect(md, contains('# Marks on Shop (http://localhost:3000/)'));
    expect(md, contains('The picture (page-marks-1.png)'));
    expect(md, contains('## 1. An element: button "Sign in"'));
    expect(md, contains('Note: make it bigger'));
    expect(md, contains('Selector: `#login > button`'));
    expect(md, contains('Source: src/Header.tsx:42'));
    expect(md, contains('font-size: 14px'));
    expect(md, contains('## 2. A region'));
    expect(md, contains('No note.'));
    expect(md, contains('Inside it:'));
    expect(md, contains('`img` logo'));
    expect(md, isNot(contains('—')));
  });
}
