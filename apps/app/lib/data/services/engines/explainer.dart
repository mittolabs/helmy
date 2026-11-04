import '../../../domain/identity.dart';
import 'engine_registry.dart';
import 'engine_router.dart';

/// Explains a shell command in plain words, asking the connection with the
/// most room first, then the rest, and the model on this computer last.
class CommandExplainer {
  CommandExplainer(this._engines, this._router, this._enabled);
  final EngineRegistry _engines;
  final EngineRouter _router;
  final bool Function(String engineId) _enabled;

  static const _instructions =
      '$helmyIdentity\n\n'
      'You explain shell commands to a developer in plain words: first what the whole '
      'command does, then each part in one short line as a Markdown list. Mention anything '
      'risky. No preamble. Under 150 words.';

  /// The explanation of [command]; null when no connection could give one.
  Future<String?> explain(String command) async {
    final ready = [
      for (final e in _engines.engines)
        if (_enabled(e.info.id)) e,
    ];
    final online = ready.where((e) => !e.info.localOnly).toList();
    final first = online.isEmpty
        ? null
        : _router.choose(
            candidates: [for (final e in online) e.info],
            current: null,
            needs: const {},
          );
    final order = [
      ...online.where((e) => e.info.id == first),
      ...online.where((e) => e.info.id != first),
      ...ready.where((e) => e.info.localOnly),
    ];
    for (final e in order) {
      final answer = await e.ask(_instructions, 'Explain this command:\n\n$command');
      if (answer != null) return answer;
    }
    return null;
  }
}
