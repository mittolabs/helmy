import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/ollama/ollama_doctor.dart';

void main() {
  test('a model still loaded well past when it was due to go is stuck', () {
    final now = DateTime.utc(2026, 11, 4, 9);
    Map ps(DateTime due) => {
      'models': [
        {'name': 'qwen3:8b-16k', 'expires_at': due.toIso8601String()},
      ],
    };
    expect(OllamaDoctor.isStuck(ps(now.add(const Duration(minutes: 4))), now), isFalse);
    expect(OllamaDoctor.isStuck(ps(now.subtract(const Duration(seconds: 10))), now), isFalse);
    expect(OllamaDoctor.isStuck(ps(now.subtract(const Duration(minutes: 2))), now), isTrue);
    expect(OllamaDoctor.isStuck({'models': <Map>[]}, now), isFalse);
  });
}
