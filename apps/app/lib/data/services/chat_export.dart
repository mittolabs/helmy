import 'dart:io';

import '../../domain/models/chat_item.dart';
import '../../utils/transcript_markdown.dart';
import '../repositories/session_repository.dart';
import 'storage_service.dart';

/// Every session's conversation as Markdown files in a folder.
class ChatExport {
  new(this._sessions, this._storage);
  final SessionRepository _sessions;
  final StorageService _storage;

  /// Writes one file per session into [dir]; returns how many it wrote.
  Future<int> exportAll(String dir) async {
    var n = 0;
    final used = <String>{};
    for (final s in _sessions.sessions) {
      final raw = await _storage.read('transcripts/${s.id}.json');
      final items = [
        for (final j in (raw as List? ?? const []).whereType<Map>()) ChatItem.fromJson(j.cast()),
      ];
      if (items.isEmpty) continue;
      var name = s.title.replaceAll(RegExp(r'[/:\\]'), '-').trim();
      if (name.isEmpty) name = 'session';
      var file = name;
      for (var i = 2; !used.add(file); i++) {
        file = '$name $i';
      }
      await File('$dir/$file.md').writeAsString(transcriptMarkdown(s.title, items));
      n++;
    }
    return n;
  }
}
