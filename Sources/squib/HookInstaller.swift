import Foundation

// Installs hook scripts and registers them with supported agents.
// Safe to call on every launch — idempotent.
final class HookInstaller {
    private static let squibDir    = URL.homeDirectory.appending(path: ".squib")
    private static let hooksDir    = squibDir.appending(path: "hooks")
    private static let pluginsDir  = squibDir.appending(path: "plugins")
    private static let scriptDest  = hooksDir.appending(path: "clawd-hook.js")
    private static let claudeSettings = URL.homeDirectory.appending(path: ".claude/settings.json")

    private static let hookedEvents = [
        "SessionStart", "SessionEnd", "UserPromptSubmit",
        "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "Stop", "StopFailure", "Notification",
        "PostCompact", "PreCompact",
        "SubagentStart", "SubagentStop",
        "Elicitation",
    ]

    static func installIfNeeded() {
        copyHookScript()
        registerClaudeHooks()
    }

    // MARK: - Script

    private static func copyHookScript() {
        guard let src = Bundle.module.url(forResource: "clawd-hook", withExtension: "js") else {
            print("[HookInstaller] clawd-hook.js not found in bundle")
            return
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        try? fm.removeItem(at: scriptDest)
        do {
            try fm.copyItem(at: src, to: scriptDest)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptDest.path)
        } catch {
            print("[HookInstaller] failed to copy hook script: \(error)")
        }
    }

    // MARK: - Claude Code settings.json

    private static func registerClaudeHooks() {
        let fm = FileManager.default
        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: claudeSettings.path),
           let data = try? Data(contentsOf: claudeSettings),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        }

        var hooks = settings["hooks"] as? [String: [[String: Any]]] ?? [:]
        let command = "node \(scriptDest.path)"

        for event in hookedEvents {
            var entries = hooks[event] ?? []
            // Only add if not already registered
            let alreadyAdded = entries.contains { entry in
                (entry["hooks"] as? [[String: Any]])?.contains { $0["command"] as? String == command } == true
            }
            if !alreadyAdded {
                entries.append([
                    "matcher": "",
                    "hooks": [["type": "command", "command": command]],
                ])
            }
            hooks[event] = entries
        }

        settings["hooks"] = hooks
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? fm.createDirectory(at: claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: claudeSettings)
            print("[HookInstaller] hooks registered in \(claudeSettings.path)")
        } catch {
            print("[HookInstaller] failed to write settings: \(error)")
        }
    }

    // MARK: - opencode plugin

    /// Copies the bundled opencode-plugin directory to ~/.squib/plugins/opencode-plugin/ and
    /// registers that stable path in ~/.config/opencode/opencode.json. Idempotent.
    /// Skips silently if ~/.config/opencode/ doesn't exist (opencode not installed).
    static func registerOpencodePlugin() {
        copyOpencodePlugin()
        registerInOpencodeConfig()
    }

    private static func copyOpencodePlugin() {
        // SPM's .process("Resources") flattens subdirectories to the bundle root.
        // opencode-plugin/index.mjs and opencode-plugin/package.json land at bundle root,
        // not inside an "opencode-plugin/" subdirectory.
        guard let resourcesURL = Bundle.module.resourceURL else {
            print("[HookInstaller] bundle resourceURL not found")
            return
        }
        let dstDir = pluginsDir.appending(path: "opencode-plugin")
        let fm = FileManager.default
        try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        for filename in ["index.mjs", "package.json"] {
            let src = resourcesURL.appending(path: filename)   // flat bundle root
            let dst = dstDir.appending(path: filename)
            try? fm.removeItem(at: dst)
            do {
                try fm.copyItem(at: src, to: dst)
            } catch {
                print("[HookInstaller] failed to copy \(filename): \(error)")
            }
        }
    }

    private static func registerInOpencodeConfig() {
        let opencodeConfigDir  = URL.homeDirectory.appending(path: ".config/opencode")
        let opencodeConfigFile = opencodeConfigDir.appending(path: "opencode.json")
        let pluginPath         = pluginsDir.appending(path: "opencode-plugin").path
        let fm = FileManager.default

        guard fm.fileExists(atPath: opencodeConfigDir.path) else {
            print("[HookInstaller] ~/.config/opencode/ not found — skipping opencode plugin")
            return
        }

        var settings: [String: Any] = [:]
        var created = false
        if fm.fileExists(atPath: opencodeConfigFile.path),
           let data   = try? Data(contentsOf: opencodeConfigFile),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        } else {
            settings = ["$schema": "https://opencode.ai/config.json"]
            created  = true
        }

        var plugins = settings["plugin"] as? [Any] ?? []

        // Idempotency: exact path match only.
        // A basename match would incorrectly match other plugins also named "opencode-plugin"
        // (e.g. the clawd-on-desk plugin at a different path).
        let alreadyRegistered = plugins.contains { ($0 as? String) == pluginPath }

        guard !alreadyRegistered else {
            print("[HookInstaller] opencode plugin already registered")
            return
        }

        plugins.append(pluginPath)
        settings["plugin"] = plugins
        guard let data = try? JSONSerialization.data(withJSONObject: settings,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        do {
            try data.write(to: opencodeConfigFile)
            print("[HookInstaller] opencode plugin registered\(created ? " (created opencode.json)" : "") → \(pluginPath)")
        } catch {
            print("[HookInstaller] failed to write opencode config: \(error)")
        }
    }

    // MARK: - Permission hook (HTTP, blocking)

    /// Upserts the PermissionRequest HTTP hook in settings.json pointing to squib's port.
    /// Must be called after the server port is known (i.e. from the NWListener ready callback).
    static func registerPermissionHook(port: UInt16) {
        let fm  = FileManager.default
        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: claudeSettings.path),
           let data   = try? Data(contentsOf: claudeSettings),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        }

        var hooks = settings["hooks"] as? [String: [[String: Any]]] ?? [:]
        hooks["PermissionRequest"] = [[
            "matcher": "",
            "hooks": [["type": "http", "url": "http://127.0.0.1:\(port)/permission", "timeout": 600]],
        ]]
        settings["hooks"] = hooks

        guard let data = try? JSONSerialization.data(withJSONObject: settings,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        do {
            try data.write(to: claudeSettings)
            print("[HookInstaller] PermissionRequest hook → port \(port)")
        } catch {
            print("[HookInstaller] failed to write PermissionRequest hook: \(error)")
        }
    }
}
