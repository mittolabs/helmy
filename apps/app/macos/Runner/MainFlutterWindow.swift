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

    // Hidden behind the splash until Flutter has drawn its first frame.
    self.alphaValue = 0
    Splash.shared.show(then: { [weak self] in
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.25
        self?.animator().alphaValue = 1
      }
    })

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


/// The window Helmy shows while it starts, before Flutter has drawn anything:
/// Helmy dreaming on a card, breathing, with its name. It follows the theme
/// set in Helmy (read from its settings, since Dart is not running yet), stays
/// at least a second so it never just flickers, and fades out when Dart says
/// it is ready, or after a while regardless.
final class Splash {
  static let shared = Splash()
  private var window: NSWindow?
  private var shownAt = Date()
  private var done: (() -> Void)?

  func show(then: @escaping () -> Void) {
    done = then
    let dark = Splash.isDark()
    let size = NSSize(width: 320, height: 380)
    let w = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
      backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = true
    w.level = .floating
    w.isReleasedWhenClosed = false

    let card = NSView(frame: NSRect(origin: .zero, size: size))
    card.wantsLayer = true
    card.layer?.cornerRadius = 28
    card.layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).cgColor
    card.layer?.borderWidth = 0.5
    card.layer?.borderColor = NSColor(white: dark ? 1 : 0, alpha: 0.12).cgColor

    let side: CGFloat = 220
    let picture = NSImageView(
      frame: NSRect(x: (size.width - side) / 2, y: 120, width: side, height: side))
    picture.image = NSImage(named: "SplashHelmy")
    picture.imageScaling = .scaleProportionallyUpOrDown
    picture.wantsLayer = true
    card.addSubview(picture)

    let ink = dark ? NSColor.white : NSColor.black
    let name = NSTextField(labelWithString: "Helmy")
    name.font = .systemFont(ofSize: 22, weight: .semibold)
    name.textColor = ink
    name.alignment = .center
    name.frame = NSRect(x: 0, y: 70, width: size.width, height: 30)
    card.addSubview(name)

    let tagline = NSTextField(labelWithString: "Dream it, do it.")
    tagline.font = .systemFont(ofSize: 13)
    tagline.textColor = ink.withAlphaComponent(0.55)
    tagline.alignment = .center
    tagline.frame = NSRect(x: 0, y: 46, width: size.width, height: 20)
    card.addSubview(tagline)

    w.contentView = card
    w.center()
    w.orderFrontRegardless()
    window = w
    shownAt = Date()

    // Breathing: a slow rise and fall, scaled from the picture's middle.
    if let layer = picture.layer {
      let frame = layer.frame
      layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
      layer.frame = frame
      let breathe = CABasicAnimation(keyPath: "transform.scale")
      breathe.fromValue = 1.0
      breathe.toValue = 1.035
      breathe.duration = 1.6
      breathe.autoreverses = true
      breathe.repeatCount = .infinity
      breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      layer.add(breathe, forKey: "breathe")
    }

    // If Dart never says it is ready, the app still shows.
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.finish() }
  }

  /// Dart is ready: fade out, at least a second after showing.
  func finish() {
    guard let w = window else { return }
    window = nil
    let wait = max(0, 1.0 - Date().timeIntervalSince(shownAt))
    DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
      self?.done?()
      self?.done = nil
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.3
        w.animator().alphaValue = 0
      }, completionHandler: { w.close() })
    }
  }

  /// The theme set in Helmy: light, dark, or the system's.
  private static func isDark() -> Bool {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first?.appendingPathComponent(Bundle.main.bundleIdentifier ?? "")
      .appendingPathComponent("settings.json")
    if let url = support, let data = try? Data(contentsOf: url),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let theme = json["theme"] as? String
    {
      if theme == "light" { return false }
      if theme == "dark" { return true }
    }
    return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
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
      case "ready":
        Splash.shared.finish()
        result(nil)
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
