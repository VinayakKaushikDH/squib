import Foundation
import SquibCore

public enum BubbleKeyAction { case allow, deny, allowSession, firstSuggestion, editPlan }

@MainActor
public final class BubbleViewModel: ObservableObject {
    public let request: PermissionRequest

    // Swift → SwiftUI: set by BubbleWindow key handlers
    @Published public var pendingKeyAction: BubbleKeyAction? = nil
    @Published public var isDecided = false

    // SwiftUI → BubbleWindow callbacks
    public var onDecision:       ((PermissionDecision) -> Void)?
    public var onTrustSession:   (() -> Void)?
    public var onHeightMeasured: ((CGFloat) -> Void)?

    public init(request: PermissionRequest) { self.request = request }

    // MARK: - Inbound triggers (called by BubbleWindow)

    public func triggerAllow()           { pendingKeyAction = .allow }
    public func triggerDeny()            { pendingKeyAction = .deny }
    public func triggerAllowSession()    { pendingKeyAction = .allowSession }
    public func triggerFirstSuggestion() { pendingKeyAction = .firstSuggestion }
    public func triggerEditPlan()        { pendingKeyAction = .editPlan }

    // MARK: - Outbound decisions (called by BubbleCardView)

    public func decide(_ decision: PermissionDecision) {
        guard !isDecided else { return }
        isDecided = true
        onDecision?(decision)
    }

    public func trustSession() {
        guard !isDecided else { return }
        isDecided = true
        onTrustSession?()
    }
}
