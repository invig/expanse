import Testing
import AppKit
import Carbon.HIToolbox
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "CanvasView.swift") @testable import Expanse

/// Screens you build on the canvas (docs/regression/arranging.md, EDIT-27 on) and sizes picked
/// zoomed out (docs/regression/sizes.md, SIZE-15 on), on fake windows. The laptop's screen is
/// 1512×949 below the menu bar. Mouse and key events go straight to the view; nothing is posted.
@MainActor @Suite("EDIT and SIZE: screens you build, sizes picked zoomed out", .serialized) struct SCREENSTests {

    // MARK: Helpers

    static let size = NAVTests.viewSize
    static let screen = CGRect(origin: .zero, size: size)

    static func win(_ id: CGWindowID, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> ManagedWindow {
        NAVTests.win(id, x, y, w, h)
    }

    /// The gap setting for `body`, put back afterwards.
    static func withGap(_ gap: Double?, _ body: () throws -> Void) rethrows {
        let saved = UserDefaults.standard.object(forKey: CanvasController.gapKey)
        if let gap { UserDefaults.standard.set(gap, forKey: CanvasController.gapKey) } else {
            UserDefaults.standard.removeObject(forKey: CanvasController.gapKey)
        }
        defer { UserDefaults.standard.set(saved, forKey: CanvasController.gapKey) }
        try body()
    }

    /// Zoomed out to 50%, the view's top left at canvas (-100, -100), with the windows drawn.
    static func zoomedOut(_ ws: [ManagedWindow]) -> CanvasController {
        let c = TestCanvas.make(windows: ws)
        c.camera = Camera(origin: CGPoint(x: -100, y: -100), scale: 0.5)
        ws.forEach { c.view.addNode($0.node) }
        c.view.render()
        return c
    }

    static func mouse(_ type: NSEvent.EventType, _ p: CGPoint, _ c: CanvasController, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: p.x, y: c.view.bounds.height - p.y), modifierFlags: flags,
                           timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    static func key(_ code: Int, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code))!
    }

    /// The menu item titled `title` in `menu`, chosen.
    static func choose(_ title: String, in menu: NSMenu?) {
        guard let menu, let i = menu.items.firstIndex(where: { $0.title == title }) else {
            Issue.record("no “\(title)” in the menu")
            return
        }
        menu.performActionForItem(at: i)
    }

    // MARK: Slots

    @Test("EDIT-32 Slots: the gap between them and round the screen's edge, at 20pt, 10pt and none")
    func edit32Slots() {
        let s20 = Self.screen
        #expect(Screens.frame(of: .left, in: s20, gap: 20) == CGRect(x: 20, y: 20, width: 726, height: 909))
        #expect(Screens.frame(of: .right, in: s20, gap: 20) == CGRect(x: 766, y: 20, width: 726, height: 909))
        #expect(Screens.frame(of: .topRight, in: s20, gap: 20) == CGRect(x: 766, y: 20, width: 726, height: 444))
        #expect(Screens.frame(of: .bottomRight, in: s20, gap: 20) == CGRect(x: 766, y: 484, width: 726, height: 445))
        #expect(Screens.frame(of: .full, in: s20, gap: 20) == CGRect(x: 20, y: 20, width: 1472, height: 909))
        #expect(Screens.frame(of: .left, in: s20, gap: 10) == CGRect(x: 10, y: 10, width: 741, height: 929))
        #expect(Screens.frame(of: .right, in: s20, gap: 0) == CGRect(x: 756, y: 0, width: 756, height: 949))
        #expect(Screens.frame(of: .bottomLeft, in: s20, gap: 0) == CGRect(x: 0, y: 474, width: 756, height: 475))
        // Each layout, at each gap, is a screen group: hops, ⌃⌥C and a click zoomed out frame it.
        for gap: CGFloat in [20, 10, 0] {
            for layout in [ScreenLayout.halves, .leftAndQuarters, .quartersAndRight, .quarters] {
                let frames = layout.slots.map { Screens.frame(of: $0, in: s20.offsetBy(dx: 3000, dy: -700), gap: gap) }
                #expect(CanvasController.screenGroups(frames, fitting: Self.size) == [Array(frames.indices)])
            }
        }
    }

    @Test("EDIT-32 The gap setting: 20pt unless 10pt or none is chosen")
    func edit32Setting() {
        Self.withGap(nil) { #expect(CanvasController.gap == 20) }
        Self.withGap(10) { #expect(CanvasController.gap == 10) }
        Self.withGap(0) { #expect(CanvasController.gap == 0) }
        Self.withGap(15) { #expect(CanvasController.gap == 20) }
        // Snapping keeps the gap you chose: a window dragged close to another's right edge.
        Self.withGap(10) {
            let a = Self.win(1, 0, 0, 400, 300), b = Self.win(2, 0, 0, 400, 300)
            let c = TestCanvas.make(windows: [a, b])
            c.camera = Camera(origin: CGPoint(x: -20_000, y: -20_000), scale: 1)
            let (snapped, _) = c.snap(CGRect(x: 414, y: 0, width: 400, height: 300), excluding: [b.id])
            #expect(snapped.minX == 410)
        }
    }

    @Test("EDIT-27 Drop zones: a corner is a quarter, a side a half, the middle nothing")
    func edit27Zones() {
        let t = CGRect(x: 100, y: 100, width: 1000, height: 600)
        #expect(Screens.dropZone(at: CGPoint(x: 150, y: 150), in: t) == .topLeft)
        #expect(Screens.dropZone(at: CGPoint(x: 1050, y: 650), in: t) == .bottomRight)
        #expect(Screens.dropZone(at: CGPoint(x: 1050, y: 400), in: t) == .right)
        #expect(Screens.dropZone(at: CGPoint(x: 400, y: 400), in: t) == .left)
        #expect(Screens.dropZone(at: CGPoint(x: 600, y: 400), in: t) == nil)
        #expect(Screens.dropZone(at: CGPoint(x: 600, y: 120), in: t) == nil)
        #expect(Screens.dropZone(at: CGPoint(x: 50, y: 400), in: t) == nil)
        // Dropped on its right, the window dropped on goes left, and stays where it is.
        #expect(Slot.right.otherHalf == .left && Slot.topLeft.otherHalf == .right)
        let a = CGRect(x: 500, y: 300, width: 800, height: 600)
        let origin = Screens.screenOrigin(keeping: a, in: .left, size: Self.size, gap: 20)
        #expect(Screens.frame(of: .left, in: CGRect(origin: origin, size: Self.size), gap: 20).origin == a.origin)
    }

    @Test("EDIT-28 A screen's windows and their slots are worked out from where they are")
    func edit28Layout() {
        let s = Self.screen.offsetBy(dx: 2000, dy: 500)
        func frames(_ slots: [Slot]) -> [CGRect] { slots.map { Screens.frame(of: $0, in: s, gap: 20) } }
        let halves = Screens.layout(of: frames([.left, .right]), size: Self.size, gap: 20)
        #expect(halves?.screen == s && halves?.slots == [.left, .right])
        // A slot left empty (the bottom right), and the bottom row on its own.
        #expect(Screens.layout(of: frames([.left, .topRight]), size: Self.size, gap: 20)?.slots == [.left, .topRight])
        // A row of two quarters on its own could be either row of a screen: either will do.
        let row = Screens.layout(of: frames([.bottomLeft, .bottomRight]), size: Self.size, gap: 20)
        #expect(row?.slots == [.topLeft, .topRight] || row?.slots == [.bottomLeft, .bottomRight])
        // An app that rounds its size (Terminal) still counts.
        var rounded = frames([.left, .right])
        rounded[1].size.width -= 9
        #expect(Screens.layout(of: rounded, size: Self.size, gap: 20)?.slots == [.left, .right])
        // Two windows that just happen to be side by side don't.
        #expect(Screens.layout(of: [CGRect(x: 0, y: 0, width: 600, height: 400), CGRect(x: 620, y: 0, width: 600, height: 400)],
                                size: Self.size, gap: 20) == nil)
    }

    @Test("EDIT-29 Windows take the slots nearest where they are")
    func edit29Assign() {
        // One far left, two stacked on the right: the left half and the right quarters.
        let centres = [CGPoint(x: 0, y: 500), CGPoint(x: 900, y: 0), CGPoint(x: 900, y: 900)]
        #expect(Screens.assign(centres, to: .leftAndQuarters) == [.left, .topRight, .bottomRight])
        #expect(Screens.assign([CGPoint(x: 900, y: 900), CGPoint(x: 0, y: 500), CGPoint(x: 900, y: 0)], to: .leftAndQuarters)
                == [.bottomRight, .left, .topRight])
        #expect(Screens.assign([CGPoint(x: 500, y: 0), CGPoint(x: 0, y: 0)], to: .halves) == [.right, .left])
        #expect(ScreenLayout.layouts(for: 3) == [.leftAndQuarters, .quartersAndRight])
        #expect(ScreenLayout.layouts(for: 1).isEmpty && ScreenLayout.layouts(for: 5).isEmpty)
    }

    // MARK: Arranging

    @Test("EDIT-27 Arranging: windows take their slots' sizes and spots, and windows in the way move clear")
    func edit27Arrange() {
        let a = Self.win(1, 0, 0, 500, 400), b = Self.win(2, 3000, 0, 500, 400)
        // In the way: inside where the screen will be, and just beyond its right edge.
        let inside = Self.win(3, 900, 300, 300, 200), beside = Self.win(4, 1520, 100, 300, 200)
        let far = Self.win(5, 8000, 0, 300, 200)
        let c = TestCanvas.make(windows: [a, b, inside, beside, far])
        NAVTests.onCanvas(c) {
            let origin = Screens.screenOrigin(keeping: a.canvasFrame, in: .left, size: Self.size, gap: 20)
            c.arrange([(a, .left), (b, .right)], screen: origin, how: "test")
            let screen = c.screenRect(at: origin)
            #expect(a.canvasFrame == Screens.frame(of: .left, in: screen, gap: 20))
            #expect(a.canvasFrame.origin == .zero)
            #expect(b.canvasFrame == Screens.frame(of: .right, in: screen, gap: 20))
            #expect(a.preferredSize == a.canvasFrame.size && b.preferredSize == b.canvasFrame.size)
            #expect(a.home == a.canvasFrame.origin && b.home == b.canvasFrame.origin)
            // It's a group, and nothing else is near enough to spoil it.
            #expect(c.screenGroup(of: a).map { Set($0.map(\.id)) } == [1, 2])
            for w in [inside, beside] {
                #expect(!w.canvasFrame.intersects(screen.insetBy(dx: -40, dy: -40)))
                #expect(w.home == w.canvasFrame.origin)
            }
            #expect(far.canvasFrame.origin == CGPoint(x: 8000, y: 0))
        }
    }

    @Test("EDIT-33 An app that won't take a slot's size keeps its own, and the rest still forms")
    func edit33() {
        let vm = Fake.window(id: 7, bundleID: "com.utmapp.UTM", appName: "UTM", canvas: CGRect(x: 0, y: 0, width: 1024, height: 768))
        vm.needsFirstFrame = false
        let b = Self.win(8, 3000, 0, 500, 400)
        let c = TestCanvas.make(windows: [vm, b])
        NAVTests.onCanvas(c) {
            c.arrange([(vm, .left), (b, .right)], screen: .zero, how: "test")
            #expect(vm.canvasFrame.size == CGSize(width: 1024, height: 768))
            #expect(vm.canvasFrame.origin == CGPoint(x: 20, y: 20))
            #expect(b.canvasFrame == Screens.frame(of: .right, in: Self.screen, gap: 20))
        }
    }

    @Test("EDIT-34 ⌘Z puts back the windows a screen moved and sized, one step at a time")
    func edit34() {
        let a = Self.win(1, 0, 0, 500, 400), b = Self.win(2, 3000, 0, 500, 400), other = Self.win(3, 900, 300, 300, 200)
        let c = Self.zoomedOut([a, b, other])
        NAVTests.onCanvas(c) {
            let before = [a, b, other].map(\.canvasFrame)
            c.arrange([(a, .left), (b, .right)], screen: .zero, how: "test")
            c.resize(a, to: CGSize(width: 300, height: 300), how: "test")
            #expect(c.canUndo)
            c.view.keyDown(with: Self.key(kVK_ANSI_Z, .command))
            #expect(a.canvasFrame == Screens.frame(of: .left, in: Self.screen, gap: 20))
            c.view.keyDown(with: Self.key(kVK_ANSI_Z, .command))
            #expect([a, b, other].map(\.canvasFrame) == before)
            #expect(a.preferredSize == CGSize(width: 500, height: 400))
            #expect(!c.canUndo)
            // Nothing left to undo: nothing happens.
            c.view.keyDown(with: Self.key(kVK_ANSI_Z, .command))
            #expect([a, b, other].map(\.canvasFrame) == before)
        }
    }

    /// Drags the window at canvas point `from` to canvas point `to` (one step), and lets go.
    static func drag(_ c: CanvasController, from: CGPoint, to: CGPoint, _ flags: NSEvent.ModifierFlags = [], letGo: Bool = true) {
        let a = c.camera.toView(from), b = c.camera.toView(to)
        c.view.mouseDown(with: mouse(.leftMouseDown, a, c))
        c.view.mouseDragged(with: mouse(.leftMouseDragged, b, c, flags))
        if letGo { c.view.mouseUp(with: mouse(.leftMouseUp, b, c, flags)) }
    }

    // MARK: Drop zones

    @Test("EDIT-27 Dropping a window on another's right side makes the two a screen where that window is")
    func edit27Drop() {
        let a = Self.win(1, 0, 0, 600, 400), b = Self.win(2, 3000, 0, 500, 300)
        let c = Self.zoomedOut([a, b])
        NAVTests.onCanvas(c) {
            // Over A's right side: the zone shows, B's slot filled and the screen outlined.
            Self.drag(c, from: CGPoint(x: 3250, y: 150), to: CGPoint(x: 560, y: 200), letGo: false)
            #expect(c.view.dropSlot.path != nil && c.view.dropScreen.path != nil)
            c.view.mouseUp(with: Self.mouse(.leftMouseUp, c.camera.toView(CGPoint(x: 560, y: 200)), c))
            #expect(c.view.dropSlot.path == nil)
            let screen = c.screenRect(at: CGPoint(x: -20, y: -20))
            #expect(a.canvasFrame == Screens.frame(of: .left, in: screen, gap: 20))
            #expect(a.canvasFrame.origin == .zero)
            #expect(b.canvasFrame == Screens.frame(of: .right, in: screen, gap: 20))
            #expect(c.screenGroup(of: b).map { Set($0.map(\.id)) } == [1, 2])
            // ⌘Z: B back where it was dragged from, A as it was.
            c.undo()
            #expect(b.canvasFrame == CGRect(x: 3000, y: 0, width: 500, height: 300))
            #expect(a.canvasFrame == CGRect(x: 0, y: 0, width: 600, height: 400))
        }
    }

    @Test("EDIT-27 A corner makes a quarter; the middle, or ⌘ held, is an ordinary move")
    func edit27Corner() {
        let a = Self.win(1, 0, 0, 600, 400), b = Self.win(2, 3000, 0, 500, 300)
        let c = Self.zoomedOut([a, b])
        NAVTests.onCanvas(c) {
            Self.drag(c, from: CGPoint(x: 3250, y: 150), to: CGPoint(x: 40, y: 380))
            // The bottom-left quarter for B; A takes the right half, staying where it was.
            let screen = c.screenRect(at: Screens.screenOrigin(keeping: CGRect(x: 0, y: 0, width: 600, height: 400), in: .right,
                                                               size: Self.size, gap: 20))
            #expect(b.canvasFrame == Screens.frame(of: .bottomLeft, in: screen, gap: 20))
            #expect(a.canvasFrame == Screens.frame(of: .right, in: screen, gap: 20))
        }
        let a2 = Self.win(1, 0, 0, 600, 400), b2 = Self.win(2, 3000, 0, 500, 300)
        let c2 = Self.zoomedOut([a2, b2])
        NAVTests.onCanvas(c2) {
            Self.drag(c2, from: CGPoint(x: 3250, y: 150), to: CGPoint(x: 300, y: 200))
            #expect(a2.canvasFrame == CGRect(x: 0, y: 0, width: 600, height: 400))
            #expect(b2.canvasFrame.size == CGSize(width: 500, height: 300))
            Self.drag(c2, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 560, y: 200), .command)
            #expect(a2.canvasFrame.size == CGSize(width: 600, height: 400) && b2.canvasFrame.size == CGSize(width: 500, height: 300))
        }
    }

    @Test("EDIT-28 Dropping into a screen you built: an empty slot, or half of a half")
    func edit28Drop() {
        let a = Self.win(1, 0, 0, 600, 400), b = Self.win(2, 3000, 0, 500, 300)
        let d = Self.win(3, 3000, 2000, 400, 300), e = Self.win(4, 3000, 4000, 400, 300)
        let c = Self.zoomedOut([a, b, d, e])
        NAVTests.onCanvas(c) {
            c.arrange([(a, .left), (b, .topRight)], screen: .zero, how: "test")
            // The empty bottom-right slot.
            let bottomRight = Screens.frame(of: .bottomRight, in: Self.screen, gap: 20)
            Self.drag(c, from: CGPoint(x: 3200, y: 2150), to: CGPoint(x: bottomRight.midX, y: bottomRight.midY))
            #expect(d.canvasFrame == bottomRight)
            // The screen's windows stay: they aren't in the way.
            #expect(a.canvasFrame == Screens.frame(of: .left, in: Self.screen, gap: 20))
            #expect(b.canvasFrame == Screens.frame(of: .topRight, in: Self.screen, gap: 20))
            // The bottom of A's half: A goes to the top-left quarter, E below it.
            let left = Screens.frame(of: .left, in: Self.screen, gap: 20)
            Self.drag(c, from: CGPoint(x: 3200, y: 4150), to: CGPoint(x: left.midX, y: left.maxY - 50))
            #expect(a.canvasFrame == Screens.frame(of: .topLeft, in: Self.screen, gap: 20))
            #expect(e.canvasFrame == Screens.frame(of: .bottomLeft, in: Self.screen, gap: 20))
            #expect(c.builtScreens().first?.members.count == 4)
        }
    }

    @Test("EDIT-31 Dragging a screen's ring moves the whole screen; dragging a window moves just it")
    func edit31() {
        let a = Self.win(1, 0, 0, 600, 400), b = Self.win(2, 3000, 0, 500, 300)
        let c = Self.zoomedOut([a, b])
        NAVTests.onCanvas(c) {
            c.arrange([(a, .left), (b, .right)], screen: .zero, how: "test")
            let left = a.canvasFrame, right = b.canvasFrame
            // Hovering the gap between them: the ring, outlined.
            let gap = CGPoint(x: left.maxX + 10, y: left.midY)
            c.view.mouseMoved(with: Self.mouse(.mouseMoved, c.camera.toView(gap), c))
            #expect(c.view.ringGroup?.count == 2 && c.view.groupOutline.path != nil)
            // ⌘ so nothing snaps: both move 400, 200 on the canvas (200, 100 in the view at 50%).
            Self.drag(c, from: gap, to: CGPoint(x: gap.x + 400, y: gap.y + 200), .command)
            #expect(a.canvasFrame == left.offsetBy(dx: 400, dy: 200))
            #expect(b.canvasFrame == right.offsetBy(dx: 400, dy: 200))
            #expect(a.home == a.canvasFrame.origin && b.home == b.canvasFrame.origin)
            // One window dragged out moves on its own.
            Self.drag(c, from: CGPoint(x: b.canvasFrame.midX, y: b.canvasFrame.midY),
                      to: CGPoint(x: b.canvasFrame.midX + 3000, y: b.canvasFrame.midY), .command)
            #expect(a.canvasFrame == left.offsetBy(dx: 400, dy: 200))
            #expect(c.screenGroup(of: a) == nil)
        }
    }

    // MARK: Picking a layout, and the screen tool

    /// A click (down and up) at canvas point `p`.
    static func click(_ c: CanvasController, _ p: CGPoint) {
        let v = c.camera.toView(p)
        c.view.mouseDown(with: mouse(.leftMouseDown, v, c))
        c.view.mouseUp(with: mouse(.leftMouseUp, v, c))
    }

    @Test("EDIT-29 Select windows and pick a layout: each goes in the slot nearest it, the left one staying put")
    func edit29() {
        let a = Self.win(1, 0, 0, 600, 400), b = Self.win(2, 2000, -500, 500, 300), d = Self.win(3, 2000, 900, 400, 300)
        let c = Self.zoomedOut([a, b, d])
        NAVTests.onCanvas(c) {
            c.view.selected = [1, 2, 3]
            let menu = c.view.layoutMenu(for: [a, b, d])
            #expect(menu.items.map(\.title) == ["One left, two right", "Two left, one right"])
            #expect(menu.items.map(\.keyEquivalent) == ["1", "2"])
            // Right-clicking one of them offers the same, under Make a screen.
            let right = c.view.menu(for: Self.mouse(.rightMouseDown, c.camera.toView(CGPoint(x: 300, y: 200)), c))
            #expect(right?.items.first { $0.title == "Make a screen" }?.submenu?.items.count == 2)
            menu.performActionForItem(at: 0)
            let screen = c.screenRect(at: Screens.screenOrigin(keeping: CGRect(x: 0, y: 0, width: 600, height: 400), in: .left,
                                                               size: Self.size, gap: 20))
            #expect(a.canvasFrame == Screens.frame(of: .left, in: screen, gap: 20) && a.canvasFrame.origin == .zero)
            #expect(b.canvasFrame == Screens.frame(of: .topRight, in: screen, gap: 20))
            #expect(d.canvasFrame == Screens.frame(of: .bottomRight, in: screen, gap: 20))
            #expect(c.view.selected.isEmpty)
            // One window picked: S has nothing to make.
            c.view.selected = [1]
            c.view.keyDown(with: Self.key(kVK_ANSI_S))
            #expect(c.view.tool == nil)
        }
    }

    @Test("EDIT-30 The screen tool: a slot then a window, a window then a slot; a quarter splits a half")
    func edit30() {
        let a = Self.win(1, 3000, 0, 600, 400), b = Self.win(2, 3000, 1000, 500, 300), d = Self.win(3, 3000, 2000, 400, 300)
        let c = Self.zoomedOut([a, b, d])
        NAVTests.onCanvas(c) {
            c.view.keyDown(with: Self.key(kVK_ANSI_S))
            #expect(c.view.tool != nil)
            c.view.startTool(centredOn: CGPoint(x: 756, y: 474.5))
            #expect(c.view.tool?.screen == Self.screen)
            let screen = Self.screen
            func slot(_ s: Slot) -> CGRect { Screens.frame(of: s, in: screen, gap: 20) }
            // A slot, then a window.
            Self.click(c, CGPoint(x: slot(.right).midX, y: slot(.right).midY))
            #expect(c.view.tool?.slot == .right)
            Self.click(c, CGPoint(x: 3300, y: 200))
            #expect(a.canvasFrame == slot(.right))
            #expect(c.isActive, "a click on a window with the tool on doesn't go to it")
            // A window, then a slot.
            Self.click(c, CGPoint(x: 3250, y: 1150))
            #expect(c.view.tool?.window === b)
            Self.click(c, CGPoint(x: slot(.left).midX, y: slot(.left).midY))
            #expect(b.canvasFrame == slot(.left))
            // A quarter of A's half: A moves to the other quarter.
            Self.click(c, CGPoint(x: 3200, y: 2150))
            Self.click(c, CGPoint(x: slot(.right).midX, y: slot(.right).maxY - 40))
            #expect(d.canvasFrame == slot(.bottomRight) && a.canvasFrame == slot(.topRight))
            #expect(c.view.tool?.steps == 3)
            c.view.keyDown(with: Self.key(kVK_Return))
            #expect(c.view.tool == nil)
            #expect(c.builtScreens().first?.members.count == 3)
        }
    }

    @Test("EDIT-30 Esc puts back everything the screen tool did; its empty frame moves by its edge")
    func edit30Cancel() {
        let a = Self.win(1, 3000, 0, 600, 400), b = Self.win(2, 3000, 1000, 500, 300)
        let c = Self.zoomedOut([a, b])
        NAVTests.onCanvas(c) {
            c.view.startTool(centredOn: CGPoint(x: 756, y: 474.5))
            // The empty frame by its top edge, 100pt down (50 in the view at 50%).
            Self.drag(c, from: CGPoint(x: 756, y: 0), to: CGPoint(x: 756, y: 100))
            #expect(c.view.tool?.screen == Self.screen.offsetBy(dx: 0, dy: 100))
            let moved = Self.screen.offsetBy(dx: 0, dy: 100)
            let left = Screens.frame(of: .left, in: moved, gap: 20), right = Screens.frame(of: .right, in: moved, gap: 20)
            Self.click(c, CGPoint(x: left.midX, y: left.midY))
            Self.click(c, CGPoint(x: 3300, y: 200))
            Self.click(c, CGPoint(x: right.midX, y: right.midY))
            Self.click(c, CGPoint(x: 3250, y: 1150))
            #expect(a.canvasFrame == left && b.canvasFrame == right)
            c.view.keyDown(with: Self.key(kVK_Escape))
            #expect(c.view.tool == nil && c.isActive)
            #expect(a.canvasFrame == CGRect(x: 3000, y: 0, width: 600, height: 400))
            #expect(b.canvasFrame == CGRect(x: 3000, y: 1000, width: 500, height: 300))
            // New screen from the canvas menu starts it where you right-clicked.
            Self.choose("New screen", in: c.view.menu(for: Self.mouse(.rightMouseDown, c.camera.toView(CGPoint(x: 900, y: 600)), c)))
            #expect(c.view.tool?.screen.midX == 900)
        }
    }

    // MARK: Resizing by the edges

    /// Drags from view point `a` to view point `b` and lets go.
    static func dragView(_ c: CanvasController, _ a: CGPoint, _ b: CGPoint, _ flags: NSEvent.ModifierFlags = []) {
        c.view.mouseDown(with: mouse(.leftMouseDown, a, c))
        c.view.mouseDragged(with: mouse(.leftMouseDragged, b, c, flags))
        c.view.mouseUp(with: mouse(.leftMouseUp, b, c, flags))
    }

    @Test("SIZE-15 Dragging a window's edge or corner zoomed out resizes it, no smaller than 200 × 120")
    func size15() {
        // At 50% from (-100, -100): A is at view (50, 50) to (350, 250).
        let a = Self.win(1, 0, 0, 600, 400)
        let c = Self.zoomedOut([a])
        NAVTests.onCanvas(c) {
            Self.dragView(c, CGPoint(x: 348, y: 150), CGPoint(x: 398, y: 150), .command)
            #expect(a.canvasFrame == CGRect(x: 0, y: 0, width: 700, height: 400))
            #expect(a.preferredSize == CGSize(width: 700, height: 400))
            // The bottom-right corner: both ways.
            Self.dragView(c, CGPoint(x: 398, y: 248), CGPoint(x: 348, y: 298), .command)
            #expect(a.canvasFrame == CGRect(x: 0, y: 0, width: 600, height: 500))
            // The left edge past the right: it stops at the smallest size, the right edge staying.
            Self.dragView(c, CGPoint(x: 51, y: 150), CGPoint(x: 502, y: 150), .command)
            #expect(a.canvasFrame == CGRect(x: 400, y: 0, width: 200, height: 500))
            // ⌘Z undoes each.
            c.undo()
            #expect(a.canvasFrame == CGRect(x: 0, y: 0, width: 600, height: 500))
        }
        // A VM's window has no edges to drag: that's a move.
        let vm = Fake.window(id: 7, bundleID: "com.utmapp.UTM", appName: "UTM", canvas: CGRect(x: 0, y: 0, width: 600, height: 400))
        vm.needsFirstFrame = false
        let v = Self.zoomedOut([vm])
        NAVTests.onCanvas(v) {
            Self.dragView(v, CGPoint(x: 349, y: 150), CGPoint(x: 399, y: 150), .command)
            #expect(vm.canvasFrame.size == CGSize(width: 600, height: 400))
            #expect(vm.canvasFrame.minX == 100)
        }
    }

    @Test("SIZE-16 A dragged edge snaps a gap from a neighbour, and to half the screen's width")
    func size16() {
        let a = Self.win(1, 0, 0, 600, 400), b = Self.win(2, 720, 0, 400, 400)
        let c = Self.zoomedOut([a, b])
        NAVTests.onCanvas(c) {
            // To 696 wide: within reach of 700, a gap short of B.
            Self.dragView(c, CGPoint(x: 348, y: 150), CGPoint(x: 396, y: 150))
            #expect(a.canvasFrame.width == 700)
        }
        let d = Self.win(1, 0, 0, 600, 400)
        let c2 = Self.zoomedOut([d])
        NAVTests.onCanvas(c2) {
            // To 716 wide: within reach of half the screen (726).
            Self.dragView(c2, CGPoint(x: 348, y: 150), CGPoint(x: 406, y: 150))
            #expect(d.canvasFrame.width == 726)
        }
    }

    @Test("SIZE-18 Even up: Same width, height or size as the window you right-clicked")
    func size18() {
        let a = Self.win(1, 0, 0, 600, 400), b = Self.win(2, 700, 0, 300, 300), d = Self.win(3, 1100, 0, 500, 500)
        let c = Self.zoomedOut([a, b, d])
        NAVTests.onCanvas(c) {
            c.view.selected = [1, 2, 3]
            let onA = c.camera.toView(CGPoint(x: 300, y: 200))
            Self.choose("Same height", in: c.view.menu(for: Self.mouse(.rightMouseDown, onA, c)))
            #expect(b.canvasFrame == CGRect(x: 700, y: 0, width: 300, height: 400))
            #expect(d.canvasFrame == CGRect(x: 1100, y: 0, width: 500, height: 400))
            c.view.selected = [1, 2, 3]
            Self.choose("Same width", in: c.view.menu(for: Self.mouse(.rightMouseDown, onA, c)))
            // B is now 600 wide and reaches over D, which moves along, a gap after it.
            #expect(b.canvasFrame == CGRect(x: 700, y: 0, width: 600, height: 400))
            #expect(d.canvasFrame.size == CGSize(width: 600, height: 400) && d.canvasFrame.minX >= 1320)
            #expect(a.canvasFrame == CGRect(x: 0, y: 0, width: 600, height: 400))
            // Only one window picked: no evening up to offer.
            c.view.selected = []
            #expect(c.view.menu(for: Self.mouse(.rightMouseDown, onA, c))?.items.contains { $0.title == "Same width" } == false)
        }
    }

    // MARK: The size menu

    @Test("SIZE-17 Right-click a window: fill, half or a quarter of the screen, its top-left staying put")
    func size17() {
        let a = Self.win(1, 0, 0, 500, 400), b = Self.win(2, 600, 0, 500, 400)
        let c = Self.zoomedOut([a, b])
        NAVTests.onCanvas(c) {
            let at = c.camera.toView(CGPoint(x: 250, y: 200))
            Self.choose("Half screen", in: c.view.menu(for: Self.mouse(.rightMouseDown, at, c)))
            #expect(a.canvasFrame == CGRect(x: 0, y: 0, width: 726, height: 909))
            #expect(a.preferredSize == a.canvasFrame.size)
            // B was in the way, and moved clear.
            #expect(!b.canvasFrame.intersects(a.canvasFrame))
            Self.choose("Quarter screen", in: c.view.menu(for: Self.mouse(.rightMouseDown, at, c)))
            #expect(a.canvasFrame == CGRect(x: 0, y: 0, width: 726, height: 444))
            Self.choose("Fill screen", in: c.view.menu(for: Self.mouse(.rightMouseDown, at, c)))
            #expect(a.canvasFrame == CGRect(x: 0, y: 0, width: 1472, height: 909))
        }
        // A window that sizes itself (a VM's) has the sizes greyed out.
        let vm = Fake.window(id: 7, bundleID: "com.utmapp.UTM", appName: "UTM", canvas: CGRect(x: 0, y: 0, width: 1024, height: 768))
        vm.needsFirstFrame = false
        let v = Self.zoomedOut([vm])
        NAVTests.onCanvas(v) {
            let menu = v.view.menu(for: Self.mouse(.rightMouseDown, v.camera.toView(CGPoint(x: 500, y: 300)), v))
            #expect(menu?.items.first { $0.title == "Fill screen" }?.isEnabled == false)
            #expect(menu?.items.first { $0.title == "Same size as…" }?.isEnabled == false)
        }
    }

    @Test("SIZE-17 Same size as…: the next window clicked gives its size")
    func size17SameSize() {
        let a = Self.win(1, 0, 0, 500, 400), b = Self.win(2, 2000, 0, 900, 700)
        let c = Self.zoomedOut([a, b])
        NAVTests.onCanvas(c) {
            Self.choose("Same size as…", in: c.view.menu(for: Self.mouse(.rightMouseDown, c.camera.toView(CGPoint(x: 250, y: 200)), c)))
            #expect(c.view.sizing === a)
            let onB = c.camera.toView(CGPoint(x: 2400, y: 300))
            c.view.mouseDown(with: Self.mouse(.leftMouseDown, onB, c))
            #expect(a.canvasFrame == CGRect(x: 0, y: 0, width: 900, height: 700))
            #expect(c.view.sizing == nil)
            // Esc instead of a click: nothing changes.
            Self.choose("Same size as…", in: c.view.menu(for: Self.mouse(.rightMouseDown, c.camera.toView(CGPoint(x: 250, y: 200)), c)))
            c.view.keyDown(with: Self.key(kVK_Escape))
            #expect(c.view.sizing == nil && c.isActive)
        }
    }

    @Test("SIZE-19 Back to its own size: the size it had before Expanse took it on")
    func size19() {
        let a = Self.win(1, 0, 0, 500, 400)
        a.originalFrame = CGRect(x: 300, y: 200, width: 820, height: 610)
        let c = Self.zoomedOut([a])
        NAVTests.onCanvas(c) {
            let at = c.camera.toView(CGPoint(x: 250, y: 200))
            Self.choose("Back to its own size", in: c.view.menu(for: Self.mouse(.rightMouseDown, at, c)))
            #expect(a.canvasFrame == CGRect(x: 0, y: 0, width: 820, height: 610))
            #expect(a.preferredSize == CGSize(width: 820, height: 610))
        }
    }

    @Test("SIZE-17 Right-click on empty canvas: Tidy up and Fit everything; at 100%, no menu")
    func size17Canvas() {
        let a = Self.win(1, 0, 0, 500, 400)
        let c = Self.zoomedOut([a])
        NAVTests.onCanvas(c) {
            let menu = c.view.menu(for: Self.mouse(.rightMouseDown, c.camera.toView(CGPoint(x: 3000, y: 3000)), c))
            #expect(menu?.items.map(\.title).contains("Tidy up") == true)
            #expect(menu?.items.map(\.title).contains("Fit everything") == true)
        }
        #expect(c.view.menu(for: Self.mouse(.rightMouseDown, .zero, c)) == nil)
    }
}
