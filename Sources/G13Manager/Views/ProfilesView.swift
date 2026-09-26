import SwiftUI
import G13Core

struct ProfilesView: View {
    @Bindable var editor: EditorModel
    @State private var newProfileName = ""
    @State private var manualBundleID = ""

    private var selectedProfile: Profile? { editor.selectedProfile }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                List(selection: $editor.selectedProfileID) {
                    ForEach(editor.config.profiles) { p in
                        HStack {
                            Text(p.name)
                            if p.id == editor.config.defaultProfileID {
                                Text("default").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .tag(p.id)
                    }
                }
                .frame(minWidth: 220)

                HStack {
                    TextField("New profile", text: $newProfileName).textFieldStyle(.roundedBorder)
                    Button {
                        editor.addProfile(name: newProfileName); newProfileName = ""
                    } label: { Image(systemName: "plus") }
                    if let id = editor.selectedProfileID as UUID?, editor.config.profiles.count > 1 {
                        Button(role: .destructive) { editor.deleteProfile(id) } label: { Image(systemName: "trash") }
                    }
                }
            }
            .padding()

            ScrollView {
                if let profile = selectedProfile {
                    profileDetail(profile)
                } else {
                    ContentUnavailableView("No profile", systemImage: "person.2")
                }
            }
            .frame(minWidth: 380)
            .padding()
        }
    }

    private func profileDetail(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Profile name", text: Binding(
                    get: { profile.name },
                    set: { editor.renameProfile(profile.id, $0) }))
                    .textFieldStyle(.roundedBorder).font(.headline)
                if profile.id != editor.config.defaultProfileID {
                    Button("Make Default") { editor.setDefaultProfile(profile.id) }
                }
            }

            GroupBox("Banks (M1 / M2 / M3 / MR)") {
                VStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        HStack {
                            Text(MKey.forBank(i).displayName).frame(width: 36, alignment: .leading)
                                .foregroundStyle(.secondary)
                            TextField("Bank name", text: Binding(
                                get: { profile.banks[safe: i]?.name ?? "" },
                                set: { editor.setBankName($0, bank: i) }))
                                .textFieldStyle(.roundedBorder)
                            ColorPicker("", selection: Binding(
                                get: { Color(profile.banks[safe: i]?.color ?? .off) },
                                set: { editor.setBankColor($0.rgbColor, bank: i) }))
                                .labelsHidden()
                        }
                    }
                }
                .padding(6)
            }

            appsSection
        }
    }

    private var appsSection: some View {
        GroupBox("App → Profile") {
            VStack(alignment: .leading, spacing: 8) {
                Text("When one of these apps is frontmost, its profile activates automatically.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(editor.config.apps) { app in
                    HStack {
                        Text(app.bundleIdentifier).font(.system(.body, design: .monospaced)).lineLimit(1)
                        Spacer()
                        Text(editor.config.profile(id: app.profileID)?.name ?? "?")
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) { editor.deleteApp(app.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }

                Divider()
                HStack {
                    Menu("Add running app → \(selectedProfile?.name ?? "")") {
                        ForEach(editor.controller.availableRunningApps, id: \.bundleID) { app in
                            Button(app.name) {
                                editor.setAppAssociation(bundleID: app.bundleID, profileID: editor.selectedProfileID)
                            }
                        }
                    }
                }
                HStack {
                    TextField("com.example.App (manual bundle id)", text: $manualBundleID)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        editor.setAppAssociation(bundleID: manualBundleID, profileID: editor.selectedProfileID)
                        manualBundleID = ""
                    }
                }
            }
            .padding(6)
        }
    }
}
