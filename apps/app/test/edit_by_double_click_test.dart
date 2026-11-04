import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/chat_items.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/core/ashlar/selection.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

/// Double-clicking your own message opens it to edit, inside the selectable
/// conversation, whose text selection also wants double-clicks.
void main() {
  testWidgets('double-clicking a message of yours opens it to edit', (tester) async {
    final root = Directory.systemTemp.createTempSync('dblclick');
    final storage = storageAt(root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    late ChatViewModel vm;
    await tester.runAsync(() async {
      final created = (await sessions.create(cwd: root.path) as Ok).value as Session;
      repo.of(created.id)
        ..loaded = true
        ..items.addAll([UserMessage('Hellodnd'), AssistantText('1', 'Hi!'), TurnSummary(ok: true)]);
      vm = ChatViewModel(sessionId: created.id, sessions: sessions, conversations: repo);
    });

    await tester.pumpWidget(
      AshlarApp(
        theme: appTheme,
        darkTheme: appDarkTheme,
        home: SelectableRegion(
          selectionControls: AshlarSelectionControls(const Color(0xFF000000)),
          child: ListenableBuilder(
            listenable: vm,
            builder: (context, _) => Column(children: [for (final r in buildRows(vm)) r.child]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(vm.editing, isNull);

    final at = tester.getCenter(find.text('Hellodnd'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at);
    for (var i = 0; i < 2; i++) {
      await mouse.down(at);
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(vm.editing, 0);

    // One click alone does not.
    vm.cancelEdit();
    await tester.pump(const Duration(seconds: 1));
    await mouse.down(at);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(vm.editing, isNull);

    // In place: the bubble becomes the text box, on the right where the
    // message was. Esc cancels.
    final bubbleRight = tester.getRect(find.text('Hellodnd')).right;
    vm.startEdit(0);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    final box = tester.getRect(find.byType(EditableText));
    expect(box.right, greaterThan(bubbleRight - 20), reason: 'on the right, where it was');
    expect(box.width, greaterThan(200), reason: 'room to type in');
    expect(find.text('Save'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(vm.editing, isNull);

    // Enter saves the change: the message is sent again as a new version.
    vm.startEdit(0);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Hello again');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    // Up to 5 s: a second was not enough with the suite running loaded.
    for (var i = 0; i < 100 && (vm.items.isEmpty || vm.busy); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(vm.editing, isNull);
    expect((vm.items.first as UserMessage).text, 'Hello again');
    expect((vm.items.first as UserMessage).branches!.length, 2);

    vm.dispose();
    repo.dispose();
    await tester.runAsync(() => deleteFolder(root));
  });
}
