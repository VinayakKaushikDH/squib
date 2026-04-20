import Foundation

/// Pure JSONL parsing logic extracted from PiWatcher.
/// Stateless — call parseMessage for each line.
struct PiJSONLParser {

    /// Parses a single JSONL line from a pi-mono session file.
    /// Returns nil for non-message entries (session headers, labels, model_change, etc.)
    func parseMessage(_ json: String, sessionId: String) -> HookEvent? {
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Only handle message entries; skip session headers, model_change, label, etc.
        guard let type = obj["type"] as? String, type == "message" else { return nil }
        guard let role = obj["role"] as? String else { return nil }

        switch role {
        case "user":
            return HookEvent(hookEventName: "UserPromptSubmit", sessionId: sessionId, toolName: nil)

        case "assistant":
            let content    = obj["content"] as? [[String: Any]] ?? []
            let hasToolUse = content.contains { $0["type"] as? String == "tool_use" }
            // pi-mono follows Anthropic API format: snake_case stop_reason.
            // Guard with camelCase fallback in case the schema evolves.
            let stopReason = obj["stop_reason"] as? String
                          ?? obj["stopReason"] as? String
                          ?? ""

            if stopReason == "error" {
                return HookEvent(hookEventName: "PostToolUseFailure", sessionId: sessionId, toolName: nil)
            } else if hasToolUse || stopReason == "tool_use" {
                return HookEvent(hookEventName: "PreToolUse", sessionId: sessionId, toolName: nil)
            } else if stopReason == "end_turn" || stopReason == "stop_sequence" {
                return HookEvent(hookEventName: "Stop", sessionId: sessionId, toolName: nil)
            }
            return nil

        default:
            return nil
        }
    }
}
