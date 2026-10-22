import SwiftUI
import AppKit

// MARK: - Per-connection actions menu

/// Device options as a native NSMenu with submenus, built fresh on every
/// click by a plain NSButton. The button re-asserts its icon in
/// updateNSView, so list recycling after a disconnect cannot leave an
/// invisible-but-clickable control behind. Live updates hold while the
/// menu is open, so graph activity cannot make it flicker.
struct ActionsMenuButton: NSViewRepresentable {
    @ObservedObject var model: LinkModel
    var row: LinkRow

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        context.coordinator.button = button
        context.coordinator.configure(model: model, row: row)
        applyIcon(to: button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.button = button
        context.coordinator.configure(model: model, row: row)
        applyIcon(to: button)
    }

    private func applyIcon(to button: NSButton) {
        button.image = NSImage(systemSymbolName: "ellipsis.circle",
                               accessibilityDescription: "More actions")
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "More actions for \(row.service)"
    }

    final class Coordinator: NSObject {
        weak var button: NSButton?
        var model: LinkModel?
        var device: String?

        func configure(model: LinkModel, row: LinkRow) {
            self.model = model
            self.device = row.device
        }

        func currentRow() -> LinkRow? {
            guard let model, let device else { return nil }
            return model.rows.first(where: { $0.device == device })
        }

        @objc func showMenu(_ sender: NSButton) {
            guard let model, let row = currentRow() else { return }
            model.interactionHold = true
            defer { model.interactionHold = false }

            let menu = NSMenu()
            add(menu, "Prefer this connection", key: "prefer",
                checked: model.isPreferred(row))
            add(menu, "Test speed", key: "test", enabled: row.ip != nil)
            menu.addItem(.separator())

            let roleMenu = NSMenu()
            for (id, label) in [("primary", "Primary"), ("balanced", "Balanced"),
                                ("secondary", "Secondary"), ("backup", "Backup only"),
                                ("never", "Never use")] {
                add(roleMenu, label, key: "role:\(id)",
                    checked: model.role(of: row.device) == id)
            }
            let roleItem = NSMenuItem(title: "Connection role", action: nil, keyEquivalent: "")
            roleItem.submenu = roleMenu
            menu.addItem(roleItem)

            let limitMenu = NSMenu()
            for (value, label) in [(0.0, "No limit"), (1_000_000_000.0, "1 GB"),
                                   (5_000_000_000.0, "5 GB"), (10_000_000_000.0, "10 GB"),
                                   (25_000_000_000.0, "25 GB")] {
                add(limitMenu, label, key: "limit:\(value)",
                    checked: (model.dataLimits[row.device] ?? 0) == value)
            }
            let limitItem = NSMenuItem(title: "Daily data limit", action: nil, keyEquivalent: "")
            limitItem.submenu = limitMenu
            menu.addItem(limitItem)

            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: sender.bounds.height + 2),
                       in: sender)
        }

        func add(_ menu: NSMenu, _ title: String, key: String,
                         checked: Bool = false, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: #selector(handle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = checked ? .on : .off
            item.isEnabled = enabled
            menu.addItem(item)
        }

        @objc private func handle(_ sender: NSMenuItem) {
            guard let model, let row = currentRow(),
                  let key = sender.representedObject as? String else { return }
            if key == "prefer" {
                model.makePrimary(row)
            } else if key == "test" {
                model.runSpeedTest(row)
            } else if key.hasPrefix("role:") {
                model.setRole(device: row.device, role: String(key.dropFirst(5)))
            } else if key.hasPrefix("limit:") {
                let value = Double(String(key.dropFirst(6))) ?? 0
                model.setDataLimit(device: row.device, bytesLimit: value)
            }
        }
    }
}
