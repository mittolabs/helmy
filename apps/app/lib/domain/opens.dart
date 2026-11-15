/// How often a chat is opened, as T3 Code ranks its search: a count that
/// halves every two weeks, so a chat opened often lately comes first, and one
/// opened often long ago fades.
library;

import 'dart:math' as math;

const openHalfLife = Duration(days: 14);

/// [score] as of [now], from when it was last counted ([at]).
double openScore(double score, DateTime? at, DateTime now) {
  if (at == null || score <= 0) return 0;
  final halves = now.difference(at).inMinutes / openHalfLife.inMinutes;
  return score * math.pow(2, -halves);
}

/// One more open, at [now].
({double score, DateTime at}) opened(double score, DateTime? at, DateTime now) =>
    (score: openScore(score, at, now) + 1, at: now);
