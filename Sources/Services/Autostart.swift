import Foundation

// MARK: - Login item

enum Autostart {
    static let label = "local.linkblend"
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var isOn: Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let printed = shellOut("/bin/launchctl", ["print-disabled", "gui/\(getuid())"])
        return !printed.contains("\"\(label)\" => disabled")
    }

    static func set(_ on: Bool) {
        let domain = "gui/\(getuid())"
        _ = shell("/bin/launchctl", ["bootout", domain, url.path])
        if on {
            let exe = "/Applications/LinkBlend.app/Contents/MacOS/LinkBlend"
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [exe],
                "RunAtLoad": true,
                "ProcessType": "Interactive"
            ]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url)
            }
            _ = shell("/bin/launchctl", ["enable", "\(domain)/\(label)"])
            _ = shell("/bin/launchctl", ["bootstrap", domain, url.path])
        } else {
            _ = shell("/bin/launchctl", ["disable", "\(domain)/\(label)"])
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func shellOut(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try? p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    @discardableResult
    static func shell(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
