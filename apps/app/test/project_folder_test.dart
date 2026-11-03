import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/claude/claude_engine.dart';

void main() {
  test('a project folder name reads back as the path on disk, dashes and all', () {
    final root = Directory.systemTemp.createTempSync('pf').resolveSymbolicLinksSync();
    Directory('$root/Work/billing-api').createSync(recursive: true);
    Directory('$root/code/my.app').createSync(recursive: true);
    Directory('$root/code/web_app').createSync(recursive: true);
    String name(String path) => path.replaceAll(RegExp(r'[^A-Za-z0-9]'), '-');
    expect(ClaudeEngine.projectFolder(name('$root/Work/billing-api')), '$root/Work/billing-api');
    expect(ClaudeEngine.projectFolder(name('$root/code/my.app')), '$root/code/my.app');
    expect(ClaudeEngine.projectFolder(name('$root/code/web_app')), '$root/code/web_app');
    expect(ClaudeEngine.projectFolder('-no-such-place'), '-no-such-place');
    Directory(root).deleteSync(recursive: true);
  });
}
