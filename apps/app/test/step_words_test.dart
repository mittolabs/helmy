import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/activity_words.dart';
import 'package:helmy/domain/models/permission_rule.dart';

void main() {
  test('real steps from a real chat read as what they did, never "Ran a script"', () {
    // Commands Codex ran tidying a Downloads folder and totaling a spending file
    // (2026-11-11), home folder renamed.
    final commands = (jsonDecode(
      File('test/fixtures/real_commands.json').readAsStringSync(),
    ) as List).cast<String>();
    final labels = [
      for (final c in commands) specificCommandLabel(PermissionRule.plainCommand(c), done: true),
    ];
    expect(labels, [
      'Inspected the folder',
      'Compared files',
      'Checked the tools available',
      'Read the documents',
      'Moved files to the Trash',
      'Moved Screenshot 2026-11-03 at 9.14.22 AM.png to the Trash',
      'Sorted files into folders',
      'Inspected the folder',
      'Read file contents',
      'Wrote a file',
    ]);
  });

  test('code is never taken for a file name', () {
    expect(namedFiles("print(f.name); p.glob('*.pdf'); f.suffix == '.txt'"), isEmpty);
    expect(namedFiles("shutil.move(src / 'lease-draft-v3.txt', old)"), ['lease-draft-v3.txt']);
  });

  test("Codex's own reading of a command comes first", () {
    expect(
      actionsLabel([
        {'type': 'read', 'name': 'notes.md', 'path': '/w/notes.md'},
      ], done: true),
      'Read notes.md',
    );
    expect(
      actionsLabel([
        {'type': 'listFiles', 'path': '/Users/sam/Studio/Downloads'},
        {'type': 'search', 'query': 'invoice'},
      ], done: false),
      'Listing Downloads and searching for "invoice"',
    );
    expect(
      actionsLabel([
        {'type': 'unknown', 'command': 'x'},
      ], done: true),
      isNull,
    );
  });
}
