import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/activity_words.dart';
import 'package:helmy/domain/helmy_voice.dart';
import 'package:helmy/domain/models/chat_item.dart';
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
      // Codex looking for AGENTS.md, committing and removing, from a tutorial take.
      'Looked for AGENTS.md and notes.md',
      'Reviewed the changes',
      'Looked for AGENTS.md',
      'Committed the changes',
      'Removed menu-draft-spring.md and menu-draft-summer.md',
      // Codex designing a landing page, from the Design tutorial take.
      'Looked for notes.md and AGENTS.md',
      'Inspected notes',
      'Created a folder',
      'Edited index.html',
      'Wrote a file',
      'Wrote a file',
      'Edited a file',
      'Removed review.html',
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

  test("a command Codex wraps in its shell is read as the shell reads it", () {
    expect(
      PermissionRule.plainCommand(
        "/bin/zsh -lc \"for p in a; do if [ -f \\\"\"'\$p\" ]; then cat \"\$p\"; fi; done'",
      ),
      'for p in a; do if [ -f "\$p" ]; then cat "\$p"; fi; done',
    );
    expect(PermissionRule.plainCommand("/bin/zsh -lc 'git status'"), "git status");
    expect(PermissionRule.plainCommand("git status"), "git status");
  });

  test("a step turned down says what it didn't do", () {
    expect(
      declinedLabel("Removed menu-draft-spring.md and menu-draft-summer.md"),
      "Didn't remove menu-draft-spring.md and menu-draft-summer.md",
    );
    expect(declinedLabel("Committed the changes"), "Didn't commit the changes");
    expect(declinedLabel("Opened Gmail"), "Didn't open Gmail");
    expect(declinedLabel("Shared a link"), "Didn't go ahead: shared a link");
    final call = ToolCall(id: "1", name: "Shell", input: const {})
      ..isError = true
      ..result = "declined";
    expect(call.declined, isTrue);
    expect(
      (ToolCall(id: "2", name: "Shell", input: const {})
            ..isError = true
            ..result = "exit 1")
          .declined,
      isFalse,
    );
  });

  test("a program file run as it is, and the Vault's own steps, are named", () {
    expect(specificCommandLabel("node check-stripe.mjs", done: true), "Ran check-stripe.mjs");
    expect(specificCommandLabel("python3 scripts/tidy.py", done: false), "Running tidy.py");
    expect(specificCommandLabel("node -e 'console.log(1)'", done: true), 'Ran a script');
    expect(toolLabel("mcp__helmy__vault_list"), "Checked the Vault");
    expect(ownStep("mcp__helmy__vault_ask"), ("Asked you for a key", "Asking you for a key"));
  });
}
