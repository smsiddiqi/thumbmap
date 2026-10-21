// ThumbMap — remaps the extra (thumb) buttons on a mouse under macOS.
//
// Design:
//   * A Quartz event tap intercepts "other" mouse buttons (button 2 and up).
//   * Each mapped button can have a TAP action and a HOLD action.
//       - If a button has no HOLD action, its TAP action fires instantly on press.
//       - If it has a HOLD action, a quick click fires TAP on release, and holding
//         past `holdThresholdMs` starts HOLD; releasing the button ends HOLD.
//         Key-chord and mouse-button HOLD actions stay pressed for as long as you
//         hold the mouse button, which is exactly what push-to-talk dictation needs.
//   * Mapped buttons are swallowed, so browsers no longer treat them as Back/Forward.
//
// Config:  ~/.config/thumbmap/config.json
// Log:     ~/Library/Logs/ThumbMap.log
// Signals: SIGHUP  -> reload config
//          SIGUSR1 -> "record helper": 4 s later, performs the first HOLD chord for
//                     1.5 s so another app's shortcut recorder can capture it.

import Cocoa
import ApplicationServices

// MARK: - Configuration

struct Action: Codable {
    /// none | spaceLeft | spaceRight | missionControl | appWindows | keys | mouseButton | shell
    var type: String
    var keyCode: Int?          // for "keys" (virtual key code; omit for a modifier-only chord)
    var modifiers: [String]?   // for "keys": control, option, command, shift, fn
    var button: Int?           // for "mouseButton": 0-based button number to synthesize
    var command: String?       // for "shell": run via /bin/zsh -lc
}

struct ButtonMap: Codable {
    var name: String?
    var tap: Action?
    var hold: Action?
}

struct Config: Codable {
    var holdThresholdMs: Int?
    var logButtons: Bool?
    var buttons: [String: ButtonMap]
}

let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/thumbmap/config.json")

var config = Config(holdThresholdMs: 300, logButtons: true, buttons: [:])

let isoFormatter = ISO8601DateFormatter()
func log(_ message: String) {
    print("[\(isoFormatter.string(from: Date()))] \(message)")
    fflush(stdout)
}

func loadConfig() {
    do {
        let data = try Data(contentsOf: configURL)
        config = try JSONDecoder().decode(Config.self, from: data)
        let summary = config.buttons.keys.sorted().map { key -> String in
            let m = config.buttons[key]!
            return "\(key)(\(m.name ?? "unnamed"): tap=\(m.tap?.type ?? "-"), hold=\(m.hold?.type ?? "-"))"
        }.joined(separator: ", ")
        log("Loaded config: \(summary)")
    } catch {
        log("Could not load \(configURL.path): \(error). Keeping previous config.")
    }
}

// MARK: - Event synthesis

/// Marker stamped on every event we post, so our own tap ignores it.
let kSyntheticMarker: Int64 = 0x5448_4D50 // "THMP"

let eventSource = CGEventSource(stateID: .hidSystemState)

let modifierTable: [String: (key: CGKeyCode, flag: CGEventFlags)] = [
    "control": (59, .maskControl),
    "option":  (58, .maskAlternate),
    "command": (55, .maskCommand),
    "shift":   (56, .maskShift),
    "fn":      (63, .maskSecondaryFn),
]

/// Arrow keys on Apple hardware carry the Fn and NumericPad flags; Mission Control's
/// "Move left/right a space" shortcut matches reliably only when they are present.
let arrowFlags: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]

enum KeyCode {
    static let left: CGKeyCode = 123
    static let right: CGKeyCode = 124
    static let down: CGKeyCode = 125
    static let up: CGKeyCode = 126
}

func post(_ event: CGEvent?) {
    guard let event = event else { return }
    event.setIntegerValueField(.eventSourceUserData, value: kSyntheticMarker)
    event.post(tap: .cghidEventTap)
}

func modifierFlags(_ names: [String]) -> CGEventFlags {
    var flags: CGEventFlags = []
    for name in names { if let entry = modifierTable[name.lowercased()] { flags.insert(entry.flag) } }
    return flags
}

func chordDown(modifiers: [String], key: CGKeyCode?, extraKeyFlags: CGEventFlags = []) {
    var flags: CGEventFlags = []
    for name in modifiers {
        guard let entry = modifierTable[name.lowercased()] else { log("Unknown modifier '\(name)'"); continue }
        flags.insert(entry.flag)
        let e = CGEvent(keyboardEventSource: eventSource, virtualKey: entry.key, keyDown: true)
        e?.type = .flagsChanged
        e?.flags = flags
        post(e)
    }
    if let key = key {
        let e = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: true)
        e?.flags = flags.union(extraKeyFlags)
        post(e)
    }
}

func chordUp(modifiers: [String], key: CGKeyCode?, extraKeyFlags: CGEventFlags = []) {
    var flags = modifierFlags(modifiers)
    if let key = key {
        let e = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: false)
        e?.flags = flags.union(extraKeyFlags)
        post(e)
    }
    for name in modifiers.reversed() {
        guard let entry = modifierTable[name.lowercased()] else { continue }
        flags.remove(entry.flag)
        let e = CGEvent(keyboardEventSource: eventSource, virtualKey: entry.key, keyDown: false)
        e?.type = .flagsChanged
        e?.flags = flags
        post(e)
    }
}

func chordTap(modifiers: [String], key: CGKeyCode?, extraKeyFlags: CGEventFlags = []) {
    chordDown(modifiers: modifiers, key: key, extraKeyFlags: extraKeyFlags)
    chordUp(modifiers: modifiers, key: key, extraKeyFlags: extraKeyFlags)
}

func syntheticMouse(button: Int, down: Bool) {
    let location = CGEvent(source: nil)?.location ?? .zero
    let e = CGEvent(mouseEventSource: eventSource,
                    mouseType: down ? .otherMouseDown : .otherMouseUp,
                    mouseCursorPosition: location,
                    mouseButton: .center)
    e?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
    post(e)
}

func runShell(_ command: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-lc", command]
    do { try p.run() } catch { log("Shell action failed: \(error)") }
}

// MARK: - Actions

enum Phase { case tap, begin, end }

func perform(_ action: Action, _ phase: Phase) {
    switch action.type {
    case "none":
        return
    case "spaceLeft":
        if phase != .end { chordTap(modifiers: ["control"], key: KeyCode.left, extraKeyFlags: arrowFlags) }
    case "spaceRight":
        if phase != .end { chordTap(modifiers: ["control"], key: KeyCode.right, extraKeyFlags: arrowFlags) }
    case "missionControl":
        if phase != .end { chordTap(modifiers: ["control"], key: KeyCode.up, extraKeyFlags: arrowFlags) }
    case "appWindows":
        if phase != .end { chordTap(modifiers: ["control"], key: KeyCode.down, extraKeyFlags: arrowFlags) }
    case "keys":
        let mods = action.modifiers ?? []
        let key = action.keyCode.map { CGKeyCode($0) }
        switch phase {
        case .tap:   chordTap(modifiers: mods, key: key)
        case .begin: chordDown(modifiers: mods, key: key)
        case .end:   chordUp(modifiers: mods, key: key)
        }
    case "mouseButton":
        guard let b = action.button else { log("mouseButton action missing 'button'"); return }
        switch phase {
        case .tap:   syntheticMouse(button: b, down: true); syntheticMouse(button: b, down: false)
        case .begin: syntheticMouse(button: b, down: true)
        case .end:   syntheticMouse(button: b, down: false)
        }
    case "shell":
        if phase != .end, let cmd = action.command { runShell(cmd) }
    default:
        log("Unknown action type '\(action.type)'")
    }
}

// MARK: - Button state machine

final class Press {
    var holdWork: DispatchWorkItem?
    var holdActive = false
    var tapFired = false
}

var presses: [Int: Press] = [:]
var tapPort: CFMachPort?

/// Returns true if the event should be swallowed.
func handle(type: CGEventType, event: CGEvent) -> Bool {
    if event.getIntegerValueField(.eventSourceUserData) == kSyntheticMarker { return false }

    let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
    if type == .otherMouseDown && (config.logButtons ?? false) {
        let mapped = config.buttons[String(button)]?.name ?? "unmapped"
        log("button \(button) pressed (\(mapped))")
    }
    guard let map = config.buttons[String(button)] else { return false }

    switch type {
    case .otherMouseDown:
        presses[button]?.holdWork?.cancel()
        let press = Press()
        presses[button] = press

        if let hold = map.hold, hold.type != "none" {
            let work = DispatchWorkItem {
                guard presses[button] === press else { return }
                press.holdActive = true
                perform(hold, .begin)
            }
            press.holdWork = work
            let ms = config.holdThresholdMs ?? 300
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms), execute: work)
        } else if let tap = map.tap {
            perform(tap, .tap)          // no hold action: fire instantly, zero latency
            press.tapFired = true
        }
        return true

    case .otherMouseUp:
        guard let press = presses.removeValue(forKey: button) else { return true }
        press.holdWork?.cancel()
        if press.holdActive {
            if let hold = map.hold { perform(hold, .end) }
        } else if !press.tapFired, let tap = map.tap {
            perform(tap, .tap)
        }
        return true

    case .otherMouseDragged:
        return true

    default:
        return false
    }
}

func releaseAllHolds() {
    for (button, press) in presses where press.holdActive {
        if let hold = config.buttons[String(button)]?.hold { perform(hold, .end) }
    }
    presses.removeAll()
}

let eventCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = tapPort { CGEvent.tapEnable(tap: port, enable: true) }
        log("Event tap was disabled by the system; re-enabled.")
        return Unmanaged.passUnretained(event)
    }
    return handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}

// MARK: - Record helper (SIGUSR1)

func recordHelper() {
    let candidate = config.buttons.keys.sorted().compactMap { key -> Action? in
        guard let hold = config.buttons[key]?.hold, hold.type == "keys" || hold.type == "mouseButton" else { return nil }
        return hold
    }.first
    guard let hold = candidate else { log("Record helper: no 'keys' or 'mouseButton' hold action configured."); return }
    log("Record helper: will press the hold chord in 4 seconds and hold it for 1.5 seconds…")
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { perform(hold, .begin) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) { perform(hold, .end); log("Record helper: released.") }
}

// MARK: - Main

setvbuf(stdout, nil, _IOLBF, 0)
log("ThumbMap starting (pid \(getpid()))")
loadConfig()

let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
    log("Waiting for Accessibility permission: System Settings → Privacy & Security → Accessibility → enable ThumbMap.")
    while !AXIsProcessTrusted() { Thread.sleep(forTimeInterval: 2) }
    log("Accessibility permission granted.")
}
if !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }

let mask: CGEventMask =
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.otherMouseUp.rawValue) |
    (1 << CGEventType.otherMouseDragged.rawValue)

guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                   place: .headInsertEventTap,
                                   options: .defaultTap,
                                   eventsOfInterest: mask,
                                   callback: eventCallback,
                                   userInfo: nil) else {
    log("Failed to create event tap. Check Accessibility permission, then restart ThumbMap.")
    exit(1)
}
tapPort = port
let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: port, enable: true)

signal(SIGHUP, SIG_IGN); signal(SIGUSR1, SIG_IGN); signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
let hupSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
hupSource.setEventHandler { loadConfig() }
hupSource.resume()
let usr1Source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
usr1Source.setEventHandler { recordHelper() }
usr1Source.resume()
let termHandler = { releaseAllHolds(); log("ThumbMap stopping."); exit(0) }
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler(handler: termHandler)
termSource.resume()
let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
intSource.setEventHandler(handler: termHandler)
intSource.resume()

log("Event tap active. Listening for mouse buttons.")
CFRunLoopRun()
