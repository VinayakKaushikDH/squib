import Testing
import Foundation
import SquibCore

@Suite("HookServer Integration", .serialized)
struct HookServerIntegrationTests {

    // MARK: - Helpers

    func startServer() async throws -> (HookServer, UInt16) {
        let server = HookServer()
        return try await withCheckedThrowingContinuation { cont in
            var resumed = false
            server.onReady = { port in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: (server, port))
            }
            do { try server.start() }
            catch { cont.resume(throwing: error) }
        }
    }

    func post(_ path: String, body: String, port: UInt16) async throws -> (Data, Int) {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        req.httpMethod = "POST"
        req.httpBody = Data(body.utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as! HTTPURLResponse).statusCode)
    }

    func get(_ path: String, port: UInt16) async throws -> (Data, Int) {
        let (data, resp) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        return (data, (resp as! HTTPURLResponse).statusCode)
    }

    /// Polls every 20ms until condition is true or timeout expires.
    func waitFor(_ condition: @escaping () -> Bool, timeout: Double = 2.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    // MARK: - Health

    @Test("GET /health returns 200")
    func healthCheck() async throws {
        let (_, port) = try await startServer()
        let (data, status) = try await get("/health", port: port)
        #expect(status == 200)
        #expect(String(data: data, encoding: .utf8)?.contains("ok") == true)
    }

    // MARK: - /state route

    @Test("POST /state with valid event fires onEvent and returns 200")
    func postStateFiresEvent() async throws {
        let (server, port) = try await startServer()
        var received: HookEvent?
        server.onEvent = { received = $0 }

        // HookEvent CodingKeys use snake_case (hook_event_name, session_id)
        let (_, status) = try await post(
            "/state",
            body: #"{"hook_event_name":"UserPromptSubmit","session_id":"s1"}"#,
            port: port)
        #expect(status == 200)

        // Match by session_id so real Claude Code hooks on the same port don't cause false positives
        let fired = await waitFor { received?.sessionId == "s1" }
        #expect(fired, "onEvent callback did not fire")
        #expect(received?.hookEventName == "UserPromptSubmit")
    }

    @Test("POST /state with invalid JSON returns 400")
    func postStateBadJson() async throws {
        let (_, port) = try await startServer()
        let (_, status) = try await post("/state", body: "not json", port: port)
        #expect(status == 400)
    }

    @Test("POST /state drives StateEngine transitions")
    func postStateIntegratesWithStateEngine() async throws {
        let (server, port) = try await startServer()
        let engine = StateEngine()
        server.onEvent = { engine.handle($0) }

        _ = try await post(
            "/state",
            body: #"{"hook_event_name":"UserPromptSubmit","session_id":"s1"}"#,
            port: port)

        let transitioned = await waitFor { engine.currentState == .thinking }
        #expect(transitioned, "StateEngine did not transition to .thinking")
    }

    // MARK: - Unknown route

    @Test("unknown route returns 404")
    func unknownRoute() async throws {
        let (_, port) = try await startServer()
        let (_, status) = try await get("/unknown", port: port)
        #expect(status == 404)
    }

    // MARK: - Debug routes

    @Test("GET /debug/state returns debugStateSnapshot output")
    func debugStateEndpoint() async throws {
        let (server, port) = try await startServer()
        server.debugEnabled = true
        server.debugStateSnapshot = { #"{"state":"idle"}"# }

        let (data, status) = try await get("/debug/state", port: port)
        #expect(status == 200)
        #expect(String(data: data, encoding: .utf8)?.contains("idle") == true)
    }

    @Test("POST /debug/inject fires onEvent")
    func debugInjectFiresEvent() async throws {
        let (server, port) = try await startServer()
        server.debugEnabled = true
        var received: HookEvent?
        server.onEvent = { received = $0 }

        _ = try await post(
            "/debug/inject",
            body: #"{"hook_event_name":"PreToolUse","session_id":"s1"}"#,
            port: port)

        let fired = await waitFor { received?.sessionId == "s1" }
        #expect(fired, "onEvent did not fire from /debug/inject")
        #expect(received?.hookEventName == "PreToolUse")
    }

    @Test("POST /debug/reset calls onDebugReset")
    func debugReset() async throws {
        let (server, port) = try await startServer()
        server.debugEnabled = true
        var resetCalled = false
        server.onDebugReset = { resetCalled = true }

        _ = try await post("/debug/reset", body: "{}", port: port)

        let called = await waitFor { resetCalled }
        #expect(called, "onDebugReset was not called")
    }

    @Test("debug routes return 404 when debugEnabled is false")
    func debugRoutesDisabledByDefault() async throws {
        let (server, port) = try await startServer()
        // debugEnabled defaults to false
        _ = server
        let (_, status) = try await get("/debug/state", port: port)
        #expect(status == 404)
    }
}
