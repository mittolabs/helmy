import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../domain/models/chat_item.dart';
import '../../../domain/models/session.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/conversation_repository.dart';
import '../../repositories/session_repository.dart';
import '../engines/agent_engine.dart';
import '../../../utils/result.dart';
import 'remote_crypto.dart';
import 'screen_source.dart';

/// Helmy on this Mac, reachable from a paired phone: its chats, each one's
/// conversation as it goes, and sending, approving and stopping. One
/// WebSocket per phone; every message sealed with the pairing's key, so a
/// phone that has not paired can neither read nor ask anything.
///
/// The work stays here: the phone only shows it and says what to do.
class RemoteServer {
  RemoteServer({
    required this._sessions,
    required this._conversations,
    this._chats,
    this.port = defaultPort,
    this._screen,
  }) {
    _screen?.onFrame = _onFrame;
    _screen?.onStopped = _onScreenStopped;
  }

  /// This Mac's screen, for phones to see and use; null where it cannot be.
  final ScreenSource? _screen;

  /// Whether paired phones may see and use this Mac's screen, as Settings
  /// says.
  bool Function() screenAllowed = () => true;

  /// A phone's own key, by its id; null for one not paired (or turned
  /// away). Set by whoever keeps the phones.
  String? Function(String device) keyOf = (_) => null;

  /// A phone said hello: its id and the name it goes by.
  void Function(String device, String name)? onHello;

  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final ChatRepository? _chats;
  final int port;

  static const defaultPort = 47823;

  HttpServer? _server;
  Sealer? _sealer;
  final _clients = <_Client>[];

  bool get running => _server != null;

  /// How many phones are connected now.
  int get connected => _clients.length;

  /// Listens on every address of this Mac, sealing with [key].
  Future<void> start(String key) async {
    if (_server != null) await stop();
    _sealer = Sealer(key);
    final server = _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _sessions.addListener(_onState);
    _chats?.addListener(_onState);
    _conversations.addListener(_onConversations);
    server.listen((req) async {
      if (req.uri.path != '/ws' || !WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      // A phone with its own key says which it is; one paired before has
      // the shared key.
      final device = req.uri.queryParameters['d'];
      final own = device == null ? null : keyOf(device);
      if (device != null && own == null) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(req);
      ws.pingInterval = const Duration(seconds: 20);
      final client = _Client(ws, device: device, sealer: own == null ? null : Sealer(own));
      ws.listen(
        (data) => unawaited(_receive(client, data)),
        onDone: () => _gone(client),
        onError: (_) => _gone(client),
        cancelOnError: true,
      );
    });
  }

  Future<void> stop() async {
    _sessions.removeListener(_onState);
    _chats?.removeListener(_onState);
    _conversations.removeListener(_onConversations);
    for (final c in [..._clients]) {
      await c.ws.close();
    }
    _clients.clear();
    await _stopScreen();
    await _server?.close(force: true);
    _server = null;
  }

  /// This Mac's addresses a phone can reach: the local network's and
  /// Tailscale's, loopback left out.
  static Future<List<String>> addresses() async {
    final out = <String>[];
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in i.addresses) {
        if (!a.isLoopback) out.add(a.address);
      }
    }
    // Tailscale's (100.64.0.0/10) last: the local network is faster when both work.
    out.sort((a, b) => (a.startsWith('100.') ? 1 : 0).compareTo(b.startsWith('100.') ? 1 : 0));
    return out;
  }

  /// Turns phone [device] away now: its connections close.
  Future<void> drop(String device) async {
    for (final c in [..._clients.where((c) => c.device == device)]) {
      _gone(c);
      await c.ws.close(WebSocketStatus.policyViolation, 'unpaired');
    }
  }

  /// The phones connected now, by id (null for one paired before).
  Set<String?> get connectedDevices => {for (final c in _clients) c.device};

  Future<void> _send(_Client c, Map<String, Object?> message) async {
    final s = c.sealer ?? _sealer;
    if (s == null) return;
    try {
      c.ws.add(await s.seal(message));
    } on Object {
      _clients.remove(c);
    }
  }

  Future<void> _receive(_Client c, Object? data) async {
    final m = data is String ? await (c.sealer ?? _sealer)?.open(data) : null;
    if (m == null) {
      // Not sealed with this pairing's key: not a paired phone.
      await c.ws.close(WebSocketStatus.policyViolation, 'not paired');
      _clients.remove(c);
      return;
    }
    if (!c.paired) {
      c.paired = true;
      _clients.add(c);
    }
    final id = '${m['id'] ?? ''}';
    switch (m['type']) {
      case 'hello':
        c.name = '${m['name'] ?? ''}';
        if (c.device case final d?) onHello?.call(d, c.name);
        await _send(c, _state());
      case 'open':
        c.open.add(id);
        await _conversations.load(id);
        await _send(c, _conversation(id, from: 0));
      case 'close':
        c.open.remove(id);
      case 'send':
        final s = _sessions.byId(id);
        final text = '${m['text'] ?? ''}'.trim();
        if (s != null && text.isNotEmpty) await _conversations.send(s, text);
      case 'answer':
        final p = _conversations
            .of(id)
            .items
            .whereType<PermissionPrompt>()
            .where((p) => p.requestId == m['request'])
            .firstOrNull;
        final answer = PermissionAnswer.values.asNameMap()[m['answer']];
        if (p != null && answer != null) _conversations.answerPermission(id, p, answer);
      case 'question':
        final p = _conversations
            .of(id)
            .items
            .whereType<PermissionPrompt>()
            .where((p) => p.requestId == m['request'])
            .firstOrNull;
        if (p == null || m['answers'] is! Map) return;
        p.answers
          ..clear()
          ..addAll((m['answers'] as Map).map((k, v) => MapEntry('$k', '$v')));
        _conversations.answerQuestion(id, p);
      case 'interrupt':
        _conversations.interrupt(id);
      case 'screen':
        await (m['on'] == true ? _watch(c) : _unwatch(c));
      case 'got':
        c.awaiting = false;
        _askFrame();
      case 'input':
        final screen = _screen;
        if (!c.watching || screen == null || m['input'] is! Map) return;
        final wrong = await screen.input((m['input'] as Map).cast());
        if (wrong != null) await _send(c, {'type': 'screen', 'on': true, 'trouble': _says(wrong)});
      case 'new':
        final cwd = _sessions.sessions.where((s) => s.sideOf == null).firstOrNull?.cwd;
        final made = await _sessions.create(cwd: '${m['cwd'] ?? cwd ?? Directory.current.path}');
        if (made case Ok(value: final s)) {
          await _send(c, {'type': 'made', 'id': s.id, 'ask': m['ask']});
          final text = '${m['text'] ?? ''}'.trim();
          if (text.isNotEmpty) await _conversations.send(s, text);
        }
    }
  }

  /// Every chat and its threads, for the phone's list.
  Map<String, Object?> _state() {
    final chats = _chats;
    return {
      'type': 'state',
      'chats': [
        for (final c in chats?.chats ?? const [])
          {
            ...c.toJson(),
            'threads': [for (final t in chats!.threadsOf(c.id)) _thread(t)],
          },
      ],
      // Threads in no chat (no chats here): each its own row.
      'loose': [
        for (final s in _sessions.sessions)
          if (s.sideOf == null && (s.chatId == null || chats?.byId(s.chatId!) == null)) _thread(s),
      ],
    };
  }

  Map<String, Object?> _thread(Session s) {
    final c = _conversations.of(s.id);
    final last = c.items
        .whereType<AssistantText>()
        .where((a) => a.text.trim().isNotEmpty)
        .lastOrNull;
    return {
      'id': s.id,
      'title': s.title,
      'cwd': s.cwd,
      'updatedAt': s.updatedAt.toIso8601String(),
      'archived': s.archived,
      'busy': c.busy,
      'needsYou': c.pendingPrompts > 0,
      'heldUntil': c.heldUntil?.toIso8601String(),
      'last': last == null ? '' : last.text.trim().split('\n').first,
    };
  }

  /// [id]'s conversation from item [from] on: all of it when a phone opens
  /// it, then what changed at its end as it goes.
  Map<String, Object?> _conversation(String id, {required int from}) {
    final c = _conversations.of(id);
    return {
      'type': 'conversation',
      'id': id,
      'from': from,
      'items': [for (final i in c.items.skip(from)) i.toJson()],
      'busy': c.busy,
      'heldUntil': c.heldUntil?.toIso8601String(),
    };
  }

  /// A phone gone: no longer watching either.
  void _gone(_Client c) {
    _clients.remove(c);
    if (c.watching) unawaited(_unwatch(c));
  }

  Iterable<_Client> get _watchers => _clients.where((c) => c.watching);

  /// What went wrong with the screen, as the phone shows it.
  static String _says(String why) => switch (why) {
    'off' => "Showing this Mac is turned off, in Helmy's Settings, under Phone, on the Mac.",
    'record' =>
      'Helmy on the Mac needs the Screen Recording permission. On the Mac, open System '
          'Settings, Privacy & Security, Screen & System Audio Recording, and turn Helmy on.',
    'accessibility' =>
      'You can see the Mac, but Helmy there needs the Accessibility permission to click and '
          'type. On the Mac, open System Settings, Privacy & Security, Accessibility, and turn '
          'Helmy on.',
    final other => other,
  };

  Future<void> _watch(_Client c) async {
    final screen = _screen;
    if (screen == null || !screenAllowed()) {
      await _send(c, {
        'type': 'screen',
        'on': false,
        'trouble': _says(screen == null ? 'This computer cannot share its screen.' : 'off'),
      });
      return;
    }
    final names = {..._watchers.map((w) => w.name), c.name}.where((n) => n.isNotEmpty).toList();
    final who = names.isEmpty ? 'A phone' : names.join(' and ');
    final wrong = await screen.start(
      mark: '$who ${names.length > 1 ? 'are' : 'is'} viewing this screen',
    );
    if (wrong != null) {
      await _send(c, {'type': 'screen', 'on': false, 'trouble': _says(wrong)});
      return;
    }
    c
      ..watching = true
      ..awaiting = false;
    await _send(c, {'type': 'screen', 'on': true});
    _askFrame();
  }

  Future<void> _unwatch(_Client c) async {
    c
      ..watching = false
      ..awaiting = false;
    if (_watchers.isEmpty) await _stopScreen();
  }

  Future<void> _stopScreen() async {
    _frameLate?.cancel();
    await _screen?.stop();
  }

  Timer? _frameLate;

  /// The next frame, once every phone watching has the last one; a phone
  /// that has not said so in two seconds is not waited for.
  void _askFrame() {
    if (_watchers.isEmpty || _watchers.any((w) => w.awaiting)) return;
    _frameLate?.cancel();
    _screen?.next();
  }

  Future<void> _onFrame(Uint8List jpeg) async {
    for (final c in [..._watchers.where((w) => !w.awaiting)]) {
      final s = c.sealer ?? _sealer;
      if (s == null) continue;
      c.awaiting = true;
      try {
        c.ws.add(await s.sealBytes(jpeg));
      } on Object {
        _gone(c);
      }
    }
    _frameLate?.cancel();
    _frameLate = Timer(const Duration(seconds: 2), () {
      for (final c in _watchers) {
        c.awaiting = false;
      }
      _askFrame();
    });
  }

  /// Ends every phone's view of the screen: turned off in Settings.
  Future<void> endScreen() async {
    if (_watchers.isEmpty) return;
    _onScreenStopped('off');
    await _stopScreen();
  }

  void _onScreenStopped(String why) {
    for (final c in [..._watchers]) {
      c
        ..watching = false
        ..awaiting = false;
      unawaited(
        _send(c, {
          'type': 'screen',
          'on': false,
          'trouble': switch (why) {
            'mark' => 'Sharing was stopped on the Mac.',
            'off' => _says('off'),
            _ => 'Sharing stopped on the Mac: $why',
          },
        }),
      );
    }
    _frameLate?.cancel();
  }

  Timer? _stateLater;

  void _onState() {
    // Many changes come together (a save per field): one message for them.
    _stateLater?.cancel();
    _stateLater = Timer(const Duration(milliseconds: 250), () {
      final m = _state();
      for (final c in [..._clients]) {
        unawaited(_send(c, m));
      }
    });
  }

  Timer? _convLater;

  void _onConversations() {
    _onState();
    // Streaming answers change many times a second: at most four a second
    // to each phone, each the end that changed.
    _convLater ??= Timer(const Duration(milliseconds: 250), () {
      _convLater = null;
      for (final c in [..._clients]) {
        for (final id in c.open) {
          final n = _conversations.of(id).items.length;
          final sent = c.sent[id] ?? 0;
          // The last few again too: the latest answer grows, and an
          // approval near the end can be answered.
          final from = (sent < n ? sent : n) - 3;
          c.sent[id] = n;
          unawaited(_send(c, _conversation(id, from: from < 0 ? 0 : from)));
        }
      }
    });
  }
}

class _Client {
  _Client(this.ws, {this.device, this.sealer});
  final WebSocket ws;

  /// Which phone, and its own key's sealer; both null for one paired before.
  final String? device;
  final Sealer? sealer;
  bool paired = false;

  /// What it calls itself, from its hello.
  String name = '';

  /// Whether it is watching the screen, and has a frame it has not yet
  /// said it got.
  bool watching = false;
  bool awaiting = false;

  /// The conversations it has open, and how many items it was sent of each.
  final open = <String>{};
  final sent = <String, int>{};
}
