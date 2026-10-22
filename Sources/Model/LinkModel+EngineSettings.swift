import Foundation

// MARK: - Engine configuration files

extension LinkModel {
    /// Write the candidate list once. The supervisor starts net-merge with every
    /// candidate so that later plug/unplug needs no restart; linking and unlinking
    /// is done by disabling the macOS service, which leaves the tunnel intact.
    private func writeIfChanged(_ body: String, to path: String) {
        if let data = FileManager.default.contents(atPath: path),
           String(data: data, encoding: .utf8) == body {
            return
        }
        try? body.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func syncConf() {
        writeEngineSettings()
        let excluded = effectiveExcluded()
        writeIfChanged(excluded.sorted().joined(separator: "\n") + (excluded.isEmpty ? "" : "\n"),
                       to: "\(confDir)/excluded.conf")
        let candidates = rows.filter { !excluded.contains($0.device) }.map { $0.device }
        let body = candidates.joined(separator: "\n") + (candidates.isEmpty ? "" : "\n")
        writeIfChanged(body, to: "\(confDir)/candidates.conf")
        ensureSupervisor()
    }

    /// Make sure the root supervisor is running.
    ///
    /// The supervisor loops forever, so it is started detached with its
    /// output discarded rather than run and captured: a captured pipe never
    /// closes, which would wedge the shared work queue permanently.
    private func ensureSupervisor() {
        guard Date().timeIntervalSince(lastSupervisorCheck) > 25 else { return }
        lastSupervisorCheck = Date()
        queue.async { [weak self] in
            guard let self else { return }
            let running = self.run("/usr/bin/pgrep", ["-f", "linkblend-supervisor"])?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard running.isEmpty else { return }
            self.spawnDetached("/usr/bin/sudo", ["-n", self.supervisor, self.confDir])
        }
    }

    private func writeEngineSettings() {
        writeWeightsFile()
        writeIfChanged(ipv6Mode, to: "\(confDir)/ipv6")
        writeIfChanged("\(mtu)", to: "\(confDir)/mtu")
        writeIfChanged("\(rescanSec)", to: "\(confDir)/rescan")
        writeIfChanged(profilerOn ? "on" : "off", to: "\(confDir)/pprof")
    }

    func role(of device: String) -> String {
        roles[device] ?? "balanced"
    }

    func setRole(device: String, role: String) {
        let before = effectiveExcluded()
        roles[device] = role
        defaults.set(roles, forKey: "roles")
        writeWeightsFile()
        syncConf()
        if effectiveExcluded() != before {
            requestEngineRestart()
            showToast("Engine restarting to apply the change")
        }
    }

    func setProfiler(_ on: Bool) {
        profilerOn = on
        defaults.set(on, forKey: "profilerOn")
        writeEngineSettings()
    }

    func effectiveExcluded() -> Set<String> {
        var excluded = engineExcluded
        for row in rows where role(of: row.device) == "never" {
            excluded.insert(row.device)
        }
        return excluded
    }

    /// Writes weightmode + weights.conf from weighting mode and roles.
    /// Passing any fixed weight disables net-merge auto-weighting, so fixed
    /// weights are written only when something actually needs them.
    func writeWeightsFile() {
        let excluded = effectiveExcluded()
        let included = rows.filter { !excluded.contains($0.device) }
        let anyRole = included.contains { role(of: $0.device) != "balanced" }
        let manual = weightingMode == "manual" || anyRole
        writeIfChanged(manual ? "manual" : "auto", to: "\(confDir)/weightmode")
        guard manual else {
            writeIfChanged("", to: "\(confDir)/weights.conf")
            return
        }
        let lines = included.map { row -> String in
            let value: Double
            switch role(of: row.device) {
            case "primary": value = 10
            case "secondary": value = 0.3
            case "backup": value = 0.05
            default: value = weightsDraft[row.device] ?? row.weight ?? 1
            }
            return "\(row.device)=\(String(format: "%.2f", value))"
        }
        writeIfChanged(lines.joined(separator: "\n") + "\n", to: "\(confDir)/weights.conf")
    }

    func setWeightingMode(_ mode: String) {
        weightingMode = mode
        defaults.set(mode, forKey: "weightingMode")
        writeEngineSettings()
    }

    func setIPv6Mode(_ mode: String) {
        ipv6Mode = mode
        defaults.set(mode, forKey: "ipv6Mode")
        writeEngineSettings()
    }

    func setMTU(_ value: Int) {
        mtu = value
        defaults.set(value, forKey: "mtu")
        writeEngineSettings()
    }

    func setRescan(_ seconds: Int) {
        rescanSec = seconds
        defaults.set(seconds, forKey: "rescanSec")
        writeEngineSettings()
    }

    func setEngineIncluded(device: String, included: Bool) {
        let before = effectiveExcluded()
        if included {
            engineExcluded.remove(device)
        } else {
            engineExcluded.insert(device)
        }
        defaults.set(Array(engineExcluded), forKey: "engineExcluded")
        syncConf()
        if effectiveExcluded() != before {
            requestEngineRestart()
            showToast("Engine restarting to apply the change")
        }
    }

    func applyEngineSettings() {
        writeEngineSettings()
        syncConf()
        requestEngineRestart()
        showToast("Engine restarting with new settings")
    }
}
