import 'dart:convert';
import 'dart:io';

import 'engines/codex/codex_engine.dart';

/// What the model on this Mac wrote, and what it took.
typedef Written = ({String text, String model, int? promptTokens, int? outputTokens});

/// Short writing on the model on this Mac (Ollama), for Helmy's own upkeep
/// (decision `0014`): a thread's summary, a chat's brief. It costs no cloud
/// tokens. Null when no model runs here, or it does not answer in time.
class LocalWriter {
  LocalWriter({required this._model, this.host = 'http://localhost:11434'});

  /// The model chosen in settings; null for the first one pulled.
  final String? Function() _model;
  final String host;

  /// The model to write with: the most capable here (the largest), since
  /// upkeep runs in the background where a few seconds cost nothing and a
  /// wrong brief costs much. Measured: qwen3 0.6b filed an open question as
  /// decided; qwen3 8b did not. Null when Ollama is not running or has none.
  Future<String?> model() async {
    final sized = await _sized();
    if (sized.isEmpty) {
      final models = await CodexEngine.ollamaModels();
      if (models == null || models.isEmpty) return null;
      final chosen = _model();
      return chosen != null && models.contains(chosen) ? chosen : models.first;
    }
    sized.sort((a, b) => b.$2.compareTo(a.$2));
    return sized.first.$1;
  }

  /// The models here and their sizes, as Ollama lists them.
  Future<List<(String, int)>> _sized() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse('$host/api/tags'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return [];
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      return [
        for (final m in (j['models'] as List? ?? const []).whereType<Map>())
          // Embedding models write nothing.
          if (!'${m['name']}'.contains('embed'))
            ('${m['name']}', (m['size'] as num?)?.toInt() ?? 0),
      ];
    } on Object {
      return [];
    } finally {
      client.close(force: true);
    }
  }

  Future<Written?> write(
    String prompt, {
    int maxTokens = 400,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final model = await this.model();
    if (model == null) return null;
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('$host/api/generate'));
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'model': model,
          'prompt': prompt,
          'stream': false,
          'think': false,
          'options': {'num_predict': maxTokens, 'temperature': .2},
        }),
      );
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      final text = '${j['response'] ?? ''}'
          .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '')
          .trim();
      if (text.isEmpty) return null;
      return (
        text: text,
        model: model,
        promptTokens: (j['prompt_eval_count'] as num?)?.toInt(),
        outputTokens: (j['eval_count'] as num?)?.toInt(),
      );
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
