import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/models/chat_item.dart';

void main() {
  test('a decision this build does not know reads as settled, not waiting', () {
    final p = PermissionPrompt.fromJson({
      'kind': 'permission',
      'requestId': '1',
      'toolName': 'Bash',
      'input': {'command': 'ls'},
      'decision': 'decidedByAFutureHelmy',
    });
    expect(p.decision, PermissionDecision.cancelled);
    expect(
      PermissionPrompt.fromJson({
        'requestId': '2',
        'toolName': 'Bash',
        'decision': 'allowedByHelmy',
      }).decision,
      PermissionDecision.allowedByHelmy,
    );
  });
}
