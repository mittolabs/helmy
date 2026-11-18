import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/acp/acp_registry.dart';
import 'package:helmy/utils/paths.dart';
import 'package:path/path.dart' as p;

void main() {
  final win = p.Context(style: p.Style.windows, current: r'C:\Users\sam');
  final mac = p.Context(style: p.Style.posix, current: '/Users/sam');

  test('a name is read from a path with either separator', () {
    expect(baseName(r'C:\Users\sam\code\app\main.dart'), 'main.dart');
    expect(baseName('/Users/sam/code/app/main.dart'), 'main.dart');
    expect(baseName(r'C:\Users\sam\.claude-work\'), '.claude-work');
    expect(baseName('src/lib/a.dart'), 'a.dart');
    expect(baseName('a.dart'), 'a.dart');
    expect(programName(r'C:\Program Files\Git\bin\git.exe'), 'git');
    expect(programName(r'C:\Users\sam\AppData\Roaming\npm\opencode.CMD'), 'opencode');
    expect(programName('/usr/bin/git'), 'git');
  });

  test('the folder a path is in, as written', () {
    expect(parentOf(r'C:\Users\sam\code\app.html'), r'C:\Users\sam\code');
    expect(parentOf('/Users/sam/code/app.html'), '/Users/sam/code');
    expect(parentOf('src/a.dart'), 'src');
    expect(parentOf('a.dart'), '');
    expect(parentOf('/a'), '/');
  });

  test('whole paths on each system, and relative ones put in their folder', () {
    expect(isAbsolutePath(r'C:\Users\sam\a.txt', style: win), isTrue);
    expect(isAbsolutePath(r'\\server\share\a.txt', style: win), isTrue);
    expect(isAbsolutePath('/Users/sam/a.txt', style: mac), isTrue);
    expect(isAbsolutePath(r'src\a.txt', style: win), isFalse);
    expect(
      inFolder(r'C:\Users\sam\code', r'src\a.txt', style: win),
      r'C:\Users\sam\code\src\a.txt',
    );
    expect(inFolder(r'C:\Users\sam\code', 'src/a.txt', style: win), r'C:\Users\sam\code\src/a.txt');
    expect(inFolder(r'C:\Users\sam\code', r'D:\b.txt', style: win), r'D:\b.txt');
    expect(inFolder('/Users/sam/code', 'src/a.txt', style: mac), '/Users/sam/code/src/a.txt');
  });

  test('~ is the home folder, written either way', () {
    expect(expandHome(r'~\code', r'C:\Users\sam', style: win), r'C:\Users\sam\code');
    expect(expandHome('~/code', r'C:\Users\sam', style: win), r'C:\Users\sam\code');
    expect(expandHome('~/code', '/Users/sam', style: mac), '/Users/sam/code');
    expect(expandHome('~', '/Users/sam', style: mac), '/Users/sam');
    expect(expandHome('code', '/Users/sam', style: mac), 'code');
  });

  test('inside a folder, as each system compares paths', () {
    // Windows: either separator, any case.
    expect(isInside(r'C:\Users\Sam\Code\a.txt', r'c:\users\sam\code', style: win), isTrue);
    expect(isInside('C:/Users/sam/code/a.txt', r'C:\Users\sam\code', style: win), isTrue);
    expect(isInside(r'C:\Users\sam\code', r'C:\Users\sam\code\', style: win), isTrue);
    expect(isInside(r'C:\Users\sam\code\..\secrets', r'C:\Users\sam\code', style: win), isFalse);
    expect(isInside(r'C:\Users\sam\codebase\a', r'C:\Users\sam\code', style: win), isFalse);
    // A Mac and Linux: case counts.
    expect(isInside('/Users/sam/code/a.txt', '/Users/sam/code', style: mac), isTrue);
    expect(isInside('/Users/sam/code/../x', '/Users/sam/code', style: mac), isFalse);
  });

  test('a typed command keeps quoted words whole, backslashes and all', () {
    expect(commandWords(r'"C:\Program Files\Agent\agent.exe" --acp'), [
      r'C:\Program Files\Agent\agent.exe',
      '--acp',
    ]);
    expect(commandWords("my-agent  --mode 'two words'"), ['my-agent', '--mode', 'two words']);
    expect(commandWords(r'C:\tools\agent.exe acp'), [r'C:\tools\agent.exe', 'acp']);
  });

  test("OpenCode Desktop's program is looked for where each system's installer puts it", () {
    expect(desktopPrograms('opencode', os: 'macos', env: {'HOME': '/Users/sam'}), [
      '/Applications/OpenCode.app/Contents/Resources/opencode-cli',
      '/Users/sam/Applications/OpenCode.app/Contents/Resources/opencode-cli',
    ]);
    expect(
      desktopPrograms(
        'opencode',
        os: 'windows',
        env: {
          'USERPROFILE': r'C:\Users\sam',
          'LOCALAPPDATA': r'C:\Users\sam\AppData\Local',
          'ProgramFiles': r'C:\Program Files',
        },
      ),
      [
        r'C:\Users\sam\AppData\Local\Programs\ai.opencode.desktop\resources\opencode-cli.exe',
        r'C:\Users\sam\AppData\Local\Programs\@opencodedesktop\resources\opencode-cli.exe',
        r'C:\Users\sam\AppData\Local\Programs\OpenCode\resources\opencode-cli.exe',
        r'C:\Program Files\OpenCode\resources\opencode-cli.exe',
      ],
    );
    expect(desktopPrograms('opencode', os: 'linux', env: {'HOME': '/home/sam'}), [
      '/opt/OpenCode/resources/opencode-cli',
    ]);
    expect(desktopPrograms('cursor', os: 'macos', env: {}), isEmpty);
  });
}
