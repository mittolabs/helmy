import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/memory_repository.dart';
import '../../../data/repositories/settings_repository.dart';

import 'dart:io';

import '../../../data/services/desktop_service.dart';
import '../../../data/services/engines/claude/claude_engine.dart';
import '../../../data/services/engines/codex/codex_engine.dart';
import '../../../data/services/engines/engine_registry.dart';
import '../../../data/services/engines/usage_meter.dart';
import '../../../domain/models/engine.dart';
import '../../../domain/models/memory.dart';
import '../../../domain/models/settings.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../../utils/platform.dart';
import '../../../utils/format.dart';
import '../../../domain/models/session.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../core/file_actions.dart';

enum SettingsSection { general, projects, agents, tools, memory, data, keyboard }

/// One engine as settings shows it: what it is, whether it can run, and what
/// it last said about its usage.
typedef AgentRow = ({
  EngineInfo info,
  bool enabled,
  String? problem,
  Usage? usage,
  DateTime? downUntil,
});

class SettingsViewModel extends ChangeNotifier {
  new({
    required this._settings,
    required this._engines,
    required this._meter,
    required this._memory,
  }) {
    _settings.addListener(notifyListeners);
    _meter.addListener(notifyListeners);
    save = Command1(_save);
    remove = Command0(_remove);
    _checkEngines();
    loadMemory();
  }

  final SettingsRepository _settings;
  final EngineRegistry _engines;
  final UsageMeter _meter;
  final MemoryRepository _memory;

  SettingsSection section = .general;

  void show(SettingsSection s) {
    section = s;
    notifyListeners();
  }

  // General.

  AppSettings get settings => _settings.settings;
  Future<void> update(AppSettings s) => _settings.save(s);

  // Projects.

  /// The sessions, for the projects they work in; set where the page is made.
  SessionRepository? sessions;

  /// Every repository a session has worked in, and every one set before,
  /// by its top folder, sorted by name.
  /// Which repository a folder is in; set where the page is made.
  ProjectRepository? projectsOf;

  Future<List<String>> projects() async {
    final found = <String>{...settings.projects.keys};
    for (final s in sessions?.sessions ?? const <Session>[]) {
      if (s.repo case final repo?) {
        found.add(repo);
      } else if (await projectsOf?.repoOf(s.cwd) case final repo?) {
        found.add(repo);
      }
    }
    return found.toList()..sort((a, b) => folderName(a).compareTo(folderName(b)));
  }

  /// Sets [repo]'s own settings; null for a field leaves it as everywhere.
  Future<void> setProject(
    String repo, {
    bool? ownCopies,
    PermissionLevel? level,
    bool clearOwn = false,
    bool clearLevel = false,
  }) {
    final now = settings.project(repo);
    final next = ProjectSettings(
      ownCopies: clearOwn ? null : ownCopies ?? now.ownCopies,
      level: clearLevel ? null : level ?? now.level,
    );
    return update(settings.copyWith(projects: {...settings.projects, repo: next}));
  }

  // Agents.

  final Map<String, String?> _problems = {};
  final Map<String, Set<Capability>> _connections = {};

  /// What [engineId] is connected to, once asked; null while asking.
  Set<Capability>? connectionsOf(String engineId) => _connections[engineId];
  bool checked = false;

  /// The models Ollama has, or null when it is not running.
  List<String>? localModels;

  Future<void> _checkEngines() async {
    localModels = await CodexEngine.ollamaModels();
    // Engines that can say their usage without a message are asked now.
    for (final e in _engines.engines) {
      unawaited(e.readUsage().then((u) => _meter.report(e.info.id, u)));
      unawaited(
        e.connected().then((set) {
          _connections[e.info.id] = set;
          notifyListeners();
        }),
      );
    }
    for (final e in _engines.engines) {
      _problems[e.info.id] = await e.unavailableReason();
    }
    checked = true;
    notifyListeners();
  }

  List<AgentRow> get agents => [
    for (final e in _engines.engines)
      (
        info: e.info,
        enabled: !settings.disabledEngines.contains(e.info.id),
        problem: _problems[e.info.id],
        usage: _meter.usageOf(e.info.id),
        downUntil: _meter.downUntil(e.info.id),
      ),
  ];

  Future<void> setEnabled(String engineId, bool on) {
    final off = {...settings.disabledEngines};
    on ? off.remove(engineId) : off.add(engineId);
    return update(settings.copyWith(disabledEngines: off));
  }

  // Skills and tools: what each engine can run, and the servers it reaches.

  /// Per engine, once asked: its skills and commands, and its MCP servers.
  final Map<String, ({List<SlashCommand> commands, List<({String name, String status})> servers})>
  tools = {};
  bool toolsLoaded = false;

  Future<void> loadTools() async {
    final home = homeDir;
    for (final e in _engines.engines) {
      if (e.info.localOnly) continue;
      final both = await (e.commands(home), e.servers()).wait;
      tools[e.info.id] = (commands: both.$1, servers: both.$2);
      notifyListeners();
    }
    toolsLoaded = true;
    notifyListeners();
  }

  // Data and storage: where things are, how big, and clearing them out.

  /// A place on disk Helmy or an agent keeps things, with its size.
  List<({String label, String path, int? bytes, String note})> places = const [];
  bool? openAtLogin;
  DesktopService? _desktop;

  /// Opening and showing files, for what this page saves.
  FileActions get fileActions => _Files(_desktop);

  set desktop(DesktopService d) {
    _desktop = d;
    d.openAtLogin().then((v) {
      openAtLogin = v;
      notifyListeners();
    });
  }

  Future<void> setOpenAtLogin(bool on) async {
    openAtLogin = await _desktop?.openAtLogin(on);
    notifyListeners();
  }

  Future<void> loadPlaces(String supportDir) async {
    final home = homeDir;
    final d = _desktop;
    if (d == null) return;
    final list = [
      (label: 'Helmy', path: supportDir, note: 'Sessions, conversations, settings'),
      (
        label: 'Pasted pictures',
        path: '${Directory.systemTemp.path}/helmy-pasted',
        note: 'Pictures pasted into messages',
      ),
      for (final e in _engines.engines)
        if (e is ClaudeEngine)
          (
            label: e.info.name,
            path: '${e.configDir ?? '$home/.claude'}/projects',
            note: "Claude Code's own copy of each conversation",
          ),
      (
        label: 'Codex',
        path: '$home/.codex/sessions',
        note: "Codex's own copy of each conversation",
      ),
    ];
    places = [
      for (final p in list)
        (label: p.label, path: p.path, note: p.note, bytes: await d.sizeOf(p.path)),
    ];
    notifyListeners();
  }

  void reveal(String path) => _desktop?.reveal(path);

  // Memory.

  List<MemoryFile> files = const [];
  List<MemoryNote> notes = const [];
  MemoryFile? selected;
  String? original;
  bool loadingMemory = true;

  late final Command1<void, String> save;
  late final Command0<void> remove;

  bool exists(MemoryFile f) => _memory.exists(f);

  Future<void> loadMemory() async {
    loadingMemory = true;
    notifyListeners();
    files = await _memory.files();
    notes = await _memory.notes();
    loadingMemory = false;
    notifyListeners();
  }

  /// Back to the list of files, on a window too narrow to show both.
  void closeFile() {
    selected = null;
    original = null;
    notifyListeners();
  }

  Future<void> open(MemoryFile file) async {
    selected = file;
    original = null;
    notifyListeners();
    final text = await _memory.read(file);
    if (selected != file) return;
    original = switch (text) {
      Ok(:final value) => value,
      Error() => '',
    };
    notifyListeners();
  }

  Future<Result<void>> _save(String text) async {
    final file = selected;
    if (file == null) return .error(Exception('No file open'));
    final result = await _memory.write(file, text);
    if (result is Ok) original = text;
    notifyListeners();
    return result;
  }

  Future<Result<void>> _remove() async {
    final file = selected;
    if (file == null) return .error(Exception('No file open'));
    final result = await _memory.delete(file);
    if (result is Ok) {
      selected = null;
      original = null;
      await loadMemory();
    }
    return result;
  }

  @override
  void dispose() {
    _settings.removeListener(notifyListeners);
    _meter.removeListener(notifyListeners);
    super.dispose();
  }
}

class _Files implements FileActions {
  _Files(this._desktop);
  final DesktopService? _desktop;

  @override
  Future<void> open(String where) async => _desktop?.open(where);

  @override
  Future<void> reveal(String path) async => _desktop?.reveal(path);
}
