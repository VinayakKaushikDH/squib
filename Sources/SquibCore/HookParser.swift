import Foundation

/// Pure HTTP parsing and permission payload parsing extracted from HookServer.
/// Struct with no state — all methods are deterministic functions of their inputs.
struct HookParser {

    // MARK: - HTTP parsing

    enum ParseResult {
        case incomplete
        case complete(method: String, path: String, body: Data)
        case error(Data)
    }

    func tryParse(_ data: Data) -> ParseResult {
        let sep = Data("\r\n\r\n".utf8)
        guard let sepRange = data.range(of: sep) else { return .incomplete }

        let headerBytes = data[..<sepRange.lowerBound]
        let bodyOffset  = sepRange.upperBound

        guard let headerStr = String(data: headerBytes, encoding: .utf8) else {
            return .error(httpResponse(400, #"{"error":"bad headers"}"#))
        }

        let lines    = headerStr.components(separatedBy: "\r\n")
        let reqParts = (lines.first ?? "").components(separatedBy: " ")
        guard reqParts.count >= 2 else {
            return .error(httpResponse(400, #"{"error":"bad request line"}"#))
        }

        let method = reqParts[0]
        let path   = reqParts[1]

        let contentLength: Int = lines.compactMap { line -> Int? in
            guard line.lowercased().hasPrefix("content-length:") else { return nil }
            return Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces))
        }.first ?? 0

        let bodySlice = data[bodyOffset...]
        guard bodySlice.count >= contentLength else { return .incomplete }

        return .complete(method: method, path: path, body: Data(bodySlice.prefix(contentLength)))
    }

    // MARK: - Permission payload parsing

    func parsePermissionPayload(_ data: Data) -> PermissionRequest? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let toolName      = obj["tool_name"]     as? String ?? "(unknown)"
        let sessionId     = obj["session_id"]    as? String
        let cwd           = obj["cwd"]           as? String
        let isElicitation = toolName == "AskUserQuestion"
            || (obj["isElicitation"] as? NSNumber)?.boolValue ?? false
        let suggestions   = obj["suggestions"]   as? [[String: Any]] ?? []

        var toolInput: String? = nil
        if let input = obj["tool_input"] {
            toolInput = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]))
                .flatMap { String(data: $0, encoding: .utf8) }
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

    // MARK: - Decision response serialisation

    func buildResponseBody(for decision: PermissionDecision) -> String {
        let hookName = "PermissionRequest"
        switch decision {
        case .allow:
            return #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        case .deny:
            return #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}"#
        case .allowWithPermissions(let perms):
            let inner: [String: Any] = ["behavior": "allow", "updatedPermissions": perms]
            let outer: [String: Any] = ["hookSpecificOutput": ["hookEventName": hookName, "decision": inner]]
            if let data = try? JSONSerialization.data(withJSONObject: outer),
               let str  = String(data: data, encoding: .utf8) { return str }
            return #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        case .allowWithUpdatedInput(let input):
            let inner: [String: Any] = ["behavior": "allow", "updatedInput": input]
            let outer: [String: Any] = ["hookSpecificOutput": ["hookEventName": hookName, "decision": inner]]
            if let data = try? JSONSerialization.data(withJSONObject: outer),
               let str  = String(data: data, encoding: .utf8) { return str }
            return #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        }
    }

    // MARK: - HTTP response helper (shared with HookServer via this struct)

    func httpResponse(_ status: Int, _ body: String) -> Data {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status) \(statusText(status))\r\n" +
                     "Content-Type: application/json\r\n" +
                     "Content-Length: \(bodyData.count)\r\n" +
                     "Connection: close\r\n\r\n"
        return Data(header.utf8) + bodyData
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        default:  return "Unknown"
        }
    }
}
