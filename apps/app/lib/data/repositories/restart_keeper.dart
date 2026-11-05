import 'dart:async';

import '../../utils/result.dart';
import '../services/storage_service.dart';
import 'conversation_repository.dart';
import 'session_repository.dart';

/// Chats at work when Helmy closed (quit, an update, a crash, a restart of
/// the computer) carry on when it opens again. Which sessions are working is
/// written down as it changes; what was written when Helmy last ran is read
/// at the start, and each of those sessions is asked to pick up where it
/// stopped.
class RestartKeeper {
  RestartKeeper(this._storage, this._sessions, this._conversations, {bool Function()? enabled})
    : _enabled = enabled ?? (() => true);

  final StorageService _storage;
  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final bool Function() _enabled;

  static const _file = 'working.json';

  /// What a session is told, carrying on.
  static const carryOn =
      'Helmy closed while you were working on this. Carry on from where you stopped; '
      'check what was already done before doing it again.';

  Set<String> _written = const {};

  /// The sessions that were working when Helmy last closed, and carries
  /// them on; then keeps the list as work starts and stops. The sessions
  /// carried on.
  Future<List<String>> start() async {
    final before = await _storage.read(_file);
    _conversations.addListener(_save);
    final ids = [for (final id in (before is List ? before : const []).whereType<String>()) id];
    await _storage.write(_file, const <String>[]);
    if (!_enabled()) return const [];
    final carried = <String>[];
    for (final id in ids) {
      final s = _sessions.byId(id);
      if (s == null || s.archived) continue;
      await _conversations.load(id);
      final r = await _conversations.send(s, carryOn, from: 'Helmy, after a restart');
      if (r is Ok) carried.add(id);
    }
    return carried;
  }

  void _save() {
    final now = {
      for (final s in _sessions.sessions)
        if (_conversations.of(s.id).busy) s.id,
    };
    if (now.length == _written.length && now.containsAll(_written)) return;
    _written = now;
    unawaited(_storage.write(_file, now.toList()));
  }

  void dispose() => _conversations.removeListener(_save);
}
