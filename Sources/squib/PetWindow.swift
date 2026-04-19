import AppKit

final class PetWindow: NSPanel {
    private static let petSize = NSSize(width: 200, height: 200)
    private var petView: PetView!
    private var mouseMonitor: Any?

    private var baseFrame: NSRect = .zero

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = PetWindow.petSize
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - size.width - 24,
            y: screen.visibleFrame.minY + 24
        )
        let frame = NSRect(origin: origin, size: size)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        baseFrame = frame

        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let view = PetView(frame: NSRect(origin: .zero, size: size))
        petView = view
        contentView = view

        startEyeTracking()
    }

    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func startEyeTracking() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self else { return }
            self.updateEyeTracking(cursor: NSEvent.mouseLocation)
        }
    }

    // Converts screen cursor position to SVG pupil offset and forwards to PetView.
    // Uses circular clamping so diagonal movement stays within the socket circle.
    private func updateEyeTracking(cursor: NSPoint) {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let dx = Double(cursor.x - center.x)
        let dy = Double(cursor.y - center.y)  // AppKit: positive = cursor above pet center
        let magnitude = (dx * dx + dy * dy).squareRoot()
        guard magnitude > 0 else { return }
        let scale = 300.0   // screen points for full deflection
        let maxOffset = 3.5 // SVG units (socket radius - pupil radius)
        let clamped = min(magnitude, scale) / scale * maxOffset
        let angle = atan2(dy, dx)
        let svgDx = clamped * cos(angle)
        let svgDy = -clamped * sin(angle) // negate: screen-up (positive dy) → SVG-up (negative dy)
        petView.updateEyes(dx: svgDx, dy: svgDy)
    }

    func loadState(_ state: PetState) {
        petView.loadState(state.svgName)
    }

    /// Slides the pet up by `offset` points from its base position (animated).
    /// Pass 0 to return to the base position.
    func setBubbleOffset(_ offset: CGFloat) {
        var target = baseFrame
        target.origin.y += offset
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(target, display: true)
        }
    }
}
