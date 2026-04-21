import Foundation
import SquibCore

// Installs hook scripts and registers them with supported agents.
// Safe to call on every launch — idempotent.
final class HookInstaller {
    private static let squibDir    = URL.homeDirectory.appending(path: ".squib")
    private static let hooksDir    = squibDir.appending(path: "hooks")
    private static let pluginsDir  = squibDir.appending(path: "plugins")
    private static let scriptDest  = hooksDir.appending(path: "clawd-hook.js")
    private static let claudeSettings = URL.homeDirectory.appending(path: ".claude/settings.json")

    private static let hookedEvents = [
        HookEventName.sessionStart,
        HookEventName.sessionEnd,
        HookEventName.userPromptSubmit,
        HookEventName.preToolUse,
        HookEventName.postToolUse,
        HookEventName.postToolUseFailure,
        HookEventName.stop,
        HookEventName.stopFailure,
        HookEventName.notification,
        HookEventName.postCompact,
        HookEventName.preCompact,
        HookEventName.subagentStart,
        HookEventName.subagentStop,
        HookEventName.worktreeCreate,
        HookEventName.elicitation,
    ]

    /// Copies the hook script to ~/.squib/hooks/. Call at launch before the server starts.
    static func installIfNeeded() {
        copyHookScript()
    }

    /// Registers all Claude Code hooks (event hooks + permission hook) in a single
    /// settings.json write. Call from the HookServer onReady callback once the port is known.
    static func registerClaudeHooks(port: UInt16) {
        let fm = FileManager.default
        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: claudeSettings.path),
           let data = try? Data(contentsOf: claudeSettings),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        }

        var hooks = settings["hooks"] as? [String: [[String: Any]]] ?? [:]
        let command = "node \(scriptDest.path)"

        // Event hooks (fire-and-forget command)
        for event in hookedEvents {
            var entries = hooks[event] ?? []
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

        // Permission hook (blocking HTTP).
        // Filter out any existing squib entry (identified by the /squib/permission path on
        // localhost) so we replace the stale port from the previous launch without clobbering
        // entries registered by other tools.
        let permissionURL = "http://127.0.0.1:\(port)/squib/permission"
        var permEntries = hooks[HookEventName.permissionRequest] ?? []
        permEntries = permEntries.filter { entry in
            let entryHooks = entry["hooks"] as? [[String: Any]] ?? []
            return !entryHooks.contains { hook in
                guard let url = hook["url"] as? String else { return false }
                return url.contains("127.0.0.1") && url.hasSuffix("/squib/permission")
            }
        }
        permEntries.append([
            "matcher": "",
            "hooks": [["type": "http", "url": permissionURL, "timeout": 600]],
        ])
        hooks[HookEventName.permissionRequest] = permEntries

        settings["hooks"] = hooks
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? fm.createDirectory(at: claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: claudeSettings)
            print("[HookInstaller] Claude hooks registered (port \(port))")
        } catch {
            print("[HookInstaller] failed to write settings: \(error)")
        }
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

}
