import SwiftUI

// MARK: - A single connection

struct LinkRow: Identifiable, Equatable {
    var id: String { device }
    var device: String
    var service: String
    var hardware: String
    var enabled: Bool
    var present: Bool = true

    // topology
    var ip: String?
    var subnet: String?
    var gateway: String?
    var publicIP: String?

    // live
    var rtt: Double?
    var rateIn: Double = 0
    var rateOut: Double = 0
    var weight: Double?
    var failed: Int = 0
    var usedToday: Double = 0
    var merged: Bool = false
    var sessionIn: Double = 0
    var sessionOut: Double = 0
    var peakRate: Double = 0
    var ipv6: String?

    // duplicate detection, filled by the model
    var duplicateOf: String?

    var friendly: String {
        let hw = hardware.lowercased()
        if hw.contains("wi-fi") { return "Wi-Fi" }
        if hw.contains("iphone") { return "iPhone" }
        if hw.contains("android") || service.lowercased().contains("pixel") { return "Android" }
        return service
    }

    var symbol: String {
        let hw = hardware.lowercased()
        if hw.contains("wi-fi") { return "wifi" }
        if hw.contains("iphone") { return "iphone" }
        if hw.contains("android") || service.lowercased().contains("pixel") { return "smartphone" }
        return "cable.connector"
    }

    var isPresent: Bool { ip != nil }
    var usable: Bool { enabled && ip != nil && duplicateOf == nil }

    var qualityText: String {
        if !enabled { return "Off" }
        if duplicateOf != nil { return "Shared path" }
        guard ip != nil else { return "No address" }
        guard let rtt else { return "Checking…" }
        if rtt < 25 { return "Excellent" }
        if rtt < 60 { return "Good" }
        if rtt < 120 { return "Fair" }
        return "Weak"
    }

}
