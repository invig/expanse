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
    private let pauseItem = NSMenuItem(title: "Pause Canvas", action: #selector(togglePause), keyEquivalent: "")
    private let screenRecordingItem = NSMenuItem(title: "", action: #selector(openScreenRecordingSettings), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        let trusted = AX.isTrusted(prompt: true)
        let canRecord = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        logger.info("accessibility=\(trusted) screenRecording=\(canRecord)")

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
    }

    /// canvas://toggle | enter | exit | fit | restore | zoom?scale=0.5 | pan?dx=100&dy=0 | focus?app=Safari
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "canvas", let command = url.host else { continue }
            let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems ?? []).map { ($0.name, $0.value ?? "") })
            func number(_ key: String) -> CGFloat? { Double(query[key] ?? "").map { CGFloat($0) } }
            logger.info("url command \(command, privacy: .public)")
            switch command {
            case "toggle": controller.toggle()
            case "enter": controller.enter(zoomOut: query["zoomOut"] != "0")
            case "exit": controller.exit()
            case "fit": controller.animate(to: controller.fitCamera())
            case "restore": controller.restoreAll()
            case "tidy": controller.tidy()
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
            case "focus":
                let name = (query["app"] ?? "").lowercased()
                if let w = controller.windows.last(where: { $0.appName.lowercased() == name }) { controller.focus(w) }
            default: break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Canvas")

        let menu = NSMenu()
        menu.delegate = self
        let open = NSMenuItem(title: "Open Canvas", action: #selector(toggleCanvas), keyEquivalent: "`")
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
        menu.addItem(.separator())
        menu.addItem(accessibilityItem)
        menu.addItem(screenRecordingItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Canvas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
        pauseItem.title = controller.isPaused ? "Resume Canvas" : "Pause Canvas (back to macOS layout)"
        accessibilityItem.title = ax ? "Accessibility: granted" : "Grant Accessibility…"
        screenRecordingItem.title = sr ? "Screen Recording: granted" : "Grant Screen Recording…"
    }

    @objc private func toggleCanvas() { controller.toggle() }
    @objc private func restoreAll() { controller.restoreAll() }
    @objc private func tidy() { controller.tidy() }
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

    @objc private func togglePause() { controller.isPaused ? controller.resume() : controller.pause() }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
