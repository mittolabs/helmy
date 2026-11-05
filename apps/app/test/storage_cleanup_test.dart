import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/storage_cleanup.dart';
import 'package:helmy/data/services/storage_service.dart';

import 'support/storage.dart';

/// Old leftovers go; anything a chat still shows stays, however old.
void main() {
  test('old and referred to by nothing goes; the rest stays', () async {
    final root = await Directory.systemTemp.createTemp('cleanup');
    addTearDown(() => deleteFolder(root));
    final data = await Directory('${root.path}/data').create();
    final extra = await Directory('${root.path}/pasted').create();
    final now = DateTime(2026, 11, 5);
    final old = now.subtract(const Duration(days: 40));
    File make(String name, {DateTime? at}) {
      final f = File('${extra.path}/$name')..writeAsStringSync('x' * 100);
      f.setLastModifiedSync(at ?? old);
      return f;
    }

    final kept = make('shown.png');
    final gone = make('forgotten.png');
    final fresh = make('new.png', at: now.subtract(const Duration(days: 2)));
    await Directory('${data.path}/transcripts').create();
    File('${data.path}/transcripts/t.json')
        .writeAsStringSync('[{"kind":"user","attachments":["${kept.path}"]}]');
    final storage = StorageService(root: () async => data);
    final cleanup = StorageCleanup(
      storage,
      appData: () async => data,
      extra: [extra],
      now: () => now,
    );
    final done = await cleanup.run();
    expect((done.files, done.bytes), (1, 100));
    expect(gone.existsSync(), isFalse);
    expect(kept.existsSync(), isTrue, reason: 'a chat still shows it');
    expect(fresh.existsSync(), isTrue, reason: 'not old enough');
    await storage.flush();
    expect((await cleanup.last())?.files, 1);
    expect(await cleanup.runIfDue(), isNull, reason: 'run today already');
  });
}
