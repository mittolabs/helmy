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
Future<void> deleteFolder(Directory dir) async {
  for (final s in _made.remove(dir.path) ?? const <StorageService>[]) {
    await Future.any([s.flush(), Future<void>.delayed(const Duration(milliseconds: 500))]);
  }
  await dir.delete(recursive: true);
}
