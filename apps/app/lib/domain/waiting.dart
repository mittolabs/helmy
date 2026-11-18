/// Chats that wait on something outside them: a person's reply, a command
/// the person runs elsewhere and brings back. Helmy offers to set such a
/// chat aside, so it neither fills the list nor is forgotten.
library;

/// Phrases with which an answer hands the next step to the person, outside
/// the chat: only then is a model asked whether it waits, so most answers
/// cost nothing.
final _handsOver = RegExp(
  r"\bpaste (it |them |that |this |the output |what )?(back|here|in)\b"
  r'|\bpaste back\b'
  r'|\bsend (me|it|them|over|back)\b'
  r'|\bshare (the|what|it|them)\b'
  r'|\blet me know\b'
  r'|\btell me (what|which|how|whether|if)\b'
  r'|\bonce (you|they|he|she|it)\b'
  r'|\bonce \w+ (replies|answers|confirms|sends|says|gets back)\b'
  r'|\bwhen (you|they|he|she) (have|hear|get|reply|send|run)\b'
  r'|\bwaiting (on|for)\b'
  r'|\b(run|try) (this|these|it|them|that) (on|in|against)\b'
  r'|\breply with\b'
  r'|\bcheck with\b'
  r'|\bask (him|her|them|[A-Z][a-z]+) (for|about|which|whether|to|if)\b'
  r'|\bget back to me\b'
  r'|\bafter you (run|try|check|ask)\b'
  r'|\bwhat (it|they|either one|each) prints?\b',
  caseSensitive: false,
);

/// Whether [answer] may leave its chat waiting on something outside it:
/// how its last lines hand over. A cheap first look; a model decides.
bool mayWait(String answer) {
  final t = answer.trim();
  if (t.isEmpty) return false;
  final tail = t.length > 700 ? t.substring(t.length - 700) : t;
  return _handsOver.hasMatch(tail);
}

/// What a model is asked about the end of a conversation ([transcript]):
/// whether its last answer waits on the person doing something outside it,
/// and if so on what, in a few words.
String waitPrompt(String transcript) => [
  'Here is the end of a conversation between a person and an assistant.',
  '<conversation>\n$transcript\n</conversation>',
  "Does the assistant's last message leave the conversation waiting on something the person "
      'has to do outside it before it can go on: run something elsewhere and bring back what '
      'it printed, get an answer from someone else, or wait for something to happen?',
  'Write exactly one line and nothing else:',
  'Waiting: <who or what, in under 8 words, as a note to self>',
  'or, when it does not wait on anything outside the conversation:',
  'Waiting: no',
  'Two examples from other conversations, for the form only:\n'
      'Waiting: Sam to confirm the venue\n'
      'Waiting: what the server log prints',
].join('\n\n');

/// What the model said a chat waits on, as one short line; null when it
/// waits on nothing or the answer is not in the asked form.
String? waitFrom(String written) {
  final m = RegExp(
    r'^\s*[-*]?\s*waiting\s*:\s*(.+)$',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(written);
  var v = m?[1]?.trim().replaceAll(RegExp('^["\'“”]+|["\'“”.]+\$'), '').trim();
  if (v == null || v.isEmpty) return null;
  if (RegExp(r'^(no|none|nothing|n/?a)\b', caseSensitive: false).hasMatch(v)) return null;
  // Narrated ("The user to...") reads as a report, not a note to self.
  v = v.replaceFirst(RegExp(r'^(the )?(user|person)\b\s*', caseSensitive: false), 'you ');
  if (v.length > 60) v = '${v.substring(0, 57).trimRight()}...';
  return v[0].toUpperCase() + v.substring(1);
}
