import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../data/repositories/attention_repository.dart';
import '../../../data/repositories/conversation_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/models/permission_rule.dart';
import '../../../data/services/engines/agent_engine.dart';
import '../../../domain/models/chat_item.dart';
import '../../../domain/models/engine.dart';
import '../../../domain/models/session.dart';
import '../../../utils/command.dart';
import '../../../utils/starters.dart';
import '../../../data/services/man_pages.dart';
import '../../../data/services/snapshots.dart';
import '../../../utils/diffs.dart';
import '../../../utils/project_files.dart';
import '../../../utils/result.dart';
import '../../../utils/transcript_markdown.dart';
import '../../../utils/platform.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/desktop_service.dart';
import '../../../data/services/editors.dart';
import '../../../data/services/project_actions.dart';
import '../../../domain/models/project_action.dart';
import '../../../data/services/watch_service.dart';
import '../../../data/services/fixes.dart';
import '../../../domain/problem.dart';
import '../../core/file_actions.dart';
import '../../../data/services/devices.dart';
import 'device_view_model.dart';
import '../../../data/services/browser/browser_host.dart';
import '../../../data/services/chromium/chromium_service.dart';
import '../../../domain/models/settings.dart';

/// What can open beside the conversation. A new kind (a browser, a terminal)
/// joins here with the condition under which it is offered.
enum SidePanel { changes, background, preview, terminal, ship, device }

/// One tab in the panel beside the conversation: what it shows, and for a
/// browser tab, where it is.
class PanelTab {
  PanelTab(this.kind, {this.url, this.action}) : id = '${kind.name}-${_next++}';
  static var _next = 0;
  final String id;
  final SidePanel kind;

  /// A browser tab's address.
  String? url;

  /// A browser tab's page: its title and the address of its icon, once read.
  String? title;
  String? icon;

  /// A terminal tab running a project action: which, how many times it has
  /// been started (each start runs it afresh), and how it last ended (null
  /// while it runs).
  ProjectAction? action;
  int runs = 1;
  int? exitCode;
}

class ChatViewModel extends ChangeNotifier implements MediaActions {
  new({
    required this.sessionId,
    required this._sessions,
    required this._conversations,
    this._attention,
    this._settings,
    this._projects,
    this._desktop,
    this._watch,
    this._fixes,
    DeviceService? devices,
    this.chromium,
    this.browser,
    this._editors,
  }) : device = devices == null ? null : DeviceViewModel(devices) {
    _attention?.viewing = sessionId;
    // The agent's browser_open opens the page here, in the Preview panel.
    browser?.opener(sessionId, preview);
    // The agent's device tools show the device here, in the Device panel.
    if (device != null) browser?.deviceOpener(sessionId, () => show(.device));
    _sessions.addListener(notifyListeners);
    _sessions.addListener(_findRepoLater);
    _conversations.addListener(notifyListeners);
    _conversations.addListener(_onConversation);
    send = Command1(_send);
    _conversations.load(sessionId).then((_) => countChanges());
    unawaited(_findRepo());
  }

  void _findRepoLater() => unawaited(_findRepo());

  /// Whether the session's folder is in a git repository, so its work can
  /// go on to a pull request; asked once, and again when the folder changes.
  bool inRepo = false;

  /// Whether the session's folder holds an iOS or Android app, so the
  /// Device panel is offered.
  bool mobile = false;

  /// The Device panel's simulator or emulator; null where there are none.
  final DeviceViewModel? device;
  String? _askedFor;

  Future<void> _findRepo() async {
    final cwd = session?.cwd;
    if (cwd == null || cwd == _askedFor) return;
    // The session moved into its own copy while open here (its first
    // message made it): what is to run in each new copy runs there now.
    final intoCopy = _askedFor != null && (session?.ownCopy ?? false);
    _askedFor = cwd;
    refreshActions();
    if (intoCopy) {
      for (final a in actions.where((a) => a.onNewCopy)) {
        run(a, focus: false);
      }
    }
    unawaited(_findEditors(cwd));
    final found = await _projects?.repoOf(cwd) != null;
    final mobile = isMobileProject(cwd);
    if (mobile != this.mobile) {
      this.mobile = mobile;
      notifyListeners();
    }
    if (found != inRepo) {
      inRepo = found;
      notifyListeners();
    }
  }

  final String sessionId;
  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final AttentionRepository? _attention;
  final SettingsRepository? _settings;
  final EditorService? _editors;

  late final Command1<void, String> send;

  Session? get session => _sessions.byId(sessionId);
  Conversation get _c => _conversations.of(sessionId);
  List<ChatItem> get items => _c.items;
  bool get busy => _c.busy;

  /// Only the model on this Mac could answer the last message sent.
  bool get onlyThisMac => _conversations.onlyThisMac ?? false;
  bool get thinking => _c.thinking;

  // Composing: commands, files, history, the queue, the context.

  Future<List<SlashCommand>>? _commands;
  Future<List<String>>? _files;

  /// Every engine's slash commands for this session's folder.
  Future<List<SlashCommand>> commands() {
    final s = session;
    if (s == null) return Future.value(const []);
    return _commands ??= _conversations.commands(s);
  }

  /// The session folder's files, read again when [fresh].
  Future<List<String>> files({bool fresh = false}) {
    final s = session;
    if (s == null) return Future.value(const []);
    if (fresh || _files == null) _files = projectFiles(s.cwd);
    return _files!;
  }

  Future<List<Starter>>? _starters;

  /// What an empty session suggests, from what its folder holds.
  Future<List<Starter>> starters() {
    final s = session;
    if (s == null) return Future.value(const []);
    return _starters ??= readFolderFacts(s.cwd).then(startersFor);
  }

  /// What you sent before, oldest first, for the up arrow.
  List<String> get history => [
    for (final i in items)
      if (i is UserMessage && i.text.isNotEmpty) i.text,
  ];

  /// Messages waiting for the agent to be free.
  List<Queued> get queue => _c.queue;

  void unqueue(int index) => _conversations.unqueue(sessionId, index);

  /// How full the context is, as the engine that answered last reported.
  ContextUse? get context => _c.context;

  Future<Result<void>> compact() async {
    final s = session;
    if (s == null) return .error(Exception('No session'));
    return _conversations.compact(s);
  }

  // What the conversation's widgets may do, through the services here.
  final ProjectRepository? _projects;
  final DesktopService? _desktop;
  final WatchService? _watch;
  final Fixes? _fixes;

  @override
  Future<void> open(String where) async => _desktop?.open(where);

  @override
  Future<void> reveal(String path) async => _desktop?.reveal(path);

  @override
  Future<bool> copyImage(String path) async => await _desktop?.copyImage(path) ?? false;

  @override
  Future<String?> documentPicture(String path) async => _desktop?.documentPicture(path);

  /// Chromium browsers for Preview, when this computer can run them.
  final ChromiumService? chromium;

  /// Where the session's agent finds the page in its Preview panel.
  final BrowserHost? browser;

  /// What draws pages in Preview.
  PreviewEngine get previewEngine => _settings?.settings.previewWith ?? .system;

  /// The Chromium browser chosen in settings; null lets Helmy pick.
  String? get chromiumBrowser => _settings?.settings.chromiumBrowser;

  Future<void> setPreviewEngine(PreviewEngine engine, {String? browser}) async {
    final s = _settings;
    if (s == null) return;
    await s.save(s.settings.copyWith(previewWith: engine, chromiumBrowser: browser));
    notifyListeners();
  }

  /// Saves a picture of the built-in browser's page to [path]; null where it cannot.
  Future<String?> webSnapshot(String path) async => _desktop?.webSnapshot(path);

  /// Does [action] to the page in the Preview panel; false where it cannot.
  Future<bool> webPage(String action, [Map<String, Object?> args = const {}]) async =>
      await _desktop?.webPage(action, args) ?? false;

  @override
  Future<List<Frame>> frames(String path, {int count = 40, int width = 240}) async =>
      await _watch?.frames(path, count: count, width: width) ?? const [];

  /// Does [fix] outside the conversation (signing in, starting the model
  /// here, a system pane); true when it worked.
  Future<bool> applyFix(Fix fix, {String? engineId}) async {
    final ok = await _fixes?.apply(fix, engineId: engineId) ?? false;
    if (fix == .installDeviceInput) await device?.checkTouch();
    return ok;
  }

  /// A picture on the clipboard, attached; false when there is none.
  Future<bool> pasteImage() async {
    final desktop = _desktop;
    if (desktop == null) return false;
    final dir = Directory('${Directory.systemTemp.path}/helmy-pasted')..createSync(recursive: true);
    final path = await desktop.pasteImage(
      '${dir.path}/pasted-${DateTime.now().millisecondsSinceEpoch}.png',
    );
    if (path == null) return false;
    attach([path]);
    return true;
  }

  // Changes made in the folder.

  final _snapshots = Snapshots();

  // Panels beside the conversation, offered only while they have something
  // to show for this session.

  /// The tabs in the panel beside the conversation, in their order.
  final tabs = <PanelTab>[];

  /// The tab showing; null when there are none.
  PanelTab? active;

  /// Whether the panel shows. Its tabs stay while it is hidden.
  bool panelOpen = false;

  /// What the panel shows now; null when it is hidden or has no tabs.
  SidePanel? get panel => panelOpen ? active?.kind : null;

  /// How wide the panel is, as last dragged.
  double panelWidth = 380;

  bool isOpen(SidePanel p) => panel == p;

  bool get changesOpen => isOpen(.changes);

  /// Shows [tab] in the panel.
  void focus(PanelTab tab) {
    active = tab;
    panelOpen = true;
    notifyListeners();
  }

  /// A tab of [kind] shown: the open one, or a new one.
  PanelTab show(SidePanel kind) {
    final tab =
        (active?.kind == kind ? active : null) ??
        tabs.where((t) => t.kind == kind).firstOrNull ??
        add(kind, focus: false);
    focus(tab);
    return tab;
  }

  /// A new tab of [kind], shown unless [focus] is false.
  PanelTab add(SidePanel kind, {String? url, bool focus = true}) {
    final tab = PanelTab(kind, url: url);
    final at = active == null ? tabs.length : tabs.indexOf(active!) + 1;
    tabs.insert(at, tab);
    if (focus) this.focus(tab);
    return tab;
  }

  /// Closes [tab]; the one beside it shows, and with none left the panel hides.
  void closeTab(PanelTab tab) {
    final at = tabs.indexOf(tab);
    if (at < 0) return;
    tabs.removeAt(at);
    if (active == tab) active = tabs.isEmpty ? null : tabs[at.clamp(0, tabs.length - 1)];
    if (tabs.isEmpty) {
      panelOpen = false;
      panelExpanded = false;
    }
    notifyListeners();
  }

  /// Something a tab shows changed (a page's title or icon): its name redrawn.
  void panelChanged() => notifyListeners();

  /// The panel shown or hidden, its tabs kept.
  void togglePanel() {
    panelOpen = !panelOpen;
    if (!panelOpen) panelExpanded = false;
    notifyListeners();
  }

  /// A tab of [p] shown, or the panel hidden when it is already what shows.
  void toggle(SidePanel p) {
    if (panel == p) {
      togglePanel();
    } else {
      show(p);
    }
  }

  /// The open panel over the whole page, the conversation set aside.
  bool panelExpanded = false;

  void toggleExpanded() {
    panelExpanded = panel != null && !panelExpanded;
    notifyListeners();
  }

  /// Hides the panel; its tabs stay.
  void closePanel() {
    panelOpen = false;
    panelExpanded = false;
    notifyListeners();
  }

  void resize(double width) {
    panelWidth = width.clamp(260.0, 900.0);
    notifyListeners();
  }

  void toggleChanges() => toggle(.changes);

  /// How many files the session has changed, once counted: again whenever a
  /// turn ends.
  int? changedFiles;
  bool _wasBusy = false;

  Future<void> countChanges() async {
    final git = await changesIn(null);
    final n =
        git?.length ??
        {
          for (final c in reportedIn(null))
            for (final d in diffsOf(c)) d.path,
        }.length;
    if (n != changedFiles) {
      changedFiles = n;
      notifyListeners();
    }
  }

  void _onConversation() {
    if (_wasBusy && !busy) countChanges();
    _wasBusy = busy;
    _findServer();
  }

  // Project actions: run, test, build, as the project's files say, and those
  // the user added; each runs in a terminal tab of its own.

  /// The project's actions: those found in its files, then the user's own.
  List<ProjectAction> actions = const [];

  /// The action run last here, which ⌘R runs again.
  ProjectAction? lastAction;

  /// The folder whose settings hold the user's own actions: the repository
  /// (shared by its copies), else the session's folder.
  String? get _actionsHome => session?.repo ?? session?.cwd;

  /// Reads the actions again (the project's files may have changed).
  void refreshActions() {
    final cwd = session?.cwd;
    if (cwd == null) return;
    final home = _actionsHome!;
    final own = _settings?.settings.project(home).actions ?? const <ProjectAction>[];
    final next = [...findActions(cwd), ...own];
    if (listEquals(next, actions)) return;
    actions = next;
    notifyListeners();
  }

  /// Runs [action] in the session's folder, in a terminal tab of its own:
  /// the one it ran in before, afresh, if that is still open.
  void run(ProjectAction action, {bool focus = true}) {
    lastAction = action;
    final tab = tabs.where((t) => t.action?.key == action.key).firstOrNull;
    if (tab != null) {
      tab
        ..runs += 1
        ..exitCode = null;
      if (focus) {
        this.focus(tab);
      } else {
        notifyListeners();
      }
      return;
    }
    final made = PanelTab(.terminal, action: action);
    final at = active == null ? tabs.length : tabs.indexOf(active!) + 1;
    tabs.insert(at, made);
    if (focus || active == null) {
      this.focus(made);
    } else {
      notifyListeners();
    }
  }

  /// What an action's terminal said: a local address in it opens in the
  /// Preview panel, once.
  void actionOutput(PanelTab tab, String text) {
    if (!webViewHere) return;
    // Output comes in pieces, and an address can be split between two: the
    // end of what came before is read with what comes now.
    final seen = (_tails[tab.id] ?? '') + text;
    _tails[tab.id] = seen.length > 400 ? seen.substring(seen.length - 400) : seen;
    final url = localServerInText(seen);
    if (url == null || !_servers.add(url)) return;
    preview(url);
  }

  final _tails = <String, String>{};

  /// An action's run ended with [code].
  void actionEnded(PanelTab tab, int code) {
    tab.exitCode = code;
    notifyListeners();
  }

  /// Saves [action] as one of the user's own, in place of [replacing].
  Future<void> saveAction(ProjectAction action, {ProjectAction? replacing}) async {
    final s = _settings, home = _actionsHome;
    if (s == null || home == null) return;
    final project = s.settings.project(home);
    final list = [...project.actions];
    final at = replacing == null ? -1 : list.indexWhere((a) => a.key == replacing.key);
    if (at >= 0) {
      list[at] = action;
    } else {
      list.add(action);
    }
    await s.save(
      s.settings.copyWith(
        projects: {
          ...s.settings.projects,
          home: project.copyWith(actions: list),
        },
      ),
    );
    refreshActions();
  }

  /// Removes one of the user's own actions.
  Future<void> removeAction(ProjectAction action) async {
    final s = _settings, home = _actionsHome;
    if (s == null || home == null) return;
    final project = s.settings.project(home);
    await s.save(
      s.settings.copyWith(
        projects: {
          ...s.settings.projects,
          home: project.copyWith(
            actions: [
              for (final a in project.actions)
                if (a.key != action.key) a,
            ],
          ),
        },
      ),
    );
    if (lastAction?.key == action.key) lastAction = null;
    refreshActions();
  }

  // Opening the project in an editor.

  /// The apps this project can open in, editors first.
  List<Editor> editors = const [];

  /// The one it opens in: as chosen last, else the editor used most recently.
  Editor? get editor => defaultEditor(editors, _settings?.settings.editor);

  Future<void> _findEditors(String cwd) async {
    final found = await _editors?.installed() ?? const <Editor>[];
    editors = editorsFor(cwd, found);
    notifyListeners();
  }

  /// Opens the project in [app] (else the usual one), which becomes the
  /// usual one; false when it could not open.
  Future<bool> openIn([Editor? app]) async {
    final e = app ?? editor;
    final folder = session?.cwd;
    if (e == null || folder == null || _editors == null) return false;
    if (app != null && app.id != _settings?.settings.editor) {
      final s = _settings;
      if (s != null) await s.save(s.settings.copyWith(editor: app.id));
      notifyListeners();
    }
    return _editors.open(e, folder);
  }

  /// Local servers already offered, so each opens once.
  final Set<String> _servers = {};

  /// A server on this computer that a step started (a dev server printing
  /// "http://localhost:3000"): opened in Preview, the first time it shows.
  void _findServer() {
    if (!webViewHere) return;
    final url = localServerIn(items);
    if (url == null || !_servers.add(url)) return;
    preview(url);
  }

  /// Steps an agent moved to the background, newest first.
  List<ToolCall> get backgroundSteps {
    final out = <ToolCall>[];
    void walk(Iterable<ToolCall> calls) {
      for (final c in calls) {
        if (c.background != null) out.add(c);
        walk(c.children);
      }
    }

    walk(items.whereType<ToolCall>());
    return out.reversed.toList();
  }

  /// What the Preview panel shows: a web page, a running app on this Mac
  /// (http://localhost:3000), or a file such as a PDF. Set when an answer
  /// points at one and you open it.
  String? get previewUrl =>
      (active?.kind == .preview ? active : tabs.where((t) => t.kind == .preview).lastOrNull)?.url;

  /// A new session from this one, up to the answer that ends at item
  /// [upTo]: the same folder and permissions, the conversation so far, and
  /// a note of where it came from. Its id, or null when it could not be made.
  Future<String?> fork(int upTo) async {
    final s = session;
    if (s == null) return null;
    final made = await _sessions.create(cwd: s.cwd, level: s.level, title: '${s.title} fork');
    if (made case Ok(:final value)) {
      await _conversations.copy(s.id, value.id, upTo: upTo, note: 'Forked from "${s.title}"');
      return value.id;
    }
    return null;
  }

  /// An attached file shown: beside the conversation where there is a web
  /// view (pictures, PDFs and text show there), else in its own app.
  void showFile(String path) {
    if (!File(path).existsSync()) return;
    if (webViewHere) {
      add(.preview, url: Uri.file(path).toString());
    } else {
      unawaited(open(path));
    }
  }

  /// Shows [url] in a browser tab beside the conversation: the one showing,
  /// else the last one, else a new one.
  @override
  void preview(String url) {
    final tab =
        (active?.kind == .preview ? active : null) ??
        tabs.where((t) => t.kind == .preview).lastOrNull ??
        add(.preview, focus: false);
    tab.url = url;
    focus(tab);
  }

  /// The kinds of tab that can be added now, in the menu's order.
  List<SidePanel> get addable => [
    // (Only where there is a web view to show it in.)
    if (webViewHere) .preview,
    .terminal,
    .changes,
    if (inRepo) .ship,
    if (device != null) .device,
    if (backgroundSteps.isNotEmpty) .background,
  ];

  /// What wants the user while the panel is hidden, for the header to say:
  /// changes made, work running in the background.
  List<SidePanel> get notices => panelOpen
      ? const []
      : [
          if ((changedFiles ?? 0) > 0) .changes,
          if (backgroundSteps.any((c) => c.background!.status == .running)) .background,
        ];

  /// What the Changes panel shows: the whole session (null), or the turn
  /// that the message at this index started.
  int? changesScope;

  void showChanges({int? from}) {
    changesScope = from;
    show(.changes);
  }

  void setChangesScope(int? from) {
    changesScope = from;
    notifyListeners();
  }

  /// Messages of yours with a checkpoint: the turns whose own changes can be shown.
  List<int> get turnsWithChanges => [
    for (final (i, item) in items.indexed)
      if (item is UserMessage && item.checkpoint != null) i,
  ];

  /// The checkpoints a turn's work lies between: before its message, and
  /// before the next message (null when it is the latest, so up to now).
  (Snapshot, Snapshot?)? _turnBounds(int index) {
    if (index >= items.length) return null;
    final at = items[index];
    if (at is! UserMessage || at.checkpoint == null) return null;
    for (final i in items.skip(index + 1)) {
      if (i is UserMessage && i.checkpoint != null) return (at.checkpoint!, i.checkpoint);
    }
    return (at.checkpoint!, null);
  }

  /// The files changed, in the scope chosen: since the session started, or by
  /// one turn alone. Null when the folder is not a git repository and only
  /// the agents' own edits are known ([reportedChanges]).
  Future<List<FileChange>?> changes() => changesIn(changesScope);

  /// The files changed in [scope]: the whole session when null.
  Future<List<FileChange>?> changesIn(int? scope) async {
    final s = session;
    if (s == null) return null;
    if (scope != null) {
      final bounds = _turnBounds(scope);
      if (bounds == null) return null;
      final (from, to) = bounds;
      return to == null
          ? _snapshots.changes(s.cwd, from)
          : _snapshots.changesBetween(s.cwd, from, to);
    }
    final base = s.baseline;
    if (base == null) return null;
    return _snapshots.changes(s.cwd, base);
  }

  Future<String> diffOf(String path) async {
    final s = session;
    if (s == null) return '';
    final scope = changesScope;
    if (scope != null) {
      final bounds = _turnBounds(scope);
      if (bounds == null) return '';
      final (from, to) = bounds;
      return to == null
          ? _snapshots.diff(s.cwd, from, path)
          : _snapshots.diffBetween(s.cwd, from, to, path);
    }
    if (s.baseline == null) return '';
    return _snapshots.diff(s.cwd, s.baseline!, path);
  }

  /// The edits the agents reported, for a folder git does not track: in the
  /// scope chosen.
  List<ToolCall> get reportedChanges => reportedIn(changesScope);

  /// The agents' reported edits in [scope]: the whole session when null.
  List<ToolCall> reportedIn(int? scope) {
    var start = 0, end = items.length;
    if (scope != null && scope < items.length) {
      start = scope;
      final next = items.indexed.skip(scope + 1).where((e) => e.$2 is UserMessage).firstOrNull;
      if (next != null) end = next.$1;
    }
    return [
      for (final i in items.sublist(start, end))
        if (i is ToolCall && !i.isError && diffsOf(i).isNotEmpty) i,
    ];
  }

  /// Whether files can be put back as they were before the message at [index].
  bool canUndoFrom(int index) =>
      items[index] is UserMessage && (items[index] as UserMessage).checkpoint != null;

  /// The files changed since the message at [index] went.
  Future<List<FileChange>> changesFrom(int index) async {
    final s = session;
    final cp = (items[index] as UserMessage).checkpoint;
    if (s == null || cp == null) return const [];
    return _snapshots.changes(s.cwd, cp);
  }

  /// Puts every file changed since the message at [index] back as it was then.
  Future<int> undoFrom(int index) async {
    final s = session;
    final cp = (items[index] as UserMessage).checkpoint;
    if (s == null || cp == null || busy) return 0;
    final changed = await _snapshots.changes(s.cwd, cp);
    await _snapshots.restore(s.cwd, cp, [for (final c in changed) c.path]);
    notifyListeners();
    return changed.length;
  }

  /// Files waiting to go with the next message, by path.
  final List<String> attachments = [];

  /// What the next message needs beyond what its words say: a picture made,
  /// when it refines one.
  final Set<Capability> pendingNeeds = {};

  /// Counts requests to put the cursor in the message box.
  final focusRequests = ValueNotifier(0);

  /// Starts a message that changes the picture at [path]: it goes with the
  /// message, and the message goes to an agent that makes pictures.
  void refine(String path) {
    attach([path]);
    pendingNeeds.add(Capability.imageGeneration);
    focusRequests.value++;
    notifyListeners();
  }

  /// Asks for another take on the picture at [path] straight away.
  Future<Result<void>> variation(String path) async {
    final s = session;
    if (s == null || busy) return .error(Exception('Still working'));
    return _conversations.send(
      s,
      'Make a variation of this image: same subject and style, a fresh take.',
      attachments: [path],
      needs: {Capability.imageGeneration},
    );
  }

  /// A device's screen as it is now, attached to the message.
  Future<void> attachScreen(Uint8List bytes) async {
    final dir = Directory('${Directory.systemTemp.path}/helmy-pasted')..createSync(recursive: true);
    final png = bytes.length > 3 && bytes[1] == 0x50;
    final file = File(
      '${dir.path}/device-${DateTime.now().millisecondsSinceEpoch}.${png ? 'png' : 'jpg'}',
    );
    await file.writeAsBytes(bytes);
    attach([file.path]);
  }

  void attach(Iterable<String> paths) {
    for (final p in paths) {
      if (!attachments.contains(p)) attachments.add(p);
    }
    notifyListeners();
  }

  void detach(String path) {
    attachments.remove(path);
    if (attachments.isEmpty) pendingNeeds.clear();
    notifyListeners();
  }

  Future<Result<void>> _send(String text) async {
    final s = session;
    if (s == null || (text.trim().isEmpty && attachments.isEmpty)) {
      return .error(Exception('Nothing to send'));
    }
    final files = [...attachments];
    final needs = {...pendingNeeds};
    attachments.clear();
    pendingNeeds.clear();
    return _conversations.send(s, text.trim(), attachments: files, needs: needs);
  }

  void interrupt() => _conversations.interrupt(sessionId);

  /// Sends the waiting message at [index] now, redirecting the agent.
  void steer(int index) => _conversations.steer(sessionId, index);

  /// Sends [text] now even while the agent works: it stops what it is doing
  /// and takes this up instead.
  Future<void> sendNow(String text) async {
    if (!busy) {
      await send.execute(text);
      return;
    }
    await _send(text);
    if (queue.isNotEmpty) steer(queue.length - 1);
  }

  void allow(PermissionPrompt p, {bool forSession = false}) => _conversations.answerPermission(
    sessionId,
    p,
    forSession ? PermissionAnswer.allowForSession : PermissionAnswer.allow,
  );

  /// The lasting rule "always allow" would make for [p], or null.
  PermissionRule? ruleFor(PermissionPrompt p) {
    final s = session;
    return s == null ? null : PermissionRule.from(p, s.cwd);
  }

  /// Allows [p] and keeps [rule] in settings, so its like is never asked again.
  Future<void> allowAlways(PermissionPrompt p, PermissionRule rule) async {
    final s = _settings?.settings;
    if (s != null && !s.rules.any((r) => r.kind == rule.kind && r.prefix == rule.prefix)) {
      await _settings!.save(s.copyWith(rules: [...s.rules, rule]));
    }
    allow(p);
  }

  /// Approves a plan: the agent goes ahead, asking first as usual.
  Future<void> approvePlan(PermissionPrompt p) async {
    allow(p);
    if (session?.level == .readOnly) await setLevel(.ask);
  }

  void deny(PermissionPrompt p) => _conversations.answerPermission(sessionId, p, .deny);

  void choose(PermissionPrompt p, String question, String answer) {
    p.answers[question] = answer;
    notifyListeners();
  }

  void submitAnswers(PermissionPrompt p) => _conversations.answerQuestion(sessionId, p);

  Future<void> setLevel(PermissionLevel level) async {
    final s = session;
    if (s == null || s.level == level) return;
    await _sessions.save(s.copyWith(level: level));
    await _conversations.setLevel(sessionId, level);
  }

  // Editing and retrying.

  /// The user message being edited in place, by its index in [items].
  int? editing;

  void startEdit(int index) {
    if (busy) return;
    editing = index;
    notifyListeners();
  }

  void cancelEdit() {
    editing = null;
    notifyListeners();
  }

  /// Sends [text] in place of the message at [index], taking back what came after.
  Future<Result<void>> resend(int index, String text) async {
    final s = session;
    editing = null;
    if (s == null || text.trim().isEmpty) return .error(Exception('Nothing to send'));
    return _conversations.rewind(s, index, text.trim());
  }

  /// The versions of the conversation held by the message at [index], when
  /// that message was edited.
  Branches? branchesAt(int index) =>
      index < items.length ? (items[index] as UserMessage?)?.branches : null;

  /// Each version from [index] on, for choosing between them: how it starts
  /// and how many messages of yours it has.
  List<({String first, int asks})> versionsAt(int index) {
    final b = branchesAt(index);
    if (b == null) return const [];
    return [
      for (final tail in [for (var i = 0; i < b.length; i++) b.tails[i] ?? items.sublist(index)])
        (
          first: tail.whereType<UserMessage>().firstOrNull?.text ?? '',
          asks: tail.whereType<UserMessage>().length,
        ),
    ];
  }

  /// Shows version [to] of the conversation from [index] on.
  Future<Result<void>> showBranch(int index, int to) async {
    final s = session;
    if (s == null) return .error(Exception('No session'));
    editing = null;
    return _conversations.showBranch(s, index, to);
  }

  final Map<String, Future<List<ManPart>>> _manual = {};

  /// [command] explained from the Mac's manual pages: free and offline.
  Future<List<ManPart>> manual(String command) =>
      _manual[command] ??= explainFromManual(PermissionRule.plainCommand(command));

  /// [call]'s command in plain words, from an agent; kept on the step.
  Future<Result<String>> explain(ToolCall call) => _conversations.explain(sessionId, call);

  /// Stops work an agent left running in the background.
  void stopTask(String taskId) => _conversations.stopTask(sessionId, taskId);

  /// The index of the user's last message, whose answer Retry asks for again.
  int? get lastAsk {
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i] is UserMessage) return i;
    }
    return null;
  }

  Future<Result<void>> retry() async {
    final i = lastAsk;
    if (i == null) return .error(Exception('Nothing to retry'));
    return resend(i, (items[i] as UserMessage).text);
  }

  // Copying, saving and the session itself.

  String answerAfter(int index) => answerText(items, index);

  String get markdown => transcriptMarkdown(session?.title ?? 'Conversation', items);

  Future<void> copy(String text) => Clipboard.setData(ClipboardData(text: text));

  Future<Result<void>> saveMarkdown(String path) async {
    try {
      await File(path).writeAsString(markdown);
      return const .ok(null);
    } on Exception catch (e) {
      return .error(e);
    }
  }

  Future<void> rename(String title) async {
    final s = session;
    final t = title.trim();
    if (s == null || t.isEmpty) return;
    await _sessions.save(s.copyWith(title: t));
  }

  Future<void> delete() async {
    await _conversations.forget(sessionId);
    await _sessions.delete(sessionId);
  }

  /// Moves the session to another folder. The engines' threads belong to the
  /// old folder, so each starts a new one there and is handed the conversation.
  Future<void> changeFolder(String cwd) async {
    final s = session;
    if (s == null || s.cwd == cwd || busy) return;
    await _conversations.stop(sessionId);
    // Before its first message, a session takes on its new project's level.
    final fresh = !items.any((i) => i is UserMessage);
    final level = fresh ? await _projects?.levelFor(cwd) : null;
    await _sessions.save(s.copyWith(cwd: cwd, threads: const {}, level: level));
  }

  @override
  void dispose() {
    _attention?.viewing = null;
    browser?.opener(sessionId, null);
    browser?.deviceOpener(sessionId, null);
    device?.dispose();
    focusRequests.dispose();
    _sessions.removeListener(notifyListeners);
    _sessions.removeListener(_findRepoLater);
    _conversations.removeListener(notifyListeners);
    _conversations.removeListener(_onConversation);
    super.dispose();
  }
}

/// The last address on this computer in [text] (a terminal's output, its
/// colors taken out); null when there is none.
String? localServerInText(String text) {
  final plain = text.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
  final found = _local.allMatches(plain).lastOrNull?[0];
  return found?.replaceFirst('0.0.0.0', 'localhost');
}

final _local = RegExp(
  r'''https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0)(?::\d+)?(?:/[^\s'"`<>)\]]*)?''',
);

/// The newest address on this computer that a step's output gave, such as
/// a dev server's "Local: http://localhost:5173/"; null when there is none.
String? localServerIn(List<ChatItem> items) {
  final local = RegExp(
    r'''https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0)(?::\d+)?(?:/[^\s'"`<>)\]]*)?''',
  );
  for (final call in items.reversed.whereType<ToolCall>()) {
    final out = call.result ?? '';
    final found = local.allMatches(out).lastOrNull?[0];
    if (found != null) return found.replaceFirst('0.0.0.0', 'localhost');
  }
  return null;
}

/// Whether [folder] holds an iOS or Android app: an Xcode project, a
/// Flutter or React Native app's ios/ and android/ folders, or Gradle's
/// Android app module.
bool isMobileProject(String folder) {
  final dir = Directory(folder);
  if (!dir.existsSync()) return false;
  if (Directory('$folder/ios').existsSync() || Directory('$folder/android').existsSync()) {
    return true;
  }
  if (File('$folder/app/src/main/AndroidManifest.xml').existsSync()) return true;
  try {
    return dir.listSync().any(
      (e) => e.path.endsWith('.xcodeproj') || e.path.endsWith('.xcworkspace'),
    );
  } on FileSystemException {
    return false;
  }
}
