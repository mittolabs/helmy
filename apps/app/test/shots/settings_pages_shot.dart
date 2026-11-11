import 'package:flutter/widgets.dart';
import 'package:helmy/data/repositories/lesson_repository.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:provider/provider.dart';

import '../../testing/fake_repositories.dart';

/// One Settings page, for `ashlar shot`.
Widget _page(SettingsSection section) {
  final settings = FakeSettingsRepository();
  final engines = EngineRegistry([]);
  final vm = SettingsViewModel(
    settings: settings,
    engines: engines,
    meter: UsageMeter(),
    memory: MemoryRepositoryEngines(engines),
  )..section = section;
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsRepository>.value(value: settings),
      ChangeNotifierProvider<LessonRepository>.value(value: LessonRepository(null)),
      Provider(create: (_) => DesktopService()),
    ],
    child: SettingsScreen(viewModel: vm),
  );
}

class UsageShot extends StatelessWidget {
  const UsageShot({super.key});
  @override
  Widget build(BuildContext context) => _page(.usage);
}

class ConnectionsShot extends StatelessWidget {
  const ConnectionsShot({super.key});
  @override
  Widget build(BuildContext context) => _page(.agents);
}

class StorageShot extends StatelessWidget {
  const StorageShot({super.key});
  @override
  Widget build(BuildContext context) => _page(.storage);
}

class DataShot extends StatelessWidget {
  const DataShot({super.key});
  @override
  Widget build(BuildContext context) => _page(.data);
}
