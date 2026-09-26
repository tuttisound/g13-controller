import Foundation
import IOKit.hid
import G13Core

// g13probe — a tiny CLI to validate the G13 driver against real hardware.
//
//   swift run g13probe          decoded, symbolic events (DOWN/UP/BANK)
//   swift run g13probe --raw    raw 8-byte hex reports
//   swift run g13probe --joy    also print joystick movement
//
// Note: reading HID input requires Input Monitoring. When run from a terminal,
// the *terminal app* must have Input Monitoring (System Settings › Privacy &
// Security › Input Monitoring).

setbuf(stdout, nil)

let rawMode = CommandLine.arguments.contains("--raw")
let showJoy = CommandLine.arguments.contains("--joy")
var duration: Double? = nil
if let i = CommandLine.arguments.firstIndex(of: "--duration"),
   i + 1 < CommandLine.arguments.count {
    duration = Double(CommandLine.arguments[i + 1])
}

print("g13probe — Logitech G13 monitor (VID 0x046D / PID 0xC21C)")
print(rawMode ? "mode: raw hex" : "mode: decoded events\(showJoy ? " + joystick" : "")")

let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
switch access {
case kIOHIDAccessTypeGranted:
    print("Input Monitoring: granted ✓")
case kIOHIDAccessTypeDenied:
    print("Input Monitoring: DENIED ✗ — enable this terminal in System Settings › Privacy & Security › Input Monitoring.")
default:
    print("Input Monitoring: not determined — requesting…")
    _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    print("If no reports appear, grant Input Monitoring to this terminal and re-run.")
}
print("Press keys / move the stick. Ctrl-C to quit.\n")

let device = G13Device()
let tracker = InputStateTracker()

device.onConnected = { print("[connected]") }
device.onDisconnected = { print("[disconnected]") }
device.onInputReport = { data in
    if rawMode {
        print("report: " + data.map { String(format: "%02x", $0) }.joined(separator: " "))
        return
    }
    guard let frame = InputDecoder.decode(data) else {
        print("undecodable: " + data.map { String(format: "%02x", $0) }.joined(separator: " "))
        return
    }
    for event in tracker.process(frame) {
        if let line = describe(event) { print(line) }
    }
}

func describe(_ event: InputEvent) -> String? {
    switch event {
    case .down(let id): return "DOWN  \(id.displayName)"
    case .up(let id): return "UP    \(id.displayName)"
    case .bankKey(let m): return "BANK  \(m.displayName)  → bank \(m.bankIndex + 1)"
    case .joystick(let x, let y): return showJoy ? "JOY   x=\(x) y=\(y)" : nil
    }
}

device.start()

if let duration {
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        print("\n[done: \(duration)s elapsed]")
        exit(0)
    }
}

if !rawMode {
    // Hint if nothing arrives within a few seconds (likely a permission issue).
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        if !device.isConnected {
            print("\n(no device events yet — is the G13 plugged in, and does this terminal have Input Monitoring?)")
        }
    }
}

RunLoop.main.run()
