// Flutter's windowing is experimental: its API is internal, and the stable
// channel will not turn it on, so Helmy does (see enable). Found in the spike
// recorded in Mittolabs' docs/notes/helmy-tab-windows-spike.md.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/src/foundation/_features.dart' as features;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/widgets.dart';

import '../../data/services/desktop_service.dart';

/// Helmy's windows, all drawn by one engine with Flutter's windowing: the
/// main one, and (to come) a panel tab moved into a window of its own. One
/// engine, so every window shares the app's state as it is.
class HelmyWindows extends ChangeNotifier {
  /// Turns Flutter's windowing on, once the binding is up: the stable channel
  /// refuses its build flag, so its switch is set here, and the windowing
  /// owner made again with it on. Recheck after every Flutter update.
  static void enable() {
    features.isWindowingEnabled = true;
    WidgetsBinding.instance.windowingOwner = createDefaultWindowingOwner();
  }

  /// The main window, titled "Helmy": the runner finds it by that title and
  /// gives it Helmy's look (HelmyWindow in MainFlutterWindow.swift).
  final main = RegularWindowController(
    size: const Size(1200, 800),
    title: 'Helmy',
    delegate: _MainWindow(),
  );

  /// The windows, for runWidget: the main one with the app in it.
  Widget build(Widget app) => ViewCollection(
    views: [RegularWindow(controller: main, child: app)],
  );

  @override
  void dispose() {
    main.dispose();
    super.dispose();
  }
}

/// The main window's close button: hidden while chats keep working (the Dock
/// icon brings it back), closed (and the app with it) when the setting is
/// off.
class _MainWindow with RegularWindowControllerDelegate {
  @override
  void onWindowCloseRequested(RegularWindowController controller) {
    if (DesktopService.keepRunning) {
      DesktopService.hideMainWindow();
    } else {
      controller.destroy();
    }
  }
}
