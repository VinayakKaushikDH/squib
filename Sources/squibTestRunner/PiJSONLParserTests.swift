import Testing
import SquibCore

@Suite("PiJSONLParser")
struct PiJSONLParserTests {
    let parser = PiJSONLParser()
    let sessionId = "test-session"

    // MARK: - Non-message entries

    @Test("non-message type returns nil")
    func nonMessageType() {
        let json = #"{"type":"session","id":"abc","timestamp":1}"#
        #expect(parser.parseMessage(json, sessionId: sessionId) == nil)
    }

    @Test("missing type field returns nil")
    func missingType() {
        let json = #"{"message":{"role":"user"}}"#
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

    @Test("model_change entry returns nil")
    func modelChangeEntry() {
        let json = #"{"type":"model_change","modelId":"claude-3"}"#
        #expect(parser.parseMessage(json, sessionId: sessionId) == nil)
    }

    // MARK: - Compaction

    @Test("compaction entry maps to PostCompact")
    func compactionEntry() {
        let json = #"{"type":"compaction","id":"c1","parentId":"c0","timestamp":1,"summary":"...","firstKeptEntryId":"e5","tokensBefore":5000}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "PostCompact")
        #expect(event?.sessionId    == sessionId)
    }

    // MARK: - User messages

    @Test("user message maps to UserPromptSubmit")
    func userMessage() {
        // Pi-mono nests message payload under "message" key
        let json = #"{"type":"message","id":"m1","parentId":"m0","timestamp":1,"message":{"role":"user","content":[{"type":"text","text":"hello"}],"timestamp":1}}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "UserPromptSubmit")
        #expect(event?.sessionId    == sessionId)
    }

    // MARK: - Assistant messages

    @Test("assistant with toolCall content maps to PreToolUse")
    func assistantWithToolCall() {
        let json = #"{"type":"message","id":"m2","parentId":"m1","timestamp":1,"message":{"role":"assistant","content":[{"type":"toolCall","id":"t1","name":"Bash","input":{}}],"stopReason":"toolUse","timestamp":1}}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "PreToolUse")
    }

    @Test("assistant stopReason=toolUse without content block maps to PreToolUse")
    func assistantStopReasonToolUse() {
        let json = #"{"type":"message","id":"m2","parentId":"m1","timestamp":1,"message":{"role":"assistant","content":[],"stopReason":"toolUse","timestamp":1}}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "PreToolUse")
    }

    @Test("assistant stopReason=stop maps to Stop")
    func assistantStop() {
        let json = #"{"type":"message","id":"m3","parentId":"m2","timestamp":1,"message":{"role":"assistant","content":[],"stopReason":"stop","timestamp":1}}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "Stop")
    }

    @Test("assistant stopReason=aborted maps to Stop")
    func assistantAborted() {
        let json = #"{"type":"message","id":"m3","parentId":"m2","timestamp":1,"message":{"role":"assistant","content":[],"stopReason":"aborted","timestamp":1}}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "Stop")
    }

    @Test("assistant stopReason=error maps to PostToolUseFailure")
    func assistantError() {
        let json = #"{"type":"message","id":"m4","parentId":"m3","timestamp":1,"message":{"role":"assistant","content":[],"stopReason":"error","timestamp":1}}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event?.hookEventName == "PostToolUseFailure")
    }

    @Test("assistant with no stopReason and no toolCall returns nil")
    func assistantNoStopReason() {
        let json = #"{"type":"message","id":"m5","parentId":"m4","timestamp":1,"message":{"role":"assistant","content":[],"timestamp":1}}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event == nil)
    }

    @Test("assistant stopReason=length returns nil")
    func assistantLength() {
        let json = #"{"type":"message","id":"m6","parentId":"m5","timestamp":1,"message":{"role":"assistant","content":[],"stopReason":"length","timestamp":1}}"#
        let event = parser.parseMessage(json, sessionId: sessionId)
        #expect(event == nil)
    }

    @Test("toolResult role returns nil")
    func toolResultRole() {
        let json = #"{"type":"message","id":"m7","parentId":"m6","timestamp":1,"message":{"role":"toolResult","content":[],"timestamp":1}}"#
        #expect(parser.parseMessage(json, sessionId: sessionId) == nil)
    }

    // MARK: - sessionId is passed through

    @Test("sessionId is preserved on all events")
    func sessionIdPreserved() {
        let id = "my-unique-id"
        let json = #"{"type":"message","id":"m1","parentId":"m0","timestamp":1,"message":{"role":"user","content":[],"timestamp":1}}"#
        let event = parser.parseMessage(json, sessionId: id)
        #expect(event?.sessionId == id)
    }

    // MARK: - Old flat format is rejected

    @Test("flat format (old assumption) does not parse — role must be nested under message key")
    func flatFormatRejected() {
        // Previously we assumed {"type":"message","role":"user",...} — that's wrong.
        // Pi-mono wraps the payload in a "message" key.
        let json = #"{"type":"message","role":"user","content":"hello"}"#
        #expect(parser.parseMessage(json, sessionId: sessionId) == nil)
    }
}
