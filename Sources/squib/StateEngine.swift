import Foundation

private struct SessionRecord {
    var state: PetState
    var lastSeen: Date
}

// Phase 1c: multi-session, priority resolution, stale cleanup.
final class StateEngine {
    var onStateChange:   ((PetState) -> Void)?
    /// Fired on main thread whenever the session map changes. Passes a [sessionId: PetState] snapshot.
    var onSessionsChange: (([String: PetState]) -> Void)?
    private(set) var currentState: PetState = .idle

    private var sessions: [String: SessionRecord] = [:]
    private var staleTimer: Timer?
    private let staleCutoff: TimeInterval = 30
    private let anonKey = "__anon__"

    init() {
        staleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.evictStaleSessions()
        }
    }

    deinit { staleTimer?.invalidate() }

    func handle(_ event: HookEvent) {
        let key = event.sessionId ?? anonKey

        if event.hookEventName == "SessionEnd" {
            sessions.removeValue(forKey: key)
        } else if let newState = PetState.from(hookEventName: event.hookEventName) {
            sessions[key] = SessionRecord(state: newState, lastSeen: Date())
        } else {
            return
        }

        resolveState()
        notifySessionsChange()
    }

    private func evictStaleSessions() {
        let cutoff = Date().addingTimeInterval(-staleCutoff)
        let before = sessions.count
        sessions = sessions.filter { $0.value.lastSeen > cutoff }
        if sessions.count != before {
            resolveState()
            notifySessionsChange()
        }
    }

    private func resolveState() {
        let resolved = sessions.values
            .map(\.state)
            .max(by: { $0.priority < $1.priority }) ?? .idle
        guard resolved != currentState else { return }
        currentState = resolved
        onStateChange?(resolved)
    }

    private func notifySessionsChange() {
        let snapshot = sessions.mapValues(\.state)
        onSessionsChange?(snapshot)
    }
}
