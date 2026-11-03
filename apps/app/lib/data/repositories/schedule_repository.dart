import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/engine.dart';
import '../../domain/models/scheduled_task.dart';
import '../../domain/models/session.dart';
import '../../utils/result.dart';
import '../services/storage_service.dart';
import 'conversation_repository.dart';
import 'session_repository.dart';

/// Scheduled tasks: kept on disk, and run while the app is open. Each run is a
/// new session named after the task, sending the task's message.
class ScheduleRepository extends ChangeNotifier {
  new({
    required this._storage,
    required this._sessions,
    required this._conversations,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final StorageService _storage;
  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final DateTime Function() _now;

  static const _file = 'schedules.json';

  final List<ScheduledTask> _tasks = [];
  Timer? _timer;

  List<ScheduledTask> get tasks => List.unmodifiable(_tasks);

  /// Reads the tasks, runs any whose time came while the app was closed, and
  /// checks every half minute from then on.
  Future<void> start() async {
    final json = await _storage.read(_file);
    _tasks
      ..clear()
      ..addAll([
        for (final t in (json as List? ?? const []).whereType<Map>())
          ScheduledTask.fromJson(t.cast()),
      ]);
    notifyListeners();
    await tick();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => tick());
  }

  /// Runs every task that is due.
  Future<void> tick() async {
    final now = _now();
    for (final t in [..._tasks]) {
      if (t.dueAt(now)) await run(t.id);
    }
  }

  /// The sessions a task's runs made, newest first.
  List<Session> runsOf(String taskId) =>
      _sessions.sessions.where((s) => s.taskId == taskId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<ScheduledTask> add({
    required String name,
    required String prompt,
    required String cwd,
    required PermissionLevel level,
    required Schedule schedule,
  }) async {
    final task = ScheduledTask(
      id: const Uuid().v4(),
      name: name,
      prompt: prompt,
      cwd: cwd,
      level: level,
      schedule: schedule,
      createdAt: _now(),
    );
    _tasks.add(task);
    await _save();
    return task;
  }

  Future<void> update(ScheduledTask task) async {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i < 0) return;
    _tasks[i] = task;
    await _save();
  }

  Future<void> remove(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    await _save();
  }

  /// Runs [id] now: a new session in its folder, sending its message. The
  /// schedule goes on from now, so a run missed twice runs once.
  Future<Result<Session>> run(String id) async {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return .error(Exception('No such task'));
    final task = _tasks[i];
    final now = _now();
    _tasks[i] = task.copyWith(lastRunAt: now);
    await _save();
    final created = await _sessions.create(
      cwd: task.cwd,
      level: task.level,
      title: '${task.name} · ${monthDay(now)}, ${clock(now)}',
      taskId: task.id,
    );
    if (created case Ok(:final value)) {
      unawaited(_conversations.send(value, task.prompt));
    }
    return created;
  }

  Future<void> _save() async {
    notifyListeners();
    await _storage.write(_file, [for (final t in _tasks) t.toJson()]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
