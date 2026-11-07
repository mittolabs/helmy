import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/connections_setup.dart';
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

/// Where new chats start, as chosen in the last step: where the last chat
/// was ([folder] null), or always in [folder].
typedef StartChoice = ({String? folder});

/// The first run, after the splash: the AI tools Helmy works through, the
/// conversations already had in them, and where new chats start.
class OnboardingViewModel extends ChangeNotifier {
  new({required this._setup, required this._settings, required this._engines, this.import});

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
  bool get anyReady => checks?.any((c) => c.state == .ready && used(c.id)) ?? false;

  /// Who each ready connection is signed in as, by its id: said on its row,
  /// so it is plain what Helmy would use.
  final who = <String, String>{};

  /// Ready when Helmy first looked: found on this Mac, and said so, as Helmy
  /// switched them on without being asked.
  Set<String>? found;

  Future<void> check() async {
    checks = await _setup.check();
    found ??= {
      for (final c in checks ?? const <ConnectionCheck>[])
        if (c.state == .ready) c.id,
    };
    notifyListeners();
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

  /// Whether Helmy uses connection [id]: found ready, it is, until switched
  /// off here (or removed in Settings).
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
    busy = null;
    notifyListeners();
  }

  /// Adds another account of [kind], signed in through the browser; false
  /// when sign-in did not finish.
  Future<bool> addAccount(String kind) async {
    if (adding != null) return false;
    adding = kind;
    notifyListeners();
    // Named as Settings names them, "Codex 2" and on; changed there.
    final taken = {for (final e in _engines.engines) e.info.id};
    final base = kind == 'claude' ? 'Claude Code' : 'Codex';
    final n = 2 + _settings.settings.accounts.where((a) => a.kind == kind).length;
    final made = await _setup.addAccount(kind, '$base $n', taken: taken);
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

  // Folders.

  /// Where new chats start; where the last chat was, to begin with.
  StartChoice start = (folder: null);

  /// A folder chosen from the file picker, offered beside the suggestions.
  String? picked;

  void choose(StartChoice choice) {
    start = choice;
    notifyListeners();
  }

  void pick(String folder) {
    picked = folder;
    start = (folder: folder);
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
  /// was set up. Connections that are not ready are left on: Helmy uses
  /// each once it is.
  Future<void> finish() async {
    finished = true;
    notifyListeners();
    await _settings.save(
      _settings.settings.copyWith(
        setupDone: true,
        folderMode: start.folder == null ? FolderMode.last : FolderMode.fixed,
        fixedFolder: start.folder,
      ),
    );
  }

  /// Ends the first run without choosing anything more.
  Future<void> skip() => _settings.save(_settings.settings.copyWith(setupDone: true));

  @override
  void dispose() {
    import?.dispose();
    super.dispose();
  }
}
