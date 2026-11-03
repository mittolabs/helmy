import '../../../domain/models/chat_item.dart';

/// What an engine missed while others answered, as a few lines it reads ahead
/// of the new message. Built without a model call, and kept small: each turn is
/// what was asked, the final reply (trimmed) and the files changed. Tool output
/// is left out; the files are on disk for the engine to read if it needs them.
/// Empty when it missed nothing.
String handoff(List<ChatItem> missed, {int maxAsk = 600, int maxReply = 500, int maxChars = 4000}) {
  final turns = <String>[];
  String? ask;
  String? reply;
  final changed = <String>{};
  final images = <String>[];
  final youRan = <String>[];
  var commands = 0;

  void close() {
    if (ask == null && reply == null && changed.isEmpty && images.isEmpty && youRan.isEmpty) {
      return;
    }
    turns.add(
      [
        if (ask != null) 'User: ${_trim(ask!, maxAsk)}',
        if (reply != null) 'Assistant: ${_trim(reply!, maxReply)}',
        if (changed.isNotEmpty) 'Changed: ${changed.join(', ')}',
        for (final i in images) 'Made an image: $i',
        ...youRan,
        if (commands > 0) 'Ran $commands command${commands == 1 ? '' : 's'}',
      ].join('\n'),
    );
    ask = reply = null;
    changed.clear();
    images.clear();
    youRan.clear();
    commands = 0;
  }

  for (final item in missed) {
    switch (item) {
      case UserMessage(:final text, :final attachments):
        close();
        ask = [
          text.trim(),
          if (attachments.isNotEmpty) '(attached: ${attachments.join(', ')})',
        ].join(' ');
      case ImageItem(:final path):
        images.add(path);
      case AssistantText(:final text) when text.trim().isNotEmpty:
        reply = text.trim();
      case ToolCall(:final name, :final input, :final isError)
          when !isError || input['by'] == 'you':
        switch (name) {
          case 'Write' || 'Edit' || 'NotebookEdit':
            final path = input['file_path'] ?? input['notebook_path'];
            if (path is String && path.isNotEmpty) changed.addAll(path.split(', '));
          case 'Bash' || 'Shell' when item.input['by'] == 'you':
            final out = _trim(item.result ?? '', 400);
            youRan.add('User ran `${item.input['command']}`, which printed: $out');
          case 'Bash' || 'Shell':
            commands++;
        }
      default:
        break;
    }
  }
  close();
  if (turns.isEmpty) return '';

  // Newest turns first until the budget is spent; they matter most.
  final kept = <String>[];
  var size = 0;
  for (final t in turns.reversed) {
    if (size + t.length > maxChars && kept.isNotEmpty) break;
    kept.insert(0, t);
    size += t.length;
  }
  final dropped = turns.length - kept.length;
  return '<earlier_conversation>\n'
      'Another assistant handled part of this conversation in this folder. '
      'What happened since you last took part:\n'
      '${dropped > 0 ? '($dropped earlier turns left out)\n' : ''}'
      '${kept.join('\n\n')}\n'
      '</earlier_conversation>\n\n';
}

String _trim(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}...';
