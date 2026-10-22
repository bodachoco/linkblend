import SwiftUI

// MARK: - Developer tab

struct DeveloperView: View {
    @ObservedObject var model: LinkModel
    @State private var confirmRestart = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Engine") {
                    LabeledContent("Process", value: model.statusPID.map(String.init) ?? "—")
                    LabeledContent("Mode", value: model.statusMode ?? "—")
                    LabeledContent("Status updated", value: model.statusUpdated ?? "—")
                    LabeledContent("Adapters in tunnel", value: "\(model.tunnelCount)")
                    HStack {
                        Button("Refresh diagnostics") { model.loadDevData() }
                            .buttonStyle(.glass)
                        Button("Copy diagnostics") { model.copyDiagnostics() }
                            .buttonStyle(.glass)
                        Spacer()
                        Button("Restart engine", role: .destructive) { confirmRestart = true }
                            .buttonStyle(.glass)
                    }
                    Text("Restart sends net-merge off. The supervisor starts it again within a few seconds, with your saved weights.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                section("Engine tuning") {
                    Picker("IPv6", selection: Binding(
                        get: { model.ipv6Mode },
                        set: { model.setIPv6Mode($0) }
                    )) {
                        Text("Automatic").tag("auto")
                        Text("Always").tag("on")
                        Text("Off").tag("off")
                    }
                    Picker("Tunnel MTU", selection: Binding(
                        get: { model.mtu },
                        set: { model.setMTU($0) }
                    )) {
                        Text("1500 — compatibility").tag(1500)
                        Text("4096").tag(4096)
                        Text("9000 — performance").tag(9000)
                    }
                    Picker("Adapter rescan", selection: Binding(
                        get: { model.rescanSec },
                        set: { model.setRescan($0) }
                    )) {
                        Text("1s — fastest detection").tag(1)
                        Text("3s").tag(3)
                        Text("10s — least CPU").tag(10)
                    }
                    Toggle("Go profiler on 127.0.0.1:6060", isOn: Binding(
                        get: { model.profilerOn },
                        set: { model.setProfiler($0) }
                    ))
                    ForEach(model.rows) { row in
                        Toggle("Include \(row.service) in engine", isOn: Binding(
                            get: { !model.engineExcluded.contains(row.device) },
                            set: { model.setEngineIncluded(device: row.device, included: $0) }
                        ))
                    }
                    HStack {
                        Spacer()
                        Button("Apply and restart engine") { model.applyEngineSettings() }
                            .buttonStyle(.glassProminent)
                            .tint(Brand.accent)
                    }
                }

                section("Per-app proxy (SOCKS5)") {
                    HStack(spacing: 12) {
                        Text("Port")
                        TextField("Port", value: $model.socksPort, format: .number)
                            .frame(width: 80)
                            .disabled(model.socksRunning)
                        Spacer()
                        Text(model.socksRunning ? "Running on 127.0.0.1:\(model.socksPort)" : "Off")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(model.socksRunning ? "Stop proxy" : "Start proxy") { model.toggleSocks() }
                            .buttonStyle(.glass)
                        Button("Copy address") { model.copySocksAddress() }
                            .buttonStyle(.glass)
                            .disabled(!model.socksRunning)
                    }
                    Text("Apps set to use this proxy share every included connection, without the system-wide tunnel.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                section("Adapter weights") {
                    ForEach(model.rows) { row in
                        HStack(spacing: 12) {
                            Text(row.service)
                                .frame(width: 150, alignment: .leading)
                            Slider(value: Binding(
                                get: { model.weightsDraft[row.device] ?? row.weight ?? 1 },
                                set: { model.weightsDraft[row.device] = $0 }
                            ), in: 0.25...3, step: 0.25)
                            .disabled(model.weightingMode != "manual")
                            Text(String(format: "%.2f", model.weightsDraft[row.device] ?? row.weight ?? 1))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Save weights") { model.saveWeights() }
                            .buttonStyle(.glassProminent)
                            .tint(Brand.accent)
                    }
                    Text("Higher weight sends more flows over that link. Saved to /usr/local/var/linkblend/weights.conf.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                section("Adapters (engine view)") {
                    ForEach(model.rows) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(row.service) [\(row.device)]")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text(row.merged ? "in tunnel" : "not in tunnel")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Text("session down \(bytes(row.sessionIn)) · up \(bytes(row.sessionOut)) · peak \(rate(row.peakRate)) · failed flows \(row.failed) · IPv6 \(row.ipv6 ?? "—")")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                section("net-merge status and adapters") {
                    monoText(model.devDiagText.isEmpty ? "No output yet. Use Refresh diagnostics." : model.devDiagText)
                }

                section("Raw status (/var/run/net-merge/status.json)") {
                    monoText(model.devStatusText.isEmpty ? "Status file unavailable." : model.devStatusText)
                }

                section("Logs") {
                    monoText(model.devLogsText.isEmpty ? "No logs readable." : model.devLogsText)
                }
            }
            .padding(20)
        }
        .navigationTitle("Developer")
        .task { model.loadDevData() }
        .alert("Restart the merge engine?", isPresented: $confirmRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Restart", role: .destructive) { model.requestEngineRestart() }
        } message: {
            Text("Open connections drop for a few seconds while the tunnel comes back.")
        }
    }

    func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
        }
    }

    private func monoText(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 240)
    }
}
