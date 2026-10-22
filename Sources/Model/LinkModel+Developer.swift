import SwiftUI
import AppKit

// MARK: - Diagnostics and engine tuning

extension LinkModel {
    func loadDevData() {
        if let data = FileManager.default.contents(atPath: statusPath),
           let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                    options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            devStatusText = text
        }
        devLogsText = ["/var/log/linkblend.log", "/var/log/linkblend-run.log"].map { path in
            let body = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            return "== \(path) ==\n" + String(body.suffix(6000))
        }.joined(separator: "\n\n")
        queue.async { [weak self] in
            guard let self else { return }
            let status = self.run(self.netMergeList, ["status"]) ?? ""
            let list = self.run(self.netMergeList, ["list"]) ?? ""
            DispatchQueue.main.async {
                self.devDiagText = (status + "\n" + list)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    func copyDiagnostics() {
        var lines = [
            "LinkBlend diagnostics",
            "Date: \(Date())",
            statusTitle,
            statusDetail,
            "",
            "Connections:"
        ]
        for row in rows {
            let rtt = row.rtt.map { String(format: "%.0f ms", $0) } ?? "-"
            lines.append("- \(row.service) [\(row.device)] ip=\(row.ip ?? "-") gw=\(row.gateway ?? "-") " +
                         "rtt=\(rtt) merged=\(row.merged) quality=\(row.qualityText) " +
                         "usedToday=\(bytes(row.usedToday))")
        }
        lines += ["", "Status file:", devStatusText.isEmpty ? "(unavailable)" : devStatusText]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        showToast("Diagnostics copied")
    }

    func requestEngineRestart() {
        queue.async { [weak self] in
            guard let self else { return }
            _ = self.run(self.netMergeList, ["off"])
        }
    }

    func setAutoOff(_ minutes: Int) {
        autoOffMinutes = minutes
        defaults.set(minutes, forKey: "autoOffMinutes")
        if mergeEnabled {
            scheduleAutoOff()
        } else {
            autoOffTask?.cancel()
        }
    }

    func scheduleAutoOff() {
        autoOffTask?.cancel()
        guard autoOffMinutes > 0 else { return }
        let minutes = autoOffMinutes
        // The whole task runs on the main actor, so the timer only touches
        // published state from the same actor that renders it.
        autoOffTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled, let self, self.mergeEnabled else { return }
            self.setMerging(false)
            self.showToast("Merging turned off by timer")
        }
    }
}
