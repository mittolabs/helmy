import 'models/engine.dart';

/// Which of [candidates] a message may go to, before headroom picks one: the
/// connections online first; with none online, the model on this computer,
/// answering directly when the message needs no tools.
List<EngineInfo> eligible(List<EngineInfo> candidates, Set<Capability> needs) {
  final online = [
    for (final e in candidates)
      if (!e.localOnly) e,
  ];
  if (online.isNotEmpty) return online;
  final plain = [
    for (final e in candidates)
      if (!e.capabilities.contains(Capability.tools)) e,
  ];
  return !needs.contains(Capability.tools) && plain.isNotEmpty ? plain : candidates;
}
