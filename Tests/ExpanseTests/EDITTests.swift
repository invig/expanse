import Testing
import AppKit
import Carbon.HIToolbox
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "CanvasView.swift") @testable import Expanse
@_private(sourceFile: "ManagedWindow.swift") @testable import Expanse

/// docs/regression/arranging.md. Snapping, Tidy Up and the close button, on fake windows. The
/// "(logic)" tests drive CanvasView with made-up mouse and key events handed straight to it
/// (nothing is posted), and never let go of a click that would dive into a window.
@MainActor @Suite("EDIT: Arranging windows on the canvas", .serialized) struct EDITTests {

    // MARK: Helpers

    private static func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    /// A canvas with these windows, the camera at `origin` and `scale`. By default the middle of
    /// the screen is far away from them, so the screen-centre snap stays out of the way.
    private static func canvas(_ ws: [ManagedWindow], scale: CGFloat = 1,
                               origin: CGPoint = CGPoint(x: -20_000, y: -20_000), active: Bool = false) -> CanvasController {
        let c = TestCanvas.make(windows: ws)
        c.camera = Camera(origin: origin, scale: scale)
        if active { c.isActive = true }
        return c
    }

    /// Zoomed out to 50% with the canvas open, the view's top left at canvas (-100, -100): a canvas
    /// point p is at view point (p + 100) / 2. The screen's middle is canvas (1412, 849).
    private static func zoomedOut(_ ws: [ManagedWindow]) -> CanvasController {
        let c = canvas(ws, scale: 0.5, origin: CGPoint(x: -100, y: -100), active: true)
        ws.forEach { c.view.addNode($0.node) }
        c.view.render()
        return c
    }

    /// View point (top-left origin) for a canvas point.
    private static func view(_ c: CanvasController, _ p: CGPoint) -> CGPoint { c.camera.toView(p) }

    /// A mouse event at view point `p` (top-left origin), handed to the view directly.
    private static func mouse(_ type: NSEvent.EventType, _ p: CGPoint, _ c: CanvasController,
                              _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: p.x, y: c.view.bounds.height - p.y), modifierFlags: flags,
                           timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private static func key(_ code: Int, _ flags: NSEvent.ModifierFlags = [], _ chars: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false,
                         keyCode: UInt16(code))!
    }

    /// What `body` asks to close (CanvasController.close), each call's window IDs; nothing closes.
    private static func closing(_ body: () -> Void) -> [[CGWindowID]] {
        var calls: [[CGWindowID]] = []
        CanvasController.closeOverride = { calls.append($0.map(\.id)) }
        defer { CanvasController.closeOverride = nil }
        body()
        return calls
    }

    /// Gaps between frames side by side that share rows (`a` left of `b`).
    private static func gapX(_ a: CGRect, _ b: CGRect) -> CGFloat { b.minX - a.maxX }
    private static func gapY(_ a: CGRect, _ b: CGRect) -> CGFloat { b.minY - a.maxY }

    private static func overlaps(_ frames: [CGRect]) -> Bool {
        for i in frames.indices { for j in frames.indices where j > i && frames[i].intersects(frames[j]) { return true } }
        return false
    }

    // MARK: EDIT-01 Drag a window on the canvas to move it

    @Test("EDIT-01 Drag a window on the canvas to move it (logic)") func edit01() {
        let w = Fake.window(id: 1, canvas: Self.r(0, 0, 400, 300))
        let c = Self.zoomedOut([w])
        let start = Self.view(c, CGPoint(x: 200, y: 150))
        c.view.mouseDown(with: Self.mouse(.leftMouseDown, start, c))
        // 150 by 100 on screen at 50% is 300 by 200 on the canvas.
        let to = CGPoint(x: start.x + 150, y: start.y + 100)
        c.view.mouseDragged(with: Self.mouse(.leftMouseDragged, to, c))
        #expect(w.canvasFrame == Self.r(300, 200, 400, 300), "the picture follows the pointer")
        c.view.mouseUp(with: Self.mouse(.leftMouseUp, to, c))
        #expect(w.canvasFrame == Self.r(300, 200, 400, 300), "it stays where dropped")
        #expect(w.lastPlaced == nil, "the real window isn't moved while zoomed out")
        #expect(w.home == CGPoint(x: 300, y: 200), "its new spot is its home spot straight away")
    }

    // MARK: EDIT-02 A tiny drag still counts as a click

    @Test("EDIT-02 A tiny drag still counts as a click (logic)") func edit02() {
        let w = Fake.window(id: 1, canvas: Self.r(0, 0, 400, 300))
        let c = Self.zoomedOut([w])
        let start = Self.view(c, CGPoint(x: 200, y: 150))
        c.view.mouseDown(with: Self.mouse(.leftMouseDown, start, c))
        c.view.mouseDragged(with: Self.mouse(.leftMouseDragged, CGPoint(x: start.x + 2, y: start.y + 1), c))
        #expect(w.canvasFrame == Self.r(0, 0, 400, 300), "under 3 screen points the window doesn't move")
        #expect(!c.view.dragged, "letting go now is a click (a dive), not a drag")
        // (Not letting go: a click dives into the window, which needs a real Mac.)
        c.view.mouseDragged(with: Self.mouse(.leftMouseDragged, CGPoint(x: start.x + 6, y: start.y), c))
        #expect(c.view.dragged)
        #expect(w.canvasFrame == Self.r(12, 0, 400, 300), "further, it's a drag")
    }

    // MARK: EDIT-03 Dragged windows snap into place with guides

    @Test("EDIT-03 Snaps 20pt beside a window (the standard gap)") func edit03a() {
        let a = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let c = Self.canvas([a])
        let (right, _) = c.snap(Self.r(627, 300, 400, 300), excluding: [2])
        #expect(right == Self.r(620, 300, 400, 300))
        let (left, _) = c.snap(Self.r(-427, 300, 400, 300), excluding: [2])
        #expect(left.maxX == -20)
        #expect(CanvasController.gap == 20)
    }

    @Test("EDIT-03 Snaps flush with a window's edge, with a guide spanning both") func edit03b() {
        let a = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let c = Self.canvas([a])
        let (f, lines) = c.snap(Self.r(604, 120, 400, 300), excluding: [2])
        #expect(f == Self.r(600, 120, 400, 300))
        #expect(lines.count == 1)
        #expect(lines.first.map { $0.0 == CGPoint(x: 600, y: 0) && $0.1 == CGPoint(x: 600, y: 420) } == true,
                "a vertical guide at x 600 from A's top to B's bottom")
    }

    @Test("EDIT-03 Tops and bottoms line up, with a guide line") func edit03c() {
        let a = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let c = Self.canvas([a])
        let (top, topLines) = c.snap(Self.r(620, 6, 400, 300), excluding: [2])
        #expect(top == Self.r(620, 0, 400, 300))
        #expect(topLines.count == 1)
        #expect(topLines.first.map { $0.0 == CGPoint(x: 0, y: 0) && $0.1 == CGPoint(x: 1020, y: 0) } == true)
        let (bottom, bottomLines) = c.snap(Self.r(620, 105, 400, 300), excluding: [2])
        #expect(bottom.maxY == 400)
        #expect(bottomLines.first.map { $0.0.y == 400 && $0.1.y == 400 } == true)
    }

    @Test("EDIT-03 Centres snap at half the reach, and an edge wins a tie") func edit03d() {
        let a = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let c = Self.canvas([a])
        // 3pt off A's centre line (within 5): snaps, with a guide through both centres.
        let (near, lines) = c.snap(Self.r(620, 53, 400, 300), excluding: [2])
        #expect(near.midY == 200)
        #expect(lines.first.map { $0.0.y == 200 && $0.1.y == 200 } == true)
        // 7pt off: within an edge's reach (10) but not a centre's (5).
        let (far, _) = c.snap(Self.r(620, 57, 400, 300), excluding: [2])
        #expect(far.minY == 57)
        // B's top 3pt below A's top and its centre 3pt above C's: the edge wins.
        let other = Fake.window(id: 3, canvas: Self.r(-2000, 56, 600, 200))
        let c2 = Self.canvas([a, other])
        let (tie, _) = c2.snap(Self.r(620, 3, 400, 300), excluding: [2])
        #expect(tie.minY == 0, "lined up with A's top, not centred on C")
    }

    @Test("EDIT-03 Near the middle of the screen it snaps dead centre") func edit03e() {
        let c = Self.canvas([], origin: .zero)
        let mid = c.camera.center(in: c.viewport.size)
        let (f, _) = c.snap(Self.r(mid.x - 204, mid.y - 154, 400, 300), excluding: [2])
        #expect(f.midX == mid.x && f.midY == mid.y)
    }

    @Test("EDIT-03 Above a row of windows it can centre on the whole row") func edit03f() {
        let r1 = Fake.window(id: 1, canvas: Self.r(0, 500, 400, 300))
        let r2 = Fake.window(id: 2, canvas: Self.r(420, 500, 400, 300))
        let c = Self.canvas([r1, r2])
        let (f, lines) = c.snap(Self.r(262, 100, 300, 300), excluding: [3])
        #expect(f.midX == 410, "the row's middle, not either window's")
        #expect(lines.count == 1)
        #expect(lines.first.map { $0.0 == CGPoint(x: 410, y: 100) && $0.1 == CGPoint(x: 410, y: 800) } == true,
                "the guide spans the window and the row")
    }

    // MARK: EDIT-04 Hold ⌘ while dragging to skip snapping

    @Test("EDIT-04 Hold ⌘ while dragging to skip snapping (logic)") func edit04() {
        let a = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let b = Fake.window(id: 2, canvas: Self.r(700, 450, 400, 300))
        let c = Self.zoomedOut([a, b])
        let start = Self.view(c, CGPoint(x: 900, y: 600))
        // To where B's top is 8pt below A's: within reach (20 canvas points at 50%).
        let to = CGPoint(x: start.x, y: start.y - 221)
        c.view.mouseDown(with: Self.mouse(.leftMouseDown, start, c))
        c.view.mouseDragged(with: Self.mouse(.leftMouseDragged, to, c, .command))
        #expect(b.canvasFrame.origin == CGPoint(x: 700, y: 8), "with ⌘ held, B follows the pointer exactly")
        #expect(c.view.guides.path == nil, "and there are no guide lines")
        c.view.mouseDragged(with: Self.mouse(.leftMouseDragged, to, c))
        #expect(b.canvasFrame.origin == CGPoint(x: 700, y: 0), "⌘ let go: snapping is back from the next movement")
        #expect(c.view.guides.path != nil)
        c.view.mouseUp(with: Self.mouse(.leftMouseUp, to, c))
        #expect(c.view.guides.path == nil, "guides vanish when you let go")
    }

    // MARK: EDIT-05 Clicking or dragging a window brings it to the front of the canvas

    @Test("EDIT-05 bringToFront puts the window last in windows and its picture on top") func edit05a() {
        let a = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let b = Fake.window(id: 2, canvas: Self.r(300, 200, 600, 400))
        let c = Self.canvas([b, a])   // back to front: A on top
        [b, a].forEach { c.view.addNode($0.node) }
        c.bringToFront(b)
        #expect(c.windows.map(\.id) == [1, 2])
        #expect(b.node.container.superlayer?.sublayers?.last === b.node.container)
        c.bringToFront(b)
        #expect(c.windows.map(\.id) == [1, 2], "already in front: nothing changes")
    }

    @Test("EDIT-05 Pressing on the window underneath brings it to the front") func edit05b() {
        let a = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let b = Fake.window(id: 2, canvas: Self.r(300, 200, 600, 400))
        let c = Self.zoomedOut([b, a])
        c.view.mouseDown(with: Self.mouse(.leftMouseDown, Self.view(c, CGPoint(x: 800, y: 500)), c))
        #expect(c.windows.last === b, "on top as soon as you press")
        #expect(b.node.container.superlayer?.sublayers?.last === b.node.container)
        let to = Self.view(c, CGPoint(x: 830, y: 530))
        c.view.mouseDragged(with: Self.mouse(.leftMouseDragged, to, c))
        c.view.mouseUp(with: Self.mouse(.leftMouseUp, to, c))
        #expect(c.windows.last === b, "and stays on top")
    }

    // MARK: EDIT-06 Hover × closes a window

    @Test("EDIT-06 The × hit area is the window's top-right corner") func edit06a() {
        let r = Self.r(100, 50, 400, 300)
        let close = WindowNode.closeRect(in: r)
        #expect(close == Self.r(464, 60, 26, 26))
        #expect(close.contains(CGPoint(x: 477, y: 73)))
        #expect(!close.contains(CGPoint(x: 300, y: 200)), "the rest of the window isn't the button")
        #expect(r.contains(close))
    }

    @Test("EDIT-06 Clicking × closes the window; clicking elsewhere doesn't (logic)") func edit06b() {
        let w = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        let c = Self.zoomedOut([w])
        c.view.hovered = w
        c.view.render()
        #expect(w.node.closeVisible)
        let onScreen = c.camera.toView(w.canvasFrame)
        let x = WindowNode.closeRect(in: onScreen)
        let closed = Self.closing { c.view.mouseDown(with: Self.mouse(.leftMouseDown, CGPoint(x: x.midX, y: x.midY), c)) }
        #expect(closed == [[1]])
        let elsewhere = Self.closing {
            c.view.mouseDown(with: Self.mouse(.leftMouseDown, CGPoint(x: onScreen.midX, y: onScreen.midY), c))
        }
        #expect(elsewhere.isEmpty)
    }

    // MARK: EDIT-07 No × on windows too small on screen

    @Test("EDIT-07 No × under 220 screen points wide") func edit07a() {
        #expect(WindowNode.closeMinWidth == 220)
        let narrow = WindowNode()
        narrow.place(canvasFrame: Self.r(0, 0, 219, 200))
        narrow.style(scale: 1, hovered: true, selected: false, showsClose: true, visible: true, screenRect: Self.r(0, 0, 219, 200))
        #expect(!narrow.closeVisible)
        let wide = WindowNode()
        wide.place(canvasFrame: Self.r(0, 0, 220, 200))
        wide.style(scale: 1, hovered: true, selected: false, showsClose: true, visible: true, screenRect: Self.r(0, 0, 220, 200))
        #expect(wide.closeVisible)
        // On screen size, not canvas size: 400 wide at 50% is 200 on screen.
        let zoomed = WindowNode()
        zoomed.place(canvasFrame: Self.r(0, 0, 400, 300))
        zoomed.style(scale: 0.5, hovered: true, selected: false, showsClose: true, visible: true, screenRect: Self.r(0, 0, 200, 150))
        #expect(!zoomed.closeVisible)
    }

    @Test("EDIT-07 A click where × would be dives in instead of closing") func edit07b() {
        let w = Fake.window(id: 1, canvas: Self.r(0, 0, 400, 300))   // 200 wide on screen
        let c = Self.zoomedOut([w])
        c.view.hovered = w
        c.view.render()
        #expect(!w.node.closeVisible)
        let x = WindowNode.closeRect(in: c.camera.toView(w.canvasFrame))
        let closed = Self.closing { c.view.mouseDown(with: Self.mouse(.leftMouseDown, CGPoint(x: x.midX, y: x.midY), c)) }
        #expect(closed.isEmpty)
        guard case .window(let pressed, _, _) = c.view.drag else { Issue.record("not a press on the window"); return }
        #expect(pressed === w && !c.view.dragged, "letting go dives into it")
    }

    // MARK: EDIT-08 ⌘W closes the selection, otherwise the window under the pointer

    @Test("EDIT-08 ⌘W closes the selection, otherwise the hovered window") func edit08() {
        let ws = (1...4).map { Fake.window(id: CGWindowID($0), canvas: Self.r(CGFloat($0 - 1) * 700, 0, 600, 400)) }
        let c = Self.zoomedOut(ws)
        // Two selected, a third hovered: × only on the hovered one, and it closes just that one.
        c.view.selected = [1, 2]
        c.view.hovered = ws[2]
        c.view.render()
        #expect(ws.map(\.node.closeVisible) == [false, false, true, false])
        #expect(Self.closing { c.view.close(ws[2]) } == [[3]])
        #expect(c.view.selected == [1, 2])
        // ⌘W: the selection wins over the hovered window.
        let cmdW = Self.key(kVK_ANSI_W, .command, "w")
        #expect(Self.closing { c.view.keyDown(with: cmdW) } == [[1, 2]])
        #expect(c.view.selected.isEmpty)
        // No selection: the hovered window.
        c.view.hovered = ws[3]
        #expect(Self.closing { c.view.keyDown(with: cmdW) } == [[4]])
        // A selection of one is still the selection.
        c.view.selected = [1]
        #expect(Self.closing { c.view.keyDown(with: cmdW) } == [[1]])
    }

    // MARK: EDIT-10 Drag on empty canvas to select windows

    @Test("EDIT-10 Drag on empty canvas to select windows (logic)") func edit10() {
        let frames = [Self.r(0, 0, 400, 300), Self.r(500, 0, 400, 300), Self.r(1000, 0, 400, 300),
                      Self.r(0, 500, 400, 300), Self.r(500, 500, 400, 300)]
        let ws = frames.enumerated().map { Fake.window(id: CGWindowID($0.offset + 1), canvas: $0.element) }
        let c = Self.zoomedOut(ws)
        let start = Self.view(c, CGPoint(x: -50, y: -50)), end = Self.view(c, CGPoint(x: 1100, y: 100))
        c.view.mouseDown(with: Self.mouse(.leftMouseDown, start, c))
        c.view.mouseDragged(with: Self.mouse(.leftMouseDragged, end, c))
        #expect(c.view.marquee.path != nil, "a box follows the pointer")
        #expect(c.view.selected == [1, 2, 3], "every window it touches")
        #expect(ws.map(\.node.highlight.borderWidth) == [6, 6, 6, 0, 0], "a thick border (3pt on screen at 50%)")
        #expect(c.view.selectionBox.path != nil, "an outline round them all")
        c.view.mouseUp(with: Self.mouse(.leftMouseUp, end, c))
        #expect(c.view.marquee.path == nil)
        #expect(c.view.selected == [1, 2, 3], "the selection stays after you let go")
    }

    // MARK: EDIT-11 ⇧-click and ⇧-drag add to the selection

    @Test("EDIT-11 ⇧-click and ⇧-drag add to the selection (logic)") func edit11() {
        let frames = [Self.r(0, 0, 400, 300), Self.r(500, 0, 400, 300), Self.r(1000, 0, 400, 300),
                      Self.r(0, 500, 400, 300), Self.r(500, 500, 400, 300)]
        let ws = frames.enumerated().map { Fake.window(id: CGWindowID($0.offset + 1), canvas: $0.element) }
        let c = Self.zoomedOut(ws)
        c.view.selected = [1, 2]
        func click(_ p: CGPoint, _ flags: NSEvent.ModifierFlags) {
            let v = Self.view(c, p)
            c.view.mouseDown(with: Self.mouse(.leftMouseDown, v, c, flags))
            c.view.mouseUp(with: Self.mouse(.leftMouseUp, v, c, flags))
        }
        func box(_ from: CGPoint, _ to: CGPoint, _ flags: NSEvent.ModifierFlags) {
            c.view.mouseDown(with: Self.mouse(.leftMouseDown, Self.view(c, from), c, flags))
            c.view.mouseDragged(with: Self.mouse(.leftMouseDragged, Self.view(c, to), c, flags))
            c.view.mouseUp(with: Self.mouse(.leftMouseUp, Self.view(c, to), c, flags))
        }
        click(CGPoint(x: 1200, y: 150), .shift)
        #expect(c.view.selected == [1, 2, 3], "⇧-click adds")
        click(CGPoint(x: 1200, y: 150), .shift)
        #expect(c.view.selected == [1, 2], "⇧-click again removes")
        box(CGPoint(x: -50, y: 450), CGPoint(x: 1000, y: 600), .shift)
        #expect(c.view.selected == [1, 2, 4, 5], "⇧-drag adds to the selection")
        box(CGPoint(x: 950, y: -50), CGPoint(x: 1450, y: 100), [])
        #expect(c.view.selected == [3], "a box without ⇧ starts again")
    }

    // MARK: EDIT-12 ⌘A selects every window; Esc clears it, then leaves

    @Test("EDIT-12 ⌘A selects every window; Esc clears it (logic)") func edit12() {
        let ws = (1...3).map { Fake.window(id: CGWindowID($0), canvas: Self.r(CGFloat($0 - 1) * 500, 0, 400, 300)) }
        let c = Self.zoomedOut(ws)
        c.view.keyDown(with: Self.key(kVK_ANSI_A, .command, "a"))
        #expect(c.view.selected == [1, 2, 3])
        let camera = c.camera
        c.view.keyDown(with: Self.key(kVK_Escape, [], "\u{1b}"))
        #expect(c.view.selected.isEmpty)
        #expect(c.isActive && c.camera == camera, "the canvas stays zoomed out")
        // (A second Esc goes back to 100%, which moves real windows.)
    }

    // MARK: EDIT-13 Dragging a selected window moves the group, snapping as one block

    @Test("EDIT-13 The group's bounding box snaps as one block") func edit13a() {
        let s = [Self.r(0, 0, 300, 200), Self.r(320, 0, 300, 200), Self.r(0, 220, 300, 200)]
        let ws = s.enumerated().map { Fake.window(id: CGWindowID($0.offset + 1), canvas: $0.element) }
        let d = Fake.window(id: 4, canvas: Self.r(1000, 0, 400, 300))
        let c = Self.canvas(ws + [d])
        let bounds = s.dropFirst().reduce(s[0]) { $0.union($1) }
        let (f, lines) = c.snap(bounds.offsetBy(dx: 355, dy: 3), excluding: [1, 2, 3])
        #expect(f == Self.r(360, 0, 620, 420), "20pt from D, tops lined up with D's")
        #expect(lines.count == 1)
        #expect(lines.first.map { $0.0 == CGPoint(x: 360, y: 0) && $0.1 == CGPoint(x: 1400, y: 0) } == true)
    }

    @Test("EDIT-13 Dragging one selected window moves them all, snapped; ⌘ skips snapping") func edit13b() {
        let s = [Self.r(0, 0, 300, 200), Self.r(320, 0, 300, 200), Self.r(0, 220, 300, 200)]
        let ws = s.enumerated().map { Fake.window(id: CGWindowID($0.offset + 1), canvas: $0.element) }
        let d = Fake.window(id: 4, canvas: Self.r(1000, 0, 400, 300))
        let c = Self.zoomedOut(ws + [d])
        c.view.selected = [1, 2, 3]
        let start = Self.view(c, CGPoint(x: 150, y: 100))
        let to = CGPoint(x: start.x + 177.5, y: start.y + 1.5)   // 355, 3 on the canvas
        c.view.mouseDown(with: Self.mouse(.leftMouseDown, start, c))
        c.view.mouseDragged(with: Self.mouse(.leftMouseDragged, to, c))
        #expect(ws.map(\.canvasFrame) == s.map { $0.offsetBy(dx: 360, dy: 0) }, "together, snapped as a block")
        #expect(c.view.guides.path != nil)
        c.view.mouseDragged(with: Self.mouse(.leftMouseDragged, to, c, .command))
        #expect(ws.map(\.canvasFrame) == s.map { $0.offsetBy(dx: 355, dy: 3) }, "with ⌘: no snapping")
        c.view.mouseUp(with: Self.mouse(.leftMouseUp, to, c, .command))
        #expect(d.canvasFrame == Self.r(1000, 0, 400, 300))
        #expect(c.view.selected == [1, 2, 3])
    }

    // MARK: EDIT-15 Edges and the 20pt gap snap firmly; centres snap softly

    @Test("EDIT-15 Edges reach 10 screen points, centres 5, at any zoom") func edit15() {
        let a = Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400))
        for scale: CGFloat in [1, 0.5, 0.25] {
            let c = Self.canvas([a], scale: scale)
            let firm = 10 / scale, soft = 5 / scale
            // The gap: B's left edge just inside, then just outside the reach of 20pt right of A.
            #expect(c.snap(Self.r(620 + firm - 0.5, 300, 400, 300), excluding: [2]).0.minX == 620, "scale \(scale)")
            #expect(c.snap(Self.r(620 + firm + 0.5, 300, 400, 300), excluding: [2]).0.minX == 620 + firm + 0.5, "scale \(scale)")
            // Tops: within reach they line up. (B is 100 high, so no centre is near.)
            #expect(c.snap(Self.r(620, firm - 0.5, 400, 100), excluding: [2]).0.minY == 0, "scale \(scale)")
            #expect(c.snap(Self.r(620, firm + 0.5, 400, 100), excluding: [2]).0.minY == firm + 0.5, "scale \(scale)")
            // Centres: half the reach.
            #expect(c.snap(Self.r(620, 150 + soft - 0.5, 400, 100), excluding: [2]).0.midY == 200, "scale \(scale)")
            #expect(c.snap(Self.r(620, 150 + soft + 0.5, 400, 100), excluding: [2]).0.midY == 200 + soft + 0.5, "scale \(scale)")
        }
    }

    // MARK: EDIT-16 A window can centre on a whole row above or below

    @Test("EDIT-16 A window centres on a whole row below or above it") func edit16a() {
        let r1 = Fake.window(id: 1, canvas: Self.r(0, 500, 400, 300))
        let r2 = Fake.window(id: 2, canvas: Self.r(420, 500, 400, 300))
        let r3 = Fake.window(id: 3, canvas: Self.r(840, 500, 400, 300))
        let c = Self.canvas([r1, r2, r3])
        // Above the row (the row's middle is 620, which is also r2's: use two windows for that below).
        let (above, lines) = c.snap(Self.r(468, 100, 300, 300), excluding: [9])
        #expect(above.midX == 620)
        #expect(lines.first.map { $0.0.x == 620 && $0.0.y == 100 && $0.1.y == 800 } == true)
        // Below a row of two: the middle of the pair, which isn't either window's centre.
        let c2 = Self.canvas([r1, r2])
        let (below, belowLines) = c2.snap(Self.r(258, 900, 300, 300), excluding: [9])
        #expect(below.midX == 410)
        #expect(belowLines.first.map { $0.0 == CGPoint(x: 410, y: 500) && $0.1 == CGPoint(x: 410, y: 1200) } == true,
                "a guide spanning the row and the window")
    }

    @Test("EDIT-16 The same for a column to the left or right") func edit16b() {
        let c1 = Fake.window(id: 1, canvas: Self.r(0, 0, 400, 300))
        let c2 = Fake.window(id: 2, canvas: Self.r(0, 320, 400, 300))
        let c = Self.canvas([c1, c2])
        let (right, lines) = c.snap(Self.r(500, 162, 300, 300), excluding: [9])
        #expect(right.midY == 310, "the column's middle")
        #expect(lines.first.map { $0.0 == CGPoint(x: 0, y: 310) && $0.1 == CGPoint(x: 800, y: 310) } == true)
        let (left, _) = c.snap(Self.r(-400, 158, 300, 300), excluding: [9])
        #expect(left.midY == 310)
    }

    // MARK: EDIT-17 Tidy Up tidies each group where it is

    @Test("EDIT-17 Tidy Up tidies each group where it is") func edit17() {
        let groupA = [Self.r(0, 0, 400, 300), Self.r(300, 0, 400, 300), Self.r(720, 0, 400, 300)]
        let groupB = [Self.r(1600, 0, 400, 300), Self.r(2020, 0, 400, 300)]
        var frames = groupA + groupB
        CanvasController.tidyUp(&frames)
        let a = Array(frames[0..<3]), b = Array(frames[3...])
        #expect(!Self.overlaps(a), "the overlap inside A is pushed apart")
        #expect(Self.gapX(a[0], a[1]) == 20 && Self.gapX(a[1], a[2]) == 20, "gaps become 20pt")
        #expect(a[0] == groupA[0], "A stays where it is")
        #expect(b == groupB, "group B doesn't move")
    }

    @Test("EDIT-17 Groups more than 240pt apart aren't pulled together") func edit17b() {
        // Two groups 300pt apart: closer than they'd be after a whole-canvas tidy, further than 240.
        let frames0 = [Self.r(0, 0, 400, 300), Self.r(430, 0, 400, 300),
                       Self.r(1130, 40, 400, 300), Self.r(1580, 40, 400, 300)]
        var frames = frames0
        CanvasController.tidyUp(&frames)
        #expect(frames[1].minX == 420)
        #expect(frames[2] == frames0[2], "B's first window stays put")
        #expect(frames[3].minX == 1550 && frames[3].minY == 40, "B is tidied where it is")
    }

    // MARK: EDIT-18 The close button only closes when it's showing

    @Test("EDIT-18 No × unless hovered and wide enough; closeVisible follows") func edit18a() {
        let n = WindowNode()
        n.place(canvasFrame: Self.r(0, 0, 600, 400))
        n.style(scale: 1, hovered: false, selected: false, showsClose: false, visible: true, screenRect: Self.r(0, 0, 600, 400))
        #expect(!n.closeVisible, "not hovered")
        n.style(scale: 1, hovered: true, selected: false, showsClose: true, visible: true, screenRect: Self.r(0, 0, 600, 400))
        #expect(n.closeVisible)
        n.style(scale: 1, hovered: true, selected: false, showsClose: true, visible: false, screenRect: Self.r(0, 0, 600, 400))
        #expect(!n.closeVisible, "not drawn at all")
        let small = WindowNode()
        small.place(canvasFrame: Self.r(0, 0, 200, 150))
        small.style(scale: 1, hovered: true, selected: false, showsClose: true, visible: true, screenRect: Self.r(0, 0, 200, 150))
        #expect(!small.closeVisible, "under 220pt on screen")
    }

    @Test("EDIT-18 A click where × would be only closes when it shows") func edit18b() {
        let small = Fake.window(id: 1, canvas: Self.r(0, 0, 400, 300))     // 200 on screen
        let large = Fake.window(id: 2, canvas: Self.r(500, 0, 600, 400))   // 300 on screen
        let c = Self.zoomedOut([small, large])
        func clickClose(_ w: ManagedWindow) -> [[CGWindowID]] {
            let x = WindowNode.closeRect(in: c.camera.toView(w.canvasFrame))
            return Self.closing { c.view.mouseDown(with: Self.mouse(.leftMouseDown, CGPoint(x: x.midX, y: x.midY), c)) }
        }
        c.view.hovered = small
        c.view.render()
        #expect(!small.node.closeVisible)
        #expect(clickClose(small).isEmpty, "1: too small, not closed")
        #expect(!large.node.closeVisible)
        #expect(clickClose(large).isEmpty, "not hovered, not closed")
        c.view.hovered = large
        c.view.render()
        #expect(large.node.closeVisible)
        #expect(clickClose(large) == [[2]], "2: hovered and wide enough, it closes")
    }

    // MARK: EDIT-20 Tidy Up on a smaller screen holds on the big screen

    @Test("EDIT-20 A tidied home layout comes back exactly at full sizes") func edit20a() {
        var home = [Self.r(0, 0, 1600, 900), Self.r(1550, 40, 800, 600), Self.r(1640, 700, 700, 500)]
        let full = home.map(\.size)
        CanvasController.tidyUp(&home)
        #expect(!Self.overlaps(home))
        #expect(Self.gapX(home[0], home[1]) == 20 && home[1].minY == home[0].minY)
        #expect(Self.gapY(home[1], home[2]) == 20 && home[2].minX == home[1].minX)
        // The big screen: full sizes give back the tidied home layout exactly.
        #expect(CanvasController.derive(home: home, sizes: full) == home.map(\.origin))
        // A smaller screen: shrunk windows keep the 20pt gaps.
        let small = full.map { CanvasController.cap($0, to: CGSize(width: 1512, height: 949)) }
        let here = zip(CanvasController.derive(home: home, sizes: small), small).map { CGRect(origin: $0, size: $1) }
        #expect(Self.gapX(here[0], here[1]) == 20)
        #expect(Self.gapY(here[1], here[2]) == 20)
    }

    @Test("EDIT-20 Tidied on the laptop, the group is tidy on the big screen") func edit20b() {
        // Chosen sizes and an untidy home layout (overlap, uneven gaps).
        let chosen = [Self.r(0, 0, 1600, 900), Self.r(1550, 40, 800, 600), Self.r(1640, 700, 700, 500)]
        let ws = chosen.enumerated().map { Fake.window(id: CGWindowID($0.offset + 1), canvas: $0.element) }
        let c = TestCanvas.make(display: .external, windows: ws)
        for (w, f) in zip(ws, chosen) { w.home = f.origin }
        c.fitLayoutToScreen(tidy: false, rederiving: [])
        // The laptop: macOS (or Expanse) shrinks what doesn't fit; fake windows need telling.
        c.displayOverride = (TestDisplay.laptop.frame, TestDisplay.laptop.usable)
        c.updateOverlayFrame()
        for w in ws { w.canvasFrame.size = CanvasController.cap(w.preferredSize, to: c.viewSize) }
        c.fitLayoutToScreen(tidy: false, rederiving: [])
        // Tidy Up there (as tidy() does, without the canvas and the animation).
        c.homeFromCanvas()
        c.fitLayoutToScreen(tidy: true)
        let laptop = ws.map(\.canvasFrame)
        #expect(!Self.overlaps(laptop))
        #expect(Self.gapX(laptop[0], laptop[1]) == 20 && Self.gapY(laptop[1], laptop[2]) == 20, "tidy on the laptop")
        // Back on the big screen: windows grow back to their chosen sizes.
        c.displayOverride = (TestDisplay.external.frame, TestDisplay.external.usable)
        c.updateOverlayFrame()
        for w in ws { w.canvasFrame.size = w.preferredSize }
        c.fitLayoutToScreen(tidy: false, rederiving: [])
        let big = ws.map(\.canvasFrame)
        #expect(big.map(\.size) == chosen.map(\.size))
        #expect(!Self.overlaps(big), "not the untidy layout from before")
        #expect(Self.gapX(big[0], big[1]) == 20 && big[1].minY == big[0].minY, "the tidied arrangement, 20pt gaps")
        #expect(Self.gapY(big[1], big[2]) == 20 && big[2].minX == big[1].minX)
        #expect(ws.allSatisfy { $0.home == $0.canvasFrame.origin }, "the home layout is the tidied one")
    }

    // MARK: EDIT-21 Dragging near the middle of the screen snaps to dead centre

    @Test("EDIT-21 Near the screen's middle a window snaps to dead centre, with a guide") func edit21() {
        for scale: CGFloat in [1, 0.5] {
            let c = Self.canvas([], scale: scale, origin: .zero)
            let mid = c.camera.center(in: c.viewport.size)
            let near = 8 / scale   // 8 screen points off, each way
            let (f, lines) = c.snap(Self.r(mid.x - 200 + near, mid.y - 150 - near, 400, 300), excluding: [1])
            #expect(f.midX == mid.x && f.midY == mid.y, "scale \(scale)")
            #expect(lines.count == 2)
            let vertical = lines.first { $0.0.x == $0.1.x }, horizontal = lines.first { $0.0.y == $0.1.y }
            #expect(vertical.map { $0.0.x == mid.x && $0.0.y <= f.minY && $0.1.y >= f.maxY } == true, "through the window")
            #expect(horizontal.map { $0.0.y == mid.y && $0.0.x <= f.minX && $0.1.x >= f.maxX } == true)
            // Only one way near: only that way snaps.
            let (h, _) = c.snap(Self.r(mid.x - 200 + near, mid.y - 150 - 100, 400, 300), excluding: [1])
            #expect(h.midX == mid.x && h.midY == mid.y - 100)
        }
    }

    // MARK: EDIT-22 One × closes every selected window

    @Test("EDIT-22 Hovering one of a selection shows × on all of them; one × closes them all") func edit22() {
        let ws = (1...4).map { Fake.window(id: CGWindowID($0), canvas: Self.r(CGFloat($0 - 1) * 700, 0, 600, 400)) }
        let c = Self.zoomedOut(ws)
        c.view.selected = [1, 2, 3]
        c.view.hovered = ws[0]
        c.view.render()
        #expect(ws.map(\.node.closeVisible) == [true, true, true, false])
        // Hovering a window outside the selection: only its own ×.
        c.view.hovered = ws[3]
        c.view.render()
        #expect(ws.map(\.node.closeVisible) == [false, false, false, true])
        c.view.hovered = ws[1]
        c.view.render()
        let x = WindowNode.closeRect(in: c.camera.toView(ws[1].canvasFrame))
        let closed = Self.closing { c.view.mouseDown(with: Self.mouse(.leftMouseDown, CGPoint(x: x.midX, y: x.midY), c)) }
        #expect(closed == [[1, 2, 3]], "all three close, nothing else")
        #expect(c.view.selected.isEmpty, "and the selection is cleared")
    }

    @Test("EDIT-22 A selection of one is no group; × needs a window wide enough") func edit22b() {
        let ws = [Fake.window(id: 1, canvas: Self.r(0, 0, 600, 400)), Fake.window(id: 2, canvas: Self.r(700, 0, 600, 400)),
                  Fake.window(id: 3, canvas: Self.r(1400, 0, 400, 300))]   // 200 on screen
        let c = Self.zoomedOut(ws)
        c.view.selected = [1]
        c.view.hovered = ws[1]
        c.view.render()
        #expect(ws.map(\.node.closeVisible) == [false, true, false])
        c.view.selected = [1, 2, 3]
        c.view.hovered = ws[0]
        c.view.render()
        #expect(ws.map(\.node.closeVisible) == [true, true, false], "the narrow one shows none")
    }

    // MARK: EDIT-24 Tidy Up lines up edges that nearly line up and closes gaps

    @Test("EDIT-24 Tidy Up lines up near edges and closes gaps to 20pt") func edit24() {
        let a = Self.r(0, 0, 400, 300)
        let b = Self.r(450, 40, 400, 300)    // right of A: 50pt gap, top 40pt lower
        let c = Self.r(30, 380, 400, 300)    // below A: left edge 30pt in, 80pt gap
        let p1 = Self.r(3000, 0, 400, 300), p2 = Self.r(3450, 100, 400, 300)   // tops 100pt apart
        var frames = [a, b, c, p1, p2]
        CanvasController.tidyUp(&frames)
        #expect(frames[1].minY == frames[0].minY, "B's top lines up with A's")
        #expect(Self.gapX(frames[0], frames[1]) == 20)
        #expect(frames[2].minX == frames[0].minX, "C's left edge lines up with A's")
        #expect(Self.gapY(frames[0], frames[2]) == 20)
        #expect(frames[4].minY - frames[3].minY == 100, "100pt apart is more than 60: not lined up")
        #expect(CanvasController.alignReach == 60 && CanvasController.gap == 20)
    }

    @Test("EDIT-24 A line-up that would come closer than 20pt to another window is skipped") func edit24b() {
        let left = Self.r(0, 0, 400, 300), right = Self.r(420, 40, 400, 300)
        var free = [left, right]
        CanvasController.align(&free, reach: 60, gap: 20)
        #expect(free[1].minY == 0)
        // A window above `right`: lined up, it would be 10pt below it.
        var blocked = [left, right, Self.r(420, -310, 400, 300)]
        CanvasController.align(&blocked, reach: 60, gap: 20)
        #expect(blocked[1].minY == 40)
        // Gravity closes gaps without making overlaps.
        var gaps = [left, Self.r(480, 0, 400, 300), Self.r(0, 390, 400, 300)]
        CanvasController.gravity(&gaps, gap: 20)
        #expect(gaps[1].minX == 420 && gaps[2].minY == 320)
    }

    // MARK: EDIT-25 A group moves as a whole only when another grows into its space

    @Test("EDIT-25 A group another grows into moves as a whole, 240pt clear") func edit25() {
        let groupA = [Self.r(0, 0, 400, 300), Self.r(250, 0, 400, 300)]   // overlapping by 150
        let groupB = [Self.r(910, 0, 400, 300), Self.r(1330, 0, 400, 300)] // 260 right of A
        var frames = groupA + groupB
        CanvasController.tidyUp(&frames)
        #expect(Self.gapX(frames[0], frames[1]) == 20, "A is tidied")
        let shift = frames[2].minX - groupB[0].minX
        #expect(shift > 0)
        #expect(frames[2] == groupB[0].offsetBy(dx: shift, dy: 0) && frames[3] == groupB[1].offsetBy(dx: shift, dy: 0),
                "B moves right as a whole")
        #expect(frames[2].minX - frames[1].maxX == 240, "the groups stay 240pt apart")
    }

    @Test("EDIT-25 separateGroups leaves groups that are clear alone") func edit25b() {
        var frames = [Self.r(0, 0, 400, 300), Self.r(700, 0, 400, 300), Self.r(820, 0, 400, 300)]
        CanvasController.separateGroups(&frames, groups: [[0], [1, 2]], reach: 240)
        #expect(frames[1].minX == 700, "300pt clear: stays")
        var close = [Self.r(0, 0, 400, 300), Self.r(500, 50, 400, 300), Self.r(920, 50, 400, 300)]
        CanvasController.separateGroups(&close, groups: [[0], [1, 2]], reach: 240)
        #expect(close[1] == Self.r(640, 50, 400, 300) && close[2] == Self.r(1060, 50, 400, 300))
    }

    // MARK: EDIT-26 Tidy Up right after a drag keeps what you dragged

    @Test("EDIT-26 A drag sets home spots at once, so Tidy Up keeps the new place (logic)") func edit26() {
        let g = [Fake.window(id: 1, canvas: Self.r(0, 0, 400, 300)), Fake.window(id: 2, canvas: Self.r(430, 0, 400, 300))]
        let c = TestCanvas.make(windows: g)
        for w in g { w.home = w.canvasFrame.origin }
        for w in g {
            let before = w.canvasFrame.origin
            w.canvasFrame.origin = CGPoint(x: before.x + 2000, y: before.y + 500)
            c.noteUserMove(w, from: before)
        }
        #expect(g.map(\.home) == [CGPoint(x: 2000, y: 500), CGPoint(x: 2430, y: 500)], "home follows the drag, before any save")
        c.fitLayoutToScreen(tidy: true)
        #expect(g.map(\.canvasFrame.origin) == [CGPoint(x: 2000, y: 500), CGPoint(x: 2420, y: 500)],
                "tidied at its new place, not put back")
    }
}
