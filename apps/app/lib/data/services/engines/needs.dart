import '../../../domain/models/engine.dart';

/// What a message needs that only some engines have. Rules over the words, not
/// a model call: free and instant, and wrong now and then, in which case the
/// message goes where headroom alone would have sent it.
Set<Capability> needsOf(String message) => {
  if (_wantsPicture(message)) Capability.imageGeneration,
  for (final e in _services.entries)
    if (e.value.hasMatch(message.length > 600 ? message.substring(0, 600) : message)) e.key,
};

/// A connected service, asked for by the way people ask for theirs: "my
/// Drive", "my inbox", "my calendar". Words about building such a thing
/// ("an email validator", "a calendar widget") do not count.
final _services = {
  Capability.googleDrive: RegExp(
    r'\b(google drive|my drive|in drive|on drive|from drive|google (doc|docs|sheet|sheets|slides))\b',
    caseSensitive: false,
  ),
  Capability.gmail: RegExp(
    r'\b(gmail|my (e-?mail|e-?mails|inbox|mail)|unread (e-?mails?|mail)|e-?mails? from)\b',
    caseSensitive: false,
  ),
  Capability.googleCalendar: RegExp(
    r"\b(google calendar|my (calendar|meetings?|schedule|agenda)|what'?s on (my|the) calendar|calendar (today|tomorrow|this week))\b",
    caseSensitive: false,
  ),
  Capability.slack: RegExp(
    r'\b(on|in|from|my) slack\b|\bslack (messages?|channels?|threads?)\b',
    caseSensitive: false,
  ),
  Capability.notion: RegExp(
    r'\b(in|from|my|on) notion\b|\bnotion (page|pages|doc|docs|database)\b',
    caseSensitive: false,
  ),
};

const _make =
    r'(generate|create|make|draw|design|paint|illustrate|render|produce|sketch|imagine|give me|show me)';
const _picture =
    r'(image|picture|pic|photo|illustration|drawing|artwork|art|poster|wallpaper|sticker|portrait|logo|comic|manga|anime|painting|cartoon|meme|thumbnail|banner|mockup)s?';

/// Words that point at a picture that already exists: "make the logo bigger".
const _existing = r'(the|this|that|these|those|my|our|your|its|their)';

/// "Generate an image of a cat", "draw me a cat in manga style", "make a logo":
/// a verb of making followed closely by a kind of picture. Not "why does this
/// image not load" or "resize the images in assets", which are about files.
final _pictureRequest = RegExp(
  '\\b$_make\\b(\\W+(?!$_existing\\b)\\w+){0,4}?\\W+$_picture\\b',
  caseSensitive: false,
);
final _drawSomething = RegExp(
  r'^\s*(please\s+)?(draw|paint|sketch|illustrate)\b',
  caseSensitive: false,
);

bool _wantsPicture(String message) {
  final head = message.length > 400 ? message.substring(0, 400) : message;
  return _pictureRequest.hasMatch(head) || _drawSomething.hasMatch(head);
}
