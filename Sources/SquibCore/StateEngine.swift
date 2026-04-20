import Foundation

private struct SessionRecord {
    var state: PetState
    var lastSeen: Date
}

// Multi-session state engine with priority resolution and stale eviction.
// Synthetic sessions (subagent, notification) are managed explicitly and not evicted by the timer.
public final class StateEngine {
    public var onStateChange:    ((PetState) -> Void)?
    public var onSessionsChange: (([String: PetState]) -> Void)?
    public private(set) var currentState: PetState = .idle

    private var sessions:        [String: SessionRecord] = [:]
    private var staleTimer:      Timer?
    private let staleCutoff:     TimeInterval = 30
    private let anonKey          = "[anon]"
    private let subagentKey      = "__subagent__"
    private var activeSubagents  = 0

    public init() {
        staleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.evictStaleSessions()
        }
    }

    deinit { staleTimer?.invalidate() }

    public func handle(_ event: HookEvent) {
        let key = event.sessionId ?? anonKey

        switch event.hookEventName {
        case "SessionEnd":
            sessions.removeValue(forKey: key)

        case "SubagentStart":
            activeSubagents += 1
            updateSubagentSession()

        case "SubagentStop":
            activeSubagents = max(0, activeSubagents - 1)
            updateSubagentSession()

        case "PreToolUse", "PostToolUse":
            // Upgrade to building when 3+ real sessions are active
            sessions[key] = SessionRecord(state: .working, lastSeen: Date())
            let realCount = sessions.filter { !isSynthetic($0.key) }.count
            if realCount >= 3 {
                sessions[key] = SessionRecord(state: .building, lastSeen: Date())
            }

        default:
            guard let state = PetState.from(hookEventName: event.hookEventName) else { return }
            sessions[key] = SessionRecord(state: state, lastSeen: Date())
        }

        resolveState()
        notifySessionsChange()
    }

    /// Sets or clears the notification state for a pending permission request.
    /// Current session states as a synchronous snapshot. Useful for assertions in tests.
    public var sessionSnapshot: [String: PetState] {
        sessions.mapValues(\.state)
    }

    /// Clears all session state and resets to idle. Useful for test teardown.
    public func reset() {
        sessions.removeAll()
        activeSubagents = 0
        resolveState()
        notifySessionsChange()
    }

    public func setNotification(id: UUID, active: Bool) {
        let key = "__notification__\(id)"
        if active {
            sessions[key] = SessionRecord(state: .notification, lastSeen: Date())
        } else {
            sessions.removeValue(forKey: key)
        }
        resolveState()
        notifySessionsChange()
    }

    private func updateSubagentSession() {
        if activeSubagents > 0 {
            let state: PetState = activeSubagents >= 2 ? .conducting : .juggling
            sessions[subagentKey] = SessionRecord(state: state, lastSeen: Date())
        } else {
            sessions.removeValue(forKey: subagentKey)
        }
    }

    /// Synthetic sessions are managed explicitly and must not be touched by the stale timer.
    private func isSynthetic(_ key: String) -> Bool {
        key == subagentKey || key.hasPrefix("__notification__")
    }

    private func evictStaleSessions() {
        let cutoff = Date().addingTimeInterval(-staleCutoff)
        let before = sessions.count
        sessions = sessions.filter { isSynthetic($0.key) || $0.value.lastSeen > cutoff }
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
