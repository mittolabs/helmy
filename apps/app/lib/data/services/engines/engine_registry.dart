import '../../../domain/models/engine.dart';
import 'agent_engine.dart';

/// The engines this build knows, in the order the picker shows them.
class EngineRegistry {
  new(this.engines, {this.account});
  final List<AgentEngine> engines;

  /// Makes the engine for another account of a connection: its id (claude-2)
  /// and folder. Null where accounts cannot be added (tests).
  final AgentEngine Function(String id, String folder)? account;

  /// An account added while Helmy runs, used from the next message on.
  void add(String id, String folder) {
    final make = account;
    if (make == null || byId(id) != null) return;
    engines.add(make(id, folder));
  }

  /// An account removed while Helmy runs.
  void remove(String id) => engines.removeWhere((e) => e.info.id == id);

  AgentEngine? byId(String id) => engines.where((e) => e.info.id == id).firstOrNull;

  EngineInfo? infoOf(String id) => byId(id)?.info;
}
