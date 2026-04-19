import Foundation

struct PermissionRequest {
    let id:            UUID
    let sessionId:     String?
    let toolName:      String
    let toolInput:     String?           // serialised JSON fragment for display/elicitation
    let cwd:           String?           // working directory path (for session folder label)
    let suggestions:   [[String: Any]]   // may be empty; raw suggestion objects from Claude Code
    let isElicitation: Bool
}
