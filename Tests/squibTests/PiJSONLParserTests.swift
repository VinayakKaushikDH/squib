import Testing
@testable import SquibCore

@Suite("PiJSONLParser")
struct PiJSONLParserTests {
    let parser = PiJSONLParser()
    let sessionId = "test-session"

    // MARK: - Non-message entries

    @Test("non-message type returns nil")
    func nonMessageType() {
        let json = #"{"type":"session","data":{}}"#
        #expect(parser.parseMessage(json, sessionId: sessionId) == nil)
    }

    @Test("missing type field returns nil")
    func missingType() {
        let json = #"{"role":"user","content":"hello"}"#
        #expect(parser.parseMessage(json, sessionId: sessionId) == nil)
    }

    @Test("invalid JSON returns nil")
    func invalidJSON() {
        #expect(parser.parseMessage("not json", sessionId: sessionId) == nil)
    }

    @Test("label entry returns nil")
    func labelEntry() {
        let json = #"{"type":"label","label":"test"}"#
        #expect(parser.parseMessage(json, sessionId: sessionId) == nil)
    }

    // MARK: - User messages

    @Test("user message maps to UserPromptSubmit")
    func userMessage() {
        let json = #"{"type":"message","role":"user","content":"hello"}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "UserPromptSubmit")
        #expect(event?.sessionId    == sessionId)
    }

    // MARK: - Assistant messages

    @Test("assistant with tool_use content maps to PreToolUse")
    func assistantWithToolUse() {
        let json = #"""
        {"type":"message","role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}],"stop_reason":"tool_use"}
        """#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "PreToolUse")
    }

    @Test("assistant stop_reason=tool_use without content block maps to PreToolUse")
    func assistantStopReasonToolUse() {
        let json = #"{"type":"message","role":"assistant","content":[],"stop_reason":"tool_use"}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "PreToolUse")
    }

    @Test("assistant stop_reason=end_turn maps to Stop")
    func assistantEndTurn() {
        let json = #"{"type":"message","role":"assistant","content":[],"stop_reason":"end_turn"}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "Stop")
    }

    @Test("assistant stop_reason=stop_sequence maps to Stop")
    func assistantStopSequence() {
        let json = #"{"type":"message","role":"assistant","content":[],"stop_reason":"stop_sequence"}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "Stop")
    }

    @Test("assistant stop_reason=error maps to PostToolUseFailure")
    func assistantError() {
        let json = #"{"type":"message","role":"assistant","content":[],"stop_reason":"error"}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "PostToolUseFailure")
    }

    @Test("assistant with no stop_reason and no tool_use returns nil")
    func assistantNoStopReason() {
        let json = #"{"type":"message","role":"assistant","content":[]}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event == nil)
    }

    @Test("unknown role returns nil")
    func unknownRole() {
        let json = #"{"type":"message","role":"system","content":"setup"}"#
        #expect(parser.parseMessage(json, sessionId: sessionId) == nil)
    }

    // MARK: - sessionId is passed through

    @Test("sessionId is preserved on all events")
    func sessionIdPreserved() {
        let id = "my-unique-id"
        let json = #"{"type":"message","role":"user","content":"x"}"#
        let event = parser.parseMessage(json, sessionId: id)
        #expect(event?.sessionId == id)
    }

    // MARK: - camelCase stop_reason fallback

    @Test("camelCase stopReason fallback works")
    func camelCaseStopReason() {
        let json = #"{"type":"message","role":"assistant","content":[],"stopReason":"end_turn"}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "Stop")
    }
}
