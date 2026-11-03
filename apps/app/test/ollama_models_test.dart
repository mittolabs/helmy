import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/codex/codex_engine.dart';

void main() {
  test("the models pulled to this Mac are read from Ollama's own files", () async {
    final home = await Directory.systemTemp.createTemp('ollama-home');
    final base = '${home.path}/.ollama/models/manifests/registry.ollama.ai';
    for (final p in ['library/gpt-oss/20b', 'library/qwen3/8b', 'someone/tool-model/latest']) {
      File('$base/$p')
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
    }
    expect(CodexEngine.pulledModels(home: home.path), [
      'gpt-oss:20b',
      'qwen3:8b',
      'someone/tool-model:latest',
    ]);
    expect(CodexEngine.pulledModels(home: '${home.path}/nowhere'), isEmpty);
    await home.delete(recursive: true);
  });
}
