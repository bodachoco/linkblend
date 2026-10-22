import SwiftUI

// MARK: - Motion

/// Animation helpers that honour the system reduce-motion setting.
///
/// Every animation in the app goes through one of these, so a user who
/// turns on **Reduce Motion** gets state changes with no movement. Use
/// `motionAnimation(_:value:)` for the `.animation` modifier, and
/// `Motion.run(_:reduced:)` inside an action for `withAnimation`.
enum Motion {
    /// Runs an animated state change, or applies it immediately when the
    /// user asked for reduced motion.
    static func run(_ animation: Animation, reduced: Bool, _ body: () -> Void) {
        withAnimation(reduced ? nil : animation, body)
    }
}

private struct MotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Like `.animation(_:value:)`, but skipped when the system asks for
    /// reduced motion. Prefer this over the plain modifier in this app.
    func motionAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }

    /// Runs a symbol effect unless the system asks for reduced motion.
    func motionSymbolEffect(value: Bool) -> some View {
        modifier(MotionSymbolEffect(value: value))
    }
}

private struct MotionSymbolEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Bool

    func body(content: Content) -> some View {
        content.symbolEffect(.bounce, value: reduceMotion ? false : value)
    }
}
