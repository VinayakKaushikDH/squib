import AppKit

// NSStatusItem menu bar presence.
// Shows the active session list and a Quit item.
// Updated via update(sessions:) — called from AppDelegate when StateEngine fires onSessionsChange.
final class TrayMenu: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu       = NSMenu()

    override init() {
        super.init()
        statusItem.button?.title = "squib"
        statusItem.menu = menu
        rebuild(sessions: [:])
    }

    func update(sessions: [String: PetState]) {
        rebuild(sessions: sessions)
    }

    // MARK: - Private

    private func rebuild(sessions: [String: PetState]) {
        menu.removeAllItems()

        if sessions.isEmpty {
            let item = NSMenuItem(title: "No active sessions", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for (id, state) in sessions.sorted(by: { $0.key < $1.key }) {
                let label = truncated(id) + "  " + state.rawValue
                let item  = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit squib", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func truncated(_ id: String) -> String {
        id.count > 14 ? String(id.prefix(12)) + "…" : id
    }
}
