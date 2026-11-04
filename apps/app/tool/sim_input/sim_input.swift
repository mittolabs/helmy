// Helmy's simulator input: connects to one iOS simulator once and keeps the
// connection, so each tap costs milliseconds rather than a fresh connection.
// Built on the simulator frameworks AXe ships (MIT). One JSON action per line
// on stdin; one line back per action: "ok" or "error: <why>".
//   {"do":"tap","x":201,"y":437}
//   {"do":"swipe","x1":200,"y1":600,"x2":200,"y2":300,"duration":0.3}
//   {"do":"key","code":40}            (a USB keyboard usage: Return 40)
//   {"do":"button","name":"home"}
//   {"do":"text","text":"Hello!"}     (US keyboard characters; else an error
//                                      and the caller types it another way)
import FBControlCore
import FBSimulatorControl
import Foundation

final class Quiet: NSObject, FBEventReporter {
  var metadata: [String: String] = [:]
  func report(_ subject: FBEventReporterSubject) {}
  func addMetadata(_ metadata: [String: String]) {}
}

@MainActor
func connect(_ udid: String) async throws -> FBSimulatorHID {
  let logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false)
  FBControlCoreGlobalConfiguration.defaultLogger = logger
  try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(logger)
  let config = FBSimulatorControlConfiguration(deviceSetPath: nil, logger: logger, reporter: Quiet())
  let control = try FBSimulatorControl.withConfiguration(config)
  guard let sim = control.set.allSimulators.first(where: { $0.udid == udid }) else {
    throw NSError(domain: "helmy", code: 1, userInfo: [NSLocalizedDescriptionKey: "no simulator \(udid)"])
  }
  return try await sim.connectToHID()
}

/// A character as a US keyboard types it: its key, and whether with shift.
func keyOf(_ c: Character) -> (UInt32, Bool)? {
  let plain: [Character: UInt32] = [
    "1": 30, "2": 31, "3": 32, "4": 33, "5": 34, "6": 35, "7": 36, "8": 37, "9": 38, "0": 39,
    "\n": 40, "\t": 43, " ": 44, "-": 45, "=": 46, "[": 47, "]": 48, "\\": 49, ";": 51,
    "'": 52, "`": 53, ",": 54, ".": 55, "/": 56,
  ]
  let shifted: [Character: UInt32] = [
    "!": 30, "@": 31, "#": 32, "$": 33, "%": 34, "^": 35, "&": 36, "*": 37, "(": 38, ")": 39,
    "_": 45, "+": 46, "{": 47, "}": 48, "|": 49, ":": 51, "\"": 52, "~": 53, "<": 54, ">": 55,
    "?": 56,
  ]
  if let k = plain[c] { return (k, false) }
  if let k = shifted[c] { return (k, true) }
  guard c.isASCII, c.isLetter, let v = c.asciiValue else { return nil }
  return (UInt32(v | 0x20) - 97 + 4, c.isUppercase)
}

/// Text as key presses, or nil when a character has no key.
func typing(_ text: String) -> FBSimulatorHIDEvent? {
  var events: [FBSimulatorHIDEvent] = []
  for c in text {
    guard let (key, shift) = keyOf(c) else { return nil }
    if shift { events.append(.keyboard(direction: .down, keyCode: 225)) }
    events.append(.keyboard(direction: .down, keyCode: key))
    events.append(.keyboard(direction: .up, keyCode: key))
    if shift { events.append(.keyboard(direction: .up, keyCode: 225)) }
  }
  return .composite(events)
}

@MainActor
func run() async {
  guard CommandLine.arguments.count > 1 else {
    print("error: give the simulator's UDID")
    exit(2)
  }
  let hid: FBSimulatorHID
  let logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false)
  do {
    hid = try await connect(CommandLine.arguments[1])
  } catch {
    print("error: \(error.localizedDescription)")
    exit(1)
  }
  print("ready")
  fflush(stdout)
  while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let a = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let what = a["do"] as? String else {
      print("error: not an action")
      fflush(stdout)
      continue
    }
    func n(_ k: String) -> Double { (a[k] as? NSNumber)?.doubleValue ?? 0 }
    let event: FBSimulatorHIDEvent?
    switch what {
    case "tap": event = .tapAt(x: n("x"), y: n("y"))
    case "swipe":
      event = .swipe(n("x1"), yStart: n("y1"), xEnd: n("x2"), yEnd: n("y2"),
                     delta: 10, duration: a["duration"] == nil ? 0.3 : n("duration"))
    case "key": event = .shortKeyPress(UInt32(n("code")))
    case "text":
      guard let e = typing(a["text"] as? String ?? "") else {
        print("error: a character has no key")
        fflush(stdout)
        continue
      }
      event = e
    case "button": event = (a["name"] as? String) == "home" ? .shortButtonPress(.homeButton) : nil
    default: event = nil
    }
    guard let event else {
      print("error: unknown action \(what)")
      fflush(stdout)
      continue
    }
    do {
      try await hid.send(event: event, logger: logger)
      print("ok")
    } catch {
      print("error: \(error.localizedDescription)")
    }
    fflush(stdout)
  }
}

Task { @MainActor in
  await run()
  exit(0)
}
RunLoop.main.run()
