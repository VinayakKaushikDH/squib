import Foundation
import SquibCore

indirect enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self)            { self = .bool(v);   return }
        if let v = try? container.decode(Double.self)          { self = .number(v); return }
        if let v = try? container.decode(String.self)          { self = .string(v); return }
        if container.decodeNil()                               { self = .null;      return }
        if let v = try? container.decode([JSONValue].self)     { self = .array(v);  return }
        if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "unknown JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .null:          try container.encodeNil()
        case .array(let v):  try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    func toAny() -> Any {
        switch self {
        case .string(let v): return v
        case .number(let v): return v
        case .bool(let v):   return v
        case .null:          return NSNull()
        case .array(let v):  return v.map { $0.toAny() }
        case .object(let v): return v.mapValues { $0.toAny() }
        }
    }
}

struct Fixture: Codable {
    let id: String
    let toolName: String
    let toolInput: String?
    let cwd: String?
    let sessionId: String?
    let isElicitation: Bool
    let permissionSuggestions: [[String: JSONValue]]

    enum CodingKeys: String, CodingKey {
        case id
        case toolName              = "tool_name"
        case toolInput             = "tool_input"
        case cwd
        case sessionId             = "session_id"
        case isElicitation         = "is_elicitation"
        case permissionSuggestions = "permission_suggestions"
    }

    func toPermissionRequest() -> PermissionRequest {
        let suggestions: [[String: Any]] = permissionSuggestions.map { dict in
            dict.mapValues { $0.toAny() }
        }
        return PermissionRequest(
            id:            UUID(),
            sessionId:     sessionId,
            toolName:      toolName,
            toolInput:     toolInput,
            cwd:           cwd,
            suggestions:   suggestions,
            isElicitation: isElicitation
        )
    }
}

func loadFixtures(from dir: URL, id filterID: String?) throws -> [Fixture] {
    let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    return try urls.compactMap { url in
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        if let id = filterID, fixture.id != id { return nil }
        return fixture
    }
}
