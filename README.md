# G13 Manager

A userspace driver + management app that makes the **Logitech G13 Advanced Gameboard** work on
macOS 26 (Tahoe), where Logitech/Logicool no longer provides a driver.

No kernel extension, no DriverKit, no virtual HID device, no root daemon — just a single
SwiftUI menu-bar app that talks to the G13 over IOKit's user-space `IOHIDManager` and injects
remapped input with CoreGraphics.

## Features

- **All G13 inputs**: G1–G22, BD, L1–L4, thumb Left/Right, stick click, analog joystick, and the
  M1/M2/M3/MR mode keys.
- **Per-app profiles** that switch automatically when you change the frontmost app.
- **Four banks per app** selected with M1 / M2 / M3 / MR (this is how "4 profiles" is realized,
  since the hardware has no M4). The active bank's color is shown on the RGB backlight.
- **Per-key actions**: keystroke (with modifiers, optional hold-to-repeat), typed text
  (layout-independent), mouse click/move/scroll, a recorded macro, or nothing.
- **GUI macro recording** with timing, step editing, and playback.
- **Configurable joystick**: directional keys / mouse move / **scroll wheel (vertical + horizontal)** /
  disabled, with deadzone, speed, and invert options.
- **RGB backlight** reflecting the active bank.

## Requirements

- macOS 14+ (developed/tested against macOS 26.5, Apple Silicon).
- Swift toolchain (the bundled Command Line Tools are enough — full Xcode is not required).

## Build & install

```sh
# Build everything
swift build

# Run the logic self-tests (no XCTest needed)
swift run g13selftest

# Inspect raw/decoded device input (needs Input Monitoring for the terminal)
swift run g13probe          # decoded events
swift run g13probe --raw    # raw 8-byte reports
swift run g13probe --joy    # also print joystick movement

# Build the .app, ad-hoc sign it, and install to ~/Applications
scripts/make_app.sh release
open ~/Applications/G13Manager.app
```

`make_app.sh` installs to a **fixed path with a stable bundle id** (`dev.tuttisound.G13Manager`)
so the macOS permissions you grant persist across rebuilds.

## Permissions (first run)

macOS will require two permissions in **System Settings › Privacy & Security**. The app shows a
banner and buttons that jump straight to the right panes:

- **Input Monitoring** — to read the G13's input.
- **Accessibility** — to send keystrokes/mouse events to other apps.

If permissions seem stuck after a rebuild:

```sh
tccutil reset ListenEvent dev.tuttisound.G13Manager
tccutil reset Accessibility dev.tuttisound.G13Manager
```

## Usage

The app lives in the menu bar (🎮). Open the window from its menu to:

- **Keys** — pick a profile + bank, click a G13 key on the layout, and assign its action.
- **Macros** — record/edit/playback macros and name them.
- **Profiles** — manage profiles, bank names/colors, and which apps map to which profile.
- **Settings** — master enable, joystick mode, permissions, open-at-login.

Config is stored at `~/Library/Application Support/dev.tuttisound.G13Manager/config.json`
(atomic writes + a `config.backup.json`).

## Architecture

```
G13Core (library, no UI)
  G13Device          IOHIDManager open/read/write, hotplug (VID 0x046D / PID 0xC21C)
  InputDecoder       8-byte report -> InputFrame
  InputStateTracker  frames -> press/release edges + joystick changes
  ActionEngine       binding -> CGEvent (key/text/mouse/scroll/macro)
  Injector/EventTagger  shared tagged CGEventSource (prevents macro self-capture)
  MacroRecorder/Player  CGEventTap capture / timed replay
  ConfigStore        JSON load/save/backup/migrate
  ProfileResolver    (app, bank) -> active bindings
  AppFocusMonitor    NSWorkspace frontmost-app tracking
  BankManager/BacklightController  banks + feature reports (0x07 RGB, 0x05 M-LED)
  JoystickDriver/Math  directional / mouse / scroll modes
  AppController      @MainActor orchestrator

G13Manager (app)   menu-bar shell + SwiftUI editors
g13probe           device validation CLI
g13selftest        plain-executable logic tests
```

## Notes / caveats

- Targets normal apps (browsers, dev tools, office). It does **not** aim at games, so CGEvent
  injection is sufficient and no virtual HID device is needed.
- This is a local, personal build (ad-hoc signed, not notarized).
- The exact on-wire framing of the backlight/LED feature reports isn't described by a HID
  descriptor; `BacklightController` tries the documented convention and falls back to the
  libusb-style framing. If the backlight doesn't respond on your unit, adjust the two byte
  layouts in `Sources/G13Core/BacklightController.swift`.
- The LCD screen is intentionally out of scope.
