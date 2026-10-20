import SwiftUI
import AppKit
import G13Core

/// Shared editor for a single `BindingAction`, reused by both the per-key binding
/// editor (Keys tab) and each macro step (Macros tab). It mirrors the bound
/// action into local `@State`, then commits changes back through the binding.
///
/// It is intentionally Form-free (uses `GroupBox` sections) so it can be embedded
/// inline inside a scrolling macro step card without nested-scroll conflicts; the
/// caller owns scrolling.
struct ActionEditorView: View {
    @Binding var action: BindingAction
    /// Where this editor lives — gates options that only make sense for a held
    /// key (repeat / accelerate) or that would nest (Macro inside a macro step).
    var context: EditContext = .keyBinding
    /// Optional title rendered above the action picker (the key name, for Keys).
    var title: String? = nil
    /// Stable identity of the thing being edited (input id / step id). When it
    /// changes, the mirror reloads from the new bound action.
    var reloadKey: AnyHashable = ""
    var editor: EditorModel

    enum EditContext { case keyBinding, macroStep }

    enum Kind: String, CaseIterable, Identifiable {
        case none = "None", keystroke = "Keystroke", text = "Text", mouse = "Mouse", macro = "Macro"
        case media = "Media", window = "Window", system = "System"
        case app = "Open App", openURL = "Open URL", shortcut = "Run Shortcut"
        var id: String { rawValue }
    }
    enum KeyMode: String, CaseIterable, Identifiable {
        case single = "Single Key", sequence = "Key Sequence"
        var id: String { rawValue }
    }
    enum MouseKind: String, CaseIterable, Identifiable {
        case click = "Click", doubleClick = "Double-click", scroll = "Scroll", move = "Move"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .none
    @State private var keyMode: KeyMode = .single
    @State private var keyName = "a"
    @State private var modCommand = false
    @State private var modShift = false
    @State private var modOption = false
    @State private var modControl = false
    @State private var repeats = false
    @State private var sequenceText = ""
    @State private var sequenceIntervalMs = KeySequence.defaultIntervalMs
    @State private var textValue = ""
    @State private var mouseKind: MouseKind = .scroll
    @State private var mouseButton: MouseButton = .left
    @State private var mouseDirection: MouseDirection = .down
    @State private var mouseSpeed: Double = 5
    @State private var mouseAccelerate = false
    @State private var macroID: UUID?
    @State private var mediaKey: MediaKey = .playPause
    @State private var windowAction: WindowAction = .leftHalf
    @State private var systemCommand: SystemCommand = .missionControl
    @State private var appBundleID = ""
    @State private var appName = ""
    @State private var appArgs = ""
    @State private var urlString = ""
    @State private var shortcutName = ""
    @State private var suppress = false

    /// Macro steps can't nest another macro.
    private var availableKinds: [Kind] {
        context == .macroStep ? Kind.allCases.filter { $0 != .macro } : Kind.allCases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionBox(nil) {
                if let title { Text(title).font(.title3.bold()) }
                Picker("Action", selection: $kind) {
                    ForEach(availableKinds) { k in
                        Text(k == .none ? noneLabel : k.rawValue).tag(k)
                    }
                }
            }

            switch kind {
            case .none:
                sectionBox(nil) {
                    Text(context == .macroStep
                         ? "No action — this step just waits for the delay set on the card."
                         : "This key does nothing.")
                        .foregroundStyle(.secondary)
                }
            case .keystroke: keystrokeEditor
            case .text:
                sectionBox("Text") {
                    TextField("Text to type", text: $textValue, axis: .vertical)
                        .lineLimit(1...4)
                    Text("Injected as Unicode, independent of keyboard layout.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .mouse: mouseEditor
            case .macro: macroEditor
            case .media: mediaEditor
            case .window: windowEditor
            case .system: systemEditor
            case .app: appEditor
            case .openURL: urlEditor
            case .shortcut: shortcutEditor
            }
        }
        .onAppear { load() }
        .onChange(of: reloadKey) { _, _ in load() }
        .onChange(of: signature) { _, _ in commit() }
    }

    private var noneLabel: String { context == .macroStep ? "None (Wait)" : "None" }

    // MARK: - Section container (Form-free)

    @ViewBuilder
    private func sectionBox<Content: View>(_ heading: String?,
                                           @ViewBuilder _ content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        } label: {
            if let heading { Text(heading).font(.caption).foregroundStyle(.secondary) }
        }
    }

    // MARK: - Per-kind editors

    private var keystrokeEditor: some View {
        sectionBox("Keystroke") {
            Picker("Keystroke", selection: $keyMode) {
                ForEach(KeyMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch keyMode {
            case .single:
                Menu(KeyCodeTable.label(for: KeyName(keyName))) {
                    ForEach(KeyCodeTable.groups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.keys, id: \.rawValue) { k in
                                Button(KeyCodeTable.label(for: k)) { keyName = k.rawValue }
                            }
                        }
                    }
                }
                Toggle("⌘ Command", isOn: $modCommand)
                Toggle("⇧ Shift", isOn: $modShift)
                Toggle("⌥ Option", isOn: $modOption)
                Toggle("⌃ Control", isOn: $modControl)
                if context == .keyBinding {
                    Toggle("Repeat while held", isOn: $repeats)
                }
            case .sequence:
                TextField("Text to type key by key", text: $sequenceText, axis: .vertical)
                    .lineLimit(1...4)
                HStack(spacing: 8) {
                    Text("Delay between keys")
                    TextField("ms", text: intervalText)
                        .frame(width: 64).textFieldStyle(.roundedBorder)
                    Stepper("", value: $sequenceIntervalMs, in: 0...KeySequence.maxIntervalMs, step: 10)
                        .labelsHidden()
                    Text("ms").foregroundStyle(.secondary)
                }
                Text("Each character is pressed as its own key on the current keyboard layout, so input methods see ordinary typing; characters with no key are typed as Unicode. ⌥Return adds a line break, which presses Return.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Try it in another app — while this window is in front, the keys type into it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The delay as live text, so like the other fields it commits per keystroke
    /// (a `value:` field only commits on Return/focus loss — an edit pending when
    /// the key or step changes would be lost). Accepts full-width digits.
    private var intervalText: Binding<String> {
        Binding(get: { String(sequenceIntervalMs) },
                set: { text in
                    let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
                    if let ms = Int(halfWidth.filter { $0.isASCII && $0.isNumber }) { sequenceIntervalMs = ms }
                })
    }

    private var mouseEditor: some View {
        sectionBox("Mouse") {
            Picker("Type", selection: $mouseKind) {
                ForEach(MouseKind.allCases) { Text($0.rawValue).tag($0) }
            }
            if mouseKind == .click || mouseKind == .doubleClick {
                Picker("Button", selection: $mouseButton) {
                    ForEach(MouseButton.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } else {
                Picker("Direction", selection: $mouseDirection) {
                    ForEach(MouseDirection.allCases, id: \.self) { Text(directionLabel($0)).tag($0) }
                }
                LabeledContent("Speed") {
                    Slider(value: $mouseSpeed, in: 1...20, step: 1)
                    Text("\(Int(mouseSpeed))").monospacedDigit().frame(width: 28)
                }
                if context == .keyBinding {
                    Toggle("Accelerate while held", isOn: $mouseAccelerate)
                    Text(mouseKind == .scroll
                         ? "Scrolls while held. “Accelerate” speeds up the longer you hold."
                         : "Moves the cursor while held. “Accelerate” speeds up the longer you hold.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(mouseKind == .scroll ? "Scrolls one step." : "Moves the cursor once.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func directionLabel(_ d: MouseDirection) -> String {
        "\(mouseKind == .scroll ? "Scroll" : "Move") \(d.displayName)"
    }

    private var macroEditor: some View {
        sectionBox("Macro") {
            if editor.config.macros.isEmpty {
                Text("No macros yet — create one in the Macros tab.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Macro", selection: $macroID) {
                    Text("—").tag(UUID?.none)
                    ForEach(editor.config.macros) { m in Text(m.name).tag(UUID?.some(m.id)) }
                }
            }
        }
    }

    private var mediaEditor: some View {
        sectionBox("Media Key") {
            Picker("Key", selection: $mediaKey) {
                ForEach(MediaKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
    }

    private var windowEditor: some View {
        sectionBox("Window") {
            Picker("Action", selection: $windowAction) {
                ForEach(WindowAction.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Text("Resizes/moves the frontmost window via Accessibility.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var systemGroups: [(String, [SystemCommand])] {
        ["Spaces", "Window", "Zoom", "Screenshot", "System"].map { group in
            (group, SystemCommand.allCases.filter { $0.group == group })
        }
    }

    private var systemEditor: some View {
        sectionBox("System Command") {
            Picker("Command", selection: $systemCommand) {
                ForEach(systemGroups, id: \.0) { group, commands in
                    Section(group) {
                        ForEach(commands, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
            }
        }
    }

    private var appEditor: some View {
        sectionBox("Open / Focus Application") {
            LabeledContent("App", value: appName.isEmpty ? "—" : appName)
            Menu("Choose running app") {
                ForEach(editor.controller.availableRunningApps, id: \.bundleID) { app in
                    Button(app.name) { appName = app.name; appBundleID = app.bundleID }
                }
            }
            Button("Choose from /Applications…") { chooseApp() }
            TextField("Bundle id (manual)", text: $appBundleID)
            VStack(alignment: .leading, spacing: 4) {
                Text("Launch arguments (one per line)").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $appArgs)
                    .font(.body.monospaced())
                    .frame(minHeight: 52)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                Text("e.g. Chrome → --profile-directory=Profile 1 · --new-window · https://…")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var urlEditor: some View {
        sectionBox("Open URL / File") {
            TextField("https://… or /path/to/file", text: $urlString)
            Text("A web URL (with scheme) or a file/folder path.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var shortcutEditor: some View {
        sectionBox("Run Shortcut") {
            TextField("Shortcut name", text: $shortcutName)
            Text("Runs a Shortcuts.app shortcut with this exact name.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return }
        appBundleID = id
        appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Mirror <-> action

    /// Combined change signal so a single onChange drives commit().
    private var signature: String {
        "\(kind.rawValue)|\(keyMode.rawValue)|\(keyName)|\(modCommand)\(modShift)\(modOption)\(modControl)|\(repeats)|\(sequenceText)|\(sequenceIntervalMs)|\(textValue)|\(mouseKind.rawValue)|\(mouseButton.rawValue)|\(mouseDirection.rawValue)|\(Int(mouseSpeed))|\(mouseAccelerate)|\(macroID?.uuidString ?? "")|\(mediaKey.rawValue)|\(windowAction.rawValue)|\(systemCommand.rawValue)|\(appBundleID)|\(appArgs)|\(urlString)|\(shortcutName)"
    }

    private var modifiers: ModifierSet {
        var m: ModifierSet = []
        if modCommand { m.insert(.command) }
        if modShift { m.insert(.shift) }
        if modOption { m.insert(.option) }
        if modControl { m.insert(.control) }
        return m
    }

    private func load() {
        suppress = true
        switch action {
        case .none:
            kind = .none
        case .keystroke(let c):
            kind = .keystroke
            keyName = c.key.rawValue
            modCommand = c.modifiers.contains(.command)
            modShift = c.modifiers.contains(.shift)
            modOption = c.modifiers.contains(.option)
            modControl = c.modifiers.contains(.control)
            repeats = c.repeatsWhileHeld
            keyMode = c.sequence == nil ? .single : .sequence
            sequenceText = c.sequence?.text ?? ""
            sequenceIntervalMs = c.sequence?.intervalMs ?? KeySequence.defaultIntervalMs
        case .text(let s):
            kind = .text; textValue = s
        case .mouse(let m):
            kind = .mouse; loadMouse(m)
        case .macro(let id):
            kind = .macro; macroID = id
        case .media(let m):
            kind = .media; mediaKey = m
        case .window(let w):
            kind = .window; windowAction = w
        case .system(let s):
            kind = .system; systemCommand = s
        case .launchApp(let id, let name, let args):
            kind = .app; appBundleID = id; appName = name; appArgs = args.joined(separator: "\n")
        case .openURL(let u):
            kind = .openURL; urlString = u
        case .runShortcut(let n):
            kind = .shortcut; shortcutName = n
        }
        DispatchQueue.main.async { suppress = false }
    }

    private func loadMouse(_ m: MouseAction) {
        switch m {
        case .click(let b): mouseKind = .click; mouseButton = b
        case .doubleClick(let b): mouseKind = .doubleClick; mouseButton = b
        case .scroll(let dir, let speed, let accel):
            mouseKind = .scroll; mouseDirection = dir; mouseSpeed = speed; mouseAccelerate = accel
        case .move(let dir, let speed, let accel):
            mouseKind = .move; mouseDirection = dir; mouseSpeed = speed; mouseAccelerate = accel
        }
    }

    private func parseArgs(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func commit() {
        guard !suppress else { return }
        let new: BindingAction
        switch kind {
        case .none:
            new = .none
        case .keystroke:
            switch keyMode {
            case .single:
                new = .keystroke(KeyChord(key: KeyName(keyName), modifiers: modifiers, repeatsWhileHeld: repeats))
            case .sequence:
                let sequence = KeySequence(text: sequenceText, intervalMs: sequenceIntervalMs)
                if sequence.intervalMs != sequenceIntervalMs { sequenceIntervalMs = sequence.intervalMs }   // show the clamped value
                // Modifiers/repeat don't apply to a sequence; keep the key so switching back restores it.
                new = .keystroke(KeyChord(key: KeyName(keyName), sequence: sequence))
            }
        case .text:
            new = .text(textValue)
        case .mouse:
            switch mouseKind {
            case .click: new = .mouse(.click(mouseButton))
            case .doubleClick: new = .mouse(.doubleClick(mouseButton))
            case .scroll: new = .mouse(.scroll(direction: mouseDirection, speed: mouseSpeed, accelerate: mouseAccelerate))
            case .move: new = .mouse(.move(direction: mouseDirection, speed: mouseSpeed, accelerate: mouseAccelerate))
            }
        case .macro:
            new = macroID.map(BindingAction.macro) ?? .none
        case .media:
            new = .media(mediaKey)
        case .window:
            new = .window(windowAction)
        case .system:
            new = .system(systemCommand)
        case .app:
            new = appBundleID.isEmpty ? .none
                : .launchApp(bundleID: appBundleID, name: appName.isEmpty ? appBundleID : appName, args: parseArgs(appArgs))
        case .openURL:
            new = urlString.isEmpty ? .none : .openURL(urlString)
        case .shortcut:
            new = shortcutName.isEmpty ? .none : .runShortcut(shortcutName)
        }
        guard new != action else { return }   // e.g. the re-commit after showing a clamped delay
        action = new
    }
}
