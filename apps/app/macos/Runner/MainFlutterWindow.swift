import Cocoa
import FlutterMacOS
import ServiceManagement
import UserNotifications

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: true)
    self.center()
    self.minSize = NSSize(width: 760, height: 480)

    // Content runs under a transparent title bar; the app pads its top rows.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)
    Notifier.shared.attach(to: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Closing hides the window, so the Flutter engine and every session behind
  /// it keep running; the Dock icon brings it back. Off, it closes as usual.
  override func performClose(_ sender: Any?) {
    if AppDelegate.keepRunning { orderOut(sender) } else { super.performClose(sender) }
  }

  override func close() {
    if AppDelegate.keepRunning && !AppDelegate.quitting { orderOut(nil) } else { super.close() }
  }
}


/// Notifications and the dock badge for the Dart side, over "helmy/notify".
/// A click on a notification brings the app forward and tells Dart which
/// session it was about.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
  static let shared = Notifier()
  private var channel: FlutterMethodChannel?

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "helmy/notify", binaryMessenger: messenger)
    self.channel = channel
    UNUserNotificationCenter.current().delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "notify":
        self?.post(
          title: args["title"] as? String ?? "",
          body: args["body"] as? String ?? "",
          sessionId: args["sessionId"] as? String ?? "")
        result(nil)
      case "copyImage":
        // Flutter's clipboard holds text only; a picture goes through AppKit.
        let path = args["path"] as? String ?? ""
        if let image = NSImage(contentsOfFile: path) {
          NSPasteboard.general.clearContents()
          result(NSPasteboard.general.writeObjects([image]))
        } else {
          result(false)
        }
      case "pasteImage":
        // A picture on the clipboard, saved where Dart says, as PNG.
        let dest = args["path"] as? String ?? ""
        guard let image = NSImage(pasteboard: NSPasteboard.general),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
          result(nil)
          return
        }
        do {
          try png.write(to: URL(fileURLWithPath: dest))
          result(dest)
        } catch {
          result(nil)
        }
      case "openAtLogin":
        if #available(macOS 13.0, *) {
          if let on = args["on"] as? Bool {
            do {
              if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
              result(FlutterError(code: "login", message: error.localizedDescription, details: nil))
              return
            }
          }
          result(SMAppService.mainApp.status == .enabled)
        } else {
          result(nil)
        }
      case "keepRunning":
        AppDelegate.keepRunning = args["on"] as? Bool ?? true
        result(nil)
      case "isActive":
        result(NSApp.isActive)
      case "badge":
        let count = args["count"] as? Int ?? 0
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func post(title: String, body: String, sessionId: String) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      content.userInfo = ["sessionId": sessionId]
      // One notification per session: a newer one replaces the older.
      center.add(UNNotificationRequest(identifier: sessionId, content: content, trigger: nil))
    }
  }

  // Shown even while the app is in front: Dart only asks when the session in
  // question is not the one on screen.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let sessionId = response.notification.request.content.userInfo["sessionId"] as? String
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      if let sessionId { self.channel?.invokeMethod("open", arguments: sessionId) }
    }
    completionHandler()
  }
}
