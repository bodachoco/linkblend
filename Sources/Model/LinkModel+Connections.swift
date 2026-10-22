import SwiftUI

// MARK: - Turn links on and off, merge control

extension LinkModel {
    /// Unlinking is refused when it would remove the last working path.
    func setLinked(_ row: LinkRow, linked: Bool) {
        if linked && !row.present {
            showToast("\(row.service) is not connected. Plug it in, then turn it on.", isError: true)
            return
        }
        if !linked {
            let remaining = rows.filter { $0.enabled && $0.ip != nil && $0.device != row.device }.count
            if remaining == 0 {
                showToast("\(row.service) stays on because it is the only link with an address.", isError: true)
                return
            }
        }
        pendingLinks[row.device] = linked
        if linked {
            linkStages[row.device] = "enabling"
            stageDeadlines[row.device] = Date().addingTimeInterval(35)
        }
        if let index = rows.firstIndex(where: { $0.id == row.id }) {
            rows[index].enabled = linked
        }
        markDuplicates()
        applyLink(row, linked: linked)
    }

    /// Pause keeps one link inside the tunnel instead of removing it, so open
    /// transfers and calls survive the switch.
    /// Pausing unlinks every link except the preferred one: net-merge keeps running
    /// with that single adapter, so the tunnel and its open connections stay up.
    /// Resuming relinks the set that was active before the pause.
    private func toggleMerging() {
        setMerging(pausedByUser)
    }

    func isPreferred(_ row: LinkRow) -> Bool {
        priority.first == row.device
    }

    private func refreshNow() {
        refreshServices()
        readStatus()
    }

    func setPreferred(device: String) {
        guard let row = rows.first(where: { $0.device == device }) else { return }
        makePrimary(row)
    }

    func setNotifications(_ on: Bool) {
        notificationsEnabled = on
        defaults.set(on, forKey: "notificationsEnabled")
    }

    func setMerging(_ on: Bool) {
        if on {
            let restore = defaults.stringArray(forKey: "pausedLinkSet") ?? []
            pausedByUser = false
            defaults.set(false, forKey: "pausedByUser")
            for row in rows where restore.contains(row.device) && !row.enabled {
                applyLink(row, linked: true)
            }
        } else {
            let active = rows.filter { $0.enabled }.map { $0.device }
            defaults.set(active, forKey: "pausedLinkSet")
            pausedByUser = true
            defaults.set(true, forKey: "pausedByUser")

            // Keep the preferred working link; unlink the rest.
            let primary = rows.first { $0.enabled && $0.ip != nil && $0.duplicateOf == nil }
            for row in rows where row.enabled && row.device != primary?.device {
                applyLink(row, linked: false)
            }
        }
        if on {
            scheduleAutoOff()
        } else {
            autoOffTask?.cancel()
        }
        syncConf()
    }

    /// Enable or disable a macOS network service. The interface disappears from
    /// net-merge's list within one rescan, without restarting the tunnel.
    private func applyLink(_ row: LinkRow, linked: Bool) {
        pendingLinks[row.device] = linked
        if let index = rows.firstIndex(where: { $0.id == row.id }) {
            rows[index].enabled = linked
        }
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.runCmd("/usr/sbin/networksetup",
                                     ["-setnetworkserviceenabled", row.service, linked ? "on" : "off"])
            let detail = [result?.stderr, result?.stdout]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? ""
            let failed = result == nil || result?.code != 0 || detail.lowercased().contains("error")
            DispatchQueue.main.async {
                self.pendingLinks[row.device] = nil
                if failed {
                    if linked {
                        self.linkStages[row.device] = nil
                        self.stageDeadlines[row.device] = nil
                    }
                    self.showToast("Could not \(linked ? "turn on" : "turn off") \(row.service). \(detail.isEmpty ? "networksetup failed." : detail)", isError: true)
                } else if linked && self.linkStages[row.device] == "enabling" {
                    self.linkStages[row.device] = "waitingAddress"
                }
                self.markDuplicates()
                self.syncConf()
                self.refreshServices()
            }
        }
    }

    func makePrimary(_ row: LinkRow) {
        var order = priority.filter { $0 != row.device }
        order.insert(row.device, at: 0)
        for r in rows where !order.contains(r.device) { order.append(r.device) }
        priority = order
        defaults.set(priority, forKey: "priority")
        rows = sortByPriority(rows)
        markDuplicates()
        syncConf()
    }

    func setAutoPrefer(_ on: Bool) {
        autoPrefer = on
        defaults.set(on, forKey: "autoPrefer")
    }

    func testAll() {
        for row in rows where row.enabled && row.ip != nil && row.duplicateOf == nil {
            runSpeedTest(row)
        }
    }

    func runSpeedTest(_ row: LinkRow) {
        guard !testing.contains(row.id) else { return }
        guard row.ip != nil else {
            showToast("\(row.service) has no address, so it cannot be tested.", isError: true)
            return
        }
        testing.insert(row.id)
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.runCmd("/usr/bin/curl", [
                "-s", "-o", "/dev/null", "-m", "12", "-w", "%{speed_download}",
                "--interface", row.device,
                "https://speed.cloudflare.com/__down?bytes=8000000"
            ])
            let bps = Double(result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
            DispatchQueue.main.async {
                self.testing.remove(row.id)
                if bps > 1000 {
                    self.testResults[row.id] = bps
                } else {
                    self.showToast("Speed test failed for \(row.service). The link did not return data.", isError: true)
                }
            }
        }
    }
}
