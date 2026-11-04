import 'package:uuid/uuid.dart';

import '../../domain/models/engine.dart';
import '../../domain/models/session.dart';
import '../../utils/result.dart';
import '../services/storage_service.dart';
import 'session_repository.dart';

class SessionRepositoryLocal extends SessionRepository {
  new(this._storage);

  final StorageService _storage;
  final List<Session> _sessions = [];

  @override
  List<Session> get sessions => List.unmodifiable(_sessions);

  @override
  Session? byId(String id) => _sessions.where((s) => s.id == id).firstOrNull;

  @override
  Future<Result<void>> load() async {
    try {
      final raw = await _storage.read('sessions.json');
      _sessions
        ..clear()
        ..addAll(
          ((raw as List?) ?? const []).whereType<Map>().map(
            (j) => Session.fromJson(j.cast<String, Object?>()),
          ),
        );
      _sort();
      notifyListeners();
      return const .ok(null);
    } on Exception catch (e) {
      return .error(e);
    }
  }

  @override
  Future<Result<Session>> create({
    required String cwd,
    PermissionLevel level = .ask,
    String? title,
    String? taskId,
    String? sideOf,
    String? chatId,
  }) async {
    final now = DateTime.now();
    final name = cwd.split('/').where((p) => p.isNotEmpty).lastOrNull ?? cwd;
    final session = Session(
      id: const Uuid().v4(),
      level: level,
      title: title ?? 'New session in $name',
      taskId: taskId,
      sideOf: sideOf,
      chatId: chatId,
      cwd: cwd,
      createdAt: now,
      updatedAt: now,
    );
    _sessions.insert(0, session);
    notifyListeners();
    final saved = await _persist();
    return switch (saved) {
      Ok() => .ok(session),
      Error(:final error) => .error(error),
    };
  }

  @override
  Future<Result<void>> save(Session session) async {
    final i = _sessions.indexWhere((s) => s.id == session.id);
    if (i < 0) return .error(Exception('No session ${session.id}'));
    _sessions[i] = session;
    _sort();
    notifyListeners();
    return _persist();
  }

  @override
  Future<Result<void>> delete(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    notifyListeners();
    await _storage.delete('transcripts/$id.json');
    return _persist();
  }

  void _sort() => _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<Result<void>> _persist() async {
    try {
      await _storage.write('sessions.json', _sessions.map((s) => s.toJson()).toList());
      return const .ok(null);
    } on Exception catch (e) {
      return .error(e);
    }
  }
}
