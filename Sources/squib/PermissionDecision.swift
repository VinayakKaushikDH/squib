import Foundation

/// The full decision returned to Claude Code when a user resolves a permission bubble.
enum PermissionDecision {
    case allow
    case deny
    /// User clicked a suggestion button — allow and apply the resolved permission rule.
    case allowWithPermissions(updatedPermissions: [[String: Any]])
    /// User submitted an elicitation form — allow and return answers merged into toolInput.
    case allowWithUpdatedInput(updatedInput: [String: Any])
}
