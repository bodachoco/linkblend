import SwiftUI

// MARK: - Main window

enum MainSection: String, Hashable {
    case overview
    case activity
    case developer
    case settings

    /// Switches the main window to this tab. The selection is stored in
    /// `UserDefaults` under the same key `ContentView` reads, so the menu
    /// bar can request a tab without sharing view state.
    func activate() {
        UserDefaults.standard.set(rawValue, forKey: "mainSection")
    }
}

struct ContentView: View {
    @ObservedObject var model: LinkModel
    /// Shared with the menu bar so its Settings button can switch tabs here.
    @AppStorage("mainSection") private var selection: MainSection = .overview
    @AppStorage("developerMode") private var developerMode = false
    @Namespace private var tabSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(.title3, weight: .bold))
                            .foregroundStyle(Brand.accent)
                            .accessibilityHidden(true)
                        Text("LinkBlend")
                            .font(.system(.title3, weight: .semibold))
                    }
                    Spacer()
                }

                HStack(spacing: 4) {
                    tabButton(.overview, "Overview", "gauge.with.dots.needle.33percent")
                    tabButton(.activity, "Activity", "chart.line.uptrend.xyaxis")
                    if developerMode {
                        tabButton(.developer, "Developer", "hammer")
                    }
                    tabButton(.settings, "Settings", "gearshape")
                }
                .padding(4)
                .glassEffect(.regular, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Group {
                switch currentSection {
                case .overview:
                    OverviewView(model: model)
                case .activity:
                    ActivityView(model: model)
                case .developer:
                    DeveloperView(model: model)
                case .settings:
                    SettingsView(model: model)
                }
            }
            .transition(.opacity)
            .motionAnimation(.easeInOut(duration: 0.2), value: currentSection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 540, idealHeight: 640)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                HStack(spacing: 8) {
                    Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    Text(toast.text)
                        .font(.system(.body, weight: .medium))
                }
                .foregroundStyle(toast.isError ? Color.red : Color.green)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint((toast.isError ? Color.red : Color.green).opacity(0.16)),
                             in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .motionAnimation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast?.id)
        .sheet(item: $model.mergePrompt) { prompt in
            MergePromptSheet(model: model, prompt: prompt)
        }
    }

    private var currentSection: MainSection {
        if selection == .developer && !developerMode { return .overview }
        return selection
    }
    private func tabButton(_ section: MainSection, _ title: String, _ symbol: String) -> some View {
        Button {
            Motion.run(.spring(response: 0.38, dampingFraction: 0.82), reduced: reduceMotion) {
                selection = section
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(.body, weight: .medium))
            .foregroundStyle(selection == section ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if selection == section {
                    Capsule()
                        .fill(Color.primary.opacity(0.13))
                        .matchedGeometryEffect(id: "tabPill", in: tabSpace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
    }
}
