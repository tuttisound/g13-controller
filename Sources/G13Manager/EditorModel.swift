import Foundation
import Observation
import SwiftUI
import G13Core

/// View-model bridging the SwiftUI editors to `AppController`. Holds the GUI's
/// editing selection (which profile/bank/input is being edited — independent of
/// the live active bank that follows the device) and applies mutations through
/// `controller.apply`, which persists and re-applies live.
@MainActor
@Observable
final class EditorModel {
    let controller: AppController

    var selectedProfileID: UUID
    var selectedBank: Int = 0
    var selectedInput: InputID?
    var selectedMacroID: UUID?

    init(controller: AppController) {
        self.controller = controller
        self.selectedProfileID = controller.config.defaultProfileID
    }

    var config: Config { controller.config }

    var selectedProfile: Profile? {
        config.profiles.first { $0.id == selectedProfileID }
    }

    // MARK: - Generic mutation

    private func mutate(_ block: (inout Config) -> Void) {
        var c = controller.config
        block(&c)
        controller.apply(c)
    }

    private func mutateSelectedBank(_ block: (inout Bank) -> Void) {
        mutate { c in
            guard let p = c.profiles.firstIndex(where: { $0.id == selectedProfileID }),
                  c.profiles[p].banks.indices.contains(selectedBank) else { return }
            block(&c.profiles[p].banks[selectedBank])
        }
    }

    // MARK: - Bindings

    func binding(for input: InputID) -> BindingAction {
        selectedProfile?.banks[safe: selectedBank]?.binding(for: input) ?? .none
    }

    func setBinding(_ action: BindingAction, for input: InputID) {
        mutateSelectedBank { bank in
            if case .none = action {
                bank.bindings[input] = nil
            } else {
                bank.bindings[input] = action
            }
        }
    }

    /// Two-way binding to a key's action, for the shared `ActionEditorView`.
    func bindingBinding(for input: InputID) -> Binding<BindingAction> {
        Binding(get: { [weak self] in self?.binding(for: input) ?? .none },
                set: { [weak self] in self?.setBinding($0, for: input) })
    }

    /// Copy the selected bank's binding for `input` to ALL 4 banks (M1–MR) of the profile.
    func applyBindingToAllBanks(for input: InputID) {
        applyToAllBanks(input: input, action: binding(for: input))
    }

    /// Clear `input` in all 4 banks.
    func clearInAllBanks(for input: InputID) {
        applyToAllBanks(input: input, action: .none)
    }

    private func applyToAllBanks(input: InputID, action: BindingAction) {
        mutate { c in
            guard let p = c.profiles.firstIndex(where: { $0.id == selectedProfileID }) else { return }
            for b in c.profiles[p].banks.indices {
                if case .none = action {
                    c.profiles[p].banks[b].bindings[input] = nil
                } else {
                    c.profiles[p].banks[b].bindings[input] = action
                }
            }
        }
    }

    // MARK: - Banks

    func bankName(_ index: Int) -> String {
        selectedProfile?.banks[safe: index]?.name ?? "Bank \(index + 1)"
    }

    func bankColor(_ index: Int) -> G13Core.RGBColor {
        selectedProfile?.banks[safe: index]?.color ?? .off
    }

    func setBankName(_ name: String, bank: Int) {
        mutate { c in
            guard let p = c.profiles.firstIndex(where: { $0.id == selectedProfileID }),
                  c.profiles[p].banks.indices.contains(bank) else { return }
            c.profiles[p].banks[bank].name = name
        }
    }

    func setBankColor(_ color: G13Core.RGBColor, bank: Int) {
        mutate { c in
            guard let p = c.profiles.firstIndex(where: { $0.id == selectedProfileID }),
                  c.profiles[p].banks.indices.contains(bank) else { return }
            c.profiles[p].banks[bank].color = color
        }
    }

    // MARK: - Profiles

    func addProfile(name: String) {
        let p = ConfigStore.makeDefaultProfile(name: name.isEmpty ? "New Profile" : name)
        mutate { $0.profiles.append(p) }
        selectedProfileID = p.id
    }

    func renameProfile(_ id: UUID, _ name: String) {
        mutate { c in
            if let i = c.profiles.firstIndex(where: { $0.id == id }) { c.profiles[i].name = name }
        }
    }

    func deleteProfile(_ id: UUID) {
        guard config.profiles.count > 1 else { return }   // keep at least one
        mutate { c in
            c.profiles.removeAll { $0.id == id }
            c.apps.removeAll { $0.profileID == id }
            if c.defaultProfileID == id { c.defaultProfileID = c.profiles[0].id }
        }
        if selectedProfileID == id { selectedProfileID = config.defaultProfileID }
    }

    func setDefaultProfile(_ id: UUID) {
        mutate { $0.defaultProfileID = id }
    }

    // MARK: - App associations

    func setAppAssociation(bundleID: String, profileID: UUID) {
        guard !bundleID.isEmpty else { return }
        mutate { c in
            c.apps.removeAll { $0.bundleIdentifier == bundleID }
            c.apps.append(AppAssociation(bundleIdentifier: bundleID, profileID: profileID))
        }
    }

    func deleteApp(_ id: UUID) {
        mutate { c in c.apps.removeAll { $0.id == id } }
    }

    // MARK: - Macros

    func addMacro(_ macro: Macro) {
        mutate { $0.macros.append(macro) }
        selectedMacroID = macro.id
    }

    /// Create a fresh empty macro and select it.
    @discardableResult
    func newMacro() -> UUID {
        let m = Macro(name: "Macro \(config.macros.count + 1)")
        addMacro(m)
        return m.id
    }

    func renameMacro(_ id: UUID, _ name: String) {
        mutate { c in if let i = c.macros.firstIndex(where: { $0.id == id }) { c.macros[i].name = name } }
    }

    func deleteMacro(_ id: UUID) {
        mutate { c in c.macros.removeAll { $0.id == id } }
        if selectedMacroID == id { selectedMacroID = nil }
    }

    func duplicateMacro(_ id: UUID) {
        guard let src = config.macros.first(where: { $0.id == id }) else { return }
        // Fresh step ids so the copy is independent.
        let steps = src.steps.map { MacroStep(action: $0.action, delayAfterMs: $0.delayAfterMs, isEnabled: $0.isEnabled) }
        addMacro(Macro(name: src.name + " copy", steps: steps, repeatCount: src.repeatCount))
    }

    func macro(_ id: UUID?) -> Macro? {
        guard let id else { return nil }
        return config.macros.first { $0.id == id }
    }

    private func mutateMacro(_ id: UUID, _ block: (inout Macro) -> Void) {
        mutate { c in if let i = c.macros.firstIndex(where: { $0.id == id }) { block(&c.macros[i]) } }
    }

    func setRepeatCount(_ count: Int, macroID: UUID) {
        mutateMacro(macroID) { $0.repeatCount = max(1, count) }
    }

    // MARK: Macro steps (RPA builder)

    /// Insert a new step (from a palette drop) before the step currently at `gap`.
    func insertStep(_ action: BindingAction, atGap gap: Int, delayAfterMs: Int = 60, macroID: UUID) {
        mutateMacro(macroID) { m in
            let i = min(max(0, gap), m.steps.count)
            m.steps.insert(MacroStep(action: action, delayAfterMs: delayAfterMs), at: i)
        }
    }

    func appendStep(_ action: BindingAction, delayAfterMs: Int = 60, macroID: UUID) {
        mutateMacro(macroID) { $0.steps.append(MacroStep(action: action, delayAfterMs: delayAfterMs)) }
    }

    func deleteStep(_ stepID: UUID, macroID: UUID) {
        mutateMacro(macroID) { $0.steps.removeAll { $0.id == stepID } }
    }

    func duplicateStep(_ stepID: UUID, macroID: UUID) {
        mutateMacro(macroID) { m in
            guard let i = m.steps.firstIndex(where: { $0.id == stepID }) else { return }
            let s = m.steps[i]
            m.steps.insert(MacroStep(action: s.action, delayAfterMs: s.delayAfterMs, isEnabled: s.isEnabled), at: i + 1)
        }
    }

    /// Move the step with `stepID` so it lands before the step currently at `gap`
    /// (drag-to-reorder; accounts for the removal shift).
    func moveStep(_ stepID: UUID, toGap gap: Int, macroID: UUID) {
        mutateMacro(macroID) { m in
            guard let from = m.steps.firstIndex(where: { $0.id == stepID }) else { return }
            var dest = min(max(0, gap), m.steps.count)
            let step = m.steps.remove(at: from)
            if from < dest { dest -= 1 }
            dest = min(max(0, dest), m.steps.count)
            m.steps.insert(step, at: dest)
        }
    }

    /// Menu fallbacks for reordering without dragging.
    func moveStepUp(_ stepID: UUID, macroID: UUID) {
        mutateMacro(macroID) { m in
            guard let i = m.steps.firstIndex(where: { $0.id == stepID }), i > 0 else { return }
            m.steps.swapAt(i, i - 1)
        }
    }

    func moveStepDown(_ stepID: UUID, macroID: UUID) {
        mutateMacro(macroID) { m in
            guard let i = m.steps.firstIndex(where: { $0.id == stepID }), i < m.steps.count - 1 else { return }
            m.steps.swapAt(i, i + 1)
        }
    }

    // MARK: Per-step bindings (for inline editors / cards)

    func stepActionBinding(macroID: UUID, stepID: UUID) -> Binding<BindingAction> {
        Binding(
            get: { [weak self] in
                self?.macro(macroID)?.steps.first { $0.id == stepID }?.action ?? .none
            },
            set: { [weak self] newValue in
                self?.mutateMacro(macroID) { m in
                    if let i = m.steps.firstIndex(where: { $0.id == stepID }) { m.steps[i].action = newValue }
                }
            })
    }

    func stepDelayBinding(macroID: UUID, stepID: UUID) -> Binding<Int> {
        Binding(
            get: { [weak self] in
                self?.macro(macroID)?.steps.first { $0.id == stepID }?.delayAfterMs ?? 0
            },
            set: { [weak self] newValue in
                self?.mutateMacro(macroID) { m in
                    if let i = m.steps.firstIndex(where: { $0.id == stepID }) { m.steps[i].delayAfterMs = max(0, newValue) }
                }
            })
    }

    func stepEnabledBinding(macroID: UUID, stepID: UUID) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                self?.macro(macroID)?.steps.first { $0.id == stepID }?.isEnabled ?? true
            },
            set: { [weak self] newValue in
                self?.mutateMacro(macroID) { m in
                    if let i = m.steps.firstIndex(where: { $0.id == stepID }) { m.steps[i].isEnabled = newValue }
                }
            })
    }

    func repeatCountBinding(macroID: UUID) -> Binding<Int> {
        Binding(
            get: { [weak self] in self?.macro(macroID)?.repeatCount ?? 1 },
            set: { [weak self] in self?.setRepeatCount($0, macroID: macroID) })
    }

    // MARK: - Settings

    func updateSettings(_ block: (inout GlobalSettings) -> Void) {
        mutate { block(&$0.settings) }
    }
}
