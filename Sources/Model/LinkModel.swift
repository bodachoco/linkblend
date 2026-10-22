import SwiftUI
import Foundation

// MARK: - Engine state and the polling loop

final class LinkModel: ObservableObject {
    @Published var rows: [LinkRow] = []
    @Published var merging = false
    @Published var pausedByUser = false
    @Published var totalIn: Double = 0
    @Published var totalOut: Double = 0
    @Published var testing: Set<String> = []
    @Published var testResults: [String: Double] = [:]
    @Published var toast: ToastMsg?
    @Published var tunnelCount: Int = 0
    @Published var notificationsEnabled = true
    @Published var samples: [RateSample] = []
    @Published var autoPrefer = false
    @Published var weightsDraft: [String: Double] = [:]
    @Published var statusPID: Int?
    @Published var statusMode: String?
    @Published var statusUpdated: String?
    @Published var devStatusText = ""
    @Published var devDiagText = ""
    @Published var devLogsText = ""
    @Published var dataLimits: [String: Double] = [:]
    @Published var weightingMode = "auto"
    @Published var ipv6Mode = "auto"
    @Published var mtu = 1500
    @Published var rescanSec = 3
    @Published var autoOffMinutes = 0
    @Published var engineExcluded: Set<String> = []
    @Published var socksRunning = false
    @Published var socksPort = 1080
    @Published var roles: [String: String] = [:]
    @Published var profilerOn = false
    @Published var linkEvent: LinkEventMsg?
    @Published var mergePrompt: MergePrompt?
    @Published var linkStages: [String: String] = [:]

    let statusPath = "/var/run/net-merge/status.json"
    let netMergeList = "/opt/homebrew/bin/net-merge"
    let supervisor = "/usr/local/bin/linkblend-supervisor"
    let confDir = "/usr/local/var/linkblend"
    let terminalNotifier = "/opt/homebrew/bin/terminal-notifier"

    private var timer: Timer?
    private var ticks = 0
    var lastSeen: Set<String> = []
    var lastBytes: [String: Double] = [:]
    var usage: [String: [String: Double]] = [:]
    let usageURL: URL
    let defaults = UserDefaults.standard
    let queue = DispatchQueue(label: "linkblend.work", qos: .utility)
    var priority: [String] = []
    var lastPublicCheck = Date.distantPast
    var publicCache: [String: String] = [:]
    var pendingLinks: [String: Bool] = [:]
    var lastSupervisorCheck = Date.distantPast
    private var limitNotified: Set<String> = []
    /// While a connection action popover is open, live updates pause so the
    /// popover cannot flicker or lose selection mid-tap.
    var interactionHold = false
    private var toastDismissWork: DispatchWorkItem?
    var autoOffTask: Task<Void, Never>?
    var socksProcess: Process?
    var previousActiveDevices: Set<String>?
    var lastKnownRows: [String: LinkRow] = [:]
    var lastLinkEventAt: [String: Date] = [:]
    var linkEventQueue: [LinkEventMsg] = []
    let launchedAt = Date()
    var stageDeadlines: [String: Date] = [:]
    var knownPresent: Set<String> = []
    var dismissedPrompts: Set<String> = []

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LinkBlend", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        usageURL = base.appendingPathComponent("usage.json")
        loadUsage()
        pausedByUser = defaults.bool(forKey: "pausedByUser")
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        autoPrefer = defaults.bool(forKey: "autoPrefer")
        dataLimits = (defaults.dictionary(forKey: "dataLimits") as? [String: Double]) ?? [:]
        weightingMode = defaults.string(forKey: "weightingMode") ?? "auto"
        ipv6Mode = defaults.string(forKey: "ipv6Mode") ?? "auto"
        // 9000 was the old default. A 9000-byte tunnel over 1500-byte
        // links stalls large transfers (images, files, feed prefetch),
        // so migrate the old default to 1500. An explicit 1500/4096/9000
        // choice in Developer is still honored.
        let storedMTU = defaults.object(forKey: "mtu") as? Int
        if storedMTU == 9000 {
            mtu = 1500
            defaults.set(1500, forKey: "mtu")
        } else {
            mtu = storedMTU ?? 1500
        }
        rescanSec = (defaults.object(forKey: "rescanSec") as? Int) ?? 1
        autoOffMinutes = defaults.integer(forKey: "autoOffMinutes")
        engineExcluded = Set(defaults.stringArray(forKey: "engineExcluded") ?? [])
        socksPort = (defaults.object(forKey: "socksPort") as? Int) ?? 1080
        roles = (defaults.dictionary(forKey: "roles") as? [String: String]) ?? [:]
        profilerOn = defaults.bool(forKey: "profilerOn")
        priority = defaults.stringArray(forKey: "priority") ?? []
        refreshServices()
        readStatus()
        NotificationCenter.default.addObserver(
            forName: .linkBlendWillTerminate, object: nil, queue: .main) { [weak self] _ in
            self?.stopSocks()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    // MARK: polling

    // Status is a small file read, so it stays at 1 Hz for live rates. Service
    // discovery spawns several system tools per link, so it runs far less
    // often; links still appear within one discovery pass after a change.
    func tick() {
        guard !interactionHold else { return }
        ticks += 1
        readStatus()
        updateStages()
        // While a link is joining, poll discovery every 2 s so the UI tracks
        // it live; otherwise every 15 s is enough.
        let joining = linkStages.values.contains { $0 != "merged" }
        if joining ? (ticks % 2 == 0) : (ticks % 15 == 0) { refreshServices() }
        if ticks % 10 == 0 { pingAll() }
        if ticks % 60 == 0 { saveUsage() }
        if Date().timeIntervalSince(lastPublicCheck) > 300 && ticks % 10 == 0 {
            refreshPublicIPs()
        }
        if ticks % 6 == 0 { syncConf() }
    }

    func readStatus() {
        guard let data = FileManager.default.contents(atPath: statusPath),
              let status = try? JSONDecoder().decode(NMStatus.self, from: data) else {
            merging = false
            tunnelCount = 0
            totalIn = 0
            totalOut = 0
            var cleared = rows
            for i in cleared.indices {
                cleared[i].rateIn = 0
                cleared[i].rateOut = 0
                cleared[i].merged = false
            }
            if cleared != rows { rows = cleared }
            detectLinkEvents()
            return
        }
        // The status file is written once a second by a root-owned process, so
        // liveness comes from its modification time. Checking the PID with
        // kill(pid, 0) fails with EPERM for a process owned by root.
        let modified = (try? FileManager.default.attributesOfItem(atPath: statusPath))?[.modificationDate] as? Date
        let fresh = modified.map { Date().timeIntervalSince($0) < 5 } ?? false
        merging = fresh && !status.NICs.isEmpty
        tunnelCount = fresh ? status.NICs.count : 0
        statusPID = status.PID
        statusMode = status.Mode
        statusUpdated = status.Updated
        var tin = 0.0, tout = 0.0
        for i in rows.indices {
            if let nic = status.NICs.first(where: { $0.Name == rows[i].device }) {
                rows[i].merged = true
                rows[i].rateIn = nic.RateIn ?? 0
                rows[i].rateOut = nic.RateOut ?? 0
                rows[i].weight = nic.Weight
                rows[i].failed = nic.Failed ?? 0
                rows[i].sessionIn = nic.BytesIn ?? 0
                rows[i].sessionOut = nic.BytesOut ?? 0
                rows[i].peakRate = nic.Peak ?? 0
                rows[i].ipv6 = (nic.IP6?.isEmpty == false) ? nic.IP6 : nil
                if let bytes = nic.BytesIn { addUsage(device: rows[i].device, bytes: bytes) }
                tin += rows[i].rateIn
                tout += rows[i].rateOut
            } else if !status.NICs.isEmpty {
                rows[i].merged = false
                rows[i].rateIn = 0
                rows[i].rateOut = 0
            }
        }
        totalIn = tin
        totalOut = tout
        detectLinkEvents()
        let reordered = sortByPriority(rows)
        if reordered.map(\.device) != rows.map(\.device) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                rows = reordered
            }
        }
        if fresh {
            let now = Date()
            if samples.last.map({ now.timeIntervalSince($0.date) >= 1.9 }) ?? true {
                samples.append(RateSample(date: now, down: tin, up: tout))
                if samples.count > 300 { samples.removeFirst(samples.count - 300) }
            }
        }
    }

    private func addUsage(device: String, bytes: Double) {
        let key = dayKey()
        var per = usage[key] ?? [:]
        if let prev = lastBytes[device] {
            let delta = bytes - prev
            if delta > 0 { per[device, default: 0] += delta }
        }
        usage[key] = per
        lastBytes[device] = bytes
        for i in rows.indices where rows[i].device == device {
            rows[i].usedToday = per[device] ?? 0
        }
        if let limit = dataLimits[device], limit > 0,
           (per[device] ?? 0) >= limit,
           !limitNotified.contains("\(key):\(device)") {
            limitNotified.insert("\(key):\(device)")
            let name = rows.first(where: { $0.device == device })?.service ?? device
            let amount = limit >= 1_000_000_000
                ? String(format: "%.1f GB", limit / 1_000_000_000)
                : String(format: "%.0f MB", limit / 1_000_000)
            notify(title: "\(name) passed its data limit", message: "\(amount) used today")
        }
    }

    func dayKey() -> String {
        Self.dayFormatter.string(from: Date())
    }

    func showToast(_ text: String, isError: Bool = false) {
        toast = ToastMsg(text: text, isError: isError)
        toastDismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }
}
