import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/file_editor.dart';
import 'package:helmy/ui/chat/widgets/files_panel.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/utils/result.dart';

void main() {
  testWidgets('the file tree edits in place and protects unsaved files', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Directory root;
    late File file;
    late ChatViewModel vm;
    late ConversationRepositoryEngines repo;
    late StorageService storage;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('inline-editor');
      file = File('${root.path}/sample.dart');
      await file.writeAsString(
        '// A long comment that wraps when the panel gets narrow.\nvoid main() {\n  print("hello");\n}\n',
      );
      await File('${root.path}/other.dart').writeAsString('void other() {}');
      storage = StorageService(root: () async => root);
      final sessions = SessionRepositoryLocal(storage);
      final meter = UsageMeter();
      repo = ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      final session = (await sessions.create(cwd: root.path) as Ok).value as Session;
      repo.of(session.id).loaded = true;
      vm = ChatViewModel(sessionId: session.id, sessions: sessions, conversations: repo);
      final tab = vm.add(SidePanel.files);
      await tester.pumpWidget(
        AshlarApp(
          theme: appDarkTheme,
          home: FilesPanel(vm: vm, tab: tab),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    Future<void> choose(String name) async {
      await tester.runAsync(() async {
        await tester.tap(find.text(name).first);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    await choose('sample.dart');
    expect(find.byType(FileEditor), findsOneWidget);
    expect(vm.tabs, hasLength(1), reason: 'editing stays inside the file-browser tab');
    expect(find.text('other.dart'), findsOneWidget, reason: 'the file tree stays visible');
    await tester.enterText(
      find.byType(EditableText).last,
      'void main() {\n  print("edited");\n}\n',
    );
    await tester.pump();
    expect(vm.active!.hasUnsavedEdits, isTrue);
    await choose('other.dart');
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).controller.text,
      contains('edited'),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(vm.active!.hasUnsavedEdits, isFalse);
    await tester.runAsync(() async => expect(await file.readAsString(), contains('edited')));
    await choose('other.dart');
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).controller.text,
      'void other() {}',
    );
    expect(vm.tabs, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    vm.dispose();
    repo.dispose();
    await tester.runAsync(() async {
      await storage.flush();
      await root.delete(recursive: true);
    });
  });

  testWidgets('edit, find, save with keyboard, and discard inside the panel', (tester) async {
    late Directory root;
    late File file;
    late ChatViewModel vm;
    late ConversationRepositoryEngines repo;
    late StorageService storage;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('editor-widget');
      file = File('${root.path}/sample.dart');
      await file.writeAsString('void main() {\n  print("hello");\n}\n');
      storage = StorageService(root: () async => root);
      final sessions = SessionRepositoryLocal(storage);
      final meter = UsageMeter();
      repo = ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      final session = (await sessions.create(cwd: root.path) as Ok).value as Session;
      repo.of(session.id).loaded = true;
      vm = ChatViewModel(sessionId: session.id, sessions: sessions, conversations: repo);
      await vm.editFile(file.path);
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(
        AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: SizedBox(
            width: 380,
            child: FileEditor(vm: vm, tab: vm.active!),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final field = find.byType(EditableText).first;
    await tester.enterText(field, 'void main() {\n  print("world");\n}\n');
    await tester.pump();
    expect(vm.active!.hasUnsavedEdits, isTrue);
    await tester.runAsync(() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(vm.active!.hasUnsavedEdits, isFalse);
    await tester.runAsync(() async => expect(await file.readAsString(), contains('world')));
    await tester.tap(find.bySemanticsLabel('Find in file'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'world');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    final editor = tester.widget<EditableText>(find.byType(EditableText).last);
    expect(editor.controller.selection.textInside(editor.controller.text), 'world');
    await tester.enterText(find.byType(EditableText).last, 'unwanted edits');
    await tester.pump();
    await tester.tap(find.text('Discard edits'));
    await tester.pumpAndSettle();
    expect(editor.controller.text, contains('world'));
    expect(vm.active!.hasUnsavedEdits, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    vm.dispose();
    repo.dispose();
    await tester.runAsync(() async {
      await storage.flush();
      await root.delete(recursive: true);
    });
  });
}
