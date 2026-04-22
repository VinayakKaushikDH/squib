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
        button.imageScaling  = .scaleNone   // don't auto-scale to button height
        button.setAccessibilityLabel("Squib")
    }

    // Always returns a non-nil image — falls through to a programmatic draw if needed.
    private func makeMenubarIcon() -> NSImage {
        let symbolSize: CGFloat = 21   // adjust here to resize the icon
        let barH = NSStatusBar.system.thickness
        let canvasSize = NSSize(width: barH, height: barH)

        func centered(_ img: NSImage) -> NSImage {
            img.size = NSSize(width: symbolSize, height: symbolSize)
            let canvas = NSImage(size: canvasSize, flipped: false) { _ in
                let x = (barH - symbolSize) / 2
                let y = (barH - symbolSize) / 2
                img.draw(in: NSRect(x: x, y: y, width: symbolSize, height: symbolSize))
                return true
            }
            canvas.isTemplate = true
            return canvas
        }

        // Prefer bundled SVG/PNG (drop menubar-icon.svg or .png in Resources/ to customise).
        for ext in ["svg", "png"] {
            if let url = Bundle.module.url(forResource: "menubar-icon", withExtension: ext),
               let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                return centered(image)
            }
        }
        // SF Symbol fallback.
        let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
        if let base = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Squib"),
           let img  = base.withSymbolConfiguration(config) {
            img.isTemplate = true
            return centered(img)
        }
        // Guaranteed fallback: draw clawd silhouette via NSBezierPath.
        return makeClawdSilhouette()
    }

    // Draws the clawd standing-pose silhouette into a 15×15 pt NSImage.
    // Coordinates derived from idle-follow.svg geometry (viewBox "-0.5 5.5 16 11"):
    //   xScale = 15/16 ≈ 0.94,  yScale = 15/11 ≈ 1.36
    //   AppKit y (bottom-left origin) = 15 − (svgY − 5.5 + rectH) × yScale
    private func makeClawdSilhouette() -> NSImage {
        let image = NSImage(size: NSSize(width: 15, height: 15))
        image.lockFocus()
        NSColor.black.setFill()
        let rects: [NSRect] = [
            NSRect(x: 2.3,  y: 4.8,  width: 10.3, height: 9.5),  // torso / head
            NSRect(x: 0.5,  y: 7.5,  width: 1.9,  height: 2.7),  // left arm
            NSRect(x: 12.7, y: 7.5,  width: 1.9,  height: 2.7),  // right arm
            NSRect(x: 3.3,  y: 2.0,  width: 1.0,  height: 5.4),  // leg 1
            NSRect(x: 5.2,  y: 2.0,  width: 1.0,  height: 5.4),  // leg 2
            NSRect(x: 8.9,  y: 2.0,  width: 1.0,  height: 5.4),  // leg 3
            NSRect(x: 10.8, y: 2.0,  width: 1.0,  height: 5.4),  // leg 4
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
