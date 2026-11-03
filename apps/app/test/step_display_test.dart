import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/chat/widgets/step_input.dart';
import 'package:helmy/ui/core/markdown_preview.dart';

void main() {
  test('a command is cut into programs, flags, strings and operators', () {
    final parts = shellParts("cd /Users/x; head -20 'My Notes.md' | grep -n todo && ls");
    final kinds = {
      for (final (k, t) in parts)
        if (k != ShellPart.space) t: k,
    };
    expect(kinds['cd'], ShellPart.program);
    expect(kinds['/Users/x'], ShellPart.word);
    expect(kinds[';'], ShellPart.operator);
    expect(kinds['head'], ShellPart.program);
    expect(kinds['-20'], ShellPart.flag);
    expect(kinds["'My Notes.md'"], ShellPart.string);
    expect(kinds['grep'], ShellPart.program);
    expect(kinds['todo'], ShellPart.word);
    expect(kinds['ls'], ShellPart.program);
    // Nothing is lost: the pieces put back together are the command.
    expect(
      parts.map((p) => p.$2).join(),
      "cd /Users/x; head -20 'My Notes.md' | grep -n todo && ls",
    );
  });

  test('front matter becomes fields, nested ones named with their parent', () {
    final (:fields, :body) = splitFrontmatter('''---
name: feedback-human-prose
description: "Writing must not read as AI-generated"
metadata:
  type: feedback
---

All prose must read like a person wrote it.''');
    expect(fields, [
      ('name', 'feedback-human-prose'),
      ('description', 'Writing must not read as AI-generated'),
      ('metadata type', 'feedback'),
    ]);
    expect(body, 'All prose must read like a person wrote it.');
    expect(splitFrontmatter('# Just a title').fields, isEmpty);
  });

  test('only a Markdown file a step read is shown formatted', () {
    String? md(String name, Map<String, Object?> input, String result, [String command = '']) =>
        markdownResult(name: name, input: input, result: result, command: command);
    expect(
      md('Read', {'file_path': '/a/notes.md'}, '     1\t# Title\n     2\t\n     3\tText'),
      '# Title\n\nText',
    );
    expect(md('Read', {'file_path': '/a/main.dart'}, 'void main() {}'), isNull);
    expect(md('Bash', {}, '# Hi', 'cat README.md'), '# Hi');
    expect(md('Bash', {}, '# Hi', 'cd /x && cat README.md'), '# Hi');
    expect(
      md('Bash', {}, '# Hi\nfile.txt', 'cat Hello.md; ls'),
      isNull,
      reason: 'mixed output is not one Markdown file',
    );
  });
}
