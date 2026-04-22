import ServiceManagement

/// Manages the "Launch at Login" state using SMAppService.
/// Requires the app to be running from a proper .app bundle (use `make install`).
final class LoginItemManager {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Toggles the current state and returns the new value.
    @discardableResult
    static func toggle() -> Bool {
        let target = !isEnabled
        do {
            if target {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[LoginItemManager] Failed to \(target ? "enable" : "disable") login item: \(error)")
        }
        return isEnabled
    }
}
