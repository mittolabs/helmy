import 'dart:async';

import '../../domain/helmy_voice.dart';

import 'package:flutter/widgets.dart';

import '../../domain/models/chat_item.dart';
import '../services/notify_service.dart';
import 'conversation_repository.dart';
import 'session_repository.dart';
import 'settings_repository.dart';

/// What needs the user: sessions waiting for an approval, and sessions that
/// finished while the user was not looking. Sends a notification when either
/// happens out of sight, keeps the dock badge at their count, and shows in
/// the Dock the face that fits what Helmy is doing.
class AttentionRepository extends ChangeNotifier with WidgetsBindingObserver {
  new({
    required this._conversations,
    required this._sessions,
    required this._settings,
    required this._notify,
  }) {
    _conversations.addListener(_check);
    _inSightChanges = _notify.inSight.listen(_onInSight);
    _sessions.addListener(_planWake);
    WidgetsBinding.instance.addObserver(this);
    _planWake();
    // Just opened: Helmy waking up, unless something needs showing first.
    _wakingUp = Timer(wakingFor, _showFace);
    _showFace();
  }

  /// How long the Dock shows Helmy waking up after the app opens.
  static const wakingFor = Duration(seconds: 3);
  Timer? _wakingUp;

  final ConversationRepository _conversations;
  final SessionRepository _sessions;
  final SettingsRepository _settings;
  final NotifyService _notify;

  final Map<String, bool> _wasBusy = {};
  final Map<String, int> _wasWaiting = {};
  final Set<String> _unread = {};
  String? _viewing;
  bool _active = true;
  String? _face;
  Timer? _dozing;
  StreamSubscription<bool>? _inSightChanges;
  Timer? _wake;
  DateTime? _wakeAt;

  /// Nothing asked of Helmy for this long, and it dozes off in the Dock.
  static const dozeAfter = Duration(minutes: 30);

  /// Finished while the user was elsewhere, and not opened since.
  bool isUnread(String sessionId) => _unread.contains(sessionId);

  /// Clears [sessionId]'s unread mark without opening it.
  void markRead(String sessionId) => _seen(sessionId);

  /// Wakes snoozed sessions that are due, as needing you, and sets a timer
  /// for the next one.
  void _planWake() {
    final now = DateTime.now();
    DateTime? next;
    for (final s in _sessions.sessions) {
      final until = s.snoozedUntil;
      if (until == null) continue;
      if (!until.isAfter(now)) {
        _unread.add(s.id);
        unawaited(_sessions.save(s.copyWith(wake: true)));
        _changed();
      } else if (next == null || until.isBefore(next)) {
        next = until;
      }
    }
    if (next == _wakeAt) return;
    _wake?.cancel();
    _wakeAt = next;
    _wake = next == null
        ? null
        : Timer(next.difference(now), () {
            _wakeAt = null;
            _planWake();
          });
  }

  /// The session on screen, or null.
  set viewing(String? sessionId) {
    _viewing = sessionId;
    if (sessionId != null) _seen(sessionId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active && _viewing != null) _seen(_viewing!);
  }

  /// The window came into sight (or went out of it): the session on screen
  /// is seen. Hiding and showing the window may never change whether the app
  /// is the active one, so this, not the app's state, is what counts.
  void _onInSight(bool inSight) {
    _active = inSight;
    if (inSight && _viewing != null) _seen(_viewing!);
  }

  /// [sessionId] is seen: no longer unread, out of the count, and its
  /// notification gone from the system's list.
  void _seen(String sessionId) {
    unawaited(_notify.clearNotification(sessionId));
    if (_unread.remove(sessionId)) _changed();
  }

  void _check() {
    for (final s in _sessions.sessions) {
      final c = _conversations.of(s.id);
      final busy = c.busy;
      final waiting = c.pendingPrompts;
      final wasBusy = _wasBusy[s.id] ?? false;
      final wasWaiting = _wasWaiting[s.id] ?? 0;
      _wasBusy[s.id] = busy;
      _wasWaiting[s.id] = waiting;

      if (waiting > wasWaiting) unawaited(_waiting(s.id, s.title));
      if (wasBusy && !busy) unawaited(_finished(s.id, s.title));
    }
    _showFace();
  }

  /// The face for the most pressing thing across every session: one waiting
  /// on you, then work under way, then work left to read.
  String? faceNow() {
    final all = [for (final s in _sessions.sessions) _conversations.of(s.id)];
    if (all.any((c) => c.pendingPrompts > 0)) return 'needs-you';
    final busy = all.where((c) => c.busy);
    if (busy.isNotEmpty) return busy.any((c) => !c.thinking) ? 'answering' : 'thinking';
    final background = all.any(
      (c) => c.items.whereType<ToolCall>().any((t) => t.background?.status == .running),
    );
    if (background) return 'background';
    final unread = [for (final id in _unread) _conversations.of(id).items.lastOrNull];
    if (unread.any((last) => last is TurnSummary && !last.ok || last is Notice)) return 'error';
    if (unread.isNotEmpty) return 'done';
    // Idle, and only the model on this Mac could answer the last message.
    if (_conversations.onlyThisMac ?? false) return 'offline';
    return null;
  }

  void _showFace() {
    final idle = faceNow();
    final face = idle == null || idle == 'offline'
        ? (_wakingUp?.isActive ?? false ? 'waking' : idle)
        : idle;
    if (face != null && face != 'offline' && face != 'waking') {
      _dozing?.cancel();
      _dozing = null;
      _setFace(face);
    } else if (face == 'waking') {
      _setFace(face);
    } else if (_face != 'dozing') {
      // Idle: the app icon (or offline), and dozing once nothing has been
      // asked for a while.
      _setFace(face);
      _dozing ??= Timer(dozeAfter, () => _setFace('dozing'));
    }
  }

  void _setFace(String? face) {
    if (face == _face) return;
    _face = face;
    unawaited(_notify.face(face));
  }

  /// Flutter's own idea of whether the app is in front can be wrong (an app
  /// opened in the background), so macOS is asked when it matters.
  Future<bool> _inSightNow(String sessionId) async {
    final active = await _notify.isActive() ?? _active;
    final inSight = active && _viewing == sessionId;
    return inSight;
  }

  Future<void> _waiting(String sessionId, String title) async {
    if (await _inSightNow(sessionId)) return;
    final c = _conversations.of(sessionId);
    final prompt = c.items
        .whereType<PermissionPrompt>()
        .where((p) => p.decision == .pending)
        .lastOrNull;
    if (prompt == null) return;
    _send(
      sessionId,
      title,
      prompt.isQuestion ? 'Has a question for you' : 'Waiting for your approval',
    );
    _changed();
  }

  Future<void> _finished(String sessionId, String title) async {
    if (await _inSightNow(sessionId)) return;
    _unread.add(sessionId);
    final last = _conversations.of(sessionId).items.lastOrNull;
    final failed = last is TurnSummary && !last.ok || last is Notice;
    _send(sessionId, title, failed ? 'Stopped: ${_short(last)}' : 'Finished', thumbsUp: !failed);
    _changed();
  }

  static String _short(ChatItem? item) {
    final text = switch (item) {
      TurnSummary(:final error) => inHelmysWords(error),
      Notice(:final text) => text,
      _ => 'something went wrong',
    };
    return text.length > 120 ? '${text.substring(0, 117)}...' : text;
  }

  void _send(String sessionId, String title, String body, {bool thumbsUp = false}) {
    if (!_settings.settings.notify) return;
    _notify.notify(sessionId: sessionId, title: title, body: body, thumbsUp: thumbsUp);
  }

  void _changed() {
    final waiting = _sessions.sessions.where((s) => _conversations.of(s.id).pendingPrompts > 0);
    final count = {..._unread, for (final s in waiting) s.id}.length;
    _notify.badge(_settings.settings.notify ? count : 0);
    _showFace();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_inSightChanges?.cancel());
    _dozing?.cancel();
    _wakingUp?.cancel();
    _wake?.cancel();
    _sessions.removeListener(_planWake);
    _conversations.removeListener(_check);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
