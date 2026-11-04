/// Helmy speaks for itself: what a connection reports reaches a conversation
/// only in Helmy's words. These put their errors, tool names and phrases into
/// those words. (Answers are the model speaking as Helmy, and are left alone.)
library;

import 'problem.dart';

/// A failed turn, in Helmy's words: the common causes said plainly, anything
/// else said simply. The connection's own text never reaches the conversation.
String inHelmysWords(String? raw) => diagnose(raw).what;

/// A tool's name as Helmy says it: a connected service's tool,
/// `mcp__claude_ai_Gmail__search_threads` or `gmail.search_threads`, reads
/// "Gmail: search threads"; other names are left as they are.
String toolLabel(String name) {
  // Helmy's own tools, and a connection's look-up of one, in plain words.
  if (name.endsWith('watch_video')) return 'Watched a video';
  for (final (tool, said) in const [
    ('device_list', 'Looked for devices'),
    ('device_screen', "Looked at the device's screen"),
    ('device_tap', 'Tapped the device'),
    ('device_swipe', 'Swiped on the device'),
    ('device_type', 'Typed on the device'),
    ('device_home', 'Pressed home'),
    ('browser_open', 'Opened a page'),
    ('browser_read', 'Read the page'),
    ('browser_act', 'Used the page'),
    ('browser_screenshot', 'Looked at the page'),
    ('browser_logs', "Checked the page's errors"),
    ('browser_eval', 'Ran a script in the page'),
  ]) {
    if (name.endsWith(tool)) return said;
  }
  if (name == 'ToolSearch') return 'Found a tool';
  String words(String s) => s.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  // "notion" reads "Notion"; "Google_Drive" stays "Google Drive".
  String service(String s) =>
      words(s.replaceFirst(RegExp(r'^(claude[_ ]?ai[_ ]?|codex[_ ]?)', caseSensitive: false), ''))
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join(' ');
  if (name.startsWith('mcp__')) {
    final parts = name.split('__');
    if (parts.length >= 3) return '${service(parts[1])}: ${words(parts.sublist(2).join(' '))}';
  }
  final dot = RegExp(r'^([A-Za-z0-9_ -]+)\.([A-Za-z0-9_-]+)$').firstMatch(name);
  if (dot != null) return '${service(dot[1]!)}: ${words(dot[2]!)}';
  return name;
}

/// A step's result, unless it is a connection's own note about being stopped
/// or turned down, which reads as Helmy's instead.
String stepResult(String result) {
  final r = result.trim();
  if (RegExp(r"^\[request interrupted by user", caseSensitive: false).hasMatch(r)) {
    return 'Stopped.';
  }
  if (RegExp(
        r"^the user doesn.t want to (proceed|take this action)",
        caseSensitive: false,
      ).hasMatch(r) ||
      RegExp(r'^the user declined', caseSensitive: false).hasMatch(r)) {
    return 'You declined this.';
  }
  return result;
}

/// Text Helmy shows that came from a connection (a command's description, a
/// notice), with the products behind it named as Helmy.
String withoutNames(String text) => text
    .replaceAll(RegExp(r'\bClaude Code\b|\bClaude\b|\bCodex\b|\bChatGPT\b'), 'Helmy')
    .replaceAll(RegExp(r'\b(Anthropic|OpenAI)\b'), 'Mittolabs');
