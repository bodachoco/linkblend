import SwiftUI

// MARK: - Join stages, ordering, link events

extension LinkModel {
    /// When a new adapter appears while merging is on, offer to merge it.
    /// The first scan only records what is already plugged in.
    func detectMergePrompts(updated: [LinkRow]) {
        let presentNow = Set(updated.filter { $0.present }.map { $0.device })
        if !knownPresent.isEmpty {
            for device in presentNow.subtracting(knownPresent) {
                guard mergeEnabled,
                      mergePrompt == nil,
                      !dismissedPrompts.contains(device),
                      let row = updated.first(where: { $0.device == device }),
                      !row.merged else { continue }
                mergePrompt = MergePrompt(device: device, service: row.service)
                notify(title: "\(row.service) connected",
                       message: "Open LinkBlend to merge it with your current connection")
            }
        }
        for device in knownPresent.subtracting(presentNow) {
            dismissedPrompts.remove(device)
        }
        knownPresent = presentNow
    }

    func confirmMerge() {
        guard let prompt = mergePrompt else { return }
        dismissedPrompts.insert(prompt.device)
        mergePrompt = nil
        guard let row = rows.first(where: { $0.device == prompt.device }) else { return }
        if !row.enabled {
            setLinked(row, linked: true)
        } else {
            beginStage(row)
        }
    }

    func dismissMerge() {
        if let prompt = mergePrompt {
            dismissedPrompts.insert(prompt.device)
        }
        mergePrompt = nil
    }

    func beginStage(_ row: LinkRow) {
        guard linkStages[row.device] == nil else { return }
        linkStages[row.device] = row.ip == nil ? "waitingAddress" : "waitingTunnel"
        stageDeadlines[row.device] = Date().addingTimeInterval(35)
    }

    /// Stages are derived from live row state every second, so a Wi-Fi
    /// drop and reconnect shows Getting an address, then Joining the
    /// tunnel, then In use, with no app action involved.
    func updateStages() {
        for row in rows {
            let device = row.device
            let stage = linkStages[device]

            if stage == "enabling" {
                if row.enabled {
                    linkStages[device] = "waitingAddress"
                    stageDeadlines[device] = Date().addingTimeInterval(35)
                }
                continue
            }

            let desired: String?
            if !row.present || !row.enabled {
                desired = nil
            } else if row.merged {
                desired = "merged"
            } else if row.ip == nil {
                desired = "waitingAddress"
            } else if mergeEnabled {
                desired = "waitingTunnel"
            } else {
                desired = nil
            }

            if desired != stage {
                if desired == "merged", stage == "waitingAddress" || stage == "waitingTunnel" {
                    showToast("\(row.service) merged")
                }
                linkStages[device] = desired
                switch desired {
                case "waitingAddress":
                    stageDeadlines[device] = Date().addingTimeInterval(35)
                case "waitingTunnel":
                    stageDeadlines[device] = Date().addingTimeInterval(25)
                default:
                    stageDeadlines[device] = nil
                }
                continue
            }

            if stage == "waitingAddress" || stage == "waitingTunnel",
               let deadline = stageDeadlines[device], Date() > deadline {
                stageDeadlines[device] = .distantFuture
                if row.ip == nil {
                    showToast("\(row.service) got no address. Unlock the device, tap Trust, and turn on USB tethering or Personal Hotspot.", isError: true)
                } else {
                    showToast("\(row.service) did not join the tunnel. Open Developer to check the engine.", isError: true)
                }
            }
        }
        for device in Array(linkStages.keys) where !rows.contains(where: { $0.device == device }) {
            linkStages[device] = nil
            stageDeadlines[device] = nil
        }
    }

    /// A connection counts as active when it is in the tunnel, or when it
    /// is present, switched on, and has an address. Changes drive the
    /// link/unlink animation; the first seconds after launch only record
    /// the starting set so startup does not replay existing connections.
    func detectLinkEvents() {
        for row in rows { lastKnownRows[row.device] = row }
        let active = Set(rows.filter {
            $0.merged || ($0.present && $0.enabled && $0.ip != nil)
        }.map(\.device))

        guard let previous = previousActiveDevices else {
            previousActiveDevices = active
            return
        }
        previousActiveDevices = active
        guard Date().timeIntervalSince(launchedAt) > 4, active != previous else { return }

        for device in active.subtracting(previous) {
            guard let row = lastKnownRows[device] else { continue }
            enqueueLinkEvent(LinkEventMsg(device: device, service: row.service,
                                          symbol: row.symbol, kind: .connected), for: device)
        }
        for device in previous.subtracting(active) {
            guard let row = lastKnownRows[device] else { continue }
            enqueueLinkEvent(LinkEventMsg(device: device, service: row.service,
                                          symbol: row.symbol, kind: .disconnected), for: device)
        }
    }

    func enqueueLinkEvent(_ event: LinkEventMsg, for device: String) {
        let key = "\(device):\(event.kind == .connected ? "up" : "down")"
        let now = Date()
        if let last = lastLinkEventAt[key], now.timeIntervalSince(last) < 3 { return }
        lastLinkEventAt[key] = now
        if linkEvent == nil {
            linkEvent = event
        } else {
            linkEventQueue.append(event)
        }
    }

    func advanceLinkEvent(after id: UUID) {
        guard linkEvent?.id == id else { return }
        linkEvent = linkEventQueue.isEmpty ? nil : linkEventQueue.removeFirst()
    }

    /// Active connections float to the top: in the tunnel first, then
    /// connected, then off, then not connected. When a device drops, the
    /// ones still carrying traffic move up on the next status tick.
    func activeRank(_ row: LinkRow) -> Int {
        if row.merged { return 0 }
        if !row.present { return 3 }
        if row.enabled && row.ip != nil { return 1 }
        return 2
    }

    func sortByPriority(_ input: [LinkRow]) -> [LinkRow] {
        input.sorted { a, b in
            let ra = activeRank(a)
            let rb = activeRank(b)
            if ra != rb { return ra < rb }
            let ia = priority.firstIndex(of: a.device) ?? Int.max
            let ib = priority.firstIndex(of: b.device) ?? Int.max
            if ia != ib { return ia < ib }
            return a.device < b.device
        }
    }
}
