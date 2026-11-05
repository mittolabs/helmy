import 'dart:async';
import 'dart:io';

import '../../../domain/models/chat_item.dart';
import '../../../domain/models/engine.dart';
import '../../../domain/models/session.dart';
import '../../../utils/result.dart';
import '../../services/engines/agent_engine.dart';
import '../../services/remote/remote_link.dart';
import '../conversation_repository.dart';
import '../session_repository.dart';

/// The Mac's threads, as the phone has them over [RemoteLink]: what the
/// chat screen's view model reads, so the phone draws the Mac's own chat.
/// Made and changed on the Mac only.
class RemoteSessions extends SessionRepository {
  RemoteSessions(this._link) {
    _link.addListener(notifyListeners);
  }
  final RemoteLink _link;

  @override
  List<Session> get sessions => [
    for (final c in _link.chats)
      for (final t in c.threads)
        Session(
          id: t.id,
          title: t.title,
          cwd: t.cwd,
          level: .ask,
          createdAt: t.updatedAt,
          updatedAt: t.updatedAt,
          archived: t.archived,
          chatId: c.chat.id == t.id ? null : c.chat.id,
        ),
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Session? byId(String id) => sessions.where((s) => s.id == id).firstOrNull;

  @override
  Future<Result<void>> load() async => const Result.ok(null);

  @override
  Future<Result<Session>> create({
    required String cwd,
    PermissionLevel level = .ask,
    String? title,
    String? taskId,
    String? sideOf,
    String? chatId,
  }) async => Result.error(Exception('Chats are started on the Mac, by a first message.'));

  @override
  Future<Result<void>> save(Session session) async => const Result.ok(null);

  @override
  Future<Result<void>> delete(String id) async => Result.error(Exception('Delete it on the Mac.'));

  @override
  void dispose() {
    _link.removeListener(notifyListeners);
    super.dispose();
  }
}

/// The Mac's conversations, over [RemoteLink]: each as the Mac has it, and
/// what the phone can ask of it (send, approve, answer, stop). The rest of
/// what the Mac's chat can do stays on the Mac.
class RemoteConversations extends ConversationRepository {
  RemoteConversations(this._link) {
    _link.addListener(_sync);
  }
  final RemoteLink _link;
  final _all = <String, Conversation>{};

  /// Files on the Mac that chats show, by their path there: where the
  /// phone keeps its copy, once fetched.
  final _here = <String, String>{};
  final _asked = <String>{};

  static final _picture = RegExp(r'!\[[^\]]*\]\((/[^)\s]+)\)');

  /// [item] with the Mac's files swapped for the phone's copies, fetching
  /// those not here yet.
  ChatItem _local(String id, ChatItem item) {
    String at(String path) {
      if (_here[path] case final local?) return local;
      if (_asked.add(path)) unawaited(_fetch(id, path));
      return path;
    }

    return switch (item) {
      ImageItem(:final path, :final prompt) => ImageItem(at(path), prompt),
      AssistantText(:final key, :final text) when _picture.hasMatch(text) => AssistantText(
        key,
        text.replaceAllMapped(_picture, (m) => m[0]!.replaceFirst(m[1]!, at(m[1]!))),
      ),
      _ => item,
    };
  }

  Future<void> _fetch(String id, String path) async {
    final bytes = await _link.file(id, path);
    if (bytes == null) {
      // Asked again next time it is shown.
      _asked.remove(path);
      return;
    }
    final dir = Directory('${Directory.systemTemp.path}/helmy-files');
    await dir.create(recursive: true);
    final f = File('${dir.path}/${path.hashCode.toUnsigned(32)}-${path.split('/').last}');
    await f.writeAsBytes(bytes);
    _here[path] = f.path;
    _sync();
  }

  void _sync() {
    for (final MapEntry(key: id, value: c) in _all.entries) {
      final r = _link.of(id);
      c.items
        ..clear()
        ..addAll([for (final i in r.items) _local(id, i)]);
      c
        ..busy = r.busy
        ..heldUntil = r.heldUntil
        ..loaded = true;
    }
    notifyListeners();
  }

  @override
  Conversation of(String sessionId) => _all.putIfAbsent(sessionId, Conversation.new);

  @override
  Future<void> load(String sessionId) async {
    of(sessionId);
    await _link.open(sessionId);
  }

  static Result<T> _onMac<T>() => Result.error(Exception('That is done on the Mac.'));

  @override
  Future<String> searchText(String sessionId) async => '';

  @override
  Future<void> copy(String from, String to, {required int upTo, required String note}) async {}

  @override
  Future<void> adopt(String to, List<ChatItem> items, {required String note}) async {}

  @override
  Future<Result<void>> send(
    Session session,
    String text, {
    List<String> attachments = const [],
    Set<Capability> needs = const {},
    String? from,
  }) async {
    await _link.send(session.id, text);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> rewind(Session session, int index, String text) async => _onMac();

  @override
  Future<Result<void>> showBranch(Session session, int index, int to) async => _onMac();

  @override
  Future<Result<String>> explain(String sessionId, ToolCall call) async => _onMac();

  @override
  void stopTask(String sessionId, String taskId) {}

  @override
  void interrupt(String sessionId) => unawaited(_link.interrupt(sessionId));

  @override
  Future<List<SlashCommand>> commands(Session session) async => const [];

  @override
  void unqueue(String sessionId, int index) {}

  @override
  void steer(String sessionId, int index) {}

  @override
  Future<Result<void>> compact(Session session) async => _onMac();

  @override
  void answerPermission(String sessionId, PermissionPrompt prompt, PermissionAnswer answer) =>
      unawaited(_link.answer(sessionId, prompt, answer.name));

  @override
  void answerQuestion(String sessionId, PermissionPrompt prompt) =>
      unawaited(_link.answerQuestion(sessionId, prompt));

  @override
  Future<void> setLevel(String sessionId, PermissionLevel level) async {}

  @override
  Future<void> stop(String sessionId) async => _link.interrupt(sessionId);

  @override
  Future<void> forget(String sessionId) async {
    _all.remove(sessionId);
    await _link.close(sessionId);
  }

  @override
  void dispose() {
    _link.removeListener(_sync);
    super.dispose();
  }
}
