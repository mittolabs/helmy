import '../domain/models/chat_item.dart';

/// A conversation as Markdown, to copy or save: what was said, the steps taken
/// as one line each, and pictures as their files. Approvals and timings are
/// left out; they are how it got there, not what was said.
String transcriptMarkdown(String title, List<ChatItem> items) {
  final out = StringBuffer('# $title\n');
  for (final item in items) {
    switch (item) {
      case UserMessage(:final text):
        out.write('\n**You:**\n\n$text\n');
      case AssistantText(:final text) when text.trim().isNotEmpty:
        out.write('\n$text\n');
      case ToolCall call:
        final what = call.summary.isEmpty ? '' : ': ${call.summary}';
        out.write('\n> ${call.name}$what${call.isError ? ' (failed)' : ''}\n');
      case ImageItem(:final path):
        out.write('\n![image]($path)\n');
      case Notice(:final text):
        out.write('\n_${text}_\n');
      default:
        break;
    }
  }
  return out.toString();
}

/// The words of one answer: every reply the agent gave between [from], a
/// message of the user's, and the next one.
String answerText(List<ChatItem> items, int from) {
  final parts = <String>[];
  for (var i = from + 1; i < items.length; i++) {
    final item = items[i];
    if (item is UserMessage) break;
    if (item is AssistantText && item.text.trim().isNotEmpty) parts.add(item.text.trim());
  }
  return parts.join('\n\n');
}
