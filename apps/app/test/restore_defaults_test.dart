import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/models/project_action.dart';
import 'package:helmy/domain/models/settings.dart';

void main() {
  test('nothing has changed in settings as Helmy ships them', () {
    expect(changedSettings(const AppSettings()), isEmpty);
  });

  test('what changed is named as Settings shows it, in its order', () {
    const s = AppSettings(
      theme: .dark,
      fixedFolder: '/w',
      folderMode: .fixed,
      editor: 'dev.zed.Zed',
      sort: .name,
      sidebarWidth: 400,
      sidebarOpen: false,
    );
    expect(changedSettings(s), [
      'Theme',
      'Default folder for new chats',
      'Editor projects open in',
      'Chat list',
    ]);
  });

  test('restoring puts back what was chosen and keeps what was set up', () {
    const s = AppSettings(
      theme: .dark,
      wrapCode: true,
      fixedFolder: '/w',
      folderMode: .fixed,
      chromiumBrowser: '/Applications/Brave.app',
      sidebarWidth: 400,
      disabledEngines: {'codex'},
      setupDone: true,
      projects: {
        '/p': ProjectSettings(
          actions: [ProjectAction(name: 'dev', command: 'npm run dev')],
        ),
      },
    );
    final all = withDefaults(s);
    expect(changedSettings(all), isEmpty);
    expect(all.fixedFolder, isNull, reason: 'a field that is empty by default is emptied');
    expect(all.chromiumBrowser, isNull);
    expect(all.sidebarWidth, 400);
    expect(all.disabledEngines, {'codex'});
    expect(all.setupDone, isTrue);
    expect(all.project('/p').actions.single.name, 'dev');

    // One alone, as its row's undo does.
    final one = withDefaults(s, ['Theme']);
    expect(one.theme, ThemeChoice.system);
    expect(one.wrapCode, isTrue);
  });
}
