import Foundation

// MARK: - Adapter discovery and reachability

extension LinkModel {
    func refreshServices() {
        queue.async { [weak self] in
            guard let self else { return }
            let services = self.detectServices()
            DispatchQueue.main.async {
                self.apply(services: services)
                self.markDuplicates()
                self.syncConf()
                self.notifyChanges()
            }
        }
    }

    /// Interfaces that exist on this Mac right now, read in-process so
    /// discovery does not spawn a tool just to answer presence.
    private func presentDevices() -> Set<String> {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(first) }
        var names = Set<String>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            names.insert(String(cString: current.pointee.ifa_name))
            cursor = current.pointee.ifa_next
        }
        return names
    }

    private func apply(services: [(service: String, hardware: String, device: String)]) {
        let present = presentDevices()
        var updated: [LinkRow] = []
        for s in services {
            let isPresent = present.contains(s.device)
            if var existing = rows.first(where: { $0.device == s.device }) {
                existing.service = s.service
                existing.hardware = s.hardware
                existing.present = isPresent
                existing.enabled = pendingLinks[s.device] ?? serviceEnabled(s.service)
                existing.ip = isPresent ? interfaceIP(s.device) : nil
                existing.subnet = isPresent ? interfaceSubnet(s.device) : nil
                existing.gateway = isPresent ? gateway(s.device) : nil
                existing.publicIP = publicCache[s.device]
                existing.usedToday = usage[dayKey()]?[s.device] ?? 0
                updated.append(existing)
            } else {
                updated.append(LinkRow(
                    device: s.device,
                    service: s.service,
                    hardware: s.hardware,
                    enabled: pendingLinks[s.device] ?? serviceEnabled(s.service),
                    present: isPresent,
                    ip: isPresent ? interfaceIP(s.device) : nil,
                    subnet: isPresent ? interfaceSubnet(s.device) : nil,
                    gateway: isPresent ? gateway(s.device) : nil,
                    publicIP: publicCache[s.device],
                    usedToday: usage[dayKey()]?[s.device] ?? 0))
            }
        }
        rows = sortByPriority(updated)
        detectLinkEvents()
        syncWeightsDraft()
        detectMergePrompts(updated: updated)
    }

    /// Two links that reach the internet through the same gateway or exit through the
    /// same public address share capacity, so merging them adds nothing. Mark the
    /// lower-priority one as a duplicate and leave it out of the merge set.
    func markDuplicates() {
        for i in rows.indices {
            rows[i].duplicateOf = nil
        }
        let live = rows.indices.filter { rows[$0].enabled && rows[$0].ip != nil }
        for i in live {
            guard rows[i].duplicateOf == nil else { continue }
            for j in live where j != i && rows[j].duplicateOf == nil {
                let sameGateway = rows[i].gateway != nil && rows[i].gateway == rows[j].gateway
                let sameSubnet = rows[i].subnet != nil && rows[i].subnet == rows[j].subnet
                let samePublic = rows[i].publicIP != nil && rows[i].publicIP == rows[j].publicIP
                guard sameGateway || sameSubnet || samePublic else { continue }
                if i < j {
                    rows[j].duplicateOf = rows[i].device
                } else {
                    rows[i].duplicateOf = rows[j].device
                }
            }
        }
    }

    private func detectServices() -> [(service: String, hardware: String, device: String)] {
        let out = run("/usr/sbin/networksetup", ["-listnetworkserviceorder"]) ?? ""
        var result: [(String, String, String)] = []
        let lines = out.components(separatedBy: .newlines)
        var name: String?
        for line in lines {
            if let r = line.range(of: #"^\((?:\d+|\*)\)\s+"#, options: .regularExpression) {
                name = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if let service = name, line.contains("Device:") {
                let device = line.components(separatedBy: "Device:").last?
                    .trimmingCharacters(in: CharacterSet(charactersIn: ") ")) ?? ""
                let hardware = line.components(separatedBy: "Hardware Port:").last?
                    .components(separatedBy: ", Device:").first?
                    .trimmingCharacters(in: .whitespaces) ?? service
                if device.hasPrefix("en") && !service.isEmpty && !hardware.contains("Thunderbolt Bridge") {
                    result.append((service, hardware, device))
                }
                name = nil
            }
        }
        return result
    }

    private func serviceEnabled(_ name: String) -> Bool {
        let out = run("/usr/sbin/networksetup", ["-getnetworkserviceenabled", name])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out != "Disabled"
    }

    private func interfaceIP(_ device: String) -> String? {
        let out = run("/usr/sbin/ipconfig", ["getifaddr", device])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let out, !out.isEmpty else { return nil }
        return out
    }

    private func gateway(_ device: String) -> String? {
        let out = run("/usr/sbin/ipconfig", ["getoption", device, "router"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let out, !out.isEmpty else { return nil }
        return out
    }

    private func interfaceSubnet(_ device: String) -> String? {
        guard let out = run("/usr/sbin/ifconfig", [device]) else { return nil }
        guard let range = out.range(of: #"inet (\d+\.\d+\.\d+\.\d+) netmask 0x([0-9a-f]+)"#,
                                    options: .regularExpression) else { return nil }
        let match = String(out[range])
        let parts = match.components(separatedBy: " ")
        guard parts.count >= 4, let mask = UInt32(parts[3].dropFirst(2), radix: 16),
              let ip = ipToUInt(parts[1]) else { return nil }
        let network = ip & mask
        return "\(network)/\(mask)"
    }

    private func ipToUInt(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    func refreshPublicIPs() {
        lastPublicCheck = Date()
        let devices = rows.filter { $0.enabled && $0.ip != nil }.map { $0.device }
        guard !devices.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            var found: [String: String] = [:]
            for device in devices {
                let out = self.run("/usr/bin/curl", [
                    "-s", "-m", "6", "--interface", device, "https://api.ipify.org"
                ])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !out.isEmpty, out.split(separator: ".").count == 4 { found[device] = out }
            }
            DispatchQueue.main.async {
                self.publicCache.merge(found) { _, new in new }
                for i in self.rows.indices {
                    self.rows[i].publicIP = self.publicCache[self.rows[i].device]
                }
                self.markDuplicates()
                self.syncConf()
            }
        }
    }

    func pingAll() {
        let targets = rows.filter { $0.enabled && $0.ip != nil }.map { $0.device }
        guard !targets.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            var results: [String: Double] = [:]
            for device in targets {
                guard let gw = self.gateway(device) else { continue }
                let out = self.run("/sbin/ping", ["-c", "1", "-W", "800", "-b", device, gw]) ?? ""
                if let r = out.range(of: #"time=([\d.]+)"#, options: .regularExpression) {
                    results[device] = Double(out[r].replacingOccurrences(of: "time=", with: ""))
                }
            }
            DispatchQueue.main.async {
                for i in self.rows.indices {
                    if let rtt = results[self.rows[i].device] { self.rows[i].rtt = rtt }
                }
                if self.autoPrefer,
                   let best = self.rows.filter({ $0.enabled && $0.ip != nil && $0.duplicateOf == nil && $0.rtt != nil })
                        .min(by: { ($0.rtt ?? 9999) < ($1.rtt ?? 9999) }),
                   self.priority.first != best.device {
                    self.makePrimary(best)
                }
            }
        }
    }
}
