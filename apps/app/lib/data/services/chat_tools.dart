import '../repositories/chat_keeper.dart';
import '../repositories/chat_repository.dart';
import '../repositories/conversation_repository.dart';
import '../repositories/session_repository.dart';
import '../../utils/result.dart';
import '../../domain/models/session.dart';
import 'turn_log.dart';

/// The agent's way into the rest of its chat (decision `0014`), cheapest
/// first: the other threads' one-line summaries, then one thread's words,
/// only the parts that match when that is enough. Each lookup is logged
/// with its rung. And its way to the other threads' agents: a message to
/// one, or a new thread started, each labelled as from this thread.
class ChatTools {
  ChatTools({
    required this._sessions,
    required this._chats,
    required this._conversations,
    this._log,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Messages between threads, by sender and receiver, when sent: two
  /// agents can keep each other busy without end, so the pair is held to
  /// [pairLimit] in [pairWindow].
  final _sent = <String, List<DateTime>>{};
  static const pairLimit = 5;
  static const pairWindow = Duration(minutes: 10);

  final SessionRepository _sessions;
  final ChatRepository _chats;
  final ConversationRepository _conversations;
  final TurnLog? _log;

  static const names = ['chat_threads', 'chat_thread', 'chat_message', 'chat_start'];

  static final list = [
    {
      'name': 'chat_threads',
      'description':
          "The other threads in this chat (the same topic, talked about at other times): each "
          "one's title, a one-line summary, and an id. Cheap: look here first when something "
          "about this topic was likely settled elsewhere and the brief does not say it.",
      'inputSchema': {'type': 'object', 'properties': <String, Object?>{}},
      'annotations': {'readOnlyHint': true, 'title': 'Other threads in this chat'},
    },
    {
      'name': 'chat_thread',
      'description':
          "What was said in another thread of this chat, by its id from chat_threads. With "
          "find, only the parts holding those words; without, the whole thread, compacted. "
          'Costs more: use find when you know what you are looking for.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'id': {'type': 'string', 'description': 'The thread, from chat_threads.'},
          'find': {'type': 'string', 'description': 'Words to look for; leave out for all of it.'},
        },
        'required': ['id'],
      },
      'annotations': {'readOnlyHint': true, 'title': 'Read another thread'},
    },
    {
      'name': 'chat_message',
      'description':
          "Sends a message to another thread of this chat, by its id from chat_threads: its "
          'agent takes it up as its next message (after what it is doing), labelled as from '
          "this thread. Use it to hand work over, or to ask what only that thread knows. Its "
          'answer stays there; it can message you back. Say what you need and why, in full: '
          'that agent sees only your message and its own thread.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'id': {'type': 'string', 'description': 'The thread, from chat_threads.'},
          'message': {'type': 'string', 'description': 'What to say to it.'},
        },
        'required': ['id', 'message'],
      },
      'annotations': {'readOnlyHint': false, 'title': 'Message another thread'},
    },
    {
      'name': 'chat_start',
      'description':
          'Starts a new thread in this chat, in this folder, with a first message from this '
          'thread: for a piece of work that should go on beside this one. Give it a short '
          'title and a message that stands on its own.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'A few words naming the work.'},
          'message': {'type': 'string', 'description': 'Its first message, in full.'},
        },
        'required': ['title', 'message'],
      },
      'annotations': {'readOnlyHint': false, 'title': 'Start a thread'},
    },
  ];

  /// Whether [from] may send [to] another message now; records it if so.
  bool _allow(String from, String to) {
    final now = _now();
    final times = (_sent['$from>$to'] ??= [])..removeWhere((t) => now.difference(t) > pairWindow);
    if (times.length >= pairLimit) return false;
    times.add(now);
    return true;
  }

  Map<String, Object?> _says(String text, {bool error = false}) => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': error,
  };

  Future<Map<String, Object?>> call(String name, Map args, String? session) async {
    final me = session == null ? null : _sessions.byId(session);
    final chatId = me?.chatId;
    if (me == null || chatId == null) {
      return _says('This conversation is in no chat yet, so it has no other threads.', error: true);
    }
    final others = [
      for (final t in _chats.threadsOf(chatId))
        if (t.id != me.id) t,
    ];
    if (name == 'chat_threads') {
      await _log?.lookup(thread: me.id, chat: chatId, rung: 'summaries', size: others.length);
      if (others.isEmpty) return _says('No other threads in this chat yet.');
      return _says(
        [
          for (final t in others)
            '- ${t.title} (id ${t.id}, ${t.updatedAt.toIso8601String().substring(0, 10)})'
                '${t.summary == null ? '' : ': ${t.summary}'}',
        ].join('\n'),
      );
    }
    if (name == 'chat_thread') {
      final id = '${args['id'] ?? ''}';
      final thread = others.where((t) => t.id == id).firstOrNull;
      if (thread == null) {
        return _says('No thread $id in this chat. chat_threads lists them.', error: true);
      }
      await _conversations.load(id);
      final items = _conversations.of(id).items;
      final find = '${args['find'] ?? ''}'.trim().toLowerCase();
      String text;
      if (find.isEmpty) {
        text = ChatKeeper.transcript(items, each: 2000, all: 24000);
      } else {
        final wanted = find.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
        final lines = ChatKeeper.transcript(items, each: 1500, all: 200000).split('\n');
        final hits = [
          for (final l in lines)
            if (wanted.any((w) => l.toLowerCase().contains(w))) l,
        ];
        text = hits.isEmpty
            ? 'Nothing in "${thread.title}" mentions $find.'
            : hits.take(20).join('\n');
      }
      await _log?.lookup(
        thread: me.id,
        chat: chatId,
        rung: find.isEmpty ? 'thread' : 'thread-find',
        size: text.length,
      );
      return _says('From "${thread.title}":\n\n$text');
    }
    if (name == 'chat_message') {
      final id = '${args['id'] ?? ''}';
      final message = '${args['message'] ?? ''}'.trim();
      if (id == me.id) return _says('That is this thread.', error: true);
      final thread = others.where((t) => t.id == id).firstOrNull;
      if (thread == null) {
        return _says('No thread $id in this chat. chat_threads lists them.', error: true);
      }
      if (message.isEmpty) return _says('Say what to send.', error: true);
      if (!_allow(me.id, id)) {
        return _says(
          'You have sent "${thread.title}" $pairLimit messages in the last '
          '${pairWindow.inMinutes} minutes. Wait for its answer, or ask the person.',
          error: true,
        );
      }
      await _conversations.load(id);
      final sent = await _conversations.send(thread, message, from: 'the thread "${me.title}"');
      if (sent case Error(:final error)) return _says('It did not go: $error', error: true);
      await _log?.lookup(thread: me.id, chat: chatId, rung: 'message', size: message.length);
      final busy = _conversations.of(id).busy;
      return _says(
        'Sent to "${thread.title}"${busy ? ', which takes it up next' : ''}. Its answer stays '
        'there; chat_thread reads it later.',
      );
    }
    if (name == 'chat_start') {
      final title = '${args['title'] ?? ''}'.trim();
      final message = '${args['message'] ?? ''}'.trim();
      if (title.isEmpty || message.isEmpty) {
        return _says('Give it a title and a first message.', error: true);
      }
      final made = await _sessions.create(
        cwd: me.cwd,
        level: me.level,
        title: title,
        chatId: chatId,
      );
      if (made case Error(:final error)) return _says('It was not started: $error', error: true);
      final thread = (made as Ok<Session>).value;
      _allow(me.id, thread.id);
      _conversations.of(thread.id).loaded = true;
      final sent = await _conversations.send(thread, message, from: 'the thread "${me.title}"');
      if (sent case Error(:final error)) {
        return _says('Started, but the message did not go: $error', error: true);
      }
      await _log?.lookup(thread: me.id, chat: chatId, rung: 'start', size: message.length);
      return _says('Started "$title" (id ${thread.id}) in this chat, working on your message.');
    }
    return _says('No such tool.', error: true);
  }
}
