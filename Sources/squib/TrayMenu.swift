import AppKit
import SquibCore

// NSStatusItem menubar presence.
// Icon: custom menubar-icon.png from bundle if present, otherwise cat.fill SF Symbol.
// Menu (refreshed on every open): Launch at Login toggle, session list, Quit.
final class TrayMenu: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu       = NSMenu()
    private var sessions:  [String: PetState] = [:]

    override init() {
        super.init()
        setupButton()
        menu.delegate = self
        statusItem.menu = menu
        rebuild()
    }

    func update(sessions: [String: PetState]) {
        self.sessions = sessions
        rebuild()
    }

    // MARK: - Private

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.image = makeMenubarIcon()
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("Squib")
    }

    // Always returns a non-nil image — falls through to a programmatic draw if needed.
    private func makeMenubarIcon() -> NSImage {
        // Prefer bundled SVG/PNG (drop menubar-icon.svg or .png in Resources/ to customise).
        for ext in ["svg", "png"] {
            if let url = Bundle.module.url(forResource: "menubar-icon", withExtension: ext),
               let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                return image
            }
        }
        // SF Symbol fallback.
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        if let base = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Squib"),
           let img  = base.withSymbolConfiguration(config) {
            return img
        }
        // Guaranteed fallback: draw clawd silhouette via NSBezierPath.
        return makeClawdSilhouette()
    }

    // Draws the clawd standing-pose silhouette into a 22×22 pt NSImage.
    // Coordinates derived from idle-follow.svg geometry (viewBox "-0.5 5.5 16 11"):
    //   xScale = 22/16 = 1.375,  yScale = 22/11 = 2.0
    //   AppKit y (bottom-left origin) = 22 − (svgY − 5.5 + rectH) × yScale
    private func makeClawdSilhouette() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocus()
        NSColor.black.setFill()
        let rects: [NSRect] = [
            NSRect(x: 3.4,  y: 7.0,  width: 15.1, height: 14.0), // torso / head
            NSRect(x: 0.7,  y: 11.0, width: 2.8,  height: 4.0),  // left arm
            NSRect(x: 18.6, y: 11.0, width: 2.8,  height: 4.0),  // right arm
            NSRect(x: 4.8,  y: 3.0,  width: 1.4,  height: 8.0),  // leg 1
            NSRect(x: 7.6,  y: 3.0,  width: 1.4,  height: 8.0),  // leg 2
            NSRect(x: 13.1, y: 3.0,  width: 1.4,  height: 8.0),  // leg 3
            NSRect(x: 15.8, y: 3.0,  width: 1.4,  height: 8.0),  // leg 4
        ]
        rects.forEach { NSBezierPath.fill($0) }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func rebuild() {
        menu.removeAllItems()

        // Launch at Login toggle — always first
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        // Active session list
        if sessions.isEmpty {
            let item = NSMenuItem(title: "No active sessions", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for (id, state) in sessions.sorted(by: { $0.key < $1.key }) {
                let item = NSMenuItem(title: truncated(id) + "  " + state.rawValue,
                                      action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Squib",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItemManager.toggle()
        rebuild()
    }

    private func truncated(_ id: String) -> String {
        id.count > 14 ? String(id.prefix(12)) + "…" : id
    }
}

// Refresh the checkmark whenever the menu opens (state may have changed externally).
extension TrayMenu: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }
}
