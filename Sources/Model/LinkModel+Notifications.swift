import Foundation

// MARK: - User notifications

extension LinkModel {
    func notifyChanges() {
        let now = Set(rows.filter { $0.enabled && $0.ip != nil }.map { $0.device })
        if !lastSeen.isEmpty {
            if let d = now.subtracting(lastSeen).first,
               let row = rows.first(where: { $0.device == d }) {
                let usable = rows.filter { $0.usable }.count
                notify(title: "\(row.friendly) connected",
                       message: usable >= 2 ? "Merging \(usable) links"
                                            : "Single link; traffic stays on it")
            }
            if let d = lastSeen.subtracting(now).first {
                let name = rows.first(where: { $0.device == d })?.friendly ?? d
                let usable = rows.filter { $0.usable }.count
                notify(title: "\(name) disconnected",
                       message: usable >= 1 ? "\(usable) link\(usable == 1 ? "" : "s") still carrying traffic"
                                            : "No uplink left")
            }
        }
        lastSeen = now
    }

    func notify(title: String, message: String) {
        guard notificationsEnabled,
              FileManager.default.isExecutableFile(atPath: terminalNotifier) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            _ = self.run(self.terminalNotifier, ["-title", title, "-message", message,
                                                 "-group", "linkblend", "-sound", "Glass"])
        }
    }
}
