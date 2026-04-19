import Foundation
import Network

final class HookServer {
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    // MARK: - Callbacks

    var onEvent:             ((HookEvent) -> Void)?
    /// Fired (on main thread) when the server is ready and the port is known.
    var onReady:             ((UInt16) -> Void)?
    /// Fired (on main thread) when a PermissionRequest arrives and the connection is held open.
    var onPermissionRequest: ((PermissionRequest) -> Void)?
    /// Fired (on main thread) when a held permission connection disconnects before the user decides.
    var onPermissionEvicted: ((UUID) -> Void)?

    // MARK: - Pending permissions

    private struct PermissionPending {
        let connection: NWConnection
        let request:    PermissionRequest
    }
    /// Keyed by PermissionRequest.id. Accessed on main thread only.
    private var pendingPermissions: [UUID: PermissionPending] = [:]

    // MARK: - Start

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params)

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state, let port = self.listener?.port?.rawValue {
                self.port = port
                self.writeConfig(port: port)
                print("[HookServer] listening on port \(port)")
                DispatchQueue.main.async { self.onReady?(port) }
            }
        }

        listener?.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }

        listener?.start(queue: .global(qos: .userInteractive))
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInteractive))
        accumulate(connection: connection, buffer: Data())
    }

    private func accumulate(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data, !data.isEmpty { buf.append(data) }

            if buf.count > 1_048_576 {
                self.reply(self.httpResponse(413, #"{"error":"payload too large"}"#), on: connection)
                return
            }

            switch self.tryParse(buf) {
            case .complete(let method, let path, let body):
                self.route(method: method, path: path, body: body, connection: connection)
            case .error(let response):
                self.reply(response, on: connection)
            case .incomplete:
                if !isComplete && error == nil {
                    self.accumulate(connection: connection, buffer: buf)
                } else {
                    connection.cancel()
                }
            }
        }
    }

    // MARK: - Parsing

    private enum ParseResult {
        case incomplete
        case complete(method: String, path: String, body: Data)
        case error(Data)
    }

    private func tryParse(_ data: Data) -> ParseResult {
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

    // MARK: - Routing

    private func route(method: String, path: String, body: Data, connection: NWConnection) {
        if method == "GET", path == "/health" {
            reply(httpResponse(200, #"{"ok":true}"#), on: connection)
            return
        }

        if method == "POST", path == "/state" {
            do {
                let event = try JSONDecoder().decode(HookEvent.self, from: body)
                DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
                reply(httpResponse(200, #"{"ok":true}"#), on: connection)
            } catch {
                reply(httpResponse(400, #"{"error":"invalid json"}"#), on: connection)
            }
            return
        }

        if method == "POST", path == "/permission" {
            handlePermission(body, connection: connection)
            return
        }

        reply(httpResponse(404, #"{"error":"not found"}"#), on: connection)
    }

    // MARK: - Permission handling

    private func handlePermission(_ body: Data, connection: NWConnection) {
        guard let request = parsePermissionPayload(body) else {
            reply(httpResponse(400, #"{"error":"invalid json"}"#), on: connection)
            return
        }

        let id = request.id

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                DispatchQueue.main.async { self?.evictPermission(id: id) }
            default:
                break
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingPermissions[id] = PermissionPending(connection: connection, request: request)
            self.onPermissionRequest?(request)
        }
    }

    private func parsePermissionPayload(_ data: Data) -> PermissionRequest? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let toolName      = obj["tool_name"]     as? String ?? "(unknown)"
        let sessionId     = obj["session_id"]    as? String
        let cwd           = obj["cwd"]           as? String
        let isElicitation = obj["isElicitation"] as? Bool ?? false
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

    // MARK: - Resolving permissions

    /// Sends the decision response and closes the held connection. Call from main thread.
    func resolvePermission(id: UUID, decision: PermissionDecision) {
        guard let pending = pendingPermissions.removeValue(forKey: id) else { return }
        let body = buildResponseBody(for: decision)
        reply(httpResponse(200, body), on: pending.connection)
    }

    /// Sends deny on all open permission connections. Call from applicationWillTerminate.
    func denyAllPending() {
        let snapshot = pendingPermissions
        pendingPermissions.removeAll()
        let body = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"squib is quitting"}}}"#
        for (_, p) in snapshot {
            reply(httpResponse(200, body), on: p.connection)
        }
    }

    private func buildResponseBody(for decision: PermissionDecision) -> String {
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

    private func evictPermission(id: UUID) {
        guard pendingPermissions.removeValue(forKey: id) != nil else { return }
        onPermissionEvicted?(id)
    }

    // MARK: - Helpers

    private func reply(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func httpResponse(_ status: Int, _ body: String) -> Data {
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

    private func writeConfig(port: UInt16) {
        let dir = URL.homeDirectory.appending(path: ".squib")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config: [String: UInt16] = ["port": port]
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: dir.appending(path: "server-config.json"))
        }
    }
}
