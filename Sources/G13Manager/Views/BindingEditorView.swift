import SwiftUI
import G13Core

/// Per-key action editor (Keys tab). Thin wrapper around the shared
/// `ActionEditorView`, bound to the selected bank's binding for `input`.
struct BindingEditorView: View {
    @Bindable var editor: EditorModel
    let input: InputID

    var body: some View {
        let target = "\(editor.selectedProfileID)|\(editor.selectedBank)|\(input.rawValue)"
        ScrollView {
            ActionEditorView(action: editor.bindingBinding(for: input),
                             context: .keyBinding,
                             title: input.displayName,
                             // Reload the mirror when the key, bank, or profile changes.
                             reloadKey: target,
                             editor: editor)
                // Fresh editor state per key: an uncommitted field edit or the
                // previous key's values must never be saved onto the next key.
                .id(target)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
