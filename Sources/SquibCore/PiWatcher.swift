import Foundation

// Watches ~/.pi/agent/sessions/*/*.jsonl for pi-mono session events.
//
// Strategy: 2-second polling timer (same pattern as StateEngine's stale eviction timer).
// Simpler and more robust than kqueue for a two-level directory tree of growing files.
//
// Directory layout (pi-mono session-manager.js):
//   ~/.pi/agent/sessions/<encoded-cwd>/<sessionId>.jsonl
//
// Session ID: derived from the filename (pi-mono names files <sessionId>.jsonl).

public final class PiWatcher {
    public var onEvent: ((HookEvent) -> Void)?

    private let sessionsRoot:  URL
    private let pollInterval:  TimeInterval
    /// Tracks last-read byte offset per file path. Accessed on pollQueue only.
    private var fileOffsets: [String: Int] = [:]
    private var pollTimer:   Timer?
    private let pollQueue  = DispatchQueue(label: "squib.piwatcher", qos: .utility)
    private let parser     = PiJSONLParser()

    public init(
        sessionsRoot: URL = URL.homeDirectory.appending(path: ".pi/agent/sessions"),
        pollInterval: TimeInterval = 2
    ) {
        self.sessionsRoot = sessionsRoot
        self.pollInterval = pollInterval
    }

    // MARK: - Lifecycle

    public func start() {
        guard FileManager.default.fileExists(atPath: sessionsRoot.path) else {
            print("[PiWatcher] ~/.pi/agent/sessions not found — skipping")
            return
        }
        // Seed pre-existing files to their current size so we don't replay history
        // from sessions that ended before squib started. Files created after start()
        // are genuinely new and will be processed from byte 0 on first sight.
        pollQueue.async { self.seedExistingFiles() }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollQueue.async { self?.scan() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Records current file sizes for all pre-existing JSONL files without emitting events.
    private func seedExistingFiles() {
        let fm = FileManager.default
        guard let cwdDirs = try? fm.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return }
        for cwdDir in cwdDirs {
            guard (try? cwdDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard let files = try? fm.contentsOfDirectory(
                at: cwdDir,
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let path = file.path
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let size = attrs[.size] as? Int {
                    fileOffsets[path] = size
                }
            }
        }
    }

    public func stop() {
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
            // Truly new file (created after squib started) — emit SessionStart and
            // process from byte 0. Pre-existing files are seeded in seedExistingFiles()
            // so they never reach this branch.
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
            if let event = parser.parseMessage(trimmed, sessionId: sessionId) {
                emit(event)
            }
        }
    }

    // MARK: - Dispatch

    private func emit(_ event: HookEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
}
