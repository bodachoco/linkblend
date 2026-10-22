import SwiftUI

import AppKit
// MARK: - Menu bar panel

struct MenuBarContentView: View {
    @ObservedObject var model: LinkModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(model.statusColor).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(model.statusTitle)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(model.statusDetail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Label(rate(model.totalIn), systemImage: "arrow.down")
                Label(rate(model.totalOut), systemImage: "arrow.up")
            }
            .font(.system(size: 12, design: .monospaced))

            Divider()

            ForEach(model.rows) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.symbol)
                        .accessibilityHidden(true)
                    Text(row.service)
                    Spacer()
                    Toggle("Use \(row.service)", isOn: Binding(
                        get: { row.enabled },
                        set: { model.setLinked(row, linked: $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                .font(.system(size: 12))
                .opacity(row.present ? 1 : 0.55)
            }

            Divider()

            Toggle("Merge connections", isOn: Binding(
                get: { model.mergeEnabled },
                set: { model.setMerging($0) }
            ))
            .toggleStyle(.switch)

            HStack {
                Button("Open LinkBlend") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Settings…") { openSettings() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
    }
}
