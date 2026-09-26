import SwiftUI
import G13Core

/// Per-key action editor (Keys tab). Thin wrapper around the shared
/// `ActionEditorView`, bound to the selected bank's binding for `input`.
struct BindingEditorView: View {
    @Bindable var editor: EditorModel
    let input: InputID

    var body: some View {
        ScrollView {
            ActionEditorView(action: editor.bindingBinding(for: input),
                             context: .keyBinding,
                             title: input.displayName,
                             // Reload the mirror when the key, bank, or profile changes.
                             reloadKey: "\(editor.selectedProfileID)|\(editor.selectedBank)|\(input.rawValue)",
                             editor: editor)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
