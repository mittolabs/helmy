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
import '../../../data/services/engines/attachments.dart';
import '../../../domain/models/session.dart';
import '../../../utils/command.dart';
import '../../../utils/starters.dart';
import '../../../data/services/man_pages.dart';
import '../../../data/services/snapshots.dart';
import '../../../utils/diffs.dart';
import '../../../utils/format.dart';
import '../../../utils/project_files.dart';
import '../../../utils/result.dart';
import '../../../utils/transcript_markdown.dart';
import '../../../utils/platform.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/desktop_service.dart';
import '../../../data/services/editors.dart';
import '../widgets/file_popup.dart' show EditorChoice;
import '../../../data/services/window_snapshots.dart';
import '../../../data/repositories/chat_repository.dart';
import '../../../data/services/turn_log.dart';
import '../../../domain/filing.dart';
import '../../../data/services/project_actions.dart';
import '../../../domain/models/project_action.dart';
import '../../../data/services/watch_service.dart';
import '../../../data/services/fixes.dart';
import '../../../domain/problem.dart';
import '../../core/file_actions.dart';
import '../../../data/services/devices.dart';
import '../../../data/services/mac/mac_control.dart';
import 'device_view_model.dart';
import '../../../data/services/browser/browser_host.dart';
import '../../../data/services/chromium/chromium_service.dart';
import '../../../domain/models/settings.dart';
import '../../../data/services/webhooks.dart';

/// What can open beside the conversation. A new kind (a browser, a terminal)
/// joins here with the condition under which it is offered.
enum SidePanel { changes, background, preview, terminal, files, side, ship, device }

/// What came of a snapshot.
enum SnapResult {
  taken,

  /// macOS does not let Helmy see other apps' windows: screen recording.
  notAllowed,
  failed,
}

/// The note a side chat begins with, after what it was copied from.
const sideChatNote = 'A side chat: it knows what was said in the thread, which goes on as it is.';

/// Where a side chat's own part begins: its note, as it reads now or read
/// before chats.
bool isSideChatNote(ChatItem i) =>
    i is Notice &&
    (i.text == sideChatNote ||
        i.text == 'A side chat: it knows what was said in the session, which goes on as it is.');

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

  /// A side chat tab's session, and the question to ask it once it shows.
  String? sideId;
  String? ask;
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
    MacControl? mac,
    this.chromium,
    this.browser,
    this._editors,
    this._snaps,
    this._chats,
    this._log,
    this.embedded = false,
  }) : device = devices == null ? null : DeviceViewModel(devices, mac: mac, session: sessionId) {
    _attention?.viewing = sessionId;
    // The agent's browser_open opens the page here, in the Preview panel.
    browser?.opener(sessionId, preview);
    // The agent's device tools show the device here: in the Device panel,
    // or where it floats.
    if (device != null) browser?.deviceOpener(sessionId, showDevice);
    _sessions.addListener(notifyListeners);
    _sessions.addListener(_findRepoLater);
    _conversations.addListener(notifyListeners);
    _conversations.addListener(_onConversation);
    send = Command1(_send);
    ready = _conversations.load(sessionId);
    ready.then((_) => countChanges());
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
    // Its own copy, tidied away (archived, merged): back on its branch.
    if (session case final s? when s.ownCopy && !Directory(cwd).existsSync()) {
      await _projects?.restoreCopy(s);
    }
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

  bool _disposed = false;

  @override
  void notifyListeners() {
    // Work that finishes after the screen has gone (a deletion, a read)
    // has no one to tell.
    if (!_disposed) super.notifyListeners();
  }

  /// Done once the conversation has been read.
  late final Future<void> ready;
  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final AttentionRepository? _attention;
  final SettingsRepository? _settings;
  final EditorService? _editors;
  final WindowSnapshots? _snaps;
  final ChatRepository? _chats;
  final TurnLog? _log;

  // Filing (decision 0014): a new thread, after its first message, goes
  // into the chat it belongs to, said on screen with Move and Undo.

  /// What filing decided for this thread, to show; null when nothing to say.
  Filing? filing;

  /// The chat this thread is in, and its title.
  String? get chatTitle {
    final id = session?.chatId;
    return id == null ? null : _chats?.byId(id)?.title;
  }

  Future<void> _file(String message) async {
    final chats = _chats, s = session;
    if (chats == null || s == null || s.sideOf != null || s.chatId == null || embedded) return;
    final own = chats.byId(s.chatId!);
    // Only a thread alone in a chat nobody named: one started in a chat stays.
    if (own == null || own.named || chats.threadsOf(own.id).length != 1) return;
    final f = file(message, chats.cards(except: own.id));
    unawaited(
      _log?.filing(
        thread: s.id,
        kind: f.kind.name,
        chat: f.best,
        score: f.bestScore,
        runnerUp: f.runnerUp,
        runnerUpScore: f.runnerUpScore,
      ),
    );
    if (f.kind == .own) return;
    if (f.kind == .file) {
      await chats.move(s, f.best);
    }
    filing = f;
    notifyListeners();
  }

  /// Gives this thread its chat's brief as it stands now, to keep for good.
  Future<void> _freezeBrief([Session? thread]) async {
    final s = thread ?? session, chats = _chats;
    if (s == null || chats == null || s.chatId == null) return;
    var brief = chats.byId(s.chatId!)?.brief ?? '';
    // Other threads but no brief yet: still said, so the agent knows they
    // are there to look into.
    if (brief.isEmpty && chats.threadsOf(s.chatId!).any((t) => t.id != s.id)) {
      brief = '(No brief yet.)';
    }
    if ((s.brief ?? '') == brief) return;
    await _sessions.save(s.copyWith(brief: brief));
  }

  /// A thread moved while it is new (one message in) takes its new chat's
  /// brief; later it keeps the one it began with, which its cache is of.
  Future<void> _rebrief() async {
    if (items.whereType<UserMessage>().length <= 1) await _freezeBrief();
  }

  /// Files this thread into [chatId] (an answer to Helmy's question, or a
  /// move): a correction, logged.
  Future<void> fileInto(String? chatId) async {
    final chats = _chats, s = session;
    if (chats == null || s == null) return;
    final from = s.chatId;
    final to = await chats.move(s, chatId);
    await _rebrief();
    await _log?.correction(
      what: filing?.kind == .ask ? 'answer' : 'move',
      thread: s.id,
      from: from,
      to: to,
    );
    filing = (kind: FilingKind.file, best: to, bestScore: 1, runnerUp: null, runnerUpScore: 0);
    notifyListeners();
  }

  /// Takes the filing back: the thread goes back into a chat of its own.
  Future<void> undoFiling() async {
    final chats = _chats, s = session;
    if (chats == null || s == null) return;
    final from = s.chatId;
    final to = await chats.move(s, null);
    await _rebrief();
    await _log?.correction(what: 'undo', thread: s.id, from: from, to: to);
    filing = null;
    notifyListeners();
  }

  /// The chip put away, the filing kept.
  void dismissFiling() {
    filing = null;
    notifyListeners();
  }

  // A chat's threads, in its conversation (decision 0014): the others above
  // this one, oldest worked in first, each folded to what it came to.

  /// The other threads of this thread's chat, oldest worked in first.
  List<Session> get earlierThreads {
    final s = session, chats = _chats;
    if (s == null || chats == null || s.chatId == null || s.sideOf != null || embedded) {
      return const [];
    }
    final list = chats.threadsOf(s.chatId!).where((t) => t.id != s.id).toList()
      ..sort((a, b) => lastWorked(a).compareTo(lastWorked(b)));
    // Read in the background, for their summaries and to open them.
    for (final t in list) {
      if (!_conversations.of(t.id).loaded && _reading.add(t.id)) {
        unawaited(_conversations.load(t.id).then((_) => notifyListeners()));
      }
    }
    return list;
  }

  final _reading = <String>{};

  /// When [t] was last worked in: its last message or answer.
  DateTime lastWorked(Session t) {
    final ended = _conversations.of(t.id).items.whereType<TurnSummary>().lastOrNull?.endedAt;
    return ended != null && ended.isAfter(t.updatedAt) ? ended : t.updatedAt;
  }

  /// [id]'s conversation, to show folded or open.
  List<ChatItem> itemsOf(String id) => _conversations.of(id).items;

  /// What [t] came to, in a line: Helmy's summary of it, else how it began.
  String gistOf(Session t) {
    final summary = t.summary?.trim() ?? '';
    if (summary.isNotEmpty) return summary;
    final first = itemsOf(t.id).whereType<UserMessage>().firstOrNull?.text.trim() ?? '';
    return first.split('\n').first;
  }

  /// The earlier threads shown open.
  final unfolded = <String>{};

  void toggleThread(String id) {
    if (!unfolded.remove(id)) unfolded.add(id);
    notifyListeners();
  }

  /// A new thread in this chat, in this thread's folder and at its level:
  /// it starts with the chat's brief, not this thread's history. Its id.
  Future<String?> newThread() async {
    final s = session;
    if (s == null) return null;
    final made = await _sessions.create(
      cwd: s.cwd,
      level: s.level,
      chatId: s.chatId,
      title: 'New thread',
    );
    return switch (made) {
      Ok(:final value) => value.id,
      Error() => null,
    };
  }

  /// After this long without a word, a message starts a new thread.
  static const quietGap = Duration(hours: 6);

  /// Threads started on their own, by the thread they followed, for
  /// "keep going in the last one".
  static final startedAfter = <String, String>{};

  /// Where the screen should go: a thread started by sending here.
  final openThread = ValueNotifier<String?>(null);

  /// Whether [text] goes to a new thread rather than this one: this thread
  /// has gone quiet, and nothing ties the message to it (its own working
  /// copy, a scheduled run, a command, something waiting).
  bool _startsAfresh(Session s, String text, DateTime now) =>
      !embedded &&
      s.sideOf == null &&
      s.chatId != null &&
      !s.ownCopy &&
      s.taskId == null &&
      !text.trim().startsWith('!') &&
      !busy &&
      queue.isEmpty &&
      items.any((i) => i is UserMessage) &&
      now.difference(lastWorked(s)) >= quietGap;

  /// Takes a thread started on its own back: its message goes to the thread
  /// before it instead, and it is gone. The thread to open.
  Future<String?> keepGoingInLast() async {
    final s = session;
    final last = startedAfter.remove(sessionId);
    if (s == null || last == null) return null;
    final before = _sessions.byId(last);
    if (before == null) return null;
    final first = items.whereType<UserMessage>().firstOrNull;
    await _conversations.stop(sessionId);
    await _conversations.forget(sessionId);
    await _sessions.delete(sessionId);
    if (first != null) {
      await _conversations.send(before, first.text, attachments: first.attachments);
    }
    return last;
  }

  /// Every other chat, for Move.
  List<({String id, String title})> get otherChats => [
    for (final c in _chats?.chats ?? const [])
      if (c.id != session?.chatId) (id: c.id, title: c.title),
  ];

  String? chatTitleOf(String? id) => id == null ? null : _chats?.byId(id)?.title;

  /// Snapshots [window] into the message being written: its picture, and its
  /// text where macOS gives it. What came of it, to say so when it did not.
  Future<SnapResult> snapshotWindow(ScreenWindow window) async {
    final snaps = _snaps;
    if (snaps == null) return .failed;
    final taken = await snaps.take(window);
    if (taken == null) return (await snaps.access()).record ? .failed : .notAllowed;
    attach([taken.picture, ?taken.text]);
    focusRequests.value++;
    return .taken;
  }

  /// The windows that can be snapshotted now.
  Future<List<ScreenWindow>> snapshotWindows() async => await _snaps?.windows() ?? const [];

  /// Shown inside another session's panel (a side chat): it opens no panel
  /// of its own.
  final bool embedded;

  // Side chats: a question asked beside the session without adding to it.

  /// Where a side chat's own part begins (its first note); 0 for a session.
  int get firstShown {
    if (session?.sideOf == null) return 0;
    final at = items.lastIndexWhere(isSideChatNote);
    return at < 0 ? 0 : at;
  }

  /// This session's side chats, newest first.
  List<Session> get sideChats => [
    for (final s in _sessions.sessions)
      if (s.sideOf == sessionId) s,
  ];

  /// A side chat's name: its title once its first question named it.
  String sideTitle(String id) {
    final s = _sessions.byId(id);
    if (s == null || s.untitled) return 'Side chat';
    return s.title;
  }

  /// Starts a side chat beside this session, from all it knows, in a tab of
  /// its own, asking [ask] there when given. Its first edit is asked about,
  /// whatever this session may do.
  Future<void> sideChat({String? ask}) async {
    final s = session;
    if (s == null) return;
    final made = await _sessions.create(cwd: s.cwd, sideOf: s.id);
    if (made case Ok(:final value)) {
      await _conversations.copy(s.id, value.id, upTo: items.length - 1, note: sideChatNote);
      openSide(value.id, ask: ask);
    }
  }

  /// Shows side chat [id] in its tab: the one open, else a new one.
  void openSide(String id, {String? ask}) {
    final open = tabs.where((t) => t.sideId == id).firstOrNull;
    if (open != null) {
      if (ask != null) open.ask = ask;
      focus(open);
      return;
    }
    final tab = PanelTab(.side)
      ..sideId = id
      ..ask = ask;
    final at = active == null ? tabs.length : tabs.indexOf(active!) + 1;
    tabs.insert(at, tab);
    focus(tab);
  }

  /// Deletes side chat [id], its tab closed.
  Future<void> deleteSide(String id) async {
    // The tab goes at once; the deleting after, which may outlast this screen.
    for (final t in tabs.where((t) => t.sideId == id).toList()) {
      _removeTab(t);
    }
    notifyListeners();
    await _conversations.forget(id);
    await _sessions.delete(id);
  }

  /// Whether side chat [id] has nothing asked in it yet.
  bool sideUnused(String id) {
    final c = _conversations.of(id);
    final start = c.items.lastIndexWhere(isSideChatNote);
    return !c.busy && !c.items.skip(start + 1).any((i) => i is UserMessage);
  }

  /// What was said in side chat [id], given to this session with the next
  /// message as a file it reads (its chip shows above the message, to take
  /// off). False while this session works, as it cannot take it then.
  Future<bool> bringBack(String id) async {
    if (busy) return false;
    final side = _conversations.of(id).items;
    final start = side.lastIndexWhere(isSideChatNote);
    final title = sideTitle(id);
    final text = transcriptMarkdown('Side chat: $title', side.skip(start + 1).toList());
    final dir = await Directory.systemTemp.createTemp('helmy-side');
    final name = title.replaceAll(RegExp(r'[/:\\]'), '-');
    final file = File('${dir.path}/Side chat, $name.md');
    await file.writeAsString(text);
    attach([file.path]);
    focusRequests.value++;
    return true;
  }

  late final Command1<void, String> send;

  Session? get session => _sessions.byId(sessionId);
  Conversation get _c => _conversations.of(sessionId);
  List<ChatItem> get items => _c.items;
  bool get busy => _c.busy;

  /// Only the model on this Mac could answer the last message sent.
  bool get onlyThisMac => _conversations.onlyThisMac ?? false;
  bool get thinking => _c.thinking;

  /// Every connection is at its limit: the message waits until then.
  DateTime? get heldUntil => _c.heldUntil;

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
    // A folder of its own (no project) is empty: nothing in it to suggest.
    if (s == null || isScratch(s.cwd)) return Future.value(const []);
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
    if (s == null) return .error(Exception('No thread'));
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

  @override
  Future<String?> documentText(String path) async => _desktop?.documentText(path);

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
    final dir = attachmentsDir();
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
    // A side chat nothing was asked in goes with its tab.
    final side = tab.sideId;
    if (side != null && sideUnused(side)) {
      unawaited(deleteSide(side));
      return;
    }
    _removeTab(tab);
    notifyListeners();
  }

  void _removeTab(PanelTab tab) {
    final at = tabs.indexOf(tab);
    if (at < 0) return;
    tabs.removeAt(at);
    if (active == tab) active = tabs.isEmpty ? null : tabs[at.clamp(0, tabs.length - 1)];
    if (tabs.isEmpty) {
      panelOpen = false;
      panelExpanded = false;
    }
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

  // The terminal under the conversation, as an editor's bottom panel.

  /// The terminals in it, side by side, by id; empty until first shown.
  final List<int> bottomTerminals = [];
  static var _nextTerminal = 0;

  /// Shown; hidden, its terminals keep running.
  bool bottomOpen = false;

  /// How tall it is, as last dragged.
  double bottomHeight = 260;

  /// Shows the terminal under the conversation (one is started the first
  /// time), or hides it.
  void toggleBottom() {
    if (!bottomOpen && bottomTerminals.isEmpty) bottomTerminals.add(_nextTerminal++);
    bottomOpen = !bottomOpen;
    notifyListeners();
  }

  /// Another terminal beside the others.
  void splitBottom() {
    bottomTerminals.add(_nextTerminal++);
    bottomOpen = true;
    notifyListeners();
  }

  /// Ends terminal [id]; with none left, the panel hides.
  void closeBottom(int id) {
    bottomTerminals.remove(id);
    if (bottomTerminals.isEmpty) bottomOpen = false;
    notifyListeners();
  }

  void resizeBottom(double height) {
    bottomHeight = height;
    notifyListeners();
  }

  /// The open panel over the whole page, the conversation set aside.
  bool panelExpanded = false;

  void toggleExpanded() {
    panelExpanded = panel != null && !panelExpanded;
    notifyListeners();
  }

  /// Hides the panel; its tabs stay.
  void closePanel() {
    if (panel == .changes) _changesClosed = true;
    panelOpen = false;
    panelExpanded = false;
    notifyListeners();
  }

  void resize(double width) {
    panelWidth = width.clamp(260.0, 900.0);
    notifyListeners();
  }

  void toggleChanges() => toggle(.changes);

  // The device over the conversation, as a picture in picture: watched
  // while the conversation has the room.

  /// The device floats over the conversation, out of the panel.
  bool deviceFloating = false;

  /// Where its top left sits, as last dragged; null until then (top right).
  Offset? deviceFloatAt;

  /// The device shown: where it floats, or in the panel.
  void showDevice({bool mac = false}) {
    if (mac) device?.showMac();
    if (deviceFloating) return notifyListeners();
    show(.device);
  }

  /// The device out of the panel, floating over the conversation. Its tab
  /// goes; the panel hides with no tab left.
  void floatDevice() {
    if (device == null) return;
    for (final tab in tabs.where((t) => t.kind == .device).toList()) {
      _removeTab(tab);
    }
    deviceFloating = true;
    notifyListeners();
  }

  /// The floating device back in the panel, as a tab.
  void dockDevice() {
    deviceFloating = false;
    show(.device);
  }

  /// The floating device put away.
  void closeFloatingDevice() {
    deviceFloating = false;
    notifyListeners();
  }

  void moveFloatingDevice(Offset at) {
    deviceFloatAt = at;
    notifyListeners();
  }

  /// How many files the session has changed, once counted: again whenever a
  /// turn ends.
  int? changedFiles;
  bool _wasBusy = false;

  Future<void> countChanges({bool turnEnded = false}) async {
    final git = await changesIn(null);
    final n =
        git?.length ??
        {
          for (final c in reportedIn(null))
            for (final d in diffsOf(c)) d.path,
        }.length;
    final lines = git?.fold<int>(0, (sum, c) => sum + c.added + c.removed) ?? 0;

    if (n != changedFiles) {
      changedFiles = n;
      notifyListeners();
    }
    // Enough changed to be worth seeing (three files, or fifty lines): the
    // Changes panel opens by itself, once, unless it was closed here.
    final enough = n >= 3 || lines >= 50;
    if (turnEnded && enough && !_changesShown && !panelOpen && !_changesClosed) {
      _changesShown = true;
      showChanges();
    }
  }

  /// The Changes panel opened by itself here already: once is enough.
  bool _changesShown = false;

  /// The Changes panel was closed in this thread: it does not open by itself.
  bool _changesClosed = false;

  void _onConversation() {
    if (_wasBusy && !busy) countChanges(turnEnded: true);
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

  /// The apps a file can open in, for the file popup.
  EditorChoice get editorChoice => (all: editors, usual: editor, open: openIn);

  /// Opens the project (or the file at [path] in it) in [app], else the
  /// usual one; a chosen app becomes the usual one. False when it could not.
  Future<bool> openIn([Editor? app, String? path]) async {
    final e = app ?? editor;
    final folder = path ?? session?.cwd;
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
    // A thread of the same chat.
    final made = await _sessions.create(
      cwd: s.cwd,
      level: s.level,
      title: '${s.title} fork',
      chatId: s.chatId,
    );
    if (made case Ok(:final value)) {
      await _conversations.copy(s.id, value.id, upTo: upTo, note: 'Forked from "${s.title}"');
      return value.id;
    }
    return null;
  }

  /// An attached file shown: beside the conversation where there is a web
  /// view (pictures, PDFs and text show there), else in its own app.

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
    .files,
    if (!embedded) .side,
    .changes,
    if (inRepo) .ship,
    if (device != null && !deviceFloating) .device,
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

  /// Text to put in the message being written, at its cursor: a file to ask
  /// about, "@lib/main.dart". Taken (set back to null) by the composer.
  final draftInserts = ValueNotifier<String?>(null);

  /// Puts [path] (relative to the session's folder) in the message as an @
  /// mention, and the cursor after it.
  void mention(String path) => draftInserts.value = '@$path ';

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
  /// A device's screen with marks drawn on it, and the marks as text: both
  /// go with the next message.
  Future<void> attachMarks(Uint8List png, String text) async {
    final dir = attachmentsDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final picture = File('${dir.path}/device-marks-$stamp.png');
    final notes = File('${dir.path}/device-marks-$stamp.md');
    await picture.writeAsBytes(png);
    await notes.writeAsString(text);
    attach([picture.path, notes.path]);
    focusRequests.value++;
  }

  Future<void> attachScreen(Uint8List bytes) async {
    final dir = attachmentsDir();
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

  // What is being written and not sent: kept with the thread, so leaving it
  // (for another, or a new one) or closing Helmy loses nothing.

  /// The words in the message box, as last kept; null when not changed here.
  String? _draft;
  Timer? _draftTimer;

  /// What was being written when the thread was last left.
  String get draft => session?.draft ?? '';

  /// The message box changed: kept a moment after typing stops.
  void keepDraft(String text) {
    _draft = text;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 700), saveDraft);
  }

  /// Keeps what is in the message box now (the thread is being left).
  Future<void> saveDraft() async {
    _draftTimer?.cancel();
    final text = _draft;
    final s = session;
    if (text == null || s == null || text == (s.draft ?? '')) return;
    _draft = null;
    await _sessions.save(s.copyWith(draft: text));
  }

  /// Gives this thread a webhook address (a new secret), or takes it away:
  /// an address turned off and on again is a new one.
  Future<void> setWebhook(bool on) async {
    final s = session;
    if (s == null) return;
    await _sessions.save(s.copyWith(webhook: on ? Webhooks.newSecret() : ''));
    notifyListeners();
  }

  /// Comments on parts of the conversation: the words chosen, and what the
  /// person says about them. They go with the next message, quoted, so the
  /// agent knows what each is about.
  final comments = <({int id, String quote, String note})>[];
  static var _nextComment = 0;

  /// Whether something waits to go besides the words typed.
  bool get hasExtras => attachments.isNotEmpty || comments.isNotEmpty;

  /// A comment on [quote], its words to come; the message box takes them.
  void comment(String quote) {
    final q = quote.trim();
    if (q.isEmpty) return;
    comments.add((id: _nextComment++, quote: q, note: ''));
    notifyListeners();
  }

  void noteComment(int i, String note) {
    if (i < 0 || i >= comments.length) return;
    comments[i] = (id: comments[i].id, quote: comments[i].quote, note: note);
  }

  void dropComment(int i) {
    if (i < 0 || i >= comments.length) return;
    comments.removeAt(i);
    notifyListeners();
  }

  /// [comments] as they go ahead of the message: each part quoted (cut
  /// short when long), and what was said about it.
  static String commentsText(List<({int id, String quote, String note})> comments) => [
    'About these parts of the conversation:',
    for (final c in comments) ...[
      '',
      for (final line in (c.quote.length <= 600 ? c.quote : '${c.quote.substring(0, 600)}…').split(
        '\n',
      ))
        '> $line',
      c.note.trim().isEmpty ? '(no comment written: look at this part)' : c.note.trim(),
    ],
  ].join('\n');

  Future<Result<void>> _send(String text) async {
    final s = session;
    if (s == null || (text.trim().isEmpty && !hasExtras)) {
      return .error(Exception('Nothing to send'));
    }
    if (comments.isNotEmpty) {
      text = '${commentsText(comments)}${text.trim().isEmpty ? '' : '\n\n${text.trim()}'}';
      comments.clear();
    }
    _draftTimer?.cancel();
    _draft = null;
    if (session?.hasDraft ?? false) await _sessions.save(session!.copyWith(draft: ''));
    final files = [...attachments];
    final needs = {...pendingNeeds};
    attachments.clear();
    pendingNeeds.clear();
    // Back after a quiet gap: a new thread in this chat, which starts with
    // the chat's brief rather than this thread's whole history.
    if (_startsAfresh(s, text, DateTime.now())) {
      final id = await newThread();
      final fresh = id == null ? null : _sessions.byId(id);
      if (fresh != null) {
        startedAfter[fresh.id] = s.id;
        await _freezeBrief(fresh);
        final sent = await _conversations.send(
          _sessions.byId(fresh.id) ?? fresh,
          text.trim(),
          attachments: files,
          needs: needs,
        );
        openThread.value = fresh.id;
        return sent;
      }
    }
    // A thread's first message: filed first (local, at once), so it starts
    // in its chat knowing the chat's brief, frozen for the thread.
    if (!items.any((i) => i is UserMessage)) {
      await _file(text);
      await _freezeBrief();
    }
    return _conversations.send(session ?? s, text.trim(), attachments: files, needs: needs);
  }

  void interrupt() => _conversations.interrupt(sessionId);

  /// Sends the waiting message at [index] now, redirecting the agent.
  void steer(int index) => _conversations.steer(sessionId, index);

  /// Sends [text] now even while the agent works: it stops what it is doing
  /// and takes this up instead.
  Future<void> sendNow(String text) async {
    // Waiting for room, there is nothing to redirect: it waits its turn.
    if (!busy || heldUntil != null) {
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
    if (s == null) return .error(Exception('No thread'));
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

  /// Names this thread's chat, for good; a thread in no chat, the thread.
  Future<void> rename(String title) async {
    final s = session;
    final t = title.trim();
    if (s == null || t.isEmpty) return;
    if (s.chatId != null && _chats?.byId(s.chatId!) != null) {
      await _chats!.rename(s.chatId!, t);
      notifyListeners();
      return;
    }
    await _sessions.save(s.copyWith(title: t));
  }

  /// Moves the session (before its first message) into a folder of its
  /// own that Helmy keeps: for what belongs to no project. Its files are
  /// still made there, and choosing a folder later moves it.
  Future<void> startWithoutProject() async {
    final root = scratchRoot;
    if (root == null) return;
    final dir = Directory('$root/$sessionId');
    await dir.create(recursive: true);
    await changeFolder(dir.path);
  }

  Future<void> delete() async {
    // Its own working copy goes with it, unless it holds uncommitted work;
    // its branch stays either way.
    if (session case final s? when s.ownCopy) await _projects?.removeCopy(s.repo!, s.cwd);
    // A folder of its own (no project) is Helmy's, and goes with it.
    final cwd = session?.cwd;
    if (cwd != null && isScratch(cwd)) {
      try {
        await Directory(cwd).delete(recursive: true);
      } on FileSystemException {
        // Already gone.
      }
    }
    // Its side chats go with it.
    for (final side in sideChats) {
      await _conversations.forget(side.id);
      await _sessions.delete(side.id);
    }
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
    // What was read of the old folder is not this one's.
    _starters = null;
    _files = null;
    await _sessions.save(s.copyWith(cwd: cwd, threads: const {}, level: level));
  }

  @override
  void dispose() {
    _disposed = true;
    _draftTimer?.cancel();
    _attention?.viewing = null;
    browser?.opener(sessionId, null);
    browser?.deviceOpener(sessionId, null);
    device?.dispose();
    focusRequests.dispose();
    draftInserts.dispose();
    openThread.dispose();
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
