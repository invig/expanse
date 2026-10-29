import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = CanvasController()
    private var statusItem: NSStatusItem!
    private var menuPanel: MenuPanel?
    private var hotKey: HotKey?
    private var centreHotKey: HotKey?
    private var centreWindowHotKey: HotKey?
    private var arrowHotKeys: [HotKey] = []
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        // No system permission prompts out of the blue: the walkthrough explains each one first.
        let trusted = AX.isTrusted(prompt: false)
        let canRecord = CGPreflightScreenCaptureAccess()
        logger.info("accessibility=\(trusted) screenRecording=\(canRecord)")
        Onboarding.hotCorner = controller.hotCorner
        // Expanse stays off (it moves no windows and takes no shortcuts) until the walkthrough is
        // finished, skipped or closed: setting up shouldn't have windows moving under you.
        if Onboarding.needed { Onboarding.show { [weak self] in self?.turnOn() } } else { turnOn() }
        // Launching Expanse again while it's running shows this window (see main.swift).
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.invignation.expanse.showWelcome"),
                                                            object: nil, queue: .main) { [weak self] _ in self?.showWelcome() }

        // Never leave windows stranded in the corner: restore them on SIGTERM / SIGINT too.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }

        Updater.shared.onReady = { [weak self] release in self?.updateReady(release) }
        Updater.shared.start()
    }

    /// Expanse has started: the canvas and its shortcuts.
    private var isOn = false

    private func turnOn() {
        guard !isOn else { return }
        isOn = true
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
        // ⌃⌥C centres the window you're in (as Rectangle's Center does; ⌃Space is editors'
        // autocomplete, and macOS's input-source switch for anyone with two keyboard layouts).
        centreWindowHotKey = HotKey(keyCode: kVK_ANSI_C, modifiers: controlKey | optionKey, id: 3) { [weak self] in
            self?.controller.centreCurrentWindow()
        }
        controller.start()
        LoginItem.setUpOnce()
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

    private func checkForUpdates() {
        askedToCheck = true
        Updater.shared.check(interactive: true)
    }

    private func copyLogs() {
        let c = controller
        BugReport.copy(settings: [
            "Canvas: \(c.windows.count) windows, \(c.isPaused ? "paused" : "running"), auto-centre \(c.autoCentre ? "on" : "off"), hot corner \(c.hotCorner.corner.title)",
            "Desktop picture background \(Wallpaper.enabled ? "on" : "off"), window names \(CanvasView.showsNames ? "shown" : "hidden"), detailed logging \(LogFile.shared.isEnabled ? "on" : "off")",
        ])
    }

    /// expanse://toggle | enter | exit | fit | restore | menu | zoom?scale=0.5 | pan?dx=100&dy=0 | focus?app=Safari
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
            let debugCommands: Set<String> = ["place", "prefer", "dump", "screen", "update", "appearance", "logging", "copylogs", "snapshot",
                                              "poweroff"]
            if debugCommands.contains(command), !UserDefaults.standard.bool(forKey: "debugURLCommands") {
                logger.info("ignored debug URL command \(command, privacy: .public) (debugURLCommands is off)")
                continue
            }
            if !isOn, !["welcome", "update"].contains(command) {
                logger.info("ignored URL command \(command, privacy: .public): Expanse starts once the walkthrough is done")
                continue
            }
            if command == "nav" { runURLCommand(command, query: query, number: number); continue }
            controller.whenIdle { [weak self] in self?.runURLCommand(command, query: query, number: number) }
        }
    }

    private func runURLCommand(_ command: String, query: [String: String], number: (String) -> CGFloat?) {
            // A window ID or an index: a whole number in range, or nothing. Converting anything
            // else traps, and any web page can open these links.
            func windowID(_ key: String) -> CGWindowID? { number(key).flatMap { CGWindowID(exactly: $0) } }
            func index(_ key: String) -> Int? { number(key).flatMap { Int(exactly: $0) } }
            switch command {
            case "toggle": controller.toggle()
            case "centre", "center": controller.centreCurrentWindow()
            case "enter": controller.enter(zoomOut: query["zoomOut"] != "0")
            case "exit": controller.exit()
            case "fit": controller.animate(to: controller.fitCamera())
            case "restore": controller.restoreAll()
            case "tidy": controller.tidy()
            case "layout":
                // A layout snapshot, 0 the newest (see Earlier layouts in the menu bar panel).
                let all = LayoutStore.snapshots(), n = Int(number("snapshot") ?? 0)
                if all.indices.contains(n), let layout = LayoutStore.load(all[n]) { controller.restoreLayout(layout) }
            case "welcome": showWelcome()
            case "menu": menuPanel?.show()
            case "place":
                if let id = windowID("id"), let x = number("x"), let y = number("y") {
                    controller.setCanvasOrigin(id, CGPoint(x: x, y: y), commit: query["commit"] == "1")
                }
            case "prefer":
                // Repair: set the size a window should have (by window ID), e.g. after it was lost.
                if let id = windowID("id"), let w = number("w"), let h = number("h") {
                    controller.setPreferredSize(id, CGSize(width: w, height: h))
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
            // What Troubleshooting › Detailed Logging and Copy Logs do, for testing them.
            case "logging": LogFile.shared.isEnabled = query["on"] == "1"
            case "copylogs": copyLogs()
            // What Take snapshot in the menu bar panel does.
            case "snapshot": controller.takeSnapshot()
            // A logout or restart starting: the notification macOS posts for one (see willPowerOff).
            case "poweroff": NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willPowerOffNotification, object: NSWorkspace.shared)
            case "appearance":
                // Light or dark for Expanse alone, to check its look in both (anything else: the Mac's).
                let names: [String: NSAppearance.Name] = ["light": .aqua, "dark": .darkAqua]
                NSApp.appearance = (query["mode"]).flatMap { names[$0] }.flatMap { NSAppearance(named: $0) }
            case "screen":
                if let w = number("w"), let h = number("h") {
                    controller.simulateScreen(CGSize(width: w, height: h))
                } else {
                    controller.simulateScreen(nil)
                }
            case "zoom": if let s = number("scale") { controller.zoomAnimated(to: s) }
            case "pan": controller.pan(by: CGVector(dx: number("dx") ?? 0, dy: number("dy") ?? 0))
            case "space":
                // A Space by name ("Expanse" for the canvas's, "Canvas" too as it used to be called,
                // "Desktop", or a full-screen app's), or by its place in Mission Control's order, from 1.
                let spaces = Spaces.list().spaces
                let name = (query["name"] ?? "").lowercased()
                let position = (index("index") ?? 0) - 1
                if let space = (name == "expanse" || name == "canvas" ? spaces.first { $0.id == controller.canvasDesktop } : nil)
                    ?? spaces.first(where: { $0.name.lowercased() == name })
                    ?? (spaces.indices.contains(position) ? spaces[position] : nil) {
                    controller.switchToSpace(space)
                }
            case "focus":
                // ?app=Safari (its front window), or ?id= a window ID (from dump). Reaching into a
                // particular window is for debugging, like place and prefer (see above).
                let name = (query["app"] ?? "").lowercased()
                let id = UserDefaults.standard.bool(forKey: "debugURLCommands") ? windowID("id") : nil
                if let w = controller.windows.last(where: { id != nil ? $0.id == id : $0.appName.lowercased() == name }) {
                    controller.focus(w)
                }
            default: break
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never started: nothing to put back, and the saved layout must not be overwritten.
        guard isOn else { return }
        controller.shutdown()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Expanse")
        menuPanel = MenuPanel(button: button, state: { [unowned self] in menuState() }, perform: { [unowned self] in perform($0) })
    }

    private func menuState() -> MenuPanel.State {
        let c = controller
        return MenuPanel.State(isOn: isOn, isPaused: c.isPaused, isActive: c.isActive,
                               windows: c.windows.map(\.canvasFrame), viewport: c.visibleCanvas,
                               autoCentre: c.autoCentre, wallpaper: Wallpaper.enabled, names: CanvasView.showsNames,
                               corner: c.hotCorner.corner,
                               update: Updater.shared.ready?.release.version,
                               detailedLogging: LogFile.shared.isEnabled,
                               hasLogFile: FileManager.default.fileExists(atPath: LogFile.shared.url.path))
    }

    private func perform(_ action: MenuPanel.Action) {
        switch action {
        case .toggleCanvas: controller.whenIdle { [weak self] in self?.controller.toggle() }
        case .setPaused(let paused):
            controller.whenIdle { [weak self] in
                guard let c = self?.controller, c.isPaused != paused else { return }
                paused ? c.pause() : c.resume()
            }
        case .centreWindow: controller.whenIdle { [weak self] in self?.controller.centreCurrentWindow() }
        case .tidy: controller.whenIdle { [weak self] in self?.controller.tidy() }
        case .restoreAll: controller.whenIdle { [weak self] in self?.controller.restoreAll() }
        case .restoreLayout(let url):
            guard let snapshot = LayoutStore.snapshots().first(where: { $0.url == url }),
                  let layout = LayoutStore.load(snapshot) else { return }
            controller.whenIdle { [weak self] in self?.controller.restoreLayout(layout) }
        case .takeSnapshot: controller.takeSnapshot()
        case .autoCentre(let on): controller.autoCentre = on
        case .wallpaper(let on):
            Wallpaper.enabled = on
            controller.refreshWallpaper()
        case .names(let on):
            CanvasView.showsNames = on
            controller.view.render()
        case .corner(let corner): controller.hotCorner.corner = corner
        case .grantAccessibility: Permissions.requestAccessibility()
        case .grantScreenRecording: Permissions.requestScreenRecording()
        case .installUpdate: Updater.shared.install()
        case .detailedLogging(let on):
            LogFile.shared.isEnabled = on
            Toast.show(on ? "Detailed logging on" : "Detailed logging off")
        case .copyLogs: copyLogs()
        case .showLogFile: NSWorkspace.shared.activateFileViewerSelecting([LogFile.shared.url])
        case .reportIssue: NSWorkspace.shared.open(BugReport.issuesURL)
        case .welcome: showWelcome()
        case .settings:
            // An ordinary window: zoomed out, leave the canvas first, or it would open underneath.
            if controller.isActive, !controller.gliding { controller.exit() }
            SettingsWindow.show { [weak self] in self?.checkForUpdates() }
        case .quit: NSApp.terminate(nil)
        }
    }

    /// The walkthrough is an ordinary window: zoomed out, leave the canvas first, or it would
    /// open underneath.
    private func showWelcome() {
        if controller.isActive, !controller.gliding { controller.exit() }
        Onboarding.show {}
    }

    private func toggleAutoCentre() {
        controller.autoCentre.toggle()
        Toast.show(controller.autoCentre ? "Auto-centre on" : "Auto-centre off: windows stay put")
    }
}
