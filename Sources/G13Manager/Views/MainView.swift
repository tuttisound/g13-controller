import SwiftUI
import G13Core

struct MainView: View {
    let editor: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            PermissionBanner(controller: editor.controller)
            TabView {
                KeysView(editor: editor)
                    .tabItem { Label("Keys", systemImage: "keyboard") }
                MacroBuilderView(editor: editor)
                    .tabItem { Label("Macros", systemImage: "wand.and.stars") }
                ProfilesView(editor: editor)
                    .tabItem { Label("Profiles", systemImage: "person.2") }
                SettingsView(editor: editor)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                DiagnosticsView(editor: editor)
                    .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            }
            .padding(8)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct PermissionBanner: View {
    let controller: AppController

    var body: some View {
        if !controller.inputMonitoringGranted || !controller.accessibilityGranted {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permissions required").font(.headline)
                    Text("Input Monitoring lets G13 Manager read the device; Accessibility lets it send keystrokes. Grant both, then this banner disappears.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 6) {
                    if !controller.inputMonitoringGranted {
                        Button("Input Monitoring…") {
                            Permissions.requestInputMonitoring()
                            Permissions.openInputMonitoringSettings()
                        }
                    }
                    if !controller.accessibilityGranted {
                        Button("Accessibility…") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.12))
        }
    }
}
