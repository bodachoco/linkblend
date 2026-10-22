import Foundation
import AppKit

// MARK: - Per-app SOCKS5 proxy

extension LinkModel {
    func toggleSocks() {
        socksRunning ? stopSocks() : startSocks()
    }

    private func startSocks() {
        let include = rows.filter { !effectiveExcluded().contains($0.device) }.map { $0.device }
        guard !include.isEmpty else {
            showToast("No adapter is included in the engine.", isError: true)
            return
        }
        let stateDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LinkBlend/socks-state", isDirectory: true)
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

        var args = ["socks",
                    "-include", include.joined(separator: ","),
                    "-listen", "127.0.0.1:\(socksPort)",
                    "-state-dir", stateDir.path,
                    "-ipv6", ipv6Mode,
                    "-mtu", "\(mtu)"]
        if weightingMode == "manual" {
            for row in rows where !effectiveExcluded().contains(row.device) {
                args += ["-weight", "\(row.device)=\(weightsDraft[row.device] ?? row.weight ?? 1)"]
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: netMergeList)
        process.arguments = args
        // Discard the output: unread pipes fill up and block the proxy.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                self.socksProcess = nil
                self.socksRunning = false
                if proc.terminationStatus != 0 {
                    self.showToast("Per-app proxy stopped (exit \(proc.terminationStatus)).", isError: true)
                }
            }
        }
        do {
            try process.run()
            socksProcess = process
            socksRunning = true
            defaults.set(socksPort, forKey: "socksPort")
            showToast("Per-app proxy running on 127.0.0.1:\(socksPort)")
        } catch {
            showToast("Could not start the per-app proxy.", isError: true)
        }
    }

    func stopSocks() {
        socksProcess?.terminate()
        socksProcess = nil
        socksRunning = false
    }

    func copySocksAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("127.0.0.1:\(socksPort)", forType: .string)
        showToast("Proxy address copied")
    }
}
