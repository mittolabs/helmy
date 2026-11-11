import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/file_editor.dart';
import 'package:helmy/ui/chat/view_models/file_document.dart';

class FileEditorShot extends StatefulWidget {
  const FileEditorShot({super.key, this.draft = false});
  final bool draft;
  @override
  State<FileEditorShot> createState() => _FileEditorShotState();
}

class _FileEditorShotState extends State<FileEditorShot> {
  late final Directory root;
  late final ConversationRepositoryEngines repo;
  late final ChatViewModel vm;
  late final PanelTab tab;
  late final FileDocument document;
  @override
  void initState() {
    super.initState();
    root = Directory.systemTemp.createTempSync('editor-shot');
    final file = File('${root.path}/welcome.dart')
      ..writeAsStringSync('''// A free starting point for every new chat.
Future<void> connect() async {
  final connection = await installFree();
  await settings.enable(connection);
}
''');
    document = FileDocument.fromText(widget.draft ? '' : file.path, file.readAsStringSync());
    final storage = StorageService(root: () async => root);
    final meter = UsageMeter();
    final sessions = SessionRepositoryLocal(storage);
    repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    vm = ChatViewModel(sessionId: 'preview', sessions: sessions, conversations: repo);
    if (widget.draft) {
      vm.editCode(document.text, 'dart');
      tab = vm.active!;
    } else {
      tab = vm.add(SidePanel.files)..filePath = file.path;
    }
  }

  @override
  Widget build(BuildContext context) => FileEditor(vm: vm, tab: tab, document: document);

  @override
  void dispose() {
    vm.dispose();
    repo.dispose();
    super.dispose();
  }
}

class CodeDraftShot extends StatelessWidget {
  const CodeDraftShot({super.key});
  @override
  Widget build(BuildContext context) => const FileEditorShot(draft: true);
}
