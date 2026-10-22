import SwiftUI

// MARK: - New connection prompt

struct MergePromptSheet: View {
    @ObservedObject var model: LinkModel
    var prompt: MergePrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "iphone")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Brand.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Merge \(prompt.service)?")
                        .font(.system(size: 17, weight: .semibold))
                    Text(model.statusDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            Text("Merging uses \(prompt.service) together with your current connection. Nothing changes until you confirm.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Not now") { model.dismissMerge() }
                Button("Merge") { model.confirmMerge() }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
