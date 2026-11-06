import Cocoa
import FlutterMacOS
import desktop_multi_window
import file_selector_macos
import mobile_scanner
import screen_retriever_macos
import video_player_avfoundation
import webview_flutter_wkwebview
import window_manager

/// The main engine's plugins: all but the two that find their window through
/// a view of their own, which the main engine has not (its windows are
/// Flutter's). File drops are Helmy's own (HelmyDropTarget); window control
/// is only the floating player's, in its own engine.
func RegisterMainPlugins(registry: FlutterPluginRegistry) {
  // The floating player's plugin attaches to mainFlutterWindow, which is
  // Flutter's to make: registered once it is (HelmyWindow.adopt).
  FileSelectorPlugin.register(with: registry.registrar(forPlugin: "FileSelectorPlugin"))
  MobileScannerPlugin.register(with: registry.registrar(forPlugin: "MobileScannerPlugin"))
  ScreenRetrieverMacosPlugin.register(with: registry.registrar(forPlugin: "ScreenRetrieverMacosPlugin"))
  VideoPlayerPlugin.register(with: registry.registrar(forPlugin: "VideoPlayerPlugin"))
  WebViewFlutterPlugin.register(with: registry.registrar(forPlugin: "WebViewFlutterPlugin"))
}

@main
class AppDelegate: FlutterAppDelegate {
  /// Off by Dart's word, when the setting to keep running is turned off.
  static var keepRunning = true

  /// Set once Quit is under way, so the window really closes then.
  static var quitting = false

  /// Set by Dart while chats are working and the setting asks for it: the
  /// first ⌘Q only warns, a second within a few seconds quits.
  static var guardQuit = false
  private var warnedAt: Date?

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if AppDelegate.guardQuit, !AppDelegate.quitting {
      if let at = warnedAt, Date().timeIntervalSince(at) < 4 {
        warnedAt = nil
      } else {
        warnedAt = Date()
        Notifier.shared.tell("quitAsked", nil)
        return .terminateCancel
      }
    }
    AppDelegate.quitting = true
    return .terminateNow
  }

  // Closing the window hides it while sessions keep working; the app ends
  // with Quit. With the setting off, closing the window ends it as before.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !AppDelegate.keepRunning
  }

  // A click on the Dock icon brings the hidden window back.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag { HelmyWindow.main?.makeKeyAndOrderFront(nil) }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// The one engine every window of Helmy's draws with: run without a window
  /// of its own, as Flutter's windowing has it; Dart makes the main window
  /// ("Helmy"), and HelmyWindow gives it Helmy's look once it is made.
  var engine: FlutterEngine?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // About Helmy is Helmy's own window, with its open-source credits.
    DispatchQueue.main.async { About.take() }
    let engine = FlutterEngine(name: "helmy", project: nil)
    self.engine = engine
    engine.run(withEntrypoint: nil)
    RegisterMainPlugins(registry: engine)
    // Each floating player is its own Flutter engine, and gets every plugin:
    // the player, window control.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      // A floating window is rarely the focused one: it still sees the
      // pointer, so its controls show when the pointer is over it.
      controller.mouseTrackingMode = .always
    }
    Notifier.shared.attach(to: engine.binaryMessenger)
    ScreenShare.attach(to: engine.binaryMessenger)
    HelmyWindow.watch(engine: engine)
    // The splash shows until Dart has drawn; then the main window fades in.
    Splash.shared.show(then: {
      guard let w = HelmyWindow.main else { return }
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.25
        w.animator().alphaValue = 1
      }
    })
  }
}
