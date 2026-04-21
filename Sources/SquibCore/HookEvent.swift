import Foundation

/// Compile-time constants for hook event name strings.
/// Use these instead of raw string literals to catch typos at build time.
public enum HookEventName {
    public static let sessionStart        = "SessionStart"
    public static let sessionEnd          = "SessionEnd"
    public static let userPromptSubmit    = "UserPromptSubmit"
    public static let preToolUse          = "PreToolUse"
    public static let postToolUse         = "PostToolUse"
    public static let postToolUseFailure  = "PostToolUseFailure"
    public static let stop                = "Stop"
    public static let stopFailure         = "StopFailure"
    public static let notification        = "Notification"
    public static let postCompact         = "PostCompact"
    public static let preCompact          = "PreCompact"
    public static let subagentStart       = "SubagentStart"
    public static let subagentStop        = "SubagentStop"
    public static let worktreeCreate      = "WorktreeCreate"
    public static let elicitation         = "Elicitation"
    public static let permissionRequest   = "PermissionRequest"
}

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
