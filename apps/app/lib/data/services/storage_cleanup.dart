import 'dart:io';

import 'storage_service.dart';

/// What a cleanup did: when, and how many files and bytes it removed.
typedef CleanupRun = ({DateTime at, int files, int bytes});

/// Keeps Helmy's own leftovers in check: pasted pictures, page marks and
/// snapshots older than [olderThan] that no conversation refers to any
/// more. A file a chat still shows is never removed. Runs once a day.
class StorageCleanup {
  StorageCleanup(
    this._storage, {
    required this._appData,
    this.olderThan = const Duration(days: 30),
    this._extra,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final StorageService _storage;
  final Future<Directory> Function() _appData;
  final List<Directory>? _extra;
  final DateTime Function() _now;
  final Duration olderThan;

  static const _file = 'cleanup.json';

  /// The last run, as kept; null before the first.
  Future<CleanupRun?> last() async {
    final j = await _storage.read(_file);
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    if (at == null) return null;
    return (
      at: at,
      files: (j['files'] as num?)?.toInt() ?? 0,
      bytes: (j['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  /// Runs when a day has passed since the last run.
  Future<CleanupRun?> runIfDue() async {
    final l = await last();
    if (l != null && _now().difference(l.at) < const Duration(days: 1)) return null;
    return run();
  }

  /// Removes what is old and referred to by nothing; what it did.
  Future<CleanupRun> run() async {
    final data = await _appData();
    final folders = [
      Directory('${Directory.systemTemp.path}/helmy-pasted'),
      Directory('${data.path}/snapshots'),
      ...?_extra,
    ];
    // Everything a conversation, chat or session could point at.
    final said = StringBuffer();
    for (final name in ['chats.json', 'sessions.json']) {
      final f = File('${data.path}/$name');
      if (f.existsSync()) said.write(await f.readAsString());
    }
    final transcripts = Directory('${data.path}/transcripts');
    if (transcripts.existsSync()) {
      for (final f in transcripts.listSync().whereType<File>()) {
        said.write(await f.readAsString());
      }
    }
    final text = said.toString();
    final cutoff = _now().subtract(olderThan);
    var files = 0, bytes = 0;
    for (final dir in folders) {
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        final stat = f.statSync();
        if (stat.modified.isAfter(cutoff)) continue;
        // Paths are kept as written, or JSON-escaped (a slash as \/).
        if (text.contains(f.path) || text.contains(f.path.replaceAll('/', r'\/'))) continue;
        try {
          f.deleteSync();
          files++;
          bytes += stat.size;
        } on FileSystemException {
          // In use or gone: next time.
        }
      }
    }
    final done = (at: _now(), files: files, bytes: bytes);
    await _storage.write(_file, {'at': done.at.toIso8601String(), 'files': files, 'bytes': bytes});
    return done;
  }
}
