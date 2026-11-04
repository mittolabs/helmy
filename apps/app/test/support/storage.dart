import 'dart:io';

import 'package:helmy/data/services/storage_service.dart';

/// Storage in [dir], fixed now. `StorageService(root: () async => root)`
/// reads a `late root` when it writes, so a save still queued from one test
/// lands in the next test's folder, outside that test's storage's queue, and
/// the two race on one temp file (2026-11-04: `chat_repository_test` and
/// `list_menu_test` failed this way, only when the suite ran loaded).
StorageService storageAt(Directory dir) {
  final storage = StorageService(root: () async => dir);
  (_made[dir.path] ??= []).add(storage);
  return storage;
}

final _made = <String, List<StorageService>>{};

/// Deletes [dir] once every save into it has landed: deleting under a save
/// still on its way fails that save ("No such file"), in whatever test is
/// running then (2026-11-04: `list_menu_test`, a loaded suite). A save a
/// widget test started on its fake clock never lands in real time, so the
/// wait is short: such a save does not run once the test is over.
///
/// A save can also start while the folder is being deleted (a listener
/// reacting to the last change), leaving it "not empty": the delete is tried
/// again, after another flush (2026-11-05: `pull_requests_test`).
Future<void> deleteFolder(Directory dir) async {
  final made = _made.remove(dir.path) ?? const <StorageService>[];
  for (var attempt = 1; ; attempt++) {
    for (final s in made) {
      await Future.any([s.flush(), Future<void>.delayed(const Duration(milliseconds: 500))]);
    }
    try {
      await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 5 || !dir.existsSync()) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
