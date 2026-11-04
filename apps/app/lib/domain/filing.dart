import 'dart:math';

/// What a chat is known by, to file a new thread against: its id, and the
/// words of its title, brief and threads' titles.
typedef ChatCard = ({String id, String text});

/// Where a new thread goes (decision `0014`): into a chat Helmy is sure of,
/// a question between two it is not, or a chat of its own.
enum FilingKind { file, ask, own }

typedef Filing = ({
  FilingKind kind,
  String? best,
  double bestScore,
  String? runnerUp,
  double runnerUpScore,
});

/// Alike enough to file at all: [alikeFrom]. A second chat this alike
/// ([askFrom]) and within [close] of the first makes it a question, as the
/// thread may be about both. Measured on examples, to be tuned on the log.
const alikeFrom = .15, askFrom = .18, close = .5;

const _stop = {
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'but', 'by', 'can', 'could', 'do', 'does', 'for', //
  'from', 'had', 'has', 'have', 'how', 'i', 'if', 'in', 'into', 'is', 'it', 'its', 'just', 'let',
  'like', 'me', 'my', 'need', 'new', 'no', 'not', 'now', 'of', 'on', 'or', 'our', 'please', 'so',
  'some',
  'that',
  'the',
  'their',
  'them',
  'then',
  'there',
  'these',
  'this',
  'to',
  'up',
  'us',
  'want',
  'was',
  'we',
  'what',
  'when',
  'where',
  'which',
  'who',
  'why',
  'will',
  'with',
  'would',
  'you',
  'your',
  'make', 'get', 'help', 'about', 'again', 'also', 'all', 'any', 'one', 'more', 'should', 'session',
};

/// The words that carry meaning, each as its plain stem.
List<String> words(String text) => [
  for (final w in text.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
    if (w.length > 2 && !_stop.contains(w)) _stem(w),
];

String _stem(String w) {
  for (final end in ['ings', 'ing', 'ies', 'es', 'ed', 's']) {
    if (w.length > end.length + 3 && w.endsWith(end)) {
      return end == 'ies'
          ? '${w.substring(0, w.length - 3)}y'
          : w.substring(0, w.length - end.length);
    }
  }
  return w;
}

/// Where a thread beginning with [message] goes, among [chats]: by how
/// alike their words are, rarer words weighing more. No model is asked, so
/// it costs nothing; when two chats are close, the person is asked.
Filing file(String message, List<ChatCard> chats) {
  final none = (
    kind: FilingKind.own,
    best: null,
    bestScore: 0.0,
    runnerUp: null,
    runnerUpScore: 0.0,
  );
  final q = words(message.length > 1200 ? message.substring(0, 1200) : message);
  if (q.isEmpty || chats.isEmpty) return none;
  final docs = {for (final c in chats) c.id: words(c.text)};
  // How rare each word is across the chats.
  final df = <String, int>{};
  for (final d in docs.values) {
    for (final w in d.toSet()) {
      df[w] = (df[w] ?? 0) + 1;
    }
  }
  double idf(String w) => log((chats.length + 1) / ((df[w] ?? 0) + 1)) + 1;
  Map<String, double> vector(List<String> ws) {
    final v = <String, double>{};
    for (final w in ws) {
      v[w] = (v[w] ?? 0) + 1;
    }
    return {for (final e in v.entries) e.key: (1 + log(e.value)) * idf(e.key)};
  }

  double cosine(Map<String, double> a, Map<String, double> b) {
    var dot = 0.0;
    for (final e in a.entries) {
      dot += e.value * (b[e.key] ?? 0);
    }
    double norm(Map<String, double> v) => sqrt(v.values.fold(0.0, (s, x) => s + x * x));
    final n = norm(a) * norm(b);
    return n == 0 ? 0 : dot / n;
  }

  final qv = vector(q);
  final scored = [
    for (final MapEntry(key: id, value: d) in docs.entries) (id: id, score: cosine(qv, vector(d))),
  ]..sort((a, b) => b.score.compareTo(a.score));
  final best = scored.first;
  final second = scored.length > 1 ? scored[1] : (id: null, score: 0.0);
  final kind = best.score < alikeFrom
      ? FilingKind.own
      : second.score >= askFrom && second.score >= close * best.score
      ? FilingKind.ask
      : FilingKind.file;
  return (
    kind: kind,
    best: best.id,
    bestScore: best.score,
    runnerUp: second.id,
    runnerUpScore: second.score,
  );
}
