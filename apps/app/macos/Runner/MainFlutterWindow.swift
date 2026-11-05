import ApplicationServices
import Cocoa
import FlutterMacOS
import desktop_multi_window
import ServiceManagement
import Speech
import UserNotifications
import WebKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // About Helmy is Helmy's own window, with its open-source credits.
    DispatchQueue.main.async { About.take() }
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: true)
    self.center()
    // As narrow as a phone: the layout steps down to one column.
    self.minSize = NSSize(width: 360, height: 480)

    // Content runs under a transparent title bar; the app pads its top rows.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)
    // Each extra window (the floating player) is its own Flutter engine,
    // and gets the same plugins: the player, window control.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      // A floating window is rarely the focused one: it still sees the
      // pointer, so its controls show when the pointer is over it.
      controller.mouseTrackingMode = .always
    }
    Notifier.shared.attach(to: flutterViewController.engine.binaryMessenger)

    // In sight or not: focused (on top, being looked at), or not focused or
    // in the Dock. What a notification was about is seen once it is in sight.
    for (name, seen) in [
      (NSWindow.didBecomeKeyNotification, true),
      (NSWindow.didResignKeyNotification, false),
      (NSWindow.didMiniaturizeNotification, false),
    ] {
      NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { _ in
        Notifier.shared.tell("inSight", seen)
      }
    }

    // Full screen hides the window's buttons; the app's title row moves left
    // into their place.
    for (name, on) in [
      (NSWindow.willEnterFullScreenNotification, true),
      (NSWindow.willExitFullScreenNotification, false),
    ] {
      NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { _ in
        Notifier.shared.tell("fullScreen", on)
      }
    }

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
/// at least four seconds, and fades out when Dart says
/// it is ready, or after a while regardless.
final class Splash {
  static let shared = Splash()

  /// Long enough to see Helmy breathe a little: the owner's choice.
  static let minimum: TimeInterval = 4.0
  private var window: NSWindow?
  private var status: NSTextField?
  private var shownAt = Date()

  /// What Helmy is doing as it starts, as it says it; only real steps.
  func say(_ text: String) {
    status?.stringValue = text
  }
  private var done: (() -> Void)?

  func show(then: @escaping () -> Void) {
    done = then
    let dark = Splash.isDark()
    let size = NSSize(width: 320, height: 440)
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
      frame: NSRect(x: (size.width - side) / 2, y: 178, width: side, height: side))
    picture.image = NSImage(named: "SplashHelmy")
    picture.imageScaling = .scaleProportionallyUpOrDown
    picture.wantsLayer = true
    card.addSubview(picture)

    let ink = dark ? NSColor.white : NSColor.black
    let name = NSTextField(labelWithString: "Helmy")
    name.font = .systemFont(ofSize: 22, weight: .semibold)
    name.textColor = ink
    name.alignment = .center
    name.frame = NSRect(x: 0, y: 128, width: size.width, height: 30)
    card.addSubview(name)

    let tagline = NSTextField(labelWithString: "Dream it, do it.")
    tagline.font = .systemFont(ofSize: 13)
    tagline.textColor = ink.withAlphaComponent(0.55)
    tagline.alignment = .center
    tagline.frame = NSRect(x: 0, y: 104, width: size.width, height: 20)
    card.addSubview(tagline)

    // The version, read from the app itself.
    if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
      let version = NSTextField(labelWithString: "Version \(v)")
      version.font = .systemFont(ofSize: 11)
      version.textColor = ink.withAlphaComponent(0.4)
      version.alignment = .center
      version.frame = NSRect(x: 0, y: 84, width: size.width, height: 16)
      card.addSubview(version)
    }

    let step = NSTextField(labelWithString: "Starting…")
    step.font = .systemFont(ofSize: 11)
    step.textColor = ink.withAlphaComponent(0.55)
    step.alignment = .center
    step.frame = NSRect(x: 0, y: 66, width: size.width, height: 16)
    card.addSubview(step)
    status = step

    // At the foot, as the sites have it: the mark, "Powered by Mittolabs",
    // then the notice, small and quiet.
    let mark = NSImageView()
    mark.image = NSImage(named: dark ? "MittolabsWhite" : "Mittolabs")
    mark.imageScaling = .scaleProportionallyUpOrDown
    let powered = NSTextField(labelWithAttributedString: {
      let s = NSMutableAttributedString(
        string: "Powered by ",
        attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: ink.withAlphaComponent(0.55)])
      s.append(NSAttributedString(
        string: "Mittolabs",
        attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: ink]))
      return s
    }())
    powered.sizeToFit()
    let markSide: CGFloat = 16
    let rowWidth = markSide + 6 + powered.frame.width
    let rowX = (size.width - rowWidth) / 2
    mark.frame = NSRect(x: rowX, y: 44, width: markSide, height: markSide * 87 / 96)
    powered.frame.origin = NSPoint(x: rowX + markSide + 6, y: 42)
    card.addSubview(mark)
    card.addSubview(powered)

    let year = Calendar.current.component(.year, from: Date())
    let notice = NSTextField(labelWithString: "© \(year) Mittolabs · BSD license")
    notice.font = .systemFont(ofSize: 11)
    notice.textColor = ink.withAlphaComponent(0.4)
    notice.alignment = .center
    notice.frame = NSRect(x: 0, y: 20, width: size.width, height: 16)
    card.addSubview(notice)

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

  /// Dart is ready: fade out, no sooner than [minimum] after showing.
  func finish() {
    guard let w = window else { return }
    say("Ready")
    window = nil
    let wait = max(0, Splash.minimum - Date().timeIntervalSince(shownAt))
    DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
      self?.done?()
      self?.done = nil
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.4
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

  /// Tells the Dart side something about the window.
  func tell(_ method: String, _ arguments: Any?) {
    channel?.invokeMethod(method, arguments: arguments)
  }

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
      case "splash":
        Splash.shared.say(args["text"] as? String ?? "")
        result(nil)
      case "notify":
        let banner = args["banner"] as? Bool ?? true
        let sound = args["sound"] as? Bool ?? true
        if banner {
          self?.post(
            title: args["title"] as? String ?? "",
            body: args["body"] as? String ?? "",
            sessionId: args["sessionId"] as? String ?? "",
            thumbsUp: args["thumbsUp"] as? Bool ?? false,
            sound: sound)
        } else if sound {
          NSSound(named: "Glass")?.play()
        }
        result(nil)
      case "quitGuard":
        AppDelegate.guardQuit = args["on"] as? Bool ?? false
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
      case "notificationsAllowed":
        // Whether macOS lets Helmy notify: false only when the user said no
        // (not before it was ever asked).
        UNUserNotificationCenter.current().getNotificationSettings { s in
          DispatchQueue.main.async { result(s.authorizationStatus != .denied) }
        }
      case "isActive":
        // In front and showing: a hidden or minimized window is not in sight,
        // though the app may still be the active one.
        let window = NSApp.windows.first { $0 is MainFlutterWindow }
        result(NSApp.isActive && (window?.isVisible ?? false) && !(window?.isMiniaturized ?? true))
      case "clearNotification":
        // A session's notification, gone from Notification Center once seen.
        let id = args["sessionId"] as? String ?? ""
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        result(nil)
      case "badge":
        let count = args["count"] as? Int ?? 0
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        result(nil)
      case "transcribe":
        // A sound file's words, recognized on this Mac.
        Transcriber.transcribe(path: args["path"] as? String ?? "") { text, error in
          if let text { result(text) } else {
            result(FlutterError(code: "transcribe", message: error, details: nil))
          }
        }
      case "titleBarDoubleClick":
        // What a double-click on a title bar does, as set in Desktop & Dock.
        let window = NSApp.mainWindow ?? NSApp.windows.first { $0 is MainFlutterWindow }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window?.performMiniaturize(nil)
        case "None": break
        default: window?.performZoom(nil)
        }
        result(nil)
      case "face":
        DockFace.shared.show(args["face"] as? String)
        result(nil)
      case "snapWindows":
        result(Snapshots.windows())
      case "snapCapture":
        // Off the main thread: screencapture takes a moment.
        let id = args["id"] as? Int ?? 0
        let path = args["path"] as? String ?? ""
        DispatchQueue.global(qos: .userInitiated).async {
          let ok = Snapshots.capture(id, to: path)
          DispatchQueue.main.async { result(ok) }
        }
      case "snapText":
        let pid = args["pid"] as? Int ?? 0
        let title = args["title"] as? String ?? ""
        DispatchQueue.global(qos: .userInitiated).async {
          let text = Snapshots.text(pid: pid, title: title)
          DispatchQueue.main.async { result(text) }
        }
      case "snapAllowed":
        result(["record": Snapshots.canRecord(), "read": Snapshots.trusted(prompt: false)])
      case "snapAskRecord":
        result(Snapshots.askRecord())
      case "snapAskRead":
        result(Snapshots.trusted(prompt: true))
      case "snapKeys":
        Snapshots.shared.onKeys = { [weak self] w in self?.tell("snapshot", w) }
        result(Snapshots.shared.keys(args["on"] as? Bool ?? false))
      case "activate":
        NSApp.activate(ignoringOtherApps: true)
        result(nil)
      case "apps":
        // Which of these apps (by bundle id) are installed: where, their
        // name, when last used, and their icon. Off the main thread: asking
        // Spotlight for the dates can take a moment.
        let ids = args["ids"] as? [String] ?? []
        DispatchQueue.global(qos: .userInitiated).async {
          let found = ids.compactMap { Notifier.app($0) }
          DispatchQueue.main.async { result(found) }
        }
      case "webSnapshot":
        // A picture of the page in the Preview panel, as PNG, at the
        // screen's sharpness; nil when there is none.
        Notifier.snapshot(path: args["path"] as? String ?? "") { result($0) }
      case "webPage":
        // The page in the Preview panel: the largest web view in the window.
        result(Notifier.webPage(args["do"] as? String ?? "", args))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// The largest web view in the main window: the Preview panel's page.
  static func previewWebView() -> WKWebView? {
    func all(_ v: NSView) -> [WKWebView] {
      (v as? WKWebView).map { [$0] } ?? v.subviews.flatMap(all)
    }
    guard let root = (NSApp.mainWindow ?? NSApp.windows.first)?.contentView else { return nil }
    return all(root).max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
  }

  /// Saves a picture of the Preview panel's page to [path]; the path, or nil.
  static func snapshot(path: String, done: @escaping (String?) -> Void) {
    guard let web = previewWebView() else { return done(nil) }
    web.takeSnapshot(with: nil) { image, _ in
      guard let image, let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
      else { return done(nil) }
      do {
        try png.write(to: URL(fileURLWithPath: path))
        done(path)
      } catch {
        done(nil)
      }
    }
  }

  /// Does [action] to the largest web view in the main window (the Preview
  /// panel's): its inspector, its zoom, a reload past the cache, or the
  /// appearance the page sees. False when there is no page.
  /// An installed app by bundle id: its path, name, when it was last used
  /// (milliseconds since 1970, or nil when macOS has not recorded it) and
  /// its icon as a 64-pixel PNG.
  static func app(_ id: String) -> [String: Any]? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
    var out: [String: Any] = ["id": id, "path": url.path]
    let name = FileManager.default.displayName(atPath: url.path)
    out["name"] = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    if let item = NSMetadataItem(url: url),
       let used = item.value(forAttribute: "kMDItemLastUsedDate") as? Date {
      out["lastUsed"] = Int(used.timeIntervalSince1970 * 1000)
    }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    let size = NSSize(width: 64, height: 64)
    if let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0) {
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
      icon.draw(in: NSRect(origin: .zero, size: size))
      NSGraphicsContext.restoreGraphicsState()
      if let png = rep.representation(using: .png, properties: [:]) {
        out["icon"] = FlutterStandardTypedData(bytes: png)
      }
    }
    return out
  }

  static func webPage(_ action: String, _ args: [String: Any]) -> Bool {
    func all(_ v: NSView) -> [WKWebView] {
      (v as? WKWebView).map { [$0] } ?? v.subviews.flatMap(all)
    }
    guard let root = (NSApp.mainWindow ?? NSApp.windows.first)?.contentView,
          let web = all(root).max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
    else { return false }
    switch action {
    case "inspect":
      // WebKit's own inspector, as Safari opens it: developer extras on for
      // the page, then shown.
      if #available(macOS 13.3, *) { web.isInspectable = true }
      web.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
      guard let inspector = web.perform(NSSelectorFromString("_inspector"))?.takeUnretainedValue() as? NSObject,
            inspector.responds(to: NSSelectorFromString("show"))
      else { return false }
      inspector.perform(NSSelectorFromString("show"))
      // Docked to the page; without this some versions open it nowhere.
      if inspector.responds(to: NSSelectorFromString("attach")) {
        inspector.perform(NSSelectorFromString("attach"))
      }
      return true
    case "inspecting":
      // Whether the inspector is showing, so a press is never reported as
      // working when it did not.
      guard let inspector = web.perform(NSSelectorFromString("_inspector"))?.takeUnretainedValue() as? NSObject,
            inspector.responds(to: NSSelectorFromString("isVisible"))
      else { return false }
      return inspector.value(forKey: "visible") as? Bool ?? false
    case "zoom":
      web.pageZoom = CGFloat(args["zoom"] as? Double ?? 1)
      return true
    case "hardReload":
      web.reloadFromOrigin()
      return true
    case "appearance":
      switch args["appearance"] as? String {
      case "light": web.appearance = NSAppearance(named: .aqua)
      case "dark": web.appearance = NSAppearance(named: .darkAqua)
      default: web.appearance = nil
      }
      return true
    default:
      return false
    }
  }

  /// Helmy's thumbs up as a notification picture. macOS moves an attachment's
  /// file into its own store, so each notification gets a fresh copy.
  private static func thumbsUp() -> UNNotificationAttachment? {
    guard let image = NSImage(named: "ThumbsUp"), let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { return nil }
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("thumbs-up-\(UUID().uuidString).png")
    do {
      try png.write(to: file)
      return try UNNotificationAttachment(identifier: "thumbs-up", url: file)
    } catch {
      return nil
    }
  }

  private func post(title: String, body: String, sessionId: String, thumbsUp: Bool, sound: Bool) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = sound ? .default : nil
      content.userInfo = ["sessionId": sessionId]
      if thumbsUp, let picture = Notifier.thumbsUp() {
        content.attachments = [picture]
      }
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
    completionHandler(notification.request.content.sound == nil ? [.banner] : [.banner, .sound])
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

/// Helmy's face in the Dock, changed with what it is doing: waking up,
/// thinking,
/// answering, needs you, working in the background, done, went wrong,
/// offline, dozing.
/// Drawn exactly as macOS draws the app icon (the same tile, the head at the
/// same size and place, white or black by the Mac's icon style), so only the
/// face changes. No face is the app icon itself.
final class DockFace {
  static let shared = DockFace()
  private var face: String?
  private var watching: NSKeyValueObservation?

  func show(_ name: String?) {
    if watching == nil {
      // Redrawn when the Mac switches between light and dark.
      watching = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
        DispatchQueue.main.async { self?.draw() }
      }
    }
    guard name != face else { return }
    face = name
    draw()
  }

  /// The Dock's icons follow "Icon & widget style" in System Settings, not
  /// the light or dark appearance: they stay light unless that says dark.
  private var darkIcons: Bool {
    let style = UserDefaults.standard.string(forKey: "AppleIconAppearanceTheme") ?? ""
    if style.contains("Dark") { return true }
    if style.contains("Automatic") {
      return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
    return false
  }

  private func draw() {
    guard let name = face, let head = NSImage(named: "Face-\(name)") else {
      NSApp.applicationIconImage = nil
      return
    }
    let dark = darkIcons
    let size: CGFloat = 1024
    let icon = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
      // macOS's icon grid: an 824-point rounded square, centered.
      let shape = NSBezierPath(
        roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
      (dark ? NSColor.black : NSColor.white).setFill()
      shape.fill()
      shape.addClip()
      // Where macOS puts the app icon's head (measured from its own render
      // of the icon), so the face lands on it exactly; the tile trims the ear
      // pieces the same way.
      // On black, the face whose ear pieces are lifted to read against it.
      NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
        head.draw(
          in: NSRect(x: 18, y: 9, width: 988, height: 988), from: .zero, operation: .sourceOver,
          fraction: 1)
      }
      return true
    }
    NSApp.applicationIconImage = icon
  }
}

/// Speech in a sound file, as text, by macOS's own recognizer: on this Mac
/// when it can (the sound never leaves it), in the user's language. Asks the
/// user's permission the first time.
enum Transcriber {
  static func transcribe(path: String, done: @escaping (String?, String?) -> Void) {
    let finish = { (text: String?, error: String?) in
      DispatchQueue.main.async { done(text, error) }
    }
    SFSpeechRecognizer.requestAuthorization { status in
      guard status == .authorized else {
        return finish(nil, "Speech recognition is not allowed for Helmy.")
      }
      guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
        return finish(nil, "Speech recognition is not available.")
      }
      let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
      request.shouldReportPartialResults = false
      // Names it would not know, spelled as they are.
      request.contextualStrings = ["Helmy", "Mittolabs"]
      if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
      var answered = false
      recognizer.recognitionTask(with: request) { result, error in
        if answered { return }
        if let result, result.isFinal {
          answered = true
          finish(result.bestTranscription.formattedString, nil)
        } else if let error {
          answered = true
          // No speech in it is an empty transcript, not a failure.
          let nsError = error as NSError
          if nsError.code == 1110 { finish("", nil) } else { finish(nil, error.localizedDescription) }
        }
      }
    }
  }
}

/// About Helmy, from the app's menu: asks the app to show its own window.
final class About: NSObject {
  static let shared = About()

  static func take() {
    for item in NSApp.mainMenu?.items.first?.submenu?.items ?? []
    where item.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)) {
      item.target = About.shared
      item.action = #selector(About.show(_:))
    }
  }

  // The Mac's own About window: Helmy, its version, and the notice. The
  // open-source credits live on the site, not in the app.
  @objc func show(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
      .credits: NSAttributedString(string: ""),
      NSApplication.AboutPanelOptionKey(rawValue: "Copyright"):
        "© \(Calendar.current.component(.year, from: Date())) Mittolabs · BSD license",
    ])
  }


}


/// SnapShots: a window of any app, captured into the message being written,
/// with the text in it where macOS gives it (its accessibility data), as T3
/// Code has them. Both Shift keys together take the window in front.
final class Snapshots {
  static let shared = Snapshots()
  private var monitors: [Any] = []
  private var last = Date.distantPast
  var onKeys: (([String: Any]) -> Void)?

  /// Whether macOS lets Helmy see other apps' windows' pixels.
  static func canRecord() -> Bool { CGPreflightScreenCaptureAccess() }

  /// Asks for screen recording: macOS shows its prompt once, then only the
  /// settings pane grants it.
  static func askRecord() -> Bool { CGRequestScreenCaptureAccess() }

  /// Whether Helmy may read other apps' windows (and hear keys anywhere).
  static func trusted(prompt: Bool) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  /// The windows on screen, front to back, other than the menu bar's and
  /// the Dock's: id, app, its process, title.
  static func windows(includeHelmy: Bool = false) -> [[String: Any]] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] else { return [] }
    let me = ProcessInfo.processInfo.processIdentifier
    return list.compactMap { w in
      guard (w[kCGWindowLayer as String] as? Int) == 0,
            let id = w[kCGWindowNumber as String] as? Int,
            let pid = w[kCGWindowOwnerPID as String] as? Int32,
            let app = w[kCGWindowOwnerName as String] as? String,
            let bounds = w[kCGWindowBounds as String] as? [String: CGFloat],
            (bounds["Width"] ?? 0) > 80, (bounds["Height"] ?? 0) > 60
      else { return nil }
      if pid == me && !includeHelmy { return nil }
      return ["id": id, "pid": Int(pid), "app": app, "title": w[kCGWindowName as String] as? String ?? ""]
    }
  }

  /// The window in front of the app in front: what both Shift keys take.
  static func front() -> [String: Any]? {
    guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
    return windows(includeHelmy: true).first { ($0["pid"] as? Int) == Int(pid) }
  }

  /// The window [id] as a PNG at [path]: its own pixels, not what covers it.
  static func capture(_ id: Int, to path: String) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l\(id)", path]
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0 && FileManager.default.fileExists(atPath: path)
  }

  /// The text in a window of [pid] titled [title] (else its focused one), as
  /// an outline of what is in it: roles, names, values. Nil when Helmy may
  /// not read it, or the app does not say. Stops at a second and a half.
  static func text(pid: Int, title: String) -> String? {
    guard trusted(prompt: false) else { return nil }
    let app = AXUIElementCreateApplication(pid_t(pid))
    AXUIElementSetMessagingTimeout(app, 1.0)
    func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
      var v: AnyObject?
      return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    var window: AXUIElement?
    if let all = attr(app, kAXWindowsAttribute) as? [AXUIElement] {
      window = all.first { (attr($0, kAXTitleAttribute) as? String) == title }
    }
    if window == nil, let w = attr(app, kAXFocusedWindowAttribute) { window = (w as! AXUIElement) }
    guard let root = window else { return nil }
    let until = Date().addingTimeInterval(1.5)
    var lines: [String] = []
    func walk(_ e: AXUIElement, _ depth: Int) {
      if lines.count >= 600 || depth > 30 || Date() > until { return }
      let role = (attr(e, kAXRoleAttribute) as? String ?? "").replacingOccurrences(of: "AX", with: "")
      let words = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
        .compactMap { attr(e, $0) as? String }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      if !words.isEmpty {
        var seen = Set<String>()
        let unique = words.filter { seen.insert($0).inserted }
        lines.append(String(repeating: "  ", count: min(depth, 12)) + "- \(role): " + unique.joined(separator: " | "))
      }
      for child in attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] { walk(child, depth + 1) }
    }
    walk(root, 0)
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  /// Both Shift keys together, in any app: on or off. True when on and
  /// macOS lets Helmy hear keys in other apps.
  func keys(_ on: Bool) -> Bool {
    for m in monitors { NSEvent.removeMonitor(m) }
    monitors = []
    guard on else { return false }
    let handle: (NSEvent) -> Void = { [weak self] e in
      let raw = e.modifierFlags.rawValue
      // The left and right Shift keys' own bits, and no other modifier.
      let both = raw & 0x2 != 0 && raw & 0x4 != 0
      let others = e.modifierFlags.intersection([.command, .option, .control])
      guard both, others.isEmpty, let self, Date().timeIntervalSince(self.last) > 0.8 else { return }
      self.last = Date()
      if let w = Snapshots.front() { self.onKeys?(w) }
    }
    if let g = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handle) { monitors.append(g) }
    if let l = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { handle($0); return $0 }) {
      monitors.append(l)
    }
    return Snapshots.trusted(prompt: false)
  }
}
