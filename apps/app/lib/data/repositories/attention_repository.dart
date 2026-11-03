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
/// happens out of sight, and keeps the dock badge at their count.
class AttentionRepository extends ChangeNotifier with WidgetsBindingObserver {
  new({
    required this._conversations,
    required this._sessions,
    required this._settings,
    required this._notify,
  }) {
    _conversations.addListener(_check);
    WidgetsBinding.instance.addObserver(this);
  }

  final ConversationRepository _conversations;
  final SessionRepository _sessions;
  final SettingsRepository _settings;
  final NotifyService _notify;

  final Map<String, bool> _wasBusy = {};
  final Map<String, int> _wasWaiting = {};
  final Set<String> _unread = {};
  String? _viewing;
  bool _active = true;

  /// Finished while the user was elsewhere, and not opened since.
  bool isUnread(String sessionId) => _unread.contains(sessionId);

  /// Clears [sessionId]'s unread mark without opening it.
  void markRead(String sessionId) {
    if (_unread.remove(sessionId)) _changed();
  }

  /// The session on screen, or null.
  set viewing(String? sessionId) {
    _viewing = sessionId;
    if (sessionId != null && _unread.remove(sessionId)) _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active && _viewing != null && _unread.remove(_viewing)) _changed();
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
    _send(sessionId, title, failed ? 'Stopped: ${_short(last)}' : 'Finished');
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

  void _send(String sessionId, String title, String body) {
    if (!_settings.settings.notify) return;
    _notify.notify(sessionId: sessionId, title: title, body: body);
  }

  void _changed() {
    final waiting = _sessions.sessions.where((s) => _conversations.of(s.id).pendingPrompts > 0);
    final count = {..._unread, for (final s in waiting) s.id}.length;
    _notify.badge(_settings.settings.notify ? count : 0);
    notifyListeners();
  }

  @override
  void dispose() {
    _conversations.removeListener(_check);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
