import Testing
import AppKit
@_private(sourceFile: "AppDelegate.swift") @testable import Expanse
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "LayoutStore.swift") @testable import Expanse
@_private(sourceFile: "Updater.swift") @testable import Expanse

/// docs/regression/url-scripting.md. Links go through AppDelegate.application(_:open:) as macOS
/// hands them over, to an AppDelegate that was never launched (no status item, shortcuts, window
/// scans or anything on screen) whose controller has fake windows on a pretend display.
@MainActor @Suite("URL: expanse:// scripting", .serialized) struct URLTests {

    // MARK: Helpers

    /// Window IDs no real window is likely to have.
    static let a: CGWindowID = 900_001, b: CGWindowID = 900_002, c: CGWindowID = 900_003

    static func makeApp(_ windows: [ManagedWindow] = [], on: Bool = true) -> AppDelegate {
        Env.isolate()
        let app = AppDelegate()
        let c = app.controller
        let d = TestDisplay.laptop
        c.displayOverride = (d.frame, d.usable)
        c.updateOverlayFrame()
        // A fake window has nothing to capture: never ask for a first picture of one.
        for w in windows { w.needsFirstFrame = false }
        c.windows = windows
        // Past the walkthrough (URL commands wait for it).
        app.isOn = on
        return app
    }

    static func window(_ id: CGWindowID, _ app: String = "Example", at origin: CGPoint, size: CGSize = CGSize(width: 600, height: 400)) -> ManagedWindow {
        Fake.window(id: id, bundleID: "com.example.\(app.lowercased())", appName: app, canvas: CGRect(origin: origin, size: size))
    }

    /// A link, as macOS hands it over.
    static func open(_ app: AppDelegate, _ link: String) {
        app.application(NSApplication.shared, open: [URL(string: link)!])
    }

    /// The canvas open and zoomed out, as far as the controller's state goes: nothing is shown.
    static func zoomOut(_ c: CanvasController, scale: CGFloat = 0.4, origin: CGPoint = CGPoint(x: -200, y: -150)) {
        c.isActive = true
        c.camera = Camera(origin: origin, scale: scale)
    }

    /// Runs `body` with captures held back, as when replayd isn't answering, so nothing asks
    /// ScreenCaptureKit for pictures of the fake windows; then stops whatever the command left
    /// running (the camera animation, the snapshot timer), so nothing fires after the test.
    static func held(_ app: AppDelegate, _ body: () throws -> Void) rethrows {
        let was = WindowCapture.replaydStuck
        WindowCapture.replaydStuck = true
        defer {
            let c = app.controller
            c.cancelAnimation()
            c.snapshotTimer?.invalidate()
            c.snapshotTimer = nil
            c.isActive = false
            c.gliding = false
            c.glideTarget = nil
            c.windows = []
            WindowCapture.replaydStuck = was
        }
        try body()
    }

    /// A link's query and numbers, read the way application(_:open:) reads them, for the helpers
    /// runURLCommand hands them to.
    static func parse(_ link: String) -> (query: [String: String], number: (String) -> CGFloat?) {
        let query = Dictionary((URLComponents(string: link)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                               uniquingKeysWith: { first, _ in first })
        return (query, { key in
            guard let d = Double(query[key] ?? ""), d.isFinite else { return nil }
            return CGFloat(d)
        })
    }

    static func close(_ p: CGPoint, _ q: CGPoint) -> Bool { abs(p.x - q.x) < 0.001 && abs(p.y - q.y) < 0.001 }

    /// The visible canvas for a camera.
    static func view(_ camera: Camera, _ c: CanvasController) -> CGRect {
        camera.toCanvas(CGRect(origin: .zero, size: c.viewport.size))
    }

    // MARK: URL-03

    @Test("URL-03 expanse://exit at 100% does nothing (logic)") func url03() {
        let app = Self.makeApp([Self.window(Self.a, at: CGPoint(x: 100, y: 100))])
        let c = app.controller
        Self.held(app) {
            c.camera = Camera(origin: CGPoint(x: 40, y: 0), scale: 1)
            Self.open(app, "expanse://exit")
            #expect(!c.isActive)
            #expect(c.animation == nil)
            #expect(c.camera == Camera(origin: CGPoint(x: 40, y: 0), scale: 1))
        }
    }

    // MARK: URL-04

    @Test("URL-04 fitCamera puts every window in view, at up to 100%") func url04a() {
        let spread = TestCanvas.make(windows: [
            Self.window(Self.a, at: CGPoint(x: -3000, y: -500), size: CGSize(width: 800, height: 600)),
            Self.window(Self.b, at: CGPoint(x: 2500, y: 1200), size: CGSize(width: 900, height: 700)),
        ])
        let fit = spread.fitCamera()
        #expect(fit.scale < 1)
        for w in spread.windows { #expect(Self.view(fit, spread).contains(w.canvasFrame)) }

        // A few small windows close together: 100%, never more.
        let small = TestCanvas.make(windows: [
            Self.window(Self.a, at: CGPoint(x: 0, y: 0), size: CGSize(width: 300, height: 200)),
            Self.window(Self.b, at: CGPoint(x: 400, y: 100), size: CGSize(width: 300, height: 200)),
        ])
        let close = small.fitCamera()
        #expect(close.scale == 1)
        for w in small.windows { #expect(Self.view(close, small).contains(w.canvasFrame)) }
    }

    @Test("URL-04 expanse://fit while zoomed out and panned away heads for every window in view") func url04b() throws {
        let app = Self.makeApp([
            Self.window(Self.a, at: CGPoint(x: -1500, y: 0), size: CGSize(width: 800, height: 600)),
            Self.window(Self.b, at: CGPoint(x: 1800, y: 900), size: CGSize(width: 800, height: 600)),
        ])
        let c = app.controller
        try Self.held(app) {
            Self.zoomOut(c, scale: 0.3, origin: CGPoint(x: 20_000, y: 20_000))
            Self.open(app, "expanse://fit")
            let to = try #require(c.animation?.to)
            #expect(to == c.fitCamera())
            #expect(to.scale <= 1)
            for w in c.windows { #expect(Self.view(to, c).contains(w.canvasFrame)) }
        }
    }

    // MARK: URL-05

    @Test("URL-05 Camera.zoom clamps to 3%-150% and keeps the point under the anchor still") func url05a() {
        var cam = Camera(origin: CGPoint(x: 100, y: 50), scale: 0.4)
        let anchor = CGPoint(x: 756, y: 474)
        let under = cam.toCanvas(anchor)
        cam.zoom(to: 0.5, anchor: anchor)
        #expect(cam.scale == 0.5)
        #expect(Self.close(cam.toCanvas(anchor), under))
        cam.zoom(to: 9, anchor: anchor)
        #expect(cam.scale == 1.5)
        #expect(Camera.maxScale == 1.5)
        #expect(Self.close(cam.toCanvas(anchor), under))
        cam.zoom(to: 0.000_1, anchor: anchor)
        #expect(cam.scale == Camera.minScale)
        let before = cam
        cam.zoom(to: .nan, anchor: anchor)
        cam.zoom(to: .infinity, anchor: anchor)
        #expect(cam == before)
    }

    @Test("URL-05 expanse://zoom?scale=0.5 zooms to 50% around the middle of the screen") func url05b() throws {
        let app = Self.makeApp([Self.window(Self.a, at: CGPoint(x: 0, y: 0))])
        let c = app.controller
        try Self.held(app) {
            Self.zoomOut(c, scale: 0.25)
            let middle = CGPoint(x: c.viewport.width / 2, y: c.viewport.height / 2)
            let centre = c.camera.toCanvas(middle)
            Self.open(app, "expanse://zoom?scale=0.5")
            let to = try #require(c.animation?.to)
            #expect(to.scale == 0.5)
            #expect(Self.close(to.toCanvas(middle), centre))
        }
    }

    @Test("URL-05 expanse://zoom?scale=9 is clamped to 150%; a non-number is ignored") func url05c() {
        let app = Self.makeApp([Self.window(Self.a, at: CGPoint(x: 0, y: 0))])
        let c = app.controller
        Self.held(app) {
            Self.zoomOut(c, scale: 0.25)
            Self.open(app, "expanse://zoom?scale=9")
            #expect(c.animation?.to.scale == 1.5)
            c.cancelAnimation()
            let before = c.camera
            for link in ["expanse://zoom?scale=abc", "expanse://zoom?scale=nan", "expanse://zoom?scale=inf", "expanse://zoom?scale=",
                         "expanse://zoom"] {
                Self.open(app, link)
                #expect(c.animation == nil, "\(link)")
                #expect(c.camera == before, "\(link)")
            }
        }
    }

    // MARK: URL-06

    @Test("URL-06 Camera.pan moves the content by screen points at any zoom") func url06a() {
        var cam = Camera(origin: CGPoint(x: 10, y: 20), scale: 0.5)
        let p = CGPoint(x: 300, y: 400)
        let before = cam.toView(p)
        cam.pan(by: CGVector(dx: 100, dy: 0))
        #expect(cam.toView(p).x - before.x == 100)
        #expect(cam.toView(p).y == before.y)
        let moved = cam
        cam.pan(by: CGVector(dx: CGFloat.infinity, dy: CGFloat.nan))
        #expect(cam == moved)
    }

    @Test("URL-06 expanse://pan?dx=100&dy=0 moves the open canvas 100 points right, at once") func url06b() {
        let w = Self.window(Self.a, at: CGPoint(x: 300, y: 200))
        let app = Self.makeApp([w])
        let c = app.controller
        Self.held(app) {
            Self.zoomOut(c, scale: 0.5)
            let before = c.camera.toView(w.canvasFrame.origin)
            Self.open(app, "expanse://pan?dx=100&dy=0")
            let after = c.camera.toView(w.canvasFrame.origin)
            #expect(after.x - before.x == 100)
            #expect(after.y == before.y)
            #expect(c.animation == nil)
        }
    }

    @Test("URL-06 expanse://pan does nothing with the canvas closed") func url06c() {
        let app = Self.makeApp([Self.window(Self.a, at: CGPoint(x: 300, y: 200))])
        let c = app.controller
        Self.held(app) {
            let before = c.camera
            Self.open(app, "expanse://pan?dx=100&dy=0")
            #expect(c.camera == before)
            #expect(!c.isActive)
        }
    }

    // MARK: URL-07

    @Test("URL-07 expanse://focus?app= goes to that app's front-most window, any case; an unknown app does nothing (logic)",
          arguments: ["safari", "Safari", "SAFARI"])
    func url07(_ name: String) throws {
        // Back to front: the second Safari window is the front-most.
        let back = Self.window(Self.a, "Safari", at: CGPoint(x: 0, y: 0))
        let front = Self.window(Self.b, "Safari", at: CGPoint(x: 900, y: 0))
        let notes = Self.window(Self.c, "Notes", at: CGPoint(x: 0, y: 600))
        let app = Self.makeApp([back, front, notes])
        let c = app.controller
        try Self.held(app) {
            // Zoomed out it dives into the window (at 100% the glide would bring the overlay up).
            Self.zoomOut(c)
            Self.open(app, "expanse://focus?app=NoSuchApp")
            #expect(c.animation == nil)
            Self.open(app, "expanse://focus?app=\(name)")
            let to = try #require(c.animation?.to)
            #expect(to == c.focusCamera(for: front))
            #expect(c.windows.last === front)
        }
    }

    // MARK: URL-09

    @Test("URL-09 expanse://pause pauses; a second pause does nothing (logic)") func url09() {
        let app = Self.makeApp([Self.window(Self.a, at: CGPoint(x: 0, y: 0)), Self.window(Self.b, at: CGPoint(x: 700, y: 0))])
        let c = app.controller
        Self.held(app) {
            Self.open(app, "expanse://pause")
            #expect(c.isPaused)
            // Windows handed back to macOS: nothing left on the canvas.
            #expect(c.windows.isEmpty)
            let late = Self.window(Self.c, at: CGPoint(x: 0, y: 0))
            late.needsFirstFrame = false
            c.windows = [late]
            Self.open(app, "expanse://pause")
            #expect(c.isPaused)
            #expect(c.windows.count == 1)
        }
    }

    // MARK: URL-12

    @Test("URL-12 expanse://nav reads a direction and a delay of 0-10s; other directions do nothing") func url12() {
        func hop(_ query: String) -> (CanvasController.Direction, Double)? {
            let (q, number) = Self.parse("expanse://nav?\(query)")
            return AppDelegate.navHop(q, number: number).map { ($0.direction, $0.delay) }
        }
        let plain: [(String, CanvasController.Direction)] = [("right", .right), ("left", .left), ("up", .up), ("down", .down)]
        for (name, direction) in plain {
            #expect(hop("dir=\(name)")?.0 == direction)
            #expect(hop("dir=\(name)")?.1 == 0)
        }
        #expect(hop("dir=sideways") == nil)
        #expect(hop("") == nil)
        #expect(hop("dir=right&delay=2")?.1 == 2)
        #expect(hop("dir=right&delay=99")?.1 == 10)
        #expect(hop("dir=right&delay=-5")?.1 == 0)
        #expect(hop("dir=right&delay=abc")?.1 == 0)
    }

    // MARK: URL-13

    @Test("URL-13 expanse://prefer sets a window's chosen size (debug commands on)") func url13a() {
        let w = Self.window(Self.a, at: CGPoint(x: 0, y: 0)), other = Self.window(Self.b, at: CGPoint(x: 700, y: 0))
        let app = Self.makeApp([w, other])
        Env.withDefaults(["debugURLCommands": true]) {
            Self.held(app) {
                Self.open(app, "expanse://prefer?id=\(Self.a)&w=900&h=700")
                #expect(w.preferredSize == CGSize(width: 900, height: 700))
                #expect(other.preferredSize == CGSize(width: 600, height: 400))
                // No such window: nothing changes.
                Self.open(app, "expanse://prefer?id=12345&w=300&h=300")
                #expect(w.preferredSize == CGSize(width: 900, height: 700))
                #expect(other.preferredSize == CGSize(width: 600, height: 400))
            }
        }
    }

    @Test("URL-13 expanse://prefer is ignored with debug commands off") func url13b() {
        let w = Self.window(Self.a, at: CGPoint(x: 0, y: 0))
        let app = Self.makeApp([w])
        Env.withDefaults(["debugURLCommands": false]) {
            Self.held(app) {
                Self.open(app, "expanse://prefer?id=\(Self.a)&w=900&h=700")
                #expect(w.preferredSize == CGSize(width: 600, height: 400))
            }
        }
    }

    // MARK: URL-14

    @Test("URL-14 expanse://place moves a window's canvas spot; the real window waits for the next commit") func url14a() {
        let w = Self.window(Self.a, at: CGPoint(x: 100, y: 100))
        let app = Self.makeApp([w])
        Env.withDefaults(["debugURLCommands": true]) {
            Self.held(app) {
                w.lastPlaced = CGPoint(x: 100, y: 133)
                Self.open(app, "expanse://place?id=\(Self.a)&x=0&y=0")
                #expect(w.canvasFrame.origin == .zero)
                // Not committed: the real window hasn't been placed again.
                #expect(w.lastPlaced == CGPoint(x: 100, y: 133))
            }
        }
    }

    @Test("URL-14 expanse://place&commit=1 re-places the real windows straight away") func url14b() {
        let w = Self.window(Self.a, at: CGPoint(x: 100, y: 100))
        let away = Self.window(Self.b, at: CGPoint(x: 5000, y: 100))
        let app = Self.makeApp([w, away])
        Env.withDefaults(["debugURLCommands": true]) {
            Self.held(app) {
                w.lastPlaced = CGPoint(x: 100, y: 133)
                away.lastPlaced = CGPoint(x: 5000, y: 133)
                Self.open(app, "expanse://place?id=\(Self.a)&x=200&y=100&commit=1")
                #expect(w.canvasFrame.origin == CGPoint(x: 200, y: 100))
                // A commit: every window placed afresh (a fake window can't really move, so none
                // records a spot), the one out of view parked.
                #expect(w.lastPlaced == nil)
                #expect(away.lastPlaced == nil)
                #expect(!w.parked)
                #expect(away.parked)
            }
        }
    }

    // MARK: URL-16, URL-17

    static let spaces = [
        Spaces.Space(id: 11, pid: nil, window: nil, name: "Desktop 1"),
        Spaces.Space(id: 12, pid: nil, window: nil, name: "Desktop 2"),
        Spaces.Space(id: 13, pid: 501, window: 77, name: "Safari"),
    ]

    @Test("URL-16 expanse://space finds a Space by name in any case, before its position; an unknown name does nothing") func url16() {
        func space(_ link: String) -> UInt64? {
            let (q, number) = Self.parse(link)
            let index = number("index").flatMap { Int(exactly: $0) }
            return AppDelegate.space(named: q["name"] ?? "", at: index, in: Self.spaces, canvas: nil)?.id
        }
        #expect(space("expanse://space?name=safari") == 13)
        #expect(space("expanse://space?name=SAFARI") == 13)
        #expect(space("expanse://space?name=Desktop%202") == 12)
        #expect(space("expanse://space?index=1") == 11)
        #expect(space("expanse://space?index=3") == 13)
        #expect(space("expanse://space?name=nonesuch") == nil)
        // The name wins over the position.
        #expect(space("expanse://space?name=safari&index=1") == 13)
        #expect(space("expanse://space?index=0") == nil)
        #expect(space("expanse://space?index=4") == nil)
        #expect(space("expanse://space") == nil)
    }

    @Test("URL-17 expanse://space?name=expanse (or canvas) is the canvas's own Space") func url17() {
        var asked = 0
        func canvas() -> UInt64? { asked += 1; return 12 }
        for name in ["expanse", "Expanse", "canvas", "CANVAS"] {
            #expect(AppDelegate.space(named: name, at: nil, in: Self.spaces, canvas: canvas())?.id == 12)
        }
        #expect(asked > 0)
        // Other names never ask where the canvas is.
        asked = 0
        #expect(AppDelegate.space(named: "Safari", at: nil, in: Self.spaces, canvas: canvas())?.id == 13)
        #expect(asked == 0)
        // Nowhere to go when the canvas's Space isn't known.
        #expect(AppDelegate.space(named: "expanse", at: nil, in: Self.spaces, canvas: nil) == nil)
        // The controller's answer is the Space of its front window: none with no windows.
        let app = Self.makeApp()
        #expect(app.controller.canvasDesktop == nil)
    }

    // MARK: URL-18

    @Test("URL-18 expanse://focus?id= goes to that window (debug commands on)") func url18a() throws {
        let one = Self.window(Self.a, "Safari", at: CGPoint(x: 0, y: 0))
        let two = Self.window(Self.b, "Safari", at: CGPoint(x: 900, y: 0))
        let app = Self.makeApp([one, two])
        let c = app.controller
        try Env.withDefaults(["debugURLCommands": true]) {
            try Self.held(app) {
                // Zoomed out it zooms in to the window (at 100% the glide would bring the overlay up).
                Self.zoomOut(c)
                Self.open(app, "expanse://focus?id=\(Self.a)")
                let to = try #require(c.animation?.to)
                #expect(to == c.focusCamera(for: one))
                #expect(to.scale == 1)
                #expect(c.windows.last === one)
            }
        }
    }

    @Test("URL-18 expanse://focus?id= is ignored with debug commands off") func url18b() {
        let app = Self.makeApp([Self.window(Self.a, at: CGPoint(x: 0, y: 0)), Self.window(Self.b, at: CGPoint(x: 900, y: 0))])
        let c = app.controller
        Env.withDefaults(["debugURLCommands": false]) {
            Self.held(app) {
                Self.zoomOut(c)
                Self.open(app, "expanse://focus?id=\(Self.a)")
                #expect(c.animation == nil)
            }
        }
    }

    // MARK: URL-19

    @Test("URL-19 A release ignores debug commands whatever the setting; a development build follows it") func url19a() {
        Env.withDefaults(["debugURLCommands": true]) {
            #expect(!AppDelegate.debugCommandsAllowed(release: true))
            #expect(AppDelegate.debugCommandsAllowed(release: false))
        }
        Env.withDefaults(["debugURLCommands": nil]) {
            #expect(!AppDelegate.debugCommandsAllowed(release: true))
            #expect(!AppDelegate.debugCommandsAllowed(release: false))
        }
    }

    @Test("URL-19 expanse://update?install=1 in a development build checks and installs nothing") func url19b() throws {
        try #require(!Updater.shared.isRelease, "the test host must not be a release")
        let app = Self.makeApp(on: false)
        var told: [String] = []
        let tell = Updater.tell
        Updater.tell = { title, _ in told.append(title) }
        defer { Updater.tell = tell }
        Env.withDefaults(["debugURLCommands": true]) {
            Self.held(app) {
                #expect(AppDelegate.debugURLCommands)
                Self.open(app, "expanse://update?install=1")
                #expect(!Updater.shared.checking)
                #expect(Updater.shared.ready == nil)
                #expect(told.isEmpty)
            }
        }
    }

    // MARK: URL-20

    @Test("URL-20 expanse://centre and expanse://center centre the window you're in", arguments: ["centre", "center"])
    func url20a(_ spelling: String) throws {
        let other = Self.window(Self.a, at: CGPoint(x: 0, y: 0))
        let current = Self.window(Self.b, at: CGPoint(x: 1400, y: 300))
        let app = Self.makeApp([current, other])
        let c = app.controller
        // Whichever app is in front, its focused window is `current` (and Accessibility isn't asked).
        for running in NSWorkspace.shared.runningApplications { c.focusedWindowByApp[running.processIdentifier] = Self.b }
        try Self.held(app) {
            // Zoomed out it zooms in to the window (at 100% the glide would bring the overlay up;
            // see url20b for that path).
            Self.zoomOut(c)
            Self.open(app, "expanse://\(spelling)")
            let to = try #require(c.animation?.to)
            #expect(to == c.focusCamera(for: current))
            #expect(c.windows.last === current)
        }
    }

    @Test("URL-20 centre at 100% glides to the window you're in", arguments: ["centre", "center"])
    func url20b(_ spelling: String) {
        let other = Self.window(Self.a, at: CGPoint(x: 0, y: 0))
        let current = Self.window(Self.b, at: CGPoint(x: 1400, y: 300))
        let app = Self.makeApp([current, other])
        let c = app.controller
        for running in NSWorkspace.shared.runningApplications { c.focusedWindowByApp[running.processIdentifier] = Self.b }
        Self.held(app) {
            // A glide already under way takes the new target without bringing the overlay up
            // again (see glide(to:)); links wait for it to finish, so the command runs directly.
            c.gliding = true
            app.runURLCommand(spelling, query: [:], number: { _ in nil })
            #expect(c.glideTarget === current)
            #expect(c.animation?.to == c.focusCamera(for: current))
        }
    }

    // MARK: URL-21

    @Test("URL-21 expanse://appearance picks light or dark for Expanse, or follows the Mac (logic)") func url21() {
        let app = Self.makeApp()
        let was = NSApp.appearance
        defer { NSApp.appearance = was }
        Env.withDefaults(["debugURLCommands": true]) {
            Self.open(app, "expanse://appearance?mode=dark")
            #expect(NSApp.appearance?.name == .darkAqua)
            Self.open(app, "expanse://appearance?mode=light")
            #expect(NSApp.appearance?.name == .aqua)
            Self.open(app, "expanse://appearance")
            #expect(NSApp.appearance == nil)
            Self.open(app, "expanse://appearance?mode=dark")
            Self.open(app, "expanse://appearance?mode=sepia")
            #expect(NSApp.appearance == nil)
        }
        Env.withDefaults(["debugURLCommands": false]) {
            Self.open(app, "expanse://appearance?mode=dark")
            #expect(NSApp.appearance == nil)
        }
    }

    // MARK: URL-22

    @Test("URL-22 expanse://layout?snapshot=N restores snapshot N, 0 the newest; other numbers do nothing (logic)") func url22() {
        let w = Self.window(Self.a, at: CGPoint(x: 0, y: 0))
        let app = Self.makeApp([w])
        let c = app.controller
        // Three snapshots, taken on this screen, newest first: the window at x = 100, 200, 300.
        for (time, x) in [(3000, 100.0), (2000, 200.0), (1000, 300.0)] {
            var layout = SavedLayout.with([.entry(bundleID: w.bundleID, appName: w.appName, x: x, y: 0, w: 600, h: 400)])
            layout.fittedWidth = Double(c.viewport.width)
            layout.fittedHeight = Double(c.viewport.height)
            LayoutStore.write(layout, to: LayoutStore.snapshotFolder.appendingPathComponent("\(time).json"))
        }
        Self.held(app) {
            // Restoring shows the canvas zoomed out; here it's open already.
            Self.zoomOut(c)
            Self.open(app, "expanse://layout?snapshot=2")
            #expect(w.canvasFrame.origin.x == 300)
            Self.open(app, "expanse://layout")
            #expect(w.canvasFrame.origin.x == 100)
            Self.open(app, "expanse://layout?snapshot=1")
            #expect(w.canvasFrame.origin.x == 200)
            for bad in ["7", "abc", "-1", "1.5", "nan", "10001"] {
                Self.open(app, "expanse://layout?snapshot=\(bad)")
                #expect(w.canvasFrame.origin.x == 200, "snapshot=\(bad)")
            }
        }
    }

    // MARK: URL-23

    @Test("URL-23 expanse://place moves the window's home spot with it (logic)") func url23() {
        let w = Self.window(Self.a, at: CGPoint(x: 0, y: 0))
        let app = Self.makeApp([w, Self.window(Self.b, at: CGPoint(x: 700, y: 0))])
        let c = app.controller
        Env.withDefaults(["debugURLCommands": true]) {
            Self.held(app) {
                // On the big screen (no window shrunk to fit): the new spot is its home spot.
                #expect(!c.isDerived)
                Self.open(app, "expanse://place?id=\(Self.a)&x=40&y=900&commit=1")
                #expect(w.canvasFrame.origin == CGPoint(x: 40, y: 900))
                #expect(w.home == CGPoint(x: 40, y: 900))
            }
        }
    }
}
