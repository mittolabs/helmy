import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/models/engine.dart';
import '../../../domain/models/scheduled_task.dart';
import '../../../domain/models/session.dart';
import '../../../utils/result.dart';

/// The scheduled tasks page: the tasks, their runs, and changing them.
class ScheduleViewModel extends ChangeNotifier {
  new({required this._schedules, required this._settings}) {
    _schedules.addListener(notifyListeners);
  }

  final ScheduleRepository _schedules;
  final SettingsRepository _settings;

  List<ScheduledTask> get tasks => _schedules.tasks;

  List<Session> runsOf(String taskId) => _schedules.runsOf(taskId);

  /// Where a new task works unless you choose: the folder new sessions use.
  String get defaultFolder => _settings.settings.fixedFolder ?? Platform.environment['HOME'] ?? '/';

  Future<void> add({
    required String name,
    required String prompt,
    required String cwd,
    required PermissionLevel level,
    required Schedule schedule,
  }) => _schedules.add(name: name, prompt: prompt, cwd: cwd, level: level, schedule: schedule);

  Future<void> save(ScheduledTask task) => _schedules.update(task);

  Future<void> setEnabled(ScheduledTask task, bool on) =>
      _schedules.update(task.copyWith(enabled: on));

  Future<void> remove(ScheduledTask task) => _schedules.remove(task.id);

  /// Runs it now; the new session's id, to open it.
  Future<String?> runNow(ScheduledTask task) async => switch (await _schedules.run(task.id)) {
    Ok(:final value) => value.id,
    Error() => null,
  };

  @override
  void dispose() {
    _schedules.removeListener(notifyListeners);
    super.dispose();
  }
}
