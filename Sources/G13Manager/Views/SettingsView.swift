import SwiftUI
import AppKit
import UniformTypeIdentifiers
import G13Core

struct SettingsView: View {
    @Bindable var editor: EditorModel
    @State private var transferStatus: String?

    private var joystick: JoystickSettings { editor.config.settings.joystick }
    private var accel: AccelerationSettings { editor.config.settings.scrollAcceleration }

    private var rampBinding: Binding<Double> {
        Binding(get: { editor.config.settings.scrollAcceleration.rampSeconds },
                set: { v in editor.updateSettings { $0.scrollAcceleration.rampSeconds = v } })
    }
    private var maxBinding: Binding<Double> {
        Binding(get: { editor.config.settings.scrollAcceleration.maxMultiplier },
                set: { v in editor.updateSettings { $0.scrollAcceleration.maxMultiplier = v } })
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enable G13", isOn: Binding(
                    get: { editor.config.settings.masterEnabled },
                    set: { editor.controller.setMasterEnabled($0) }))
                Toggle("Open at Login", isOn: Binding(
                    get: { editor.config.settings.openAtLogin },
                    set: { on in
                        LoginItem.setEnabled(on)
                        editor.updateSettings { $0.openAtLogin = on }
                    }))
            }

            Section("Joystick") {
                Picker("Mode", selection: Binding(
                    get: { joystick.mode },
                    set: { m in editor.updateSettings { $0.joystick.mode = m } })) {
                    ForEach(JoystickSettings.Mode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }

                LabeledContent("Deadzone") {
                    Slider(value: doubleBinding(\.deadzone, max: 100), in: 5...100, step: 1)
                    Text("\(joystick.deadzone)").monospacedDigit().frame(width: 34)
                }

                if joystick.mode == .mouseMove {
                    LabeledContent("Mouse speed") {
                        Slider(value: speedBinding(\.mouseSpeed), in: 1...30)
                        Text(String(format: "%.0f", joystick.mouseSpeed)).monospacedDigit().frame(width: 34)
                    }
                }
                if joystick.mode == .scrollWheel {
                    LabeledContent("Scroll speed") {
                        Slider(value: speedBinding(\.scrollSpeed), in: 1...20)
                        Text(String(format: "%.0f", joystick.scrollSpeed)).monospacedDigit().frame(width: 34)
                    }
                }
                if joystick.mode != .disabled {
                    Toggle("Invert X", isOn: boolBinding(\.invertX))
                    Toggle("Invert Y", isOn: boolBinding(\.invertY))
                }
                Text(joystickHint).font(.caption).foregroundStyle(.secondary)
            }

            Section("Scroll / Move Acceleration") {
                Stepper("Time to reach max: \(Int(accel.rampSeconds)) sec", value: rampBinding, in: 1...30, step: 1)
                Stepper("Max speed: \(Int(accel.maxMultiplier))×", value: maxBinding, in: 2...12, step: 1)
                Text("Applies when “Accelerate while held” is on for a mouse Scroll/Move binding.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Export / Import") {
                HStack {
                    Button("Export Settings…") { exportSettings() }
                    Button("Import Settings…") { importSettings() }
                }
                Text("One JSON file with every profile, bank, key binding, macro, app association and setting. Importing replaces all of them; the settings it replaces are kept as config.pre-import.json.")
                    .font(.caption).foregroundStyle(.secondary)
                if let transferStatus {
                    Text(transferStatus).font(.caption)
                }
            }

            Section("Permissions") {
                permissionRow("Input Monitoring", granted: editor.controller.inputMonitoringGranted) {
                    Permissions.requestInputMonitoring(); Permissions.openInputMonitoringSettings()
                }
                permissionRow("Accessibility", granted: editor.controller.accessibilityGranted) {
                    Permissions.requestAccessibility(); Permissions.openAccessibilitySettings()
                }
            }

            Section {
                LabeledContent("Device", value: editor.controller.deviceConnected ? "Connected" : "Disconnected")
            }
        }
        .formStyle(.grouped)
    }

    private var joystickHint: String {
        switch joystick.mode {
        case .directionalKeys: return "Stick acts as Joy ↑/↓/←/→ — assign them per bank in the Keys tab."
        case .mouseMove: return "Stick moves the mouse pointer."
        case .scrollWheel: return "Stick scrolls: up/down = vertical, left/right = horizontal."
        case .disabled: return "Stick does nothing."
        }
    }

    // MARK: - Export / import

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let today = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        panel.nameFieldStringValue = "G13Manager-Settings-\(today).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try editor.exportConfig(to: url)
            transferStatus = "Exported to \(url.lastPathComponent)."
        } catch {
            showError("Couldn’t export settings", error)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let imported: Config
        do {
            imported = try ConfigStore.readImport(from: url)
        } catch {
            showError("Couldn’t import settings", error)
            return
        }

        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "Replace all settings with “\(url.lastPathComponent)”?"
        confirm.informativeText = "The file has \(imported.profiles.count) profile(s) and \(imported.macros.count) macro(s). Your current profiles, key bindings, macros, app associations and settings will be replaced; they are kept as config.pre-import.json."
        confirm.addButton(withTitle: "Import")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            try editor.importConfig(imported)
            transferStatus = "Imported \(url.lastPathComponent)."
        } catch {
            showError("Couldn’t import settings", error)
        }
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func permissionRow(_ name: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(name)
            Spacer()
            if granted { Text("Granted").foregroundStyle(.secondary) }
            else { Button("Grant…", action: action) }
        }
    }

    // MARK: - Binding helpers into JoystickSettings

    private func doubleBinding(_ keyPath: WritableKeyPath<JoystickSettings, UInt8>, max: Double) -> Binding<Double> {
        Binding(
            get: { Double(editor.config.settings.joystick[keyPath: keyPath]) },
            set: { v in editor.updateSettings { $0.joystick[keyPath: keyPath] = UInt8(min(max, v.rounded())) } })
    }

    private func speedBinding(_ keyPath: WritableKeyPath<JoystickSettings, Double>) -> Binding<Double> {
        Binding(
            get: { editor.config.settings.joystick[keyPath: keyPath] },
            set: { v in editor.updateSettings { $0.joystick[keyPath: keyPath] = v } })
    }

    private func boolBinding(_ keyPath: WritableKeyPath<JoystickSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { editor.config.settings.joystick[keyPath: keyPath] },
            set: { v in editor.updateSettings { $0.joystick[keyPath: keyPath] = v } })
    }
}
