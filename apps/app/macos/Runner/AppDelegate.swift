import Cocoa
import FlutterMacOS

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
    if !flag { for window in sender.windows where window is MainFlutterWindow { window.makeKeyAndOrderFront(nil) } }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
