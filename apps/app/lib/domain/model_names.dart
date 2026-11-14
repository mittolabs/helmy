import 'models/engine.dart';

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

/// How big a model is, for carrying a chat over to another connection: a
/// flagship goes to a flagship (Opus to Codex's top GPT), a smaller model to
/// a smaller one, so the thread reads the same wherever it answers.
enum ModelClass { flagship, smaller }

/// The class of the model [id] (or its display name); null when the name
/// does not say, as with most models run on this Mac.
ModelClass? classOf(String? id) {
  if (id == null || id.trim().isEmpty) return null;
  final n = id.toLowerCase();
  if (RegExp(r'\b(haiku|sonnet|mini|nano|flash|lite|small|spark)\b').hasMatch(n)) return .smaller;
  if (RegExp(r'opus|^(openai/)?gpt-|^o\d\b|\b(pro|ultra|max)\b').hasMatch(n)) return .flagship;
  return null;
}

/// The model in [offered] closest to [model]: the same one where it is offered
/// (another account of the same connection), otherwise the first of the same
/// class, which is the one its connection lists first and so recommends.
/// Null when none is of that class.
ModelChoice? closestModel(String? model, List<ModelChoice> offered) {
  if (model != null) {
    for (final m in offered) {
      if (m.id == model) return m;
    }
  }
  final wanted = classOf(model);
  if (wanted == null) return null;
  for (final m in offered) {
    if ((classOf(m.id) ?? classOf(m.name)) == wanted) return m;
  }
  return null;
}
