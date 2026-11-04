import 'dart:async';

import '../../domain/models/chat_item.dart';
import '../services/local_writer.dart';
import '../services/turn_log.dart';
import 'chat_repository.dart';
import 'conversation_repository.dart';
import 'session_repository.dart';

/// Keeps chats current (decision `0014`): when a thread has gone quiet, its
/// one-line summary is written and its chat's brief brought up to date, on
/// the model on this Mac, costing no cloud tokens. Without one, the summary
/// is the thread's own first words and the brief is left to the person. A
/// brief the person wrote is never rewritten.
class ChatKeeper {
  ChatKeeper({
    required this._sessions,
    required this._conversations,
    required this._chats,
    required this._writer,
    this._log,
    this.quiet = const Duration(seconds: 90),
  }) {
    _conversations.addListener(_watch);
  }

  final SessionRepository _sessions;
  final ConversationRepository _conversations;
  final ChatRepository _chats;
  final LocalWriter _writer;
  final TurnLog? _log;

  /// How long a thread has been still before it is kept.
  final Duration quiet;

  final _busy = <String>{};
  final _timers = <String, Timer>{};

  /// A thread that stopped working is kept once it has been quiet a while;
  /// one that starts again is not.
  void _watch() {
    for (final s in _sessions.sessions) {
      final busy = _conversations.of(s.id).busy;
      if (busy) {
        _busy.add(s.id);
        _timers.remove(s.id)?.cancel();
      } else if (_busy.remove(s.id)) {
        _timers[s.id] = Timer(quiet, () => unawaited(keep(s.id)));
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

  /// A brief as the model wrote it, kept only in its shape: lines saying
  /// what was decided or is open, at most eight. Null when nothing fits.
  static String? briefFrom(String written) {
    final lines = [
      for (final l in written.split('\n'))
        if (RegExp(r'^\s*[-*]?\s*(Decided|Open):', caseSensitive: false).hasMatch(l))
          l.replaceFirst(RegExp(r'^\s*[-*]?\s*'), '').trim(),
    ];
    if (lines.isEmpty) return null;
    return lines.take(8).join('\n');
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

  /// Keeps thread [id] and its chat current now.
  Future<void> keep(String id) async {
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
      await _sessions.save(now.copyWith(summary: summary));
    }

    // Its chat's brief, unless the person wrote it, or no model runs here.
    final chat = s.chatId == null ? null : _chats.byId(s.chatId!);
    if (chat == null || chat.briefByPerson || said == null) return;
    final wrote = await _writer.write(
      "You keep a chat's brief: what has been decided and what is still open, about one "
      'topic, across conversations.\n\n'
      'Current brief:\n<brief>\n${chat.brief.isEmpty ? '(empty)' : chat.brief}\n</brief>\n\n'
      'A conversation in this chat just went quiet:\n<conversation>\n$text\n</conversation>\n\n'
      "Write the updated brief: lines starting 'Decided:' or 'Open:', at most 8 lines, each "
      'under 25 words. Keep what still holds from the current brief, add what this '
      'conversation decided or left open, drop what it settled. Only facts from the text. '
      'Output only the lines.',
    );
    final brief = wrote == null ? null : briefFrom(wrote.text);
    await _log?.upkeep(
      what: 'brief',
      thread: id,
      chat: chat.id,
      model: wrote?.model,
      promptTokens: wrote?.promptTokens,
      outputTokens: wrote?.outputTokens,
      kept: brief != null,
    );
    if (brief != null && brief != chat.brief) {
      await _chats.setBrief(chat.id, brief, byPerson: false);
    }
  }

  void dispose() {
    _conversations.removeListener(_watch);
    for (final t in _timers.values) {
      t.cancel();
    }
  }
}
