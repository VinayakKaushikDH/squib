import AppKit

/// Manages the permission bubble stack anchored to the lower-right corner of the screen.
/// Bubbles stack vertically upward. Each bubble self-reports its actual rendered height
/// via JS→Swift messaging; the manager repositions the stack on every height update.
final class BubbleManager {
    private static let margin: CGFloat = 16  // from screen edges
    private static let gap:    CGFloat = 8   // between bubbles (and between top bubble and pet)

    private var stack: [(request: PermissionRequest, window: BubbleWindow)] = []

    /// Fired with the Y offset the pet should shift up from its base position.
    var onOffsetChange: ((CGFloat) -> Void)?
    /// Fired when the user resolves a bubble (Allow, Deny, suggestion, elicitation submit).
    var onDecision: ((UUID, PermissionDecision) -> Void)?

    // MARK: - Public API

    func add(_ request: PermissionRequest) {
        let win = BubbleWindow(request: request)
        win.onDecision = { [weak self] decision in
            self?.onDecision?(request.id, decision)
            self?.remove(id: request.id)
        }
        win.onHeightChanged = { [weak self] in
            self?.reposition()
        }
        stack.append((request, win))
        reposition()
    }

    func remove(id: UUID) {
        guard let idx = stack.firstIndex(where: { $0.request.id == id }) else { return }
        stack[idx].window.close()
        stack.remove(at: idx)
        reposition()
    }

    /// Closes all bubbles and resets the pet offset to 0. Call on app quit.
    func dismissAll() {
        stack.forEach { $0.window.close() }
        stack.removeAll()
        onOffsetChange?(0)
    }

    // MARK: - Layout

    private func reposition() {
        let wa     = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let bw     = BubbleWindow.width
        let margin = Self.margin
        let gap    = Self.gap

        let x = wa.maxX - bw - margin
        var y = wa.minY + margin

        for entry in stack {
            entry.window.show(at: NSPoint(x: x, y: y))
            y += entry.window.measuredHeight + gap
        }

        // Pet Y offset = total stack height.
        let stackHeight: CGFloat
        if stack.isEmpty {
            stackHeight = 0
        } else {
            let total = stack.reduce(0) { $0 + $1.window.measuredHeight }
            stackHeight = total + CGFloat(stack.count - 1) * gap
        }
        onOffsetChange?(stackHeight)
    }
}
