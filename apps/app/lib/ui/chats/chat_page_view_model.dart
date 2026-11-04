import 'package:flutter/foundation.dart';

import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/services/turn_log.dart';
import '../../domain/models/chat.dart';
import '../../domain/models/session.dart';
import '../../utils/result.dart';

/// A chat's page: the topic, what it has come to, where it works, and its
/// threads, each to open, move, or start anew.
class ChatPageViewModel extends ChangeNotifier {
  ChatPageViewModel({
    required this.chatId,
    required this._chats,
    required this._sessions,
    this._log,
  }) {
    _chats.addListener(notifyListeners);
  }

  final String chatId;
  final ChatRepository _chats;
  final SessionRepository _sessions;
  final TurnLog? _log;

  Chat? get chat => _chats.byId(chatId);
  List<Session> get threads => _chats.threadsOf(chatId);
  List<String> get places => _chats.placesOf(chatId);

  /// Every other chat, to move a thread into.
  List<Chat> get others => [
    for (final c in _chats.chats)
      if (c.id != chatId) c,
  ];

  Future<void> rename(String title) => _chats.rename(chatId, title);

  Future<void> setBrief(String brief) async {
    final before = chat?.brief ?? '';
    await _chats.setBrief(chatId, brief);
    if (before.trim() != brief.trim()) {
      await _log?.correction(what: 'brief', thread: '', from: chatId, to: chatId);
    }
  }

  /// Moves [thread] into chat [to] (a chat of its own when null). The chat it
  /// lands in.
  Future<String> move(Session thread, String? to) async {
    final landed = await _chats.move(thread, to);
    await _log?.correction(what: 'move', thread: thread.id, from: chatId, to: landed);
    return landed;
  }

  /// A new thread in this chat, in the folder it worked in last.
  Future<String?> newThread() async {
    final where = threads.firstOrNull;
    if (where == null) return null;
    final made = await _sessions.create(
      cwd: where.repo ?? where.cwd,
      level: where.level,
      chatId: chatId,
    );
    return switch (made) {
      Ok(value: final s) => s.id,
      _ => null,
    };
  }

  @override
  void dispose() {
    _chats.removeListener(notifyListeners);
    super.dispose();
  }
}
