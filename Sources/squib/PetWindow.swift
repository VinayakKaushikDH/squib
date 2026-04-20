import AppKit

final class PetWindow: NSPanel {
    private static let petSize = NSSize(width: 200, height: 200)
    private var petView: PetView!
    private var mouseMonitor: Any?
    private var currentState: PetState = .idle

    private var baseFrame: NSRect = .zero

    // Timers for multi-step sequences
    private var sequenceTimer: Timer?
    private var idleVariantTimer: Timer?

    // Idle variants: (SVG name, duration to show in seconds)
    // Duration matches each SVG's own animation cycle so we switch cleanly at the end.
    private let idleVariants: [(name: String, duration: Double)] = [
        ("clawd-idle-look",    10.0),  // 10s loop: looks left/right, scratches
        ("clawd-idle-reading", 14.0),  // 14s loop: grabs book, reads, slides away
        ("clawd-idle-yawn",     3.8),  // 3.8s one-shot: yawn + tear
    ]

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
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
    }

    private func startEyeTracking() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self, self.currentState.supportsEyeTracking else { return }
            self.updateEyeTracking(cursor: NSEvent.mouseLocation)
        }
    }

    // Converts screen cursor position to SVG-unit offset for #eyes-js translate.
    // Circular clamping keeps the pupil inside the socket. Max 3.0 SVG units (theme spec).
    private func updateEyeTracking(cursor: NSPoint) {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let dx = Double(cursor.x - center.x)
        let dy = Double(cursor.y - center.y)
        let magnitude = (dx * dx + dy * dy).squareRoot()
        guard magnitude > 0 else { return }
        let scale     = 300.0  // screen points for full deflection
        let maxOffset = 3.0    // SVG units (theme spec for #eyes-js)
        let clamped   = min(magnitude, scale) / scale * maxOffset
        let angle     = atan2(dy, dx)
        let svgDx     =  clamped * cos(angle)
        let svgDy     = -clamped * sin(angle) // negate: screen-up → SVG-up
        petView.updateEyes(dx: svgDx, dy: svgDy)
    }

    func loadState(_ state: PetState) {
        currentState = state
        cancelSequences()

        switch state {
        case .idle:
            petView.loadSVG(name: "clawd-idle-follow")
            scheduleIdleVariant()
        case .sleeping:
            playSleepSequence()
        default:
            petView.loadState(state)
        }
    }

    // MARK: - Sleep sequence: yawn (3.8s) → doze (2s) → collapse (1s) → sleeping SVG
    // Step 1 uses loadSVG (full page load, sets base URL for the SVG directory).
    // Steps 2–4 use swapInlineSVG (JS innerHTML swap — no reload, no flash).

    private func playSleepSequence() {
        petView.loadSVG(name: "clawd-idle-yawn")
        sequenceTimer = Timer.scheduledTimer(withTimeInterval: 3.8, repeats: false) { [weak self] _ in
            guard let self, self.currentState == .sleeping else { return }
            self.petView.swapInlineSVG(name: "clawd-idle-doze")
            self.sequenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                guard let self, self.currentState == .sleeping else { return }
                self.petView.swapInlineSVG(name: "clawd-idle-collapse")
                self.sequenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                    guard let self, self.currentState == .sleeping else { return }
                    self.petView.swapInlineSVG(name: "clawd-sleeping")
                }
            }
        }
    }

    // MARK: - Idle variant pool: random variant every 20–45s, then back to follow

    private func scheduleIdleVariant() {
        let delay = Double.random(in: 20...45)
        idleVariantTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.currentState == .idle else { return }
            let variant = self.idleVariants.randomElement()!
            self.petView.loadSVG(name: variant.name)
            self.sequenceTimer = Timer.scheduledTimer(withTimeInterval: variant.duration, repeats: false) { [weak self] _ in
                guard let self, self.currentState == .idle else { return }
                self.petView.loadSVG(name: "clawd-idle-follow")
                self.scheduleIdleVariant()
            }
        }
    }

    private func cancelSequences() {
        sequenceTimer?.invalidate();    sequenceTimer    = nil
        idleVariantTimer?.invalidate(); idleVariantTimer = nil
    }

    // MARK: - Bubble offset

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
