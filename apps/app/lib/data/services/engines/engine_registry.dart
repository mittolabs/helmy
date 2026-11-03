import '../../../domain/models/engine.dart';
import 'agent_engine.dart';

/// The engines this build knows, in the order the picker shows them.
class EngineRegistry {
  new(this.engines);
  final List<AgentEngine> engines;

  AgentEngine? byId(String id) => engines.where((e) => e.info.id == id).firstOrNull;

  EngineInfo? infoOf(String id) => byId(id)?.info;
}
