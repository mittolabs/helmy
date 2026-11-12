import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/connections_setup.dart';
import '../../../data/services/engines/acp/acp_engine.dart';
import '../../../data/services/engines/acp/free_agent.dart';
import '../../../data/services/engines/engine_registry.dart';
import '../../../domain/models/settings.dart';
import '../../../utils/platform.dart';
import '../../import/history_import_view_model.dart';

/// The steps of getting Helmy ready, in order, as T3 Code has its own.
enum OnboardingStep {
  connections('Connections'),
  chats('Chats'),
  folders('Folders');

  const OnboardingStep(this.label);
  final String label;
}

/// Where new chats start, as chosen in the last step: in no project, where
/// the last chat was, or always in [folder] ([mode] fixed).
typedef StartChoice = ({FolderMode mode, String? folder});

/// The first run, after the splash: the AI tools Helmy works through, the
/// conversations already had in them, and where new chats start.
class OnboardingViewModel extends ChangeNotifier {
  new({
    required this._setup,
    required this._settings,
    required this._engines,
    this.import,
    this._installFree,
    this._installAgent,
  });

  /// Installs an agent from the registry by its id (installAgent); null
  /// where they are not offered (a test).
  final Future<ConnectionAccount> Function(String registryId)? _installAgent;

  /// Installs the free connection (installFreeAgent); null where it is not
  /// offered (a test).
  final Future<ConnectionAccount> Function()? _installFree;

  final ConnectionsSetup _setup;
  final SettingsRepository _settings;
  final EngineRegistry _engines;

  /// The conversations to bring in; null where there is nothing to bring
  /// them in with (a test).
  final HistoryImportViewModel? import;

  OnboardingStep step = .connections;

  /// The furthest step reached, so the bar can go back to any before it.
  OnboardingStep reached = .connections;

  void goTo(OnboardingStep to) {
    if (to.index > reached.index) return;
    step = to;
    notifyListeners();
  }

  void next() {
    if (step.index == OnboardingStep.values.length - 1) return;
    step = OnboardingStep.values[step.index + 1];
    if (step.index > reached.index) reached = step;
    // The conversations are looked for once there is somewhere to show them.
    if (step == .chats && import?.projects == null) unawaited(import?.load());
    notifyListeners();
  }

  // Connections.

  /// Each connection and where it stands; null while checking.
  List<ConnectionCheck>? checks;

  /// The connection being installed, signed in or started, and what it is
  /// doing meanwhile.
  String? busy;
  String doing = '';

  /// What went wrong with a connection, by id, in Helmy's words.
  final trouble = <String, String>{};

  /// The kind of account being added ('claude' or 'codex') while its
  /// sign-in runs in the browser.
  String? adding;

  /// The accounts added here, by kind, to say so under the connection.
  final added = <String, int>{};

  /// One found ready and left on: Helmy has something to work through.
  bool get anyReady =>
      (checks?.any((c) => c.state == .ready && used(c.id)) ?? false) ||
      (freeAdded && used(freeAgentId)) ||
      subscriptionAgents.keys.any(
        (id) => agentAdded(id) && !agentTrouble.containsKey(id) && used('acp.$id'),
      );

  // The agents people pay for besides Claude Code and Codex: Cursor, Grok,
  // Antigravity. Each added only when the person asks, then signed in.

  /// Whether they are offered here.
  bool get offersAgents => _installAgent != null;

  /// What each is doing while it is made ready, and what stopped it, by id.
  final agentBusy = <String, String>{};
  final agentTrouble = <String, String>{};

  /// Whether agent [registryId] is in Helmy.
  bool agentAdded(String registryId) =>
      _settings.settings.accounts.any((a) => a.agentId == registryId);

  /// Installs agent [registryId] (once), and signs it in the way it asks for:
  /// its own sign-in, in the browser or a terminal.
  Future<void> addAgent(String registryId) async {
    final install = _installAgent;
    if (install == null || agentBusy.containsKey(registryId)) return;
    final name = subscriptionAgents[registryId] ?? registryId;
    agentBusy[registryId] = 'Installing…';
    agentTrouble.remove(registryId);
    notifyListeners();
    try {
      if (!agentAdded(registryId)) {
        final a = await install(registryId);
        final s = _settings.settings;
        await _settings.save(
          s.copyWith(
            accounts: [...s.accounts, a],
            disabledEngines: {...s.disabledEngines}..remove(a.id),
          ),
        );
        _engines.add(a);
      }
      final e = _engines.byId('acp.$registryId');
      if (e is AcpEngine) {
        agentBusy[registryId] = 'Checking…';
        notifyListeners();
        var check = await e.check();
        if (!check.ready && check.signIns.isNotEmpty) {
          agentBusy[registryId] = 'Finish signing in to $name…';
          notifyListeners();
          await e.signIn(check.signIns.first);
          check = await e.check();
        }
        if (!check.ready) {
          agentTrouble[registryId] =
              check.problem ?? "$name isn't signed in yet. Finish signing in, then check again.";
        }
      }
    } on Object {
      agentTrouble[registryId] =
          "It didn't download: the agent list or its download didn't answer. "
          'Check the internet connection and try again.';
    } finally {
      agentBusy.remove(registryId);
      notifyListeners();
    }
  }

  // The free connection: OpenCode on its free models, no account needed.

  /// Whether the free connection is offered here.
  bool get offersFree => _installFree != null;

  /// Whether it is in Helmy.
  bool get freeAdded => _settings.settings.accounts.any((a) => a.id == freeAgentId);

  /// Being installed; and what stopped it, in Helmy's words.
  bool freeBusy = false;
  String? freeTrouble;

  /// Installs and enables the free connection by default on the first run.
  Future<void> addFree() async {
    final install = _installFree;
    if (install == null || freeBusy || freeAdded) return;
    freeBusy = true;
    freeTrouble = null;
    notifyListeners();
    try {
      final a = await install();
      final s = _settings.settings;
      await _settings.save(
        s.copyWith(
          accounts: [...s.accounts, a],
          disabledEngines: {...s.disabledEngines}..remove(freeAgentId),
        ),
      );
      _engines.add(a);
    } on Object {
      freeTrouble =
          "It didn't download: the agent list or its download didn't answer. "
          'Check the internet connection and try again.';
    } finally {
      freeBusy = false;
      notifyListeners();
    }
  }

  /// Who each ready connection is signed in as, by its id: said on its row,
  /// so it is plain what Helmy would use.
  final who = <String, String>{};

  /// Ready when Helmy first looked: found on this Mac, but left for the
  /// person to enable.
  Set<String>? found;

  Future<void> check() async {
    checks = await _setup.check();
    if (found == null) {
      found = {
        for (final c in checks ?? const <ConnectionCheck>[])
          if (c.state == .ready) c.id,
      };
      final s = _settings.settings;
      await _settings.save(
        s.copyWith(
          disabledEngines: {
            ...s.disabledEngines,
            for (final c in checks ?? const <ConnectionCheck>[]) c.id,
            for (final e in _engines.engines)
              if (e.info.id != freeAgentId) e.info.id,
            for (final a in s.accounts)
              if (a.id != freeAgentId) a.id,
          }..remove(freeAgentId),
        ),
      );
    }
    notifyListeners();
    unawaited(addFree());
    for (final c in checks ?? const <ConnectionCheck>[]) {
      if (c.state != .ready || c.id == 'ollama') continue;
      final name = await _setup.signedInAs(c.id, null);
      if (name != null) who[c.id] = name;
    }
    notifyListeners();
  }

  /// The engines that are connection [id] (Ollama's two as one; the usual
  /// account, not others added).
  List<String> _group(String id) => [
    for (final e in _engines.engines)
      if (ConnectionsSetup.kindOf(e.info.id) == id && (id == 'ollama' || e.info.id == id))
        e.info.id,
  ];

  /// Whether Helmy uses connection [id], as chosen here or in Settings.
  bool used(String id) {
    final off = _settings.settings.disabledEngines;
    final group = _group(id);
    return group.isEmpty ? !off.contains(id) : !group.every(off.contains);
  }

  /// Switches connection [id] on or off for Helmy: it stays installed and
  /// signed in on this Mac either way.
  Future<void> setUsed(String id, bool on) async {
    final s = _settings.settings;
    final group = {..._group(id), if (_group(id).isEmpty) id};
    final off = on ? ({...s.disabledEngines}..removeAll(group)) : {...s.disabledEngines, ...group};
    await _settings.save(s.copyWith(disabledEngines: off));
    notifyListeners();
  }

  /// The one press that moves [c] on: install it, sign it in, or start it.
  Future<void> act(ConnectionCheck c) async {
    if (busy != null) return;
    busy = c.id;
    trouble.remove(c.id);
    doing = switch (c.state) {
      .missing => 'Installing…',
      .signedOut => c.id == 'ollama' ? 'Starting…' : 'Finish signing in, in your browser…',
      .ready => '',
    };
    notifyListeners();
    final ok = switch (c.state) {
      .missing => await _setup.install(c.id),
      .signedOut => await _setup.signIn(c.id),
      .ready => true,
    };
    if (!ok) {
      trouble[c.id] = c.state == .missing
          ? "It didn't install from here. Its install page is open in your browser."
          : c.id == 'ollama'
          ? "It didn't start. Open Ollama, then try again."
          : "Sign-in didn't finish. Try again when ready.";
    }
    checks = await _setup.check();
    if (ok) await setUsed(c.id, true);
    busy = null;
    notifyListeners();
  }

  /// Adds another account of [kind], signed in through the browser; false
  /// when sign-in did not finish.
  Future<bool> addAccount(String kind, {String? name}) async {
    if (adding != null) return false;
    adding = kind;
    notifyListeners();
    // Named as Settings names them, "Codex 2" and on, unless named here.
    final taken = {for (final e in _engines.engines) e.info.id};
    final base = kind == 'claude' ? 'Claude Code' : 'Codex';
    final n = 2 + _settings.settings.accounts.where((a) => a.kind == kind).length;
    final given = name?.trim() ?? '';
    final made = await _setup.addAccount(kind, given.isEmpty ? '$base $n' : given, taken: taken);
    if (made != null) {
      final s = _settings.settings;
      await _settings.save(s.copyWith(accounts: [...s.accounts, made]));
      _engines.add(made);
      added[kind] = (added[kind] ?? 0) + 1;
    }
    adding = null;
    notifyListeners();
    return made != null;
  }

  // Editing a found connection: its name, which installed copy runs, and
  // another account in its place.

  /// The name given to connection [id], or '' for none.
  String nameOf(String id) => _settings.settings.connectionNames[id] ?? '';

  /// [id] shown as Settings will show it: "Claude Code (Personal)".
  String shownName(ConnectionCheck c) =>
      ConnectionsSetup.shownName(c.id, c.name, _settings.settings.connectionNames);

  /// Names connection [id] (each of its engines, for Ollama's two); '' for
  /// none.
  Future<void> setName(String id, String name) async {
    final s = _settings.settings;
    final names = {...s.connectionNames};
    for (final e in {id, ..._group(id)}) {
      if (name.trim().isEmpty) {
        names.remove(e);
      } else {
        names[e] = name.trim();
      }
    }
    await _settings.save(s.copyWith(connectionNames: names));
    notifyListeners();
  }

  /// Where connection [id]'s program is now, chosen or found; null when not.
  Future<String?> programOf(String id) => _setup.programOf(id);

  /// Whether [id]'s program was chosen by hand.
  bool programChosen(String id) => _settings.settings.programs.containsKey(id);

  /// Runs [path] for connection [id]; null to find it again by itself.
  Future<void> setProgram(String id, String? path) async {
    final s = _settings.settings;
    final programs = {...s.programs};
    if (path == null) {
      programs.remove(id);
    } else {
      programs[id] = path;
    }
    await _settings.save(s.copyWith(programs: programs));
    await check();
  }

  /// Another account of [kind] in place of the one found: signed in now,
  /// through the browser, under [name]; the found one is left out. False
  /// when the sign-in did not finish (and nothing changed).
  Future<bool> useAnotherAccount(String kind, String name) async {
    final ok = await addAccount(kind, name: name);
    if (ok) await setUsed(kind, false);
    return ok;
  }

  /// The [kind] account already signed in to [folder] (~/.claude-work), under
  /// [name], in place of the one found. Null when it was taken, else why not.
  Future<String?> useAccountFolder(String kind, String name, String folder) async {
    final who = await _setup.signedInAs(kind, folder);
    if (who == null) {
      return "Nobody is signed in there. Pick the folder an account's sign-in is kept in.";
    }
    final given = name.trim().isEmpty ? folder.split('/').last.replaceFirst('.', '') : name.trim();
    var id = '$kind-${ConnectionsSetup.slugOf(given)}';
    final taken = {for (final e in _engines.engines) e.info.id};
    for (var n = 2; taken.contains(id); n++) {
      id = '$kind-${ConnectionsSetup.slugOf(given)}-$n';
    }
    final account = ConnectionAccount(id: id, kind: kind, name: given, folder: folder);
    final s = _settings.settings;
    await _settings.save(s.copyWith(accounts: [...s.accounts, account]));
    _engines.add(account);
    added[kind] = (added[kind] ?? 0) + 1;
    await setUsed(kind, false);
    return null;
  }

  // Folders.

  /// Where new chats start; in no project, to begin with.
  StartChoice start = (mode: .none, folder: null);

  /// A folder chosen from the file picker, offered beside the suggestions.
  String? picked;

  void choose(StartChoice choice) {
    start = choice;
    notifyListeners();
  }

  void pick(String folder) {
    picked = folder;
    start = (mode: .fixed, folder: folder);
    notifyListeners();
  }

  /// Folders to offer: Home, then those with the most recent conversations,
  /// then one picked by hand.
  List<String> get folders {
    final home = homeDir;
    final out = <String>[if (home.isNotEmpty) home];
    for (final p in import?.projects ?? const []) {
      if (out.length >= 6) break;
      if (!out.contains(p.cwd)) out.add(p.cwd);
    }
    if (picked case final p? when !out.contains(p)) out.add(p);
    return out;
  }

  /// Whether every step is done, and what was set up shows before Helmy
  /// opens.
  bool finished = false;

  /// How many connections are ready, for the summary at the end.
  int get readyCount => checks?.where((c) => c.state == .ready).length ?? 0;

  /// Saves what was chosen, and that the first run is over, and shows what
  /// was set up. Other connections stay off until explicitly enabled.
  Future<void> finish() async {
    finished = true;
    notifyListeners();
    await _settings.save(
      _settings.settings.copyWith(
        setupDone: true,
        tourDue: true,
        folderMode: start.mode,
        fixedFolder: start.folder,
      ),
    );
  }

  /// Ends the first run without choosing anything more.
  Future<void> skip() =>
      _settings.save(_settings.settings.copyWith(setupDone: true, tourDue: true));

  @override
  void dispose() {
    import?.dispose();
    super.dispose();
  }
}
