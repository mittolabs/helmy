import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/chat_export.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

void main() {
  test('every conversation becomes a Markdown file; empty ones are skipped', () async {
    final root = await Directory.systemTemp.createTemp('export');
    final out = await Directory('${root.path}/out').create();
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    for (final title in ['Fix login', 'Fix login', 'Empty']) {
      final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
      await sessions.save(s.copyWith(title: title));
      if (title != 'Empty') {
        await storage.write('transcripts/${s.id}.json', [
          UserMessage('hello').toJson(),
          AssistantText('a', 'hi').toJson(),
        ]);
      }
    }
    expect(await ChatExport(sessions, storage).exportAll(out.path), 2);
    final names = out.listSync().map((f) => f.path.split('/').last).toList()..sort();
    expect(names, ['Fix login 2.md', 'Fix login.md']);
    expect(File('${out.path}/Fix login.md').readAsStringSync(), contains('**You:**\n\nhello'));
    await storage.flush();
    await root.delete(recursive: true);
  });
}
