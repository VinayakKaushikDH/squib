import Testing
import SquibCore

@Suite("PetState")
struct PetStateTests {

    // MARK: - Priority ordering

    @Test("error has the highest priority")
    func errorIsHighestPriority() {
        let sorted = PetState.allCases.sorted { $0.priority > $1.priority }
        #expect(sorted.first == .error)
    }

    @Test("priority values are strictly ordered")
    func priorityOrdering() {
        #expect(PetState.error.priority        > PetState.notification.priority)
        #expect(PetState.notification.priority > PetState.conducting.priority)
        #expect(PetState.conducting.priority   > PetState.juggling.priority)
        #expect(PetState.juggling.priority     > PetState.attention.priority)
        #expect(PetState.attention.priority    > PetState.building.priority)
        #expect(PetState.building.priority     > PetState.working.priority)
        #expect(PetState.working.priority      > PetState.sweeping.priority)
        #expect(PetState.idle.priority         >= PetState.sleeping.priority)
    }

    @Test("sleeping has the lowest priority")
    func sleepingIsLowest() {
        #expect(PetState.allCases.allSatisfy { $0.priority >= PetState.sleeping.priority })
    }

    // MARK: - Asset extension

    @Test("idle and sleeping use SVG, everything else uses GIF")
    func assetExtension() {
        #expect(PetState.idle.assetExtension    == "svg")
        #expect(PetState.sleeping.assetExtension == "svg")
        for state in PetState.allCases where state != .idle && state != .sleeping {
            #expect(state.assetExtension == "gif", "expected gif for \(state)")
        }
    }

    // MARK: - Eye tracking

    @Test("only idle supports eye tracking")
    func eyeTracking() {
        #expect(PetState.idle.supportsEyeTracking == true)
        for state in PetState.allCases where state != .idle {
            #expect(state.supportsEyeTracking == false, "expected no eye tracking for \(state)")
        }
    }

    // MARK: - Asset names are non-empty

    @Test("all states have non-empty assetName")
    func assetNamesNonEmpty() {
        for state in PetState.allCases {
            #expect(!state.assetName.isEmpty, "assetName empty for \(state)")
        }
    }

    // MARK: - from(hookEventName:)

    @Test("from maps known hook events")
    func fromKnownEvents() {
        #expect(PetState.from(hookEventName: "SessionStart")        == .idle)
        #expect(PetState.from(hookEventName: "UserPromptSubmit")    == .thinking)
        #expect(PetState.from(hookEventName: "PreToolUse")          == .working)
        #expect(PetState.from(hookEventName: "PostToolUse")         == .working)
        #expect(PetState.from(hookEventName: "PostToolUseFailure")  == .error)
        #expect(PetState.from(hookEventName: "StopFailure")         == .error)
        #expect(PetState.from(hookEventName: "Stop")                == .attention)
        #expect(PetState.from(hookEventName: "Notification")        == .attention)
        #expect(PetState.from(hookEventName: "PostCompact")         == .attention)
        #expect(PetState.from(hookEventName: "PreCompact")          == .sweeping)
        #expect(PetState.from(hookEventName: "WorktreeCreate")      == .carrying)
    }

    @Test("from returns nil for unknown event names")
    func fromUnknown() {
        #expect(PetState.from(hookEventName: "Unknown")        == nil)
        #expect(PetState.from(hookEventName: "")               == nil)
        #expect(PetState.from(hookEventName: "SubagentStart")  == nil)
        #expect(PetState.from(hookEventName: "SubagentStop")   == nil)
        #expect(PetState.from(hookEventName: "SessionEnd")     == nil)
    }
}
