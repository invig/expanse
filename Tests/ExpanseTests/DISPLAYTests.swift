import Testing
import AppKit
import ScreenCaptureKit
@_private(sourceFile: "CanvasController.swift") @testable import Expanse

/// docs/regression/displays-lock-sleep.md. A display change is played out on a test canvas: the
/// pretend display changes (displayOverride), the fake windows take the sizes Expanse asks for,
/// and the layout is fitted as restoreSizesAndPlace and relayout fit it. Nothing real moves.
@MainActor @Suite("DISPLAY: Displays, lock and sleep", .serialized)
struct DISPLAYTests {

    // MARK: Helpers

    /// A window on the canvas, at the size you chose for it.
    private static func win(_ id: CGWindowID, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                            app: String = "Example") -> ManagedWindow {
        Fake.window(id: id, appName: app, canvas: CGRect(x: x, y: y, width: w, height: h))
    }

    /// Two rows of windows, 20pt apart, in columns; A is wider than the laptop's screen and E taller.
    ///     A  B  F
    ///     C D   E      (C under A, E under B: left edges lined up)
    private static func grid() -> [ManagedWindow] {
        [win(1, 0, 0, 1600, 700, app: "A"), win(2, 1620, 0, 800, 500, app: "B"), win(3, 0, 720, 700, 500, app: "C"),
         win(4, 720, 720, 700, 600, app: "D"), win(5, 1620, 520, 800, 1000, app: "E"), win(6, 2440, 0, 300, 300, app: "F")]
    }

    /// The grid fitted to the laptop: A and E capped (screen less 16pt each side), every gap kept.
    private static let laptopGrid = [
        CGRect(x: 0, y: 0, width: 1480, height: 700), CGRect(x: 1500, y: 0, width: 800, height: 500),
        CGRect(x: 0, y: 720, width: 700, height: 500), CGRect(x: 720, y: 720, width: 700, height: 600),
        CGRect(x: 1500, y: 520, width: 800, height: 917), CGRect(x: 2320, y: 0, width: 300, height: 300),
    ]

    /// A canvas on the big display whose windows are where you put them: the home layout (as a
    /// save makes it), fitted to this screen once.
    private static func bigCanvas(_ windows: [ManagedWindow]) -> CanvasController {
        let c = TestCanvas.make(display: .external, windows: windows)
        c.homeFromCanvas()
        c.fitLayoutToScreen(tidy: false, rederiving: [])
        return c
    }

    /// The display becomes `display`, and each window is resized as fitLayoutToScreen resizes real
    /// ones (fake windows can't be): asked for the size you chose, capped at the screen, it takes
    /// that, or what `appSize` says an app that rounds sizes takes; one that came as close as the
    /// app goes to a chosen size that fits is the chosen size from then on.
    private static func switchDisplay(_ c: CanvasController, to display: TestDisplay,
                                      appSize: (ManagedWindow, CGSize) -> CGSize = { $1 }) {
        c.displayOverride = (display.frame, display.usable)
        let view = c.viewport.size
        for w in c.windows where !w.sizesItself {
            let chosen = w.preferredSize.width > 0 ? w.preferredSize : w.canvasFrame.size
            let target = CanvasController.cap(chosen, to: view)
            guard abs(target.width - w.canvasFrame.width) > 1 || abs(target.height - w.canvasFrame.height) > 1 else { continue }
            let actual = appSize(w, target)
            if chosen.width <= view.width, chosen.height <= view.height,
               abs(actual.width - target.width) <= CanvasController.appRounding,
               abs(actual.height - target.height) <= CanvasController.appRounding {
                w.preferredSize = actual
            }
            w.canvasFrame.size = actual
        }
    }

    /// A display change to `display`, fitted as restoreSizesAndPlace and relayout fit it.
    private static func move(_ c: CanvasController, to display: TestDisplay,
                             appSize: (ManagedWindow, CGSize) -> CGSize = { $1 }) {
        switchDisplay(c, to: display, appSize: appSize)
        c.fitLayoutToScreen(tidy: false, rederiving: [])
    }

    private static func frames(_ c: CanvasController) -> [CGRect] { c.windows.map(\.canvasFrame) }

    private static func noOverlaps(_ frames: [CGRect]) -> Bool {
        CanvasController.overlappingPairs(frames).isEmpty
    }

    /// `w` is the window you're in: front-most, and its app's focused window as far as Expanse
    /// knows (so currentWindow() never has to ask a real app).
    private static func focus(_ w: ManagedWindow, in c: CanvasController) {
        c.windows.removeAll { $0 === w }
        c.windows.append(w)
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier { c.focusedWindowByApp[front] = w.id }
    }

    /// Stops everything the test left scheduled (saves, settle timers, put-backs), and pauses the
    /// canvas so anything already queued does nothing.
    private static func finish(_ c: CanvasController) {
        c.relayoutWork.forEach { $0.cancel() }
        [c.saveWork, c.reassertWork, c.putBackWork, c.focusSettleWork, c.syncSoonWork, c.recheckWork,
         c.streamingWork, c.lingerWork].forEach { $0?.cancel() }
        c.cancelAnimation()
        c.snapshotTimer?.invalidate()
        c.isPaused = true
    }

    // MARK: DISPLAY-01

    @Test("DISPLAY-01 For 20s after a display change, only your drags count as moves (logic)")
    func display01() throws {
        try Env.withDefaults(["background": "plain"]) {
            let c = Self.bigCanvas(Self.grid())
            defer { Self.finish(c) }
            // Zoomed out, so the final pass fits the layout without handing back to real windows
            // (at 100% that's restoreSizesAndPlace, which needs the screen); the settle period is the same.
            c.isActive = true
            c.centreAfterResize = c.windows[0]
            c.displaysWillChange()
            #expect(c.suspendTracking)
            #expect(c.settleUntil == .distantFuture)
            c.relayout(final: true)
            #expect(CanvasController.settleDuration == 20)
            #expect(abs(c.settleUntil.timeIntervalSinceNow - 20) < 2)
            #expect(c.suspendTracking)
            c.isActive = false
            // macOS's moves aren't followed meanwhile; a window that opens is placed as usual.
            #expect(c.settling)
            let end = try #require(c.relayoutWork.last)
            end.perform()
            #expect(c.suspendTracking, "still within the 20s")
            c.settleUntil = Date().addingTimeInterval(-1)
            end.perform()
            #expect(!c.suspendTracking, "display change settled")
        }
    }

    // MARK: DISPLAY-02

    @Test("DISPLAY-02 After the screen changes size, the window you were in is centred")
    func display02a() {
        let c = Self.bigCanvas(Self.grid())
        defer { Self.finish(c) }
        let x = c.windows[3]   // D: off the middle of the big screen at 100%
        c.camera = Camera()
        Self.focus(x, in: c)
        let oldSize = c.viewport.size
        c.displaysWillChange()
        #expect(c.centreAfterResize === x)
        Self.switchDisplay(c, to: .laptop)
        // As relayout does when the size changed: the old middle stays in the middle, and the
        // screen counts as resized.
        c.camera = Camera.centered(on: c.camera.center(in: oldSize), scale: 1, viewSize: c.viewport.size)
        c.camera.origin = CGPoint(x: c.camera.origin.x.rounded(), y: c.camera.origin.y.rounded())
        c.screenResized = true
        c.fitToNewScreen()
        for w in c.windows { #expect(w.canvasFrame == Self.laptopGrid[Int(w.id) - 1]) }
        #expect(c.camera == c.focusCamera(for: x))
        let shown = c.camera.toView(x.canvasFrame)
        let view = c.viewport.size
        #expect(abs(shown.midX - view.width / 2) <= 1 && abs(shown.midY - view.height / 2) <= 1)
        #expect(!c.screenResized)
        #expect(c.centreAfterResize == nil)
    }

    @Test("DISPLAY-02 The window noted as you lock is the one centred after unlocking")
    func display02b() {
        let c = Self.bigCanvas(Self.grid())
        defer { Self.finish(c) }
        let x = c.windows[3], other = c.windows[0]
        Self.focus(x, in: c)
        // Locking: X is noted as the change begins.
        c.screenLocked = true
        c.displaysWillChange()
        #expect(c.centreAfterResize === x)
        // At the lock screen something else ends up in front; unlocking starts another change.
        Self.focus(other, in: c)
        c.screenLocked = false
        c.displaysWillChange()
        #expect(c.centreAfterResize === x)
        Self.switchDisplay(c, to: .laptop)
        c.screenResized = true
        c.fitToNewScreen()
        #expect(c.camera == c.focusCamera(for: x))
        #expect(c.camera != c.focusCamera(for: other))
    }

    // MARK: DISPLAY-04

    @Test("DISPLAY-04 After unlocking, windows are back where the canvas has them (logic)")
    func display04() {
        let c = Self.bigCanvas(Self.grid())
        defer { Self.finish(c) }
        c.camera = Camera()
        let before = Self.frames(c)
        // At the lock screen macOS piled every window at one spot.
        for w in c.windows { w.lastPlaced = CGPoint(x: 600, y: 400) }
        // Unlocking re-places every window. (Zoomed out here, so the pass itself moves nothing.)
        c.isActive = true
        c.relayout(final: false)
        #expect(c.windows.allSatisfy { $0.lastPlaced == nil })
        #expect(Self.frames(c) == before)
        c.isActive = false
        let vp = c.viewport
        for (w, target, parked) in c.commitPlan() {
            #expect(!c.alreadyAt(w, target, parked: parked), "\(w.appName) is moved back")
            if !parked { #expect(target == CGPoint(x: w.canvasFrame.minX + vp.minX, y: w.canvasFrame.minY + vp.minY)) }
        }
    }

    // MARK: DISPLAY-05

    @Test("DISPLAY-05 A tracked window stays manageable anywhere, past the screen's edge too")
    func display05a() {
        let c = TestCanvas.make(display: .laptop)
        defer { Self.finish(c) }
        // Past the laptop's right and bottom edges (where the big display parked it), and on screen.
        let past = Fake.scWindow(id: 1, frame: CGRect(x: 2519, y: 1359, width: 600, height: 400))
        let right = Fake.scWindow(id: 2, frame: CGRect(x: 1800, y: 100, width: 600, height: 400))
        let onScreen = Fake.scWindow(id: 3, frame: CGRect(x: 100, y: 100, width: 600, height: 400))
        #expect(c.isManageable(past, tracked: true, regular: { _ in true }))
        #expect(c.isManageable(right, tracked: true, regular: { _ in true }))
        // A new window only counts on the main display.
        #expect(!c.isManageable(past, tracked: false, regular: { _ in true }))
        #expect(!c.isManageable(right, tracked: false, regular: { _ in true }))
        #expect(c.isManageable(onScreen, tracked: false, regular: { _ in true }))
    }

    @Test("DISPLAY-05 A scan after the screen shrinks drops none of the windows past its edge")
    func display05b() {
        let ws = [Self.win(1, 0, 0, 600, 400), Self.win(2, 2000, 100, 600, 400), Self.win(3, 3000, 1500, 600, 400)]
        let c = TestCanvas.make(display: .laptop, windows: ws)
        defer { Self.finish(c) }
        c.firstSync = false
        c.suspendTracking = true   // the display change, before the re-layout
        // Real windows where the big display had them: one on screen, one past the right edge, one
        // in the big display's parking corner.
        let real = [CGRect(x: 100, y: 133, width: 600, height: 400), CGRect(x: 2000, y: 1100, width: 600, height: 400),
                    CGRect(x: 2519, y: 1359, width: 600, height: 400)]
        let scan = zip(ws, real).map { Fake.scWindow(id: $0.id, frame: $1) }
        let before = Self.frames(c)
        c.apply(scan, ax: CanvasController.AXSnapshot())
        #expect(c.windows.map(\.id) == [1, 2, 3])
        #expect(Self.frames(c) == before)
    }

    // MARK: DISPLAY-06

    @Test("DISPLAY-06 derive returns the home positions exactly for home sizes")
    func display06a() {
        let layouts: [[CGRect]] = [
            Self.grid().map(\.canvasFrame),
            // Cascaded and overlapping, with a window below.
            [CGRect(x: 100, y: 100, width: 800, height: 600), CGRect(x: 130, y: 130, width: 800, height: 600),
             CGRect(x: 100, y: 810, width: 1600, height: 400)],
            // Loose groups, odd gaps.
            [CGRect(x: -500, y: 40, width: 333, height: 250), CGRect(x: -140, y: 77, width: 640, height: 480),
             CGRect(x: 900, y: -300, width: 1200, height: 900), CGRect(x: 520, y: 600, width: 300, height: 200)],
        ]
        for home in layouts {
            #expect(CanvasController.derive(home: home, sizes: home.map(\.size)) == home.map(\.origin))
        }
    }

    @Test("DISPLAY-06 A smaller screen tightens the layout keeping its gaps and columns")
    func display06b() {
        let c = Self.bigCanvas(Self.grid())
        defer { Self.finish(c) }
        let home = Self.frames(c)
        Self.move(c, to: .laptop)
        let f = Self.frames(c)
        #expect(c.isDerived)
        #expect(f == Self.laptopGrid)
        // Each window keeps its gap to the one on its left and the one above.
        #expect(f[1].minX - f[0].maxX == 20)   // A | B
        #expect(f[5].minX - f[1].maxX == 20)   // B | F
        #expect(f[3].minX - f[2].maxX == 20)   // C | D
        #expect(f[2].minY - f[0].maxY == 20)   // A over C
        #expect(f[4].minY - f[1].maxY == 20)   // B over E
        // Columns stay lined up.
        #expect(f[2].minX == f[0].minX)
        #expect(f[4].minX == f[1].minX)
        #expect(Self.noOverlaps(f))
        Self.move(c, to: .external)
        #expect(!c.isDerived)
        #expect(Self.frames(c) == home)
    }

    // MARK: DISPLAY-07

    @Test("DISPLAY-07 A move made on the smaller screen survives going back")
    func display07() {
        let c = Self.bigCanvas(Self.grid())
        defer { Self.finish(c) }
        let home = Self.frames(c)
        Self.move(c, to: .laptop)
        let x = c.windows[5]   // F, with free space to its right
        let before = x.canvasFrame.origin
        x.canvasFrame.origin.x += 200
        c.noteUserMove(x, from: before)
        #expect(x.home == CGPoint(x: home[5].minX + 200, y: home[5].minY))
        Self.move(c, to: .external)
        let f = Self.frames(c)
        // 200pt further from B than it was, on the big screen too; the others where they were.
        #expect(f[5].minX - f[1].maxX == 220)
        #expect(f[5] == home[5].offsetBy(dx: 200, dy: 0))
        for i in 0..<5 { #expect(f[i] == home[i], "\(c.windows[i].appName) unaffected") }
    }

    // MARK: DISPLAY-08

    @Test("DISPLAY-08 Display changes while paused leave windows alone (logic)")
    func display08() {
        let c = Self.bigCanvas(Self.grid())
        defer { Self.finish(c) }
        let big = c.viewport.size
        c.lastViewportSize = big
        let before = Self.frames(c), camera = c.camera
        c.isPaused = true
        c.displaysWillChange()
        #expect(!c.suspendTracking)
        #expect(c.centreAfterResize == nil)
        c.scheduleRelayout()
        #expect(c.relayoutWork.isEmpty)
        c.simulateScreen(CGSize(width: 1512, height: 982))
        #expect(c.relayoutWork.isEmpty)
        #expect(!c.suspendTracking)
        c.screenOverride = nil
        c.displayOverride = (TestDisplay.laptop.frame, TestDisplay.laptop.usable)
        c.relayout(final: true)
        #expect(Self.frames(c) == before)
        #expect(c.camera == camera)
        #expect(c.lastViewportSize == big)
        #expect(!c.screenResized)
        #expect(!c.isActive)
    }

    // MARK: DISPLAY-09

    @Test("DISPLAY-09 separate pushes overlaps apart to exactly 20pt and leaves close windows")
    func display09a() {
        var frames = [
            CGRect(x: 0, y: 0, width: 400, height: 300), CGRect(x: 408, y: 0, width: 400, height: 300),   // A, B 8pt apart
            CGRect(x: 0, y: 1000, width: 600, height: 400), CGRect(x: 500, y: 1100, width: 600, height: 400),   // overlapping
        ]
        let before = frames
        CanvasController.separate(&frames, gap: 20, onlyOverlaps: true)
        #expect(frames[0] == before[0] && frames[1] == before[1])
        #expect(frames[2] == before[2])
        // Pushed right or down, whichever is the shorter move (right here: 120 against 320).
        #expect(frames[3].minY == before[3].minY)
        #expect(frames[3].minX - frames[2].maxX == 20)
    }

    @Test("DISPLAY-09 Overlaps a smaller screen makes are pushed 20pt apart; an 8pt pair stays")
    func display09b() {
        // As the grid, but D is wide enough to run into E once A shrinks; P and Q placed 8pt apart.
        let ws = [Self.win(1, 0, 0, 1600, 700, app: "A"), Self.win(2, 1620, 0, 800, 500, app: "B"),
                  Self.win(3, 0, 720, 700, 500, app: "C"), Self.win(4, 720, 720, 800, 600, app: "D"),
                  Self.win(5, 1620, 520, 800, 1000, app: "E"), Self.win(6, 2440, 0, 300, 300, app: "F"),
                  Self.win(7, 0, 2400, 400, 300, app: "P"), Self.win(8, 408, 2400, 400, 300, app: "Q")]
        let c = Self.bigCanvas(ws)
        defer { Self.finish(c) }
        let home = Self.frames(c)
        #expect(Self.noOverlaps(home))
        Self.move(c, to: .laptop)
        let f = Self.frames(c)
        #expect(Self.noOverlaps(f))
        #expect(f[3].minY - f[4].maxY == 20, "D pushed exactly 20pt below E")
        #expect(f[3].minX == 720)
        #expect(f[7].minX - f[6].maxX == 8, "P and Q still 8pt apart")
        #expect(f[7].minY == f[6].minY)
        Self.move(c, to: .external)
        #expect(Self.frames(c) == home)
    }

    // MARK: DISPLAY-11

    /// Four cascaded windows, one below them and one beside them.
    private static func cascade() -> [ManagedWindow] {
        [win(1, 100, 100, 800, 600, app: "Finder"), win(2, 130, 130, 800, 600, app: "Finder"),
         win(3, 160, 160, 800, 600, app: "Finder"), win(4, 190, 190, 800, 600, app: "Finder"),
         win(5, 100, 810, 1600, 400, app: "Below"), win(6, 1010, 100, 600, 400, app: "Beside")]
    }

    @Test("DISPLAY-11 overlappingPairs finds the cascade, and separate leaves it alone")
    func display11a() {
        let home = Self.cascade().map(\.canvasFrame)
        let pairs = CanvasController.overlappingPairs(home)
        let cascade = Set([(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)].map { CanvasController.IndexPair($0, $1) })
        #expect(pairs == cascade)
        var kept = home
        CanvasController.separate(&kept, gap: 20, onlyOverlaps: true, keep: pairs)
        #expect(kept == home)
        // Without them it would come apart, and push what's below down.
        var pushed = home
        CanvasController.separate(&pushed, gap: 20, onlyOverlaps: true)
        #expect(pushed != home)
    }

    @Test("DISPLAY-11 Overlapping windows you chose stay overlapping across screens")
    func display11b() {
        let c = Self.bigCanvas(Self.cascade())
        defer { Self.finish(c) }
        let home = Self.frames(c)
        Self.move(c, to: .laptop)
        let f = Self.frames(c)
        #expect(f[4].width == 1480)
        for i in 1..<4 {
            #expect(f[i].minX - f[i - 1].minX == 30 && f[i].minY - f[i - 1].minY == 30, "still cascaded")
        }
        #expect(f[4].minY == home[4].minY, "the window below isn't pushed down")
        #expect(Array(f[0..<4]) == Array(home[0..<4]))
        Self.move(c, to: .external)
        #expect(Self.frames(c) == home)
    }

    // MARK: DISPLAY-12

    @Test("DISPLAY-12 A display change waits for windows still moving (logic)")
    func display12() {
        let c = Self.bigCanvas(Self.grid())
        defer { Self.finish(c) }
        let big = c.viewport.size
        c.lastViewportSize = big
        let before = Self.frames(c)
        c.gliding = true
        c.displayOverride = (TestDisplay.laptop.frame, TestDisplay.laptop.usable)
        c.relayout(final: true)
        // Nothing done yet: tried again shortly, both passes.
        #expect(c.lastViewportSize == big)
        #expect(!c.screenResized)
        #expect(Self.frames(c) == before)
        #expect(c.relayoutWork.count == 2)
        #expect(c.suspendTracking)
    }

    // MARK: DISPLAY-13

    @Test("DISPLAY-13 homeFromCanvas doesn't change home spots while the screen is changing")
    func display13a() {
        let c = Self.bigCanvas(Self.grid())
        defer { Self.finish(c) }
        let homes = c.windows.map(\.home)
        for w in c.windows { w.canvasFrame.origin.x -= 100 }
        c.suspendTracking = true
        c.homeFromCanvas()
        #expect(c.windows.map(\.home) == homes)
        c.suspendTracking = false
        c.homeFromCanvas()
        #expect(c.windows.map(\.home) == c.windows.map { $0.canvasFrame.origin })
    }

    @Test("DISPLAY-13 The big-screen layout survives a trip to the laptop screen and back")
    func display13b() {
        let c = Self.bigCanvas(Self.grid())
        defer { Self.finish(c) }
        let home = Self.frames(c), homes = c.windows.map(\.home)
        Self.move(c, to: .laptop)
        // Plugging the big display back in: macOS gives windows their big sizes back before
        // Expanse has moved them, so nothing looks shrunk, and a save comes along.
        c.centreAfterResize = c.windows[0]
        c.displaysWillChange()
        Self.switchDisplay(c, to: .external)
        #expect(!c.isDerived)
        c.homeFromCanvas()
        #expect(c.windows.map(\.home) == homes, "the tightened layout isn't taken as home")
        c.fitLayoutToScreen(tidy: false, rederiving: [])
        #expect(Self.frames(c) == home)
    }

    // MARK: DISPLAY-14

    @Test("DISPLAY-14 Zoomed out during a screen change: no centring, now or later")
    func display14() {
        Env.withDefaults(["background": "plain"]) {
            let c = Self.bigCanvas(Self.grid())
            defer { Self.finish(c) }
            let x = c.windows[3]
            c.isActive = true
            c.camera = Camera(origin: CGPoint(x: -300, y: -200), scale: 0.4)
            c.lastViewportSize = c.viewport.size
            Self.focus(x, in: c)
            c.displaysWillChange()
            #expect(c.centreAfterResize === x)
            Self.switchDisplay(c, to: .laptop)
            c.relayout(final: true)
            #expect(!c.screenResized)
            #expect(c.centreAfterResize == nil)
            #expect(c.camera.scale == 0.4, "still zoomed out")
            #expect(c.camera != c.focusCamera(for: x))
            // Back to 100% (Esc), then the next fit after a display change: no window is centred
            // because of the old one.
            c.isActive = false
            let camera = c.camera
            c.fitToNewScreen()
            #expect(c.camera == camera)
        }
    }

    // MARK: DISPLAY-15

    @Test("DISPLAY-15 movedByFullScreen is false while a display change suspends tracking")
    func display15() {
        let w = Self.win(1, 0, 0, 600, 400)
        let c = TestCanvas.make(display: .laptop, windows: [w])
        defer { Self.finish(c) }
        c.suspendTracking = true      // the display change
        c.fullScreenChanging()        // which changes the Space too
        #expect(!c.movedByFullScreen(w, inFullScreenSpace: false))
        #expect(!c.movedByFullScreen(w, inFullScreenSpace: true))
        #expect(c.movedAroundFullScreen.isEmpty)
        #expect(c.putBackWork == nil)
        // Without a display change, the same move would be put back.
        c.suspendTracking = false
        #expect(c.movedByFullScreen(w, inFullScreenSpace: false))
    }

    // MARK: DISPLAY-16

    @Test("DISPLAY-16 A size within appRounding of home counts as home")
    func display16a() {
        // Terminal chose 800x600 and is 790x588 (whole character cells); R right of it and B below
        // it, 20pt from its chosen size.
        let t = Self.win(1, 100, 100, 790, 588, app: "Terminal")
        t.preferredSize = CGSize(width: 800, height: 600)
        let ws = [t, Self.win(2, 920, 100, 600, 400, app: "R"), Self.win(3, 100, 720, 600, 400, app: "B")]
        let c = TestCanvas.make(display: .external, windows: ws)
        defer { Self.finish(c) }
        #expect(CanvasController.appRounding == 32)
        #expect(!c.isDerived)
        c.homeFromCanvas()
        c.fittedViewSize = c.viewport.size
        // Every window placed from its home spot (as restoring a layout does): rounding isn't
        // shrinking, so R and B stay put.
        c.fitLayoutToScreen(tidy: false, rederiving: nil)
        #expect(ws[1].canvasFrame.origin == CGPoint(x: 920, y: 100))
        #expect(ws[2].canvasFrame.origin == CGPoint(x: 100, y: 720))
        // Taken as it is, the rounded size would pull them in by the rounding.
        let home = ws.map { CGRect(origin: $0.home!, size: $0.preferredSize) }
        let rounded = CanvasController.derive(home: home, sizes: ws.map(\.canvasFrame.size))
        #expect(rounded[1].x == 910 && rounded[2].y == 708)
    }

    @Test("DISPLAY-16 Apps that round their size don't make the layout creep")
    func display16b() {
        // Terminal sizes itself to whole cells (7x16pt here), wider than the laptop's screen; R
        // right of it and B below it, X another window wider than the laptop's screen.
        let cells: (ManagedWindow, CGSize) -> CGSize = { w, s in
            w.appName == "Terminal" ? CGSize(width: (s.width / 7).rounded(.down) * 7, height: (s.height / 16).rounded(.down) * 16) : s
        }
        let ws = [Self.win(1, 100, 100, 1596, 896, app: "Terminal"), Self.win(2, 1716, 100, 600, 400, app: "R"),
                  Self.win(3, 100, 1016, 600, 400, app: "B"), Self.win(4, 0, 1436, 1700, 500, app: "X")]
        let c = Self.bigCanvas(ws)
        defer { Self.finish(c) }
        let big = Self.frames(c)
        var laptop: [CGRect]?
        for trip in 1...3 {
            Self.move(c, to: .laptop, appSize: cells)
            c.homeFromCanvas()   // a save
            #expect(ws[0].canvasFrame.size == CGSize(width: 1477, height: 896))
            if let laptop { #expect(Self.frames(c) == laptop, "laptop, trip \(trip)") }
            laptop = Self.frames(c)
            Self.move(c, to: .external, appSize: cells)
            c.homeFromCanvas()
            #expect(Self.frames(c) == big, "big screen, trip \(trip)")
        }
    }

    // MARK: DISPLAY-17

    @Test("DISPLAY-17 Relaunching on a bigger screen fits the saved layout to it (logic)")
    func display17() {
        // As saved on the laptop: canvas spots and sizes fitted there, home spots and chosen sizes
        // from the big display, fitted to the laptop's size.
        let c = TestCanvas.make(display: .external, windows: Self.grid())
        defer { Self.finish(c) }
        let home = Self.frames(c)
        for (w, f) in zip(c.windows, Self.laptopGrid) {
            w.home = w.canvasFrame.origin
            w.canvasFrame = f
        }
        c.fittedViewSize = TestDisplay.laptop.usable.size
        // Started on the big display: windows get the sizes you chose, and the layout is fitted
        // from the laptop's (as apply does for windows restored at launch).
        Self.switchDisplay(c, to: .external)
        c.fitLayoutToScreen(tidy: false, rederiving: [])
        #expect(Self.frames(c) == home)
        #expect(!c.isDerived)
    }

    // MARK: DISPLAY-18

    @Test("DISPLAY-18 A display change while zoomed out fits the layout (logic)")
    func display18() {
        Env.withDefaults(["background": "plain"]) {
            let c = Self.bigCanvas(Self.grid())
            defer { Self.finish(c) }
            c.isActive = true
            c.camera = Camera(origin: CGPoint(x: -300, y: -200), scale: 0.35)
            c.lastViewportSize = c.viewport.size
            c.centreAfterResize = c.windows[3]
            c.displaysWillChange()
            Self.switchDisplay(c, to: .laptop)
            c.relayout(final: true)
            // While still zoomed out: the layout fitted to the new screen, gaps kept.
            #expect(Self.frames(c) == Self.laptopGrid)
            let view = c.viewport.size
            #expect(CanvasController.cap(CGSize(width: 1600, height: 1000), to: view)
                    == CGSize(width: view.width - 32, height: view.height - 32))
            #expect(Self.frames(c).allSatisfy { $0.width <= view.width && $0.height <= view.height })
            #expect(c.camera.scale == 0.35)
        }
    }

    // MARK: DISPLAY-19

    @Test("DISPLAY-19 A round trip between two screens puts every window back exactly")
    func display19() {
        let c = Self.bigCanvas(Self.grid())
        defer { Self.finish(c) }
        let home = Self.frames(c)
        Self.move(c, to: .laptop)
        // On the smaller screen each window moved only as far as the change moves it in the
        // tightened layout: derive for the laptop's sizes, less derive for the big screen's.
        let laptopSizes = c.windows.map { CanvasController.cap($0.preferredSize, to: c.viewport.size) }
        let after = CanvasController.derive(home: home, sizes: laptopSizes)
        let before = CanvasController.derive(home: home, sizes: home.map(\.size))
        for (i, w) in c.windows.enumerated() {
            #expect(w.canvasFrame.origin == CGPoint(x: home[i].minX + after[i].x - before[i].x,
                                                    y: home[i].minY + after[i].y - before[i].y))
        }
        Self.move(c, to: .external)
        #expect(Self.frames(c) == home)
        // And again.
        Self.move(c, to: .laptop)
        Self.move(c, to: .external)
        #expect(Self.frames(c) == home)
    }

    // MARK: DISPLAY-20

    @Test("DISPLAY-20 A window opened on the smaller screen moves with its neighbours")
    func display20() {
        let a = Self.win(1, 0, 0, 2000, 1000, app: "A")
        let b = Self.win(2, 0, 1200, 600, 400, app: "B")
        let c = Self.bigCanvas([a, b])
        defer { Self.finish(c) }
        Self.move(c, to: .laptop)
        #expect(a.canvasFrame.size == CGSize(width: 1480, height: 917))
        // A new window, placed 20pt beside A; no home spot yet.
        let n = Self.win(3, a.canvasFrame.maxX + 20, 0, 400, 300, app: "New")
        c.windows.append(n)
        #expect(CanvasController.anchors(2, in: Self.frames(c)) == [.gap(0)])
        // B dragged to sit 20pt below A.
        let before = b.canvasFrame.origin
        b.canvasFrame.origin = CGPoint(x: 0, y: a.canvasFrame.maxY + 20)
        c.noteUserMove(b, from: before)
        Self.move(c, to: .external)
        #expect(a.canvasFrame == CGRect(x: 0, y: 0, width: 2000, height: 1000))
        #expect(n.canvasFrame.minX - a.canvasFrame.maxX == 20 && n.canvasFrame.minY == a.canvasFrame.minY)
        #expect(b.canvasFrame.minY - a.canvasFrame.maxY == 20 && b.canvasFrame.minX == a.canvasFrame.minX)
        #expect(Self.noOverlaps(Self.frames(c)))
    }

    // MARK: DISPLAY-21

    /// A wide group on the left (G1 over G2, different widths, both wider than the laptop); on its
    /// right a column, A over B, left edges lined up. B's nearest window on the left is G2.
    private static func column() -> [ManagedWindow] {
        [win(1, 0, 0, 1700, 300, app: "G1"), win(2, 0, 420, 1600, 300, app: "G2"),
         win(3, 1820, 0, 600, 400, app: "A"), win(4, 1820, 420, 500, 300, app: "B")]
    }

    @Test("DISPLAY-21 derive keeps a column lined up (the edge anchor)")
    func display21a() {
        let home = Self.column().map(\.canvasFrame)
        #expect(CanvasController.anchor(3, in: home) == .edge(2))
        let laptop = home.map { CanvasController.cap($0.size, to: TestDisplay.laptop.usable.size) }
        let x = CanvasController.derive(home: home, sizes: laptop)
        #expect(x[3].x == x[2].x)
        #expect(x[2].x == CGFloat(1600))   // G1 capped to 1480, then its 120pt gap
    }

    @Test("DISPLAY-21 A window in a column stays lined up after a display change and back")
    func display21b() {
        let c = Self.bigCanvas(Self.column())
        defer { Self.finish(c) }
        let home = Self.frames(c)
        Self.move(c, to: .laptop)
        #expect(c.windows[3].canvasFrame.minX == c.windows[2].canvasFrame.minX)
        Self.move(c, to: .external)
        #expect(c.windows[3].canvasFrame.minX == c.windows[2].canvasFrame.minX)
        #expect(Self.frames(c) == home)
    }

    // MARK: DISPLAY-22

    /// L1 over L2, the standard gap apart, L1 wider, both wider than the laptop; A the standard gap
    /// right of L1, B under A (left edges lined up).
    private static func capped() -> [ManagedWindow] {
        [win(1, 0, 0, 1800, 500, app: "L1"), win(2, 0, 520, 1700, 400, app: "L2"),
         win(3, 1820, 0, 500, 500, app: "A"), win(4, 1820, 520, 500, 400, app: "B")]
    }

    @Test("DISPLAY-22 isNearest counts B's column as nearest when its gap to L2 ties")
    func display22a() {
        let home = Self.capped().map(\.canvasFrame)
        #expect(CanvasController.anchor(3, in: home) == .edge(2))
        // On the laptop: L1 and L2 capped to the same width, B exactly 20pt from L2.
        let here = [CGRect(x: 0, y: 0, width: 1480, height: 500), CGRect(x: 0, y: 520, width: 1480, height: 400),
                    CGRect(x: 1500, y: 0, width: 500, height: 500), CGRect(x: 1500, y: 520, width: 500, height: 400)]
        #expect(CanvasController.anchor(3, in: here) == .gap(1), "the tie goes to the gap")
        #expect(CanvasController.isNearest(.edge(2), 3, in: here))
        #expect(!CanvasController.isNearest(.gap(0), 3, in: here))
    }

    @Test("DISPLAY-22 A window in a column stays lined up after a smaller screen and back")
    func display22b() {
        let c = Self.bigCanvas(Self.capped())
        defer { Self.finish(c) }
        let home = Self.frames(c)
        let b = c.windows[3], a = c.windows[2]
        let bHome = b.home
        Self.move(c, to: .laptop)
        #expect(c.windows[0].canvasFrame.width == 1480 && c.windows[1].canvasFrame.width == 1480)
        #expect(b.canvasFrame.minX == a.canvasFrame.minX)
        #expect(b.home == bHome, "not re-homed")
        Self.move(c, to: .external)
        #expect(b.home == bHome, "not re-homed")
        #expect(b.canvasFrame.minX == a.canvasFrame.minX)
        #expect(Self.frames(c) == home)
    }

    // MARK: DISPLAY-25

    @Test("DISPLAY-25 A display change while locked isn't settled before you unlock (logic)")
    func display25() throws {
        try Env.withDefaults(["background": "plain"]) {
            let c = Self.bigCanvas(Self.grid())
            defer { Self.finish(c) }
            c.isActive = true   // see DISPLAY-01
            c.centreAfterResize = c.windows[0]
            // Locked, then the display unplugged.
            c.screenLocked = true
            c.displaysWillChange()
            c.relayout(final: true)
            let end = try #require(c.relayoutWork.last)
            c.settleUntil = Date().addingTimeInterval(-1)   // more than 20s on
            end.perform()
            #expect(c.suspendTracking, "no display change settled while locked")
            c.isActive = false
            #expect(!c.settling)
            // Unlocked: windows re-placed, and the settle period starts from there.
            c.screenLocked = false
            c.centreAfterResize = c.windows[0]
            c.displaysWillChange()
            #expect(c.settleUntil == .distantFuture)
            c.isActive = true
            c.relayout(final: true)
            #expect(abs(c.settleUntil.timeIntervalSinceNow - 20) < 2)
            let settled = try #require(c.relayoutWork.last)
            settled.perform()
            #expect(c.suspendTracking)
            c.settleUntil = Date().addingTimeInterval(-1)
            settled.perform()
            #expect(!c.suspendTracking)
        }
    }

    // MARK: DISPLAY-28

    @Test("DISPLAY-28 A window opened just after unlocking is placed as usual (logic)")
    func display28() {
        let c = TestCanvas.make(display: .laptop)
        defer { Self.finish(c) }
        // Back in place after the unlock, macOS may still move windows: settling, so a new window
        // is placed as usual (see apply).
        c.suspendTracking = true
        c.settleUntil = Date().addingTimeInterval(15)
        #expect(c.settling)
        // Not before the layout is back in place, nor while locked or zoomed out.
        c.settleUntil = .distantFuture
        #expect(!c.settling)
        c.settleUntil = Date().addingTimeInterval(15)
        c.screenLocked = true
        #expect(!c.settling)
        c.screenLocked = false
        c.isActive = true
        #expect(!c.settling)
        c.isActive = false
        c.suspendTracking = false
        #expect(!c.settling)
    }
}
