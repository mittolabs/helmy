/// Helmy speaks for itself: what a connection reports reaches a conversation
/// only in Helmy's words. These put their errors, tool names and phrases into
/// those words. (Answers are the model speaking as Helmy, and are left alone.)
library;

/// A failed turn, in Helmy's words: the common causes said plainly, anything
/// else said simply. The connection's own text never reaches the conversation.
String inHelmysWords(String? raw) {
  final e = (raw ?? '').toLowerCase();
  if (RegExp(r'usage limit|rate.?limit|quota|\b429\b|too many requests|limit reached')
      .hasMatch(e)) {
    return "I've reached a usage limit. Try again in a little while.";
  }
  if (RegExp(r'overloaded|\b529\b|\b503\b|capacity|unavailable').hasMatch(e)) {
    return "I'm overloaded right now. Try again in a moment.";
  }
  if (RegExp(r'log ?in|sign ?in|auth|\b401\b|\b403\b|credential|api key|expired').hasMatch(e)) {
    return 'I need to be signed in again. You can do that in Settings.';
  }
  if (RegExp(r'context|too long|too large|max(imum)? tokens|prompt is too').hasMatch(e)) {
    return 'This conversation has grown too long for me to take in. '
        'Compact it from the menu, or start a new session.';
  }
  if (RegExp(r'network|offline|internet|enotfound|econn|timed? ?out|socket|host lookup')
      .hasMatch(e)) {
    return "I couldn't reach the network. Check your connection and try again.";
  }
  return 'Something went wrong on my side. Send it again to try once more.';
}

/// A tool's name as Helmy says it: a connected service's tool,
/// `mcp__claude_ai_Gmail__search_threads` or `gmail.search_threads`, reads
/// "Gmail: search threads"; other names are left as they are.
String toolLabel(String name) {
  // Helmy's own tools, and a connection's look-up of one, in plain words.
  if (name.endsWith('watch_video')) return 'Watched a video';
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
