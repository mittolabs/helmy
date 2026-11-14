import '../../domain/identity.dart';
import '../../domain/models/engine.dart';
import 'engines/engine_registry.dart';
import 'engines/engine_router.dart';
import 'local_writer.dart';
import '../../domain/models/work.dart';

/// Short writing on a cloud connection, for Helmy's own upkeep where this
/// Mac has no model (decision `0014` allows the cheapest): each connection
/// answers on its smallest model. The one with the most room is asked first.
/// Null when none could.
class CloudWriter {
  CloudWriter(this._engines, this._router, this._enabled);
  final EngineRegistry _engines;
  final EngineRouter _router;
  final bool Function(String engineId) _enabled;

  static const _instructions =
      '$helmyIdentity\n\nYou write short labels for conversations, exactly in the form '
      'asked. No preamble.';

  Future<Written?> write(String prompt) async {
    final online = [
      for (final e in _engines.engines)
        if (_enabled(e.info.id) && !e.info.localOnly) e,
    ];
    if (online.isEmpty) return null;
    final first = _router.choose(
      candidates: [for (final e in online) e.info],
      current: null,
      kind: WorkKind.quick,
      needs: const {},
    );
    for (final e in [
      ...online.where((e) => e.info.id == first),
      ...online.where((e) => e.info.id != first),
    ]) {
      final answer = await e.ask(_instructions, prompt);
      if (answer != null) {
        final t = answer.tokens;
        return (
          text: answer.text,
          model: 'cloud:${e.info.id}',
          promptTokens: promptTokensOf(t),
          outputTokens: t?.output,
        );
      }
    }
    return null;
  }
}

/// All the input [tokens] reported, fresh and cached; null when the fresh or
/// cached part was not reported: unknown, never estimated. A connection that
/// reports no cache writes (Codex) has none to add.
int? promptTokensOf(TurnTokens? tokens) {
  final fresh = tokens?.fresh, cached = tokens?.cacheRead;
  if (fresh == null || cached == null) return null;
  return fresh + cached + (tokens?.cacheWrite ?? 0);
}
