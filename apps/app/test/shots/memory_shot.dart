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

/// Settings, Memory, with more lessons than fit: for `ashlar shot`.
class MemoryShot extends StatelessWidget {
  const MemoryShot({super.key});

  static LessonRepository lessons() {
    final r = LessonRepository(null);
    const texts = [
      'Keep designs on the canvas; publish only when asked.',
      'Use US spelling and dollars in sample content.',
      'Run the tests before saying a change is done.',
      'Prefer one commit per change, with the reason in its body.',
      'Check a design at its real size, not a thumbnail.',
      'Ask before deleting anything outside the chat folder.',
      'Summaries lead with what changed, then what is left.',
      'Name sample people and places from around the world.',
      'Keep answers short unless asked for detail.',
      'Show money as dollars unless the task is about currencies.',
      'Mention when a check could not be run.',
      'Use the free connection for quick questions.',
    ];
    for (final (i, t) in texts.indexed) {
      r.add(
        Lesson(
          id: 'l$i',
          text: t,
          scope: i.isEven ? everywhere : '/Users/sam/Studio',
          kind: i % 3 == 0 ? 'correction' : 'habit',
          learnedAt: DateTime(2026, 11, 1 + i),
        ),
      );
    }
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final settings = FakeSettingsRepository();
    final engines = EngineRegistry([]);
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..section = .memory;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsRepository>.value(value: settings),
        ChangeNotifierProvider<LessonRepository>.value(value: lessons()),
        Provider(create: (_) => DesktopService()),
      ],
      child: SettingsScreen(viewModel: vm),
    );
  }
}
