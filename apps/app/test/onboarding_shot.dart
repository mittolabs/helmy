import 'package:flutter/widgets.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/connections_setup.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/ui/onboarding/view_models/onboarding_view_model.dart';
import 'package:helmy/ui/onboarding/widgets/onboarding_screen.dart';
import '../testing/fake_repositories.dart';

class _PreviewModel extends OnboardingViewModel {
  _PreviewModel() : super(
    setup: ConnectionsSetup(CliLocator(), DesktopService()),
    settings: FakeSettingsRepository(),
    engines: EngineRegistry([]),
  );

  @override
  Future<void> check() async {
    checks = const [];
    notifyListeners();
  }
}

class OnboardingShot extends StatelessWidget {
  const OnboardingShot({super.key});

  @override
  Widget build(BuildContext context) => OnboardingScreen(vm: _PreviewModel());
}
