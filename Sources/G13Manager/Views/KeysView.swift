import SwiftUI
import G13Core

struct KeysView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HSplitView {
            // Left: controls + G13 layout. A ScrollView keeps content top-aligned
            // (no vertical centering) and scrolls if the window is short.
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Picker("Profile", selection: $editor.selectedProfileID) {
                            ForEach(editor.config.profiles) { p in Text(p.name).tag(p.id) }
                        }
                        .frame(maxWidth: 260)
                        Spacer()
                    }
                    BankPicker(editor: editor)
                    Divider()
                    G13LayoutView(editor: editor)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 560)

            // Right: binding editor (capped so the layout pane stays wide enough).
            Group {
                if let input = editor.selectedInput {
                    BindingEditorView(editor: editor, input: input)
                } else {
                    ContentUnavailableView("Select a key",
                                           systemImage: "hand.point.up.left",
                                           description: Text("Choose a G13 key to assign an action for the selected bank."))
                }
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 440, maxHeight: .infinity)
        }
    }
}

struct BankPicker: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                Button {
                    editor.selectedBank = i
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color(editor.bankColor(i))).frame(width: 10, height: 10)
                        Text(MKey.forBank(i).displayName)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .tint(editor.selectedBank == i ? .accentColor : .secondary)
            }
            Spacer()
            Text("Editing \(editor.bankName(editor.selectedBank))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct G13LayoutView: View {
    @Bindable var editor: EditorModel

    private let gRows: [[InputID]] = [
        [.g1, .g2, .g3, .g4, .g5, .g6, .g7],
        [.g8, .g9, .g10, .g11, .g12, .g13, .g14],
        [.g15, .g16, .g17, .g18, .g19],
        [.g20, .g21, .g22],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("G-keys").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(gRows.enumerated()), id: \.offset) { _, row in
                    keyRow(row)
                }
            }
            labeled("Thumb", [.left, .stickClick, .right])
            labeled("Joystick (directional mode)", [.joyUp, .joyDown, .joyLeft, .joyRight])
            labeled("LCD soft keys / BD", [.l1, .l2, .l3, .l4, .bd])
        }
    }

    private func labeled(_ title: String, _ keys: [InputID]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            keyRow(keys)
        }
    }

    private func keyRow(_ keys: [InputID]) -> some View {
        HStack(spacing: 8) {
            ForEach(keys, id: \.self) { KeyCap(editor: editor, input: $0) }
        }
    }
}

struct KeyCap: View {
    @Bindable var editor: EditorModel
    let input: InputID

    var body: some View {
        let action = editor.binding(for: input)
        Button {
            editor.selectedInput = input
        } label: {
            VStack(spacing: 2) {
                Text(input.displayName).font(.system(size: 11, weight: .semibold))
                Text(action.summary)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 60, height: 42)
        }
        .buttonStyle(.bordered)
        .tint(tint(for: action))
        .contextMenu {
            Button("Copy binding to all banks (M1–MR)") {
                editor.applyBindingToAllBanks(for: input)
            }
            Divider()
            Button("Clear (this bank)") { editor.setBinding(.none, for: input) }
            Button("Clear in all banks", role: .destructive) { editor.clearInAllBanks(for: input) }
        }
    }

    private func tint(for action: BindingAction) -> Color {
        if editor.selectedInput == input { return .accentColor }
        if case .none = action { return .secondary }
        return .blue
    }
}
