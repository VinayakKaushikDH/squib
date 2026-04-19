import Foundation

enum PetState: String, CaseIterable {
    case idle
    case thinking
    case working
    case error
    case attention
    case sleeping

    // Priority used in 1c when multiple sessions are active
    var priority: Int {
        switch self {
        case .error:     return 5
        case .attention: return 4
        case .working:   return 3
        case .thinking:  return 2
        case .idle:      return 1
        case .sleeping:  return 0
        }
    }

    var svgName: String { rawValue }

    static func from(hookEventName: String) -> PetState? {
        switch hookEventName {
        case "SessionStart":                        return .idle
        case "UserPromptSubmit":                    return .thinking
        case "PreToolUse", "PostToolUse":           return .working
        case "PostToolUseFailure", "StopFailure":   return .error
        case "Stop", "Notification", "PostCompact": return .attention
        default:                                    return nil
        }
    }
}
