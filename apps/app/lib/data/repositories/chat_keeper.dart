import 'dart:async';

import '../../domain/models/chat_item.dart';
import '../../domain/chat_icons.dart';
import '../../domain/models/session.dart';
import '../services/cloud_writer.dart';
import '../services/local_writer.dart';
import '../services/turn_log.dart';
import 'chat_repository.dart';
import 'conversation_repository.dart';
import 'session_repository.dart';

/// Keeps chats current: when one has gone quiet, its one-line summary is
/// written (what a move to another connection hands over), on the model on
/// this Mac, costing no cloud tokens; without one, its own first words. And
/// it is named: its title, topic word and icon.
class ChatKeeper {
  ChatKeeper({
    required this._sessions,
    required this._conversations,
    required this._chats,
    required this._writer,
    this._log,
    this._cloud,
    this.quiet = const Duration(seconds: 90),
    Duration catchUpAfter = const Duration(seconds: 8),
    this._naming,
  }) {
    _conversations.addListener(_watch);
    // Chats from before Helmy named them, named once, in the background.
    _catchUp = Timer(catchUpAfter, () => unawaited(catchUp()));
  }

  final CloudWriter? _cloud;
  Timer? _catchUp;

  /// What the person wants of names, from settings; read at each naming.
  final String Function()? _naming;

  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final ChatRepository _chats;
  final LocalWriter _writer;
  final TurnLog? _log;

  /// How long a thread has been still before it is kept.
  final Duration quiet;

  final _busy = <String>{};
  final _timers = <String, Timer>{};
  final _turns = <String, int>{};

  /// A thread that keeps busy is kept every this many turns too, so its
  /// summary is ready for a hand-off before its connection runs out.
  static const every = 5;

  /// A thread that stopped working is kept once it has been quiet a while;
  /// one that starts again is not.
  void _watch() {
    for (final s in _sessions.sessions) {
      final busy = _conversations.of(s.id).busy;
      if (busy) {
        _busy.add(s.id);
        _timers.remove(s.id)?.cancel();
      } else if (_busy.remove(s.id)) {
        // Its first answer in: a chat Helmy has not named yet is named now.
        final chat = s.chatId == null ? null : _chats.byId(s.chatId!);
        if (chat != null &&
            s.sideOf == null &&
            ((!chat.titled && !chat.named) || chat.topic.isEmpty)) {
          unawaited(describe(s.id));
        }
        final n = _turns[s.id] = (_turns[s.id] ?? 0) + 1;
        if (n % every == 0) {
          unawaited(keep(s.id));
        } else {
          _timers[s.id] = Timer(quiet, () => unawaited(keep(s.id)));
        }
      }
    }
  }

  /// What a thread said, compactly: the person's words and the answers,
  /// each cut short, newest kept when it is long.
  static String transcript(List<ChatItem> items, {int each = 500, int all = 8000}) {
    String cut(String t) => t.length <= each ? t : '${t.substring(0, each)}...';
    final lines = [
      for (final i in items)
        if (i is UserMessage)
          'Person: ${cut(i.text.trim())}'
        else if (i is AssistantText && i.text.trim().isNotEmpty)
          'Assistant: ${cut(i.text.trim())}',
    ];
    var text = lines.join('\n');
    if (text.length > all) text = '...${text.substring(text.length - all)}';
    return text;
  }

  /// A summary as the model wrote it: one line, no quotes, not too long.
  static String? summaryFrom(String written) {
    final line = written
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final clean = line.replaceAll(RegExp(r'''^["'“]+|["'”]+$'''), '').trim();
    if (clean.isEmpty) return null;
    return clean.length <= 140 ? clean : '${clean.substring(0, 137)}...';
  }

  // Naming: a chat's topic word, icon, title and what it is about, and a
  // thread's own title; written by Helmy, on the model on this Mac, else the
  // cheapest in the cloud. A title the person gave is never replaced.

  final _describing = <String>{};

  /// What the model wrote, here first, else in the cloud.
  Future<Written?> _write(String prompt, {int maxTokens = 120}) async =>
      await _writer.write(prompt, maxTokens: maxTokens) ?? await _cloud?.write(prompt);

  /// [s]'s title is still only its first message's first words, or none.
  static bool rawTitle(Session s, String? first) {
    if (s.untitled) return true;
    if (first == null) return false;
    final line = first.trim().split('\n').first.trim();
    if (s.title == line) return true;
    return s.title.endsWith('...') && line.startsWith(s.title.substring(0, s.title.length - 3));
  }

  static final _quotes = RegExp('^["\'“”]+|["\'“”.]+\$');

  /// What the model wrote for a chat, read line by line; null for any part
  /// it got wrong.
  static ({String? topic, String? icon, String? title, String? about, String? thread}) namingFrom(
    String written, {
    String? project,
  }) {
    String? field(String name, int max) {
      final m = RegExp(
        '^\\s*[-*]?\\s*$name\\s*:\\s*(.+)\$',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(written);
      var v = m?[1]?.trim().replaceAll(_quotes, '').trim();
      if (v == null || v.isEmpty) return null;
      if (v.length > max) v = '${v.substring(0, max - 3).trimRight()}...';
      return v;
    }

    // A topic from the set (or the project's name), as the set spells it.
    final said = field('Topic', 40)?.toLowerCase();
    final topic = said == null
        ? null
        : project != null && said == project.toLowerCase()
        ? project
        : chatTopics.keys.where((t) => t.toLowerCase() == said).firstOrNull;
    // An icon not in the set: the topic's own.
    final named = field('Icon', 30)?.toLowerCase().split(RegExp('[^a-z]')).first;
    final icon = chatIcons.containsKey(named) ? named : chatTopics[topic];
    final title = field('Title', 48);
    // "New chat": nothing to name yet, so nothing is named.
    final untitled = title == null || title.toLowerCase() == 'new chat';
    // Narrated ("User asked...") rather than said: dropped, not shown.
    final about = field('About', 120);
    final narrated =
        about != null &&
        RegExp(r'\b(user|person|assistant)\b', caseSensitive: false).hasMatch(about);
    return (
      topic: untitled ? null : topic,
      icon: untitled ? null : icon,
      title: untitled ? null : title,
      about: untitled || narrated ? null : about,
      thread: untitled ? null : field('Thread', 48),
    );
  }

  /// Names thread [id]'s chat from what was said: its topic word and icon
  /// (once), its title (unless the person named it, or Helmy already has),
  /// what it is about (each time); and the thread's own title while it is
  /// only its first words.
  Future<void> describe(String id) async {
    final s = _sessions.byId(id);
    final chat = s?.chatId == null ? null : _chats.byId(s!.chatId!);
    if (s == null || chat == null || s.sideOf != null || !_describing.add(chat.id)) return;
    try {
      final items = _conversations.of(id).items;
      final first = items.whereType<UserMessage>().firstOrNull?.text;
      if (first == null) return;
      final others = [
        for (final t in _chats.threadsOf(chat.id))
          if (t.id != id && (t.summary ?? '').isNotEmpty) '- ${t.title}: ${t.summary}',
      ];
      // Measured on qwen3 8b against real chats: the folder's name in the
      // prompt took over every topic, and a worked example was copied into a
      // chat that only said hello. So: a fixed set of topics, a project only
      // when there is one, two examples marked as form only, and an
      // explicit way to say nothing has happened yet.
      final project = s.repo?.split('/').where((p) => p.isNotEmpty).lastOrNull;
      final prompt = [
        'Name this conversation between a person and an assistant for a list of chats.',
        '<conversation>\n${transcript(items, all: 4000)}\n</conversation>',
        if (others.isNotEmpty) 'Earlier conversations in the same chat:\n${others.join('\n')}',
        'Write exactly these five lines and nothing else:',
        'Topic: <one of: ${chatTopics.keys.join(', ')}'
            '${project == null ? '' : ', or the project name "$project" when it is about building that project'}>',
        'Icon: <one word from: ${chatIcons.keys.join(', ')}>',
        'Title: <2 to 5 words naming the subject>',
        'About: <under 12 words: what is done and what is still open, like a note to self>',
        'Thread: <2 to 5 words naming this conversation>',
        'Use only what the conversation says. If nothing has been asked yet, the title is '
            'New chat and About is empty.',
        if (_naming?.call().trim() case final note? when note.isNotEmpty)
          'The person asks this of the title and the thread name: $note',
        'Two examples from other conversations, for the form only:\n'
            'Topic: Money\nIcon: savings\nTitle: Food budget\n'
            'About: \$400 a month agreed; how to split groceries still open\n'
            'Thread: Setting the budget\n\n'
            'Topic: Travel\nIcon: travel\nTitle: Lisbon in March\n'
            'About: Flights booked; hotel still to choose\nThread: Booking flights',
      ].join('\n\n');
      final said = await _write(prompt);
      final n = said == null ? null : namingFrom(said.text, project: project);
      await _log?.upkeep(
        what: 'describe',
        thread: id,
        chat: chat.id,
        model: said?.model,
        promptTokens: said?.promptTokens,
        outputTokens: said?.outputTokens,
        kept: n?.title != null || n?.about != null,
      );
      if (n == null) return;
      final now = _chats.byId(chat.id) ?? chat;
      if (_disposed) return;
      await _chats.describe(
        chat.id,
        title: now.titled || now.named ? null : n.title,
        description: n.about,
        icon: (now.icon ?? '').isNotEmpty ? null : n.icon,
        topic: now.topic.isEmpty ? n.topic : null,
      );
      final thread = _sessions.byId(id);
      if (n.thread != null && thread != null && rawTitle(thread, first)) {
        if (_disposed) return;
        await _sessions.save(thread.copyWith(title: n.thread));
      }
    } finally {
      _describing.remove(chat.id);
    }
  }

  /// Names every chat Helmy has not named yet, latest worked in first, one
  /// at a time; an empty one from before is called "New chat".
  Future<void> catchUp() async {
    for (final c in _chats.chats.toList()) {
      if ((c.titled || c.named) && (c.icon ?? '').isNotEmpty && c.topic.isNotEmpty) continue;
      final latest = _chats.threadsOf(c.id).firstOrNull;
      if (latest == null) continue;
      await _conversations.load(latest.id);
      if (!_conversations.of(latest.id).items.any((i) => i is UserMessage)) {
        if (latest.untitled && latest.title != 'New chat') {
          if (_disposed) return;
          await _sessions.save(latest.copyWith(title: 'New chat'));
        }
        continue;
      }
      await describe(latest.id);
    }
  }

  /// Keeps chat [id] current now: its summary (what a move to another
  /// connection hands over), then what it is about, said again as it stands.
  Future<void> keep(String id) async {
    await _keep(id);
    await describe(id);
  }

  Future<void> _keep(String id) async {
    _timers.remove(id);
    final s = _sessions.byId(id);
    if (s == null || s.sideOf != null) return;
    final items = _conversations.of(id).items;
    if (!items.any((i) => i is UserMessage)) return;
    final text = transcript(items);

    // Its summary: written here when it can be, else its own first words.
    final said = await _writer.write(
      'Here is a conversation between a person and an assistant.\n\n'
      '<conversation>\n$text\n</conversation>\n\n'
      'In one line of at most 15 words, say what it is about and where it stands. '
      'No quotes, no preamble.',
      maxTokens: 60,
    );
    final summary =
        (said == null ? null : summaryFrom(said.text)) ??
        summaryFrom(items.whereType<UserMessage>().first.text);
    await _log?.upkeep(
      what: 'summary',
      thread: id,
      chat: s.chatId,
      model: said?.model,
      promptTokens: said?.promptTokens,
      outputTokens: said?.outputTokens,
      kept: summary != null,
    );
    final now = _sessions.byId(id);
    if (summary != null && now != null && now.summary != summary) {
      if (_disposed) return;
      await _sessions.save(now.copyWith(summary: summary));
    }
  }

  /// Disposed, work already under way stops before it writes anything: a
  /// summary or a name that comes back afterwards is let go.
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _catchUp?.cancel();
    _conversations.removeListener(_watch);
    for (final t in _timers.values) {
      t.cancel();
    }
  }
}
