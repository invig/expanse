import Testing
import AppKit
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "LayoutStore.swift") @testable import Expanse
@_private(sourceFile: "ManagedWindow.swift") @testable import Expanse

/// docs/regression/sizes.md. Chosen sizes, fitting to the screen and VM windows, on fake windows:
/// they have no Accessibility element, so nothing real is ever resized. Where the real app would
/// resize a window, the test sets the fake window's size itself.
@MainActor @Suite("SIZE: Window sizes", .serialized) struct SIZETests {

    // MARK: Helpers

    private static func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    private static func size(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }

    /// The laptop's view: the screen less the menu bar (1512 × 949).
    private static let laptopView = CGSize(width: 1512, height: 949)

    /// Pretend the display is `d`, as a display change would.
    private static func move(_ c: CanvasController, to d: TestDisplay) {
        c.displayOverride = (d.frame, d.usable)
        c.updateOverlayFrame()
    }

    /// The VM and remote-screen apps SIZE-07 names.
    private static let sizesItselfIDs = [
        "com.utmapp.UTM", "com.parallels.desktop.console", "com.vmware.fusion", "org.virtualbox.app.VirtualBoxVM",
        "com.github.cirruslabs.tart", "com.apple.ScreenSharing", "com.edovia.screens.5", "com.edovia.screens.mac",
        "com.moonlight-stream.Moonlight", "com.microsoft.rdc.macos", "com.microsoft.rdc.mac",
    ]

    // MARK: SIZE-01 Resizing a window yourself keeps the new size

    @Test("SIZE-01 Your resize becomes the window's chosen size") func size01a() {
        let w = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let c = TestCanvas.make(windows: [w])
        c.adoptSize(w, Self.size(900, 700), fromUser: true)
        #expect(w.canvasFrame.size == Self.size(900, 700), "the canvas picture takes the new size at once")
        #expect(w.preferredSize == Self.size(900, 700))
        #expect(c.fittedSize(w, for: c.viewSize) == Self.size(900, 700), "kept when the layout is fitted to this screen")
    }

    @Test("SIZE-01 Resizes that aren't yours don't change the chosen size") func size01b() {
        let w = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let c = TestCanvas.make(windows: [w])
        c.adoptSize(w, Self.size(900, 700))
        #expect(w.canvasFrame.size == Self.size(900, 700))
        #expect(w.preferredSize == Self.size(600, 400))
    }

    @Test("SIZE-01 The chosen size is saved (pw/ph) for a relaunch") func size01c() {
        let w = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let c = TestCanvas.make(windows: [w])
        c.adoptSize(w, Self.size(900, 700), fromUser: true)
        c.hasSynced = true
        c.save()
        let saved = LayoutStore.load()?.windows.first
        #expect(saved?.pw == 900 && saved?.ph == 700)
        #expect(saved?.w == 900 && saved?.h == 700)
    }

    // MARK: SIZE-02 Windows shrink to fit a smaller screen and grow back

    @Test("SIZE-02 cap fits a size as is, else the screen less 32pt") func size02a() {
        let view = Self.laptopView
        #expect(CanvasController.cap(Self.size(2000, 1200), to: view) == Self.size(1480, 917))
        #expect(CanvasController.cap(Self.size(800, 600), to: view) == Self.size(800, 600))
        #expect(CanvasController.cap(Self.size(2000, 600), to: view) == Self.size(1480, 600), "a direction that fits keeps its size")
        #expect(CanvasController.cap(Self.size(1000, 1200), to: view) == Self.size(1000, 917))
    }

    @Test("SIZE-02 The layout tightens on the laptop and comes back exactly") func size02b() {
        let chosen = [Self.r(0, 0, 2000, 1200), Self.r(2020, 0, 500, 600), Self.r(0, 1220, 600, 400)]
        let ws = chosen.enumerated().map { Fake.window(id: CGWindowID($0.offset + 1), canvas: $0.element) }
        let c = TestCanvas.make(display: .external, windows: ws)
        for (w, f) in zip(ws, chosen) { w.home = f.origin }
        c.fitLayoutToScreen(tidy: false, rederiving: [])
        #expect(ws.map(\.canvasFrame) == chosen)
        // The smaller screen: the big window is shrunk (by the real fit; here, by hand).
        Self.move(c, to: .laptop)
        for w in ws { w.canvasFrame.size = c.fittedSize(w, for: c.viewSize) }
        #expect(ws[0].canvasFrame.size == Self.size(1480, 917), "the screen less 16pt all round")
        c.fitLayoutToScreen(tidy: false, rederiving: [])
        #expect(ws[1].canvasFrame.minX - ws[0].canvasFrame.maxX == 20, "the layout tightens around it")
        #expect(ws[2].canvasFrame.minY - ws[0].canvasFrame.maxY == 20)
        // Back to the big screen: chosen sizes, and the layout exactly as it was.
        Self.move(c, to: .external)
        for w in ws { w.canvasFrame.size = c.fittedSize(w, for: c.viewSize) }
        c.fitLayoutToScreen(tidy: false, rederiving: [])
        #expect(ws.map(\.canvasFrame) == chosen)
    }

    // MARK: SIZE-03 Window sizes survive quitting and relaunching Expanse

    @Test("SIZE-03 w/h (and pw/ph) survive a layout save and load") func size03() {
        Env.isolate()
        let entry = SavedLayout.Window(bundleID: "com.apple.TextEdit", appName: "TextEdit", title: "", x: 100, y: 50,
                                       w: 1100, h: 800, hx: 100, hy: 50, pw: 1100, ph: 800,
                                       ox: 40, oy: 60, ow: 600, oh: 400, id: 7, pid: 123, away: nil)
        LayoutStore.save(SavedLayout.with([entry]))
        let loaded = LayoutStore.load()?.windows.first
        #expect(loaded?.w == 1100 && loaded?.h == 800, "the canvas size to restore at launch")
        #expect(loaded?.pw == 1100 && loaded?.ph == 800)
        #expect(loaded?.ow == 600 && loaded?.oh == 400, "the macOS size to go back to on quit")
    }

    // MARK: SIZE-05 After a display change, windows get their chosen sizes back

    @Test("SIZE-05 Every window (parked too) gets its chosen size, capped at the screen") func size05() {
        let big = Fake.window(id: 1, canvas: Self.r(0, 0, 2000, 1300))
        let parked = Fake.window(id: 2, canvas: Self.r(5000, 0, 1600, 800))
        parked.parked = true
        let small = Fake.window(id: 3, canvas: Self.r(0, 1400, 700, 500))
        let ws = [big, parked, small]
        let c = TestCanvas.make(display: .external, windows: ws)
        Self.move(c, to: .laptop)
        #expect(ws.map { c.fittedSize($0, for: c.viewSize) } == [Self.size(1480, 917), Self.size(1480, 800), Self.size(700, 500)])
        // macOS squeezed them for the small screen; that isn't a size you chose.
        for w in ws { c.adoptSize(w, c.fittedSize(w, for: c.viewSize)) }
        Self.move(c, to: .external)
        #expect(ws.map { c.fittedSize($0, for: c.viewSize) } == [Self.size(2000, 1300), Self.size(1600, 800), Self.size(700, 500)],
                "back on the big display: exactly the chosen sizes")
    }

    // MARK: SIZE-06 Only a size you choose becomes a window's size

    @Test("SIZE-06 Only your resize becomes the chosen size") func size06() {
        let w = Fake.window(id: 1, bundleID: "com.google.Chrome", canvas: Self.r(0, 0, 1600, 1000))
        let c = TestCanvas.make(display: .external, windows: [w])
        // Smaller screen: Expanse fits it, and Chromium catches up in steps.
        Self.move(c, to: .laptop)
        let fitted = c.fittedSize(w, for: c.viewSize)
        w.lastSized = fitted
        c.adoptSize(w, Self.size(1550, 960))
        c.adoptSize(w, fitted, fromUser: true)   // Expanse's own size coming back, even right after a click
        #expect(w.preferredSize == Self.size(1600, 1000))
        // Back: the chosen size.
        Self.move(c, to: .external)
        #expect(c.fittedSize(w, for: c.viewSize) == Self.size(1600, 1000), "1: back at 1600×1000")
        // Your drag makes the new size.
        c.adoptSize(w, Self.size(1400, 900), fromUser: true)
        #expect(w.preferredSize == Self.size(1400, 900))
        Self.move(c, to: .laptop)
        c.adoptSize(w, c.fittedSize(w, for: c.viewSize))
        Self.move(c, to: .external)
        #expect(c.fittedSize(w, for: c.viewSize) == Self.size(1400, 900), "2: back at 1400×900")
    }

    @Test("SIZE-06 macOS moving windows during a display change isn't you") func size06b() {
        let w = Fake.window(id: 1, canvas: Self.r(0, 0, 1600, 1000))
        let c = TestCanvas.make(windows: [w])
        c.suspendTracking = true
        c.adoptSize(w, Self.size(1400, 900), fromUser: true)
        #expect(w.preferredSize == Self.size(1600, 1000))
        #expect(w.canvasFrame.size == Self.size(1400, 900))
    }

    // MARK: SIZE-07 VM and remote-screen windows keep the size their app picks

    @Test("SIZE-07 sizesItself for VM and remote-screen apps only") func size07a() {
        for id in Self.sizesItselfIDs {
            #expect(Fake.window(id: 1, bundleID: id, canvas: Self.r(0, 0, 800, 600)).sizesItself, "\(id)")
        }
        #expect(!Fake.window(id: 1, bundleID: "com.apple.TextEdit", canvas: Self.r(0, 0, 800, 600)).sizesItself)
        #expect(!Fake.window(id: 1, bundleID: "com.google.Chrome", canvas: Self.r(0, 0, 800, 600)).sizesItself)
    }

    @Test("SIZE-07 Expanse never resizes a VM window, and takes the size its app picks") func size07b() {
        let vm = Fake.window(id: 1, bundleID: "com.utmapp.UTM", appName: "UTM", canvas: Self.r(0, 0, 1920, 1200))
        let c = TestCanvas.make(display: .laptop, windows: [vm])
        #expect(c.fittedSize(vm, for: c.viewSize) == Self.size(1920, 1200), "kept on the small screen")
        #expect(c.homeSize(vm) == Self.size(1920, 1200))
        // The guest's resolution changes: its app resizes the window, and that's its size now.
        c.adoptSize(vm, Self.size(1280, 800))
        #expect(vm.preferredSize == Self.size(1280, 800))
        #expect(!c.isDerived, "never counts as shrunk")
        // Tidy Up keeps it.
        c.fitLayoutToScreen(tidy: true)
        #expect(vm.canvasFrame.size == Self.size(1280, 800))
    }

    // MARK: SIZE-08 Apps that size in steps don't make the layout count as shrunk

    @Test("SIZE-08 Within 32pt of the chosen size isn't shrunk (isDerived)") func size08a() {
        #expect(CanvasController.appRounding == 32)
        let w = Fake.window(id: 1, bundleID: "com.apple.Terminal", canvas: Self.r(0, 0, 800, 600))
        let c = TestCanvas.make(windows: [w])
        w.canvasFrame.size = Self.size(785, 590)   // Terminal rounds to character cells
        #expect(!c.isDerived)
        w.canvasFrame.size = Self.size(768, 568)   // exactly 32 short
        #expect(!c.isDerived)
        w.canvasFrame.size = Self.size(760, 600)   // 40 short: shrunk for a smaller screen
        #expect(c.isDerived)
        // A VM window smaller than its old size doesn't count.
        let vm = Fake.window(id: 2, bundleID: "com.utmapp.UTM", canvas: Self.r(0, 700, 1600, 1000))
        vm.canvasFrame.size = Self.size(1024, 768)
        c.windows = [vm]
        #expect(!c.isDerived)
    }

    @Test("SIZE-08 A window a little short of its size doesn't push its neighbours") func size08b() {
        let term = Fake.window(id: 1, bundleID: "com.apple.Terminal", canvas: Self.r(0, 0, 800, 600))
        let next = Fake.window(id: 2, canvas: Self.r(820, 0, 400, 300))
        let below = Fake.window(id: 3, canvas: Self.r(0, 620, 400, 300))
        let c = TestCanvas.make(windows: [term, next, below])
        for w in c.windows { w.home = w.canvasFrame.origin }
        c.fitLayoutToScreen(tidy: false)   // fitted to this screen once already
        term.canvasFrame.size = Self.size(785, 590)
        c.fitLayoutToScreen(tidy: true)
        c.fitLayoutToScreen(tidy: true)
        #expect(next.canvasFrame.origin == CGPoint(x: 820, y: 0) && below.canvasFrame.origin == CGPoint(x: 0, y: 620))
        #expect(!c.isDerived)
    }

    // MARK: SIZE-09 A window fitted after a display change doesn't shrink when you focus it

    @Test("SIZE-09 Display-change fitting and focus fitting use the same 16pt margin") func size09() {
        #expect(CanvasController.screenMargin == 16)
        let w = Fake.window(id: 1, canvas: Self.r(0, 0, 2000, 1200))
        let c = TestCanvas.make(display: .external, windows: [w])
        Self.move(c, to: .laptop)
        // After the display change (fitLayoutToScreen fits to cap of the chosen size).
        let fitted = c.fittedSize(w, for: c.viewSize)
        #expect(fitted == Self.size(c.viewSize.width - 32, c.viewSize.height - 32))
        w.canvasFrame.size = fitted
        // Focusing it (fitToScreen) asks for cap of the chosen size too: the size it already has.
        let onFocus = CanvasController.cap(w.preferredSize, to: c.viewSize)
        #expect(onFocus == w.canvasFrame.size, "no resize on focus")
    }

    // MARK: SIZE-10 A VM window keeps its spot when the VM changes resolution

    @Test("SIZE-10 A VM's own resize keeps moves from being followed for 2s (logic)") func size10() {
        let vm = Fake.window(id: 1, bundleID: "com.utmapp.UTM", appName: "UTM", canvas: Self.r(0, 0, 1024, 768))
        let other = Fake.window(id: 2, canvas: Self.r(1100, 0, 800, 600))
        let c = TestCanvas.make(windows: [vm, other])
        guard NSEvent.pressedMouseButtons & 1 == 0 else { return }   // a drag is followed as usual
        #expect(c.resizedItself(vm, to: Self.size(1280, 800)), "it resized itself: its move is put back")
        #expect(c.resizedItself(vm, to: vm.canvasFrame.size), "a move just after, too")
        vm.resizedItselfAt = CACurrentMediaTime() - 3
        #expect(!c.resizedItself(vm, to: vm.canvasFrame.size), "later moves are followed")
        #expect(!c.resizedItself(other, to: Self.size(1000, 700)), "only VM and remote-screen windows")
    }

    // MARK: SIZE-11 A size set with macOS's Fill sticks

    @Test("SIZE-11 A Fill counted as yours keeps filling the screen (logic)") func size11() {
        let w = Fake.window(id: 1, bundleID: "com.apple.TextEdit", canvas: Self.r(100, 100, 700, 500))
        let c = TestCanvas.make(windows: [w])
        let fill = c.viewSize
        c.adoptSize(w, fill, fromUser: true)   // a resize just after your click in TextEdit
        #expect(w.preferredSize == fill)
        #expect(c.fittedSize(w, for: c.viewSize) == fill, "hops, Tidy Up and fits keep it")
        c.fitLayoutToScreen(tidy: true)
        #expect(w.canvasFrame.size == fill)
    }

    // MARK: SIZE-12 A size set with Moom or a keyboard shortcut sticks

    @Test("SIZE-12 A shortcut's resize counted as yours sticks (logic)") func size12() {
        let w = Fake.window(id: 1, bundleID: "com.apple.TextEdit", canvas: Self.r(100, 100, 700, 500))
        let c = TestCanvas.make(windows: [w])
        let half = Self.size(c.viewSize.width / 2, c.viewSize.height)
        c.adoptSize(w, half, fromUser: true)
        #expect(w.preferredSize == half)
        #expect(c.fittedSize(w, for: c.viewSize) == half)
    }

    // MARK: SIZE-13 A window sized to fill the screen keeps filling it

    @Test("SIZE-13 cap leaves a size up to the view's alone; bigger is the view less 32") func size13() {
        let view = Self.laptopView
        #expect(CanvasController.cap(view, to: view) == view, "filling the screen keeps filling it")
        #expect(CanvasController.cap(Self.size(view.width, 500), to: view) == Self.size(view.width, 500))
        #expect(CanvasController.cap(Self.size(view.width + 1, view.height), to: view) == Self.size(view.width - 32, view.height))
        #expect(CanvasController.cap(Self.size(900, view.height + 1), to: view) == Self.size(900, view.height - 32))
        #expect(CanvasController.cap(Self.size(2560, 1415), to: view) == Self.size(1480, 917))
    }

    // MARK: SIZE-14 A resize you didn't make doesn't change the size you chose

    @Test("SIZE-14 A script's resize isn't your size; the next fit puts yours back (logic)") func size14() {
        let w = Fake.window(id: 1, bundleID: "com.apple.TextEdit", canvas: Self.r(100, 100, 900, 700))
        let c = TestCanvas.make(windows: [w])
        c.adoptSize(w, Self.size(600, 400))   // TextEdit wasn't in front: not yours
        #expect(w.canvasFrame.size == Self.size(600, 400))
        #expect(w.preferredSize == Self.size(900, 700))
        #expect(CanvasController.cap(w.preferredSize, to: c.viewSize) == Self.size(900, 700), "gliding to it asks for your size")
        // An app catching up with Expanse's own resize isn't yours either, even right after input.
        w.lastSized = Self.size(900, 700)
        c.adoptSize(w, Self.size(901, 700), fromUser: true)
        #expect(w.preferredSize == Self.size(900, 700))
    }

    // MARK: SIZE-20 Fill grows a window from its top-left on the canvas

    @Test("SIZE-20 What macOS's Fill fills: the usable area, or a little less all round") func size20a() {
        let u = Self.r(0, 33, 1512, 949)   // the laptop, no Dock shown
        #expect(CanvasController.fills(u, usable: u))
        #expect(CanvasController.fills(u.insetBy(dx: 8, dy: 8), usable: u), "with margins between tiled windows")
        #expect(!CanvasController.fills(Self.r(0, 33, 756, 949), usable: u), "a half")
        #expect(!CanvasController.fills(Self.r(0, 0, 1512, 982), usable: u), "taller than the usable area")
        #expect(!CanvasController.fills(Self.r(100, 33, 1512, 949), usable: u), "Fill's size somewhere else")
        #expect(CanvasController.fills(Self.size(1512, 949), usable: u))
        let docked = Self.r(0, 33, 1512, 879)   // a Dock that's always shown
        #expect(CanvasController.fills(docked, usable: docked))
        #expect(!CanvasController.fills(u, usable: docked))
    }

    /// A window at (300, 200) on the canvas, one above and to its left, one to its right; the view
    /// at the canvas's origin, so the real windows are 33 lower (the menu bar).
    private static func fillScene(yours: Bool) -> (CanvasController, w: ManagedWindow, aboveLeft: ManagedWindow, right: ManagedWindow) {
        let w = Fake.window(id: 2001, canvas: Self.r(300, 200, 600, 400), real: Self.r(300, 233, 600, 400))
        w.lastPlaced = CGPoint(x: 300, y: 233)
        let aboveLeft = Fake.window(id: 2002, canvas: Self.r(-400, -300, 600, 400))
        let right = Fake.window(id: 2003, canvas: Self.r(1000, 200, 600, 400))
        let c = TestCanvas.make(windows: [aboveLeft, right, w])
        c.resizeIsYours = { _ in yours }
        c.gliding = true   // (no real windows to move)
        return (c, w, aboveLeft, right)
    }

    private static func change(_ c: CanvasController, _ w: ManagedWindow, _ frame: CGRect) {
        c.realWindowChanged(w, AXUIElementCreateApplication(w.pid), userDragging: false,
                            size: frame.size, position: frame.origin, inFullScreenSpace: false)
    }

    @Test("SIZE-20 Fill keeps the window's top-left on the canvas; Return to Previous Size puts the view back (logic)")
    func size20b() {
        let (c, w, aboveLeft, right) = Self.fillScene(yours: true)
        defer { c.isPaused = true }
        // Fill, which macOS animates: each step is reported, the last fills the usable area.
        Self.change(c, w, Self.r(150, 120, 1000, 700))
        Self.change(c, w, Self.r(10, 40, 1450, 920))
        Self.change(c, w, Self.r(0, 33, 1512, 949))
        #expect(w.canvasFrame == Self.r(300, 200, 1512, 949), "grown right and down from where it was")
        #expect(w.preferredSize == Self.size(1512, 949))
        #expect(c.camera.origin == CGPoint(x: 300, y: 200), "the view moved to where the window fills the screen")
        #expect(!aboveLeft.canvasFrame.intersects(w.canvasFrame))
        #expect(right.canvasFrame.intersects(w.canvasFrame), "the one to the right is covered, as at 100%")
        // Later, Return to Previous Size: macOS animates it back to where it was on screen.
        w.changing = nil
        Self.change(c, w, Self.r(100, 100, 1100, 800))
        Self.change(c, w, Self.r(300, 233, 600, 400))
        #expect(w.canvasFrame == Self.r(300, 200, 600, 400))
        #expect(c.camera.origin == .zero, "everything is where it was before the Fill")
    }

    @Test("SIZE-20 A Fill you didn't make is followed as before (logic)") func size20c() {
        let (c, w, _, _) = Self.fillScene(yours: false)
        defer { c.isPaused = true }
        Self.change(c, w, Self.r(0, 33, 1512, 949))
        #expect(w.canvasFrame == Self.r(0, 0, 1512, 949))
        #expect(c.camera.origin == .zero)
        #expect(w.preferredSize == Self.size(600, 400))
    }
}
