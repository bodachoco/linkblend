import SwiftUI

// MARK: - Transient UI events

struct RateSample: Identifiable {
    var id = UUID()
    var date: Date
    var down: Double
    var up: Double
}

struct ToastMsg: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var isError: Bool
}

struct MergePrompt: Identifiable {
    var id: String { device }
    var device: String
    var service: String
}

struct LinkEventMsg: Identifiable, Equatable {
    enum Kind: Equatable {
        case connected
        case disconnected
    }

    var id = UUID()
    var device: String
    var service: String
    var symbol: String
    var kind: Kind
}
