import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../domain/models/chat.dart';
import '../../../domain/models/chat_item.dart';
import 'remote_crypto.dart';

/// A thread as a phone sees it: enough for its row and its state.
typedef RemoteThread = ({
  String id,
  String title,
  String cwd,
  DateTime updatedAt,
  bool archived,
  bool busy,
  bool needsYou,
  DateTime? heldUntil,
  String last,
});

/// A chat as a phone sees it, its threads newest first.
typedef RemoteChat = ({Chat chat, List<RemoteThread> threads});

/// One conversation as a phone has it: what was said, and whether it works.
class RemoteConversation {
  final List<ChatItem> items = [];
  bool busy = false;
  DateTime? heldUntil;
}

enum LinkState { connecting, connected, unreachable }

/// A phone's line to Helmy on a Mac (see [RemoteServer]): the chats there,
/// the conversations it has open, and what it asks of them. Reconnects by
/// itself, trying each of the Mac's addresses.
class RemoteLink extends ChangeNotifier {
  RemoteLink(this.pairing) : _sealer = Sealer(pairing.key);

  final Pairing pairing;
  final Sealer _sealer;

  LinkState state = LinkState.connecting;

  /// Why it is not connected, in words; null while connected or trying.
  String? trouble;

  List<RemoteChat> chats = const [];
  final _conversations = <String, RemoteConversation>{};

  WebSocket? _ws;
  Timer? _retry;
  var _attempt = 0;
  bool _closed = false;

  /// The ids opened, to open again after a reconnect.
  final _open = <String>{};

  /// A chat made on the Mac at the phone's asking, for the screen to open.
  final made = ValueNotifier<String?>(null);

  RemoteConversation of(String id) => _conversations.putIfAbsent(id, RemoteConversation.new);

  Future<void> connect() async {
    _retry?.cancel();
    state = LinkState.connecting;
    notifyListeners();
    for (final host in pairing.hosts) {
      try {
        final ws = await WebSocket.connect('ws://$host:${pairing.port}/ws')
            .timeout(const Duration(seconds: 4));
        _ws = ws;
        _attempt = 0;
        ws.listen(
          (data) => unawaited(_receive(data)),
          onDone: _lost,
          onError: (_) => _lost(),
          cancelOnError: true,
        );
        await _send({'type': 'hello'});
        for (final id in _open) {
          await _send({'type': 'open', 'id': id});
        }
        return;
      } on Object {
        // The next address.
      }
    }
    _lost(unreachable: true);
  }

  void _lost({bool unreachable = false}) {
    _ws = null;
    if (_closed) return;
    state = LinkState.unreachable;
    trouble = unreachable
        ? "Can't reach ${pairing.name}. It needs Helmy open with the phone turned on in "
              'Settings, on the same Wi-Fi as this phone, or on Tailscale.'
        : 'The connection to ${pairing.name} dropped.';
    notifyListeners();
    // Again soon, then less often: 2, 4, 8, up to 30 seconds.
    final wait = Duration(seconds: (2 << _attempt.clamp(0, 4)).clamp(2, 30));
    _attempt++;
    _retry = Timer(wait, () => unawaited(connect()));
  }

  Future<void> _send(Map<String, Object?> m) async {
    final ws = _ws;
    if (ws == null) return;
    ws.add(await _sealer.seal(m));
  }

  Future<void> _receive(Object? data) async {
    final m = data is String ? await _sealer.open(data) : null;
    if (m == null) return;
    if (state != LinkState.connected) {
      state = LinkState.connected;
      trouble = null;
    }
    switch (m['type']) {
      case 'state':
        chats = [
          for (final j in (m['chats'] as List? ?? const []).whereType<Map>())
            (
              chat: Chat.fromJson(j.cast()),
              threads: [
                for (final t in (j['threads'] as List? ?? const []).whereType<Map>())
                  _thread(t.cast()),
              ],
            ),
          for (final t in (m['loose'] as List? ?? const []).whereType<Map>())
            (
              chat: Chat(id: '${t['id']}', title: '${t['title']}', createdAt: DateTime.now()),
              threads: [_thread(t.cast())],
            ),
        ];
      case 'conversation':
        final c = of('${m['id']}');
        final from = (m['from'] as num?)?.toInt() ?? 0;
        if (from <= c.items.length) c.items.removeRange(from, c.items.length);
        c.items.addAll([
          for (final j in (m['items'] as List? ?? const []).whereType<Map>())
            ChatItem.fromJson(j.cast()),
        ]);
        c.busy = m['busy'] == true;
        c.heldUntil = DateTime.tryParse('${m['heldUntil'] ?? ''}');
      case 'made':
        made.value = '${m['id']}';
    }
    notifyListeners();
  }

  static RemoteThread _thread(Map<String, Object?> t) => (
    id: '${t['id']}',
    title: '${t['title'] ?? ''}',
    cwd: '${t['cwd'] ?? ''}',
    updatedAt: DateTime.tryParse('${t['updatedAt']}') ?? DateTime.now(),
    archived: t['archived'] == true,
    busy: t['busy'] == true,
    needsYou: t['needsYou'] == true,
    heldUntil: DateTime.tryParse('${t['heldUntil'] ?? ''}'),
    last: '${t['last'] ?? ''}',
  );

  /// Follows [id]'s conversation as it goes.
  Future<void> open(String id) async {
    _open.add(id);
    await _send({'type': 'open', 'id': id});
  }

  Future<void> close(String id) async {
    _open.remove(id);
    await _send({'type': 'close', 'id': id});
  }

  Future<void> send(String id, String text) => _send({'type': 'send', 'id': id, 'text': text});

  /// Answers [prompt] in [id]: 'allow', 'allowForSession' or 'deny'.
  Future<void> answer(String id, PermissionPrompt prompt, String answer) =>
      _send({'type': 'answer', 'id': id, 'request': prompt.requestId, 'answer': answer});

  Future<void> interrupt(String id) => _send({'type': 'interrupt', 'id': id});

  /// A new chat on the Mac, starting with [text]; [made] says its id.
  Future<void> newChat(String text) => _send({'type': 'new', 'text': text});

  @override
  void dispose() {
    _closed = true;
    _retry?.cancel();
    unawaited(_ws?.close());
    made.dispose();
    super.dispose();
  }
}
