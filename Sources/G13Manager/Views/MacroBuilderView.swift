import SwiftUI
import UniformTypeIdentifiers
import G13Core

// MARK: - Drag payload

extension UTType {
    /// In-app drag identity for macro builder palette chips & step cards.
    static let g13MacroItem = UTType(exportedAs: "dev.tuttisound.g13.macroitem")
}

/// A single drag carries EITHER a new palette action (`paletteKind`) or an
/// existing step being reordered (`stepID`).
struct MacroDragItem: Codable, Transferable {
    var paletteKind: String?
    var stepID: String?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .g13MacroItem)
    }
}

// MARK: - Palette action kinds

enum PaletteKind: String, CaseIterable, Identifiable {
    case keystroke, text, mouse, media, window, system, openApp, openURL, runShortcut, wait
    var id: String { rawValue }

    var title: String {
        switch self {
        case .keystroke: return "Keystroke"
        case .text: return "Text"
        case .mouse: return "Mouse"
        case .media: return "Media"
        case .window: return "Window"
        case .system: return "System"
        case .openApp: return "Open App"
        case .openURL: return "Open URL"
        case .runShortcut: return "Shortcut"
        case .wait: return "Wait"
        }
    }

    var icon: String {
        switch self {
        case .keystroke: return "keyboard"
        case .text: return "text.cursor"
        case .mouse: return "cursorarrow.click"
        case .media: return "playpause"
        case .window: return "macwindow"
        case .system: return "switch.2"
        case .openApp: return "app.dashed"
        case .openURL: return "link"
        case .runShortcut: return "bolt"
        case .wait: return "clock"
        }
    }

    /// App/Window/URL steps need time for the target to appear before the next step.
    var defaultDelayMs: Int {
        switch self {
        case .openApp: return 800
        case .openURL: return 600
        case .window: return 300
        case .wait: return 300
        default: return 60
        }
    }

    func makeAction() -> BindingAction {
        switch self {
        case .keystroke: return .keystroke(KeyChord(key: "a"))
        case .text: return .text("")
        case .mouse: return .mouse(.click(.left))
        case .media: return .media(.playPause)
        case .window: return .window(.leftHalf)
        case .system: return .system(.missionControl)
        case .openApp: return .launchApp(bundleID: "", name: "", args: [])
        case .openURL: return .openURL("")
        case .runShortcut: return .runShortcut("")
        case .wait: return .none
        }
    }
}

/// Title/icon for an action as shown on a step card.
enum StepStyle {
    static func title(_ a: BindingAction) -> String {
        switch a {
        case .none: return "Wait"
        case .keystroke: return "Keystroke"
        case .text: return "Type Text"
        case .mouse: return "Mouse"
        case .macro: return "Macro"
        case .media: return "Media"
        case .window: return "Window"
        case .system: return "System"
        case .launchApp: return "Open App"
        case .openURL: return "Open URL"
        case .runShortcut: return "Run Shortcut"
        }
    }

    static func icon(_ a: BindingAction) -> String {
        switch a {
        case .none: return "clock"
        case .keystroke: return "keyboard"
        case .text: return "text.cursor"
        case .mouse: return "cursorarrow.click"
        case .macro: return "wand.and.stars"
        case .media: return "playpause"
        case .window: return "macwindow"
        case .system: return "switch.2"
        case .launchApp: return "app.dashed"
        case .openURL: return "link"
        case .runShortcut: return "bolt"
        }
    }
}

// MARK: - Top-level builder

struct MacroBuilderView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HSplitView {
            MacroSidebar(editor: editor)
                .frame(minWidth: 200, idealWidth: 230, maxWidth: 300)

            Group {
                if let id = editor.selectedMacroID, let macro = editor.macro(id) {
                    MacroCanvas(editor: editor, macro: macro)
                        .id(id)   // reset per-macro canvas state on switch
                } else {
                    ContentUnavailableView("No macro selected",
                                           systemImage: "wand.and.stars",
                                           description: Text("Create a macro on the left, then drag actions from the palette to build it."))
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Sidebar

struct MacroSidebar: View {
    @Bindable var editor: EditorModel
    @State private var recordingName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $editor.selectedMacroID) {
                ForEach(editor.config.macros) { m in
                    Label(m.name, systemImage: "wand.and.stars").tag(Optional(m.id))
                }
            }

            HStack(spacing: 6) {
                Button { editor.newMacro() } label: { Image(systemName: "plus") }
                    .help("New macro")
                if let id = editor.selectedMacroID {
                    Button { editor.duplicateMacro(id) } label: { Image(systemName: "plus.square.on.square") }
                        .help("Duplicate")
                    Button(role: .destructive) { editor.deleteMacro(id) } label: { Image(systemName: "trash") }
                        .help("Delete")
                }
                Spacer()
            }

            Divider()
            recordButton
            if editor.controller.isRecording {
                Label("Recording… type keys, then Stop.", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.red).font(.caption)
            } else {
                Text("Record captures keystrokes into steps you can refine.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var recordButton: some View {
        Button {
            if editor.controller.isRecording {
                let m = editor.controller.stopRecording(name: recordingName.isEmpty ? "Recorded Macro" : recordingName)
                editor.addMacro(m)
            } else {
                recordingName = "Macro \(editor.config.macros.count + 1)"
                _ = editor.controller.startRecording()
            }
        } label: {
            Label(editor.controller.isRecording ? "Stop Recording" : "Record Macro",
                  systemImage: editor.controller.isRecording ? "stop.circle.fill" : "record.circle")
                .frame(maxWidth: .infinity)
        }
        .tint(editor.controller.isRecording ? .red : .accentColor)
    }
}

// MARK: - Canvas (palette + sequence)

struct MacroCanvas: View {
    @Bindable var editor: EditorModel
    let macro: Macro
    @State private var expandedStepID: UUID?
    @State private var targetedGap: Int?

    private var macroID: UUID { macro.id }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            palette
            Divider()
            sequence
        }
    }

    // Name, repeat count, run/stop.
    private var topBar: some View {
        HStack(spacing: 10) {
            TextField("Macro name", text: Binding(
                get: { macro.name },
                set: { editor.renameMacro(macroID, $0) }))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            Stepper(value: editor.repeatCountBinding(macroID: macroID), in: 1...99) {
                Text("Repeat ×\(macro.repeatCount)").font(.callout)
            }
            .fixedSize()

            Spacer()

            Button { editor.controller.play(macro) } label: {
                Label("Run", systemImage: "play.fill")
            }
            .disabled(macro.steps.isEmpty)
            Button { editor.controller.stopMacro() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        }
        .padding(10)
    }

    // Draggable action chips; click appends, drag inserts.
    private var palette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PaletteKind.allCases) { kind in
                    PaletteChip(kind: kind) {
                        editor.appendStep(kind.makeAction(), delayAfterMs: kind.defaultDelayMs, macroID: macroID)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .background(.quaternary.opacity(0.25))
    }

    private var sequence: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if macro.steps.isEmpty {
                    emptyDropZone
                } else {
                    gap(0)
                    ForEach(Array(macro.steps.enumerated()), id: \.element.id) { idx, step in
                        StepCard(editor: editor, macroID: macroID, step: step,
                                 index: idx, total: macro.steps.count,
                                 expandedStepID: $expandedStepID)
                        gap(idx + 1)
                    }
                }
            }
            .padding(12)
            .animation(.default, value: macro.steps.map(\.id))
        }
    }

    // A thin drop zone between cards; lights up when a drag hovers.
    @ViewBuilder
    private func gap(_ index: Int) -> some View {
        let active = targetedGap == index
        RoundedRectangle(cornerRadius: 2)
            .fill(active ? Color.accentColor : Color.clear)
            .frame(height: active ? 4 : 8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .dropDestination(for: MacroDragItem.self) { items, _ in
                guard let item = items.first else { return false }
                handleDrop(item, atGap: index)
                return true
            } isTargeted: { targetedGap = $0 ? index : nil }
    }

    private var emptyDropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.dashed").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Drag actions here — or click a chip above to add a step.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).frame(height: 170)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(targetedGap == 0 ? Color.accentColor.opacity(0.12) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
            .foregroundStyle(.quaternary))
        .dropDestination(for: MacroDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            handleDrop(item, atGap: 0)
            return true
        } isTargeted: { targetedGap = $0 ? 0 : nil }
    }

    private func handleDrop(_ item: MacroDragItem, atGap gap: Int) {
        if let raw = item.paletteKind, let kind = PaletteKind(rawValue: raw) {
            editor.insertStep(kind.makeAction(), atGap: gap, delayAfterMs: kind.defaultDelayMs, macroID: macroID)
        } else if let sid = item.stepID, let uuid = UUID(uuidString: sid) {
            editor.moveStep(uuid, toGap: gap, macroID: macroID)
        }
    }
}

// MARK: - Palette chip

struct PaletteChip: View {
    let kind: PaletteKind
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.icon)
            Text(kind.title).font(.caption)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(Capsule().stroke(.quaternary))
        .contentShape(Capsule())
        .onTapGesture { onTap() }
        .draggable(MacroDragItem(paletteKind: kind.rawValue)) {
            Label(kind.title, systemImage: kind.icon).padding(6).background(.thinMaterial)
        }
        .help("Drag into the sequence, or click to append")
    }
}

// MARK: - Step card

struct StepCard: View {
    @Bindable var editor: EditorModel
    let macroID: UUID
    let step: MacroStep
    let index: Int
    let total: Int
    @Binding var expandedStepID: UUID?

    private var isExpanded: Bool { expandedStepID == step.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                Divider()
                ActionEditorView(action: editor.stepActionBinding(macroID: macroID, stepID: step.id),
                                 context: .macroStep,
                                 reloadKey: step.id,
                                 editor: editor)
                    .padding(10)
                Divider()
                waitField.padding(10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isExpanded ? Color.accentColor : Color.black.opacity(0.08), lineWidth: isExpanded ? 1.5 : 1))
        .contextMenu { menuItems }
    }

    private var header: some View {
        HStack(spacing: 10) {
            // Drag handle (only this initiates a reorder drag).
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .draggable(MacroDragItem(stepID: step.id.uuidString)) {
                    Label(StepStyle.title(step.action), systemImage: StepStyle.icon(step.action))
                        .padding(6).background(.thinMaterial)
                }

            Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18)

            Image(systemName: StepStyle.icon(step.action))
                .foregroundStyle(.tint).frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(StepStyle.title(step.action)).font(.callout.weight(.semibold))
                Text(step.action.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            Text("\(step.delayAfterMs)ms").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)

            Toggle("", isOn: editor.stepEnabledBinding(macroID: macroID, stepID: step.id))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                .help("Enable / disable this step")

            Button {
                expandedStepID = isExpanded ? nil : step.id
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.borderless)

            Menu { menuItems } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .opacity(step.isEnabled ? 1 : 0.45)
        .contentShape(Rectangle())
        .onTapGesture { expandedStepID = isExpanded ? nil : step.id }
    }

    private var waitField: some View {
        HStack(spacing: 8) {
            Text("Wait after").font(.callout)
            TextField("ms", value: editor.stepDelayBinding(macroID: macroID, stepID: step.id), format: .number)
                .frame(width: 72).textFieldStyle(.roundedBorder)
            Stepper("", value: editor.stepDelayBinding(macroID: macroID, stepID: step.id), in: 0...600_000, step: 50)
                .labelsHidden()
            Text("ms before the next step").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Move Up") { editor.moveStepUp(step.id, macroID: macroID) }.disabled(index == 0)
        Button("Move Down") { editor.moveStepDown(step.id, macroID: macroID) }.disabled(index >= total - 1)
        Divider()
        Button("Duplicate") { editor.duplicateStep(step.id, macroID: macroID) }
        Button("Delete", role: .destructive) {
            if expandedStepID == step.id { expandedStepID = nil }
            editor.deleteStep(step.id, macroID: macroID)
        }
    }
}
