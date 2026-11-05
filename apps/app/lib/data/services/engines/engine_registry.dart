import '../../../domain/models/engine.dart';
import '../../../domain/models/settings.dart';
import 'agent_engine.dart';

/// The engines this build knows, in the order the picker shows them.
class EngineRegistry {
  new(List<AgentEngine> engines, {this.account}) : _engines = List.unmodifiable(engines);

  /// The engines as they are now. Adding or removing one makes a new list,
  /// so a loop over this one, waiting as it goes, is never upset by it.
  List<AgentEngine> get engines => _engines;
  List<AgentEngine> _engines;

  /// Makes the engine for an account added in Settings. Null where accounts
  /// cannot be added (tests).
  final AgentEngine Function(ConnectionAccount account)? account;

  /// An account added while Helmy runs, used from the next message on.
  void add(ConnectionAccount a) {
    final make = account;
    if (make == null || byId(a.id) != null) return;
    _engines = List.unmodifiable([..._engines, make(a)]);
  }

  /// An account removed while Helmy runs.
  void remove(String id) => _engines = List.unmodifiable([
    for (final e in _engines)
      if (e.info.id != id) e,
  ]);

  AgentEngine? byId(String id) => engines.where((e) => e.info.id == id).firstOrNull;

  EngineInfo? infoOf(String id) => byId(id)?.info;
}
