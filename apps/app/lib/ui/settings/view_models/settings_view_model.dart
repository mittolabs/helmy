import '../../core/key_bindings.dart';

import 'package:path_provider/path_provider.dart';

import '../../../data/services/engines/acp/acp_registry.dart';
import '../../../data/services/engines/acp/acp_engine.dart';
import '../../../domain/models/work.dart';
import '../../../data/services/engines/engine_router.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/memory_repository.dart';
import '../../../data/repositories/settings_repository.dart';

import 'dart:io';

import '../../../data/services/chromium/chromium_service.dart';
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
import '../../../data/services/connections_setup.dart';
import '../../../utils/format.dart';
import '../../../domain/models/session.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../data/repositories/project_repository.dart';
import 'settings_index.dart';
import '../../core/file_actions.dart';

enum SettingsSection {
  general,
  appearance,
  preview,
  projects,
  agents,
  tools,
  memory,
  data,
  keyboard,
  phone,
  archive,
  about,
}

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
    query = '';
    target = null;
    notifyListeners();
  }

  /// What is typed in the search box. While it is not empty the list beside
  /// the page shows what matches, and the page follows the one picked.
  String query = '';

  /// The page names, for matching a search against them: set by the screen.
  String Function(SettingsSection) pageName = (s) => s.name;

  /// What matches [query], best first.
  List<SettingEntry> get results => searchSettings(query, pageName);

  /// Which result is picked: moved with ↑ and ↓.
  int picked = 0;

  /// The setting the page brings into view and lights up, and a count that
  /// changes each time it is asked for (the same one twice lights it twice).
  String? target;
  int targetTick = 0;

  /// Its control takes the keyboard when it comes into view: true once the
  /// search is done with, false while only looking through the results.
  bool focusTarget = false;

  void search(String q) {
    query = q;
    picked = 0;
    _follow(results.firstOrNull, focus: false);
  }

  /// Moves the pick by [by], the page following it.
  void move(int by) {
    final r = results;
    if (r.isEmpty) return;
    picked = (picked + by).clamp(0, r.length - 1);
    _follow(r[picked], focus: false);
  }

  /// Goes to [e] (else the picked result): the search is done with, the page
  /// shows it, lit, its control taking the keyboard.
  void choose([SettingEntry? e]) {
    final r = results;
    final to = e ?? (r.isEmpty ? null : r[picked.clamp(0, r.length - 1)]);
    if (to == null) return;
    query = '';
    _follow(to, focus: true);
  }

  void _follow(SettingEntry? e, {required bool focus}) {
    if (e != null) {
      section = e.section;
      target = e.title;
      targetTick++;
      focusTarget = focus;
    }
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
      actions: now.actions,
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
    unawaited(checkVersions());
  }

  // Versions: what is installed of each connection, and whether its maker
  // has a newer one.

  /// By kind ('claude', 'codex', 'ollama'): installed and newest, either
  /// null when it could not be found out. Absent until checked.
  final versions = <String, ({String? installed, String? latest})>{};

  /// The kinds being updated now.
  final updating = <String>{};

  /// The kinds of connection there are here, in the list's order.
  List<String> get kinds =>
      {for (final e in _engines.engines) ?ConnectionsSetup.kindOf(e.info.id)}.toList();

  /// Kinds with a newer version than the one installed.
  List<String> get outdated => [
    for (final k in kinds)
      if (versions[k] case (installed: final i?, latest: final l?)
          when ConnectionsSetup.newer(l, i))
        k,
  ];

  /// Counts each reading of a kind's version and each update: a check that
  /// was asked before an update and answers after it would put back the old
  /// version, so only the latest of them writes (seen as "Update all" leaving
  /// a connection listed as behind, 2026-11-05).
  final _versionReads = <String, int>{};

  Future<void> checkVersions() async {
    final s = setup;
    if (s == null) return;
    await Future.wait([
      for (final k in kinds)
        () async {
          final read = _versionReads[k] = (_versionReads[k] ?? 0) + 1;
          final (i, l) = await (s.installedVersion(k), s.latestVersion(k)).wait;
          if (_versionReads[k] != read) return;
          versions[k] = (installed: i, latest: l);
          notifyListeners();
        }(),
    ]);
  }

  /// Updates [kind]; false when the update did not run or failed.
  Future<bool> updateConnection(String kind) async {
    final s = setup;
    if (s == null || !updating.add(kind)) return false;
    notifyListeners();
    final ok = await s.update(kind);
    // Any check still on its way read the version from before this update.
    final read = _versionReads[kind] = (_versionReads[kind] ?? 0) + 1;
    final now = await s.installedVersion(kind);
    if (_versionReads[kind] == read) {
      versions[kind] = (installed: now, latest: versions[kind]?.latest);
    }
    updating.remove(kind);
    notifyListeners();
    return ok;
  }

  /// Updates every connection with a newer version; how many did.
  Future<int> updateAll() async {
    var n = 0;
    for (final k in outdated) {
      if (await updateConnection(k)) n++;
    }
    return n;
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

  /// The connection whose details show beside the list.
  String? chosenAgent;

  AgentRow? get chosen {
    final all = agents;
    return all.where((a) => a.info.id == chosenAgent).firstOrNull ?? all.firstOrNull;
  }

  void chooseAgent(String engineId) {
    chosenAgent = engineId;
    notifyListeners();
  }

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

  // Preview: what draws its pages, and which Chromium browser.

  /// Chromium browsers on this computer; set where the page is made.
  ChromiumService? chromium;

  /// Signs connections in, and adds and removes their accounts.
  ConnectionsSetup? setup;

  /// The kind of account being added ('claude', 'codex') while its
  /// browser sign-in waits.
  String? adding;

  /// The kind of connection [engineId] is an account of, where another
  /// account can be added: 'claude', 'codex', or null.
  static String? kindOf(String engineId) => switch (engineId) {
    'claude' || 'codex' => engineId,
    _ when engineId.startsWith('claude-') => 'claude',
    _ when engineId.startsWith('codex-') => 'codex',
    _ => null,
  };

  /// The kinds of connection here, for "best at": 'claude' to "Claude
  /// Code", one entry for every account of it.
  Map<String, String> get families => {
    for (final e in _engines.engines)
      if (!e.info.localOnly) HeadroomRouter.familyOf(e.info.id): e.info.name.split(' (').first,
  };

  /// An agent's icon, as the registry listed it.
  String? iconOf(String engineId) =>
      settings.accounts.where((a) => a.id == engineId).firstOrNull?.icon;

  /// Sets [command]'s keys; null puts back Helmy's own.
  Future<void> setKey(AppCommand command, KeyBinding? keys) {
    final next = {...settings.keys};
    if (keys == null || keys == command.standard) {
      next.remove(command.name);
    } else {
      next[command.name] = keys.saved;
    }
    return update(settings.copyWith(keys: next));
  }

  /// The other command [keys] already belong to, if any.
  AppCommand? keyTakenBy(AppCommand command, KeyBinding keys) => AppCommand.values
      .where((c) => c != command && bindingOf(c, settings.keys) == keys)
      .firstOrNull;

  /// Whether "Best at" is unfolded.
  bool bestAtOpen = false;

  void toggleBestAt() {
    bestAtOpen = !bestAtOpen;
    notifyListeners();
  }

  /// Sets the kind of connection best at [kind]; null for any.
  Future<void> setBestAt(WorkKind kind, String? family) {
    final next = {...settings.bestAt};
    final mine = family ?? 'any';
    if (mine == (defaultBestAt[kind] ?? 'any')) {
      next.remove(kind.name);
    } else {
      next[kind.name] = mine;
    }
    return update(settings.copyWith(bestAt: next));
  }

  Set<String> get _taken => {for (final e in _engines.engines) e.info.id};

  /// Signs a new account of [kind] in through the browser, under [name];
  /// false when sign-in did not finish or was stopped. Used from the next
  /// message on.
  Future<bool> addAccount(String kind, String name) async {
    final s = setup;
    if (s == null || adding != null) return false;
    adding = kind;
    notifyListeners();
    final made = await s.addAccount(kind, name, taken: _taken);
    if (made != null) await _keep(made);
    adding = null;
    notifyListeners();
    return made != null;
  }

  /// Stops a browser sign-in that is waiting.
  void cancelAdding() => setup?.cancelSignIn();

  /// Who is signed in to the [kind] account in [folder]; null when nobody.
  Future<String?> signedInAs(String kind, String folder) async =>
      await setup?.signedInAs(kind, _expand(folder));

  /// Adds the [kind] account already signed in to [folder], under [name].
  Future<void> addFolder(String kind, String name, String folder) async {
    var id = '$kind-${ConnectionsSetup.slugOf(name)}';
    for (var n = 2; _taken.contains(id); n++) {
      id = '$kind-${ConnectionsSetup.slugOf(name)}-$n';
    }
    await _keep(ConnectionAccount(id: id, kind: kind, name: name, folder: _expand(folder)));
  }

  static String _expand(String folder) {
    final f = folder.trim();
    return f == '~' ? homeDir : (f.startsWith('~/') ? '$homeDir${f.substring(1)}' : f);
  }

  Future<void> _keep(ConnectionAccount a) async {
    await update(settings.copyWith(accounts: [...settings.accounts, a]));
    _engines.add(a);
    chosenAgent = a.id;
    await _checkEngines();
  }

  // Agents that speak the Agent Client Protocol.

  /// The ACP registry; set where the page is made.
  AcpRegistry registry = AcpRegistry();

  /// Where agents Helmy installs are kept.
  Future<String> Function() agentsRoot = () async =>
      '${(await getApplicationSupportDirectory()).path}/agents';

  /// The registry's agents that run here, those already added left out;
  /// null when it could not be reached.
  Future<List<AcpListing>?> listings() async {
    final all = await registry.list();
    if (all == null) return null;
    final have = {for (final a in settings.accounts) ?a.agentId};
    return [
      for (final l in all)
        if (l.runsHere && !have.contains(l.id)) l,
    ];
  }

  /// Installs [listing] and adds it, under [name]. Then checks it starts;
  /// what that found, for the dialog to act on.
  Future<AcpAdded> addAgent(AcpListing listing, {String? name}) async {
    final launch = await AcpRegistry.install(listing, root: await agentsRoot());
    final a = ConnectionAccount(
      id: _agentId(listing.id),
      kind: 'acp',
      name: name?.trim().isNotEmpty ?? false ? name!.trim() : listing.name,
      folder: launch.command.startsWith('/') ? '${await agentsRoot()}/${listing.id}' : '',
      made: launch.command.startsWith('/'),
      command: launch.command,
      args: launch.args,
      agentId: listing.id,
      icon: listing.icon,
    );
    await _keep(a);
    return (account: a, check: await checkAgent(a.id));
  }

  /// Adds an agent started by a command of the user's own: "my-agent --acp".
  Future<AcpAdded> addCommand(String name, String commandLine) async {
    final words = commandLine.trim().split(RegExp(r'\s+'));
    final a = ConnectionAccount(
      id: _agentId(ConnectionsSetup.slugOf(name)),
      kind: 'acp',
      name: name.trim(),
      command: words.first,
      args: words.skip(1).toList(),
    );
    await _keep(a);
    return (account: a, check: await checkAgent(a.id));
  }

  String _agentId(String base) {
    var id = 'acp.$base';
    for (var n = 2; _taken.contains(id); n++) {
      id = 'acp.$base-$n';
    }
    return id;
  }

  /// Whether agent [engineId] starts a session, and if not, why.
  Future<AcpCheck?> checkAgent(String engineId) async {
    final e = _engines.byId(engineId);
    return e is AcpEngine ? await e.check() : null;
  }

  /// Signs agent [engineId] in by [method], one its check gave.
  Future<bool> signInAgent(String engineId, Map<String, Object?> method) async {
    final e = _engines.byId(engineId);
    return e is AcpEngine && await e.signIn(method);
  }

  /// Whether [engineId] is an account added in Settings, so it can go.
  bool canRemove(String engineId) => settings.accounts.any((a) => a.id == engineId);

  /// Whether Helmy made [engineId]'s folder, so removing it removes that.
  bool madeByHelmy(String engineId) => settings.accounts.any((a) => a.id == engineId && a.made);

  /// Removes account [engineId]: Helmy stops using it, and a folder Helmy
  /// made for it goes with its sign-in. A folder the user pointed at stays.
  Future<void> removeAccount(String engineId) async {
    final a = settings.accounts.where((a) => a.id == engineId).firstOrNull;
    if (a == null) return;
    if (a.made && a.kind == 'acp') {
      final dir = Directory(a.folder);
      if (a.folder.isNotEmpty && dir.existsSync()) await dir.delete(recursive: true);
    } else if (a.made) {
      await setup?.removeAccount(a.folder);
    }
    await update(settings.copyWith(accounts: [...settings.accounts]..remove(a)));
    _engines.remove(engineId);
    if (chosenAgent == engineId) chosenAgent = null;
    notifyListeners();
  }

  /// The Chromium-based browsers installed, once asked.
  Future<List<ChromiumBrowser>> chromiumBrowsers() async => await chromium?.installed() ?? const [];

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

  /// Fonts installed here, for Appearance; null until read.
  ({List<String> all, List<String> fixed})? fonts;

  Future<void> loadFonts() async {
    if (fonts != null) return;
    fonts = await _desktop?.fontFamilies();
    notifyListeners();
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
      (label: 'Helmy', path: supportDir, note: 'Chats, conversations, settings'),
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
    _disposed = true;
    _settings.removeListener(notifyListeners);
    _meter.removeListener(notifyListeners);
    super.dispose();
  }

  // Checks and loads started on opening can answer after Settings closed.
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
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
