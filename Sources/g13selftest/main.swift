import Foundation
import CoreGraphics
import G13Core

// Plain-executable logic tests (no XCTest/Testing dependency, which aren't
// available under Command Line Tools). Run with: `swift run g13selftest`.

var total = 0
var failures = 0

func check(_ cond: Bool, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
    total += 1
    if cond {
        print("  ok   \(name)")
    } else {
        failures += 1
        print("  FAIL \(name)   (\(file):\(line))")
    }
}

func section(_ s: String) { print("\n# \(s)") }

func report(joyX: UInt8 = 0x80, joyY: UInt8 = 0x80,
            b3: UInt8 = 0, b4: UInt8 = 0, b5: UInt8 = 0,
            b6: UInt8 = 0, b7: UInt8 = 0) -> Data {
    Data([0x01, joyX, joyY, b3, b4, b5, b6, b7])
}

func hasJoystick(_ events: [InputEvent]) -> Bool {
    events.contains { if case .joystick = $0 { return true } else { return false } }
}

// MARK: - InputDecoder

section("InputDecoder")
check(InputDecoder.decode(Data([0x01, 0, 0])) == nil, "rejects short buffer")
check(InputDecoder.decode(Data([0x02, 0, 0, 0, 0, 0, 0, 0])) == nil, "rejects wrong marker")
check(InputDecoder.decode(report(joyX: 128, joyY: 64))?.joyY == 64, "decodes joystick Y")
check(InputDecoder.decode(report(b3: 0x01))?.buttons.contains(.g1) == true, "G1 = byte3 bit0")
check(InputDecoder.decode(report(b3: 0x80))?.buttons.contains(.g8) == true, "G8 = byte3 bit7")
check(InputDecoder.decode(report(b4: 0x01))?.buttons.contains(.g9) == true, "G9 = byte4 bit0")
check(InputDecoder.decode(report(b4: 0x80))?.buttons.contains(.g16) == true, "G16 = byte4 bit7")
check(InputDecoder.decode(report(b5: 0x01))?.buttons.contains(.g17) == true, "G17 = byte5 bit0")
check(InputDecoder.decode(report(b5: 0x20))?.buttons.contains(.g22) == true, "G22 = byte5 bit5")
check(InputDecoder.decode(report(b5: 0xC0))?.buttons.isEmpty == true, "byte5 light bits ignored")
check(InputDecoder.decode(report(b6: 0x01))?.buttons.contains(.bd) == true, "BD = byte6 bit0")
check(InputDecoder.decode(report(b6: 0x02))?.buttons.contains(.l1) == true, "L1 = byte6 bit1")
check(InputDecoder.decode(report(b6: 0x10))?.buttons.contains(.l4) == true, "L4 = byte6 bit4")
check(InputDecoder.decode(report(b6: 0x20))?.mKeys.contains(.m1) == true, "M1 = byte6 bit5")
check(InputDecoder.decode(report(b6: 0x40))?.mKeys.contains(.m2) == true, "M2 = byte6 bit6")
check(InputDecoder.decode(report(b6: 0x80))?.mKeys.contains(.m3) == true, "M3 = byte6 bit7")
check(InputDecoder.decode(report(b7: 0x01))?.mKeys.contains(.mr) == true, "MR = byte7 bit0")
check(InputDecoder.decode(report(b7: 0x02))?.buttons.contains(.left) == true, "LEFT = byte7 bit1")
check(InputDecoder.decode(report(b7: 0x04))?.buttons.contains(.right) == true, "RIGHT = byte7 bit2")
check(InputDecoder.decode(report(b7: 0x08))?.buttons.contains(.stickClick) == true, "STICK = byte7 bit3")

// MARK: - InputStateTracker

section("InputStateTracker")
do {
    let t = InputStateTracker()
    _ = t.process(InputFrame())
    let down = t.process(InputFrame(buttons: [.g1]))
    check(down.contains(.down(.g1)), "emits down edge")
    let up = t.process(InputFrame())
    check(up.contains(.up(.g1)), "emits up edge")
}
do {
    let t = InputStateTracker()
    _ = t.process(InputFrame())
    check(t.process(InputFrame(mKeys: [.mr])).contains(.bankKey(.mr)), "emits bankKey on mode press")
}
do {
    let t = InputStateTracker()
    _ = t.process(InputFrame(joyX: 128, joyY: 128))
    check(!hasJoystick(t.process(InputFrame(joyX: 128, joyY: 128))), "no joystick event when unchanged")
    check(hasJoystick(t.process(InputFrame(joyX: 200, joyY: 128))), "joystick event on change")
}
do {
    let t = InputStateTracker()
    _ = t.process(InputFrame(buttons: [.g5]))
    check(t.process(InputFrame(buttons: [.g5])).isEmpty, "no edges when state unchanged")
}

// MARK: - KeyCodeTable

section("KeyCodeTable")
check(KeyCodeTable.keyCode(for: "a") == 0x00, "keyCode a = 0x00")
check(KeyCodeTable.keyCode(for: "f5") == 0x60, "keyCode f5 = 0x60")
check(KeyCodeTable.keyCode(for: "return") == 0x24, "keyCode return = 0x24")
check(KeyCodeTable.keyCode(for: "kpEnter") == 0x4C, "keyCode kpEnter = 0x4C")
check(KeyCodeTable.keyCode(for: "bogus") == nil, "unknown key -> nil")
check(KeyCodeTable.name(for: 0x00)?.rawValue == "a", "name(0x00) = a")
check(!KeyCodeTable.groups.isEmpty, "GUI key groups populated")

// MARK: - Config Codable

section("Config Codable")
do {
    let pid = UUID()
    let bank0 = Bank(name: "B1", color: RGBColor(r: 0, g: 80, b: 255), bindings: [
        .g1: .keystroke(KeyChord(key: "f5", modifiers: [.command, .shift])),
        .g2: .text("hello@example.com"),
        .g3: .mouse(.scroll(direction: .down, speed: 5, accelerate: true)),
        .joyUp: .keystroke(KeyChord(key: "up", repeatsWhileHeld: true)),
    ])
    let banks = [bank0,
                 Bank(name: "B2", color: .off),
                 Bank(name: "B3", color: .off),
                 Bank(name: "B4", color: .off)]
    let profile = Profile(id: pid, name: "Default", banks: banks)
    let macro = Macro(name: "m", steps: [
        MacroStep(action: .keystroke(KeyChord(key: "a", modifiers: [.command])), delayAfterMs: 50),
        MacroStep(action: .launchApp(bundleID: "com.google.Chrome", name: "Chrome",
                                     args: ["--new-window", "https://example.com"]), delayAfterMs: 800),
        MacroStep(action: .none, delayAfterMs: 120, isEnabled: false),   // a disabled "Wait" step
    ])
    let config = Config(profiles: [profile],
                        apps: [AppAssociation(bundleIdentifier: "com.apple.Safari", profileID: pid)],
                        defaultProfileID: pid, macros: [macro])

    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    do {
        let data = try enc.encode(config)
        let json = String(data: data, encoding: .utf8) ?? ""
        check(json.contains("\"g1\""), "bindings encode as JSON object (key \"g1\")")
        let back = try JSONDecoder().decode(Config.self, from: data)
        check(back.profiles[0].banks[0].binding(for: .g1) == config.profiles[0].banks[0].binding(for: .g1),
              "g1 keystroke binding round-trips")
        check(back.profiles[0].banks[0].binding(for: .g2) == .text("hello@example.com"),
              "g2 text binding round-trips")
        check(back.profiles[0].banks[0].binding(for: .g3) == .mouse(.scroll(direction: .down, speed: 5, accelerate: true)),
              "g3 mouse-scroll binding round-trips")
        check(back.profiles[0].banks[0].binding(for: .joyUp) == .keystroke(KeyChord(key: "up", repeatsWhileHeld: true)),
              "joyUp binding round-trips")
        check(back.macros.first?.steps.count == 3, "macro steps round-trip")
        check(back.macros.first?.steps[1].action == macro.steps[1].action,
              "macro launchApp-with-args step round-trips")
        check(back.macros.first?.steps[0].delayAfterMs == 50, "macro step delayAfterMs round-trips")
        check(back.macros.first?.steps[2].isEnabled == false, "macro step isEnabled round-trips")
        check(back.settings.joystick.mode == .directionalKeys, "joystick default mode persists")
        check(back.profile(forBundleID: "com.apple.Safari").id == pid, "app association resolves profile")
        check(back.profile(forBundleID: "nope").id == pid, "unknown app falls back to default")
    } catch {
        check(false, "config round-trip threw: \(error)")
    }
}

// MARK: - Lenient bindings (resilience to unknown/legacy actions)

section("Lenient bindings")
do {
    let bank = Bank(name: "B", color: .off, bindings: [.g1: .text("hi")])
    do {
        let data = try JSONEncoder().encode(bank)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var binds = obj["bindings"] as! [String: Any]
        binds["g9"] = ["unknownCase": ["x": 1]]   // a binding from a hypothetical future/older schema
        obj["bindings"] = binds
        let mutated = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(Bank.self, from: mutated)
        check(decoded.binding(for: .g1) == .text("hi"), "good binding survives a sibling bad binding")
        let g9IsNone: Bool = { if case .none = decoded.binding(for: .g9) { return true } else { return false } }()
        check(g9IsNone, "undecodable binding is dropped (not fatal)")
    } catch {
        check(false, "lenient bindings threw: \(error)")
    }
}

// MARK: - ProfileResolver

section("ProfileResolver")
do {
    let pid = UUID()
    var b0 = ConfigStore.makeDefaultBank(index: 0)
    b0.bindings[.g1] = .text("A")
    let banks = [b0, ConfigStore.makeDefaultBank(index: 1),
                 ConfigStore.makeDefaultBank(index: 2), ConfigStore.makeDefaultBank(index: 3)]
    let profile = Profile(id: pid, name: "P", banks: banks)
    let config = Config(profiles: [profile], defaultProfileID: pid)
    let r0 = ProfileResolver.resolve(config: config, bundleID: nil, bankOverride: 0)
    check(r0.binding(for: .g1) == .text("A"), "resolver returns bank0 binding")
    check(r0.bankIndex == 0, "resolver bank index 0")
    let r1 = ProfileResolver.resolve(config: config, bundleID: nil, bankOverride: 1)
    check(r1.binding(for: .g1) == .none, "bank1 has no g1 binding")
    check(r1.bankColor == ConfigStore.defaultBankColors[1], "bank1 default color")
}

// MARK: - JoystickMath

section("JoystickMath")
do {
    var s = JoystickSettings(mode: .directionalKeys, deadzone: 40, center: 128)
    check(JoystickMath.withinDeadzone(x: 128, y: 128, settings: s), "center within deadzone")
    check(!JoystickMath.withinDeadzone(x: 255, y: 128, settings: s), "full right outside deadzone")
    let right = JoystickMath.directions(x: 255, y: 128, settings: s, previous: [])
    check(right.contains(.joyRight) && !right.contains(.joyLeft), "full right -> joyRight")
    check(JoystickMath.directions(x: 128, y: 0, settings: s, previous: []).contains(.joyUp), "y=0 -> joyUp")
    check(JoystickMath.directions(x: 128, y: 255, settings: s, previous: []).contains(.joyDown), "y=255 -> joyDown")
    let stay = JoystickMath.directions(x: 128 + 35, y: 128, settings: s, previous: [.joyRight])
    check(stay.contains(.joyRight), "hysteresis keeps right active")
    let release = JoystickMath.directions(x: 128 + 5, y: 128, settings: s, previous: [.joyRight])
    check(!release.contains(.joyRight), "releases right near center")
    s.mode = .scrollWheel
    let (sx, sy) = JoystickMath.scaled(x: 255, y: 128, settings: s, speed: 10)
    check(sx > 0 && sy == 0, "full right scaled dx>0 dy==0")
}

// MARK: - ConfigStore

section("ConfigStore")
do {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("g13selftest-\(UUID().uuidString)")
    let store = ConfigStore(directory: tmp)
    let def = store.load()
    check(def.profiles.count == 1, "default has one profile")
    check(def.profiles[0].banks.count == 4, "default profile has 4 banks")
    check(FileManager.default.fileExists(atPath: store.fileURL.path), "config file written on first load")
    var cfg = def
    cfg.settings.joystick.mode = .scrollWheel
    try? store.save(cfg)
    check(store.load().settings.joystick.mode == .scrollWheel, "saved change persists")
    try? Data("not json".utf8).write(to: store.fileURL)
    check(store.load().profiles.count >= 1, "corrupt config recovers from backup/default")
    try? FileManager.default.removeItem(at: tmp)
}

// MARK: - Settings forward-compat

section("Settings tolerance")
do {
    // A config written before scrollAcceleration existed must still decode.
    let json = #"{"masterEnabled":true,"openAtLogin":false,"joystick":{"mode":"directionalKeys","deadzone":40,"center":128,"mouseSpeed":8,"scrollSpeed":3,"invertX":false,"invertY":false}}"#
    if let gs = try? JSONDecoder().decode(GlobalSettings.self, from: Data(json.utf8)) {
        check(gs.scrollAcceleration.rampSeconds == 5, "missing scrollAcceleration defaults ramp=5")
        check(gs.scrollAcceleration.maxMultiplier == 6, "missing scrollAcceleration defaults max=6")
    } else {
        check(false, "GlobalSettings without scrollAcceleration should still decode")
    }
}

// MARK: - New action types

section("New action types")
do {
    let cases: [BindingAction] = [
        .media(.playPause), .media(.volumeUp), .media(.mute),
        .window(.leftHalf), .window(.maximize), .window(.restore),
        .system(.missionControl), .system(.lockScreen), .system(.sleepDisplay),
        .launchApp(bundleID: "com.apple.Safari", name: "Safari", args: []),
        .launchApp(bundleID: "com.google.Chrome", name: "Chrome",
                   args: ["--profile-directory=Profile 1", "--new-window", "https://example.com"]),
        .openURL("https://example.com"),
        .runShortcut("My Shortcut"),
        .mouse(.click(.back)), .mouse(.click(.forward)),
    ]
    for a in cases {
        do {
            let data = try JSONEncoder().encode(a)
            let back = try JSONDecoder().decode(BindingAction.self, from: data)
            check(back == a, "round-trips: \(a.summary)")
        } catch {
            check(false, "encode/decode failed for \(a.summary): \(error)")
        }
    }
    // SystemCommand keyChord coverage (all but sleepDisplay should have one)
    check(SystemCommand.sleepDisplay.keyChord == nil, "sleepDisplay has no keyChord")
    check(SystemCommand.missionControl.keyChord != nil, "missionControl has a keyChord")
}

// MARK: - BindingAction legacy / synthesized format (must still decode)

section("BindingAction synthesized-format decode")
do {
    func decode(_ json: String) -> BindingAction? {
        try? JSONDecoder().decode(BindingAction.self, from: Data(json.utf8))
    }
    // These shapes match what older builds (Swift synthesized enum Codable) wrote.
    check(decode(#"{"system":{"_0":"zoomIn"}}"#) == .system(.zoomIn),
          "decodes synthesized system {_0}")
    check(decode(#"{"mouse":{"_0":{"scroll":{"direction":"down","speed":5,"accelerate":true}}}}"#)
          == .mouse(.scroll(direction: .down, speed: 5, accelerate: true)),
          "decodes synthesized mouse {_0}")
    check(decode(#"{"keystroke":{"_0":{"key":"f5","modifiers":9,"repeatsWhileHeld":false}}}"#)
          == .keystroke(KeyChord(key: "f5", modifiers: [.command, .control])),
          "decodes synthesized keystroke {_0} (modifiers as Int)")
    check(decode(#"{"text":{"_0":"hi"}}"#) == .text("hi"), "decodes synthesized text {_0}")
    // launchApp written before `args` existed must decode with args == [].
    if case let .launchApp(id, name, args)? = decode(#"{"launchApp":{"bundleID":"com.apple.Safari","name":"Safari"}}"#) {
        check(id == "com.apple.Safari" && name == "Safari" && args.isEmpty,
              "legacy launchApp (no args) decodes with args == []")
    } else {
        check(false, "legacy launchApp (no args) should decode")
    }
    // New launchApp with args round-trips through our explicit codec.
    let withArgs = BindingAction.launchApp(bundleID: "com.google.Chrome", name: "Chrome",
                                           args: ["--profile-directory=Profile 1", "https://x.com"])
    if let data = try? JSONEncoder().encode(withArgs),
       let back = try? JSONDecoder().decode(BindingAction.self, from: data) {
        check(back == withArgs, "launchApp with args round-trips")
    } else {
        check(false, "launchApp with args should round-trip")
    }
}

// MARK: - Macro RPA steps + legacy migration

section("Macro RPA steps & migration")
do {
    // New MacroStep round-trips, including a disabled step.
    let step = MacroStep(action: .openURL("https://x.com"), delayAfterMs: 250, isEnabled: false)
    if let back = try? JSONDecoder().decode(MacroStep.self, from: JSONEncoder().encode(step)) {
        check(back == step, "MacroStep round-trips (delayAfterMs / isEnabled)")
    } else {
        check(false, "MacroStep should round-trip")
    }

    // migrate(): down/up collapses to a keystroke; delays fold into the previous step.
    let mid = Macro.migrate([.text("x"), .delay(milliseconds: 30), .mouse(.click(.left))])
    check(mid.count == 2, "migrate: text + folded delay + mouse → 2 steps")
    check(mid.first?.delayAfterMs == 60 + 30, "migrate: delay folds into preceding step")
    let lead = Macro.migrate([.delay(milliseconds: 200), .text("y")])
    // Note: unwrap before matching — `.none` on an Optional matches Optional.none (nil).
    let leadIsWait: Bool = {
        guard let a = lead.first?.action, case .none = a else { return false }
        return true
    }()
    check(lead.count == 2 && leadIsWait && lead.first?.delayAfterMs == 200,
          "migrate: leading delay becomes a Wait step")

    // A Macro whose `steps` are in the legacy on-disk format must decode + migrate.
    do {
        let legacy: [LegacyMacroStep] = [
            .key(name: "a", down: true, modifiers: [.command]),
            .key(name: "a", down: false, modifiers: [.command]),
            .delay(milliseconds: 100),
        ]
        let stepsJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy))
        let macroObj: [String: Any] = ["id": UUID().uuidString, "name": "old", "repeatCount": 1, "steps": stepsJSON]
        let macroData = try JSONSerialization.data(withJSONObject: macroObj)
        let m = try JSONDecoder().decode(Macro.self, from: macroData)
        check(m.steps.count == 1, "legacy down/up collapses to one keystroke step")
        let isKeystroke: Bool = { if case .keystroke = m.steps.first?.action { return true } else { return false } }()
        check(isKeystroke, "migrated legacy step is a keystroke")
        check(m.steps.first?.delayAfterMs == 160, "trailing legacy delay folds in (60 default + 100)")
    } catch {
        check(false, "legacy macro migration threw: \(error)")
    }
}

// MARK: - Key sequences (Keystroke typing text key by key)

section("Key sequences")
do {
    // Single-key chords must encode exactly as before so older builds read them unchanged.
    if let data = try? JSONEncoder().encode(KeyChord(key: "f5", modifiers: [.command])) {
        check(!String(decoding: data, as: UTF8.self).contains("sequence"), "single-key chord JSON has no sequence key")
    } else {
        check(false, "single-key chord should encode")
    }

    let typed = BindingAction.keystroke(KeyChord(key: "a", sequence: KeySequence(text: "aiueo", intervalMs: 30)))
    if let data = try? JSONEncoder().encode(typed),
       let back = try? JSONDecoder().decode(BindingAction.self, from: data) {
        check(back == typed, "key-sequence keystroke round-trips")
    } else {
        check(false, "key-sequence keystroke should round-trip")
    }
    let step = MacroStep(action: typed, delayAfterMs: 100)
    if let back = try? JSONDecoder().decode(MacroStep.self, from: JSONEncoder().encode(step)) {
        check(back == step, "key-sequence macro step round-trips")
    } else {
        check(false, "key-sequence macro step should round-trip")
    }

    func decodeSequence(_ json: String) -> KeySequence? {
        try? JSONDecoder().decode(KeySequence.self, from: Data(json.utf8))
    }
    check(decodeSequence(#"{"text":"hi"}"#)?.intervalMs == KeySequence.defaultIntervalMs, "missing intervalMs decodes as default")
    check(decodeSequence(#"{"text":"hi","intervalMs":-5}"#)?.intervalMs == 0, "negative intervalMs clamps to 0")
    check(decodeSequence(#"{"text":"hi","intervalMs":999999999}"#)?.intervalMs == KeySequence.maxIntervalMs,
          "huge intervalMs clamps to max")

    check(typed.summary == "Keys “aiueo”", "sequence summary shows the text")
    check(BindingAction.keystroke(KeyChord(key: "a", sequence: KeySequence(text: "a\nb"))).summary == "Keys “a⏎b”",
          "sequence summary shows line breaks as ⏎")

    // Character → key on the current layout; nil means "type as Unicode".
    check(KeyCodeTable.resolve(character: "\n")?.code == 0x24, "newline → Return key")
    check(KeyCodeTable.resolve(character: "\t")?.code == 0x30, "tab → Tab key")
    check(KeyCodeTable.resolve(character: " ")?.code == 0x31, "space → Space key")
    check(KeyCodeTable.resolve(character: "a")?.flags.contains(.maskShift) == false, "'a' has no shift")
    check(KeyCodeTable.resolve(character: "A")?.flags.contains(.maskShift) == true, "'A' adds shift")
    check(KeyCodeTable.resolve(character: "A")?.code == KeyCodeTable.resolve(character: "a")?.code, "'A' is the 'a' key")
    check(KeyCodeTable.resolve(character: "あ") == nil, "kana has no key → Unicode fallback")
    check(KeyCodeTable.resolve(character: "😀") == nil, "emoji has no key → Unicode fallback")

    // Dead keys start an accent instead of typing their character, so sequences
    // must not use them (checked against installed layouts, not the current one;
    // where keys sit also depends on the Mac's ANSI/ISO/JIS keyboard type).
    if let german = LayoutKeyMap.typableKeys(layoutID: "com.apple.keylayout.German"),
       let us = LayoutKeyMap.typableKeys(layoutID: "com.apple.keylayout.US") {
        check(german["^"] == nil && german["´"] == nil && german["`"] == nil,
              "German: characters only on dead keys (^ ´ `) are not typable")
        check(german["z"] != nil && german["ä"] != nil, "German: ordinary keys stay typable")
        check(us["^"] != nil && us["`"] != nil && us["'"] != nil && us["\""] != nil,
              "US: ^ ` ' \" are ordinary keys")
    } else {
        print("    (German / US layouts not installed — dead-key checks skipped)")
    }
}

// MARK: - MacroPlayer (Wait-only macros inject nothing)

section("MacroPlayer")
MainActor.assumeIsolated {
    let player = MacroPlayer()
    player.play(Macro(name: "long", steps: [MacroStep(action: .none, delayAfterMs: 1000)]))
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    player.play(Macro(name: "short", steps: [MacroStep(action: .none, delayAfterMs: 300)]))
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    check(player.isPlaying, "a cancelled run doesn't clear the newer run's task")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.45))
    check(!player.isPlaying, "a finished run clears its task")

    // A change of frontmost app only releases held input; edits/disable stop macros too.
    let engine = ActionEngine()
    engine.macroPlayer.play(Macro(name: "wait", steps: [MacroStep(action: .none, delayAfterMs: 300)]))
    engine.releaseHeld()
    check(engine.macroPlayer.isPlaying, "releaseHeld keeps a running macro going")
    engine.cancelAll()
    check(!engine.macroPlayer.isPlaying, "cancelAll stops a running macro")
}

// MARK: - Export / import

section("Export / import")
do {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("g13selftest-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    var cfg = ConfigStore.makeDefault()
    cfg.profiles[0].banks[0].bindings[.g1] = .keystroke(KeyChord(key: "a", sequence: KeySequence(text: "aiueo")))
    cfg.macros = [Macro(name: "m", steps: [MacroStep(action: .text("x"), delayAfterMs: 10)])]
    cfg.settings.joystick.mode = .mouseMove
    let file = tmp.appendingPathComponent("export.json")
    do {
        try ConfigStore.export(cfg, to: file)
        let back = try ConfigStore.readImport(from: file)
        check(back.profiles.map(\.id) == cfg.profiles.map(\.id), "export → import keeps profiles")
        check(back.profiles[0].banks[0].binding(for: .g1) == cfg.profiles[0].banks[0].binding(for: .g1),
              "export → import keeps a key-sequence binding")
        check(back.macros == cfg.macros, "export → import keeps macros")
        check(back.settings.joystick.mode == .mouseMove, "export → import keeps settings")
    } catch {
        check(false, "export/import round-trip threw: \(error)")
    }

    let junk = tmp.appendingPathComponent("junk.json")
    try? Data(#"{"hello":"world"}"#.utf8).write(to: junk)
    var rejected = false
    do { _ = try ConfigStore.readImport(from: junk) } catch ConfigStore.ImportError.notASettingsFile { rejected = true } catch {}
    check(rejected, "non-settings JSON is rejected with ImportError")

    var short = cfg
    short.profiles[0].banks = Array(short.profiles[0].banks.prefix(2))
    try? ConfigStore.export(short, to: file)
    check((try? ConfigStore.readImport(from: file))?.profiles[0].banks.count == 4, "import pads a profile to 4 banks")

    MainActor.assumeIsolated {
        let store = ConfigStore(directory: tmp.appendingPathComponent("store"))
        let controller = AppController(store: store)
        var local = controller.config
        local.settings.openAtLogin = true
        controller.apply(local)
        var incoming = cfg
        incoming.settings.openAtLogin = false
        do {
            try controller.importConfig(incoming)
            check(controller.config.profiles.map(\.id) == cfg.profiles.map(\.id), "importConfig replaces profiles")
            check(controller.config.settings.openAtLogin, "importConfig keeps this Mac's openAtLogin")
            check((try? ConfigStore.readImport(from: store.preImportURL))?.profiles.map(\.id) == local.profiles.map(\.id),
                  "importConfig keeps the replaced config as config.pre-import.json")
            check(store.load().profiles.map(\.id) == cfg.profiles.map(\.id), "imported config is saved")
        } catch {
            check(false, "importConfig threw: \(error)")
        }
    }
    try? FileManager.default.removeItem(at: tmp)
}

// MARK: - LayoutKeyMap (current keyboard layout)

section("LayoutKeyMap")
check(LayoutKeyMap.resolve("a") != nil, "resolve 'a' found")
check(LayoutKeyMap.resolve("=") != nil, "resolve '=' found")
check(LayoutKeyMap.resolve("0") != nil, "resolve '0' found")
print("    (current-layout keycodes — '=' should differ from ANSI 0x18 on JIS)")
for ch: Character in ["a", "z", "=", "-", "0", ";", "/", "["] {
    if let r = LayoutKeyMap.resolve(ch) {
        print("    '\(ch)' -> keycode 0x\(String(r.code, radix: 16)) shift=\(r.shift)")
    } else {
        print("    '\(ch)' -> not found")
    }
}

// MARK: - Summary

print("\n\(total - failures)/\(total) checks passed")
exit(failures == 0 ? 0 : 1)
