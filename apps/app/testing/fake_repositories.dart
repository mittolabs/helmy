// In-memory stand-ins for the repositories, so a view model can be tested
// with no storage, connection, git or GitHub behind it.
import 'dart:async';

import 'package:helmy/data/repositories/attention_repository.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/project_repository.dart';
import 'package:helmy/data/repositories/schedule_repository.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/repositories/ship_repository.dart';
import 'package:helmy/data/services/shipping.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/memory.dart';
import 'package:helmy/domain/models/scheduled_task.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/utils/result.dart';

class FakeSettingsRepository extends SettingsRepository {
  FakeSettingsRepository([this._settings = const AppSettings()]);
  AppSettings _settings;

  @override
  AppSettings get settings => _settings;

  @override
  Future<void> load() async {}

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
    notifyListeners();
  }
}

class FakeMemoryRepository implements MemoryRepository {
  final Map<String, String> contents = {};
  final List<MemoryFile> known = [];

  @override
  Future<List<MemoryFile>> files() async => known;

  @override
  Future<List<MemoryNote>> notes() async => const [];

  @override
  bool exists(MemoryFile file) => contents.containsKey(file.path);

  @override
  Future<Result<String>> read(MemoryFile file) async => .ok(contents[file.path] ?? '');

  @override
  Future<Result<void>> write(MemoryFile file, String text) async {
    contents[file.path] = text;
    return const .ok(null);
  }

  @override
  Future<Result<void>> delete(MemoryFile file) async {
    contents.remove(file.path);
    return const .ok(null);
  }
}

class FakeScheduleRepository extends ScheduleRepository {
  final List<ScheduledTask> _tasks = [];
  final ran = <String>[];

  @override
  List<ScheduledTask> get tasks => List.unmodifiable(_tasks);

  @override
  Future<void> start() async {}

  @override
  Future<void> tick() async {}

  @override
  List<Session> runsOf(String taskId) => const [];

  @override
  Future<ScheduledTask> add({
    required String name,
    required String prompt,
    required String cwd,
    required PermissionLevel level,
    required Schedule schedule,
  }) async {
    final task = ScheduledTask(
      id: 'task-${_tasks.length + 1}',
      name: name,
      prompt: prompt,
      cwd: cwd,
      level: level,
      schedule: schedule,
      createdAt: DateTime.now(),
    );
    _tasks.add(task);
    notifyListeners();
    return task;
  }

  @override
  Future<void> update(ScheduledTask task) async {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) _tasks[i] = task;
    notifyListeners();
  }

  @override
  Future<void> remove(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  @override
  Future<Result<Session>> run(String id) async {
    ran.add(id);
    return .error(Exception('Fakes run nothing'));
  }
}

class FakeAttentionRepository extends AttentionRepository {
  final Set<String> unread = {};
  final _inApp = StreamController<({String sessionId, String title, String body})>.broadcast();
  String? viewed;

  @override
  bool notificationsBlocked = false;

  @override
  Future<void> checkNotifications() async {}

  @override
  bool isUnread(String sessionId) => unread.contains(sessionId);

  @override
  void markRead(String sessionId) {
    unread.remove(sessionId);
    notifyListeners();
  }

  @override
  set viewing(String? sessionId) => viewed = sessionId;

  @override
  String? faceNow() => null;

  @override
  Stream<({String sessionId, String title, String body})> get inApp => _inApp.stream;

  /// Says [body] inside Helmy, as the real one does for another session.
  void say(String sessionId, String title, String body) =>
      _inApp.add((sessionId: sessionId, title: title, body: body));
}

class FakeShipRepository extends ShipRepository {
  final Map<String, BranchState> states = {};
  final asked = <String>[];

  @override
  BranchState? stateOf(String sessionId) => states[sessionId];

  @override
  Future<BranchState?> refresh(Session session) async => states[session.id];

  @override
  Future<void> commit(Session session) async => asked.add('commit ${session.id}');

  @override
  Future<void> openPullRequest(Session session) async => asked.add('pull request ${session.id}');

  @override
  Future<void> watch(Session session, bool on) async => asked.add('watch ${session.id} $on');

  @override
  Future<void> check(Session session) async => asked.add('check ${session.id}');

  @override
  Stream<String> get merged => const Stream.empty();
}

class FakeProjectRepository implements ProjectRepository {
  /// Folder → the repository it is in.
  final Map<String, String> repos = {};
  final removed = <String>[];
  PermissionLevel level = PermissionLevel.ask;

  @override
  Future<String?> repoOf(String folder) async => repos[folder];

  @override
  Future<PermissionLevel> levelFor(String folder) async => level;

  @override
  Future<bool> removeCopy(String repo, String path) async {
    removed.add(path);
    return true;
  }

  final restored = <String>[];
  var tidied = 0;

  @override
  Future<bool> restoreCopy(Session session) async {
    restored.add(session.cwd);
    return true;
  }

  @override
  Future<List<String>> tidy(List<Session> sessions, {Set<String> working = const {}}) async {
    tidied++;
    return const [];
  }
}
