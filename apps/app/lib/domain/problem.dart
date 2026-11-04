import 'helmy_voice.dart';

/// The one action that fixes a problem, where it happened.
enum Fix {
  /// Sign the connection that failed in again, through the browser.
  signIn,

  /// Send the message again.
  retry,

  /// Set up a connection: nothing can answer yet.
  setup,

  /// Start the model on this computer.
  startLocal,

  /// Allow speech recognition for Helmy (the system's own pane).
  allowSpeech,

  /// Allow notifications for Helmy (the system's own pane).
  allowNotifications,

  /// Install what carries taps and typing to iOS simulators (AXe).
  installDeviceInput,

  /// Nothing to press: it fixes itself, at [Problem.until].
  wait;

  /// As written in a `helmy://fix/<name>` link.
  String get link => switch (this) {
    signIn => 'sign-in',
    retry => 'retry',
    setup => 'setup',
    startLocal => 'start-local',
    allowSpeech => 'allow-speech',
    allowNotifications => 'allow-notifications',
    installDeviceInput => 'install-device-input',
    wait => 'wait',
  };

  static Fix? fromLink(String url) {
    final m = RegExp(r'^helmy://fix/([a-z-]+)').firstMatch(url);
    return m == null ? null : Fix.values.where((f) => f.link == m[1]).firstOrNull;
  }

  /// What its button says.
  String get label => switch (this) {
    signIn => 'Sign in again',
    retry => 'Try again',
    setup => 'Set up a connection',
    startLocal => 'Start it',
    allowSpeech => 'Allow speech recognition',
    allowNotifications => 'Allow notifications',
    installDeviceInput => 'Install it',
    wait => '',
  };
}

/// Something that went wrong, as Helmy tells it: what happened and why, in
/// its own words, and the one action that fixes it. [details] is the raw
/// account, with the names of the connections taken out.
class Problem {
  const Problem(this.what, this.fix, {this.details, this.engineId, this.until});

  final String what;
  final Fix fix;
  final String? details;

  /// The connection it happened in, for [Fix.signIn]; never shown.
  final String? engineId;

  /// When it fixes itself (a usage limit resetting), when known.
  final DateTime? until;
}

/// [raw] (a connection's own error) diagnosed: the cause, said plainly, and
/// its fix. Every problem gets one; one Helmy cannot explain still says what
/// happened, offers to try again, and keeps the details.
Problem diagnose(String? raw, {String? engineId, DateTime? now}) {
  final text = raw ?? '';
  final e = text.toLowerCase();
  final details = text.trim().isEmpty ? null : withoutNames(text.trim());
  Problem p(String what, Fix fix, {DateTime? until}) =>
      Problem(what, fix, details: details, engineId: engineId, until: until);

  if (RegExp(r'ollama is not running|11434|connection refused.*11434|11434.*refused').hasMatch(e)) {
    return p('The model on this computer is not running.', .startLocal);
  }
  if (RegExp(r'usage limit|rate.?limit|quota|\b429\b|too many requests|limit reached')
      .hasMatch(e)) {
    // Claude says when, as "...|<seconds since 1970>".
    final stamp = int.tryParse(RegExp(r'\|(\d{9,})').firstMatch(text)?[1] ?? '');
    final until = stamp == null ? null : DateTime.fromMillisecondsSinceEpoch(stamp * 1000);
    return until == null
        ? p("I've reached a usage limit. It frees up again soon; try again in a while.", .retry)
        : p(
            "I've reached a usage limit. It frees up at ${_time(until, now)}.",
            .wait,
            until: until,
          );
  }
  if (RegExp(r'overloaded|\b529\b|\b503\b|capacity|unavailable').hasMatch(e)) {
    return p(
      "The service I work through is overloaded right now. It usually passes in a minute.",
      .retry,
    );
  }
  if (RegExp(r'log ?in|sign ?in|\bauth|\b401\b|\b403\b|credential|api key|expired|oauth')
      .hasMatch(e)) {
    return p('My sign-in has expired, so I was turned away.', .signIn);
  }
  if (RegExp(r'context|too long|too large|max(imum)? tokens|prompt is too').hasMatch(e)) {
    return p(
      'This conversation has grown too long for me to take in at once. '
      'Compact it from the menu, or start a new session.',
      .retry,
    );
  }
  if (RegExp(r'network|offline|internet|enotfound|econn|timed? ?out|socket|host lookup')
      .hasMatch(e)) {
    return p("I couldn't reach the internet. When you're back online, try again.", .retry);
  }
  return p(
    details == null
        ? 'Something stopped me before I could finish, and I was not told why.'
        : 'Something went wrong while I was working on this. The details are below.',
    .retry,
  );
}

String _time(DateTime t, DateTime? now) {
  final n = now ?? DateTime.now();
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final clock = '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  final days = DateTime(t.year, t.month, t.day).difference(DateTime(n.year, n.month, n.day)).inDays;
  return days == 0
      ? clock
      : days == 1
      ? 'tomorrow at $clock'
      : '${t.month}/${t.day} at $clock';
}
