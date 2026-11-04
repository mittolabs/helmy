import 'dart:io';

import 'package:helmy/data/services/storage_service.dart';

/// Storage in [dir], fixed now. `StorageService(root: () async => root)`
/// reads a `late root` when it writes, so a save still queued from one test
/// lands in the next test's folder, outside that test's storage's queue, and
/// the two race on one temp file (2026-11-04: `chat_repository_test` and
/// `list_menu_test` failed this way, only when the suite ran loaded).
StorageService storageAt(Directory dir) => StorageService(root: () async => dir);
