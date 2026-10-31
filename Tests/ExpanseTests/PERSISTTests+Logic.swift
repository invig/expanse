import Testing
import AppKit
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "LayoutStore.swift") @testable import Expanse
@_private(sourceFile: "MenuPanel.swift") @testable import Expanse

/// The parts of PERSIST's manual cases that fake windows on a test canvas can check: what's
/// decided and saved, not the real windows moving (that needs a real Mac).
extension PERSISTTests {

    // MARK: Quit and pause

    @Test("PERSIST-03 Quitting saves a clean exit with each window's macOS frame, which it goes back to (logic)")
    func persist03() throws {
        let a = Fake.window(id: Self.farID + 1, canvas: Self.rect(3000, 100))
        a.parked = true
        a.originalFrame = Self.rect(80, 120, 1000, 700)
        let c = Self.synced([a])
        Self.quietly(c) { c.shutdown() }
        #expect(c.isPaused)
        let saved = try #require(LayoutStore.load())
        #expect(saved.cleanExit == true)
        let e = try #require(saved.windows.first)
        #expect(e.ox == 80 && e.oy == 120 && e.ow == 1000 && e.oh == 700)
        // On this screen, so exactly where macOS had it.
        #expect(c.restoredFrame(a.originalFrame) == a.originalFrame)
    }

    @Test("PERSIST-07 Pause saves a clean exit, takes the windows off the canvas and then ignores moves (logic)")
    func persist07() throws {
        let a = Fake.window(id: Self.farID + 1, canvas: Self.rect(0, 40))
        let c = Self.synced([a])
        Self.quietly(c) { c.pause() }
        #expect(c.isPaused && c.windows.isEmpty)
        #expect(LayoutStore.load()?.cleanExit == true)
        let before = try Data(contentsOf: Self.layoutFile)
        a.canvasFrame.origin.x += 500
        c.save()
        #expect(try Data(contentsOf: Self.layoutFile) == before)
        let model = MenuPanel.Model()
        model.state = MenuPanel.State(isOn: true, isPaused: true)
        #expect(PanelView(model: model).status == "Paused · windows back in the macOS layout")
    }

    @Test("PERSIST-13 Pause during a hop waits for it to land (logic)")
    func persist13a() async throws {
        let c = Self.synced([Fake.window(id: Self.farID + 1, canvas: Self.rect(0, 40))])
        c.gliding = true
        c.pause()
        #expect(!c.isPaused)
        c.gliding = false
        try await Task.sleep(for: .milliseconds(400))
        #expect(c.isPaused)
        #expect(LayoutStore.load()?.cleanExit == true)
    }

    @Test("PERSIST-13 Settling background moves stops a hop from handing back afterwards (logic)")
    func persist13b() {
        let c = TestCanvas.make()
        let generation = c.glideGeneration
        c.gliding = true
        c.settleBackgroundMoves()
        #expect(!c.gliding)
        #expect(c.glideGeneration == generation + 1)
    }

    @Test("PERSIST-18 A hidden app's windows are saved, each with its own spot, and get them back after a restart (logic)")
    func persist18() throws {
        let pid = getpid()
        try #require(NSRunningApplication(processIdentifier: pid) != nil)
        let c = Self.synced([Fake.window(id: Self.farID + 9, canvas: Self.rect(0, 40))])
        let now = Date()
        Self.departed(c, id: Self.farID + 1, pid: pid, bundleID: "com.apple.Safari", title: "Start", canvas: Self.rect(100, 1200, 900, 700), at: now - 20)
        Self.departed(c, id: Self.farID + 2, pid: pid, bundleID: "com.apple.Safari", title: "Start", canvas: Self.rect(1600, -900, 900, 700), at: now - 10)
        c.save()
        let saved = try #require(LayoutStore.load())
        let safari = saved.windows.filter { $0.bundleID == "com.apple.Safari" }
        #expect(safari.map(\.id) == [Self.farID + 2, Self.farID + 1])   // newest first
        #expect(safari.allSatisfy { $0.away == true && $0.w == 900 && $0.h == 700 })
        // Expanse restarted; Safari shown again: each window its own spot, not one place.
        var pool = saved.windows
        for (id, x) in [(Self.farID + 1, 100.0), (Self.farID + 2, 1600.0)] {
            let e = LayoutStore.takeMatch(bundleID: "com.apple.Safari", title: "Start", id: id, pid: pid, open: [], from: &pool)
            #expect(e?.x == x)
        }
    }

    @Test("PERSIST-36 Logging out pauses at once and saves the layout as it was; already paused, nothing happens (logic)")
    func persist36() throws {
        let c = Self.synced([Fake.window(id: Self.farID + 1, canvas: Self.rect(0, 40))])
        // The 3-minute resume (PERSIST-38) must never run a real window scan from a test.
        defer { c.pausedForPowerOff = false }
        Self.quietly(c) { c.willPowerOff() }
        #expect(c.isPaused && c.pausedForPowerOff)
        #expect(LayoutStore.load()?.cleanExit == true)
        #expect(LayoutStore.load()?.windows.count == 1)
        let before = try Data(contentsOf: Self.layoutFile)
        Self.quietly(c) { c.willPowerOff() }
        #expect(try Data(contentsOf: Self.layoutFile) == before)
    }

    // MARK: Restoring a snapshot

    /// The canvas's view on TestDisplay.laptop: the screen less the menu bar.
    static let laptopView = CGSize(width: 1512, height: 949)

    /// Two windows on the canvas, zoomed out (restoreLayout runs on the canvas), and a snapshot
    /// with spots for both. A third window the snapshot doesn't know.
    static func restoreSetup(fitted: CGSize?) -> (CanvasController, [ManagedWindow], SavedLayout) {
        let a = Fake.window(id: farID + 1, title: "A", canvas: rect(2000, 900, 600, 400))
        let b = Fake.window(id: farID + 2, title: "B", canvas: rect(2700, 900, 500, 300))
        let x = Fake.window(id: farID + 3, title: "X", canvas: rect(400, 1600, 400, 300))
        let c = synced([a, b, x])
        c.isActive = true
        var ea = spot(title: "A", x: 40, y: 60, w: 600, h: 400, id: farID + 1, pid: Fake.firstPID)
        ea.hx = 100; ea.hy = 80; ea.pw = 600; ea.ph = 400
        var eb = spot(title: "B", x: 700, y: 60, w: 500, h: 300, id: farID + 2, pid: Fake.firstPID)
        eb.hx = 760; eb.hy = 80; eb.pw = 500; eb.ph = 300
        var s = SavedLayout.with([ea, eb])
        s.fittedWidth = fitted.map { Double($0.width) }
        s.fittedHeight = fitted.map { Double($0.height) }
        return (c, [a, b, x], s)
    }

    @Test("PERSIST-22 Restoring a snapshot puts each window it knows at its spot and chosen size, and zooms out to show them (logic)")
    func persist22() throws {
        var (c, w, s) = Self.restoreSetup(fitted: Self.laptopView)
        #expect(c.viewSize == Self.laptopView)
        s.windows[0].pw = 640; s.windows[0].ph = 420
        let target = Self.quietly(c) { () -> Camera? in
            c.restoreLayout(s)
            return c.animation?.to
        }
        #expect(w[0].canvasFrame.origin == CGPoint(x: 40, y: 60))
        #expect(w[1].canvasFrame.origin == CGPoint(x: 700, y: 60))
        #expect(w[0].preferredSize == CGSize(width: 640, height: 420))
        #expect(w[1].preferredSize == CGSize(width: 500, height: 300))
        #expect(target == c.fitCamera())
    }

    @Test("PERSIST-23 Restoring a snapshot leaves a window it doesn't know where it is (logic)")
    func persist23Logic() {
        let (c, w, s) = Self.restoreSetup(fitted: nil)
        Self.quietly(c) { c.restoreLayout(s) }
        #expect(w[2].canvasFrame.origin == CGPoint(x: 400, y: 1600))
    }

    @Test("PERSIST-24 Restoring a snapshot first keeps the layout it replaces as the newest snapshot (logic)")
    func persist24() throws {
        let (c, w, s) = Self.restoreSetup(fitted: nil)
        Self.earlierLayouts(c, ago: [60])
        Self.quietly(c) { c.restoreLayout(s) }
        let snapshots = LayoutStore.snapshots()
        #expect(snapshots.count == 2)
        let newest = try #require(snapshots.first)
        let replaced = try #require(LayoutStore.load(newest))
        #expect(replaced.windows.first { $0.id == w[0].id }?.x == 2000)
        #expect(replaced.windows.first { $0.id == w[1].id }?.x == 2700)
    }

    @Test("PERSIST-25 Restoring a snapshot does nothing while paused (logic)")
    func persist25() {
        let (c, w, s) = Self.restoreSetup(fitted: nil)
        c.isPaused = true
        Self.quietly(c) { c.restoreLayout(s) }
        #expect(w[0].canvasFrame.origin == CGPoint(x: 2000, y: 900))
        #expect(w[1].canvasFrame.origin == CGPoint(x: 2700, y: 900))
        #expect(LayoutStore.snapshots().isEmpty)
    }

    @Test("PERSIST-26 A snapshot from a bigger screen is fitted: sizes capped 16pt inside the screen, gaps kept (logic)")
    func persist26() {
        let laptop = CGSize(width: 1512, height: 949)
        #expect(CanvasController.cap(CGSize(width: 2400, height: 1300), to: laptop) == CGSize(width: 1480, height: 917))
        #expect(CanvasController.cap(CGSize(width: 2400, height: 600), to: laptop) == CGSize(width: 1480, height: 600))
        #expect(CanvasController.cap(CGSize(width: 800, height: 600), to: laptop) == CGSize(width: 800, height: 600))
        // Two windows side by side, 40pt apart, both shrunk: still 40pt apart.
        let home = [Self.rect(0, 0, 1200, 800), Self.rect(1240, 0, 1200, 800)]
        let fitted = CanvasController.derive(home: home, sizes: [CGSize(width: 700, height: 500), CGSize(width: 700, height: 500)])
        #expect(fitted == [CGPoint(x: 0, y: 0), CGPoint(x: 740, y: 0)])
        // Restored from another screen: nothing overlapping.
        let (c, w, s) = Self.restoreSetup(fitted: CGSize(width: 2560, height: 1415))
        Self.quietly(c) { c.restoreLayout(s) }
        let frames = w.map(\.canvasFrame)
        for i in frames.indices {
            for j in frames.indices where j > i { #expect(!frames[i].intersects(frames[j]), "\(i) and \(j) overlap") }
        }
    }

    @Test("PERSIST-27 Back on the screen the layout was fitted to, fitting moves nothing; layout.json records that screen (logic)")
    func persist27() throws {
        let a = Fake.window(id: Self.farID + 1, canvas: Self.rect(100, 100))
        let b = Fake.window(id: Self.farID + 2, canvas: Self.rect(800, 100))
        // Home spots that re-deriving the layout would move them to.
        a.home = CGPoint(x: 300, y: 100)
        b.home = CGPoint(x: 1000, y: 500)
        let c = Self.synced([a, b])
        c.fittedViewSize = c.viewSize
        Self.quietly(c) { c.fitLayoutToScreen(tidy: false, rederiving: []) }
        #expect(a.canvasFrame.origin == CGPoint(x: 100, y: 100))
        #expect(b.canvasFrame.origin == CGPoint(x: 800, y: 100))
        c.save()
        let saved = try #require(LayoutStore.load())
        #expect(saved.fittedWidth == Double(c.viewSize.width) && saved.fittedHeight == Double(c.viewSize.height))
    }

    @Test("PERSIST-30 A snapshot from this screen puts windows exactly at its x, y, and keeps its home spots (logic)")
    func persist30() {
        let (c, w, s) = Self.restoreSetup(fitted: Self.laptopView)
        #expect(c.viewSize == Self.laptopView)
        Self.quietly(c) { c.restoreLayout(s) }
        #expect(w[0].canvasFrame.origin == CGPoint(x: 40, y: 60))
        #expect(w[1].canvasFrame.origin == CGPoint(x: 700, y: 60))
        // Not re-homed from where the windows are.
        #expect(w[0].home == CGPoint(x: 100, y: 80))
        #expect(w[1].home == CGPoint(x: 760, y: 80))
    }

    @Test("PERSIST-31 A snapshot from another screen is laid out from its home spots, which it keeps (logic)")
    func persist31() {
        let (c, w, s) = Self.restoreSetup(fitted: CGSize(width: 2560, height: 1415))
        Self.quietly(c) { c.restoreLayout(s) }
        #expect(w[0].home == CGPoint(x: 100, y: 80))
        #expect(w[1].home == CGPoint(x: 760, y: 80))
        // Sizes that fit this screen: the home layout as it is.
        #expect(w[0].canvasFrame.origin == CGPoint(x: 100, y: 80))
        #expect(w[1].canvasFrame.origin == CGPoint(x: 760, y: 80))
    }
}
