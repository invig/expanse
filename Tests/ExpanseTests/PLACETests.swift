import Testing
import AppKit
import ScreenCaptureKit
@_private(sourceFile: "CanvasController.swift") @testable import Expanse

/// docs/regression/new-windows.md. Window scans are fed by hand: fake ScreenCaptureKit windows
/// and an Accessibility snapshot saying which are standard windows, straight into apply().
@MainActor @Suite("PLACE: New windows and where they go", .serialized) struct PLACETests {

    // MARK: Helpers

    /// A running canvas (past its first scan) on the laptop display, camera at the origin, so a
    /// canvas point is its screen point less the 33pt menu bar.
    static func canvas(_ windows: [ManagedWindow] = [], display: TestDisplay = .laptop) -> CanvasController {
        let c = TestCanvas.make(display: display, windows: windows)
        c.firstSync = false
        // No one-off pictures of fake windows (pumpSnapshotsSoon does nothing while this is set).
        c.snapshotTimer = Timer(timeInterval: 3600, repeats: false) { _ in }
        return c
    }

    /// Leaves the canvas inert: nothing it scheduled can scan, glide or move anything later.
    static func finish(_ c: CanvasController) {
        c.cancelAnimation()
        c.syncSoonWork?.cancel(); c.syncSoonWork = nil
        c.recheckWork?.cancel(); c.recheckWork = nil
        c.saveWork?.cancel()
        c.isPaused = true
    }

    /// Glides that start are recorded (glideTarget, glideGeneration) without the overlay coming up
    /// or anything taking focus: glide() then acts as for a hop during a glide.
    static func watchGlides(_ c: CanvasController) { c.gliding = true }

    /// The real (global) frame of a canvas frame, with the camera at the origin.
    static func real(_ canvas: CGRect, _ c: CanvasController) -> CGRect { canvas.offsetBy(dx: 0, dy: c.viewport.minY) }

    /// A window Expanse placed at its canvas spot: its real window is there.
    static func placed(_ id: CGWindowID, pid: pid_t = Fake.firstPID, bundleID: String = "com.example.app",
                       appName: String = "Example", canvas: CGRect) -> ManagedWindow {
        let real = canvas.offsetBy(dx: 0, dy: TestDisplay.laptop.menuBar)
        let w = Fake.window(id: id, pid: pid, bundleID: bundleID, appName: appName, canvas: canvas, real: real)
        w.lastPlaced = real.origin
        return w
    }

    /// A window seen for the first time, where its app put it (global).
    static func newWindow(_ id: CGWindowID, pid: pid_t = Fake.firstPID, bundleID: String = "com.example.app",
                          appName: String = "Example", at real: CGRect) -> SCWindow {
        Fake.regularApp(pid)
        return Fake.scWindow(id: id, pid: pid, bundleID: bundleID, appName: appName, frame: real)
    }

    /// One window scan: `scWindows` on screen, `standard` the new ones Accessibility says are
    /// standard document windows (their kind already asked, as a real scan leaves it).
    static func scan(_ c: CanvasController, _ scWindows: [SCWindow], standard: [CGWindowID] = [],
                     known: [CGWindowID] = [], stale: Bool = false) {
        var ax = CanvasController.AXSnapshot()
        for id in standard {
            ax.standard.insert(id)
            ax.known.insert(id)
            c.windowKinds[id] = CanvasController.WindowKind(standard: true, at: CACurrentMediaTime())
        }
        ax.known.formUnion(known)
        c.apply(scWindows, ax: ax, stale: stale)
    }

    static func window(_ c: CanvasController, _ id: CGWindowID) -> ManagedWindow? { c.windows.first { $0.id == id } }

    /// Whether `r` overlaps any of `others` or comes closer than the standard gap.
    static func crowds(_ r: CGRect, _ others: [CGRect]) -> Bool {
        others.contains { $0.insetBy(dx: -CanvasController.gap / 2, dy: -CanvasController.gap / 2).intersects(r) }
    }

    // MARK: PLACE-01

    @Test("PLACE-01 Windows on another display aren't taken on")
    func place01() {
        let c = Self.canvas()
        defer { Self.finish(c) }
        let elsewhere = Fake.scWindow(id: 101, frame: CGRect(x: 1600, y: 200, width: 800, height: 600))
        let left = Fake.scWindow(id: 102, frame: CGRect(x: -1000, y: 200, width: 800, height: 600))
        let here = Fake.scWindow(id: 103, frame: CGRect(x: 200, y: 200, width: 800, height: 600))
        #expect(!c.isManageable(elsewhere, tracked: false, regular: { _ in true }))
        #expect(!c.isManageable(left, tracked: false, regular: { _ in true }))
        #expect(c.isManageable(here, tracked: false, regular: { _ in true }))
        // A window already on the canvas stays tracked wherever it goes (b6f69cf).
        #expect(c.isManageable(elsewhere, tracked: true, regular: { _ in true }))
    }

    @Test("PLACE-01 A new window on another display isn't added; a tracked one that moves there stays")
    func place01b() {
        let a = Self.placed(111, canvas: CGRect(x: 200, y: 200, width: 600, height: 400))
        let c = Self.canvas([a])
        defer { Self.finish(c) }
        let other = Self.newWindow(112, at: CGRect(x: 1700, y: 100, width: 800, height: 600))
        // A moved onto the other display (parked beyond the edge of a screen that got smaller, say).
        let moved = Fake.scWindow(id: 111, frame: CGRect(x: 1600, y: 300, width: 600, height: 400))
        Self.scan(c, [moved, other], standard: [112])
        #expect(Self.window(c, 112) == nil)
        #expect(Self.window(c, 111) != nil)
    }

    // MARK: PLACE-02

    @Test("PLACE-02 Only ordinary app windows on the main display are managed")
    func place02() {
        let c = Self.canvas()
        defer { Self.finish(c) }
        let f = CGRect(x: 100, y: 100, width: 400, height: 300)
        func manageable(_ w: SCWindow, regular: Bool = true) -> Bool {
            c.isManageable(w, tracked: false, regular: { _ in regular })
        }
        #expect(manageable(Fake.scWindow(id: 201, frame: f)))
        // Not at normal window level (menus, a menu-bar extra's popover, panels above windows).
        #expect(!manageable(Fake.scWindow(id: 202, frame: f, layer: 8)))
        #expect(!manageable(Fake.scWindow(id: 203, frame: f, layer: 25)))
        #expect(!manageable(Fake.scWindow(id: 204, frame: f, onScreen: false)))
        // Under 100×60pt.
        #expect(!manageable(Fake.scWindow(id: 205, frame: CGRect(x: 100, y: 100, width: 99, height: 300))))
        #expect(!manageable(Fake.scWindow(id: 206, frame: CGRect(x: 100, y: 100, width: 400, height: 59))))
        #expect(manageable(Fake.scWindow(id: 207, frame: CGRect(x: 100, y: 100, width: 100, height: 60))))
        // An app without a Dock icon (a menu-bar extra, a background process).
        #expect(!manageable(Fake.scWindow(id: 208, frame: f), regular: false))
        // Expanse's own windows.
        #expect(!manageable(Fake.scWindow(id: 209, pid: getpid(), frame: f)))
        // Phone and FaceTime calls.
        #expect(!manageable(Fake.scWindow(id: 210, bundleID: "com.apple.FaceTime", frame: f)))
        #expect(!manageable(Fake.scWindow(id: 211, bundleID: "com.apple.mobilephone", frame: f)))
    }

    @Test("PLACE-02 A helper process drawing an app's window counts as that app")
    func place02b() {
        let owner: pid_t = 90_201, helper: pid_t = 90_202
        Fake.regularApp(owner)
        Fake.regularApp(helper, ownedBy: owner)
        #expect(CanvasController.appPID(owning: helper) == owner)
        #expect(!CanvasController.isRegularApp(helper))
        let c = Self.canvas()
        defer { Self.finish(c) }
        let sc = Fake.scWindow(id: 220, pid: helper, appName: "Steam Helper", frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        Self.scan(c, [sc], standard: [220])
        let w = try? #require(Self.window(c, 220))
        #expect(w?.pid == helper)
        #expect(w?.appPID == owner)
    }

    // MARK: PLACE-03

    @Test("PLACE-03 A new window opens in free space beside the window it came from")
    func place03() {
        Env.withDefaults(["autoCentre": true]) {
            let a = Self.placed(301, appName: "TextEdit", canvas: CGRect(x: 500, y: 300, width: 400, height: 300))
            let c = Self.canvas([a])
            defer { Self.finish(c) }
            Self.watchGlides(c)
            let camera = c.camera
            // Where TextEdit put it: over the middle of the screen.
            let n = Self.newWindow(302, appName: "TextEdit", at: CGRect(x: 40, y: 60, width: 300, height: 200))
            Self.scan(c, [a.scWindow, n], standard: [302])
            let w = try? #require(Self.window(c, 302))
            // Right of A, exactly 20pt away, top edges lined up.
            #expect(w?.canvasFrame.origin == CGPoint(x: 920, y: 300))
            #expect(!Self.crowds(w?.canvasFrame ?? .null, [a.canvasFrame]))
            // On screen, so the view doesn't move.
            #expect(c.glideGeneration == 0)
            #expect(c.camera == camera)
        }
    }

    @Test("PLACE-03 No room on the right: below, then left, above only as a last resort")
    func place03b() {
        let a = Fake.window(id: 311, canvas: CGRect(x: 500, y: 300, width: 400, height: 300))
        let c = Self.canvas([a])
        defer { Self.finish(c) }
        let w = Fake.window(id: 312, canvas: CGRect(x: 0, y: 0, width: 300, height: 200))
        func spot() -> CGPoint? { c.freeSpot(for: w, near: a, onScreenOnly: false) }
        #expect(spot() == CGPoint(x: 920, y: 300))
        // Too little room to the right.
        c.windows.append(Fake.window(id: 313, pid: 90_301, canvas: CGRect(x: 1000, y: 0, width: 400, height: 900)))
        #expect(spot() == CGPoint(x: 500, y: 620))
        // Below taken too.
        c.windows.append(Fake.window(id: 314, pid: 90_301, canvas: CGRect(x: 0, y: 640, width: 1000, height: 300)))
        #expect(spot() == CGPoint(x: 180, y: 300))
        // And the left: above, the last resort.
        c.windows.append(Fake.window(id: 315, pid: 90_301, canvas: CGRect(x: 0, y: 250, width: 470, height: 380)))
        #expect(spot() == CGPoint(x: 500, y: 80))
    }

    @Test("PLACE-03 A spot on screen is preferred over one off screen")
    func place03c() {
        // Near the right edge: the spot to the right is off screen, the one below isn't.
        let a = Fake.window(id: 321, canvas: CGRect(x: 1100, y: 100, width: 400, height: 300))
        let c = Self.canvas([a])
        defer { Self.finish(c) }
        let w = Fake.window(id: 322, canvas: CGRect(x: 0, y: 0, width: 300, height: 200))
        #expect(c.freeSpot(for: w, near: a, onScreenOnly: false) == CGPoint(x: 1100, y: 420))
    }

    // MARK: PLACE-04 (manual)

    @Test("PLACE-04 With no free spot in view, the view glides to the new window (logic)")
    func place04() {
        Env.withDefaults(["autoCentre": true]) {
            // The screen is full.
            let a = Self.placed(401, canvas: CGRect(x: 0, y: 0, width: 1512, height: 949))
            let c = Self.canvas([a])
            defer { Self.finish(c) }
            Self.watchGlides(c)
            let n = Self.newWindow(402, at: CGRect(x: 300, y: 200, width: 600, height: 400))
            Self.scan(c, [a.scWindow, n], standard: [402])
            let w = try? #require(Self.window(c, 402))
            // Beside the source window, off screen, overlapping nothing.
            #expect(w?.canvasFrame.origin == CGPoint(x: 1532, y: 0))
            #expect(!Self.crowds(w?.canvasFrame ?? .null, [a.canvasFrame]))
            #expect(c.glideGeneration == 1)
            #expect(c.glideTarget === w)
        }
    }

    // MARK: PLACE-05 (manual)

    @Test("PLACE-05 A glide asked for while another runs still happens (logic)")
    func place05() async throws {
        let a = Self.placed(501, canvas: CGRect(x: 4000, y: 4000, width: 600, height: 400))
        let c = Self.canvas([a])
        defer { Self.finish(c) }
        // Another glide is under way.
        c.animation = CanvasController.CameraAnimation(from: c.camera, to: c.camera, start: CACurrentMediaTime(), duration: 0.3)
        c.glideWhenIdle(to: a)
        #expect(c.glideTarget == nil)
        // It finishes; the waiting glide goes ahead (it's tried every 0.1s for 2s).
        try await Task.sleep(for: .milliseconds(150))
        #expect(c.glideTarget == nil)
        c.animation = nil
        Self.watchGlides(c)
        for _ in 0..<40 where c.glideTarget == nil { try await Task.sleep(for: .milliseconds(25)) }
        c.cancelAnimation()
        #expect(c.glideTarget === a)
    }

    // MARK: PLACE-06

    @Test("PLACE-06 With auto-centre off, new windows only take free spots on screen")
    func place06() {
        let a = Fake.window(id: 601, canvas: CGRect(x: 500, y: 300, width: 400, height: 300))
        let c = Self.canvas([a])
        defer { Self.finish(c) }
        let w = Fake.window(id: 602, canvas: CGRect(x: 0, y: 0, width: 300, height: 200))
        #expect(c.freeSpot(for: w, near: a, onScreenOnly: true) == CGPoint(x: 920, y: 300))
        // The screen full: nothing on screen, though there is room off it.
        c.windows = [Fake.window(id: 603, canvas: CGRect(x: 0, y: 0, width: 1512, height: 949))]
        #expect(c.freeSpot(for: w, near: c.windows[0], onScreenOnly: true) == nil)
        #expect(c.freeSpot(for: w, near: c.windows[0], onScreenOnly: false) != nil)
    }

    @Test("PLACE-06 With auto-centre off and the screen full, a new window stays put and the view doesn't move")
    func place06b() {
        Env.withDefaults(["autoCentre": false]) {
            let a = Self.placed(611, canvas: CGRect(x: 0, y: 0, width: 1512, height: 949))
            let c = Self.canvas([a])
            defer { Self.finish(c) }
            Self.watchGlides(c)
            let camera = c.camera
            let n = Self.newWindow(612, at: CGRect(x: 300, y: 200, width: 600, height: 400))
            Self.scan(c, [a.scWindow, n], standard: [612])
            let w = try? #require(Self.window(c, 612))
            // Where TextEdit put it.
            #expect(w?.canvasFrame.origin == CGPoint(x: 300, y: 200 - c.viewport.minY))
            #expect(c.glideGeneration == 0)
            #expect(c.camera == camera)
        }
    }

    // MARK: PLACE-07

    @Test("PLACE-07 Sheets, dialogs and floating panels stay with their app")
    func place07() {
        let doc = Self.placed(701, canvas: CGRect(x: 100, y: 100, width: 600, height: 400))
        let panel = Self.placed(702, canvas: CGRect(x: 800, y: 100, width: 300, height: 400))
        let c = Self.canvas([doc, panel])
        defer { Self.finish(c) }
        // A sheet: Accessibility knows it, and it isn't a standard window.
        let sheet = Self.newWindow(703, at: CGRect(x: 150, y: 160, width: 500, height: 300))
        // Not (yet) one of the app's Accessibility windows at all.
        let unknown = Self.newWindow(704, at: CGRect(x: 200, y: 600, width: 400, height: 200))
        let another = Self.newWindow(705, at: CGRect(x: 300, y: 300, width: 400, height: 300))
        // `panel` (tracked) turns out not to be a standard window: the Fonts panel, say.
        Self.scan(c, [doc.scWindow, panel.scWindow, sheet, unknown, another], standard: [705], known: [702, 703])
        #expect(Self.window(c, 703) == nil)
        #expect(Self.window(c, 704) == nil)
        #expect(Self.window(c, 702) == nil)
        #expect(Self.window(c, 701) != nil)
        #expect(Self.window(c, 705) != nil)
    }

    // MARK: PLACE-08

    /// The screen full of the source window, then four new windows of its app in one scan.
    static func burst(focus: CGWindowID?) -> (CanvasController, [CGWindowID]) {
        let pid: pid_t = 90_801
        let a = Self.placed(801, pid: pid, appName: "Finder", canvas: CGRect(x: 0, y: 0, width: 1512, height: 949))
        let c = Self.canvas([a])
        Self.watchGlides(c)
        let ids: [CGWindowID] = [811, 812, 813, 814]
        let news = ids.enumerated().map { i, id in
            Self.newWindow(id, pid: pid, appName: "Finder", at: CGRect(x: 200 + i * 20, y: 200 + i * 20, width: 600, height: 400))
        }
        if let focus { c.focusedWindowByApp[pid] = focus }
        Self.scan(c, [a.scWindow] + news, standard: ids)
        return (c, ids)
    }

    @Test("PLACE-08 Several new windows from one scan: one glide, to the one in front")
    func place08() {
        Env.withDefaults(["autoCentre": true]) {
            let (c, ids) = Self.burst(focus: 812)
            defer { Self.finish(c) }
            let news = ids.compactMap { Self.window(c, $0) }
            #expect(news.count == 4)
            // Each in a spot of its own, overlapping nothing.
            for w in news {
                #expect(!Self.crowds(w.canvasFrame, c.windows.filter { $0 !== w }.map(\.canvasFrame)))
            }
            #expect(c.glideGeneration == 1)
            #expect(c.glideTarget?.id == 812)
        }
    }

    @Test("PLACE-08 With none focused, the one glide goes to the newest window")
    func place08b() {
        Env.withDefaults(["autoCentre": true]) {
            let (c, _) = Self.burst(focus: nil)
            defer { Self.finish(c) }
            #expect(c.glideGeneration == 1)
            #expect(c.glideTarget?.id == 814)
        }
    }

    // MARK: PLACE-09

    @Test("PLACE-09 Phone and FaceTime call windows are left where their app puts them")
    func place09() {
        #expect(CanvasController.leftAlone == ["com.apple.mobilephone", "com.apple.FaceTime"])
        let a = Self.placed(901, canvas: CGRect(x: 100, y: 100, width: 600, height: 400))
        let c = Self.canvas([a])
        defer { Self.finish(c) }
        Self.watchGlides(c)
        let f = CGRect(x: 900, y: 100, width: 400, height: 500)
        let facetime = Self.newWindow(902, pid: 90_901, bundleID: "com.apple.FaceTime", appName: "FaceTime", at: f)
        let phone = Self.newWindow(903, pid: 90_902, bundleID: "com.apple.mobilephone", appName: "Phone", at: f)
        #expect(!c.isManageable(facetime, tracked: false, regular: { _ in true }))
        #expect(!c.isManageable(phone, tracked: true, regular: { _ in true }))
        Self.scan(c, [a.scWindow, facetime, phone], standard: [902, 903])
        #expect(c.windows.map(\.id) == [901])
        #expect(a.canvasFrame.origin == CGPoint(x: 100, y: 100))
        #expect(c.glideGeneration == 0)
    }

    // MARK: PLACE-10

    /// A Finder window at a known spot with windows on either side.
    static func finderWithNeighbours() -> (CanvasController, ManagedWindow, [ManagedWindow]) {
        let finder: pid_t = 91_001
        let f = Self.placed(1001, pid: finder, appName: "Finder", canvas: CGRect(x: 400, y: 200, width: 600, height: 400))
        let left = Self.placed(1002, pid: 91_002, canvas: CGRect(x: 0, y: 200, width: 380, height: 400))
        let right = Self.placed(1003, pid: 91_002, canvas: CGRect(x: 1020, y: 200, width: 400, height: 400))
        let c = Self.canvas([left, f, right])
        Self.watchGlides(c)
        return (c, f, [left, right])
    }

    @Test("PLACE-10 A new tab keeps its window's spot")
    func place10() {
        let (c, f, neighbours) = Self.finderWithNeighbours()
        defer { Self.finish(c) }
        let spot = f.canvasFrame
        let before = neighbours.map(\.canvasFrame)
        // ⌘T: the new tab is a window of its own at the group's frame; the old tab's isn't on screen.
        let tab = Self.newWindow(1011, pid: f.pid, appName: "Finder", at: Self.real(spot, c))
        Self.scan(c, neighbours.map(\.scWindow) + [tab], standard: [1011])
        let t = try? #require(Self.window(c, 1011))
        #expect(t?.canvasFrame == spot)
        #expect(neighbours.map(\.canvasFrame) == before)
        #expect(c.glideGeneration == 0)
    }

    @Test("PLACE-10 A new tab seen a scan after its old tab went still keeps the spot")
    func place10b() {
        let (c, f, neighbours) = Self.finderWithNeighbours()
        defer { Self.finish(c) }
        let spot = f.canvasFrame
        Self.scan(c, neighbours.map(\.scWindow))
        #expect(Self.window(c, 1001) == nil)
        let tab = Self.newWindow(1012, pid: f.pid, appName: "Finder", at: Self.real(spot, c))
        Self.scan(c, neighbours.map(\.scWindow) + [tab], standard: [1012])
        #expect(Self.window(c, 1012)?.canvasFrame == spot)
    }

    @Test("PLACE-10 Only the same app, same size and same spot (within 2pt) counts as a tab")
    func place10c() {
        let (c, f, _) = Self.finderWithNeighbours()
        defer { Self.finish(c) }
        let real = Self.real(f.canvasFrame, c)
        func tab(_ frame: CGRect, pid: pid_t? = nil) -> CGWindowID? {
            let sc = Fake.scWindow(id: 1013, pid: pid ?? f.pid, frame: frame)
            let w = ManagedWindow(scWindow: sc, canvasFrame: CGRect(origin: c.canvasPoint(forGlobal: frame.origin), size: frame.size))
            c.scannedIDs = [1013]
            return c.tabTakingOver(from: w, at: frame)?.id
        }
        #expect(tab(real) == 1001)
        #expect(tab(real.insetBy(dx: -1, dy: -1)) == 1001)
        #expect(tab(real.offsetBy(dx: 2, dy: -2)) == 1001)
        #expect(tab(CGRect(origin: real.origin, size: CGSize(width: real.width + 3, height: real.height))) == nil)
        #expect(tab(real.offsetBy(dx: 3, dy: 0)) == nil)
        Fake.regularApp(91_003)
        #expect(tab(real, pid: 91_003) == nil)
    }

    // MARK: PLACE-11

    @Test("PLACE-11 Switching tabs keeps the window's spot")
    func place11() {
        let (c, f, neighbours) = Self.finderWithNeighbours()
        defer { Self.finish(c) }
        let spot = f.canvasFrame
        let before = neighbours.map(\.canvasFrame)
        let real = Self.real(spot, c)
        // Tab 2 to the front, then tab 1 again.
        let tab2 = Self.newWindow(1102, pid: f.pid, appName: "Finder", at: real)
        Self.scan(c, neighbours.map(\.scWindow) + [tab2], standard: [1102])
        #expect(Self.window(c, 1102)?.canvasFrame == spot)
        let tab1 = Fake.scWindow(id: 1001, pid: f.pid, appName: "Finder", frame: real)
        Self.scan(c, neighbours.map(\.scWindow) + [tab1], standard: [1001])
        #expect(Self.window(c, 1001)?.canvasFrame == spot)
        #expect(Self.window(c, 1102) == nil)
        #expect(neighbours.map(\.canvasFrame) == before)
        #expect(c.glideGeneration == 0)
    }

    @Test("PLACE-11 Switching tabs of a parked group keeps its spot, and the view stays put")
    func place11b() {
        Env.withDefaults(["autoCentre": false]) {
            let finder: pid_t = 91_101
            let here = Self.placed(1110, pid: 91_102, canvas: CGRect(x: 200, y: 200, width: 600, height: 400))
            let f = Fake.window(id: 1111, pid: finder, appName: "Finder", canvas: CGRect(x: 3000, y: 200, width: 600, height: 400),
                                real: CGRect(x: 1480, y: 940, width: 600, height: 400))
            f.parked = true
            f.lastPlaced = CGPoint(x: 1480, y: 940)   // macOS nudged it within the corner
            let c = Self.canvas([here, f])
            defer { Self.finish(c) }
            Self.watchGlides(c)
            let camera = c.camera
            // ⌃Tab in the parked group: the other tab is in the parking corner.
            let tab = Self.newWindow(1112, pid: finder, appName: "Finder", at: CGRect(x: 1480, y: 940, width: 600, height: 400))
            Self.scan(c, [here.scWindow, tab], standard: [1112])
            let t = try? #require(Self.window(c, 1112))
            #expect(t?.canvasFrame == CGRect(x: 3000, y: 200, width: 600, height: 400))
            #expect(t?.parked == true)
            #expect(here.canvasFrame.origin == CGPoint(x: 200, y: 200))
            #expect(c.glideGeneration == 0)
            #expect(c.camera == camera)
        }
    }

    // MARK: PLACE-12 (manual)

    @Test("PLACE-12 A new window opens beside its own app's window, else the window in front (logic)")
    func place12() {
        Env.withDefaults(["autoCentre": true]) {
            let textEdit: pid_t = 91_201, terminal: pid_t = 91_202
            let t = Self.placed(1201, pid: textEdit, appName: "TextEdit", canvas: CGRect(x: 100, y: 300, width: 400, height: 300))
            let m = Self.placed(1202, pid: terminal, appName: "Terminal", canvas: CGRect(x: 900, y: 300, width: 400, height: 300))
            let c = Self.canvas([t, m])   // Terminal in front
            defer { Self.finish(c) }
            Self.watchGlides(c)
            let n = Self.newWindow(1203, pid: textEdit, appName: "TextEdit", at: CGRect(x: 500, y: 100, width: 300, height: 300))
            Self.scan(c, [t.scWindow, m.scWindow, n], standard: [1203])
            // Right of TextEdit's window, not beside Terminal.
            #expect(Self.window(c, 1203)?.canvasFrame.origin == CGPoint(x: 520, y: 300))
        }
    }

    @Test("PLACE-12 With none of its app's windows on screen, a new window opens beside the one in front (logic)")
    func place12b() {
        Env.withDefaults(["autoCentre": true]) {
            let textEdit: pid_t = 91_211, terminal: pid_t = 91_212
            let corner = CGRect(x: 1480, y: 940, width: 400, height: 300)
            let t = Fake.window(id: 1211, pid: textEdit, appName: "TextEdit", canvas: CGRect(x: 100, y: 300, width: 400, height: 300), real: corner)
            t.parked = true
            t.lastPlaced = corner.origin
            let m = Self.placed(1212, pid: terminal, appName: "Terminal", canvas: CGRect(x: 900, y: 300, width: 400, height: 300))
            let c = Self.canvas([t, m])
            defer { Self.finish(c) }
            Self.watchGlides(c)
            let n = Self.newWindow(1213, pid: textEdit, appName: "TextEdit", at: CGRect(x: 500, y: 100, width: 300, height: 300))
            Self.scan(c, [t.scWindow, m.scWindow, n], standard: [1213])
            // Below Terminal's window, left edges lined up (the spot to its right is off screen).
            #expect(Self.window(c, 1213)?.canvasFrame.origin == CGPoint(x: 900, y: 620))
        }
    }

    // MARK: PLACE-13

    @Test("PLACE-13 A new window tries every spot along its source's edges first")
    func place13() {
        let size = CGSize(width: 400, height: 250)
        let a = Fake.window(id: 1301, canvas: CGRect(origin: CGPoint(x: 556, y: 300), size: size))
        let c = Self.canvas([a])
        defer { Self.finish(c) }
        let w = Fake.window(id: 1302, canvas: CGRect(origin: .zero, size: size))
        func spot() -> CGPoint? { c.freeSpot(for: w, near: a, onScreenOnly: false) }
        let other: pid_t = 91_301
        // Step 1: right of A, tops lined up, 20pt gap.
        #expect(spot() == CGPoint(x: 976, y: 300))
        // Step 2: another app's window right of A: below A, left edges lined up.
        c.windows.append(Fake.window(id: 1303, pid: other, canvas: CGRect(origin: CGPoint(x: 976, y: 300), size: size)))
        #expect(spot() == CGPoint(x: 556, y: 570))
        // Step 3: below blocked too: left of A, tops lined up.
        c.windows.append(Fake.window(id: 1304, pid: other, canvas: CGRect(origin: CGPoint(x: 556, y: 570), size: size)))
        #expect(spot() == CGPoint(x: 136, y: 300))
        // Step 4: and the left: above A.
        c.windows.append(Fake.window(id: 1305, pid: other, canvas: CGRect(origin: CGPoint(x: 136, y: 300), size: size)))
        #expect(spot() == CGPoint(x: 556, y: 30))
    }

    @Test("PLACE-13 On each side: lined up with the top edge, then the bottom, then centred")
    func place13b() {
        let a = Fake.window(id: 1311, canvas: CGRect(x: 500, y: 300, width: 400, height: 400))
        let c = Self.canvas([a])
        defer { Self.finish(c) }
        let w = Fake.window(id: 1312, canvas: CGRect(x: 0, y: 0, width: 300, height: 150))
        func spot() -> CGPoint? { c.freeSpot(for: w, near: a, onScreenOnly: false) }
        #expect(spot() == CGPoint(x: 920, y: 300))
        c.windows.append(Fake.window(id: 1313, pid: 91_311, canvas: CGRect(x: 920, y: 200, width: 300, height: 150)))
        #expect(spot() == CGPoint(x: 920, y: 550))
        c.windows.append(Fake.window(id: 1314, pid: 91_311, canvas: CGRect(x: 920, y: 640, width: 300, height: 100)))
        #expect(spot() == CGPoint(x: 920, y: 425))
    }

    // MARK: PLACE-14

    @Test("PLACE-14 An app's loading box doesn't take its main window's spot")
    func place14() {
        let discord = "com.hnc.Discord"
        var pool = [SavedLayout.Window.entry(bundleID: discord, appName: "Discord", x: 2000, y: 300, w: 1200, h: 800)]
        // The update box: well under a quarter of the window's saved size.
        let box = CGSize(width: 300, height: 200)
        #expect(LayoutStore.takeMatch(bundleID: discord, title: "", id: 1401, pid: 91_401, size: box, open: [], from: &pool) == nil)
        #expect(pool.count == 1)
        let larger = LayoutStore.largerSpot(bundleID: discord, size: box, open: [], in: pool)
        #expect(larger?.x == 2000 && larger?.y == 300)
        #expect(pool.count == 1)
        // A moment later the main window takes the spot.
        let main = LayoutStore.takeMatch(bundleID: discord, title: "", id: 1402, pid: 91_401,
                                         size: CGSize(width: 1200, height: 800), open: [], from: &pool)
        #expect(main?.x == 2000 && main?.y == 300)
        #expect(pool.isEmpty)
    }

    @Test("PLACE-14 A quarter of the saved size or more still takes the spot; the chosen size counts first")
    func place14b() {
        let app = "com.example.loader"
        var e = SavedLayout.Window.entry(bundleID: app, x: 10, y: 20, w: 1200, h: 800)
        var pool = [e]
        #expect(LayoutStore.largerSpot(bundleID: app, size: CGSize(width: 600, height: 400), open: [], in: pool) == nil)
        #expect(LayoutStore.takeMatch(bundleID: app, title: "", id: 1411, pid: 91_411, size: CGSize(width: 600, height: 400),
                                      open: [], from: &pool) != nil)
        // pw×ph (the size you chose) over w×h.
        e.pw = 400; e.ph = 300
        pool = [e]
        #expect(LayoutStore.largerSpot(bundleID: app, size: CGSize(width: 300, height: 200), open: [], in: pool) == nil)
        #expect(LayoutStore.largerSpot(bundleID: app, size: CGSize(width: 150, height: 100), open: [], in: pool) != nil)
        // Another app's entry is never it.
        #expect(LayoutStore.largerSpot(bundleID: "com.example.other", size: CGSize(width: 150, height: 100), open: [], in: pool) == nil)
    }

    // MARK: PLACE-15

    @Test("PLACE-15 A new window goes above its window only as a last resort")
    func place15() {
        // Every edge of A taken, each the standard gap away; a gap in the row above, to the right
        // of the window over A; open space further right and below.
        let size = CGSize(width: 400, height: 250)
        func frame(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(origin: CGPoint(x: x, y: y), size: size) }
        let other: pid_t = 91_501
        let a = Fake.window(id: 1501, canvas: frame(556, 350))
        let around = [frame(976, 350), frame(556, 620), frame(136, 350), frame(500, 80), frame(976, 620)]
        let c = Self.canvas([a] + around.enumerated().map { i, f in Fake.window(id: 1510 + CGWindowID(i), pid: other, canvas: f) })
        defer { Self.finish(c) }
        let w = Fake.window(id: 1502, canvas: frame(0, 0))
        let all = c.windows.map(\.canvasFrame)
        // The gap in the row above is free, and nearer A than any spot beside or below: going by
        // distance alone, it would win.
        let gap = frame(920, 80)
        #expect(!Self.crowds(gap, all))
        let spot = try? #require(c.freeSpot(for: w, near: a, onScreenOnly: false))
        let r = CGRect(origin: spot ?? .zero, size: size)
        #expect(!Self.crowds(r, all))
        #expect(gap.center.distance(to: a.canvasFrame.center) < r.center.distance(to: a.canvasFrame.center))
        // Not ending above A's top.
        #expect(r.maxY > a.canvasFrame.minY)
        #expect(spot == CGPoint(x: 136, y: 620))
    }

    // MARK: PLACE-16 (manual)

    @Test("PLACE-16 A new Finder window opens beside you, not at an old Finder window's spot (logic)")
    func place16() {
        Env.withDefaults(["autoCentre": true]) {
            let finder: pid_t = 91_601
            let f = Self.placed(1601, pid: finder, bundleID: "com.apple.finder", appName: "Finder",
                                canvas: CGRect(x: 300, y: 200, width: 500, height: 400))
            let c = Self.canvas([f])
            defer { Self.finish(c) }
            Self.watchGlides(c)
            // Expanse has been running for over 3 minutes; the saved layout had Finder windows elsewhere.
            c.restartSpotsUntil = .distantPast
            c.savedPool = [SavedLayout.Window.entry(bundleID: "com.apple.finder", appName: "Finder", x: 5000, y: 5000, w: 500, h: 400),
                           SavedLayout.Window.entry(bundleID: "com.apple.finder", appName: "Finder", x: -3000, y: 900, w: 500, h: 400)]
            let n = Self.newWindow(1602, pid: finder, bundleID: "com.apple.finder", appName: "Finder",
                                   at: CGRect(x: 40, y: 60, width: 500, height: 400))
            Self.scan(c, [f.scWindow, n], standard: [1602])
            #expect(Self.window(c, 1602)?.canvasFrame.origin == CGPoint(x: 820, y: 200))
            #expect(c.savedPool.count == 2)
            #expect(c.glideGeneration == 0)
        }
    }

    // MARK: PLACE-17 (manual)

    @Test("PLACE-17 A new window that reuses a closed window's ID isn't sent to its spot (logic)")
    func place17() {
        Env.withDefaults(["autoCentre": true]) {
            let finder: pid_t = 91_701
            let f1 = Self.placed(1701, pid: finder, appName: "Finder", canvas: CGRect(x: 300, y: 200, width: 500, height: 400))
            let f2 = Self.placed(1702, pid: finder, appName: "Finder", canvas: CGRect(x: 6000, y: 200, width: 500, height: 400))
            let c = Self.canvas([f2, f1])
            defer { Self.finish(c) }
            Self.watchGlides(c)
            // F2 closed (Accessibility said its element is gone), then the scan drops it.
            c.closedWindows.insert(1702)
            Self.scan(c, [f1.scWindow])
            #expect(c.recentlyRemoved[1702]?.closed == true)
            // ⌘N: Finder gives the new window F2's old ID.
            let n = Self.newWindow(1702, pid: finder, appName: "Finder", at: CGRect(x: 40, y: 60, width: 500, height: 400))
            Self.scan(c, [f1.scWindow, n], standard: [1702])
            #expect(Self.window(c, 1702)?.canvasFrame.origin == CGPoint(x: 820, y: 200))
        }
    }

    @Test("PLACE-17 A minimised window (not closed) comes back to its own spot (logic)")
    func place17b() {
        Env.withDefaults(["autoCentre": true]) {
            let finder: pid_t = 91_711
            let f1 = Self.placed(1711, pid: finder, appName: "Finder", canvas: CGRect(x: 300, y: 200, width: 500, height: 400))
            let f2 = Self.placed(1712, pid: finder, appName: "Finder", canvas: CGRect(x: 6000, y: 200, width: 500, height: 400))
            let c = Self.canvas([f2, f1])
            defer { Self.finish(c) }
            Self.watchGlides(c)
            Self.scan(c, [f1.scWindow])
            #expect(c.recentlyRemoved[1712]?.closed == false)
            let back = Self.newWindow(1712, pid: finder, appName: "Finder", at: CGRect(x: 40, y: 60, width: 500, height: 400))
            Self.scan(c, [f1.scWindow, back], standard: [1712])
            #expect(Self.window(c, 1712)?.canvasFrame.origin == CGPoint(x: 6000, y: 200))
        }
    }
}
