import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/acp/acp_engine.dart';
import 'package:helmy/data/services/engines/acp/acp_rpc.dart';

void main() {
  test('an agent saved by its path is looked at, on Windows too', () {
    // OpenCode found already installed by npm on Windows: its path has only
    // backslashes, and was once looked for on the PATH by that whole name.
    expect(AcpEngine.isPath(r'C:\Users\sam\AppData\Roaming\npm\opencode.cmd'), isTrue);
    expect(
      AcpEngine.isPath(r'C:\Users\sam\AppData\Roaming\helmy\agents\opencode/2.3.2/opencode.exe'),
      isTrue,
    );
    expect(AcpEngine.isPath('/Users/sam/.local/bin/opencode'), isTrue);
    expect(AcpEngine.isPath('npx'), isFalse);
  });

  test("npm's Windows scripts are started through a shell", () {
    expect(AcpRpc.runsInShell(r'C:\Users\sam\AppData\Roaming\npm\opencode.cmd'), isTrue);
    expect(AcpRpc.runsInShell(r'C:\x\OPENCODE.CMD'), isTrue);
    expect(AcpRpc.runsInShell(r'C:\x\opencode.exe'), isFalse);
    expect(AcpRpc.runsInShell('npx'), isFalse);
  });
}
