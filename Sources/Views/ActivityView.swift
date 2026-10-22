import SwiftUI
import Charts

// MARK: - Activity tab

struct ActivityView: View {
    @ObservedObject var model: LinkModel
    @State private var exported = false

    var body: some View {
        List {
            Section("Live throughput") {
                if model.samples.count > 1 {
                    Chart {
                        ForEach(model.samples) { sample in
                            LineMark(
                                x: .value("Time", sample.date),
                                y: .value("Download (Mbps)", sample.down * 8 / 1_000_000),
                                series: .value("Series", "Download")
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Brand.accent)
                            LineMark(
                                x: .value("Time", sample.date),
                                y: .value("Upload (Mbps)", sample.up * 8 / 1_000_000),
                                series: .value("Series", "Upload")
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Brand.teal)
                        }
                    }
                    .frame(height: 170)
                    .accessibilityLabel("Throughput for the last ten minutes")
                    HStack(spacing: 16) {
                        Label("Download", systemImage: "circle.fill")
                            .foregroundStyle(Brand.accent)
                        Label("Upload", systemImage: "circle.fill")
                            .foregroundStyle(Brand.teal)
                    }
                    .font(.system(size: 11))
                } else {
                    Text("Collecting samples. Rates appear here within a few seconds.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if model.usageHistory.isEmpty {
                    Text("No usage recorded yet. Usage is counted while links are in the tunnel.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.usageHistory, id: \.day) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.day)
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text(bytes(entry.total))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                            }
                            Text(entry.devices.sorted(by: { $0.key < $1.key })
                                .map { "\($0.key) \(bytes($0.value))" }
                                .joined(separator: "  ·  "))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                HStack {
                    Text("Last 30 days")
                    Spacer()
                    Button(exported ? "Copied" : "Copy CSV") {
                        model.copyUsageCSV()
                        exported = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .textCase(nil)
                    .disabled(model.usageHistory.isEmpty)
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Activity")
    }
}
