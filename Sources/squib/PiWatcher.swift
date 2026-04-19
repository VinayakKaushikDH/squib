import Foundation

// Watches ~/.pi/agent/sessions/*/*.jsonl for pi-mono session events.
//
// Strategy: 2-second polling timer (same pattern as StateEngine's stale eviction timer).
// Simpler and more robust than kqueue for a two-level directory tree of growing files.
//
// Directory layout (pi-mono session-manager.js):
//   ~/.pi/agent/sessions/<encoded-cwd>/<sessionId>.jsonl
//
// JSONL entry shapes relevant to squib:
//   { "type": "session",  "sessionId": "..." }         — header (first line)
//   { "type": "message",  "role": "user",   ... }       — user turn → thinking
//   { "type": "message",  "role": "assistant",           — assistant turn
//     "content": [{"type":"tool_use",...},...],          —   contains tool_use → working
//     "stop_reason": "end_turn"|"tool_use"|"error" }    —   stopReason drives state
//
// Session ID: derived from the filename (pi-mono names files <sessionId>.jsonl).

final class PiWatcher {
    var onEvent: ((HookEvent) -> Void)?

    private let sessionsRoot = URL.homeDirectory.appending(path: ".pi/agent/sessions")
    /// Tracks last-read byte offset per file path. Accessed on pollQueue only.
    private var fileOffsets: [String: Int] = [:]
    private var pollTimer:   Timer?
    private let pollQueue  = DispatchQueue(label: "squib.piwatcher", qos: .utility)

    // MARK: - Lifecycle

    func start() {
        guard FileManager.default.fileExists(atPath: sessionsRoot.path) else {
            print("[PiWatcher] ~/.pi/agent/sessions not found — skipping")
            return
        }
        // Initial scan on the poll queue, then schedule repeating timer.
        pollQueue.async { self.scan() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.pollQueue.async { self?.scan() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Scan

    private func scan() {
        let fm = FileManager.default
        guard let cwdDirs = try? fm.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return }

        for cwdDir in cwdDirs {
            guard (try? cwdDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            guard let jsonlFiles = try? fm.contentsOfDirectory(
                at: cwdDir,
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for file in jsonlFiles where file.pathExtension == "jsonl" {
                processFile(file, fm: fm)
            }
        }
    }

    private func processFile(_ url: URL, fm: FileManager) {
        let path      = url.path
        let sessionId = url.deletingPathExtension().lastPathComponent

        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let currentSize = attrs[.size] as? Int else { return }

        let lastOffset = fileOffsets[path]

        if lastOffset == nil {
            // New file — emit SessionStart.
            fileOffsets[path] = 0
            emit(HookEvent(hookEventName: "SessionStart", sessionId: sessionId, toolName: nil))
        }

        let offset = fileOffsets[path]!
        guard currentSize > offset else { return }

        // Read only the new bytes appended since last poll.
        guard let fh = FileHandle(forReadingAtPath: path) else { return }
        defer { try? fh.close() }
        try? fh.seek(toOffset: UInt64(offset))
        let newData = fh.readDataToEndOfFile()
        fileOffsets[path] = currentSize

        guard let text = String(data: newData, encoding: .utf8) else { return }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let event = parseMessage(trimmed, sessionId: sessionId) {
                emit(event)
            }
        }
    }

    // MARK: - JSONL parsing

    private func parseMessage(_ json: String, sessionId: String) -> HookEvent? {
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Only handle message entries; skip session headers, model_change, label, etc.
        guard let type = obj["type"] as? String, type == "message" else { return nil }
        guard let role = obj["role"] as? String else { return nil }

        switch role {
        case "user":
            return HookEvent(hookEventName: "UserPromptSubmit", sessionId: sessionId, toolName: nil)

        case "assistant":
            let content    = obj["content"] as? [[String: Any]] ?? []
            let hasToolUse = content.contains { $0["type"] as? String == "tool_use" }
            // pi-mono follows Anthropic API format: snake_case stop_reason.
            // Guard with camelCase fallback in case the schema evolves.
            let stopReason = obj["stop_reason"] as? String
                          ?? obj["stopReason"] as? String
                          ?? ""

            if stopReason == "error" {
                return HookEvent(hookEventName: "PostToolUseFailure", sessionId: sessionId, toolName: nil)
            } else if hasToolUse || stopReason == "tool_use" {
                return HookEvent(hookEventName: "PreToolUse", sessionId: sessionId, toolName: nil)
            } else if stopReason == "end_turn" || stopReason == "stop_sequence" {
                return HookEvent(hookEventName: "Stop", sessionId: sessionId, toolName: nil)
            }
            return nil

        default:
            return nil
        }
    }

    // MARK: - Dispatch

    private func emit(_ event: HookEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
}
