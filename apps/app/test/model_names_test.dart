import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/model_names.dart';

void main() {
  test('model ids read as their names', () {
    expect(modelLabel('claude-opus-5-5'), 'Opus 5.5');
    expect(modelLabel('claude-haiku-4-5-20251001'), 'Haiku 4.5');
    expect(modelLabel('claude-sonnet-5'), 'Sonnet 5');
    expect(modelLabel('gpt-6.1-sol'), 'GPT-6.1-Sol');
    expect(modelLabel('opencode/glm-5.3-flash-free'), 'glm-5.3-flash-free');
  });
}
