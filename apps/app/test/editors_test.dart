import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/editors.dart';

class _Locator extends CliLocator {
  _Locator(this.there);
  final Map<String, String> there;
  @override
  Future<String?> find(String name) async => there[name];
}

/// Opening a project in an editor on Windows and Linux: found by command,
/// and started with the folder the way each wants it.
void main() {
  test('found by their commands, one each', () async {
    final service = EditorService(
      locator: _Locator({
        'code': r'C:\Users\a\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd',
        'zeditor': '/usr/bin/zeditor',
        'konsole': '/usr/bin/konsole',
      }),
    );
    final found = await service.foundByCommand();
    expect(
      [for (final e in found) (e.name, e.kind)],
      [
        ('Visual Studio Code', EditorKind.editor),
        ('Zed', EditorKind.editor),
        ('Konsole', EditorKind.terminal),
      ],
    );
  });

  test('each told the folder its own way', () {
    expect(openArgs('com.microsoft.VSCode', 'code', '/p'), ['/p']);
    expect(openArgs('com.microsoft.WindowsTerminal', 'wt', r'C:\p'), ['-d', r'C:\p']);
    expect(openArgs('org.gnome.Terminal', 'gnome-terminal', '/p'), ['--working-directory=/p']);
    expect(openArgs('org.kde.konsole', 'konsole', '/p'), ['--workdir', '/p']);
  });
}
