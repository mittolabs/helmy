import 'dart:io';

import '../../domain/models/memory.dart';
import '../../utils/result.dart';
import '../services/engines/engine_registry.dart';

/// The memory every engine keeps, gathered in one place: files to read, edit
/// and delete, and notes about memory the engines keep for themselves.
/// The connections' memory and standing instructions: the files, read,
/// written and removed, and the memory they keep elsewhere, described.
abstract interface class MemoryRepository {
  Future<List<MemoryFile>> files();
  Future<List<MemoryNote>> notes();
  bool exists(MemoryFile file);
  Future<Result<String>> read(MemoryFile file);
  Future<Result<void>> write(MemoryFile file, String text);
  Future<Result<void>> delete(MemoryFile file);
}

class MemoryRepositoryEngines implements MemoryRepository {
  new(this._engines);
  final EngineRegistry _engines;

  @override
  Future<List<MemoryFile>> files() async => [
    for (final e in _engines.engines) ...await e.memoryFiles(),
  ];

  @override
  Future<List<MemoryNote>> notes() async => [
    for (final e in _engines.engines) ...await e.memoryNotes(),
  ];

  @override
  bool exists(MemoryFile file) => File(file.path).existsSync();

  @override
  Future<Result<String>> read(MemoryFile file) async {
    try {
      final f = File(file.path);
      return .ok(await f.exists() ? await f.readAsString() : '');
    } on Exception catch (e) {
      return .error(e);
    }
  }

  @override
  Future<Result<void>> write(MemoryFile file, String text) async {
    try {
      final f = File(file.path);
      await f.parent.create(recursive: true);
      await f.writeAsString(text);
      return const .ok(null);
    } on Exception catch (e) {
      return .error(e);
    }
  }

  @override
  Future<Result<void>> delete(MemoryFile file) async {
    try {
      final f = File(file.path);
      if (await f.exists()) await f.delete();
      return const .ok(null);
    } on Exception catch (e) {
      return .error(e);
    }
  }
}
