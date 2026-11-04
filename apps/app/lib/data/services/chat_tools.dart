import '../repositories/chat_keeper.dart';
import '../repositories/chat_repository.dart';
import '../repositories/conversation_repository.dart';
import '../repositories/session_repository.dart';
import 'turn_log.dart';

/// The agent's way into the rest of its chat (decision `0014`), cheapest
/// first: the other threads' one-line summaries, then one thread's words,
/// only the parts that match when that is enough. Each lookup is logged
/// with its rung.
class ChatTools {
  ChatTools({
    required this._sessions,
    required this._chats,
    required this._conversations,
    this._log,
  });

  final SessionRepository _sessions;
  final ChatRepository _chats;
  final ConversationRepository _conversations;
  final TurnLog? _log;

  static const names = ['chat_threads', 'chat_thread'];

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
  ];

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
    return _says('No such tool.', error: true);
  }
}
