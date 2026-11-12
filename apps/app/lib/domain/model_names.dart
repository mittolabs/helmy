/// A model's name as a person reads it, from the id a connection reports:
/// `claude-opus-5-5` reads "Opus 5.5", `gpt-6.1-sol` "GPT-6.1-Sol". An id it
/// does not know the shape of is shown as it is, without a provider prefix.
String modelLabel(String id) {
  final bare = id.contains('/') ? id.substring(id.lastIndexOf('/') + 1) : id;
  final claude = RegExp(r'^claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?$').firstMatch(bare);
  if (claude != null) {
    final family = claude[1]!;
    final version = claude[3] == null ? claude[2]! : '${claude[2]}.${claude[3]}';
    return '${family[0].toUpperCase()}${family.substring(1)} $version';
  }
  if (bare.startsWith('gpt-')) {
    return 'GPT-${bare.substring(4).split('-').map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}').join('-')}';
  }
  return bare;
}
