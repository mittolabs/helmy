/// A file an engine keeps memory or standing instructions in.
class const MemoryFile({
  required final String engineId,
  required final String path,

  /// What it is for: "Instructions for every project", "Project memory".
  required final String kind,

  /// The project folder it belongs to, when it belongs to one.
  final String? project,
});

/// Memory an engine keeps that Helmy can show but not edit.
class const MemoryNote({required final String engineId, required final String text});
