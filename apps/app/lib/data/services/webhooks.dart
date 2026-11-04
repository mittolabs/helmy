import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../repositories/conversation_repository.dart';
import '../repositories/session_repository.dart';

/// Webhooks into threads: a thread given an address gets each event sent to
/// it (a pull request opened, a payment made) as a message, which its agent
/// takes up in turn. The server answers on this Mac only, on one port kept
/// across launches so addresses stay the same; an event from outside needs a
/// tunnel the person runs to it.
class Webhooks {
  Webhooks({required this._sessions, required this._conversations, this.port = defaultPort});

  final SessionRepository _sessions;
  final ConversationRepository _conversations;

  static const defaultPort = 47821;
  final int port;

  /// The largest event taken; a bigger one is turned away.
  static const maxBytes = 64 * 1024;

  /// At most this many events an hour to one thread: a sender in a loop
  /// would otherwise keep its agent busy, and its usage spent.
  static const perHour = 30;

  HttpServer? _server;
  final _seen = <String, List<DateTime>>{};

  /// Why the server is not listening, when it is not.
  String? trouble;

  bool get listening => _server != null;

  /// The address of the thread with webhook secret [secret].
  String address(String secret) => 'http://localhost:$port/hooks/$secret';

  /// A new secret for a thread's address: long, random and URL-safe.
  static String newSecret() {
    final r = Random.secure();
    return base64Url.encode([for (var i = 0; i < 24; i++) r.nextInt(256)]).replaceAll('=', '');
  }

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      trouble = null;
      _server!.listen((r) => unawaited(_handle(r)));
    } on SocketException {
      trouble =
          'Port $port on this Mac is taken by another program, so webhooks cannot be '
          'received. Quit that program, then open Helmy again.';
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest r) async {
    void answer(int code, Map<String, Object?> body) {
      r.response
        ..statusCode = code
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      unawaited(r.response.close());
    }

    final m = RegExp(r'^/hooks/([A-Za-z0-9_-]{16,})$').firstMatch(r.uri.path);
    if (m == null) return answer(404, {'error': 'No such address.'});
    if (r.method != 'POST') return answer(405, {'error': 'Send events with POST.'});
    final secret = m[1]!;
    final thread = _sessions.sessions.where((s) => s.webhook == secret).firstOrNull;
    if (thread == null) return answer(404, {'error': 'No thread has this address.'});

    final now = DateTime.now();
    final times = (_seen[secret] ??= [])
      ..removeWhere((t) => now.difference(t) > const Duration(hours: 1));
    if (times.length >= perHour) {
      return answer(429, {'error': 'More than $perHour events this hour. Try again later.'});
    }

    final bytes = <int>[];
    await for (final chunk in r) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        return answer(413, {'error': 'Events are taken up to ${maxBytes ~/ 1024} KB.'});
      }
    }
    times.add(now);
    final body = utf8.decode(bytes, allowMalformed: true);
    await _conversations.load(thread.id);
    await _conversations.send(
      thread,
      eventMessage(body, event: _eventName(r.headers)),
      from: 'a webhook',
    );
    answer(202, {'ok': true, 'thread': thread.title});
  }

  /// What the sender calls the event, when it says (GitHub, Stripe and others
  /// put it in a header).
  static String? _eventName(HttpHeaders h) =>
      h.value('x-github-event') ?? h.value('x-event-type') ?? h.value('x-webhook-event');

  /// An event as its thread reads it: what kind, and its body, as JSON laid
  /// out when it is JSON.
  static String eventMessage(String body, {String? event}) {
    var shown = body.trim();
    var lang = '';
    try {
      shown = const JsonEncoder.withIndent('  ').convert(jsonDecode(shown));
      lang = 'json';
    } on FormatException {
      // As sent.
    }
    return [
      'A webhook event arrived${event == null ? '' : ' ($event)'}. Take it up as this thread is '
          'meant to.',
      if (shown.isEmpty) '(It had no body.)' else '```$lang\n$shown\n```',
    ].join('\n\n');
  }
}
