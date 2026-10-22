import SwiftUI
import AppKit

// MARK: - App entry point

extension Notification.Name {
    static let linkBlendWillTerminate = Notification.Name("linkBlendWillTerminate")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .linkBlendWillTerminate, object: nil)
    }
}

@main
struct LinkBlendApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = LinkModel()

    private var menuTitle: String {
        if model.pausedByUser { return "Paused" }
        if model.tunnelCount >= 2 { return "Merged" }
        if model.tunnelCount == 1 { return "Single" }
        return "Off"
    }

    private var menuSymbol: String {
        if model.pausedByUser { return "pause.circle.fill" }
        if model.tunnelCount >= 1 { return "arrow.triangle.branch" }
        return "exclamationmark.triangle"
    }

    var body: some Scene {
        Window("LinkBlend", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 880, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: menuSymbol)
                Text(menuTitle).font(.system(.subheadline, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
