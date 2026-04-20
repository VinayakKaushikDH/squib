import Foundation

public enum PetState: String, CaseIterable {
    case idle
    case thinking
    case working
    case building
    case juggling
    case conducting
    case error
    case attention
    case notification
    case sweeping
    case carrying
    case sleeping

    public var priority: Int {
        switch self {
        case .error:        return 9
        case .notification: return 8
        case .conducting:   return 7
        case .juggling:     return 6
        case .attention:    return 5
        case .building:     return 4
        case .working:      return 3
        case .sweeping:     return 2
        case .carrying:     return 2
        case .thinking:     return 1
        case .idle:         return 1
        case .sleeping:     return 0
        }
    }

    /// File name without extension. Pair with `assetExtension`.
    public var assetName: String {
        switch self {
        case .idle:         return "clawd-idle-follow"   // SVG with eye tracking
        case .thinking:     return "clawd-thinking"
        case .working:      return "clawd-typing"
        case .building:     return "clawd-building"
        case .juggling:     return "clawd-juggling"
        case .conducting:   return "clawd-conducting"
        case .error:        return "clawd-error"
        case .attention:    return "clawd-happy"
        case .notification: return "clawd-notification"
        case .sweeping:     return "clawd-sweeping"
        case .carrying:     return "clawd-carrying"
        case .sleeping:     return "clawd-sleeping"    // SVG: sploot + floating Zzz
        }
    }

    /// Idle and sleeping use SVGs (CSS animations + eye tracking for idle).
    /// All other states use GIFs.
    public var assetExtension: String {
        switch self {
        case .idle, .sleeping: return "svg"
        default:               return "gif"
        }
    }

    /// Only the idle SVG has #eyes-js for cursor following.
    public var supportsEyeTracking: Bool { self == .idle }

    /// Maps a hook event name to a state. PreToolUse/PostToolUse may be upgraded
    /// to .building by StateEngine based on active session count.
    /// SubagentStart/Stop and PermissionRequest are handled directly in StateEngine.
    public static func from(hookEventName: String) -> PetState? {
        switch hookEventName {
        case "SessionStart":                        return .idle
        case "UserPromptSubmit":                    return .thinking
        case "PreToolUse", "PostToolUse":           return .working
        case "PostToolUseFailure", "StopFailure":   return .error
        case "Stop", "Notification", "PostCompact": return .attention
        case "PreCompact":                          return .sweeping
        case "WorktreeCreate":                      return .carrying
        default:                                    return nil
        }
    }
}
