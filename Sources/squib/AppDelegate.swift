import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindow:     PetWindow?
    private let stateEngine   = StateEngine()
    private let hookServer    = HookServer()
    private let bubbleManager = BubbleManager()
    private let piWatcher     = PiWatcher()
    private var trayMenu:      TrayMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
        }

        // Register the blocking HTTP permission hook once the port is known.
        hookServer.onReady = { port in
            HookInstaller.registerPermissionHook(port: port)
        }

        // Show a bubble when Claude Code holds a connection open for approval.
        hookServer.onPermissionRequest = { [weak self] request in
            self?.bubbleManager.add(request)
        }

        // If the client disconnects before the user decides, dismiss the bubble.
        hookServer.onPermissionEvicted = { [weak self] id in
            self?.bubbleManager.remove(id: id)
        }

        // Slide the pet up to clear the bubble stack.
        bubbleManager.onOffsetChange = { [weak self] offset in
            self?.petWindow?.setBubbleOffset(offset)
        }

        // Forward the user's decision back to Claude Code.
        bubbleManager.onDecision = { [weak self] id, decision in
            self?.hookServer.resolvePermission(id: id, decision: decision)
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
