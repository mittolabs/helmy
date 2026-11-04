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
import '../../../data/services/worktrees.dart';

enum SessionActivity { idle, working, needsYou, unread }

class SidebarViewModel extends ChangeNotifier {
  new({
    required this._sessions,
    required this._conversations,
    required this._settings,
    this._attention,
  }) {
    _attention?.addListener(_onConversations);
    _sessions.addListener(notifyListeners);
    _settings.addListener(notifyListeners);
    _conversations.addListener(_onConversations);
    create = Command0(
      () async =>
          _sessions.create(cwd: defaultFolder, level: await _settings.levelFor(defaultFolder)),
    );
    delete = Command1(_delete);
  }

  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final SettingsRepository _settings;
  final AttentionRepository? _attention;

  late final Command0<Session> create;
  late final Command1<void, String> delete;

  final Map<String, SessionActivity> _activity = {};

  List<Session> get sessions => _sessions.sessions;

  AppSettings get settings => _settings.settings;
  Future<void> updateSettings(AppSettings s) => _settings.save(s);

  /// The sessions the list shows, pinned first, in the order settings ask for.
  List<Session> get shown {
    final s = settings;
    final since = s.recency.within == null ? null : DateTime.now().subtract(s.recency.within!);
    final list = _sessions.sessions
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
    final list = shown;
    final wants = [
      for (final x in list)
        if (activityOf(x.id) case SessionActivity.needsYou || SessionActivity.unread) x,
    ];
    final working = [
      for (final x in list)
        if (activityOf(x.id) == SessionActivity.working) x,
    ];
    final rest = [
      for (final x in list)
        if (!wants.contains(x) && !working.contains(x)) x,
    ];
    final out = <({String? label, String? folder, List<Session> sessions})>[
      if (wants.isNotEmpty) (label: 'Needs you', folder: null, sessions: wants),
      if (working.isNotEmpty) (label: 'Working', folder: null, sessions: working),
    ];
    if (settings.group == .none) {
      if (rest.isNotEmpty || out.isEmpty) {
        out.add((label: out.isEmpty ? null : 'Everything else', folder: null, sessions: rest));
      }
      return out;
    }
    final byFolder = <String, List<Session>>{};
    for (final x in rest) {
      byFolder.putIfAbsent(x.cwd, () => []).add(x);
    }
    return [
      ...out,
      for (final e in byFolder.entries) (label: null, folder: e.key, sessions: e.value),
    ];
  }

  /// Every session in the order the list shows them, for ⌘1 to ⌘9.
  List<Session> get inOrder => [for (final g in groups) ...g.sessions];

  bool isUnread(String id) => _attention?.isUnread(id) == true;

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
    for (final s in _sessions.sessions) (s, await _conversations.searchText(s.id)),
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
  static DateTime tomorrowMorning([DateTime? from]) {
    final now = from ?? DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 9);
  }

  Future<void> setPinned(Session s, bool pinned) => _sessions.save(s.copyWith(pinned: pinned));

  Future<void> setArchived(Session s, bool archived) {
    lastArchived = archived ? s : null;
    return _sessions.save(s.copyWith(archived: archived, pinned: archived ? false : null));
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
      await Worktrees().remove(session.repo!, session.cwd);
    }
    return _sessions.delete(id);
  }

  @override
  void dispose() {
    _sessions.removeListener(notifyListeners);
    _settings.removeListener(notifyListeners);
    _conversations.removeListener(_onConversations);
    _attention?.removeListener(_onConversations);
    super.dispose();
  }
}
