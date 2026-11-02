import Testing
import AppKit
import ScreenCaptureKit
@_private(sourceFile: "CanvasController.swift") @testable import Expanse

/// An app that has quit, for NSWorkspace's notification and CanvasController.appQuit: only its
/// process ID and name are asked for.
private final class QuitApp: NSRunningApplication {
    private let pid: pid_t
    init(_ pid: pid_t) {
        self.pid = pid
        super.init()
    }
    override var processIdentifier: pid_t { pid }
    override var localizedName: String? { "Quit app" }
}

/// docs/regression/tracking.md. Window scans are fed by hand: fake ScreenCaptureKit windows and
/// an Accessibility snapshot, straight into apply(); the AX side of a scan (axSnapshot) is asked
/// about fake processes, which have no windows.
@MainActor @Suite("TRACK: Finding and following windows", .serialized) struct TRACKTests {

    // MARK: Helpers

    /// A running canvas (past its first scan), camera at the origin: a canvas point is its screen
    /// point less the menu bar.
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
        c.observers = [:]
        c.isPaused = true
    }

    /// Glides that start are recorded (glideTarget, glideGeneration) without the overlay coming up
    /// or anything taking focus: glide() then acts as for a hop during a glide.
    static func watchGlides(_ c: CanvasController) { c.gliding = true }

    /// A window Expanse placed at its canvas spot (laptop display): its real window is there.
    static func placed(_ id: CGWindowID, pid: pid_t = Fake.firstPID, appName: String = "Example", canvas: CGRect) -> ManagedWindow {
        let real = canvas.offsetBy(dx: 0, dy: TestDisplay.laptop.menuBar)
        let w = Fake.window(id: id, pid: pid, appName: appName, canvas: canvas, real: real)
        w.lastPlaced = real.origin
        return w
    }

    /// A window out of view, parked: its real window is in the parking corner.
    static func parked(_ id: CGWindowID, pid: pid_t = Fake.firstPID, canvas: CGRect,
                       at corner: CGPoint = CGPoint(x: 1480, y: 940)) -> ManagedWindow {
        let w = Fake.window(id: id, pid: pid, canvas: canvas, real: CGRect(origin: corner, size: canvas.size))
        w.parked = true
        w.lastPlaced = corner
        return w
    }

    /// One window scan: `scWindows` on screen, `standard` the new ones Accessibility says are
    /// standard document windows.
    static func scan(_ c: CanvasController, _ scWindows: [SCWindow], standard: [CGWindowID] = [], stale: Bool = false) {
        var ax = CanvasController.AXSnapshot()
        for id in standard {
            ax.standard.insert(id)
            ax.known.insert(id)
            c.windowKinds[id] = CanvasController.WindowKind(standard: true, at: CACurrentMediaTime())
        }
        c.apply(scWindows, ax: ax, stale: stale)
    }

    static func window(_ c: CanvasController, _ id: CGWindowID) -> ManagedWindow? { c.windows.first { $0.id == id } }

    /// A scan's Accessibility input, live (at 100%), with these window kinds.
    static func liveInput(kinds: [CGWindowID: CanvasController.WindowKind] = [:]) -> CanvasController.ScanInput {
        var input = CanvasController.ScanInput()
        input.live = true
        input.kinds = kinds
        input.corner = CGPoint(x: 1472, y: 902)
        return input
    }

    static func seedAppOwner(_ pid: pid_t, _ app: pid_t?, at: CFTimeInterval) {
        CanvasController.appPolicyLock.lock()
        CanvasController.appOwners[pid] = (app, at)
        CanvasController.appPolicyLock.unlock()
    }

    // MARK: TRACK-01

    @Test("TRACK-01 Windows out of view are parked in the bottom-right corner")
    func track01() {
        let on = Self.placed(101, canvas: CGRect(x: 100, y: 100, width: 400, height: 300))
        let far = Self.placed(102, canvas: CGRect(x: 5000, y: 5000, width: 400, height: 300))
        let c = Self.canvas([on, far])
        defer { Self.finish(c) }
        #expect(c.parkPoint == CGPoint(x: 1511, y: 981))
        let plan = c.commitPlan()
        let onPlan = plan.first { $0.0 === on }, farPlan = plan.first { $0.0 === far }
        #expect(onPlan?.1 == CGPoint(x: 100, y: 133) && onPlan?.2 == false)
        #expect(farPlan?.1 == c.parkPoint && farPlan?.2 == true)
        c.commit()
        #expect(far.parked && !on.parked)
        // On the canvas it's at its own spot, not in the corner.
        #expect(far.canvasFrame.origin == CGPoint(x: 5000, y: 5000))
    }

    // MARK: TRACK-02

    @Test("TRACK-02 A window partly in view stays on screen at its spot (48pt minimum)")
    func track02() {
        let vp = CGRect(x: 0, y: 33, width: 1512, height: 949)
        func onScreen(_ r: CGRect, panels: CGRect = .null) -> Bool { CanvasController.goesOnScreen(r, in: vp, panels: panels) }
        // A third of it at the right edge.
        #expect(onScreen(CGRect(x: 1312, y: 200, width: 600, height: 400)))
        #expect(onScreen(CGRect(x: 1464, y: 200, width: 600, height: 400)))
        #expect(!onScreen(CGRect(x: 1465, y: 200, width: 600, height: 400)))
        // At the bottom.
        #expect(onScreen(CGRect(x: 200, y: 934, width: 600, height: 400)))
        #expect(!onScreen(CGRect(x: 200, y: 935, width: 600, height: 400)))
        // At the left.
        #expect(onScreen(CGRect(x: -552, y: 200, width: 600, height: 400)))
        #expect(!onScreen(CGRect(x: -553, y: 200, width: 600, height: 400)))
        #expect(!onScreen(CGRect(x: 3000, y: 200, width: 600, height: 400)))
        // Since 4045597: a sliver that would cover the minimap or Spaces panel is parked; more isn't.
        let minimap = CGRect(x: 1300, y: 800, width: 200, height: 150)
        #expect(!onScreen(CGRect(x: 1450, y: 700, width: 600, height: 400), panels: minimap))
        #expect(onScreen(CGRect(x: 1450, y: 700, width: 600, height: 400)))
        #expect(onScreen(CGRect(x: 1312, y: 700, width: 600, height: 400), panels: minimap))
    }

    @Test("TRACK-02 commitPlan puts a window a third in view on screen, partly off the edge")
    func track02b() {
        let w = Self.placed(201, canvas: CGRect(x: 1312, y: 50, width: 600, height: 400))
        let sliver = Self.placed(202, canvas: CGRect(x: 1470, y: 500, width: 600, height: 300))
        let c = Self.canvas([w, sliver])
        defer { Self.finish(c) }
        let plan = c.commitPlan()
        let p = plan.first { $0.0 === w }
        #expect(p?.1 == CGPoint(x: 1312, y: 83) && p?.2 == false)
        #expect(plan.first { $0.0 === sliver }?.2 == true)
    }

    // MARK: TRACK-03

    @Test("TRACK-03 A window cut off at the top stays parked")
    func track03() {
        let vp = CGRect(x: 0, y: 33, width: 1512, height: 949)
        #expect(CanvasController.goesOnScreen(CGRect(x: 300, y: 32, width: 600, height: 400), in: vp, panels: .null))
        #expect(!CanvasController.goesOnScreen(CGRect(x: 300, y: 31, width: 600, height: 400), in: vp, panels: .null))
        // Just below the menu bar, then the view moved down 150pt.
        let w = Self.placed(301, canvas: CGRect(x: 300, y: 0, width: 600, height: 400))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        #expect(c.commitPlan().first?.2 == false)
        c.camera.origin.y += 150
        #expect(c.commitPlan().first?.2 == true)
        #expect(c.commitPlan().first?.1 == c.parkPoint)
    }

    // MARK: TRACK-04 (manual)

    @Test("TRACK-04 Focus going to a parked window glides to it; with auto-centre off it doesn't (logic)")
    func track04() {
        let here = Self.placed(401, pid: 90_401, canvas: CGRect(x: 200, y: 200, width: 600, height: 400))
        let te = Self.parked(402, pid: 90_402, canvas: CGRect(x: 5000, y: 200, width: 600, height: 400))
        let c = Self.canvas([te, here])
        defer { Self.finish(c) }
        Self.watchGlides(c)
        Env.withDefaults(["autoCentre": false]) {
            c.lastHiddenHint = te.id   // (no toast here)
            c.focusSettled(on: te.id)
            #expect(c.glideTarget == nil)
        }
        Env.withDefaults(["autoCentre": true]) {
            c.focusSettled(on: te.id)
            #expect(c.glideTarget === te)
        }
    }

    // MARK: TRACK-05 (manual)

    @Test("TRACK-05 Focusing a partly visible window centres it, unless you placed the view yourself (logic)")
    func track05() {
        Env.withDefaults(["autoCentre": true]) {
            let w = Self.placed(501, canvas: CGRect(x: 1300, y: 100, width: 600, height: 400))
            let c = Self.canvas([w])
            defer { Self.finish(c) }
            Self.watchGlides(c)
            // You panned at 100% (e1165df): it's focused where it is.
            c.viewPlaced = true
            c.focusSettled(on: w.id)
            #expect(c.glideTarget == nil)
            c.viewPlaced = false
            c.focusSettled(on: w.id)
            #expect(c.glideTarget === w)
        }
    }

    // MARK: TRACK-06 (manual)

    @Test("TRACK-06 Moving a window yourself at 100% is followed (logic)")
    func track06() {
        let w = Self.placed(601, canvas: CGRect(x: 300, y: 200, width: 500, height: 400))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        w.lastPlacedAt = CACurrentMediaTime() - 20
        let element = AXUIElementCreateApplication(w.pid)
        // Moved without the mouse (a keyboard shortcut, say), long after Expanse placed it.
        c.realWindowChanged(w, element, userDragging: false, size: w.canvasFrame.size, position: CGPoint(x: 700, y: 433),
                            inFullScreenSpace: false)
        #expect(w.canvasFrame.origin == CGPoint(x: 700, y: 400))
        #expect(w.lastPlaced == nil)
    }

    // MARK: TRACK-07 (manual)

    @Test("TRACK-07 A closed window leaves the canvas (logic)")
    func track07() {
        let f = Self.placed(701, pid: 90_701, canvas: CGRect(x: 200, y: 200, width: 600, height: 400))
        let other = Self.placed(702, pid: 90_702, canvas: CGRect(x: 900, y: 200, width: 400, height: 400))
        let c = Self.canvas([f, other])
        defer { Self.finish(c) }
        c.closedWindows.insert(701)
        Self.scan(c, [other.scWindow])
        #expect(c.windows.map(\.id) == [702])
        #expect(c.recentlyRemoved[701]?.closed == true)
        #expect(!c.closedWindows.contains(701))
    }

    // MARK: TRACK-08

    @Test("TRACK-08 The canvas stacks windows as macOS does")
    func track08() {
        let a = Self.placed(801, canvas: CGRect(x: 100, y: 100, width: 600, height: 400))
        let b = Self.placed(802, canvas: CGRect(x: 300, y: 200, width: 600, height: 400))
        let x = Self.placed(803, canvas: CGRect(x: 2000, y: 100, width: 600, height: 400))
        let c = Self.canvas([x, b, a])   // back to front: A in front
        defer { Self.finish(c) }
        c.orderByWindowServer([:])
        #expect(c.windows.map(\.id) == [803, 802, 801])
        // B clicked: the window server has it in front (rank 0).
        c.orderByWindowServer([802: 0, 801: 1])
        #expect(c.windows.map(\.id) == [803, 801, 802])
    }

    // MARK: TRACK-09

    @Test("TRACK-09 Restore all windows brings out-of-view windows on screen")
    func track09() {
        let on1 = Self.placed(901, canvas: CGRect(x: 100, y: 100, width: 400, height: 300))
        let on2 = Self.placed(902, canvas: CGRect(x: 600, y: 100, width: 400, height: 300))
        let away = (0..<9).map { i in
            let w = Fake.window(id: 910 + CGWindowID(i), canvas: CGRect(x: 5000 + CGFloat(i) * 700, y: 3000, width: 600, height: 400))
            w.parked = true
            return w
        }
        let c = Self.canvas([on1] + away + [on2])
        defer { Self.finish(c) }
        c.restoreAll()
        for (i, w) in away.enumerated() {
            // The first centred 40pt below the menu bar, each next 28pt right and down, wrapping after eight.
            let step = CGFloat(i % 8) * 28
            #expect(w.canvasFrame.origin == CGPoint(x: 756 - 300 + step, y: 40 + step))
            #expect(!w.parked)
        }
        #expect(on1.canvasFrame.origin == CGPoint(x: 100, y: 100))
        #expect(on2.canvasFrame.origin == CGPoint(x: 600, y: 100))
    }

    // MARK: TRACK-10, TRACK-15 (manual)

    /// TextEdit's window (900×650 on this screen, 1000×700 the size you chose) minimised or
    /// hidden, then back from the Dock (or unhidden) where macOS puts it.
    static func awayAndBack() -> (CanvasController, here: ManagedWindow, back: ManagedWindow?) {
        let here = Self.placed(1001, pid: 91_001, canvas: CGRect(x: 100, y: 100, width: 400, height: 300))
        let te = Self.placed(1002, pid: 91_002, appName: "TextEdit", canvas: CGRect(x: 2000, y: 300, width: 900, height: 650))
        te.preferredSize = CGSize(width: 1000, height: 700)
        te.originalFrame = CGRect(x: 50, y: 80, width: 800, height: 600)
        let c = Self.canvas([here, te])
        Self.watchGlides(c)
        Self.scan(c, [here.scWindow])
        #expect(Self.window(c, 1002) == nil)
        let back = Fake.scWindow(id: 1002, pid: 91_002, appName: "TextEdit", frame: CGRect(x: 1480, y: 940, width: 900, height: 650))
        Self.scan(c, [here.scWindow, back], standard: [1002])
        return (c, here, Self.window(c, 1002))
    }

    @Test("TRACK-10 A minimised or hidden window comes back to its own spot (logic)")
    func track10() {
        let (c, here, w) = Self.awayAndBack()
        defer { Self.finish(c) }
        #expect(w?.canvasFrame == CGRect(x: 2000, y: 300, width: 900, height: 650))
        // Not placed again as a new window.
        #expect(here.canvasFrame.origin == CGPoint(x: 100, y: 100))
    }

    @Test("TRACK-15 A window back from hiding keeps its macOS spot and chosen size (logic)")
    func track15() {
        let (c, _, w) = Self.awayAndBack()
        defer { Self.finish(c) }
        #expect(w?.preferredSize == CGSize(width: 1000, height: 700))
        #expect(w?.originalFrame == CGRect(x: 50, y: 80, width: 800, height: 600))
    }

    // MARK: TRACK-11 (manual)

    @Test("TRACK-11 A stranded window in the parking corner is brought into view (logic)")
    func track11() {
        let c = Self.canvas()
        defer { Self.finish(c) }
        // Launch, with no record of the window (layout.json moved aside).
        c.firstSync = true
        Fake.regularApp(91_101)
        let sc = Fake.scWindow(id: 1101, pid: 91_101, frame: CGRect(x: 1490, y: 950, width: 600, height: 400))
        Self.scan(c, [sc], standard: [1101])
        // Horizontally centred, 40pt below the top of the usable screen.
        #expect(Self.window(c, 1101)?.canvasFrame.origin == CGPoint(x: 756 - 300, y: 40))
    }

    // MARK: TRACK-13, TRACK-38 (manual)

    @Test("TRACK-13 A window that comes back by itself returns quietly to its spot (logic)")
    func track13() {
        let here = Self.placed(1301, pid: 91_301, canvas: CGRect(x: 100, y: 100, width: 400, height: 300))
        let te = Self.parked(1302, pid: 91_302, canvas: CGRect(x: 4000, y: 300, width: 600, height: 400))
        let c = Self.canvas([te, here])
        defer { Self.finish(c) }
        Self.watchGlides(c)
        let camera = c.camera
        Self.scan(c, [here.scWindow])
        let back = Fake.scWindow(id: 1302, pid: 91_302, frame: CGRect(x: 1480, y: 940, width: 600, height: 400))
        Self.scan(c, [here.scWindow, back], standard: [1302])
        #expect(Self.window(c, 1302)?.canvasFrame.origin == CGPoint(x: 4000, y: 300))
        #expect(c.glideGeneration == 0)
        #expect(c.camera == camera)
    }

    @Test("TRACK-38 Windows back after a Space switch come back quietly (logic)")
    func track38() {
        let here = Self.placed(3801, pid: 93_801, canvas: CGRect(x: 100, y: 100, width: 400, height: 300))
        let te = Self.parked(3802, pid: 93_802, canvas: CGRect(x: 4000, y: 300, width: 600, height: 400))
        let c = Self.canvas([te, here])
        defer { Self.finish(c) }
        Self.watchGlides(c)
        Self.scan(c, [here.scWindow])
        // Restored from the Dock, but over 3s ago: only one in the last 3s counts as you asking.
        c.restoredAt[3802] = CACurrentMediaTime() - 4
        c.shownAgainAt[93_802] = CACurrentMediaTime() - 4
        let back = Fake.scWindow(id: 3802, pid: 93_802, frame: CGRect(x: 1480, y: 940, width: 600, height: 400))
        Self.scan(c, [here.scWindow, back], standard: [3802])
        #expect(Self.window(c, 3802)?.canvasFrame.origin == CGPoint(x: 4000, y: 300))
        #expect(c.glideGeneration == 0)
    }

    // MARK: TRACK-16

    @Test("TRACK-16 Window scans held back during a drag don't pile up")
    func track16() async throws {
        let c = Self.canvas()
        defer { Self.finish(c) }
        CanvasController.screenCaptureAllowed = true
        defer { CanvasController.screenCaptureAllowed = nil }
        // A glide or drag under way: scans are held back, with one retry.
        c.gliding = true
        c.sync()
        #expect(c.syncRetryScheduled)
        for _ in 0..<10 { c.sync() }
        #expect(c.syncRetryScheduled)
        // It ends. The retry comes due (0.4s) and runs; a scan is marked as running, so it only
        // notes that another is wanted (nothing is scanned here).
        c.gliding = false
        c.syncing = true
        try await Task.sleep(for: .milliseconds(600))
        #expect(!c.syncRetryScheduled)
        #expect(c.syncAgain)
    }

    // MARK: TRACK-18

    @Test("TRACK-18 An app that quit doesn't leave its observer behind")
    func track18() throws {
        let pid: pid_t = 91_801
        let c = Self.canvas()
        defer { Self.finish(c) }
        let old = try #require(AppObserver(pid: pid) { _, _, _ in })
        c.observers[pid] = old
        c.focusedWindowByApp[pid] = 1801
        c.appTerminated(Notification(name: NSWorkspace.didTerminateApplicationNotification, object: NSWorkspace.shared,
                                     userInfo: [NSWorkspace.applicationUserInfoKey: QuitApp(pid)]))
        #expect(c.observers[pid] == nil)
        #expect(c.focusedWindowByApp[pid] == nil)
        // A later app given the same process ID gets an observer of its own.
        c.observeApp(pid)
        #expect(c.observers[pid] != nil)
        #expect(c.observers[pid] !== old)
    }

    // MARK: TRACK-19

    static func departed(_ ago: TimeInterval, closed: Bool) -> CanvasController.Departed {
        CanvasController.Departed(pid: 91_901, bundleID: "com.apple.finder", appName: "Finder", title: "",
                                  canvasFrame: CGRect(x: 0, y: 0, width: 400, height: 300), originalFrame: .zero,
                                  preferredSize: .zero, home: nil, parked: false, at: Date().addingTimeInterval(-ago), closed: closed)
    }

    @Test("TRACK-19 Records of departed windows are pruned: closed after 10s, others after a week")
    func track19() {
        let w = Self.placed(1910, canvas: CGRect(x: 100, y: 100, width: 400, height: 300))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        c.recentlyRemoved = [1: Self.departed(11, closed: true), 2: Self.departed(5, closed: true),
                             3: Self.departed(8 * 86_400, closed: false), 4: Self.departed(6 * 86_400, closed: false)]
        c.remove(w)
        #expect(Set(c.recentlyRemoved.keys) == [2, 4, 1910])
    }

    @Test("TRACK-19 At most 300 records are kept, the oldest dropped first")
    func track19b() {
        let w = Self.placed(1920, canvas: CGRect(x: 100, y: 100, width: 400, height: 300))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        c.recentlyRemoved = Dictionary(uniqueKeysWithValues: (0..<300).map { (CGWindowID(10_000 + $0), Self.departed(Double($0 + 1) * 60, closed: false)) })
        c.remove(w)
        #expect(c.recentlyRemoved.count == 300)
        #expect(c.recentlyRemoved[10_299] == nil)
        #expect(c.recentlyRemoved[10_298] != nil)
        #expect(c.recentlyRemoved[1920] != nil)
    }

    // MARK: TRACK-20

    @Test("TRACK-20 A window found in the parking corner never takes that spot")
    func track20() {
        let w = Self.placed(2001, canvas: CGRect(x: 200, y: 200, width: 600, height: 400))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        #expect(c.parkingCorner == CGPoint(x: 1472, y: 902))
        #expect(c.inParkingCorner(c.parkPoint))
        #expect(c.inParkingCorner(CGPoint(x: 1480, y: 940)))
        #expect(!c.inParkingCorner(CGPoint(x: 1400, y: 940)))
        #expect(!c.inParkingCorner(CGPoint(x: 1480, y: 850)))
        // After wake: Expanse placed it on screen, but a scan finds it in the corner.
        let found = Fake.scWindow(id: 2001, frame: CGRect(x: 1480, y: 940, width: 600, height: 400))
        Self.scan(c, [found])
        #expect(w.canvasFrame.origin == CGPoint(x: 200, y: 200))
        #expect(w.parked)
        #expect(w.lastPlaced == CGPoint(x: 1480, y: 940))
    }

    // MARK: TRACK-21 (manual)

    @Test("TRACK-21 The echo of Expanse's own move is ignored, and a drag is looked at once per 50ms (logic)")
    func track21() {
        let w = Self.placed(2101, canvas: CGRect(x: 200, y: 200, width: 600, height: 400))
        let c = Self.canvas([w])
        defer { Self.finish(c); c.changedWindows = [:] }
        let element = AXUIElementCreateApplication(w.pid)
        w.lastPlacedAt = CACurrentMediaTime()
        // (It reads the real mouse button: held down, a move is a drag, never an echo.)
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
        c.handleAXEvent(element, kAXMovedNotification as String, id: w.id)
        #expect(c.changedWindows.isEmpty != mouseDown)
        w.lastPlacedAt = CACurrentMediaTime() - 1
        c.handleAXEvent(element, kAXMovedNotification as String, id: w.id)
        c.handleAXEvent(element, kAXMovedNotification as String, id: w.id)
        #expect(c.changedWindows.count == 1)
        #expect(c.changedWindowsScheduled)
    }

    // MARK: TRACK-22

    @Test("TRACK-22 Parked windows aren't moved again on every hop")
    func track22() {
        let w = Self.placed(2201, canvas: CGRect(x: 300, y: 200, width: 600, height: 400))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        // Parked, and macOS nudged it within the corner: anywhere in the corner will do.
        w.parked = true
        w.lastPlaced = CGPoint(x: 1480, y: 940)
        #expect(c.alreadyAt(w, c.parkPoint, parked: true))
        // Coming on screen, it moves.
        #expect(!c.alreadyAt(w, CGPoint(x: 300, y: 233), parked: false))
        // On screen: only where it was last put (within half a point).
        w.parked = false
        w.lastPlaced = CGPoint(x: 300, y: 233)
        #expect(c.alreadyAt(w, CGPoint(x: 300, y: 233), parked: false))
        #expect(c.alreadyAt(w, CGPoint(x: 300.4, y: 233), parked: false))
        #expect(!c.alreadyAt(w, CGPoint(x: 301, y: 233), parked: false))
        // Going off screen, it moves.
        #expect(!c.alreadyAt(w, c.parkPoint, parked: true))
        w.lastPlaced = nil
        #expect(!c.alreadyAt(w, CGPoint(x: 300, y: 233), parked: false))
    }

    // MARK: TRACK-23 (manual)

    @Test("TRACK-23 Window scans don't ask apps about windows already in place (logic)")
    func track23() {
        let pid: pid_t = 92_301
        Fake.regularApp(pid)
        let inPlace = Fake.scWindow(id: 2301, pid: pid, frame: CGRect(x: 100, y: 133, width: 600, height: 400))
        let parked = Fake.scWindow(id: 2302, pid: pid, frame: CGRect(x: 1490, y: 950, width: 600, height: 400))
        let panel = Fake.scWindow(id: 2303, pid: pid, frame: CGRect(x: 800, y: 133, width: 300, height: 400))
        var input = Self.liveInput(kinds: [2303: CanvasController.WindowKind(standard: false, at: CACurrentMediaTime())])
        input.tracked[2301] = (nil, inPlace.frame, false)
        input.tracked[2302] = (nil, nil, true)
        let s = CanvasController.axSnapshot(for: [inPlace, parked, panel], input: input)
        #expect(s.calls == 0)
        #expect(s.frames.isEmpty)
        #expect(s.known == [2303])
    }

    // MARK: TRACK-25 (manual)

    @Test("TRACK-25 A window restored from the Dock triggers a scan straight away (logic)")
    func track25() {
        let w = Self.placed(2501, canvas: CGRect(x: 200, y: 200, width: 600, height: 400))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        c.handleAXEvent(AXUIElementCreateApplication(w.pid), kAXWindowDeminiaturizedNotification as String, id: w.id)
        #expect(c.restoredAt[w.id] != nil)
        #expect(c.syncSoonWork != nil)
    }

    @Test("TRACK-25 A window a scan catches on its way into the Dock comes back to its own spot (logic)")
    func track25b() {
        let w = Self.placed(2502, canvas: CGRect(x: 200, y: 200, width: 600, height: 400))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        // Minimising: a scan sees it part way to the Dock and follows it...
        let real = w.lastPlaced ?? .zero
        c.apply([Fake.scWindow(id: w.id, frame: CGRect(x: real.x + 400, y: real.y + 300, width: 600, height: 400))],
                ax: CanvasController.AXSnapshot())
        #expect(w.canvasFrame.origin == CGPoint(x: 600, y: 500), "the scan followed it")
        // ...and a moment later it's gone: what's kept for its return is its spot from before.
        c.remove(w)
        #expect(c.recentlyRemoved[w.id]?.canvasFrame.origin == CGPoint(x: 200, y: 200))
    }

    // MARK: TRACK-26

    @Test("TRACK-26 A scan's frames are out of date if windows moved or the camera changed while it ran")
    func track26() {
        let w = Self.placed(2601, canvas: CGRect(x: 100, y: 100, width: 400, height: 300))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        let input = c.scanInput()
        #expect(!c.scanIsStale(input))
        ManagedWindow.moves += 1
        #expect(c.scanIsStale(input))
        ManagedWindow.moves -= 1
        c.camera.origin.x += 40
        #expect(c.scanIsStale(input))
        c.camera.origin.x -= 40
        // Zoomed out, or displays changing, since the scan started.
        c.isActive = true
        #expect(c.scanIsStale(input))
        c.isActive = false
        c.suspendTracking = true
        #expect(c.scanIsStale(input))
        c.suspendTracking = false
        #expect(!c.scanIsStale(input))
        // Zoomed out throughout: frames aren't followed then, so it's fine.
        c.isActive = true
        let zoomedOut = c.scanInput()
        c.camera.origin.x += 40
        #expect(!c.scanIsStale(zoomedOut))
        // But sizes are taken from scans zoomed out too: one from before Expanse resized a window
        // (fitting the layout to a new screen) is out of date (DISPLAY-18).
        ManagedWindow.resizes += 1
        #expect(c.scanIsStale(zoomedOut))
        ManagedWindow.resizes -= 1
        c.isActive = false
        c.camera.origin.x -= 40
    }

    @Test("TRACK-26 A scan during a glide doesn't drag windows back")
    func track26b() {
        let w = Self.placed(2602, canvas: CGRect(x: 100, y: 100, width: 400, height: 300))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        // Where the window was before the glide moved it.
        let old = Fake.scWindow(id: 2602, frame: CGRect(x: 600, y: 433, width: 400, height: 300))
        Self.scan(c, [old], stale: true)
        #expect(w.canvasFrame.origin == CGPoint(x: 100, y: 100))
        #expect(w.lastPlaced == CGPoint(x: 100, y: 133))
        // (The same frame in an up-to-date scan is a move by you, and followed.)
        Self.scan(c, [old])
        #expect(w.canvasFrame.origin == CGPoint(x: 600, y: 400))
    }

    // MARK: TRACK-28

    @Test("TRACK-28 A window its app doesn't list yet is pending for its first 5s, then noted")
    func track28() {
        let pid: pid_t = 92_801
        Fake.regularApp(pid)
        let sc = Fake.scWindow(id: 2801, pid: pid, appName: "Finder", frame: CGRect(x: 100, y: 100, width: 600, height: 400))
        let first = CanvasController.axSnapshot(for: [sc], input: Self.liveInput())
        let kind = try? #require(first.kinds[2801])
        #expect(kind?.pending == true && kind?.standard == false)
        #expect(first.pending)
        #expect(first.known.contains(2801) && !first.standard.contains(2801))
        #expect(first.skipped[2801] == nil)
        // Not taken on yet.
        let c = Self.canvas()
        defer { Self.finish(c) }
        c.apply([sc], ax: first)
        #expect(c.windows.isEmpty)
        // The next scan asks again, still pending.
        let second = CanvasController.axSnapshot(for: [sc], input: Self.liveInput(kinds: first.kinds))
        #expect(second.calls == 1)
        #expect(second.pending && second.kinds[2801]?.pending == true)
        // After 5s it's no longer pending, and noted (once listed, it's taken on at the next scan).
        let now = CACurrentMediaTime()
        let old = CanvasController.WindowKind(standard: false, at: now - 6, pending: true, unlistedSince: now - 6)
        let later = CanvasController.axSnapshot(for: [sc], input: Self.liveInput(kinds: [2801: old]))
        #expect(!later.pending && later.kinds[2801]?.pending == false)
        #expect(later.skipped[2801]?.contains("doesn't list it") == true)
        #expect(later.recheck)
        // Once it's a standard window, it's on the canvas.
        Self.scan(c, [sc], standard: [2801])
        #expect(c.windows.map(\.id) == [2801])
    }

    // MARK: TRACK-29

    @Test("TRACK-29 A window scan asked for during another scan isn't lost")
    func track29() throws {
        let c = Self.canvas()
        defer { Self.finish(c) }
        CanvasController.screenCaptureAllowed = true
        defer { CanvasController.screenCaptureAllowed = nil }
        c.syncing = true
        c.sync()
        #expect(c.syncAgain)
        // Asked for again while one is due: the one due isn't pushed back.
        c.syncSoon()
        let due = try #require(c.syncSoonWork)
        c.syncSoon()
        #expect(c.syncSoonWork === due)
    }

    // MARK: TRACK-30

    @Test("TRACK-30 A scan that overlapped a window move still adds new windows")
    func track30() {
        Env.withDefaults(["autoCentre": true]) {
            let a = Self.placed(3001, canvas: CGRect(x: 100, y: 100, width: 400, height: 300))
            let c = Self.canvas([a])
            defer { Self.finish(c) }
            Self.watchGlides(c)
            // Out of date: A elsewhere and another size; a new window opened meanwhile.
            let staleA = Fake.scWindow(id: 3001, frame: CGRect(x: 700, y: 500, width: 500, height: 400))
            let n = Fake.scWindow(id: 3002, frame: CGRect(x: 40, y: 60, width: 300, height: 200))
            Self.scan(c, [staleA, n], standard: [3002], stale: true)
            #expect(a.canvasFrame == CGRect(x: 100, y: 100, width: 400, height: 300))
            #expect(a.lastPlaced == CGPoint(x: 100, y: 133))
            // The new one is placed beside A all the same.
            #expect(Self.window(c, 3002)?.canvasFrame.origin == CGPoint(x: 520, y: 100))
        }
    }

    // MARK: TRACK-32

    @Test("TRACK-32 An app's late move doesn't drag a window off its spot")
    func track32() {
        let w = Self.placed(3201, canvas: CGRect(x: 300, y: 200, width: 500, height: 400))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        let before = CGPoint(x: 300, y: 233), after = CGPoint(x: 900, y: 233)
        w.lastPlaced = after   // Expanse moved it on
        #expect(w.placedBefore == before)
        // 100s on: no longer a window that's just opened.
        let t = CACurrentMediaTime() + 100
        w.lastPlacedAt = t - 3
        // Somewhere else: you (or the app) moved it, followed.
        #expect(!c.cameBack(w, to: CGPoint(x: 700, y: 500), now: t))
        // The app carrying out the old move: put back.
        #expect(c.cameBack(w, to: before, now: t))
        #expect(w.lastPlaced == before && !w.parked)
        #expect(w.cameBackAt == t)
        // Again within 10s: the app gets its way.
        w.lastPlaced = after
        w.lastPlacedAt = t + 1
        #expect(!c.cameBack(w, to: before, now: t + 5))
        // Over 10s later, once more.
        w.lastPlacedAt = t + 9
        #expect(c.cameBack(w, to: before, now: t + 11))
        // Not when Expanse placed it over 10s ago.
        w.lastPlaced = after
        w.lastPlacedAt = t + 30
        #expect(!c.cameBack(w, to: before, now: t + 41))
    }

    @Test("TRACK-32 A window under 5s old is put back wherever its app moves it")
    func track32b() {
        let w = Self.placed(3202, canvas: CGRect(x: 300, y: 200, width: 500, height: 400))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        w.lastPlacedAt = CACurrentMediaTime() - 1
        #expect(c.cameBack(w, to: CGPoint(x: 777, y: 300)))
        #expect(w.lastPlaced == CGPoint(x: 777, y: 300))
        // Through realWindowChanged too: its canvas spot stays.
        let w2 = Self.placed(3203, canvas: CGRect(x: 900, y: 200, width: 500, height: 400))
        c.windows.append(w2)
        w2.lastPlacedAt = CACurrentMediaTime() - 1
        c.realWindowChanged(w2, AXUIElementCreateApplication(w2.pid), userDragging: false,
                            size: w2.canvasFrame.size, position: CGPoint(x: 40, y: 60), inFullScreenSpace: false)
        #expect(w2.canvasFrame.origin == CGPoint(x: 900, y: 200))
        #expect(w2.lastPlaced == CGPoint(x: 40, y: 60))
    }

    // MARK: TRACK-33

    @Test("TRACK-33 Dragging a just-opened window yourself is still followed")
    func track33() {
        let w = Self.placed(3301, canvas: CGRect(x: 300, y: 200, width: 500, height: 400))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        // Just placed, and under 5s old: a move by its app would be put back.
        w.lastPlacedAt = CACurrentMediaTime()
        c.realWindowChanged(w, AXUIElementCreateApplication(w.pid), userDragging: true,
                            size: w.canvasFrame.size, position: CGPoint(x: 700, y: 433), inFullScreenSpace: false)
        #expect(w.canvasFrame.origin == CGPoint(x: 700, y: 400))
        #expect(w.lastPlaced == nil)
        #expect(w.cameBackAt == 0)
    }

    // MARK: TRACK-34

    @Test("TRACK-34 Parked windows stay parked when the Dock is always shown")
    func track34() {
        let bottom = Self.canvas(display: TestDisplay(dockBottom: 70))
        defer { Self.finish(bottom) }
        #expect(bottom.parkingCorner == CGPoint(x: 1472, y: 832))
        // macOS keeps a strip of a parked window above the Dock.
        #expect(bottom.inParkingCorner(CGPoint(x: 1480, y: 850)))
        #expect(!bottom.inParkingCorner(CGPoint(x: 1480, y: 800)))
        let right = Self.canvas(display: TestDisplay(dockRight: 80))
        defer { Self.finish(right) }
        #expect(right.parkingCorner == CGPoint(x: 1392, y: 902))
        #expect(right.inParkingCorner(CGPoint(x: 1400, y: 950)))
        #expect(!right.inParkingCorner(CGPoint(x: 1380, y: 950)))
    }

    @Test("TRACK-34 A parked window nudged above the Dock keeps its canvas spot")
    func track34b() {
        let w = Self.parked(3401, canvas: CGRect(x: 3000, y: 200, width: 600, height: 400), at: CGPoint(x: 1511, y: 981))
        let c = Self.canvas([w], display: TestDisplay(dockBottom: 70))
        defer { Self.finish(c) }
        let nudged = Fake.scWindow(id: 3401, frame: CGRect(x: 1480, y: 850, width: 600, height: 400))
        Self.scan(c, [nudged])
        #expect(w.canvasFrame.origin == CGPoint(x: 3000, y: 200))
        #expect(w.parked)
    }

    // MARK: TRACK-35 (manual)

    @Test("TRACK-35 Closing a window keeps the view where it is (logic)")
    func track35() {
        Env.withDefaults(["autoCentre": true]) {
            let f2 = Self.parked(3502, pid: 93_501, canvas: CGRect(x: 6000, y: 200, width: 600, height: 400))
            let c = Self.canvas([f2])
            defer { Self.finish(c) }
            Self.watchGlides(c)
            // F1 just closed; macOS gives F2 focus.
            c.lastClose = (pid: 93_501, at: CACurrentMediaTime())
            c.focusSettled(on: f2.id)
            #expect(c.glideTarget == nil)
            // Without a close just before, focus going to it is followed.
            c.lastClose = nil
            c.focusSettled(on: f2.id)
            #expect(c.glideTarget === f2)
        }
    }

    // MARK: TRACK-36, TRACK-37 (manual)

    /// A hidden or minimised window of the app in front coming back off screen (or on screen);
    /// `asked` marks it as asked for, as an unhide or a restore from the Dock does.
    static func comesBack(onScreen: Bool, _ asked: (CanvasController, ManagedWindow) -> Void) throws -> CanvasController {
        // Its app is in front: the window's process is fake, its app the real front one.
        let front = try #require(NSWorkspace.shared.frontmostApplication)
        let pid: pid_t = 93_601
        let here = Self.placed(3610, pid: 93_602, canvas: CGRect(x: 100, y: 100, width: 600, height: 400))
        let spot = onScreen ? CGRect(x: 800, y: 100, width: 500, height: 400) : CGRect(x: 5000, y: 200, width: 500, height: 400)
        let corner = CGPoint(x: 1480, y: 940)
        Fake.regularApp(pid, ownedBy: front.processIdentifier)
        let w = ManagedWindow(scWindow: Fake.scWindow(id: 3611, pid: pid, frame: CGRect(origin: corner, size: spot.size)), canvasFrame: spot)
        w.parked = true
        w.lastPlaced = corner
        #expect(w.appPID == front.processIdentifier)
        let c = Self.canvas([w, here])
        Self.watchGlides(c)
        Self.scan(c, [here.scWindow])
        asked(c, w)
        let back = Fake.scWindow(id: 3611, pid: pid, frame: CGRect(origin: CGPoint(x: 1480, y: 940), size: spot.size))
        Self.scan(c, [here.scWindow, back], standard: [3611])
        #expect(Self.window(c, 3611)?.canvasFrame == spot)
        return c
    }

    @Test("TRACK-36 Hiding an app, then ⌘-Tab to it, glides to its window (logic)")
    func track36() throws {
        let c = try Self.comesBack(onScreen: false) { c, w in c.shownAgainAt[w.appPID] = CACurrentMediaTime() }
        defer { Self.finish(c) }
        #expect(c.glideTarget?.id == 3611)
    }

    @Test("TRACK-36 Back from hiding and already on screen, it just reappears (logic)")
    func track36b() throws {
        let c = try Self.comesBack(onScreen: true) { c, w in c.shownAgainAt[w.appPID] = CACurrentMediaTime() }
        defer { Self.finish(c) }
        #expect(c.glideGeneration == 0)
    }

    @Test("TRACK-37 A window brought back from the Dock glides into view (logic)")
    func track37() throws {
        let c = try Self.comesBack(onScreen: false) { c, w in c.restoredAt[w.id] = CACurrentMediaTime() }
        defer { Self.finish(c) }
        #expect(c.glideTarget?.id == 3611)
    }

    // MARK: TRACK-39 (manual)

    @Test("TRACK-39 An app you quit and open again opens beside your work (logic)")
    func track39() {
        Env.withDefaults(["autoCentre": true]) {
            let calculator: pid_t = 93_901, safari: pid_t = 93_902
            let calc = Self.placed(3901, pid: calculator, appName: "Calculator", canvas: CGRect(x: 5000, y: 200, width: 300, height: 400))
            let s = Self.placed(3902, pid: safari, appName: "Safari", canvas: CGRect(x: 300, y: 200, width: 600, height: 500))
            let c = Self.canvas([calc, s])
            defer { Self.finish(c) }
            Self.watchGlides(c)
            c.restartSpotsUntil = .distantPast   // running for over 3 minutes
            // Another of its windows, out of view (minimised).
            c.recentlyRemoved[3903] = CanvasController.Departed(pid: calculator, bundleID: "com.apple.calculator", appName: "Calculator",
                                                               title: "", canvasFrame: CGRect(x: 7000, y: 0, width: 300, height: 400),
                                                               originalFrame: .zero, preferredSize: .zero, home: nil, parked: true, at: Date())
            c.appQuit(QuitApp(calculator))
            #expect(c.windows.map(\.id) == [3902])
            #expect(!c.recentlyRemoved.values.contains { $0.pid == calculator })
            // Kept half a minute only, in case this is a restart.
            #expect(c.justQuit.count == 1 && c.justQuit.first?.spots.count == 2)
            // Opened again from Spotlight: beside the Safari window you're in.
            let relaunched: pid_t = 93_903
            Fake.regularApp(relaunched)
            let n = Fake.scWindow(id: 3904, pid: relaunched, appName: "Calculator", frame: CGRect(x: 40, y: 60, width: 300, height: 400))
            Self.scan(c, [s.scWindow, n], standard: [3904])
            #expect(Self.window(c, 3904)?.canvasFrame.origin == CGPoint(x: 920, y: 200))
        }
    }

    // MARK: TRACK-40

    @Test("TRACK-40 A window drawn by a helper process is its app's, named after the app")
    func track40() throws {
        // The helper's app: a real app that's running (Finder), only looked up.
        let app = try #require(NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" })
        let helper: pid_t = 94_001
        Fake.regularApp(helper, ownedBy: app.processIdentifier)
        #expect(CanvasController.appPID(owning: helper) == app.processIdentifier)
        #expect(!CanvasController.isRegularApp(helper))
        let sc = Fake.scWindow(id: 4001, pid: helper, bundleID: "com.example.helper", appName: "Steam Helper",
                               frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let w = ManagedWindow(scWindow: sc, canvasFrame: sc.frame)
        #expect(w.pid == helper)
        #expect(w.appPID == app.processIdentifier)
        #expect(w.appName == app.localizedName)
        #expect(w.bundleID == "com.apple.finder")
        // An ordinary app is its own; no such process is nobody's.
        #expect(CanvasController.findAppPID(owning: app.processIdentifier) == app.processIdentifier)
        #expect(CanvasController.findAppPID(owning: 94_002) == nil)
    }

    @Test("TRACK-40 Quitting the app takes its helper's windows off the canvas")
    func track40b() {
        let owner: pid_t = 94_011, helper: pid_t = 94_012
        Fake.regularApp(owner)
        Fake.regularApp(helper, ownedBy: owner)
        let sc = Fake.scWindow(id: 4011, pid: helper, appName: "Steam Helper", frame: CGRect(x: 100, y: 133, width: 800, height: 600))
        let w = ManagedWindow(scWindow: sc, canvasFrame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let other = Self.placed(4012, pid: 94_013, canvas: CGRect(x: 1000, y: 100, width: 400, height: 300))
        let c = Self.canvas([w, other])
        defer { Self.finish(c) }
        c.appQuit(QuitApp(owner))
        #expect(c.windows.map(\.id) == [4012])
    }

    // MARK: TRACK-41

    @Test("TRACK-41 Whose window it is is remembered 30s; \"not an app\" only 3s")
    func track41() throws {
        let now = CACurrentMediaTime()
        let pid: pid_t = 94_101, owner: pid_t = 94_102
        defer { Self.seedAppOwner(pid, nil, at: 0) }
        // An answer from 29s ago stands (looking again would find no such process).
        Self.seedAppOwner(pid, owner, at: now - 29)
        #expect(CanvasController.appPID(owning: pid) == owner)
        Self.seedAppOwner(pid, owner, at: now - 31)
        #expect(CanvasController.appPID(owning: pid) == nil)
        // "Not an app" for a real app (it may have just got its Dock icon): kept 3s.
        let app = try #require(NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" })
        let real = app.processIdentifier
        Self.seedAppOwner(real, nil, at: now - 2)
        #expect(CanvasController.appPID(owning: real) == nil)
        Self.seedAppOwner(real, nil, at: now - 4)
        #expect(CanvasController.appPID(owning: real) == real)
    }

    @Test("TRACK-41 A window of an app without a Dock icon is asked about again every 2s for a minute")
    func track41b() {
        let now = CACurrentMediaTime()
        let k = { (since: CFTimeInterval?) in CanvasController.WindowKind(standard: false, at: now, unlistedSince: since) }
        #expect(k(now - 30).askAgainAfter(now) == 2)
        #expect(k(now - 61).askAgainAfter(now) == 10)
        #expect(k(nil).askAgainAfter(now) == 10)
        // Not an app (yet): a titled window is noted, and looked at again shortly.
        let pid: pid_t = 94_111
        Self.seedAppOwner(pid, nil, at: now)
        defer { Self.seedAppOwner(pid, nil, at: 0) }
        let titled = Fake.scWindow(id: 4111, pid: pid, appName: "Late", title: "Window", frame: CGRect(x: 100, y: 100, width: 600, height: 400))
        let popover = Fake.scWindow(id: 4112, pid: pid, appName: "Late", frame: CGRect(x: 800, y: 100, width: 300, height: 400))
        let s = CanvasController.axSnapshot(for: [titled, popover], input: Self.liveInput())
        #expect(s.skipped[4111]?.contains("isn't an app in the Dock") == true)
        #expect(s.kinds[4111]?.unlistedSince != nil)
        #expect(s.recheck)
        #expect(s.skipped[4112] == nil && s.kinds[4112] == nil)
        // After a minute, no quick rechecks for it.
        let old = CanvasController.WindowKind(standard: false, at: now - 70, unlistedSince: now - 70)
        let later = CanvasController.axSnapshot(for: [titled], input: Self.liveInput(kinds: [4111: old]))
        #expect(!later.recheck)
    }

    // MARK: TRACK-42

    @Test("TRACK-42 A window its app is slow to list is asked about every 2s, then every 10s")
    func track42() {
        let now = CACurrentMediaTime()
        #expect(CanvasController.WindowKind(standard: false, at: now, unlistedSince: now - 59).askAgainAfter(now) == 2)
        #expect(CanvasController.WindowKind(standard: false, at: now, unlistedSince: now - 60).askAgainAfter(now) == 10)
        let pid: pid_t = 94_201
        Fake.regularApp(pid)
        let sc = Fake.scWindow(id: 4201, pid: pid, frame: CGRect(x: 100, y: 100, width: 600, height: 400))
        func snapshot(at: CFTimeInterval, since: CFTimeInterval) -> CanvasController.AXSnapshot {
            let kind = CanvasController.WindowKind(standard: false, at: at, unlistedSince: since)
            return CanvasController.axSnapshot(for: [sc], input: Self.liveInput(kinds: [4201: kind]))
        }
        // Unlisted for 10s, last asked 3s ago: asked again.
        let asked = snapshot(at: now - 3, since: now - 10)
        #expect(asked.calls == 1)
        #expect((asked.kinds[4201]?.at ?? 0) >= now)
        #expect(asked.kinds[4201]?.unlistedSince == now - 10)
        #expect(asked.skipped[4201]?.contains("every 2s for a minute, then every 10s") == true)
        #expect(asked.recheck)
        // Asked 1s ago: not yet.
        let notYet = snapshot(at: now - 1, since: now - 10)
        #expect(notYet.calls == 0 && notYet.known.contains(4201))
        // Over a minute unlisted: every 10s.
        #expect(snapshot(at: now - 5, since: now - 70).calls == 0)
        let tenLater = snapshot(at: now - 11, since: now - 70)
        #expect(tenLater.calls == 1)
        #expect(!tenLater.recheck)
    }

    // MARK: TRACK-43

    @Test("TRACK-43 The move that lands just after you let go of a just-opened window isn't put back")
    func track43() {
        let w = Self.placed(4301, canvas: CGRect(x: 300, y: 200, width: 500, height: 400))
        let c = Self.canvas([w])
        defer { Self.finish(c) }
        // Just placed, and under 5s old: a move by its app alone would be put back (TRACK-32).
        w.lastPlacedAt = CACurrentMediaTime()
        c.realWindowChanged(w, AXUIElementCreateApplication(w.pid), userDragging: true,
                            size: w.canvasFrame.size, position: CGPoint(x: 700, y: 433), inFullScreenSpace: false)
        // You let go; the drag's last move lands a moment later, with the button up.
        c.realWindowChanged(w, AXUIElementCreateApplication(w.pid), userDragging: false,
                            size: w.canvasFrame.size, position: CGPoint(x: 720, y: 433), inFullScreenSpace: false)
        #expect(w.canvasFrame.origin == CGPoint(x: 720, y: 400))
        #expect(w.lastPlaced == nil)
        #expect(w.cameBackAt == 0)
    }
}
