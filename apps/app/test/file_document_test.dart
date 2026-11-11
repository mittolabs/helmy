import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/chat/view_models/file_document.dart';

void main() {
  late Directory root;
  late File file;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('file-editor');
    file = File('${root.path}/source.dart');
    await file.writeAsString('void main() {\r\n\tprint("hello");\r\n}\r\n');
  });
  tearDown(() => root.delete(recursive: true));

  test('editing and saving preserves tabs and line endings', () async {
    final doc = FileDocument(file.path);
    addTearDown(doc.dispose);
    await doc.load();
    expect(doc.loaded, isTrue);
    expect(doc.dirty, isFalse);
    doc.edit(doc.text.replaceFirst('hello', 'world'));
    expect(doc.dirty, isTrue);
    expect(await doc.save(), isTrue);
    expect(doc.dirty, isFalse);
    expect(await file.readAsString(), 'void main() {\r\n\tprint("world");\r\n}\r\n');
  });

  test('external changes are never overwritten and drafts stay available', () async {
    final doc = FileDocument(file.path);
    addTearDown(doc.dispose);
    await doc.load();
    doc.edit('my edits');
    await file.writeAsString('agent edits');
    expect(await doc.save(), isFalse);
    expect(await file.readAsString(), 'agent edits');
    expect(doc.text, 'my edits');
    expect(doc.dirty, isTrue);
    expect(doc.error, contains('changed on disk'));
  });

  test('deleted files are not silently recreated on save', () async {
    final doc = FileDocument(file.path);
    addTearDown(doc.dispose);
    await doc.load();
    doc.edit('my edits');
    await file.delete();
    expect(await doc.save(), isFalse);
    expect(await file.exists(), isFalse);
    expect(doc.text, 'my edits');
  });

  test('a snippet is a draft until saved to a new file', () async {
    final doc = FileDocument.fromText('', 'print("example");');
    addTearDown(doc.dispose);
    expect(doc.dirty, isTrue);
    final destination = '${root.path}/example.dart';
    expect(await doc.saveAs(destination), isTrue);
    expect(doc.path, destination);
    expect(doc.dirty, isFalse);
    expect(await File(destination).readAsString(), 'print("example");');
    doc.edit('print("edited");');
    expect(await doc.save(), isTrue);
  });

  test('Save As refuses to replace an existing project file', () async {
    final original = await file.readAsString();
    final doc = FileDocument.fromText('', 'snippet');
    addTearDown(doc.dispose);
    expect(await doc.saveAs(file.path), isFalse);
    expect(doc.path, isEmpty);
    expect(doc.dirty, isTrue);
    expect(await file.readAsString(), original);
  });

  test('binary files cannot be edited', () async {
    await file.writeAsBytes([0, 1, 2]);
    final doc = FileDocument(file.path);
    addTearDown(doc.dispose);
    await doc.load();
    expect(doc.loaded, isFalse);
    expect(doc.error, contains('not text'));
  });
}
