import SwiftUI

// MARK: - Formatting helpers

func rate(_ bytesPerSecond: Double) -> String {
    let bits = bytesPerSecond * 8
    if bits >= 1_000_000_000 { return String(format: "%.1f Gbps", bits / 1_000_000_000) }
    if bits >= 1_000_000 { return String(format: "%.1f Mbps", bits / 1_000_000) }
    if bits >= 1_000 { return String(format: "%.0f kbps", bits / 1_000) }
    return "0 kbps"
}

func bytes(_ value: Double) -> String {
    if value >= 1_000_000_000 { return String(format: "%.2f GB", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.0f MB", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.0f KB", value / 1_000) }
    return "0 B"
}

func joinedList(_ items: [String]) -> String {
    switch items.count {
    case 0: return ""
    case 1: return items[0]
    case 2: return "\(items[0]) and \(items[1])"
    default:
        let head = items.dropLast().joined(separator: ", ")
        return "\(head), and \(items[items.count - 1])"
    }
}

func rowState(_ row: LinkRow) -> String {
    if !row.present { return "Not connected" }
    if row.duplicateOf != nil { return "Same route as another connection" }
    if !row.enabled { return "Off" }
    if row.ip == nil { return "No address yet" }
    return row.merged ? "In use" : "Connected"
}
