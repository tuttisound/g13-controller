import SwiftUI
import G13Core

/// Live pipeline diagnostics to localize failures: read path (device → reports),
/// resolve/inject pipeline, and the injection (write) path.
struct DiagnosticsView: View {
    let editor: EditorModel
    @State private var testText = "G13_OK "

    private var c: AppController { editor.controller }

    var body: some View {
        Form {
            Section("1 · Read path (device → app)") {
                LabeledContent("Device connected", value: c.deviceConnected ? "Yes ✓" : "No ✗")
                LabeledContent("Input Monitoring", value: c.inputMonitoringGranted ? "Granted ✓" : "NOT granted ✗")
                LabeledContent("Reports received", value: "\(c.reportsReceived)")
                LabeledContent("Last key report", value: c.lastReportHex)
                Text("Press G13 keys / move the stick. “Reports received” must climb and “Last key report” must change. If it stays 0, the read path or Input Monitoring is the problem.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("2 · Pipeline (decode → resolve → inject)") {
                LabeledContent("Last input event", value: c.lastEventText)
                LabeledContent("Resolved action", value: c.lastActionText)
                LabeledContent("Injections fired", value: "\(c.injectionCount)")
                Button("Simulate G1 press (uses current binding)") { c.simulateInput(.g1) }
                Text("This feeds a synthetic G1 press through resolve→inject without the device. Bind G1 to something first (Keys tab), focus another app, then click.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("3 · Injection (write path)") {
                LabeledContent("Accessibility", value: c.accessibilityGranted ? "Granted ✓" : "NOT granted ✗")
                HStack {
                    TextField("Test text", text: $testText)
                    Button("Type into frontmost app") { c.injectTestText(testText) }
                }
                Text("Focus TextEdit, then click. If the text appears there, injection works.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
