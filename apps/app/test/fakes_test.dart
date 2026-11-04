import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/utils/result.dart';

import '../testing/fake_repositories.dart';

void main() {
  test('a view model runs on the fakes: a new session takes its project\'s level', () async {
    final root = await Directory.systemTemp.createTemp('fakes');
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final projects = FakeProjectRepository()..level = PermissionLevel.edit;
    final settings = FakeSettingsRepository(
      AppSettings(folderMode: FolderMode.fixed, fixedFolder: root.path),
    );
    final vm = SidebarViewModel(
      sessions: sessions,
      conversations: ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      ),
      settings: settings,
      attention: FakeAttentionRepository(),
      projects: projects,
    );
    await vm.create.execute();
    final made = (vm.create.result! as Ok).value as Session;
    expect(made.level, PermissionLevel.edit);
    vm.dispose();
    await root.delete(recursive: true);
  });
}
