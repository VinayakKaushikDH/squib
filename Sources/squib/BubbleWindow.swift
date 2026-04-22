import AppKit
import SwiftUI
import SquibCore

final class BubbleWindow: NSPanel {
    static let width:           CGFloat = 340
    static let estimatedHeight: CGFloat = 170

    let request: PermissionRequest
    var onDecision:      ((PermissionDecision) -> Void)?
    var onTrustSession:  (() -> Void)?
    /// Fired on main thread when the card reports its real rendered height.
    var onHeightChanged: (() -> Void)?

    private(set) var measuredHeight: CGFloat = BubbleWindow.estimatedHeight
    private var viewModel: BubbleViewModel!

    init(request: PermissionRequest) {
        self.request = request
        super.init(
            contentRect: NSRect(origin: .zero,
                                size: NSSize(width: Self.width, height: Self.estimatedHeight)),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        level                = .floating
        backgroundColor      = .clear
        isOpaque             = false
        hasShadow            = true
        ignoresMouseEvents   = false
        isReleasedWhenClosed = false
        collectionBehavior   = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        setupGlassView()
    }

    private func setupGlassView() {
        let vm = BubbleViewModel(request: request)
        vm.onDecision     = { [weak self] decision in self?.onDecision?(decision) }
        vm.onTrustSession = { [weak self] in self?.onTrustSession?() }
        vm.onHeightMeasured = { [weak self] h in
            guard let self, h > 0 else { return }
            self.measuredHeight = h
            self.onHeightChanged?()
        }
        viewModel = vm

        let hosting = NSHostingView(rootView: BubbleCardView(model: vm))

        let glass = NSGlassEffectView()
        glass.style        = .regular
        glass.cornerRadius = 16
        glass.contentView  = hosting

        contentView = glass
    }

    // MARK: - Keyboard shortcuts

    /// Called by BubbleManager's global key monitor (Y key).
    func allowViaKey()           { viewModel.triggerAllow() }
    /// Called by BubbleManager's global key monitor (N key).
    func denyViaKey()            { viewModel.triggerDeny() }
    /// Called by BubbleManager's global key monitor (S key).
    func allowSessionViaKey()    { viewModel.triggerAllowSession() }
    /// Called by BubbleManager's global key monitor (A key).
    func firstSuggestionViaKey() { viewModel.triggerFirstSuggestion() }

    // MARK: - Positioning

    func show(at origin: NSPoint) {
        let f = NSRect(origin: origin, size: NSSize(width: Self.width, height: measuredHeight))
        if isVisible {
            setFrame(f, display: true, animate: false)
        } else {
            setFrame(f, display: false)
            orderFrontRegardless()
        }
    }
}
