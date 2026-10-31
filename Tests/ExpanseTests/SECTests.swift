import Testing
import AppKit
import CoreMedia
import OSLog
import ScreenCaptureKit
@_private(sourceFile: "AppDelegate.swift") @testable import Expanse
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "LayoutStore.swift") @testable import Expanse
@_private(sourceFile: "AX.swift") @testable import Expanse
@_private(sourceFile: "WindowCapture.swift") @testable import Expanse

/// docs/regression/security.md. Links are opened through AppDelegate.application(_:open:) on an
/// app delegate that's switched on but not started (see `started`), and what they do is read off
/// its canvas: nothing reaches real windows, the screen or ScreenCaptureKit. Layout and updater
/// cases are in SECTests+Layout.swift and SECTests+Updater.swift.
@MainActor @Suite("SEC: Security hardening", .serialized) struct SECTests {

    // MARK: Helpers

    /// No process has a pid this high (macOS stops at 99,999): Accessibility finds nothing for it.
    static let noPID: pid_t = 990_001

    /// A window on the canvas whose app can't exist. It isn't due a picture for a minute, so
    /// nothing asks ScreenCaptureKit for one.
    func window(_ id: CGWindowID, _ appName: String = "Example", title: String = "", at frame: CGRect) -> ManagedWindow {
        let w = Fake.window(id: id, pid: Self.noPID, appName: appName, title: title, canvas: frame)
        w.snapshotFailures = 5
        w.lastSnapshotAt = CACurrentMediaTime()
        return w
    }

    /// Expanse once the walkthrough is done (isOn), its canvas on a pretend display with these
    /// windows, but not started: no scans, shortcuts or observers, nothing on screen. `zoomedOut`
    /// marks the canvas as up without showing it. ScreenCaptureKit isn't asked for anything
    /// (replayd counts as stuck) until `finish`.
    func started(windows: [ManagedWindow] = [], zoomedOut: Bool = false) -> AppDelegate {
        Env.isolate()
        let d = AppDelegate()
        let c = d.controller
        let display = TestDisplay.laptop
        c.displayOverride = (display.frame, display.usable)
        c.updateOverlayFrame()
        c.windows = windows
        c.isActive = zoomedOut
        d.isOn = true
        WindowCapture.replaydStuck = true
        return d
    }

    /// Stops what the test set going (animations, picture timers) before ScreenCaptureKit can be
    /// asked again.
    func finish(_ d: AppDelegate) {
        let c = d.controller
        c.cancelAnimation()
        c.snapshotTimer?.invalidate()
        c.snapshotTimer = nil
        c.windows = []
        c.view.hovered = nil
        c.isActive = false
        WindowCapture.replaydStuck = false
    }

    /// Opens links as macOS hands them over from `open` or a script: no browser behind them.
    func open(_ d: AppDelegate, _ links: String...) {
        // A browser's link asks first (NSAlert.runModal), which would block the test.
        guard d.browserSending() == nil else { Issue.record("a browser seems to be sending this link"); return }
        d.application(NSApp, open: links.map { URL(string: $0)! })
    }

    /// A focus that stops before anything moves: a glide doesn't start while the camera is
    /// animating, but the focus request is counted first (focusQuery).
    func holdGlides(_ c: CanvasController) {
        c.animation = .init(from: c.camera, to: c.camera, start: CACurrentMediaTime(), duration: 60)
    }

    /// Marks Expanse's log, for `logLines(after:)`.
    func logMark() -> String {
        let mark = "SECTests mark \(UUID().uuidString)"
        logger.info("\(mark, privacy: .public)")
        return mark
    }

    /// Expanse's log lines from this process after `mark` (the system log keeps them). By the
    /// mark, not the time: a line's time in the log can be a little before the clock's.
    func logLines(after mark: String) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", "com.invignation.expanse"))
        let lines = entries.compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
        guard let i = lines.lastIndex(of: mark) else { Issue.record("log mark not found"); return [] }
        return Array(lines[(i + 1)...])
    }

    /// Waits up to `seconds` for `condition`, letting the main queue run meanwhile.
    func wait(upTo seconds: Double, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    /// Earlier layouts in the test's folder (as the panel's Earlier layouts lists them), each
    /// with a spot for the `window` helper's app, home x = its age: 0 the newest.
    func snapshots(_ count: Int) throws {
        let folder = LayoutStore.snapshotFolder
        let encoder = JSONEncoder()
        for age in 0..<count {
            var e = SavedLayout.Window.entry(x: 0, y: 50, w: 400, h: 300)
            e.hx = Double(age)
            e.hy = 50
            try encoder.encode(SavedLayout.with([e])).write(to: folder.appendingPathComponent("\(2_000_000 - age).json"))
        }
    }

    /// The home x of the snapshot `link` restores to the window, or nil when nothing is restored.
    func restored(_ d: AppDelegate, _ w: ManagedWindow, by link: String) -> CGFloat? {
        d.controller.cancelAnimation()
        w.home = nil
        open(d, link)
        return w.home?.x
    }

    // MARK: SEC-01

    @Test("SEC-01 Camera.zoom and Camera.pan ignore nan and inf") func sec01a() {
        var camera = Camera(origin: CGPoint(x: 10, y: 20), scale: 0.3)
        let before = camera
        for s in [CGFloat.nan, .infinity, -.infinity] { camera.zoom(to: s, anchor: CGPoint(x: 100, y: 100)) }
        camera.zoom(to: 0.8, anchor: CGPoint(x: CGFloat.nan, y: 0))
        camera.zoom(to: 0.8, anchor: CGPoint(x: 0, y: CGFloat.infinity))
        camera.pan(by: CGVector(dx: CGFloat.nan, dy: 1))
        camera.pan(by: CGVector(dx: 1, dy: -CGFloat.infinity))
        #expect(camera == before)
        camera.zoom(to: 0.5, anchor: CGPoint(x: 100, y: 100))
        #expect(camera.scale == 0.5)
    }

    @Test("SEC-01 zoom?scale=nan, inf or -inf leaves the view alone; scale=0.5 zooms to 50%") func sec01b() {
        let d = started(zoomedOut: true)
        defer { finish(d) }
        let c = d.controller
        c.camera = Camera(origin: CGPoint(x: 100, y: 200), scale: 0.3)
        let before = c.camera
        open(d, "expanse://zoom?scale=nan", "expanse://zoom?scale=inf", "expanse://zoom?scale=-inf",
             "expanse://zoom?scale=infinity", "expanse://zoom?scale=1e400")
        #expect(c.animation == nil)
        #expect(c.camera == before)
        open(d, "expanse://zoom?scale=0.5")
        #expect(c.animation?.to.scale == 0.5)
    }

    @Test("SEC-01 pan?dx=nan&dy=1 and pan?dx=1e400 leave the view alone") func sec01c() {
        let d = started(zoomedOut: true)
        defer { finish(d) }
        let c = d.controller
        let before = Camera(origin: CGPoint(x: 100, y: 200), scale: 0.3)
        c.camera = before
        open(d, "expanse://pan?dx=1e400", "expanse://pan?dx=nan", "expanse://pan?dx=inf&dy=-inf")
        #expect(c.camera == before)
        open(d, "expanse://pan?dx=nan&dy=1")
        #expect(c.camera.origin.x == before.origin.x && c.camera.origin.y.isFinite)
        #expect(c.camera == before)
        // A finite pan still pans.
        c.camera = before
        open(d, "expanse://pan?dx=30&dy=0")
        #expect(abs(c.camera.origin.x - (before.origin.x - 30 / before.scale)) < 0.001)
    }

    // MARK: SEC-02

    @Test("SEC-02 Unexpected Accessibility answers can't crash Expanse") func sec02() {
        // Only the no-answer path: AX.focusedWindow and AX.close ask the app first, so a value of
        // the wrong type for their CFGetTypeID checks can't be handed in without a real app.
        #expect(AX.focusedWindow(pid: Self.noPID) == nil)
        AX.close(AXUIElementCreateApplication(Self.noPID))
        #expect(AX.subrole(AXUIElementCreateApplication(Self.noPID)) == nil)
    }

    // MARK: SEC-03 is in SECTests+Layout.swift

    // MARK: SEC-04

    @Test("SEC-04 Debug link commands are ignored by release builds (logic)") func sec04a() {
        Env.withDefaults(["debugURLCommands": true]) {
            #expect(!AppDelegate.debugCommandsAllowed(release: true))
            #expect(AppDelegate.debugCommandsAllowed(release: false))
        }
        Env.withDefaults(["debugURLCommands": nil]) {
            #expect(!AppDelegate.debugCommandsAllowed(release: true))
            #expect(!AppDelegate.debugCommandsAllowed(release: false))
            #expect(!AppDelegate.debugURLCommands)
        }
    }

    @Test("SEC-04 With debug commands off, each debug command is ignored and focus?app= still works (logic)") func sec04b() throws {
        let w = window(7, at: CGRect(x: 0, y: 33, width: 400, height: 300))
        let d = started(windows: [w])
        let appearance = NSApp.appearance
        defer { finish(d); NSApp.appearance = appearance }
        let c = d.controller
        holdGlides(c)
        NSApp.appearance = nil
        let mark = logMark()
        // Not logging, copylogs or poweroff: if the check failed, they'd act outside the test.
        let names = ["dump", "place", "prefer", "screen", "snapshot", "update", "appearance"]
        Env.withDefaults(["debugURLCommands": nil]) {
            let q = c.focusQuery
            open(d, "expanse://dump", "expanse://place?id=7&x=500&y=600", "expanse://prefer?id=7&w=800&h=600",
                 "expanse://screen?w=800&h=600", "expanse://snapshot", "expanse://update", "expanse://appearance?mode=dark")
            #expect(w.canvasFrame.origin == CGPoint(x: 0, y: 33))
            #expect(w.preferredSize == CGSize(width: 400, height: 300))
            #expect(c.screenOverride == nil)
            #expect(NSApp.appearance == nil)
            open(d, "expanse://focus?id=7")
            #expect(c.focusQuery == q)
            open(d, "expanse://focus?app=Example")
            #expect(c.focusQuery == q + 1)
        }
        let lines = try logLines(after: mark)
        for name in names {
            #expect(lines.contains("ignored debug URL command \(name) (debugURLCommands is off)"), "\(name)")
        }
    }

    // MARK: SEC-05

    @Test("SEC-05 layout?snapshot= with a number that isn't a whole number in range does nothing") func sec05a() throws {
        let w = window(7, at: CGRect(x: 0, y: 33, width: 400, height: 300))
        let d = started(windows: [w], zoomedOut: true)
        defer { finish(d) }
        try snapshots(3)
        for bad in ["99999999999999999999", "2.5", "-4", "nan", "inf"] {
            #expect(restored(d, w, by: "expanse://layout?snapshot=\(bad)") == nil, "\(bad)")
        }
        #expect(restored(d, w, by: "expanse://layout?snapshot=2") == 2)
    }

    @Test("SEC-05 place and prefer with a negative, fractional or huge id do nothing") func sec05b() {
        let w = window(7, at: CGRect(x: 0, y: 33, width: 400, height: 300))
        let d = started(windows: [w])
        defer { finish(d) }
        Env.withDefaults(["debugURLCommands": true]) {
            open(d, "expanse://place?id=-1&x=0&y=0", "expanse://place?id=7.5&x=500&y=600",
                 "expanse://place?id=4294967303&x=500&y=600", "expanse://place?id=1e400&x=500&y=600")
            #expect(w.canvasFrame.origin == CGPoint(x: 0, y: 33))
            open(d, "expanse://prefer?id=1e12&w=800&h=600", "expanse://prefer?id=-7&w=800&h=600",
                 "expanse://prefer?id=nan&w=800&h=600")
            #expect(w.preferredSize == CGSize(width: 400, height: 300))
            // A whole number in range still works.
            open(d, "expanse://place?id=7&x=500&y=600", "expanse://prefer?id=7&w=800&h=600")
            #expect(w.canvasFrame.origin == CGPoint(x: 500, y: 600))
            #expect(w.preferredSize == CGSize(width: 800, height: 600))
        }
    }

    @Test("SEC-05 focus?id= with something that isn't a window ID does nothing") func sec05c() {
        let w = window(7, at: CGRect(x: 0, y: 33, width: 400, height: 300))
        let d = started(windows: [w])
        defer { finish(d) }
        let c = d.controller
        holdGlides(c)
        Env.withDefaults(["debugURLCommands": true]) {
            let q = c.focusQuery
            // 4294967303 is 2^32 + 7: cut down to 32 bits, it would be window 7.
            open(d, "expanse://focus?id=-1", "expanse://focus?id=7.5", "expanse://focus?id=4294967303",
                 "expanse://focus?id=1e300", "expanse://focus?id=nan")
            #expect(c.focusQuery == q)
        }
    }

    // MARK: SEC-06

    @Test("SEC-06 focus?id= is ignored without debug commands; focus?app= still goes to the app") func sec06a() {
        let w = window(7, "TextEdit", at: CGRect(x: 0, y: 33, width: 400, height: 300))
        let d = started(windows: [w])
        defer { finish(d) }
        let c = d.controller
        holdGlides(c)
        Env.withDefaults(["debugURLCommands": nil]) {
            let q = c.focusQuery
            open(d, "expanse://focus?id=7")
            #expect(c.focusQuery == q)
            open(d, "expanse://focus?app=TextEdit")
            #expect(c.focusQuery == q + 1)
        }
    }

    @Test("SEC-06 focus?id= is honoured only with debug commands on, never in a release") func sec06b() {
        let w = window(7, "TextEdit", at: CGRect(x: 0, y: 33, width: 400, height: 300))
        let d = started(windows: [w])
        defer { finish(d) }
        let c = d.controller
        holdGlides(c)
        Env.withDefaults(["debugURLCommands": true]) {
            #expect(!AppDelegate.debugCommandsAllowed(release: true))
            let q = c.focusQuery
            open(d, "expanse://focus?id=7")
            #expect(c.focusQuery == q + 1)
        }
    }

    // MARK: SEC-07

    @Test("SEC-07 expanse://appearance is ignored with debug commands off") func sec07a() throws {
        let d = started()
        let appearance = NSApp.appearance
        defer { finish(d); NSApp.appearance = appearance }
        NSApp.appearance = nil
        let mark = logMark()
        Env.withDefaults(["debugURLCommands": nil]) {
            open(d, "expanse://appearance?mode=dark")
        }
        #expect(NSApp.appearance == nil)
        let lines = try logLines(after: mark)
        #expect(lines.contains("ignored debug URL command appearance (debugURLCommands is off)"))
    }

    @Test("SEC-07 appearance is a debug command: it runs with debug commands on, never in a release") func sec07b() {
        let d = started()
        let appearance = NSApp.appearance
        defer { finish(d); NSApp.appearance = appearance }
        NSApp.appearance = nil
        Env.withDefaults(["debugURLCommands": true]) {
            #expect(!AppDelegate.debugCommandsAllowed(release: true))
            open(d, "expanse://appearance?mode=dark")
        }
        #expect(NSApp.appearance?.name == .darkAqua)
    }

    // MARK: SEC-08

    @Test("SEC-08 zoom?scale=0.5&scale=2: the first value counts") func sec08a() {
        let d = started()
        defer { finish(d) }
        open(d, "expanse://zoom?scale=0.5&scale=2")
        #expect(d.controller.animation?.to.scale == 0.5)
        d.controller.cancelAnimation()
        open(d, "expanse://zoom?scale=0.5&scale=2&scale=nan&scale=0.7&scale")
        #expect(d.controller.animation?.to.scale == 0.5)
    }

    @Test("SEC-08 nav?dir=left&dir=right: the first value counts") func sec08b() async {
        let left = window(1, at: CGRect(x: -800, y: 300, width: 400, height: 300))
        let right = window(2, at: CGRect(x: 800, y: 300, width: 400, height: 300))
        let middle = window(3, at: CGRect(x: 0, y: 300, width: 400, height: 300))
        let d = started(windows: [left, right, middle], zoomedOut: true)
        defer { finish(d) }
        let c = d.controller
        c.camera = Camera(origin: CGPoint(x: -1200, y: 0), scale: 0.5)
        open(d, "expanse://nav?dir=left&dir=right")
        #expect(await wait(upTo: 2) { c.view.hovered != nil })
        #expect(c.view.hovered === left)
        c.cancelAnimation()
        c.view.hovered = nil
        open(d, "expanse://nav?dir=right&dir=left")
        #expect(await wait(upTo: 2) { c.view.hovered != nil })
        #expect(c.view.hovered === right)
    }

    // MARK: SEC-09

    @Test("SEC-09 layout?snapshot=1e300 does nothing; an index runs from 0 to 10,000") func sec09() throws {
        let w = window(7, at: CGRect(x: 0, y: 33, width: 400, height: 300))
        let d = started(windows: [w], zoomedOut: true)
        let folder = try #require(LayoutStore.folderOverride)
        defer { finish(d); try? FileManager.default.removeItem(at: folder) }
        try snapshots(10_002)
        #expect(restored(d, w, by: "expanse://layout?snapshot=1e300") == nil)
        #expect(restored(d, w, by: "expanse://layout?snapshot=1e20") == nil)
        // The 10,002nd layout is there, but 10,001 is out of range.
        #expect(restored(d, w, by: "expanse://layout?snapshot=10001") == nil)
        #expect(restored(d, w, by: "expanse://layout?snapshot=10000") == 10_000)
        #expect(restored(d, w, by: "expanse://layout?snapshot=0") == 0)
    }

    // MARK: SEC-10

    @Test("SEC-10 The minimum integer as an index does nothing; a valid index still works") func sec10() throws {
        let w = window(7, at: CGRect(x: 0, y: 33, width: 400, height: 300))
        let d = started(windows: [w], zoomedOut: true)
        defer { finish(d) }
        try snapshots(3)
        for bad in ["-9223372036854775808", "-9223372036854775809", "9223372036854775807"] {
            #expect(restored(d, w, by: "expanse://layout?snapshot=\(bad)") == nil, "\(bad)")
        }
        #expect(restored(d, w, by: "expanse://layout?snapshot=2") == 2)
    }

    // MARK: SEC-11

    @Test("SEC-11 An invalid snapshot number does nothing; none means the newest") func sec11() throws {
        let w = window(7, at: CGRect(x: 0, y: 33, width: 400, height: 300))
        let d = started(windows: [w], zoomedOut: true)
        defer { finish(d) }
        try snapshots(3)
        for bad in ["abc", "1.5", "-1", ""] {
            #expect(restored(d, w, by: "expanse://layout?snapshot=\(bad)") == nil, "\(bad)")
        }
        #expect(restored(d, w, by: "expanse://layout") == 0)
        #expect(restored(d, w, by: "expanse://layout?snapshot=2") == 2)
    }

    // MARK: SEC-12

    @Test("SEC-12 nav with delay=-5 hops straight away") func sec12a() async {
        let d = started(zoomedOut: true)
        defer { finish(d) }
        let c = d.controller
        // Every hop starts by clearing viewPlaced (with no windows it goes no further).
        c.viewPlaced = true
        open(d, "expanse://nav?dir=right&delay=-5")
        #expect(await wait(upTo: 0.5) { !c.viewPlaced })
    }

    @Test("SEC-12 nav with delay=99 hops after 10 seconds") func sec12b() async {
        let d = started(zoomedOut: true)
        defer { finish(d) }
        let c = d.controller
        c.viewPlaced = true
        let start = Date()
        open(d, "expanse://nav?dir=right&delay=99")
        try? await Task.sleep(nanoseconds: 9_000_000_000)
        #expect(c.viewPlaced)
        #expect(await wait(upTo: 3) { !c.viewPlaced })
        let took = Date().timeIntervalSince(start)
        #expect(took > 9.9 && took < 11.5)
    }

    // MARK: SEC-13

    @Test("SEC-13 Only known link commands run") func sec13a() {
        #expect(AppDelegate.commands == [
            "toggle", "centre", "center", "enter", "exit", "fit", "restore", "tidy", "layout", "welcome", "menu", "nav",
            "pause", "resume", "zoom", "pan", "space", "focus",
            "place", "prefer", "dump", "screen", "update", "appearance", "logging", "copylogs", "snapshot", "poweroff",
        ])
    }

    @Test("SEC-13 An unknown link command is ignored without logging its name") func sec13b() throws {
        let d = started()
        defer { finish(d) }
        let mark = logMark()
        open(d, "expanse://bogusq7x?x=1", "expanse://bogusq7y", "http://bogusq7z/zoom?scale=0.5")
        #expect(d.controller.animation == nil)
        let lines = try logLines(after: mark)
        #expect(lines.filter { $0 == "ignored unknown URL command" }.count == 3)
        #expect(!lines.contains { $0.contains("bogusq7") })
    }

    // MARK: SEC-14 to SEC-18 (manual: a browser, the canvas up, a running app)

    @Test("SEC-15 A web page's link while zoomed out is refused without asking (logic)") func sec15() throws {
        let d = started(zoomedOut: true)
        defer { finish(d) }
        // Zoomed in it would ask (NSAlert.runModal): only ever called zoomed out here.
        try #require(d.controller.isActive)
        #expect(!d.allowFromWebPage("tidy", in: "Google Chrome"))
    }

    @Test("SEC-17 Links from scripts and other apps run without asking (logic)") func sec17() {
        let d = started()
        defer { finish(d) }
        // No Apple event from a browser behind it: no browser, so no question.
        #expect(d.browserSending() == nil)
        open(d, "expanse://zoom?scale=0.5")
        #expect(d.controller.animation?.to.scale == 0.5)
    }

    @Test("SEC-18 Debug link commands run in a development build when turned on (logic)") func sec18() throws {
        try #require(!Updater.shared.isRelease)
        let w = window(7, at: CGRect(x: 0, y: 33, width: 400, height: 300))
        let d = started(windows: [w])
        let appearance = NSApp.appearance
        defer { finish(d); NSApp.appearance = appearance }
        let c = d.controller
        holdGlides(c)
        let mark = logMark()
        Env.withDefaults(["debugURLCommands": true]) {
            #expect(AppDelegate.debugURLCommands)
            let q = c.focusQuery
            open(d, "expanse://place?id=7&x=500&y=600", "expanse://appearance?mode=light", "expanse://focus?id=7")
            #expect(w.canvasFrame.origin == CGPoint(x: 500, y: 600))
            #expect(NSApp.appearance?.name == .aqua)
            #expect(c.focusQuery == q + 1)
        }
        let lines = try logLines(after: mark)
        #expect(!lines.contains { $0.hasPrefix("ignored debug URL command") })
    }

    // MARK: SEC-19

    @Test("SEC-19 Absurd window sizes and positions from an app are ignored") func sec19() {
        for v: CGFloat in [0, 1, -1, 1_000_000, -1_000_000, 1512.5] { #expect(AX.plausible(v), "\(v)") }
        for v: CGFloat in [.nan, .infinity, -.infinity, 1_000_000.5, -1_000_001, 1e300, .greatestFiniteMagnitude] {
            #expect(!AX.plausible(v), "\(v)")
        }
        // No answer at all is unknown too. (A value of the wrong type can't be handed in without
        // a real app: AX.position and AX.size ask it first.)
        let element = AXUIElementCreateApplication(Self.noPID)
        #expect(AX.position(element) == nil)
        #expect(AX.size(element) == nil)
    }

    // MARK: SEC-20

    @Test("SEC-20 Capture sizes are capped") func sec20() {
        func size(_ w: CGFloat, _ h: CGFloat) -> (Int, Int) {
            let c = WindowCapture.configuration(pixelSize: CGSize(width: w, height: h), fps: 30)
            return (c.width, c.height)
        }
        #expect(size(.nan, .infinity) == (2, 2))
        #expect(size(-.infinity, 1e9) == (2, 16_384))
        #expect(size(100_000, 0) == (16_384, 2))
        #expect(size(16_384.4, 16_385) == (16_384, 16_384))
        #expect(size(1.2, -50) == (2, 2))
        #expect(size(1919.6, 1080.2) == (1920, 1080))
        #expect(size(.greatestFiniteMagnitude, -.greatestFiniteMagnitude) == (16_384, 2))
        let slow = WindowCapture.configuration(pixelSize: CGSize(width: 800, height: 600), fps: 0)
        #expect(slow.minimumFrameInterval == CMTime(value: 1, timescale: 1))
    }

    // MARK: SEC-24

    @Test("SEC-24 The stream limit can only be lowered") func sec24() {
        #expect(CanvasController.streamBudget(setting: 64) == 16)
        #expect(CanvasController.streamBudget(setting: 8) == 8)
        #expect(CanvasController.streamBudget(setting: 0) == 16)
        #expect(CanvasController.streamBudget(setting: -3) == 16)
        #expect(CanvasController.streamBudget(setting: 17) == 16)
        #expect(CanvasController.streamBudget(setting: 1) == 1)
        #expect(CanvasController.streamBudget(setting: 16) == 16)
        #expect((1...16).contains(CanvasController.streamBudget))
    }
}
