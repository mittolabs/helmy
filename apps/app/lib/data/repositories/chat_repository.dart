import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/chat.dart';
import '../../domain/models/session.dart';
import '../services/storage_service.dart';
import 'session_repository.dart';

/// Chats (decision `0014`): the topics talked about, each the sum of its
/// threads. Every thread is in one: a new one gets a chat of its own (a side
/// chat, its session's), and a chat goes when its last thread does.
class ChatRepository extends ChangeNotifier {
  ChatRepository(this._storage, this._sessions) {
    _sessions.addListener(_keep);
  }

  final StorageService _storage;
  final SessionRepository _sessions;
  final Map<String, Chat> _chats = {};
  bool _loaded = false;

  Future<void> load() async {
    try {
      final raw = await _storage.read('chats.json');
      for (final j in ((raw as List?) ?? const []).whereType<Map>()) {
        final c = Chat.fromJson(j.cast<String, Object?>());
        _chats[c.id] = c;
      }
    } on Exception {
      // None yet.
    }
    _loaded = true;
    _keep();
  }

  Chat? byId(String id) => _chats[id];

  /// A chat's threads (side chats aside), most recent first.
  List<Session> threadsOf(String chatId) => [
    for (final s in _sessions.sessions)
      if (s.chatId == chatId && s.sideOf == null) s,
  ];

  /// When a chat was last worked in: its latest thread's time.
  DateTime lastActive(String chatId) =>
      threadsOf(chatId)
          .map((s) => s.updatedAt)
          .fold(_chats[chatId]?.createdAt ?? DateTime(1970), (a, b) => b.isAfter(a) ? b : a);

  /// Every chat, last worked in first.
  List<Chat> get chats =>
      _chats.values.toList()..sort((a, b) => lastActive(b.id).compareTo(lastActive(a.id)));

  /// The folders a chat's threads work in, most recent first.
  List<String> placesOf(String chatId) =>
      {for (final s in threadsOf(chatId)) s.repo ?? s.cwd}.toList();

  /// Every thread in a chat, a new one in a chat of its own; a one-thread
  /// chat nobody named, titled as its thread; a chat with no threads, gone.
  bool _keeping = false;

  void _keep() {
    // Saving a thread tells this again: once is enough.
    if (!_loaded || _keeping) return;
    _keeping = true;
    try {
      _tidy();
    } finally {
      _keeping = false;
    }
  }

  void _tidy() {
    var changed = false;
    // Threads before side chats, so a side chat finds its session's chat.
    final all = _sessions.sessions.toList()
      ..sort((a, b) => (a.sideOf == null ? 0 : 1).compareTo(b.sideOf == null ? 0 : 1));
    for (final s0 in all) {
      final s = _sessions.byId(s0.id) ?? s0;
      if (s.chatId != null && _chats.containsKey(s.chatId)) continue;
      // A side chat is in its session's chat.
      final parent = s.sideOf == null ? null : _sessions.byId(s.sideOf!);
      final chatId = parent?.chatId ?? _create(s.title, s.createdAt).id;
      _sessions.save(s.copyWith(chatId: chatId));
      changed = true;
    }
    for (final c in _chats.values.toList()) {
      final threads = threadsOf(c.id);
      if (threads.isEmpty && !_sessions.sessions.any((s) => s.chatId == c.id)) {
        _chats.remove(c.id);
        changed = true;
      } else if (!c.named && threads.length == 1 && threads.single.title != c.title) {
        _chats[c.id] = c.copyWith(title: threads.single.title);
        changed = true;
      }
    }
    if (changed) _persistLater();
    notifyListeners();
  }

  Chat _create(String title, DateTime at) {
    final c = Chat(id: const Uuid().v4(), title: title, createdAt: at);
    _chats[c.id] = c;
    return c;
  }

  /// Names [chatId], for good: its threads no longer name it.
  Future<void> rename(String chatId, String title) async {
    final c = _chats[chatId];
    if (c == null || title.trim().isEmpty) return;
    _chats[chatId] = c.copyWith(title: title.trim(), named: true);
    notifyListeners();
    await _persist();
  }

  /// Puts [brief] as [chatId]'s brief: written by the person, it holds.
  Future<void> setBrief(String chatId, String brief) async {
    final c = _chats[chatId];
    if (c == null) return;
    _chats[chatId] = c.copyWith(brief: brief.trim());
    notifyListeners();
    await _persist();
  }

  /// Moves [thread] (and its side chats) into [chatId]; into a chat of its
  /// own when [chatId] is null. The chat it leaves goes if it is left empty.
  Future<String> move(Session thread, String? chatId) async {
    final to = chatId ?? _create(thread.title, DateTime.now()).id;
    for (final s in _sessions.sessions.where((s) => s.id == thread.id || s.sideOf == thread.id)) {
      await _sessions.save(s.copyWith(chatId: to));
    }
    _keep();
    await _persist();
    return to;
  }

  bool _pending = false;
  void _persistLater() {
    if (_pending) return;
    _pending = true;
    Future.microtask(() async {
      _pending = false;
      await _persist();
    });
  }

  Future<void> _persist() async {
    try {
      await _storage.write('chats.json', [for (final c in _chats.values) c.toJson()]);
    } on Exception {
      // Kept in memory; written with the next change.
    }
  }

  @override
  void dispose() {
    _sessions.removeListener(_keep);
    super.dispose();
  }
}
