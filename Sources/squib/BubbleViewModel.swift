import Foundation
import SquibCore

enum BubbleKeyAction { case allow, deny, allowSession, firstSuggestion, editPlan }

@MainActor
final class BubbleViewModel: ObservableObject {
    let request: PermissionRequest

    // Swift → SwiftUI: set by BubbleWindow key handlers
    @Published var pendingKeyAction: BubbleKeyAction? = nil
    @Published var isDecided = false

    // SwiftUI → BubbleWindow callbacks
    var onDecision:       ((PermissionDecision) -> Void)?
    var onTrustSession:   (() -> Void)?
    var onHeightMeasured: ((CGFloat) -> Void)?

    init(request: PermissionRequest) { self.request = request }

    // MARK: - Inbound triggers (called by BubbleWindow)

    func triggerAllow()           { pendingKeyAction = .allow }
    func triggerDeny()            { pendingKeyAction = .deny }
    func triggerAllowSession()    { pendingKeyAction = .allowSession }
    func triggerFirstSuggestion() { pendingKeyAction = .firstSuggestion }
    func triggerEditPlan()        { pendingKeyAction = .editPlan }

    // MARK: - Outbound decisions (called by BubbleCardView)

    func decide(_ decision: PermissionDecision) {
        guard !isDecided else { return }
        isDecided = true
        onDecision?(decision)
    }

    func trustSession() {
        guard !isDecided else { return }
        isDecided = true
        onTrustSession?()
    }
}
