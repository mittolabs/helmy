import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// JSON files in the app's support folder: the session list and one
/// transcript per session.
class StorageService {
  new({Future<Directory> Function()? root}) : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;

  Future<File> _file(String name) async {
    final dir = await _root();
    return File('${dir.path}/$name');
  }

  Future<Object?> read(String name) async {
    final file = await _file(name);
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString());
    } on FormatException {
      return null;
    }
  }

  /// Writes to one file run one after another; overlapping saves shared a
  /// temp file and lost each other (found by the live test, 2026-11-03).
  final Map<String, Future<void>> _pending = {};

  Future<void> write(String name, Object? value) {
    final encoded = jsonEncode(value);
    final next = (_pending[name] ?? Future.value()).then((_) async {
      final file = await _file(name);
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(encoded);
      await tmp.rename(file.path);
    });
    _pending[name] = next.catchError((_) {});
    return next;
  }

  /// Completes when every write started so far has landed.
  Future<void> flush() => Future.wait(_pending.values);

  Future<void> delete(String name) async {
    await _pending[name];
    final file = await _file(name);
    if (await file.exists()) await file.delete();
  }
}
