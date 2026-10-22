import SwiftUI
import AppKit

// MARK: - Menu bar panel

struct MenuBarContentView: View {
    @ObservedObject var model: LinkModel
    @Environment(\.openWindow) private var openWindow
    // The panel is sized to its content, but it needs a floor so the
    // widest line is not clipped at large text sizes.
    @ScaledMetric(relativeTo: .body) private var panelWidth: Double = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(model.statusColor).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(model.statusTitle)
                    .font(.headline)
            }
            Text(model.statusDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Label(rate(model.totalIn), systemImage: "arrow.down")
                Label(rate(model.totalOut), systemImage: "arrow.up")
            }
            .font(.system(.callout, design: .monospaced))

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
                .font(.callout)
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
                Button("Settings…") {
                    // Settings lives in the main window now, so switch that
                    // window to the tab rather than opening a second one.
                    MainSection.settings.activate()
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: panelWidth)
    }
}
