import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let controller = CanvasController()
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var centreHotKey: HotKey?
    private var arrowHotKeys: [HotKey] = []
    private let centreItem = NSMenuItem(title: "Auto-Centre Focused Window", action: #selector(toggleAutoCentre), keyEquivalent: "`")
    private var signalSources: [DispatchSourceSignal] = []
    private let accessibilityItem = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let cornerMenu = NSMenu()
    private let wallpaperItem = NSMenuItem(title: "Desktop Picture Background", action: #selector(toggleWallpaper), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Expanse", action: #selector(togglePause), keyEquivalent: "")
    private let screenRecordingItem = NSMenuItem(title: "", action: #selector(openScreenRecordingSettings), keyEquivalent: "")
    private let installUpdateItem = NSMenuItem(title: "", action: #selector(installUpdate), keyEquivalent: "")
    private let autoUpdateItem = NSMenuItem(title: "Check for Updates Automatically", action: #selector(toggleAutoUpdate), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        // No system permission prompts out of the blue: the walkthrough explains each one first.
        let trusted = AX.isTrusted(prompt: false)
        let canRecord = CGPreflightScreenCaptureAccess()
        logger.info("accessibility=\(trusted) screenRecording=\(canRecord)")
        Onboarding.hotCorner = controller.hotCorner
        if Onboarding.needed { Onboarding.show {} }
        // Launching Expanse again while it's running shows this window (see main.swift).
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.invignation.expanse.showWelcome"),
                                                            object: nil, queue: .main) { _ in Onboarding.show {} }

        // ⌥` toggles the canvas.
        hotKey = HotKey(keyCode: kVK_ANSI_Grave, modifiers: optionKey, id: 1) { [weak self] in
            self?.controller.toggle()
        }
        // ⌃ + arrows move to the nearest window in that direction.
        let arrows: [(Int, CanvasController.Direction)] = [(kVK_LeftArrow, .left), (kVK_RightArrow, .right),
                                                           (kVK_UpArrow, .up), (kVK_DownArrow, .down)]
        for (i, (key, direction)) in arrows.enumerated() {
            arrowHotKeys.append(HotKey(keyCode: key, modifiers: controlKey, id: UInt32(10 + i)) { [weak self] in
                self?.controller.navigate(direction)
            })
        }
        // ⌥⇧` toggles auto-centring.
        centreHotKey = HotKey(keyCode: kVK_ANSI_Grave, modifiers: optionKey | shiftKey, id: 2) { [weak self] in
            self?.toggleAutoCentre()
        }

        // Never leave windows stranded in the corner: restore them on SIGTERM / SIGINT too.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }

        controller.start()

        Updater.shared.onReady = { [weak self] release in self?.updateReady(release) }
        Updater.shared.start()
    }

    /// An update has downloaded and checked out: say so, once per version unless you asked.
    private var askedToCheck = false
    private func updateReady(_ release: Updater.Release) {
        let key = "updatePromptedFor"
        guard askedToCheck || UserDefaults.standard.string(forKey: key) != release.version else { return }
        // Zoomed out, the canvas would cover the prompt: wait until you're back at 100%.
        guard !controller.isActive else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.updateReady(release) }
            return
        }
        askedToCheck = false
        UserDefaults.standard.set(release.version, forKey: key)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Expanse \(release.version) is ready to install"
        alert.informativeText = "Expanse relaunches, and your windows stay where they are. You can also install it later from the menu bar icon."
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "What's New")
        switch alert.runModal() {
        case .alertFirstButtonReturn: Updater.shared.install()
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.page)
        default: break
        }
    }

    @objc private func checkForUpdates() {
        askedToCheck = true
        Updater.shared.check(interactive: true)
    }

    @objc private func installUpdate() { Updater.shared.install() }

    @objc private func toggleAutoUpdate() { Updater.shared.automatic.toggle() }

    /// expanse://toggle | enter | exit | fit | restore | zoom?scale=0.5 | pan?dx=100&dy=0 | focus?app=Safari
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "expanse", let command = url.host else { continue }
            let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems ?? []).map { ($0.name, $0.value ?? "") })
            // Finite numbers only: "nan" and "inf" parse as Doubles and would poison the camera.
            func number(_ key: String) -> CGFloat? {
                guard let d = Double(query[key] ?? ""), d.isFinite else { return nil }
                return CGFloat(d)
            }
            logger.info("url command \(command, privacy: .public)")
            // Any app or web page can open expanse:// links. Commands that reach into individual
            // windows or fake the display are for debugging only and stay off unless enabled with
            // `defaults write com.invignation.expanse debugURLCommands -bool true`.
            let debugCommands: Set<String> = ["place", "prefer", "dump", "screen", "update"]
            if debugCommands.contains(command), !UserDefaults.standard.bool(forKey: "debugURLCommands") {
                logger.info("ignored debug URL command \(command, privacy: .public) (debugURLCommands is off)")
                continue
            }
            if command == "nav" { runURLCommand(command, query: query, number: number); continue }
            controller.whenIdle { [weak self] in self?.runURLCommand(command, query: query, number: number) }
        }
    }

    private func runURLCommand(_ command: String, query: [String: String], number: (String) -> CGFloat?) {
            switch command {
            case "toggle": controller.toggle()
            case "enter": controller.enter(zoomOut: query["zoomOut"] != "0")
            case "exit": controller.exit()
            case "fit": controller.animate(to: controller.fitCamera())
            case "restore": controller.restoreAll()
            case "tidy": controller.tidy()
            case "welcome": Onboarding.show {}
            case "place":
                if let id = number("id"), let x = number("x"), let y = number("y") {
                    controller.setCanvasOrigin(CGWindowID(id), CGPoint(x: x, y: y), commit: query["commit"] == "1")
                }
            case "prefer":
                // Repair: set the size a window should have (by window ID), e.g. after it was lost.
                if let id = number("id"), let w = number("w"), let h = number("h") {
                    controller.setPreferredSize(CGWindowID(id), CGSize(width: w, height: h))
                }
            case "nav":
                let dirs: [String: CanvasController.Direction] = ["left": .left, "right": .right, "up": .up, "down": .down]
                if let d = dirs[query["dir"] ?? ""] {
                    // Optional delay, so a test hop runs after the URL hand-off has settled.
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(number("delay") ?? 0)) { [weak self] in
                        self?.controller.navigate(d)
                    }
                }
            case "update":
                // Check now; ?install=1 installs a newer release without asking (for testing).
                Updater.shared.check(interactive: false, install: query["install"] == "1")
            case "pause": controller.pause()
            case "resume": controller.resume()
            case "dump": controller.dump()
            case "screen":
                if let w = number("w"), let h = number("h") {
                    controller.simulateScreen(CGSize(width: w, height: h))
                } else {
                    controller.simulateScreen(nil)
                }
            case "zoom": if let s = number("scale") { controller.zoomAnimated(to: s) }
            case "pan": controller.pan(by: CGVector(dx: number("dx") ?? 0, dy: number("dy") ?? 0))
            case "space":
                // A Space by name ("Canvas", "Desktop", or a full-screen app's), or by its place in
                // Mission Control's order, from 1.
                let spaces = Spaces.list().spaces
                let name = (query["name"] ?? "").lowercased()
                let index = Int(number("index") ?? 0) - 1
                if let space = (name == "canvas" ? spaces.first { $0.id == controller.canvasDesktop } : nil)
                    ?? spaces.first(where: { $0.name.lowercased() == name })
                    ?? (spaces.indices.contains(index) ? spaces[index] : nil) {
                    controller.switchToSpace(space)
                }
            case "focus":
                // ?app=Safari (its front window), or ?id= a window ID (from dump).
                let name = (query["app"] ?? "").lowercased()
                let id = number("id").map { CGWindowID($0) }
                if let w = controller.windows.last(where: { id != nil ? $0.id == id : $0.appName.lowercased() == name }) {
                    controller.focus(w)
                }
            default: break
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Expanse")

        let menu = NSMenu()
        menu.delegate = self
        let open = NSMenuItem(title: "Open Expanse", action: #selector(toggleCanvas), keyEquivalent: "`")
        open.keyEquivalentModifierMask = [.option]
        menu.addItem(open)
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        let cornerItem = NSMenuItem(title: "Hot Corner", action: nil, keyEquivalent: "")
        cornerItem.submenu = cornerMenu
        for corner in HotCorner.Corner.allCases {
            let item = NSMenuItem(title: corner.title, action: #selector(pickCorner(_:)), keyEquivalent: "")
            item.representedObject = corner.rawValue
            item.target = self
            cornerMenu.addItem(item)
        }
        menu.addItem(cornerItem)
        centreItem.keyEquivalentModifierMask = [.option, .shift]
        centreItem.target = self
        menu.addItem(centreItem)
        menu.addItem(wallpaperItem)
        menu.addItem(NSMenuItem(title: "Tidy Up Windows", action: #selector(tidy), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Restore All Windows", action: #selector(restoreAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Welcome & Shortcuts…", action: #selector(showWelcome), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(installUpdateItem)
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(autoUpdateItem)
        menu.addItem(.separator())
        menu.addItem(accessibilityItem)
        menu.addItem(screenRecordingItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Expanse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let ax = AX.isTrusted(prompt: false)
        let sr = CGPreflightScreenCaptureAccess()
        for item in cornerMenu.items {
            item.state = (item.representedObject as? String) == controller.hotCorner.corner.rawValue ? .on : .off
        }
        wallpaperItem.state = Wallpaper.enabled ? .on : .off
        centreItem.state = controller.autoCentre ? .on : .off
        pauseItem.title = controller.isPaused ? "Resume Expanse" : "Pause Expanse (back to macOS layout)"
        accessibilityItem.title = ax ? "Accessibility: granted" : "Grant Accessibility…"
        let update = Updater.shared.ready?.release.version
        installUpdateItem.title = "Install Expanse \(update ?? "")…"
        installUpdateItem.isHidden = update == nil
        autoUpdateItem.state = Updater.shared.automatic ? .on : .off
        autoUpdateItem.isHidden = !Updater.shared.isRelease
        screenRecordingItem.title = sr ? "Screen Recording: granted" : "Grant Screen Recording…"
    }

    @objc private func toggleCanvas() { controller.whenIdle { [weak self] in self?.controller.toggle() } }
    @objc private func restoreAll() { controller.whenIdle { [weak self] in self?.controller.restoreAll() } }
    @objc private func showWelcome() { Onboarding.show {} }
    @objc private func tidy() { controller.whenIdle { [weak self] in self?.controller.tidy() } }
    @objc private func pickCorner(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let corner = HotCorner.Corner(rawValue: raw) else { return }
        controller.hotCorner.corner = corner
    }

    @objc private func toggleAutoCentre() {
        controller.autoCentre.toggle()
        Toast.show(controller.autoCentre ? "Auto-centre on" : "Auto-centre off: windows stay put")
    }

    @objc private func toggleWallpaper() {
        Wallpaper.enabled.toggle()
        controller.refreshWallpaper()
    }

    @objc private func togglePause() {
        controller.whenIdle { [weak self] in
            guard let c = self?.controller else { return }
            c.isPaused ? c.resume() : c.pause()
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
