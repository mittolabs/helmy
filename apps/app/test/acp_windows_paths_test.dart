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

  test("Antigravity's options are read as its code builds them: by category", () {
    // As agy_acp_server 1.5.0 sends them with a session (its _model_option,
    // _thinking_level_option and _mode_option).
    const model = {
      'id': 'model',
      'name': 'Model',
      'category': 'model',
      'type': 'select',
      'currentValue': 'gemini-3-pro',
      'options': [
        {'value': 'gemini-3-pro', 'name': 'Gemini 3 Pro'},
      ],
    };
    const thinking = {
      'id': 'thinking_level',
      'name': 'Thinking Level',
      'category': 'thought_level',
      'type': 'select',
    };
    const mode = {'id': 'mode', 'category': 'mode', 'type': 'select'};
    expect(AcpEngine.isModelOption(model), isTrue);
    expect(AcpEngine.isEffortOption(thinking), isTrue);
    expect(AcpEngine.isModelOption(mode), isFalse);
    expect(AcpEngine.isEffortOption(mode), isFalse);
    // An agent that names its model picker otherwise, marked by category.
    expect(AcpEngine.isModelOption({'id': 'llm', 'category': 'model'}), isTrue);
    // One from before categories, by its id alone.
    expect(AcpEngine.isModelOption({'id': 'model'}), isTrue);
    expect(AcpEngine.isEffortOption({'id': 'reasoning_effort'}), isTrue);
  });
}
