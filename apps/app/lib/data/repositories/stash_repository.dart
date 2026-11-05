import 'package:flutter/foundation.dart';

import '../services/storage_service.dart';

/// A draft put aside: its words, the files and pictures with it, and the
/// chat it was written in.
typedef Stashed = ({String text, List<String> attachments, String from, DateTime at});

/// Drafts put aside (⌘S) to go on with in any chat, the latest first; kept on
/// disk, so a restart loses none.
class StashRepository extends ChangeNotifier {
  StashRepository(this._storage);
  final StorageService _storage;

  final List<Stashed> _items = [];
  bool _loaded = false;

  List<Stashed> get items => List.unmodifiable(_items);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _storage.read('stash.json');
      for (final j in ((raw as List?) ?? const []).whereType<Map>()) {
        _items.add((
          text: '${j['text'] ?? ''}',
          attachments: [for (final a in (j['attachments'] as List? ?? const [])) '$a'],
          from: '${j['from'] ?? ''}',
          at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
        ));
      }
    } on Exception {
      // None yet.
    }
    notifyListeners();
  }

  /// Puts [text] and [attachments] aside, from the chat called [from].
  Future<void> stash(String text, List<String> attachments, {required String from}) async {
    if (text.trim().isEmpty && attachments.isEmpty) return;
    _items.insert(0, (text: text, attachments: attachments, from: from, at: DateTime.now()));
    notifyListeners();
    await _save();
  }

  /// The latest put aside, taken out; null when there is none.
  Future<Stashed?> takeLatest() async {
    if (_items.isEmpty) return null;
    final s = _items.removeAt(0);
    notifyListeners();
    await _save();
    return s;
  }

  Future<void> _save() async {
    try {
      await _storage.write('stash.json', [
        for (final s in _items)
          {
            'text': s.text,
            'attachments': s.attachments,
            'from': s.from,
            'at': s.at.toIso8601String(),
          },
      ]);
    } on Exception {
      // Kept in memory; written with the next change.
    }
  }
}
