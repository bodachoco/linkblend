import SwiftUI

// MARK: - Connection list row

struct ConnectionRow: View {
    @ObservedObject var model: LinkModel
    var row: LinkRow

    var displayedState: String {
        if let stage = model.linkStages[row.device] {
            switch stage {
            case "enabling": return "Turning on…"
            case "waitingAddress": return "Getting an address…"
            case "waitingTunnel": return "Joining tunnel…"
            case "merged": return "In use"
            default: break
            }
        }
        let role = model.role(of: row.device)
        if role == "never" && row.present { return "Not used by engine" }
        let base = rowState(row)
        switch role {
        case "primary": return base + " · Primary"
        case "secondary": return base + " · Secondary"
        case "backup": return base + " · Backup"
        default: return base
        }
    }

    var stageIndex: Int? {
        guard let stage = model.linkStages[row.device] else { return nil }
        switch stage {
        case "enabling": return 0
        case "waitingAddress": return 1
        case "waitingTunnel": return 2
        case "merged": return 3
        default: return nil
        }
    }

    var enabled: Bool {
        model.rows.first(where: { $0.id == row.id })?.enabled ?? row.enabled
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(row.merged ? Color.green : (enabled ? Color.primary : Color.secondary))
                .frame(width: 28)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: row.merged)
                .animation(.easeInOut(duration: 0.3), value: row.merged)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.service)
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 6) {
                    Text(displayedState)
                        .font(.system(size: 12))
                        .foregroundStyle(row.merged ? Color.green : Color.secondary)
                    if let stageIndex {
                        HStack(spacing: 3) {
                            ForEach(0..<4, id: \.self) { dot in
                                Circle()
                                    .fill(dot <= stageIndex ? Brand.accent : Color.secondary.opacity(0.3))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .accessibilityLabel("Step \(stageIndex + 1) of 4")
                        if model.linkStages[row.device] != "merged" {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
            }

            Spacer()

            if row.merged {
                Text(rate(row.rateIn + row.rateOut))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 86, alignment: .trailing)
                    .contentTransition(.numericText())
            }

            if enabled && row.ip != nil {
                if model.testing.contains(row.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        model.runSpeedTest(row)
                    } label: {
                        Image(systemName: "gauge.with.needle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Test speed")
                }
                if let result = model.testResults[row.id] {
                    Text(rate(result))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 64, alignment: .trailing)
                }
            }

            ActionsMenuButton(model: model, row: row)
                .frame(width: 28, height: 22)
                .help("More actions for \(row.service)")

            Toggle("Use \(row.service)", isOn: Binding(
                get: { enabled },
                set: { linked in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        model.setLinked(row, linked: linked)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .help(row.present ? "" : "Connect \(row.service) first")
        }
        .padding(.vertical, 6)
        .opacity(!row.present ? 0.55 : (enabled ? 1 : 0.7))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: enabled)
    }
}
