import AppKit
import SquibCore

final class PetWindow: NSPanel {

    // MARK: - Constants

    private static let petSize          = NSSize(width: 200, height: 200)
    private static let snapTolerance:  CGFloat          = 30
    private static let miniOffsetRatio: CGFloat          = 0.486
    private static let peekOffset:     CGFloat          = 25
    private static let jumpDuration:   TimeInterval     = 0.35
    private static let jumpPeakHeight: CGFloat          = 40
    private static let dragThreshold:  CGFloat          = 3

    // MARK: - Properties

    private var petView: PetView!
    private var monitors: [Any] = []
    private var currentState: PetState = .idle

    // Bubble offset anchor — updated after every drag end and mini exit
    private var baseFrame: NSRect = .zero

    // Sequence timers
    private var sequenceTimer:    Timer?
    private var idleVariantTimer: Timer?

    private let idleVariants: [(name: String, duration: Double)] = [
        ("clawd-idle-look",    10.0),
        ("clawd-idle-reading", 14.0),
        ("clawd-idle-yawn",     3.8),
    ]

    // Drag
    private var mouseOverPet          = false
    private var cursorIsOverCharacter = false   // async pixel hit test result
    private var hitTestPending        = false
    private var isDragging            = false
    private var isDragReacting        = false   // showing clawd-react-drag.svg
    private var dragStartCursor: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero

    // Mini mode
    private enum MiniEdge { case left, right }
    private var isMiniMode      = false
    private var miniEdge        = MiniEdge.right
    private var preMiniOrigin:  NSPoint = .zero
    private var currentMiniX:   CGFloat = 0
    private var miniPeeked      = false
    private var miniAnimating   = false
    private var miniAnimTimer:  Timer?
    private var slideTimer:     Timer?   // mini entry + peek X-only slides
    private var parabolaTimer:  Timer?
    private var pendingState:   PetState?

    // MARK: - Init

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size   = PetWindow.petSize
        let defaultOrigin = NSPoint(
            x: screen.visibleFrame.maxX - size.width  - 24,
            y: screen.visibleFrame.minY                + 24
        )
        let initialFrame = NSRect(origin: defaultOrigin, size: size)

        super.init(
            contentRect: initialFrame,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )

        // Restore saved position (must come before baseFrame is set)
        if let saved = PetWindow.loadSavedPosition(size: size) {
            setFrame(NSRect(origin: saved, size: size), display: false)
        }
        baseFrame = frame

        // CGAssistiveTechHighWindowLevel = 1500 — same as reference (mac-window.js).
        // Above the menu bar level (~25), allows the pet to sit at the very top of the screen.
        level              = NSWindow.Level(rawValue: 1500)
        backgroundColor    = .clear
        isOpaque           = false
        hasShadow          = false
        ignoresMouseEvents = true   // toggled dynamically in mouseMoved
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let view = PetView(frame: NSRect(origin: .zero, size: size))
        petView      = view
        contentView  = view

        startMouseMonitors()
    }

    deinit {
        monitors.forEach { NSEvent.removeMonitor($0) }
        sequenceTimer?.invalidate()
        idleVariantTimer?.invalidate()
        miniAnimTimer?.invalidate()
        slideTimer?.invalidate()
        parabolaTimer?.invalidate()
    }

    // Allow the window to go partially off-screen (mini mode, edge snap, above menu bar).
    // AppKit's default constrains to visibleFrame — that resizes the window at edges and
    // prevents dragging above the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    // MARK: - Mouse Monitors

    private func startMouseMonitors() {
        // 1. mouseMoved (global) — always fires regardless of app focus.
        //    Toggles ignoresMouseEvents so local monitors below can consume clicks
        //    only when the cursor is actually over the pet.
        let move = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self else { return }
            let cursor  = NSEvent.mouseLocation
            let wasOver = self.mouseOverPet
            self.mouseOverPet = self.frame.contains(cursor)

            if !self.mouseOverPet {
                // Cursor left the frame — clear immediately without waiting for JS
                if wasOver {
                    self.cursorIsOverCharacter = false
                    if !self.isDragging { self.ignoresMouseEvents = true }
                }
            } else if !self.hitTestPending {
                // Inside frame — fire async pixel hit test (skip if one already in flight)
                self.hitTestPending = true
                let local = NSPoint(x: cursor.x - self.frame.origin.x,
                                    y: cursor.y - self.frame.origin.y)
                self.petView.isOpaque(at: local, frameHeight: self.frame.height) { [weak self] opaque in
                    guard let self else { return }
                    self.hitTestPending = false
                    self.cursorIsOverCharacter = opaque
                    if !self.isDragging { self.ignoresMouseEvents = !opaque }
                }
            }

            if self.isMiniMode {
                self.handleMiniPeek(cursor: cursor)
                self.updateEyeTracking(cursor: cursor)   // mini SVGs all have #eyes-js
            } else if self.currentState.supportsEyeTracking {
                self.updateEyeTracking(cursor: cursor)
            }
        }

        // 2–4. Local monitors — only fire when ignoresMouseEvents = false (cursor over pet).
        //      Returning nil consumes the event so it never reaches the app below.

        let down = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, self.mouseOverPet, self.cursorIsOverCharacter else { return event }
            if self.isMiniMode || self.miniAnimating { return nil }
            self.isDragging      = true
            self.dragStartCursor = NSEvent.mouseLocation
            self.dragStartOrigin = self.frame.origin
            return nil   // consume — prevents text selection in the app below
        }

        let drag = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self, self.isDragging else { return event }
            let cursor = NSEvent.mouseLocation
            let dx = cursor.x - self.dragStartCursor.x
            let dy = cursor.y - self.dragStartCursor.y
            guard hypot(dx, dy) > PetWindow.dragThreshold else { return nil }
            if !self.isDragReacting {
                self.isDragReacting = true
                self.petView.loadSVG(name: "clawd-react-drag")
            }
            self.setFrameOrigin(NSPoint(
                x: self.dragStartOrigin.x + dx,
                y: self.dragStartOrigin.y + dy
            ))
            return nil
        }

        let up = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            if self.isMiniMode && self.mouseOverPet {
                self.exitMiniMode()
                return nil
            }
            guard self.isDragging else { return event }
            self.isDragging         = false
            self.ignoresMouseEvents = !self.cursorIsOverCharacter
            self.baseFrame          = self.frame
            if self.isDragReacting {
                self.isDragReacting = false
                self.loadState(self.currentState)
            }
            self.savePosition()
            self.checkMiniSnap()
            return nil
        }

        // Global drag + up: fire when cursor enters another process (e.g. menu bar area).
        // NSEvent global monitors only fire for events dispatched to *other* apps, so
        // there's no double-fire with the local monitors above.
        let globalDrag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard let self, self.isDragging else { return }
            let cursor = NSEvent.mouseLocation
            let dx = cursor.x - self.dragStartCursor.x
            let dy = cursor.y - self.dragStartCursor.y
            guard hypot(dx, dy) > PetWindow.dragThreshold else { return }
            if !self.isDragReacting {
                self.isDragReacting = true
                self.petView.loadSVG(name: "clawd-react-drag")
            }
            self.setFrameOrigin(NSPoint(
                x: self.dragStartOrigin.x + dx,
                y: self.dragStartOrigin.y + dy
            ))
        }

        let globalUp = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            guard let self, self.isDragging else { return }
            self.isDragging         = false
            self.ignoresMouseEvents = !self.mouseOverPet
            self.baseFrame          = self.frame
            if self.isDragReacting {
                self.isDragReacting = false
                self.loadState(self.currentState)
            }
            self.savePosition()
            self.checkMiniSnap()
        }

        monitors = [move, down, drag, up, globalDrag, globalUp].compactMap { $0 }
    }

    // MARK: - Eye Tracking

    private func updateEyeTracking(cursor: NSPoint) {
        let center    = NSPoint(x: frame.midX, y: frame.midY)
        let dx        = Double(cursor.x - center.x)
        let dy        = Double(cursor.y - center.y)
        let magnitude = (dx * dx + dy * dy).squareRoot()
        guard magnitude > 0 else { return }
        let scale     = 300.0
        let maxOffset = 3.0
        let clamped   = min(magnitude, scale) / scale * maxOffset
        let angle     = atan2(dy, dx)
        // Snap to 0.5-unit grid (reduces per-frame jitter).
        // Clamp Y to 50% of maxOffset — matches reference: eyes track
        // horizontal movement more freely than vertical.
        let eyeDx = (clamped * cos(angle) * 2).rounded() / 2
        let rawDy = (-clamped * sin(angle) * 2).rounded() / 2
        let eyeDy = max(-maxOffset * 0.5, min(maxOffset * 0.5, rawDy))
        petView.updateEyes(dx: eyeDx, dy: eyeDy)
    }

    // MARK: - State Loading

    func loadState(_ state: PetState) {
        currentState = state

        if isMiniMode {
            pendingState = state
            switch state {
            case .error, .notification:
                showMiniState(gif: "clawd-mini-alert", duration: 4.0)
            case .attention:
                showMiniState(gif: "clawd-mini-happy", duration: 4.0)
            default:
                break
            }
            return
        }

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

    private func showMiniState(gif: String, duration: TimeInterval) {
        miniAnimTimer?.invalidate()
        miniPeeked = false
        petView.loadSVG(name: gif, flipped: miniEdge == .left)
        miniAnimTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self, self.isMiniMode else { return }
            self.miniAnimTimer = nil
            self.petView.loadSVG(name: "clawd-mini-idle", flipped: self.miniEdge == .left)
        }
    }

    // MARK: - Sleep Sequence

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

    // MARK: - Idle Variant Pool

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

    // MARK: - Bubble Offset

    func setBubbleOffset(_ offset: CGFloat) {
        guard !isMiniMode, !miniAnimating else { return }

        // Only slide if the pet's current position actually overlaps the bubble
        // region. Bubbles anchor to the lower-right corner; if the pet is far
        // away there's no need to move it.
        if offset > 0 {
            let screen        = screenContaining(baseFrame)
            let wa            = screen.visibleFrame
            let bubbleMargin: CGFloat = 16
            let bubbleLeft    = wa.maxX - BubbleWindow.width - bubbleMargin
            let bubbleTop     = wa.minY + bubbleMargin + offset
            let overlapsH     = baseFrame.maxX > bubbleLeft
            let overlapsV     = baseFrame.minY < bubbleTop
            guard overlapsH && overlapsV else { return }
        }

        var target = baseFrame
        target.origin.y += offset
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration        = 0.15
            ctx.timingFunction  = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(target, display: true)
        }
    }

    // MARK: - Mini Mode Entry

    private func enterMiniMode(edge: MiniEdge, workArea: NSRect) {
        parabolaTimer?.invalidate()
        parabolaTimer = nil

        isMiniMode    = true
        miniEdge      = edge
        miniPeeked    = false
        preMiniOrigin = baseFrame.origin
        currentMiniX  = calcMiniX(workArea: workArea)

        petView.loadSVG(name: "clawd-mini-enter", flipped: edge == .left)

        // Slide to edge (100ms), then start enter→idle timer
        miniAnimating = true
        animateSlide(toX: currentMiniX, duration: 0.1) { [weak self] in
            guard let self else { return }
            self.baseFrame    = self.frame
            self.miniAnimating = false
            self.miniAnimTimer = Timer.scheduledTimer(
                withTimeInterval: 3.2, repeats: false
            ) { [weak self] _ in
                guard let self, self.isMiniMode else { return }
                self.miniAnimTimer = nil
                self.petView.loadSVG(name: "clawd-mini-idle", flipped: self.miniEdge == .left)
            }
        }
    }

    // MARK: - Mini Mode Exit

    func exitMiniMode() {
        guard isMiniMode else { return }
        miniAnimTimer?.invalidate()
        miniAnimTimer  = nil
        isMiniMode     = false
        miniPeeked     = false
        miniAnimating  = true

        // Push return target away from snap zone to prevent immediate re-snap
        var returnOrigin = preMiniOrigin
        let screen = screenContaining(frame)
        let wa     = screen.visibleFrame
        let w      = frame.size.width
        let mEdge  = w * 0.25

        let rightLimit = wa.maxX - w + mEdge
        if miniEdge == .right && returnOrigin.x >= rightLimit - PetWindow.snapTolerance {
            returnOrigin.x = rightLimit - PetWindow.snapTolerance - 100
        }
        let leftLimit = wa.minX - mEdge
        if miniEdge == .left && returnOrigin.x <= leftLimit + PetWindow.snapTolerance {
            returnOrigin.x = leftLimit + PetWindow.snapTolerance + 100
        }

        animateParabola(to: returnOrigin, duration: PetWindow.jumpDuration) { [weak self] in
            guard let self else { return }
            self.baseFrame    = self.frame
            self.miniAnimating = false
            self.savePosition()
            let toApply      = self.pendingState ?? self.currentState
            self.pendingState = nil
            self.loadState(toApply)
        }
    }

    // MARK: - Mini Snap Check

    private func checkMiniSnap() {
        let screen = screenContaining(frame)
        let wa     = screen.visibleFrame
        let w      = frame.size.width
        let mEdge  = w * 0.25

        let rightLimit = wa.maxX - w + mEdge
        if frame.origin.x >= rightLimit - PetWindow.snapTolerance {
            enterMiniMode(edge: .right, workArea: wa)
            return
        }
        let leftLimit = wa.minX - mEdge
        if frame.origin.x <= leftLimit + PetWindow.snapTolerance {
            enterMiniMode(edge: .left, workArea: wa)
            return
        }
        clampToScreen()
    }

    // MARK: - Mini Geometry

    private func calcMiniX(workArea: NSRect) -> CGFloat {
        let w = frame.size.width
        switch miniEdge {
        case .right: return workArea.maxX - w * (1 - PetWindow.miniOffsetRatio)
        case .left:  return workArea.minX - w * PetWindow.miniOffsetRatio
        }
    }

    private func computePeekZone() -> NSRect {
        let screen       = screenContaining(frame)
        let wa           = screen.visibleFrame
        let visibleWidth = frame.size.width * (1 - PetWindow.miniOffsetRatio)
        switch miniEdge {
        case .right:
            // Visible strip runs from wa.maxX - visibleWidth to wa.maxX.
            // Extend left by peekOffset so cursor approaching from on-screen triggers peek.
            return NSRect(
                x:      wa.maxX - visibleWidth - PetWindow.peekOffset,
                y:      frame.minY,
                width:  visibleWidth + PetWindow.peekOffset,
                height: frame.size.height
            )
        case .left:
            // Visible strip runs from wa.minX to wa.minX + visibleWidth.
            // Extend right by peekOffset so cursor approaching from on-screen triggers peek.
            return NSRect(
                x:      wa.minX,
                y:      frame.minY,
                width:  visibleWidth + PetWindow.peekOffset,
                height: frame.size.height
            )
        }
    }

    // MARK: - Mini Peek

    private func handleMiniPeek(cursor: NSPoint) {
        let zone = computePeekZone()
        if zone.contains(cursor) && !miniPeeked {
            miniPeekIn()
        } else if !zone.contains(cursor) && miniPeeked {
            miniPeekOut()
        }
    }

    private func miniPeekIn() {
        guard !miniAnimating else { return }
        miniPeeked = true
        petView.loadSVG(name: "clawd-mini-peek", flipped: miniEdge == .left)
        let offset = miniEdge == .right ? -PetWindow.peekOffset : PetWindow.peekOffset
        animateSlide(toX: currentMiniX + offset, duration: 0.2)
    }

    private func miniPeekOut() {
        guard miniPeeked else { return }
        miniPeeked = false
        petView.loadSVG(name: "clawd-mini-idle", flipped: miniEdge == .left)
        animateSlide(toX: currentMiniX, duration: 0.2)
    }

    // MARK: - Parabola Animation

    private func animateParabola(to target: NSPoint, duration: TimeInterval, onDone: @escaping () -> Void) {
        parabolaTimer?.invalidate()
        let startX    = frame.origin.x
        let startY    = frame.origin.y
        let startTime = Date()

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let p     = CGFloat(min(1.0, Date().timeIntervalSince(startTime) / duration))
            let eased = p * (2 - p)
            // arc is positive at the midpoint (p=0.5).
            // Electron uses Y-from-top so "y - arc" goes up; AppKit uses Y-from-bottom
            // so we must ADD arc to make the window rise during the jump.
            let arc   = -4.0 * PetWindow.jumpPeakHeight * p * (p - 1.0)
            self.setFrameOrigin(NSPoint(
                x: startX + (target.x - startX) * eased,
                y: startY + (target.y - startY) * eased + arc
            ))
            if p >= 1.0 { timer.invalidate(); onDone() }
        }
        parabolaTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    // MARK: - Slide Animation (X-only, Timer-based)

    /// Animates the window's X coordinate using a Timer so it stays in the
    /// AppKit setFrameOrigin path — bypasses the CA layer path used by
    /// NSAnimationContext/animator(), which ignores constrainFrameRect and
    /// causes the window to resize when near screen edges.
    private func animateSlide(toX targetX: CGFloat, duration: TimeInterval, onDone: (() -> Void)? = nil) {
        slideTimer?.invalidate()
        let startX    = frame.origin.x
        let startY    = frame.origin.y
        let startTime = Date()

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let p     = CGFloat(min(1.0, Date().timeIntervalSince(startTime) / duration))
            let eased = p * (2 - p)
            self.setFrameOrigin(NSPoint(
                x: startX + (targetX - startX) * eased,
                y: startY
            ))
            if p >= 1.0 { timer.invalidate(); onDone?() }
        }
        slideTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    // MARK: - Screen Clamp

    private func clampToScreen() {
        // Loose clamp matching the reference's computeLooseClamp:
        // allow 25% of the pet's size as margin beyond the visible work area.
        // This lets the pet sit partially in the menu bar / dock zone (like the
        // reference does) and reach the very top of the screen.
        let screen   = screenContaining(frame)
        let vf       = screen.visibleFrame   // excludes menu bar and dock
        let w        = frame.size.width
        let h        = frame.size.height
        let marginX  = (w * 0.25).rounded()
        let marginY  = (h * 0.25).rounded()
        let clamped  = NSPoint(
            x: min(max(frame.origin.x, vf.minX - marginX), vf.maxX - w + marginX),
            y: min(max(frame.origin.y, vf.minY - marginY), vf.maxY - h + marginY)
        )
        guard clamped != frame.origin else { return }
        setFrameOrigin(clamped)
        baseFrame.origin = clamped
    }

    // MARK: - Screen Utilities

    private func screenContaining(_ rect: NSRect) -> NSScreen {
        NSScreen.screens.max { a, b in
            a.frame.intersection(rect).area < b.frame.intersection(rect).area
        } ?? NSScreen.screens[0]
    }

    // MARK: - Position Persistence

    private static let positionURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".squib")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("position.json")
    }()

    private func savePosition() {
        let dict: [String: Double] = ["x": Double(frame.origin.x), "y": Double(frame.origin.y)]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: PetWindow.positionURL)
    }

    private static func loadSavedPosition(size: NSSize) -> NSPoint? {
        guard
            let data = try? Data(contentsOf: positionURL),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
            let x    = dict["x"],
            let y    = dict["y"]
        else { return nil }
        // Validate: pet center must land on a connected screen
        let center = NSPoint(x: x + Double(size.width) / 2, y: y + Double(size.height) / 2)
        guard NSScreen.screens.contains(where: { $0.frame.contains(center) }) else { return nil }
        return NSPoint(x: x, y: y)
    }
}

// MARK: - NSRect helper

private extension NSRect {
    var area: CGFloat { width * height }
}
