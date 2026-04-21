import Foundation
import Network

public final class HookServer {
    private var listener: NWListener?
    public private(set) var port: UInt16 = 0
    private let parser = HookParser()

    // MARK: - Callbacks

    public var onEvent:             ((HookEvent) -> Void)?
    /// Fired (on main thread) when the server is ready and the port is known.
    public var onReady:             ((UInt16) -> Void)?
    /// Fired (on main thread) when a PermissionRequest arrives and the connection is held open.
    public var onPermissionRequest: ((PermissionRequest) -> Void)?
    /// Fired (on main thread) when a held permission connection disconnects before the user decides.
    public var onPermissionEvicted: ((UUID) -> Void)?

    // MARK: - Debug harness

    /// Enable /debug/* routes. Set to true in debug builds via AppDelegate.
    public var debugEnabled: Bool = false
    /// Returns a JSON string snapshot of current state. Wired by AppDelegate.
    public var debugStateSnapshot: (() -> String)?
    /// Called when POST /debug/reset arrives. Wired by AppDelegate.
    public var onDebugReset: (() -> Void)?

    public init() {}

    // MARK: - Pending permissions

    private struct PermissionPending {
        let connection: NWConnection
        let request:    PermissionRequest
    }
    /// Keyed by PermissionRequest.id. Accessed on main thread only.
    private var pendingPermissions: [UUID: PermissionPending] = [:]

    // MARK: - Start

    public func start() throws {
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
                self.reply(self.parser.httpResponse(413, #"{"error":"payload too large"}"#), on: connection)
                return
            }

            switch self.parser.tryParse(buf) {
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

    // MARK: - Routing

    private func route(method: String, path: String, body: Data, connection: NWConnection) {
        if method == "GET", path == "/health" {
            reply(parser.httpResponse(200, #"{"ok":true}"#), on: connection)
            return
        }

        if method == "POST", path == "/state" {
            do {
                let event = try JSONDecoder().decode(HookEvent.self, from: body)
                DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
                reply(parser.httpResponse(200, #"{"ok":true}"#), on: connection)
            } catch {
                reply(parser.httpResponse(400, #"{"error":"invalid json"}"#), on: connection)
            }
            return
        }

        if method == "POST", path == "/squib/permission" {
            handlePermission(body, connection: connection)
            return
        }

        if debugEnabled {
            if routeDebug(method: method, path: path, body: body, connection: connection) { return }
        }

        reply(parser.httpResponse(404, #"{"error":"not found"}"#), on: connection)
    }

    // MARK: - Debug routes

    /// Returns true if the request was handled by a debug route.
    private func routeDebug(method: String, path: String, body: Data, connection: NWConnection) -> Bool {
        if method == "GET", path == "/debug/state" {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let snapshot = self.debugStateSnapshot?() ?? "{}"
                self.reply(self.parser.httpResponse(200, snapshot), on: connection)
            }
            return true
        }

        if method == "POST", path == "/debug/inject" {
            do {
                let event = try JSONDecoder().decode(HookEvent.self, from: body)
                DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
                reply(parser.httpResponse(200, #"{"ok":true}"#), on: connection)
            } catch {
                reply(parser.httpResponse(400, #"{"error":"invalid json"}"#), on: connection)
            }
            return true
        }

        if method == "POST", path == "/debug/reset" {
            DispatchQueue.main.async { [weak self] in self?.onDebugReset?() }
            reply(parser.httpResponse(200, #"{"ok":true}"#), on: connection)
            return true
        }

        if method == "GET", path == "/debug/permissions" {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let ids = Array(self.pendingPermissions.keys.map(\.uuidString))
                let json = (try? JSONSerialization.data(withJSONObject: ["pending": ids]))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? #"{"pending":[]}"#
                self.reply(self.parser.httpResponse(200, json), on: connection)
            }
            return true
        }

        return false
    }

    // MARK: - Permission handling

    private func handlePermission(_ body: Data, connection: NWConnection) {
        guard let request = parser.parsePermissionPayload(body) else {
            reply(parser.httpResponse(400, #"{"error":"invalid json"}"#), on: connection)
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

    // MARK: - Resolving permissions

    /// Sends the decision response and closes the held connection. Call from main thread.
    public func resolvePermission(id: UUID, decision: PermissionDecision) {
        guard let pending = pendingPermissions.removeValue(forKey: id) else { return }
        let body = parser.buildResponseBody(for: decision)
        reply(parser.httpResponse(200, body), on: pending.connection)
    }

    /// Sends deny on all open permission connections. Call from applicationWillTerminate.
    public func denyAllPending() {
        let snapshot = pendingPermissions
        pendingPermissions.removeAll()
        let body = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"squib is quitting"}}}"#
        for (_, p) in snapshot {
            reply(parser.httpResponse(200, body), on: p.connection)
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

    private func writeConfig(port: UInt16) {
        let dir = URL.homeDirectory.appending(path: ".squib")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config: [String: UInt16] = ["port": port]
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: dir.appending(path: "server-config.json"))
        }
    }
}
