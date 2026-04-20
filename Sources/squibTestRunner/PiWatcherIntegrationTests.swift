import Testing
import Foundation
import SquibCore

@Suite("PiWatcher Integration")
struct PiWatcherIntegrationTests {

    // MARK: - Helpers

    struct TempSession {
        let root:   URL
        let cwdDir: URL

        func makeJsonlFile(sessionId: String = "test-session") throws -> URL {
            let file = cwdDir.appendingPathComponent("\(sessionId).jsonl")
            try "".write(to: file, atomically: true, encoding: .utf8)
            return file
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    func makeTempRoot() throws -> TempSession {
        let root   = FileManager.default.temporaryDirectory
            .appendingPathComponent("squib-pitest-\(UUID().uuidString)")
        let cwdDir = root.appendingPathComponent("my-project")
        try FileManager.default.createDirectory(at: cwdDir, withIntermediateDirectories: true)
        return TempSession(root: root, cwdDir: cwdDir)
    }

    func append(_ line: String, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
        try? handle.close()
    }

    /// Polls every 20ms until condition is true or timeout expires.
    func waitFor(_ condition: @escaping () -> Bool, timeout: Double = 3.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    // MARK: - Tests

    @Test("new JSONL file triggers SessionStart event")
    func detectsNewFile() async throws {
        let tmp = try makeTempRoot()
        defer { tmp.cleanup() }

        _ = try tmp.makeJsonlFile(sessionId: "s1")

        let watcher = PiWatcher(sessionsRoot: tmp.root, pollInterval: 0.05)
        var events: [HookEvent] = []
        watcher.onEvent = { events.append($0) }
        watcher.start()
        defer { watcher.stop() }

        let got = await waitFor { events.contains { $0.hookEventName == "SessionStart" } }
        #expect(got, "SessionStart not emitted for new file")
        #expect(events.first(where: { $0.hookEventName == "SessionStart" })?.sessionId == "s1")
    }

    @Test("JSONL message lines are parsed and emitted")
    func parsesJsonlLines() async throws {
        let tmp = try makeTempRoot()
        defer { tmp.cleanup() }

        let file = try tmp.makeJsonlFile(sessionId: "s2")
        try append(#"{"type":"message","role":"user","content":"hello"}"#, to: file)

        let watcher = PiWatcher(sessionsRoot: tmp.root, pollInterval: 0.05)
        var events: [HookEvent] = []
        watcher.onEvent = { events.append($0) }
        watcher.start()
        defer { watcher.stop() }

        let got = await waitFor { events.contains { $0.hookEventName == "UserPromptSubmit" } }
        #expect(got, "UserPromptSubmit not emitted for user message")
    }

    @Test("lines appended after first poll are picked up on next poll")
    func appendedLinesPicked() async throws {
        let tmp = try makeTempRoot()
        defer { tmp.cleanup() }

        let file = try tmp.makeJsonlFile(sessionId: "s3")

        let watcher = PiWatcher(sessionsRoot: tmp.root, pollInterval: 0.05)
        var events: [HookEvent] = []
        watcher.onEvent = { events.append($0) }
        watcher.start()
        defer { watcher.stop() }

        // Wait for the initial scan to record the empty file offset
        let sessionStarted = await waitFor { events.contains { $0.hookEventName == "SessionStart" } }
        #expect(sessionStarted, "SessionStart not fired for initial file")

        // Now append a message line
        try append(#"{"type":"message","role":"user","content":"hi"}"#, to: file)

        let got = await waitFor { events.contains { $0.hookEventName == "UserPromptSubmit" } }
        #expect(got, "UserPromptSubmit not picked up after appending a line")
    }

    @Test("non-.jsonl files in the session directory are ignored")
    func nonJsonlIgnored() async throws {
        let tmp = try makeTempRoot()
        defer { tmp.cleanup() }

        // Write a .txt file with message-like content — should be invisible to the watcher
        let txtFile = tmp.cwdDir.appendingPathComponent("session.txt")
        try #"{"type":"message","role":"user","content":"hi"}"#
            .write(to: txtFile, atomically: true, encoding: .utf8)

        let watcher = PiWatcher(sessionsRoot: tmp.root, pollInterval: 0.05)
        var events: [HookEvent] = []
        watcher.onEvent = { events.append($0) }
        watcher.start()
        defer { watcher.stop() }

        // Run for several poll cycles
        try? await Task.sleep(nanoseconds: 400_000_000) // 400ms ≈ 8 polls
        #expect(events.isEmpty, "unexpected events for non-.jsonl file: \(events.map(\.hookEventName))")
    }
}
