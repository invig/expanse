import AppKit

/// Global CG coordinates (top-left of the main display, y down) to AppKit's (bottom-left, y up).
@MainActor func appKitRect(_ r: CGRect) -> NSRect {
    let h = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}

/// Where the window server has a window now (global CG), on screen or not. Nil once it's gone.
func realFrame(_ id: CGWindowID) -> CGRect? {
    guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
          let b = info.first?[kCGWindowBounds as String] as? NSDictionary,
          let r = CGRect(dictionaryRepresentation: b) else { return nil }
    return r
}

/// Makes an app the front one, as clicking it or ⌘-Tab would. Through Accessibility when Expanse
/// Tests has it: since macOS 14 an app can't simply take the front from another (NSApp.activate is
/// only a request), and Accessibility can do it whichever app is in front. It can't for a hidden
/// app: unhide it (or restore its window) first.
@MainActor func bringToFront(_ app: NSRunningApplication) {
    if AXIsProcessTrusted() {
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    } else if app.processIdentifier == getpid() {
        NSApp.activate(ignoringOtherApps: true)
    } else {
        app.activate()
    }
}

/// The same, and waits until it's the front app (a hidden one is shown first, as ⌘-Tab does).
@MainActor func bringForward(_ app: NSRunningApplication, timeout: TimeInterval = 2) async {
    if app.isHidden {
        app.unhide()
        for _ in 0..<40 where app.isHidden { try? await Task.sleep(nanoseconds: 25_000_000) }
    }
    let deadline = Date().addingTimeInterval(timeout)
    while NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier, Date() < deadline {
        bringToFront(app)
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}

func isOnScreen(_ id: CGWindowID) -> Bool {
    let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]]
    return (info?.first?[kCGWindowIsOnscreen as String] as? Bool) == true
}

/// A window of Expanse Tests itself, for Expanse to manage like any app's.
@MainActor final class TestWindow {
    /// Nil once closed: let go of, so the window server forgets it too, as it does any app's
    /// closed window. (Kept, a closed NSWindow is only hidden, and Expanse rightly keeps its spot.)
    private(set) var window: NSWindow!
    let id: CGWindowID
    let title: String

    init(title: String, frame: CGRect) {
        let window = NSWindow(contentRect: appKitRect(frame), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        // No opening animation: its frame is final as soon as it's on screen (mid-animation macOS
        // reports it scaled down).
        window.animationBehavior = .none
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.alignment = .center
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(hue: CGFloat(abs(title.hashValue) % 360) / 360, saturation: 0.35, brightness: 0.95, alpha: 1).cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
                                     label.centerYAnchor.constraint(equalTo: box.centerYAnchor)])
        window.contentView = box
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.id = CGWindowID(window.windowNumber)
        self.title = title
    }

    var isOpen: Bool { window != nil }
    /// Where the window server has it (global CG).
    var real: CGRect? { realFrame(id) }
    var onScreen: Bool { isOnScreen(id) }

    func focus() {
        bringToFront(.current)
        window?.makeKeyAndOrderFront(nil)
    }
    func close() {
        window?.close()
        window = nil
    }
    func minimise() { window?.miniaturize(nil) }
    func restore() { window?.deminiaturize(nil) }
    func toggleFullScreen() { window?.toggleFullScreen(nil) }
    /// Moves or resizes it the way the app itself would (not Expanse, not you).
    func setFrame(_ r: CGRect) { window?.setFrame(appKitRect(r), display: true) }
}

/// Another app's windows: a second copy of Expanse Tests, started with --fixture, that opens
/// windows and does what it's told (see FixtureApp in main.swift). For cases about apps quitting,
/// hiding, or two apps at once.
@MainActor final class Fixture {
    static let commandNote = Notification.Name("com.invignation.expanse.integration.do")
    static let stateNote = Notification.Name("com.invignation.expanse.integration.state")

    let name: String
    private(set) var app: NSRunningApplication?
    private(set) var windows: [CGWindowID] = []
    private var observer: NSObjectProtocol?
    private var updates = 0

    init(name: String) {
        self.name = name
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.stateNote, object: name, queue: .main) { [weak self] note in
            let ids = (note.userInfo?["windows"] as? [String] ?? []).compactMap { CGWindowID($0) }
            MainActor.assumeIsolated {
                self?.windows = ids
                self?.updates += 1
            }
        }
    }

    var pid: pid_t? { app?.processIdentifier }

    /// Starts it with `count` windows of `size`, and waits until they're open.
    func launch(windows count: Int, size: CGSize = CGSize(width: 640, height: 420)) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        config.arguments = ["--fixture", name, "--windows", "\(count)", "--size", "\(Int(size.width))x\(Int(size.height))"]
        let seen = updates
        app = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
        try await waitForUpdate(after: seen, "\(name) didn't open its windows")
        // The window server lists new windows a moment after they're made.
        for _ in 0..<60 where !windows.allSatisfy({ realFrame($0) != nil }) { try await Task.sleep(nanoseconds: 50_000_000) }
    }

    func send(_ action: String, _ extra: [String: String] = [:]) async throws {
        let seen = updates
        var info = extra
        info["do"] = action
        DistributedNotificationCenter.default().postNotificationName(Self.commandNote, object: name, userInfo: info, deliverImmediately: true)
        if action != "quit" { try await waitForUpdate(after: seen, "\(name) didn't answer \(action)") }
    }

    func openWindow() async throws { try await send("open") }
    func closeWindow(_ index: Int) async throws { try await send("close", ["index": "\(index)"]) }
    func minimise(_ index: Int) async throws { try await send("minimise", ["index": "\(index)"]) }
    func hide() { app?.hide() }
    func unhide() { app?.unhide() }
    func activate() { if let app { bringToFront(app) } }

    func quit() async {
        app?.terminate()
        for _ in 0..<100 where app?.isTerminated == false { try? await Task.sleep(nanoseconds: 50_000_000) }
        if app?.isTerminated == false { app?.forceTerminate() }
        windows = []
    }

    private func waitForUpdate(after seen: Int, _ message: String) async throws {
        for _ in 0..<100 {
            if updates > seen { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw Failure(message)
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
