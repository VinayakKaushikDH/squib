import Foundation

/// Pure JSONL parsing logic extracted from PiWatcher.
/// Stateless — call parseMessage for each line.
public struct PiJSONLParser {

    public init() {}

    /// Parses a single JSONL line from a pi-mono session file.
    ///
    /// Pi-mono JSONL format (as of v3):
    ///   message entry:    { "type": "message", "message": { "role": ..., "content": [...], "stopReason": ... } }
    ///   compaction entry: { "type": "compaction", ... }
    ///
    /// Content block tool-call type: "toolCall" (not Anthropic's "tool_use").
    /// Stop reasons: "stop", "toolUse", "error", "aborted", "length".
    public func parseMessage(_ json: String, sessionId: String) -> HookEvent? {
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let type = obj["type"] as? String else { return nil }

        // Compaction entries → PostCompact
        if type == "compaction" {
            return HookEvent(hookEventName: "PostCompact", sessionId: sessionId, toolName: nil)
        }

        // Only handle message entries; skip session headers, model_change, label, etc.
        // Pi-mono nests the message payload inside a "message" key.
        guard type == "message",
              let msg  = obj["message"] as? [String: Any],
              let role = msg["role"] as? String
        else { return nil }

        switch role {
        case "user":
            return HookEvent(hookEventName: "UserPromptSubmit", sessionId: sessionId, toolName: nil)

        case "assistant":
            let content    = msg["content"] as? [[String: Any]] ?? []
            let hasToolUse = content.contains { $0["type"] as? String == "toolCall" }
            let stopReason = msg["stopReason"] as? String ?? ""

            if stopReason == "error" {
                return HookEvent(hookEventName: "PostToolUseFailure", sessionId: sessionId, toolName: nil)
            } else if hasToolUse || stopReason == "toolUse" {
                return HookEvent(hookEventName: "PreToolUse", sessionId: sessionId, toolName: nil)
            } else if stopReason == "stop" || stopReason == "aborted" {
                return HookEvent(hookEventName: "Stop", sessionId: sessionId, toolName: nil)
            }
            return nil

        default:
            return nil
        }
    }
}
