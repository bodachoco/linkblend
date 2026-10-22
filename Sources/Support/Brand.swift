import SwiftUI

// MARK: - Brand colours

enum Brand {
    static let accent = Color(red: 0.0, green: 0.32, blue: 0.78)
    static let teal = Color(red: 0.0, green: 0.55, blue: 0.55)
    static let gradient = LinearGradient(
        colors: [accent, teal], startPoint: .topLeading, endPoint: .bottomTrailing)
}
