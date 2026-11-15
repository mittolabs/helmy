/// A month's tokens from the turn log, per connection: what the Usage page
/// shows under the limits. Only what the connections reported; a number one
/// did not report is not counted, never guessed.
class TurnTotals {
  TurnTotals(this.byConnection, this.upkeep);

  /// Per connection id: its turns and their tokens.
  final Map<String, ConnectionTotals> byConnection;

  /// Helmy's own upkeep (naming, summaries, checking approvals), all
  /// connections together.
  final ConnectionTotals upkeep;

  bool get isEmpty => byConnection.isEmpty && upkeep.turns == 0;

  /// From the log's lines for one month.
  static TurnTotals of(List<Map<String, Object?>> lines) {
    final by = <String, ConnectionTotals>{};
    final upkeep = ConnectionTotals();
    for (final l in lines) {
      final kind = l['kind'];
      final t = l['tokens'];
      if (kind == 'turn') {
        final id = '${l['connection'] ?? 'unknown'}';
        (by[id] ??= ConnectionTotals()).add(t);
      } else if (kind == 'upkeep') {
        upkeep.add(t);
      }
    }
    return TurnTotals(by, upkeep);
  }
}

class ConnectionTotals {
  int turns = 0;

  /// Turns whose tokens the connection reported.
  int reported = 0;

  /// Input read afresh: new text, and a conversation its cache no longer held.
  int uncached = 0;

  /// Input read from the connection's cache: the conversation again at each
  /// step, at a fraction of the price.
  int cached = 0;

  /// Input written into the cache, to be read cheaply next time.
  int cacheWrites = 0;
  int output = 0;

  int get all => uncached + cached + cacheWrites + output;

  /// The share of input that came from the cache, 0 to 1; null with no input.
  double? get cachedShare {
    final input = uncached + cached + cacheWrites;
    return input == 0 ? null : cached / input;
  }

  void add(Object? tokens) {
    turns++;
    if (tokens is! Map || tokens.values.every((v) => v == null)) return;
    reported++;
    int n(String k) => (tokens[k] as num?)?.toInt() ?? 0;
    uncached += n('fresh');
    cached += n('cacheRead');
    cacheWrites += n('cacheWrite');
    output += n('output');
  }
}
