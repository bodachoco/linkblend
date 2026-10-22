import SwiftUI

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var model: LinkModel
    @State private var launchAtLogin = false
    @AppStorage("developerMode") private var developerMode = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onAppear { launchAtLogin = Autostart.isOn }
                    .onChange(of: launchAtLogin) { _, newValue in
                        guard newValue != Autostart.isOn else { return }
                        Autostart.set(newValue)
                    }
                Toggle("Notify when a link connects or drops", isOn: Binding(
                    get: { model.notificationsEnabled },
                    set: { model.setNotifications($0) }
                ))
            }

            Section("Merging") {
                Toggle("Merge connections", isOn: Binding(
                    get: { !model.pausedByUser },
                    set: { model.setMerging($0) }
                ))
                Toggle("Prefer the fastest healthy link automatically", isOn: Binding(
                    get: { model.autoPrefer },
                    set: { model.setAutoPrefer($0) }
                ))
                Picker("Preferred connection", selection: Binding(
                    get: { model.preferredDevice },
                    set: { model.setPreferred(device: $0) }
                )) {
                    ForEach(model.rows) { row in
                        Text(row.service).tag(row.device)
                    }
                }
                Text("Automatic preference follows the lowest-latency healthy link.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("Engine") {
                Picker("Adapter weighting", selection: Binding(
                    get: { model.weightingMode },
                    set: { model.setWeightingMode($0) }
                )) {
                    Text("Automatic").tag("auto")
                    Text("Manual").tag("manual")
                }
                Picker("Turn merging off after", selection: Binding(
                    get: { model.autoOffMinutes },
                    set: { model.setAutoOff($0) }
                )) {
                    Text("Never").tag(0)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }
            }

            Section("Developer") {
                Toggle("Developer mode", isOn: $developerMode)
                Text("Developer mode adds a Developer section with engine diagnostics, adapter weights, raw status, and logs.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                Button("Clear usage data") { model.clearUsage() }
                LabeledContent("Usage kept", value: "30 days")
            }

            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Engine", value: "net-merge")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 520)
        .navigationTitle("Settings")
    }
}
