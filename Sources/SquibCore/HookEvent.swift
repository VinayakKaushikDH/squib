import Foundation

public struct HookEvent: Codable {
    public let hookEventName: String
    public let sessionId: String?
    public let toolName: String?

    public init(hookEventName: String, sessionId: String?, toolName: String?) {
        self.hookEventName = hookEventName
        self.sessionId     = sessionId
        self.toolName      = toolName
    }

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionId     = "session_id"
        case toolName      = "tool_name"
    }
}
