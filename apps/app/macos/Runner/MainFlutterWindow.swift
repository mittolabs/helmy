import ApplicationServices
import Cocoa
import CoreAudio
import CoreImage
import ScreenCaptureKit
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
    ScreenShare.attach(to: flutterViewController.engine.binaryMessenger)

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
      case "playSound":
        NSSound(named: args["name"] as? String ?? "Pop")?.play()
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
        var extra: (String, NSEvent.ModifierFlags)? = nil
        if let ch = args["char"] as? String, !ch.isEmpty {
          var mods: NSEvent.ModifierFlags = []
          if args["cmd"] as? Bool ?? false { mods.insert(.command) }
          if args["shift"] as? Bool ?? false { mods.insert(.shift) }
          if args["alt"] as? Bool ?? false { mods.insert(.option) }
          extra = (ch.lowercased(), mods)
        }
        result(Snapshots.shared.keys(args["on"] as? Bool ?? false, extra: extra))
      case "mac":
        MacActions.run(args, result)
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
  func keys(_ on: Bool, extra: (String, NSEvent.ModifierFlags)? = nil) -> Bool {
    for m in monitors { NSEvent.removeMonitor(m) }
    monitors = []
    guard on else { return false }
    // A shortcut of the user's own, beside both Shift keys.
    if let (char, mods) = extra {
      let press: (NSEvent) -> Bool = { [weak self] e in
        let held = e.modifierFlags.intersection([.command, .shift, .option, .control])
        guard held == mods, (e.charactersIgnoringModifiers ?? "").lowercased() == char,
              let self, Date().timeIntervalSince(self.last) > 0.8 else { return false }
        self.last = Date()
        if let w = Snapshots.front() { self.onKeys?(w) }
        return true
      }
      if let g = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { _ = press($0) }) {
        monitors.append(g)
      }
      if let l = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { press($0) ? nil : $0 }) {
        monitors.append(l)
      }
    }
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

/// What Helmy does on this Mac for the user, from its own process: pressing
/// the lock and media keys (which needs Accessibility), where sound plays,
/// quitting apps, ejecting drives. Answers "accessibility" when the
/// permission is missing, for the Dart side to say so with its fix.
enum MacActions {
  static func run(_ args: [String: Any], _ result: @escaping FlutterResult) {
    switch args["do"] as? String ?? "" {
    case "lock":
      guard Snapshots.trusted(prompt: false) else { return result("accessibility") }
      // Control-Command-Q, macOS's own Lock Screen; q is key 12.
      press(12, [.maskControl, .maskCommand])
      result(nil)
    case "media":
      guard Snapshots.trusted(prompt: false) else { return result("accessibility") }
      media(Int32(args["key"] as? Int ?? 16))
      result(nil)
    case "outputs":
      let current = defaultOutput()
      result(outputDevices().map { ["id": Int($0), "name": name(of: $0), "current": $0 == current] })
    case "setOutput":
      var id = AudioDeviceID(args["id"] as? Int ?? 0)
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
      let status = AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
        UInt32(MemoryLayout<AudioDeviceID>.size), &id)
      result(status == noErr)
    case "apps":
      result(NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        .map { ["name": $0.localizedName ?? "", "bundle": $0.bundleIdentifier ?? "", "pid": Int($0.processIdentifier)] })
    case "quit":
      let wanted = (args["name"] as? String ?? "").lowercased()
      let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
      let app = apps.first { ($0.localizedName ?? "").lowercased() == wanted || $0.bundleIdentifier?.lowercased() == wanted }
        ?? apps.first { ($0.localizedName ?? "").lowercased().contains(wanted) }
      guard let app else { return result("No open app is called \(args["name"] as? String ?? "that").") }
      if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
        return result("That is Helmy itself; it stays open.")
      }
      let done = (args["force"] as? Bool ?? false) ? app.forceTerminate() : app.terminate()
      result(done ? nil : "\(app.localizedName ?? "It") didn't take the request to quit.")
    case "drives":
      result(ejectable().map { $0.1 })
    case "eject":
      let drives = ejectable()
      DispatchQueue.global(qos: .userInitiated).async {
        var ejected: [String] = [], failed: [String] = []
        for (url, name) in drives {
          do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            ejected.append(name)
          } catch {
            failed.append(name)
          }
        }
        DispatchQueue.main.async { result(["ejected": ejected, "failed": failed]) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func press(_ key: CGKeyCode, _ flags: CGEventFlags) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
      let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
      e?.flags = flags
      e?.post(tap: .cghidEventTap)
    }
  }

  /// A media key (16 play/pause, 17 next, 18 previous), as the keyboard
  /// sends it: a system-defined event, down then up.
  static func media(_ key: Int32) {
    for down in [true, false] {
      let state: Int32 = down ? 0xA : 0xB
      let event = NSEvent.otherEvent(
        with: .systemDefined, location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
        timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
        data1: Int((key << 16) | (state << 8)), data2: -1)
      event?.cgEvent?.post(tap: .cghidEventTap)
    }
  }

  static func outputDevices() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.filter { id in
      var streams = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
      var n: UInt32 = 0
      return AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &n) == noErr && n > 0
    }
  }

  static func defaultOutput() -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
    return id
  }

  static func name(of id: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return "" }
    return name.takeRetainedValue() as String
  }

  /// External drives and disk images: everything mounted but the Mac's own.
  static func ejectable() -> [(URL, String)] {
    let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeNameKey]
    let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
    return urls.compactMap { url in
      guard url.path != "/", let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
      let external = v.volumeIsEjectable == true || v.volumeIsRemovable == true || v.volumeIsInternal == false
      return external ? (url, v.volumeName ?? url.lastPathComponent) : nil
    }
  }
}

/// This Mac's screen, for a paired phone to see and use: frames from
/// ScreenCaptureKit as JPEG, one at a time as Dart asks for the next (so a
/// slow network drops frames rather than queueing them), input posted as
/// real mouse and key events, and the mark that says someone is watching.
enum ScreenShare {
  static var channel: FlutterMethodChannel?

  static func attach(to messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "helmy/screen", binaryMessenger: messenger)
    channel = ch
    ch.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "start":
        guard #available(macOS 12.3, *) else { return result("This needs macOS 12.3 or later.") }
        guard CGPreflightScreenCaptureAccess() else { return result("record") }
        ScreenStream.shared.start(maxWidth: args["maxWidth"] as? Int ?? 1600, fps: args["fps"] as? Int ?? 12) { error in
          DispatchQueue.main.async {
            if error == nil { ShareMark.shared.show(args["mark"] as? String ?? "A phone is viewing this screen") }
            result(error)
          }
        }
      case "next":
        if #available(macOS 12.3, *) { ScreenStream.shared.next() }
        result(nil)
      case "stop":
        if #available(macOS 12.3, *) { ScreenStream.shared.stop() }
        ShareMark.shared.hide()
        result(nil)
      case "input":
        result(input(args))
      case "allowed":
        result(["record": CGPreflightScreenCaptureAccess(), "control": Snapshots.trusted(prompt: false)])
      case "askRecord":
        result(CGRequestScreenCaptureAccess())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    ShareMark.shared.onStop = { channel?.invokeMethod("stopped", arguments: "mark") }
  }

  /// The screen being shared, in global points.
  static var bounds: CGRect { CGDisplayBounds(CGMainDisplayID()) }

  private static var lastClick = (at: Date.distantPast, point: CGPoint.zero, count: 0)

  /// A phone's touch or key, as this Mac's own; "accessibility" when Helmy
  /// may not post events.
  static func input(_ a: [String: Any]) -> String? {
    guard Snapshots.trusted(prompt: false) else { return "accessibility" }
    let b = bounds
    let p = CGPoint(
      x: b.minX + max(0, min(1, a["x"] as? Double ?? 0.5)) * b.width,
      y: b.minY + max(0, min(1, a["y"] as? Double ?? 0.5)) * b.height)
    func mouse(_ type: CGEventType, _ button: CGMouseButton = .left, clicks: Int = 1) {
      let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button)
      e?.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
      e?.post(tap: .cghidEventTap)
    }
    switch a["kind"] as? String ?? "" {
    case "move":
      mouse(.mouseMoved)
    case "click":
      // Two clicks close in time and place are a double click, as on the Mac.
      let near = hypot(p.x - lastClick.point.x, p.y - lastClick.point.y) < 12
      let count = near && Date().timeIntervalSince(lastClick.at) < 0.45 ? lastClick.count + 1 : 1
      lastClick = (Date(), p, count)
      mouse(.mouseMoved)
      mouse(.leftMouseDown, clicks: count)
      mouse(.leftMouseUp, clicks: count)
    case "right":
      mouse(.mouseMoved)
      mouse(.rightMouseDown, .right)
      mouse(.rightMouseUp, .right)
    case "down":
      mouse(.mouseMoved)
      mouse(.leftMouseDown)
    case "drag":
      mouse(.leftMouseDragged)
    case "up":
      mouse(.leftMouseUp)
    case "scroll":
      mouse(.mouseMoved)
      let e = CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
        wheel1: Int32(a["dy"] as? Double ?? 0), wheel2: Int32(a["dx"] as? Double ?? 0), wheel3: 0)
      e?.post(tap: .cghidEventTap)
    case "text":
      for ch in (a["text"] as? String ?? "").utf16 {
        var c = ch
        for down in [true, false] {
          let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
          e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
          e?.post(tap: .cghidEventTap)
        }
      }
    case "key":
      // A US layout's key codes: named keys, and letters and digits for
      // shortcuts (⌘C), whatever the Mac's own layout prints for them.
      let codes: [String: CGKeyCode] = [
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
        "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
      ]
      guard let code = codes[(a["key"] as? String ?? "").lowercased()] else { return "unknown key" }
      var flags: CGEventFlags = []
      let mods = a["mods"] as? [String] ?? []
      if mods.contains("cmd") { flags.insert(.maskCommand) }
      if mods.contains("shift") { flags.insert(.maskShift) }
      if mods.contains("alt") { flags.insert(.maskAlternate) }
      if mods.contains("ctrl") { flags.insert(.maskControl) }
      MacActions.press(code, flags)
    default:
      return "unknown input"
    }
    return nil
  }
}

@available(macOS 12.3, *)
final class ScreenStream: NSObject, SCStreamOutput, SCStreamDelegate {
  static let shared = ScreenStream()
  private var stream: SCStream?
  private let queue = DispatchQueue(label: "helmy.screen")
  private let context = CIContext()

  /// The newest frame not yet sent, and whether Dart is waiting for one.
  private var latest: CVPixelBuffer?
  private var wanted = false

  func start(maxWidth: Int, fps: Int, done: @escaping (String?) -> Void) {
    if stream != nil { queue.async { self.wanted = true }; return done(nil) }
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
      guard let content,
        let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
      else { return done(error?.localizedDescription ?? "No screen to share.") }
      let config = SCStreamConfiguration()
      // The display's pixels, at most maxWidth wide: sharp enough to read.
      let scale = NSScreen.main?.backingScaleFactor ?? 2
      let width = min(Double(maxWidth), Double(display.width) * scale)
      config.width = Int(width)
      config.height = Int(width * Double(display.height) / Double(display.width))
      config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
      config.showsCursor = true
      config.pixelFormat = kCVPixelFormatType_32BGRA
      config.queueDepth = 3
      let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
      do {
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
      } catch {
        return done(error.localizedDescription)
      }
      s.startCapture { error in
        if let error { return done(error.localizedDescription) }
        self.stream = s
        self.queue.async { self.wanted = true }
        done(nil)
      }
    }
  }

  func stop() {
    stream?.stopCapture { _ in }
    stream = nil
    queue.async {
      self.latest = nil
      self.wanted = false
    }
  }

  /// Dart is ready for another frame: the newest at once, else the next.
  func next() {
    queue.async {
      if let b = self.latest {
        self.latest = nil
        self.send(b)
      } else {
        self.wanted = true
      }
    }
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, let buffer = sample.imageBuffer else { return }
    // Only frames with something new in them.
    if let info = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
      let raw = info.first?[.status] as? Int, SCFrameStatus(rawValue: raw) != .complete
    {
      return
    }
    if wanted {
      wanted = false
      send(buffer)
    } else {
      latest = buffer
    }
  }

  private func send(_ buffer: CVPixelBuffer) {
    let image = CIImage(cvPixelBuffer: buffer)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let jpeg = context.jpegRepresentation(
        of: image, colorSpace: space,
        options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.55])
    else { return }
    DispatchQueue.main.async {
      ScreenShare.channel?.invokeMethod("frame", arguments: FlutterStandardTypedData(bytes: jpeg))
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    self.stream = nil
    DispatchQueue.main.async {
      ShareMark.shared.hide()
      ScreenShare.channel?.invokeMethod("stopped", arguments: error.localizedDescription)
    }
  }
}

/// The mark at the top of the screen while a phone watches it: who, and a
/// Stop that ends it at once. Floats over everything, on every Space.
final class ShareMark {
  static let shared = ShareMark()
  var onStop: (() -> Void)?
  private var panel: NSPanel?
  private var label: NSTextField?

  func show(_ text: String) {
    if let panel {
      label?.stringValue = text
      panel.orderFrontRegardless()
      return
    }
    let p = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 340, height: 36),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.level = .statusBar
    p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    p.hidesOnDeactivate = false
    let box = NSVisualEffectView(frame: p.contentRect(forFrameRect: p.frame))
    box.material = .hudWindow
    box.blendingMode = .behindWindow
    box.state = .active
    box.wantsLayer = true
    box.layer?.cornerRadius = 18
    box.layer?.masksToBounds = true
    let dot = NSView(frame: NSRect(x: 14, y: 13, width: 10, height: 10))
    dot.wantsLayer = true
    dot.layer?.backgroundColor = NSColor.systemRed.cgColor
    dot.layer?.cornerRadius = 5
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.frame = NSRect(x: 32, y: 9, width: 228, height: 18)
    label.lineBreakMode = .byTruncatingTail
    let stop = NSButton(title: "Stop", target: self, action: #selector(stopPressed))
    stop.bezelStyle = .rounded
    stop.controlSize = .small
    stop.frame = NSRect(x: 268, y: 6, width: 62, height: 24)
    box.addSubview(dot)
    box.addSubview(label)
    box.addSubview(stop)
    p.contentView = box
    if let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == CGMainDisplayID() }) ?? NSScreen.main {
      let f = screen.visibleFrame
      p.setFrameOrigin(NSPoint(x: f.midX - 170, y: f.maxY - 46))
    }
    p.orderFrontRegardless()
    panel = p
    self.label = label
  }

  func hide() {
    panel?.orderOut(nil)
    panel = nil
    label = nil
  }

  @objc private func stopPressed() {
    hide()
    if #available(macOS 12.3, *) { ScreenStream.shared.stop() }
    onStop?()
  }
}
