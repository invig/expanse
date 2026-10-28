import ServiceManagement

/// Opening Expanse at login, for release builds only: a development build would sign its build
/// folder in as the login item. On by default: the first start of a release turns it on, once.
/// After that it's yours to switch, from the menu or System Settings › General › Login Items.
enum LoginItem {
    private static let setUpKey = "loginItemSetUp"

    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    /// When Expanse starts (after the walkthrough, so macOS's "login item added" notice doesn't
    /// land in the middle of it).
    static func setUpOnce() {
        guard Updater.shared.isRelease, !UserDefaults.standard.bool(forKey: setUpKey) else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: setUpKey)
            logger.info("login item registered")
        } catch {
            // Tried again next start.
            logger.error("login item registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func toggle() {
        UserDefaults.standard.set(true, forKey: setUpKey)
        do {
            if enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            logger.error("login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        // Turned off in System Settings, it only comes back on with your OK there.
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}
