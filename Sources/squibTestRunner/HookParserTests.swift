import Testing
import Foundation
import SquibCore

@Suite("HookParser")
struct HookParserTests {
    let parser = HookParser()

    // MARK: - tryParse: incomplete

    @Test("returns incomplete for empty data")
    func incompleteEmpty() {
        let result = parser.tryParse(Data())
        if case .incomplete = result { } else { Issue.record("expected .incomplete") }
    }

    @Test("returns incomplete when header separator not yet received")
    func incompletePartialHeader() {
        let partial = Data("POST /state HTTP/1.1\r\nContent-Length: 5\r\n".utf8)
        let result = parser.tryParse(partial)
        if case .incomplete = result { } else { Issue.record("expected .incomplete") }
    }

    @Test("returns incomplete when body not fully received")
    func incompletePartialBody() {
        let req = Data("POST /state HTTP/1.1\r\nContent-Length: 10\r\n\r\nhello".utf8) // only 5 of 10
        let result = parser.tryParse(req)
        if case .incomplete = result { } else { Issue.record("expected .incomplete") }
    }

    // MARK: - tryParse: complete

    @Test("parses GET request with no body")
    func completeGet() {
        let raw = "GET /health HTTP/1.1\r\n\r\n"
        let result = parser.tryParse(Data(raw.utf8))
        guard case .complete(let method, let path, let body) = result else {
            Issue.record("expected .complete"); return
        }
        #expect(method == "GET")
        #expect(path   == "/health")
        #expect(body.isEmpty)
    }

    @Test("parses POST request with body")
    func completePost() {
        let bodyStr  = #"{"hook_event_name":"Stop"}"#
        let bodyData = Data(bodyStr.utf8)
        let raw = "POST /state HTTP/1.1\r\nContent-Length: \(bodyData.count)\r\n\r\n\(bodyStr)"
        let result = parser.tryParse(Data(raw.utf8))
        guard case .complete(let method, let path, let body) = result else {
            Issue.record("expected .complete"); return
        }
        #expect(method == "POST")
        #expect(path   == "/state")
        #expect(body   == bodyData)
    }

    @Test("header case-insensitive content-length")
    func caseInsensitiveContentLength() {
        let bodyStr = "hello"
        let raw = "POST /foo HTTP/1.1\r\nContent-Length: \(bodyStr.utf8.count)\r\n\r\n\(bodyStr)"
        let result = parser.tryParse(Data(raw.utf8))
        if case .complete(_, _, let body) = result {
            #expect(String(data: body, encoding: .utf8) == bodyStr)
        } else {
            Issue.record("expected .complete")
        }
    }

    // MARK: - parsePermissionPayload

    @Test("parses valid permission payload")
    func parseValidPermission() {
        let json = """
        {"tool_name":"Bash","session_id":"abc","cwd":"/tmp"}
        """
        let req = parser.parsePermissionPayload(Data(json.utf8))
        #expect(req != nil)
        #expect(req?.toolName   == "Bash")
        #expect(req?.sessionId  == "abc")
        #expect(req?.cwd        == "/tmp")
        #expect(req?.isElicitation == false)
    }

    @Test("returns nil for invalid JSON")
    func parseInvalidPermission() {
        let result = parser.parsePermissionPayload(Data("not json".utf8))
        #expect(result == nil)
    }

    @Test("missing tool_name uses (unknown) fallback")
    func missingToolName() {
        let json = #"{"session_id":"s1"}"#
        let req = parser.parsePermissionPayload(Data(json.utf8))
        #expect(req?.toolName == "(unknown)")
    }

    @Test("AskUserQuestion is detected as elicitation by tool name")
    func elicitationByToolName() {
        let json = #"{"tool_name":"AskUserQuestion"}"#
        let req = parser.parsePermissionPayload(Data(json.utf8))
        #expect(req?.isElicitation == true)
    }

    @Test("isElicitation flag in payload is respected")
    func elicitationByFlag() {
        let json = #"{"tool_name":"SomeTool","isElicitation":true}"#
        let req = parser.parsePermissionPayload(Data(json.utf8))
        #expect(req?.isElicitation == true)
    }

    @Test("tool_input is serialised to JSON string")
    func toolInputSerialized() {
        let json = #"{"tool_name":"Write","tool_input":{"path":"/tmp/x","content":"hi"}}"#
        let req = parser.parsePermissionPayload(Data(json.utf8))
        #expect(req?.toolInput != nil)
        if let ti = req?.toolInput, let data = ti.data(using: .utf8) {
            let parsed = try? JSONSerialization.jsonObject(with: data)
            #expect(parsed != nil)
        }
    }

    // MARK: - buildResponseBody

    @Test("allow decision serialises correctly")
    func buildAllow() {
        let body = parser.buildResponseBody(for: .allow)
        #expect(body.contains("\"behavior\":\"allow\""))
        #expect(body.contains("PermissionRequest"))
    }

    @Test("deny decision serialises correctly")
    func buildDeny() {
        let body = parser.buildResponseBody(for: .deny)
        #expect(body.contains("\"behavior\":\"deny\""))
        #expect(body.contains("PermissionRequest"))
    }

    @Test("allowWithUpdatedInput embeds input")
    func buildAllowWithInput() {
        let body = parser.buildResponseBody(for: .allowWithUpdatedInput(updatedInput: ["key": "val"]))
        #expect(body.contains("updatedInput"))
        #expect(body.contains("allow"))
    }

    @Test("allowWithPermissions embeds permissions")
    func buildAllowWithPermissions() {
        let perms: [[String: Any]] = [["type": "allow", "tools": "Bash"]]
        let body = parser.buildResponseBody(for: .allowWithPermissions(updatedPermissions: perms))
        #expect(body.contains("updatedPermissions"))
        #expect(body.contains("allow"))
    }

    // MARK: - httpResponse

    @Test("200 response has correct status line and body")
    func httpResponse200() {
        let data = parser.httpResponse(200, #"{"ok":true}"#)
        let str  = String(data: data, encoding: .utf8) ?? ""
        #expect(str.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(str.contains("Content-Type: application/json"))
        #expect(str.hasSuffix(#"{"ok":true}"#))
    }

    @Test("400 response has correct status text")
    func httpResponse400() {
        let data = parser.httpResponse(400, "{}")
        let str  = String(data: data, encoding: .utf8) ?? ""
        #expect(str.contains("400 Bad Request"))
    }

    @Test("Content-Length header matches body byte count")
    func contentLengthMatchesBody() {
        let body = "hello"
        let data = parser.httpResponse(200, body)
        let str  = String(data: data, encoding: .utf8) ?? ""
        #expect(str.contains("Content-Length: \(body.utf8.count)"))
    }
}
