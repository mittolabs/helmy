import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/desktop_service.dart';

void main() {
  test('a process is named by its program, even from a path with spaces', () {
    const agent =
        '/Users/a/Library/Application Support/com.mittolabs.helmy/agents/opencode/2.2.7/opencode';
    bool exists(String p) => p == agent || p == '/usr/bin/codex';
    expect(DesktopService.programName('$agent acp', exists: exists), 'OpenCode');
    expect(DesktopService.programName('/usr/bin/codex app-server', exists: exists), 'codex');
    expect(
      DesktopService.programName(
        '/x/Chromium --user-data-dir=/y/chromium/profiles/1',
        exists: exists,
      ),
      'Browser for the Preview panel',
    );
  });
}
