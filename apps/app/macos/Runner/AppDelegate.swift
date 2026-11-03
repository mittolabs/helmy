import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Off by Dart's word, when the setting to keep running is turned off.
  static var keepRunning = true

  /// Set once Quit is under way, so the window really closes then.
  static var quitting = false

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
    if !flag { for window in sender.windows where window is MainFlutterWindow { window.makeKeyAndOrderFront(nil) } }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
