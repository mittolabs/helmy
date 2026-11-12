import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/acp/acp_engine.dart';
import 'package:helmy/ui/core/connection_logo.dart';

void main() {
  test('Cursor, Grok and Antigravity take any work, with logos of their own', () {
    for (final id in ['cursor', 'grok-build', 'antigravity-acp']) {
      expect(profileFor(id).general, isTrue, reason: id);
      expect(ConnectionLogo.assetFor('acp.$id'), isNotNull, reason: id);
    }
    expect(ConnectionLogo.assetFor('acp.opencode'), 'assets/logos/opencode.svg');
    // Any other agent from the registry answers only what it is set best at.
    expect(profileFor('gemini').general, isFalse);
    expect(ConnectionLogo.assetFor('acp.gemini'), isNull);
  });
}
