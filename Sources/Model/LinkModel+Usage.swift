import SwiftUI

import AppKit
// MARK: - Status text, rates, usage history

extension LinkModel {
    var mergeEnabled: Bool { !pausedByUser }

    var statusTitle: String {
        if !mergeEnabled { return "Merging off" }
        if tunnelCount >= 2 { return "Merged" }
        if tunnelCount == 1 { return "Not merged" }
        return "No connection"
    }

    var statusDetail: String {
        let carrying = rows.filter { $0.merged }.map(\.service)
        if !mergeEnabled {
            let kept = rows.first { $0.enabled && $0.ip != nil }?.service ?? "One connection"
            return "\(kept) is in use."
        }
        if tunnelCount >= 2 { return "\(joinedList(carrying)) are sharing traffic." }
        if tunnelCount == 1 {
            return "\(carrying.first ?? "One connection") is in use. Turn on another connection to merge."
        }
        return "Turn on a connection to get started."
    }

    var statusColor: Color {
        if !mergeEnabled { return .secondary }
        if tunnelCount >= 2 { return .green }
        if tunnelCount == 1 { return .orange }
        return .red
    }

    var preferredDevice: String {
        priority.first ?? rows.first?.device ?? ""
    }

    func clearUsage() {
        usage = [:]
        lastBytes = [:]
        for i in rows.indices { rows[i].usedToday = 0 }
        saveUsage()
    }

    func setDataLimit(device: String, bytesLimit: Double) {
        if bytesLimit <= 0 {
            dataLimits[device] = nil
        } else {
            dataLimits[device] = bytesLimit
        }
        defaults.set(dataLimits, forKey: "dataLimits")
    }

    var limitExceededService: String? {
        rows.first { row in
            guard let limit = dataLimits[row.device], limit > 0 else { return false }
            return row.usedToday >= limit
        }?.service
    }

    /// Sum of the latest per-link speed tests, shown once at least two
    /// merged links have been tested.
    var combinedPotential: Double {
        let tested = rows.filter { $0.merged }.compactMap { testResults[$0.device] }
        guard tested.count >= 2 else { return 0 }
        return tested.reduce(0, +)
    }

    func copyUsageCSV() {
        var lines = ["day,device,bytes"]
        for day in usage.keys.sorted() {
            for (device, value) in (usage[day] ?? [:]).sorted(by: { $0.key < $1.key }) {
                lines.append("\(day),\(device),\(Int(value))")
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    var usageHistory: [(day: String, total: Double, devices: [String: Double])] {
        usage.keys.sorted(by: >).map { day in
            let devices = usage[day] ?? [:]
            return (day: day, total: devices.values.reduce(0, +), devices: devices)
        }
    }

    func syncWeightsDraft() {
        for row in rows where weightsDraft[row.device] == nil {
            weightsDraft[row.device] = row.weight ?? 1
        }
    }

    func saveWeights() {
        writeWeightsFile()
    }

    func loadUsage() {
        guard let data = try? Data(contentsOf: usageURL),
              let decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data)
        else { return }
        usage = decoded
    }

    func saveUsage() {
        let cutoff = Self.dayFormatter.string(from: Date().addingTimeInterval(-29 * 86400))
        usage = usage.filter { $0.key >= cutoff }
        if let data = try? JSONEncoder().encode(usage) {
            try? data.write(to: usageURL)
        }
    }

    func previousDayKey() -> String {
        Self.dayFormatter.string(from: Date().addingTimeInterval(-86400))
    }
}
