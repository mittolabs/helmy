import 'package:flutter/foundation.dart';

import '../../../data/repositories/attention_repository.dart';
import '../../../data/repositories/conversation_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/models/session.dart';
import '../../../domain/models/settings.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../../utils/platform.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/fixes.dart';
import '../../../domain/problem.dart';
import '../../../domain/models/chat_item.dart';
import '../../../domain/helmy_voice.dart';
import '../../../utils/diffs.dart';
import '../../../utils/format.dart';

import 'dart:async';

import '../../../data/repositories/chat_repository.dart';
import '../../../data/repositories/ship_repository.dart';
import '../../../data/services/pull_requests.dart';
import '../../../data/services/turn_log.dart';
import '../../../domain/filing.dart';
import '../../../data/services/engines/attachments.dart';
import '../../../domain/models/chat.dart';

enum SessionActivity { idle, working, needsYou, unread }

class SidebarViewModel extends ChangeNotifier {
  new({
    required this._sessions,
    required this._conversations,
    required this._settings,
    this._attention,
    this._projects,
    this._chats,
    this._log,
    this._fixes,
    ShipRepository? ship,
    this._prs,
  }) : _ship = ship {
    _sessions.addListener(_checkGitHub);
    unawaited(_checkGitHub());
    // A chat whose pull request merged is done with, unless something in it
    // still goes on.
    _mergedSub = ship?.merged.listen((id) => unawaited(_onMerged(id)));
    _attention?.addListener(_onConversations);
    _chats?.addListener(notifyListeners);
    _sessions.addListener(notifyListeners);
    _settings.addListener(notifyListeners);
    _conversations.addListener(_onConversations);
    // Working copies and checkouts kept in order: now, then now and again.
    unawaited(_tidy());
    _tidyTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      unawaited(_tidy());
      unawaited(settleIdle());
    });
    // Once the list has been read.
    _firstSettle = Timer(const Duration(seconds: 5), () => unawaited(settleIdle()));
    create = Command0(
      () async => _sessions.create(
        cwd: defaultFolder,
        level: await _projects?.levelFor(defaultFolder) ?? _settings.settings.defaultLevel,
      ),
    );
    delete = Command1(_delete);
  }

  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final SettingsRepository _settings;
  final AttentionRepository? _attention;
  final ProjectRepository? _projects;
  final Fixes? _fixes;

  /// Opens the system's own pane for allowing notifications.
  Future<void> allowNotifications() async => _fixes?.apply(Fix.allowNotifications);

  late final Command0<Session> create;

  /// A new session in [cwd], at that project's permissions.
  Future<Result<Session>> createIn(String cwd) async => _sessions.create(
    cwd: cwd,
    level: await _projects?.levelFor(cwd) ?? _settings.settings.defaultLevel,
  );
  late final Command1<void, String> delete;

  final Map<String, SessionActivity> _activity = {};

  /// Every session but side chats, which show only beside their session.
  List<Session> get sessions => [
    for (final s in _sessions.sessions)
      if (s.sideOf == null) s,
  ];

  AppSettings get settings => _settings.settings;
  Future<void> updateSettings(AppSettings s) => _settings.save(s);

  /// The sessions the list shows, pinned first, in the order settings ask for.
  List<Session> get shown {
    final s = settings;
    final since = s.recency.within == null ? null : DateTime.now().subtract(s.recency.within!);
    final list = _sessions.sessions
        // Side chats show only beside their session.
        .where((x) => x.sideOf == null)
        // A new chat with nothing sent or written is not a chat yet: it
        // joins the list with its first message, or under Drafts with words.
        .where(
          (x) =>
              !x.blank || _conversations.of(x.id).busy || _conversations.of(x.id).items.isNotEmpty,
        )
        .where(
          (x) => switch (s.show) {
            // A snoozed session stays out until it is due, unless it wants you
            // or is working before then.
            .active => !x.archived && (!x.snoozed || _calling(x.id)),
            .archived => x.archived,
            .all => true,
          },
        )
        // Pinned sessions stay listed however old they are.
        .where((x) => since == null || x.pinned || x.updatedAt.isAfter(since))
        .toList();
    int byOrder(Session a, Session b) => switch (s.sort) {
      .recent => b.updatedAt.compareTo(a.updatedAt),
      .name => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    };
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return byOrder(a, b);
    });
    return list;
  }

  /// [shown] in groups. First what wants you (an approval, or an answer you
  /// have not seen), then what is working, each only when there is any; then
  /// the rest, in one group or one per folder.
  List<({String? label, String? folder, List<Session> sessions})> get groups {
    // Settled chats are in their own section, at the bottom.
    final list = settings.show == .active ? shown.where((x) => !isSettled(x)).toList() : shown;
    // A chat is one row: all its threads go where its busiest one would.
    final ofChat = <String, List<Session>>{};
    for (final x in list) {
      (ofChat[_key(x)] ??= []).add(x);
    }
    SessionActivity chatActivity(Session x) => activityOfAll(ofChat[_key(x)]!);
    final wants = [
      for (final x in list)
        if (chatActivity(x) case SessionActivity.needsYou || SessionActivity.unread) x,
    ];
    final working = [
      for (final x in list)
        if (chatActivity(x) == SessionActivity.working) x,
    ];
    // New chats with words written and nothing sent yet: kept at the top,
    // to finish or delete.
    final drafts = [
      for (final x in list)
        if (x.untitled && x.hasDraft && chatActivity(x) == .idle) x,
    ];
    final rest = [
      for (final x in list)
        if (!wants.contains(x) && !working.contains(x) && !drafts.contains(x)) x,
    ];
    // What needs you first; what is working last, out of the way until it
    // finishes or needs you (then it moves up by itself).
    final out = <({String? label, String? folder, List<Session> sessions})>[
      if (drafts.isNotEmpty) (label: 'Drafts', folder: null, sessions: drafts),
      if (wants.isNotEmpty) (label: 'Needs you', folder: null, sessions: wants),
    ];
    final last = <({String? label, String? folder, List<Session> sessions})>[
      if (working.isNotEmpty) (label: 'Working', folder: null, sessions: working),
    ];
    if (settings.group == .none) {
      if (rest.isNotEmpty || (out.isEmpty && last.isEmpty)) {
        out.add((
          label: out.isEmpty && last.isEmpty ? null : 'Everything else',
          folder: null,
          sessions: rest,
        ));
      }
      return [...out, ...last];
    }
    // A chat under the folder its latest thread works in.
    final byFolder = <String, List<Session>>{};
    final folderOf = <String, String>{};
    for (final x in rest) {
      final folder = folderOf.putIfAbsent(_key(x), () => x.cwd);
      byFolder.putIfAbsent(folder, () => []).add(x);
    }
    return [
      ...out,
      for (final e in byFolder.entries) (label: null, folder: e.key, sessions: e.value),
      ...last,
    ];
  }

  /// Each chat in the order the list shows them, by the thread it opens
  /// to, for ⌘1 to ⌘9.
  List<Session> get inOrder => [
    for (final g in groups)
      for (final e in entriesOf(g.sessions)) e.threads.first,
  ];

  /// The chat [s] is in, as a key: its chat, or itself when it has none.
  static String _key(Session s) => s.chatId ?? s.id;

  bool isUnread(String id) => _attention?.isUnread(id) == true;

  /// Another session finished or needs you, while Helmy is in front.
  Stream<({String sessionId, String title, String body})> get inApp =>
      _attention?.inApp ?? const Stream.empty();

  /// Helmy's notifications are on, but the system blocks them.
  bool get notificationsBlocked => _attention?.notificationsBlocked ?? false;

  /// Notifications off in Helmy, for someone who does not want them after all.
  Future<void> turnOffNotifications() => updateSettings(settings.copyWith(notify: false));

  /// Settles a finished session you do not need to open.
  void markRead(String id) => _attention?.markRead(id);

  /// The session last archived, for undo.
  Session? lastArchived;

  Future<void> undoArchive() async {
    final s = lastArchived;
    if (s == null) return;
    lastArchived = null;
    final now = _sessions.byId(s.id);
    if (now != null) await _sessions.save(now.copyWith(archived: false));
  }

  /// Every session with its conversation as text, for the search palette.
  Future<List<(Session, String)>> searchIndex() async => [
    for (final s in sessions) (s, await _conversations.searchText(s.id)),
  ];

  /// Wants you or is working: back in the list even while snoozed.
  bool _calling(String id) =>
      const {SessionActivity.needsYou, SessionActivity.working}.contains(activityOf(id));

  /// Out of the list until [until], then back as needing you.
  Future<void> snooze(Session s, DateTime until) {
    lastSnoozed = s;
    return _sessions.save(s.copyWith(snoozedUntil: until, pinned: false));
  }

  /// The session last snoozed, for undo.
  Session? lastSnoozed;

  Future<void> undoSnooze() async {
    final s = lastSnoozed;
    if (s == null) return;
    lastSnoozed = null;
    final now = _sessions.byId(s.id);
    if (now != null) await _sessions.save(now.copyWith(wake: true, pinned: s.pinned));
  }

  /// Back in the list now.
  Future<void> wake(Session s) => _sessions.save(s.copyWith(wake: true));

  /// When "until tomorrow" ends: 9 in the morning.
  /// The snooze choices from [now]: in an hour, in three, this evening
  /// while it is still ahead, tomorrow morning, and Monday morning.
  static List<(String, DateTime)> snoozeChoices([DateTime? from]) {
    final now = from ?? DateTime.now();
    final evening = DateTime(now.year, now.month, now.day, 18);
    final monday = DateTime(now.year, now.month, now.day + (8 - now.weekday), 9);
    return [
      ('Snooze for an hour', now.add(const Duration(hours: 1))),
      ('Snooze for 3 hours', now.add(const Duration(hours: 3))),
      if (evening.difference(now) > const Duration(hours: 1))
        ('Snooze until this evening', evening),
      ('Snooze until tomorrow', tomorrowMorning(now)),
      if (now.weekday < 5) ('Snooze until Monday', monday),
    ];
  }

  static DateTime tomorrowMorning([DateTime? from]) {
    final now = from ?? DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 9);
  }

  Future<void> setPinned(Session s, bool pinned) => _sessions.save(s.copyWith(pinned: pinned));

  Future<void> setArchived(Session s, bool archived) async {
    lastArchived = archived ? s : null;
    await _sessions.save(s.copyWith(archived: archived, pinned: archived ? false : null));
    // Archived, its copy can go (it comes back when the session is opened).
    if (archived && s.ownCopy) unawaited(_tidy());
  }

  Timer? _tidyTimer, _firstSettle;
  bool _tidying = false;

  Future<void> _tidy() async => tidyNow();

  /// Tidies threads' copies now: those archived, merged, of no thread, and
  /// (as set) of settled chats. What was done; empty when nothing was, or
  /// a tidy was already under way.
  Future<List<String>> tidyNow() async {
    final projects = _projects;
    if (projects == null || _tidying) return const [];
    _tidying = true;
    try {
      // Never a copy a session is working in right now.
      final working = {
        for (final s in _sessions.sessions)
          if (_conversations.of(s.id).busy) s.id,
      };
      final settled = {
        if (settings.tidySettled)
          for (final s in _sessions.sessions)
            if (s.chatId != null && (_chats?.byId(s.chatId!)?.settled ?? false)) s.id,
      };
      return await projects.tidy(_sessions.sessions, working: working, settled: settled);
    } on Object {
      // Tried again next time.
      return const [];
    } finally {
      _tidying = false;
    }
  }

  /// Where a new session starts: the folder last worked in or the one set in
  /// settings, else home. It can be changed from the session itself, so
  /// nothing is asked up front.
  String get defaultFolder {
    final s = _settings.settings;
    final home = homeDir;
    if (s.folderMode == .fixed && s.fixedFolder != null) return s.fixedFolder!;
    return _sessions.sessions.firstOrNull?.cwd ?? home;
  }

  SessionActivity activityOf(String id) => _activity[id] ?? .idle;

  // The list is of chats (decision 0014): each row a chat, its threads
  // inside it, in the conversation.

  final ChatRepository? _chats;
  final TurnLog? _log;

  /// [sessions] (a section of the list, in its order) as chats: each once,
  /// where its first thread was, with its threads in that order (the one it
  /// opens to first).
  List<({Chat? chat, List<Session> threads})> entriesOf(List<Session> sessions) {
    final byChat = <String, List<Session>>{};
    for (final s in sessions) {
      (byChat[_key(s)] ??= []).add(s);
    }
    return [for (final e in byChat.entries) (chat: _chats?.byId(e.key), threads: e.value)];
  }

  /// What a chat's row is called: its title, else its latest thread's.
  String titleOf(({Chat? chat, List<Session> threads}) e) => e.chat?.title ?? e.threads.first.title;

  // What is done to a row is done to the chat: every thread in it.

  /// The threads of the chat [s] is in, side chats too; [s] alone when it is
  /// in none.
  List<Session> chatOf(Session s) => s.chatId == null
      ? [s]
      : [
          for (final x in _sessions.sessions)
            if (x.chatId == s.chatId) x,
        ];

  void markChatRead(List<Session> threads) {
    for (final t in threads) {
      markRead(t.id);
    }
  }

  Future<void> setChatPinned(List<Session> threads, bool pinned) async {
    for (final t in threads) {
      await setPinned(_sessions.byId(t.id) ?? t, pinned);
    }
  }

  Future<void> snoozeChat(List<Session> threads, DateTime until) async {
    final was = [for (final t in threads) _sessions.byId(t.id) ?? t];
    for (final t in was) {
      await _sessions.save(t.copyWith(snoozedUntil: until, pinned: false));
    }
    _undo = () async {
      for (final t in was) {
        final now = _sessions.byId(t.id);
        if (now != null) await _sessions.save(now.copyWith(wake: true, pinned: t.pinned));
      }
    };
  }

  Future<void> wakeChat(List<Session> threads) async {
    for (final t in threads) {
      await wake(_sessions.byId(t.id) ?? t);
    }
  }

  Future<void> setChatArchived(List<Session> threads, bool archived) async {
    final was = [for (final t in threads) _sessions.byId(t.id) ?? t];
    for (final t in was) {
      await _sessions.save(t.copyWith(archived: archived, pinned: archived ? false : null));
    }
    _undo = !archived
        ? null
        : () async {
            for (final t in was) {
              final now = _sessions.byId(t.id);
              if (now != null) {
                await _sessions.save(now.copyWith(archived: false, pinned: t.pinned));
              }
            }
          };
    if (archived && was.any((t) => t.ownCopy)) unawaited(_tidy());
  }

  Future<void> deleteChat(List<Session> threads) async {
    for (final t in threads) {
      await delete.execute(t.id);
    }
  }

  /// Takes back the last archive, snooze or settle (⌘Z).
  Future<void> undo() async {
    final u = _undo;
    _undo = null;
    if (u != null) {
      await u();
    } else {
      await undoArchive();
    }
  }

  Future<void> Function()? _undo;

  // Several chats at once: ⌘-click picks one more, ⇧-click a run of them;
  // then what is done is done to all of them.

  /// The chats picked, by the key of their chat.
  final picked = <String>{};
  String? _lastPicked;

  bool get picking => picked.isNotEmpty;

  /// Picks [s]'s chat, or lets it go; with [range], every chat from the last
  /// one picked to it, in the list's order.
  void pick(Session s, {bool range = false}) {
    final key = _key(_sessions.byId(s.id) ?? s);
    if (range && _lastPicked != null) {
      final order = [for (final t in inOrder) _key(t)];
      final a = order.indexOf(_lastPicked!), b = order.indexOf(key);
      if (a >= 0 && b >= 0) {
        picked.addAll(order.sublist(a < b ? a : b, (a < b ? b : a) + 1));
        notifyListeners();
        return;
      }
    }
    if (!picked.remove(key)) picked.add(key);
    _lastPicked = key;
    notifyListeners();
  }

  void clearPicks() {
    picked.clear();
    _lastPicked = null;
    notifyListeners();
  }

  bool isPicked(Session s) => picked.contains(_key(_sessions.byId(s.id) ?? s));

  /// Every picked chat's threads (side chats too), chat by chat.
  List<List<Session>> get _pickedChats => [
    for (final key in picked)
      [
        for (final x in _sessions.sessions)
          if (_key(x) == key) x,
      ],
  ].where((c) => c.isNotEmpty).toList();

  /// Does [each] to every picked chat, keeping one undo that takes all of
  /// them back; then lets them go.
  Future<void> _forPicked(Future<void> Function(List<Session> chat) each) async {
    final undos = <Future<void> Function()>[];
    for (final chat in _pickedChats) {
      _undo = null;
      await each(chat);
      if (_undo case final u?) undos.add(u);
    }
    _undo = undos.isEmpty
        ? null
        : () async {
            for (final u in undos) {
              await u();
            }
          };
    clearPicks();
  }

  Future<void> markPickedDone() => _forPicked((c) async {
    if (!busyChat(c)) await settleChat(c);
  });

  Future<void> snoozePicked(DateTime until) => _forPicked((c) => snoozeChat(c, until));

  Future<void> archivePicked() => _forPicked((c) => setChatArchived(c, true));

  Future<void> deletePicked() => _forPicked(deleteChat);

  /// Has Helmy name the picked chats afresh (a name the person gave stays).
  Future<void> renamePicked(Future<void> Function(String threadId) describe) =>
      _forPicked((c) async {
        final first = c.where((t) => t.sideOf == null).firstOrNull;
        final chatId = first?.chatId;
        if (first == null || chatId == null) return;
        await _chats?.forgetNaming(chatId);
        await describe(first.id);
      });

  int get pickedCount => picked.length;

  /// Moves the chat of [from] into [chatId]: its threads become threads of
  /// that chat, which can then read them and message them. One undo puts
  /// them back in a chat of their own.
  Future<void> mergeInto(List<Session> from, String chatId) async {
    final chats = _chats;
    final threads = from.where((t) => t.sideOf == null).toList();
    if (chats == null || threads.isEmpty || threads.first.chatId == chatId) return;
    final was = threads.first.chatId;
    for (final t in threads) {
      await chats.move(_sessions.byId(t.id) ?? t, chatId);
    }
    await _log?.correction(what: 'merge', thread: threads.first.id, from: was, to: chatId);
    _undo = () async {
      String? back;
      for (final t in threads) {
        final now = _sessions.byId(t.id);
        if (now == null) continue;
        back = await chats.move(now, back);
      }
    };
    notifyListeners();
  }

  // Settled (the list as an inbox): a chat nothing in waits on goes to the
  // bottom, until something new happens in it. By hand, when its pull
  // request merges, or after three days untouched.

  /// Whether the chat [s] is in is settled.
  bool isSettled(Session s) => s.chatId != null && (_chats?.byId(s.chatId!)?.settled ?? false);

  /// The settled chats, last worked in first: shown under Settled, in the
  /// list of what is active.
  List<({Chat? chat, List<Session> threads})> get settled {
    if (settings.show != .active) return const [];
    final list = shown.where(isSettled).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entriesOf(list);
  }

  /// Settled shown open, and all of it rather than the latest ten.
  bool settledOpen = false, settledAll = false;

  void toggleSettled() {
    settledOpen = !settledOpen;
    if (!settledOpen) settledAll = false;
    notifyListeners();
  }

  void showAllSettled() {
    settledAll = true;
    notifyListeners();
  }

  /// Something in the chat waits on you or is working: it cannot be settled.
  bool busyChat(List<Session> threads) =>
      const {SessionActivity.needsYou, SessionActivity.working}.contains(activityOfAll(threads));

  /// Settles the chat of [threads]: its threads read, the chat at the bottom.
  Future<void> settleChat(List<Session> threads) async {
    final chats = _chats;
    final chatId = threads.firstOrNull?.chatId;
    if (chats == null || chatId == null) return;
    markChatRead(threads);
    await chats.settle(chatId);
    _undo = () => chats.unsettle(chatId);
    notifyListeners();
  }

  Future<void> unsettleChat(List<Session> threads) async {
    final chatId = threads.firstOrNull?.chatId;
    if (chatId != null) await _chats?.unsettle(chatId);
    notifyListeners();
  }

  /// How long untouched before a chat settles by itself, as set.
  Duration get idleSettles => Duration(days: settings.settleDays);

  /// Settles every chat untouched for [idleSettles]: none waiting on you,
  /// working, pinned, snoozed, or (as set) with a pull request open. Only
  /// when settings let it.
  Future<void> settleIdle({DateTime? now}) async {
    final chats = _chats;
    if (chats == null || !settings.settleOnItsOwn) return;
    final at = now ?? DateTime.now();
    for (final c in chats.chats.toList()) {
      if (c.settled) continue;
      final threads = chats.threadsOf(c.id);
      if (threads.isEmpty || threads.every((t) => t.archived)) continue;
      if (threads.any((t) => t.pinned || t.snoozed)) continue;
      if (settings.keepWithPr && threads.any((t) => _ship?.stateOf(t.id)?.pr?.state == 'OPEN')) {
        continue;
      }
      if (activityOfAll(threads) != .idle) continue;
      if (at.difference(chats.lastTouched(c.id)) < idleSettles) continue;
      await chats.settle(c.id, at: at);
    }
  }

  Future<void> _onMerged(String sessionId) async {
    final chats = _chats;
    final s = _sessions.byId(sessionId);
    if (chats == null || s?.chatId == null || !settings.settleOnItsOwn) return;
    if (busyChat(chats.threadsOf(s!.chatId!))) return;
    await chats.settle(s.chatId!);
  }

  StreamSubscription<String>? _mergedSub;

  // Pull requests are for people whose chats work in GitHub repositories:
  // the list shows them only then (⌘K finds them always).

  final PullRequests? _prs;

  /// Some chat works in a repository on GitHub.
  bool showPullRequests = false;

  /// The folders last asked about, so the same ones are not asked again.
  String? _gitHubAsked;

  Future<void> _checkGitHub() async {
    final prs = _prs;
    if (prs == null) return;
    final folders = {
      for (final s in _sessions.sessions)
        if (!s.archived) s.repo ?? s.cwd,
    }.toList()..sort();
    final key = folders.join('\n');
    if (key == _gitHubAsked) return;
    _gitHubAsked = key;
    final show = await prs.anyOnGitHub(folders);
    if (_disposed || show == showPullRequests) return;
    showPullRequests = show;
    notifyListeners();
  }

  /// The busiest of [threads]: one that needs you, else one working, else
  /// one unread.
  SessionActivity activityOfAll(List<Session> threads) {
    final all = [for (final t in threads) activityOf(t.id)];
    for (final a in [SessionActivity.needsYou, SessionActivity.working, SessionActivity.unread]) {
      if (all.contains(a)) return a;
    }
    return .idle;
  }

  // The one-time review of earlier threads (decision 0014): those from before
  // chats each got a chat of their own; ones that seem to belong together are
  // suggested, never moved unasked.

  /// Threads alone in a chat nobody named that seem to belong in another chat.
  List<({Session thread, Chat into})> get suggestions {
    final chats = _chats;
    if (chats == null || settings.groupingReviewed) return const [];
    // Worked out again only when threads or chats change: the list redraws often.
    final key = Object.hashAll([
      for (final s in _sessions.sessions) Object.hash(s.id, s.chatId, s.title, s.summary),
      for (final c in chats.chats) Object.hash(c.id, c.title, c.named),
    ]);
    if (_suggestionsKey == key) return _suggestions;
    _suggestionsKey = key;
    return _suggestions = _suggest(chats);
  }

  int? _suggestionsKey;
  List<({Session thread, Chat into})> _suggestions = const [];

  List<({Session thread, Chat into})> _suggest(ChatRepository chats) {
    final out = <({Session thread, Chat into})>[];
    final moved = <String>{};
    for (final c in chats.chats) {
      final threads = chats.threadsOf(c.id);
      if (c.named || threads.length != 1) continue;
      final t = threads.single;
      final f = file('${t.title}. ${t.summary ?? ''}', chats.cards(except: c.id));
      if (f.kind != .file || f.best == null) continue;
      // Two threads that point at each other: the newer goes to the older.
      if (moved.contains(f.best)) continue;
      final into = chats.byId(f.best!);
      if (into == null) continue;
      out.add((thread: t, into: into));
      moved.add(c.id);
    }
    return out;
  }

  /// Moves the chosen suggestions; the review is done either way.
  Future<void> applySuggestions(List<({Session thread, Chat into})> chosen) async {
    final chats = _chats;
    if (chats != null) {
      for (final s in chosen) {
        final from = s.thread.chatId;
        await chats.move(s.thread, s.into.id);
        await _log?.correction(what: 'review', thread: s.thread.id, from: from, to: s.into.id);
      }
    }
    await _settings.save(settings.copyWith(groupingReviewed: true));
  }

  /// What a session's row says under its title: what it waits on, what it
  /// is doing, or how its last answer began; and the lines its changes
  /// added and removed. Read from its conversation, from disk the first
  /// time the row shows.
  ({String text, int added, int removed}) lineOf(Session s, {String about = ''}) {
    final c = _conversations.of(s.id);
    if (!c.loaded) {
      // Read, the row is drawn again with it.
      unawaited(
        _conversations.load(s.id).then((_) {
          if (!_disposed) notifyListeners();
        }),
      );
      return (text: '', added: 0, removed: 0);
    }
    var added = 0, removed = 0;
    final seen = <String>{};
    for (final i in c.items.reversed) {
      if (i is! ToolCall) continue;
      for (final d in diffsOf(i)) {
        // Each file once, at its latest change.
        if (!seen.add(d.path)) continue;
        added += d.added;
        removed += d.removed;
      }
    }
    String text;
    if (c.pendingPrompts > 0) {
      text = 'Waiting for your approval';
    } else if (c.heldUntil != null) {
      text = 'Waiting for room';
    } else if (s.hasDraft && !c.busy) {
      text = 'Draft: ${s.draft!.trim().split('\n').first}';
    } else if (c.busy) {
      final step = c.items.whereType<ToolCall>().where((t) => !t.done).lastOrNull;
      text = step == null ? 'Working' : 'Working: ${toolLabel(step.name)}';
    } else if (about.isNotEmpty) {
      // What Helmy says the chat is about, once nothing live is to say.
      text = about;
    } else {
      final last = c.items
          .whereType<AssistantText>()
          .where((a) => a.text.trim().isNotEmpty)
          .lastOrNull;
      text = last == null ? '' : _plain(last.text);
    }
    return (text: text, added: added, removed: removed);
  }

  /// What a chat's preview shows, read from what is on disk (no model is
  /// asked): its brief, its last exchanges, pictures, pages and files.
  final ShipRepository? _ship;

  /// Short facts about a chat, true now, shown as chips while its row is
  /// hovered: its topic, how many threads, its folder, its pull request,
  /// what was attached, and until when it sleeps.
  List<String> chipsOf(List<Session> threads, {DateTime? now}) {
    final latest = threads.first;
    final chat = latest.chatId == null ? null : _chats?.byId(latest.chatId!);
    final count = threads.where((x) => x.sideOf == null).length;
    final folders = {for (final x in threads) projectName(x.ownCopy ? x.repo! : x.cwd)};
    final pr = [for (final x in threads) _ship?.stateOf(x.id)?.pr].nonNulls.firstOrNull;
    var pictures = 0, files = 0;
    for (final x in threads) {
      for (final m in _conversations.of(x.id).items.whereType<UserMessage>()) {
        for (final a in m.attachments) {
          imageTypes.containsKey(a.split('.').last.toLowerCase()) ? pictures++ : files++;
        }
      }
    }
    final until = latest.snoozedUntil;
    final at = now ?? DateTime.now();
    String plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
    return [
      if (chat?.topic case final topic? when topic.isNotEmpty) topic,
      if (count > 1) plural(count, 'thread'),
      ...folders.where((f) => f != 'No project'),
      if (pr != null)
        switch (pr.state) {
          'MERGED' => 'Merged',
          'CLOSED' => 'PR closed',
          _ => 'PR #${pr.number}',
        },
      if (pictures > 0) plural(pictures, 'picture'),
      if (files > 0) plural(files, 'file'),
      if (until != null && until.isAfter(at))
        'Snoozed till ${until.day == at.day ? '' : '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][until.weekday - 1]} '}${clock(until)}',
    ];
  }

  ChatPreview previewOf(List<Session> threads) {
    final latest = threads.first;
    final chat = latest.chatId == null ? null : _chats?.byId(latest.chatId!);
    final items = _conversations.of(latest.id).items;
    final exchanges = <({String asked, String answered})>[];
    String? asked;
    for (final i in items) {
      if (i is UserMessage && i.text.trim().isNotEmpty) {
        asked = i.text.trim().split('\n').first;
      } else if (i is AssistantText && asked != null && i.text.trim().isNotEmpty) {
        exchanges.add((asked: asked, answered: _plain(i.text)));
        asked = null;
      }
    }
    final images = <String>[];
    final links = <String>{};
    final markdownImage = RegExp(r'!\[[^\]]*\]\(([^)\s]+)\)');
    final link = RegExp(r'https?://[^\s)>\]]+');
    for (final t in threads) {
      for (final i in _conversations.of(t.id).items) {
        if (i is ImageItem) images.add(i.path);
        if (i is UserMessage) {
          images.addAll(i.attachments.where(_isPicture));
        }
        if (i is AssistantText) {
          for (final m in markdownImage.allMatches(i.text)) {
            if (_isPicture(m[1]!)) images.add(m[1]!);
          }
          for (final m in link.allMatches(i.text)) {
            if (!_isPicture(m[0]!)) links.add(Uri.tryParse(m[0]!)?.host ?? m[0]!);
          }
        }
      }
    }
    final changes = lineOf(latest);
    return (
      folders: {for (final t in threads) tildePath(t.repo ?? t.cwd)}.toList(),
      threads: threads.where((t) => t.sideOf == null).length,
      brief: [
        for (final l in (chat?.brief ?? '').split('\n'))
          if (l.trim().isNotEmpty) l.trim(),
      ].take(4).toList(),
      exchanges: exchanges.reversed.take(2).toList().reversed.toList(),
      images: images.reversed.where((p) => !p.startsWith('http')).toSet().take(4).toList(),
      links: links.take(3).toList(),
      added: changes.added,
      removed: changes.removed,
    );
  }

  static bool _isPicture(String path) =>
      RegExp(r'\.(png|jpe?g|gif|webp|heic)$', caseSensitive: false).hasMatch(path);

  /// The first line of [markdown], as words: no marks, links or code.
  static String _plain(String markdown) {
    final line = markdown
        .split('\n')
        .map((l) => l.trim())
        .firstWhere(
          (l) => l.isNotEmpty && !l.startsWith('```') && !l.startsWith('|'),
          orElse: () => '',
        );
    return line
        .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '')
        .replaceAll(RegExp(r'[*_`#>]+'), '')
        .replaceAll(RegExp(r'^\s*[-+]\s+'), '')
        .trim();
  }

  void _onConversations() {
    var changed = false;
    for (final s in _sessions.sessions) {
      final c = _conversations.of(s.id);
      final a = c.pendingPrompts > 0
          ? SessionActivity.needsYou
          : c.busy
          ? SessionActivity.working
          : _attention?.isUnread(s.id) == true
          ? SessionActivity.unread
          : SessionActivity.idle;
      if (_activity[s.id] != a) {
        _activity[s.id] = a;
        changed = true;
        // Something new in a settled chat brings it back.
        if (a != .idle && isSettled(s)) unawaited(_chats!.unsettle(s.chatId!));
      }
    }
    // Stream deltas arrive many times a second; only repaint the list when a
    // status actually changes.
    if (changed) notifyListeners();
  }

  Future<Result<void>> _delete(String id) async {
    final session = _sessions.byId(id);
    await _conversations.forget(id);
    // Its own working copy goes with it, unless it holds uncommitted work;
    // its branch stays either way.
    if (session != null && session.ownCopy) {
      await _projects?.removeCopy(session.repo!, session.cwd);
    }
    return _sessions.delete(id);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _tidyTimer?.cancel();
    _firstSettle?.cancel();
    unawaited(_mergedSub?.cancel());
    _sessions.removeListener(notifyListeners);
    _settings.removeListener(notifyListeners);
    _conversations.removeListener(_onConversations);
    _attention?.removeListener(_onConversations);
    _chats?.removeListener(notifyListeners);
    _sessions.removeListener(_checkGitHub);
    super.dispose();
  }
}

/// What a chat's preview shows (see [SidebarViewModel.previewOf]).
typedef ChatPreview = ({
  List<String> folders,
  int threads,
  List<String> brief,
  List<({String asked, String answered})> exchanges,
  List<String> images,
  List<String> links,
  int added,
  int removed,
});
