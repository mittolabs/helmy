import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../repositories/conversation_repository.dart';
import '../repositories/session_repository.dart';

/// A change to a chat app: its state, set by the user in the app (on the
/// Mac or a phone) or by the agent; or, with [page], the app made again.
typedef AppChange = ({String session, String path, Object? state, bool page});

/// Where chat apps live: Helmy's own folder, one folder per chat thread.
const appsFolder = 'com.mittolabs.helmy/apps';

/// Whether [where], as an answer shows it, is a chat app.
bool isChatApp(String where) {
  final w = where.trim();
  return w.contains('/$appsFolder/') && w.endsWith('.html');
}

/// Chat apps: small pages an agent makes for the user to play or use right
/// in the chat (a game against the agent, a quiz, a checklist). Each keeps
/// its state with the chat, so it comes back as it was after scrolling
/// away, a restart, or on the phone; and the agent reads and sets that
/// state, so it plays its own moves.
abstract class ChatApps {
  /// The app's page; null when it is not one of [session]'s apps.
  Future<String?> page(String session, String path);

  /// What the app last saved; null when nothing has been.
  Future<Object?> state(String session, String path);

  /// Keeps what the app saved, and tells every view of it.
  Future<void> save(String session, String path, Object? state);

  /// What the app says to the chat, sent as the user's message.
  Future<void> say(String session, String text);

  Stream<AppChange> get changes;
}

/// On this Mac: pages and states as files in [appsFolder].
class ChatAppsLocal implements ChatApps {
  ChatAppsLocal({
    required this._appData,
    required this._sessions,
    required this._conversations,
  });

  final Future<Directory> Function() _appData;
  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final _changes = StreamController<AppChange>.broadcast();

  late final Future<String> _root = _appData().then((d) => '${d.path}/apps');

  @override
  Stream<AppChange> get changes => _changes.stream;

  /// Makes (or makes again) [session]'s app called [name] from [html],
  /// starting from [state]; its path.
  Future<String> make(String session, String name, String html, {Object? state}) async {
    var slug = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) slug = 'app';
    final dir = Directory('${await _root}/${_safe(session)}');
    await dir.create(recursive: true);
    final path = '${dir.path}/$slug.html';
    await File(path).writeAsString(html);
    await _write(path, state);
    _changes.add((session: session, path: path, state: state, page: true));
    return path;
  }

  /// [session]'s own apps only: a phone or a page cannot reach other files.
  Future<bool> _ours(String session, String path) async =>
      path.endsWith('.html') &&
      !path.contains('..') &&
      path.startsWith('${await _root}/${_safe(session)}/') &&
      File(path).existsSync();

  static String _safe(String session) => session.replaceAll(RegExp('[^A-Za-z0-9_-]'), '');

  static File _stateFile(String path) => File(path.replaceFirst(RegExp(r'\.html$'), '.state.json'));

  Future<void> _write(String path, Object? state) async {
    final f = _stateFile(path);
    if (state == null) {
      if (f.existsSync()) await f.delete();
    } else {
      // Whole or not at all: a read while it is written finds the last one.
      final next = File('${f.path}.next');
      await next.writeAsString(jsonEncode(state));
      await next.rename(f.path);
    }
  }

  @override
  Future<String?> page(String session, String path) async =>
      await _ours(session, path) ? File(path).readAsString() : null;

  @override
  Future<Object?> state(String session, String path) async {
    if (!await _ours(session, path)) return null;
    final f = _stateFile(path);
    if (!f.existsSync()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(String session, String path, Object? state) async {
    if (!await _ours(session, path)) return;
    await _write(path, state);
    _changes.add((session: session, path: path, state: state, page: false));
  }

  /// Whether [path] is one of [session]'s apps.
  Future<bool> has(String session, String path) => _ours(session, path);

  @override
  Future<void> say(String session, String text) async {
    final s = _sessions.byId(session);
    final t = text.trim();
    if (s == null || t.isEmpty) return;
    await _conversations.send(s, t);
  }

  Future<void> dispose() => _changes.close();
}
