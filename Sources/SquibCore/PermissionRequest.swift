import Foundation

public struct PermissionRequest {
    public let id:            UUID
    public let sessionId:     String?
    public let toolName:      String
    public let toolInput:     String?           // serialised JSON fragment for display/elicitation
    public let cwd:           String?           // working directory path (for session folder label)
    public let suggestions:   [[String: Any]]   // may be empty; raw suggestion objects from Claude Code
    public let isElicitation: Bool

    public init(
        id:            UUID,
        sessionId:     String?,
        toolName:      String,
        toolInput:     String?,
        cwd:           String?,
        suggestions:   [[String: Any]],
        isElicitation: Bool
    ) {
        self.id            = id
        self.sessionId     = sessionId
        self.toolName      = toolName
        self.toolInput     = toolInput
        self.cwd           = cwd
        self.suggestions   = suggestions
        self.isElicitation = isElicitation
    }
}
