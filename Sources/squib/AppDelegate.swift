import AppKit
import SquibCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindow:     PetWindow?
    private let stateEngine   = StateEngine()
    private let hookServer    = HookServer()
    private let bubbleManager = BubbleManager()
    private let piWatcher     = PiWatcher()
    private var trayMenu:      TrayMenu?

    /// Maps session ID → pending permission UUID so we can auto-dismiss when
    /// Claude Code resolves the permission in its own UI (PostToolUse fires
    /// before we get a connection-close event).
    private var pendingPermissionsBySession: [String: UUID] = [:]
    /// Sessions for which the user has chosen "Allow Session" — future
    /// permission requests from these sessions are approved immediately.
    private var trustedSessions: Set<String> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Global key monitor requires Accessibility permission.
        // Prompt only if not already granted — macOS silently ignores the global
        // monitor without this, so we request it upfront.
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }

        petWindow = PetWindow()
        petWindow?.orderFront(nil)

        trayMenu = TrayMenu()

        stateEngine.onStateChange = { [weak self] state in
            self?.petWindow?.loadState(state)
        }

        stateEngine.onSessionsChange = { [weak self] sessions in
            self?.trayMenu?.update(sessions: sessions)
        }

        hookServer.onEvent = { [weak self] event in
            self?.stateEngine.handle(event)
            // PostToolUse means the tool ran — Claude Code resolved the permission
            // in its own UI without closing our connection. Auto-dismiss the bubble.
            if event.hookEventName == HookEventName.postToolUse,
               let sessionId = event.sessionId,
               let id = self?.pendingPermissionsBySession.removeValue(forKey: sessionId) {
                self?.bubbleManager.remove(id: id)
                self?.stateEngine.setNotification(id: id, active: false)
                self?.hookServer.resolvePermission(id: id, decision: .deny)
            }
            // SessionEnd — revoke trust so the next session starts fresh.
            if event.hookEventName == HookEventName.sessionEnd,
               let sessionId = event.sessionId {
                self?.trustedSessions.remove(sessionId)
            }
        }

        // Register all Claude Code hooks once the port is known (single settings.json write).
        hookServer.onReady = { port in
            HookInstaller.registerClaudeHooks(port: port)
        }

        // Show a bubble when Claude Code holds a connection open for approval.
        hookServer.onPermissionRequest = { [weak self] request in
            // Trusted session — approve silently without showing a bubble.
            if let sessionId = request.sessionId,
               self?.trustedSessions.contains(sessionId) == true {
                self?.hookServer.resolvePermission(id: request.id, decision: .allow)
                return
            }
            self?.bubbleManager.add(request)
            self?.stateEngine.setNotification(id: request.id, active: true)
            if let sessionId = request.sessionId {
                self?.pendingPermissionsBySession[sessionId] = request.id
            }
        }

        // If the client disconnects before the user decides, dismiss the bubble.
        hookServer.onPermissionEvicted = { [weak self] id in
            self?.bubbleManager.remove(id: id)
            self?.stateEngine.setNotification(id: id, active: false)
            self?.pendingPermissionsBySession = self?.pendingPermissionsBySession.filter { $0.value != id } ?? [:]
        }

        // Slide the pet up to clear the bubble stack.
        bubbleManager.onOffsetChange = { [weak self] offset in
            self?.petWindow?.setBubbleOffset(offset)
        }

        // Forward the user's decision back to Claude Code and clear the notification state.
        bubbleManager.onDecision = { [weak self] id, decision in
            self?.hookServer.resolvePermission(id: id, decision: decision)
            self?.stateEngine.setNotification(id: id, active: false)
            self?.pendingPermissionsBySession = self?.pendingPermissionsBySession.filter { $0.value != id } ?? [:]
        }

        // "Allow Session" — trust this session and approve the current request immediately.
        bubbleManager.onTrustSession = { [weak self] id, sessionId in
            if let sid = sessionId { self?.trustedSessions.insert(sid) }
            self?.hookServer.resolvePermission(id: id, decision: .allow)
            self?.stateEngine.setNotification(id: id, active: false)
            self?.pendingPermissionsBySession = self?.pendingPermissionsBySession.filter { $0.value != id } ?? [:]
        }

        piWatcher.onEvent = { [weak self] event in
            self?.stateEngine.handle(event)
        }

        do {
            try hookServer.start()
        } catch {
            print("[AppDelegate] HookServer failed to start: \(error)")
        }

        HookInstaller.installIfNeeded()
        HookInstaller.registerOpencodePlugin()
        piWatcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        piWatcher.stop()
        // Deny all open permission requests so Claude Code doesn't hang on the 600s timeout.
        hookServer.denyAllPending()
        bubbleManager.dismissAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
