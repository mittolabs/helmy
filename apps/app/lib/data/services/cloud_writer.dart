import '../../domain/identity.dart';
import 'engines/engine_registry.dart';
import 'engines/engine_router.dart';
import 'local_writer.dart';

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
      needs: const {},
    );
    for (final e in [
      ...online.where((e) => e.info.id == first),
      ...online.where((e) => e.info.id != first),
    ]) {
      final text = await e.ask(_instructions, prompt);
      // Tokens are not reported this way: unknown, never estimated.
      if (text != null) {
        return (text: text, model: 'cloud:${e.info.id}', promptTokens: null, outputTokens: null);
      }
    }
    return null;
  }
}
