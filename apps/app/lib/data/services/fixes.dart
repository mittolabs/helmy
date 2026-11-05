import '../../domain/problem.dart';
import '../../utils/platform.dart';
import 'connections_setup.dart';
import 'desktop_service.dart';
import 'devices.dart';
import 'engines/ollama/ollama_doctor.dart';

/// Carries out the fixes Helmy offers where a problem happens. Retrying and
/// opening setup belong to the screen; these reach outside it: a connection's
/// sign-in, the model on this computer, the system's own permission panes.
class Fixes {
  Fixes(this._setup, this._desktop, [this._devices]);
  final ConnectionsSetup _setup;
  final DesktopService _desktop;
  final DeviceService? _devices;

  /// Does [fix] (for the connection [engineId], where it needs one). True
  /// when it worked, or the system's pane is open for the user to finish.
  Future<bool> apply(Fix fix, {String? engineId}) async {
    switch (fix) {
      case .signIn:
        final id = engineId ?? '';
        if (id.startsWith('claude')) {
          // Accounts beyond the first live in ~/.claude-<name>.
          return _setup.signIn('claude', configDir: id == 'claude' ? null : '$homeDir/.$id');
        }
        if (id.startsWith('codex')) {
          return _setup.signIn('codex', configDir: id == 'codex' ? null : '$homeDir/.$id');
        }
        return false;
      case .startLocal:
        return OllamaDoctor.ensure(start: true);
      case .allowSpeech || .allowNotifications || .allowAccessibility || .allowScreenRecording:
        final pane = systemPane(fix);
        if (pane == null) return false;
        await _desktop.open(pane);
        return true;
      case .installDeviceInput:
        return await _devices?.installIosInput() ?? false;
      case .retry || .setup || .wait:
        return false;
    }
  }

  /// The system's own settings pane for a permission, on this computer;
  /// null where there is none to open.
  static String? systemPane(Fix fix) => switch ((Desktop.current, fix)) {
    (.mac, .allowSpeech) =>
      'x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition',
    (.mac, .allowAccessibility) =>
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    (.mac, .allowScreenRecording) =>
      'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture',
    (.mac, .allowNotifications) =>
      'x-apple.systempreferences:com.apple.Notifications-Settings.extension',
    (.windows, .allowSpeech) => 'ms-settings:privacy-speech',
    (.windows, .allowNotifications) => 'ms-settings:notifications',
    _ => null,
  };
}
