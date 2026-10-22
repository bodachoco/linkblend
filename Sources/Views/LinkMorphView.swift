import SwiftUI

// MARK: - Link and unlink animation

/// Link/unlink animation: this Mac and the device that changed move
/// together (or apart), the line between them joins (or splits in the
/// middle), and the center badge ends as a checkmark or an X. The right
/// endpoint uses the icon that matches the connection: Wi-Fi, iPhone,
/// phone, or Ethernet cable.
struct LinkMorphView: View {
    var event: LinkEventMsg

    @State private var progress: CGFloat
    @State private var packet: CGFloat = 0
    @State private var completed = false
    @State private var ringScale: CGFloat = 0.6
    @State private var ringOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(event: LinkEventMsg) {
        self.event = event
        _progress = State(initialValue: event.kind == .connected ? 0 : 1)
    }

    private var isConnected: Bool { event.kind == .connected }
    private var deviceSymbol: String {
        event.symbol == "cable.connector" ? "cable.connector.horizontal" : event.symbol
    }
    /// Distance from center to each endpoint: wide apart at progress 0,
    /// close together at progress 1.
    private var reach: CGFloat { 40 + (1 - progress) * 46 }
    private var segmentWidth: CGFloat { max(0, reach - 34) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // Two line segments, so a disconnect visibly splits
                // in the middle instead of fading out.
                Capsule()
                    .fill(Brand.accent.opacity(0.25 + 0.65 * Double(progress)))
                    .frame(width: segmentWidth, height: 3)
                    .offset(x: -(13 + segmentWidth / 2))
                Capsule()
                    .fill(Brand.teal.opacity(0.25 + 0.65 * Double(progress)))
                    .frame(width: segmentWidth, height: 3)
                    .offset(x: 13 + segmentWidth / 2)

                if isConnected && !completed {
                    Circle()
                        .fill(Brand.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: -reach + 24 + (reach * 2 - 48) * packet)
                }

                Circle()
                    .stroke((isConnected ? Brand.accent : Color.orange).opacity(ringOpacity),
                            lineWidth: 2)
                    .frame(width: 30, height: 30)
                    .scaleEffect(ringScale)

                endpoint("laptopcomputer", tint: .primary)
                    .offset(x: -reach)
                endpoint(deviceSymbol,
                         tint: isConnected || progress > 0.5 ? Brand.teal : Color.secondary)
                    .opacity(isConnected ? 1 : 0.55 + 0.45 * Double(progress))
                    .offset(x: reach)

                ZStack {
                    Circle().fill(completed
                        ? (isConnected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.orange))
                        : AnyShapeStyle(Color.secondary.opacity(0.85)))
                    Image(systemName: completed ? (isConnected ? "checkmark" : "xmark") : "link")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 26, height: 26)
                .scaleEffect(completed ? 1.15 : 1)
                .rotationEffect(.degrees(isConnected ? 0 : (1.0 - Double(progress)) * -24))
                .opacity(isConnected ? Double(progress) : (completed ? 1 : 0.4 + 0.6 * Double(progress)))
            }
            .frame(width: 250, height: 44)

            Text(isConnected ? "\(event.service) linked" : "\(event.service) disconnected")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .frame(height: 72)
        .accessibilityHidden(true)
        .onAppear(perform: run)
    }

    private func endpoint(_ symbol: String, tint: Color) -> some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.08))
            Image(systemName: symbol)
                .font(.system(.title3, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: 40, height: 40)
    }

    func run() {
        // With reduced motion, jump straight to the end state: the view is
        // decorative and already hidden from assistive technology, so the
        // outcome matters and the travel does not.
        if reduceMotion {
            progress = isConnected ? 1 : 0
            packet = isConnected ? 1 : 0
            completed = true
            ringOpacity = 0
            return
        }
        if isConnected {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.68)) { progress = 1 }
            withAnimation(.easeInOut(duration: 0.75)) { packet = 1 }
            ringOpacity = 0.7
            withAnimation(.easeOut(duration: 1.0)) {
                ringScale = 2.0
                ringOpacity = 0
            }
        } else {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.8)) { progress = 0 }
        }
        Task {
            try? await Task.sleep(nanoseconds: 780_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { completed = true }
            if !isConnected {
                ringOpacity = 0.6
                withAnimation(.easeOut(duration: 0.8)) {
                    ringScale = 1.9
                    ringOpacity = 0
                }
            }
        }
    }
}
