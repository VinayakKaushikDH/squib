import Testing
import Foundation
@testable import SquibCore

@Suite("StateEngine")
struct StateEngineTests {

    // MARK: - Initial state

    @Test("initial state is idle")
    func initialState() {
        let engine = StateEngine()
        #expect(engine.currentState == .idle)
    }

    // MARK: - Basic event handling

    @Test("UserPromptSubmit sets thinking")
    func userPromptSubmit() {
        let engine = StateEngine()
        engine.handle(HookEvent(hookEventName: "UserPromptSubmit", sessionId: "s1", toolName: nil))
        #expect(engine.currentState == .thinking)
    }

    @Test("PreToolUse sets working")
    func preToolUse() {
        let engine = StateEngine()
        engine.handle(HookEvent(hookEventName: "PreToolUse", sessionId: "s1", toolName: nil))
        #expect(engine.currentState == .working)
    }

    @Test("PostToolUseFailure sets error")
    func toolUseFailure() {
        let engine = StateEngine()
        engine.handle(HookEvent(hookEventName: "PostToolUseFailure", sessionId: "s1", toolName: nil))
        #expect(engine.currentState == .error)
    }

    @Test("SessionEnd removes session and recalculates state")
    func sessionEnd() {
        let engine = StateEngine()
        engine.handle(HookEvent(hookEventName: "PreToolUse", sessionId: "s1", toolName: nil))
        engine.handle(HookEvent(hookEventName: "SessionEnd",  sessionId: "s1", toolName: nil))
        #expect(engine.currentState == .idle)
    }

    // MARK: - Priority resolution

    @Test("higher-priority state wins across sessions")
    func priorityResolution() {
        let engine = StateEngine()
        engine.handle(HookEvent(hookEventName: "UserPromptSubmit",   sessionId: "s1", toolName: nil)) // thinking
        engine.handle(HookEvent(hookEventName: "PostToolUseFailure", sessionId: "s2", toolName: nil)) // error
        #expect(engine.currentState == .error)
    }

    @Test("removing the high-priority session falls back to lower state")
    func priorityFallback() {
        let engine = StateEngine()
        engine.handle(HookEvent(hookEventName: "UserPromptSubmit",   sessionId: "s1", toolName: nil))
        engine.handle(HookEvent(hookEventName: "PostToolUseFailure", sessionId: "s2", toolName: nil))
        engine.handle(HookEvent(hookEventName: "SessionEnd",         sessionId: "s2", toolName: nil))
        #expect(engine.currentState == .thinking)
    }

    // MARK: - Subagent counting

    @Test("single SubagentStart gives juggling")
    func singleSubagent() {
        let engine = StateEngine()
        engine.handle(HookEvent(hookEventName: "SubagentStart", sessionId: nil, toolName: nil))
        #expect(engine.currentState == .juggling)
    }

    @Test("two SubagentStarts give conducting")
    func twoSubagents() {
        let engine = StateEngine()
        engine.handle(HookEvent(hookEventName: "SubagentStart", sessionId: nil, toolName: nil))
        engine.handle(HookEvent(hookEventName: "SubagentStart", sessionId: nil, toolName: nil))
        #expect(engine.currentState == .conducting)
    }

    @Test("SubagentStop decrements and recalculates")
    func subagentStop() {
        let engine = StateEngine()
        engine.handle(HookEvent(hookEventName: "SubagentStart", sessionId: nil, toolName: nil))
        engine.handle(HookEvent(hookEventName: "SubagentStart", sessionId: nil, toolName: nil))
        engine.handle(HookEvent(hookEventName: "SubagentStop",  sessionId: nil, toolName: nil))
        #expect(engine.currentState == .juggling)
    }

    @Test("SubagentStop to zero removes subagent session")
    func subagentStopToZero() {
        let engine = StateEngine()
        engine.handle(HookEvent(hookEventName: "SubagentStart", sessionId: nil, toolName: nil))
        engine.handle(HookEvent(hookEventName: "SubagentStop",  sessionId: nil, toolName: nil))
        #expect(engine.currentState == .idle)
    }

    // MARK: - Notification (permission requests)

    @Test("setNotification active raises state to notification")
    func notificationActive() {
        let engine = StateEngine()
        let id = UUID()
        engine.setNotification(id: id, active: true)
        #expect(engine.currentState == .notification)
    }

    @Test("setNotification inactive removes notification and falls back")
    func notificationInactive() {
        let engine = StateEngine()
        let id = UUID()
        engine.setNotification(id: id, active: true)
        engine.setNotification(id: id, active: false)
        #expect(engine.currentState == .idle)
    }

    @Test("notification outranks working")
    func notificationBeatsWorking() {
        let engine = StateEngine()
        engine.handle(HookEvent(hookEventName: "PreToolUse", sessionId: "s1", toolName: nil))
        engine.setNotification(id: UUID(), active: true)
        #expect(engine.currentState == .notification)
    }

    // MARK: - Building upgrade

    @Test("3+ real sessions upgrading to building from PreToolUse")
    func buildingUpgrade() {
        let engine = StateEngine()
        engine.handle(HookEvent(hookEventName: "PreToolUse", sessionId: "s1", toolName: nil))
        engine.handle(HookEvent(hookEventName: "PreToolUse", sessionId: "s2", toolName: nil))
        engine.handle(HookEvent(hookEventName: "PreToolUse", sessionId: "s3", toolName: nil))
        #expect(engine.currentState == .building)
    }

    // MARK: - onStateChange callback

    @Test("onStateChange fires when state changes")
    func stateChangeCallback() {
        let engine = StateEngine()
        var received: [PetState] = []
        engine.onStateChange = { received.append($0) }
        engine.handle(HookEvent(hookEventName: "UserPromptSubmit", sessionId: "s1", toolName: nil))
        engine.handle(HookEvent(hookEventName: "PreToolUse",       sessionId: "s1", toolName: nil))
        #expect(received == [.thinking, .working])
    }

    @Test("onStateChange does not fire when state is unchanged")
    func stateChangeNoFire() {
        let engine = StateEngine()
        var count = 0
        engine.onStateChange = { _ in count += 1 }
        engine.handle(HookEvent(hookEventName: "PreToolUse", sessionId: "s1", toolName: nil))
        engine.handle(HookEvent(hookEventName: "PreToolUse", sessionId: "s2", toolName: nil)) // same priority
        #expect(count == 1)
    }

    // MARK: - onSessionsChange callback

    @Test("onSessionsChange fires with correct snapshot")
    func sessionsChangeCallback() {
        let engine = StateEngine()
        var lastSnapshot: [String: PetState] = [:]
        engine.onSessionsChange = { lastSnapshot = $0 }
        engine.handle(HookEvent(hookEventName: "UserPromptSubmit", sessionId: "abc", toolName: nil))
        #expect(lastSnapshot["abc"] == .thinking)
    }

    // MARK: - Nil sessionId uses anonymous key

    @Test("nil sessionId is tracked under anonymous key")
    func nilSessionId() {
        let engine = StateEngine()
        var lastSnapshot: [String: PetState] = [:]
        engine.onSessionsChange = { lastSnapshot = $0 }
        engine.handle(HookEvent(hookEventName: "UserPromptSubmit", sessionId: nil, toolName: nil))
        #expect(lastSnapshot["[anon]"] == .thinking)
    }
}
