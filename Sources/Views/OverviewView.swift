import SwiftUI
import Charts

import AppKit
// MARK: - Overview tab

struct OverviewView: View {
    @ObservedObject var model: LinkModel
    @State private var displayedLinkEvent: LinkEventMsg?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: model.mergeEnabled ? "arrow.triangle.branch" : "arrow.triangle.merge")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Brand.accent)
                            .contentTransition(.symbolEffect(.replace))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.statusTitle)
                                .font(.system(size: 22, weight: .semibold))
                                .contentTransition(.opacity)
                                .accessibilityAddTraits(.isHeader)
                            Text(model.statusDetail)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Text("Merge connections")
                                .font(.system(size: 13, weight: .medium))
                            Toggle("Merge connections", isOn: Binding(
                                get: { model.mergeEnabled },
                                set: { on in
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                        model.setMerging(on)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: model.statusTitle)

                    chartSlot

                    HStack(alignment: .top, spacing: 36) {
                        rateStack("Download", rate(model.totalIn), Brand.accent)
                        rateStack("Upload", rate(model.totalOut), Brand.teal)
                        Spacer()
                        if model.combinedPotential > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Potential")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(rate(model.combinedPotential))
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                ForEach(model.rows) { row in
                    ConnectionRow(model: model, row: row)
                }
                if model.rows.isEmpty {
                    Text("No connections found.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Connections")
                    Spacer()
                    Button("Test all") { model.testAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .textCase(nil)
                        .disabled(!model.rows.contains { $0.enabled && $0.ip != nil })
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Overview")
        .onChange(of: model.limitExceededService) { _, service in
            if let service {
                model.showToast("\(service) passed its daily data limit", isError: true)
            }
        }
        .onChange(of: model.linkEvent?.id) { _, _ in
            guard let event = model.linkEvent else {
                displayedLinkEvent = nil
                return
            }
            if reduceMotion {
                displayedLinkEvent = nil
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    model.advanceLinkEvent(after: event.id)
                }
                return
            }
            NSHapticFeedbackManager.defaultPerformer.perform(
                event.kind == .connected ? .alignment : .generic, performanceTime: .now)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                displayedLinkEvent = event
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_300_000_000)
                guard displayedLinkEvent?.id == event.id else { return }
                withAnimation(.easeOut(duration: 0.3)) { displayedLinkEvent = nil }
                model.advanceLinkEvent(after: event.id)
            }
        }
        .onAppear {
            if displayedLinkEvent == nil, let event = model.linkEvent {
                displayedLinkEvent = event
                Task {
                    try? await Task.sleep(nanoseconds: 2_300_000_000)
                    guard displayedLinkEvent?.id == event.id else { return }
                    displayedLinkEvent = nil
                    model.advanceLinkEvent(after: event.id)
                }
            }
        }
    }

    /// Fixed-height slot: the chart and the merge morph crossfade inside it,
    /// so the layout never moves when either appears.
    var chartSlot: some View {
        ZStack {
            VStack {
                Spacer()
                Divider()
            }
            .opacity(model.samples.count > 1 || displayedLinkEvent != nil ? 0 : 1)

            if let event = displayedLinkEvent {
                LinkMorphView(event: event)
                    .id(event.id)
                    .transition(.opacity)
            } else if model.samples.count > 1 {
                Chart {
                    ForEach(model.samples.suffix(90)) { sample in
                        AreaMark(
                            x: .value("Time", sample.date),
                            y: .value("Download (Mbps)", sample.down * 8 / 1_000_000)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(colors: [Brand.accent.opacity(0.32), Brand.accent.opacity(0.02)],
                                           startPoint: .top, endPoint: .bottom))
                        LineMark(
                            x: .value("Time", sample.date),
                            y: .value("Download (Mbps)", sample.down * 8 / 1_000_000)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Brand.accent)
                        LineMark(
                            x: .value("Time", sample.date),
                            y: .value("Upload (Mbps)", sample.up * 8 / 1_000_000)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Brand.teal)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .transition(.opacity)
                .accessibilityLabel("Live speed")
            }
        }
        .frame(height: 72)
        .clipped()
        .animation(.easeInOut(duration: 0.45), value: displayedLinkEvent?.id)
        .animation(.easeInOut(duration: 0.45), value: model.samples.count > 1)
    }

    func rateStack(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText())
        }
    }
}
