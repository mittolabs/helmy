import 'package:flutter/foundation.dart';

import '../../domain/models/engine.dart';
import '../../domain/models/session.dart';
import '../../utils/result.dart';

/// The list of sessions: the source of truth for their names, folders
/// and settings. Notifies when the list changes.
abstract class SessionRepository extends ChangeNotifier {
  /// Most recently used first.
  List<Session> get sessions;

  Session? byId(String id);

  Future<Result<void>> load();

  /// A new session in [cwd]. [title] names it for good; without one it is
  /// named after its first message. [taskId] marks it a scheduled task's run;
  /// [sideOf], a side chat of that session.
  Future<Result<Session>> create({
    required String cwd,
    PermissionLevel level = .ask,
    String? title,
    String? taskId,
    String? sideOf,
    String? chatId,
  });

  Future<Result<void>> save(Session session);

  Future<Result<void>> delete(String id);
}
