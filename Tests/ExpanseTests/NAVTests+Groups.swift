import Testing
import AppKit
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "CanvasView.swift") @testable import Expanse

/// NAV cases about screen groups: windows you've arranged to fit the screen at 100%, treated as one
/// place (NAV-55 to NAV-60).
extension NAVTests {

    /// B and C side by side, a gap apart, together 1220pt wide: a group on the 1512pt screen. A is
    /// on its own, far to the left.
    static func groupLayout() -> (a: ManagedWindow, b: ManagedWindow, c: ManagedWindow) {
        (win(21, -3000, 0, 600, 400), win(22, 0, 0, 600, 400), win(23, 620, 0, 600, 400))
    }

    /// The camera that frames `frame` at 100%: centred on it.
    static func framing(_ frame: CGRect) -> Camera {
        Camera(origin: CGPoint(x: (frame.midX - viewSize.width / 2).rounded(), y: (frame.midY - viewSize.height / 2).rounded()), scale: 1)
    }

    @Test("NAV-55 Windows a gap apart that fit the screen together are a group")
    func nav55() {
        let w: CGFloat = 600, h: CGFloat = 400
        func pair(_ gap: CGFloat) -> [CGRect] { [CGRect(x: 0, y: 0, width: w, height: h), CGRect(x: w + gap, y: 0, width: w, height: h)] }
        #expect(CanvasController.screenGroups(pair(20), fitting: Self.viewSize) == [[0, 1]])
        #expect(CanvasController.screenGroups(pair(39), fitting: Self.viewSize) == [[0, 1]])
        #expect(CanvasController.screenGroups(pair(41), fitting: Self.viewSize).isEmpty)
        // One above the other counts too.
        let stacked = [CGRect(x: 0, y: 0, width: 900, height: 440), CGRect(x: 0, y: 460, width: 900, height: 440)]
        #expect(CanvasController.screenGroups(stacked, fitting: Self.viewSize) == [[0, 1]])
        // A window on its own isn't a group.
        #expect(CanvasController.screenGroups([CGRect(x: 0, y: 0, width: w, height: h)], fitting: Self.viewSize).isEmpty)
        // Three in a row, through a chain of neighbours, when they fit (3 × 480 + 2 × 20 = 1480)...
        let three = (0..<3).map { CGRect(x: CGFloat($0) * 500, y: 0, width: 480, height: 400) }
        #expect(CanvasController.screenGroups(three, fitting: Self.viewSize) == [[0, 1, 2]])
        // ...but not when they don't (3 × 600 + 2 × 20 = 1840): then none of them is.
        let wide = (0..<3).map { CGRect(x: CGFloat($0) * 620, y: 0, width: 600, height: 400) }
        #expect(CanvasController.screenGroups(wide, fitting: Self.viewSize).isEmpty)
        // Two groups far apart are two.
        let two = pair(20) + pair(20).map { $0.offsetBy(dx: 5000, dy: 0) }
        #expect(CanvasController.screenGroups(two, fitting: Self.viewSize) == [[0, 1], [2, 3]])
        // On the canvas: B and C are a group, A isn't in one.
        let (a, b, c) = Self.groupLayout()
        let canvas = TestCanvas.make(windows: [a, b, c])
        #expect(canvas.screenGroup(of: b).map { $0.map(\.id) } == [22, 23])
        #expect(canvas.screenGroup(of: c).map { $0.map(\.id) } == [22, 23])
        #expect(canvas.screenGroup(of: a) == nil)
    }

    @Test("NAV-55 Going to a window in a group frames the group; a window on its own is centred")
    func nav55b() {
        let (a, b, c) = Self.groupLayout()
        let canvas = TestCanvas.make(windows: [a, b, c])
        let outline = CGRect(x: 0, y: 0, width: 1220, height: 400)
        #expect(canvas.viewCamera(for: b) == Self.framing(outline))
        #expect(canvas.viewCamera(for: c) == Self.framing(outline))
        #expect(canvas.viewCamera(for: a) == canvas.focusCamera(for: a))
        // Framed, all of it shows.
        let shown = canvas.viewCamera(for: b).toView(outline)
        #expect(Self.screen.contains(shown))
    }

    @Test("NAV-56 A hop to a window in a group glides to frame the whole group (logic)")
    func nav56() {
        Env.withDefaults(["animationSlowdown": nil]) {
            let (a, b, c) = Self.groupLayout()
            let canvas = TestCanvas.make(windows: [a, b, c])
            Self.onCanvas(canvas, gliding: true) {
                canvas.glideTarget = a // a glide to A under way: the next hop starts from A
                canvas.navigate(.right)
                #expect(canvas.glideTarget === b)
                #expect(canvas.animation?.to == Self.framing(CGRect(x: 0, y: 0, width: 1220, height: 400)))
            }
        }
    }

    @Test("NAV-57 Hops between the windows of a group on screen only move focus (logic)")
    func nav57() {
        let (a, b, c) = Self.groupLayout()
        let canvas = TestCanvas.make(windows: [a, b, c])
        canvas.camera = canvas.viewCamera(for: b)
        #expect(canvas.hopStaysInGroup(to: c, from: b.canvasFrame))
        #expect(canvas.hopStaysInGroup(to: b, from: c.canvasFrame))
        // From a window outside the group, a hop to one in it goes there (and frames it).
        #expect(!canvas.hopStaysInGroup(to: b, from: a.canvasFrame))
        // With part of the group off screen, it glides to frame it.
        canvas.camera = canvas.focusCamera(for: b)
        #expect(!canvas.hopStaysInGroup(to: c, from: b.canvasFrame))
        // A window on its own has no group to stay in.
        #expect(!canvas.hopStaysInGroup(to: a, from: b.canvasFrame))
    }

    @Test("NAV-58 Clicking a window in a group zoomed out zooms to the group (logic)")
    func nav58() {
        let (a, b, c) = Self.groupLayout()
        let canvas = TestCanvas.make(windows: [a, b, c])
        Self.onCanvas(canvas) {
            canvas.camera = canvas.overviewCamera()
            canvas.exit(focus: c) // what a click on C (or Return with it hovered) does
            #expect(canvas.animation?.to == Self.framing(CGRect(x: 0, y: 0, width: 1220, height: 400)))
            #expect(canvas.animation?.handsBack == true)
            canvas.cancelAnimation()
            canvas.isActive = true
            canvas.camera = canvas.overviewCamera()
            canvas.exit(focus: a)
            #expect(canvas.animation?.to == canvas.focusCamera(for: a))
        }
    }

    @Test("NAV-59 ⌃⌥C frames the group of the window you're in (logic)")
    func nav59() {
        Env.withDefaults(["animationSlowdown": nil]) {
            let (a, b, c) = Self.groupLayout()
            let canvas = TestCanvas.make(windows: [a, b, c])
            // At 100% (a glide already under way, so nothing comes on screen): ⌃⌥C's glide.
            Self.onCanvas(canvas, active: false, gliding: true) {
                canvas.camera = canvas.focusCamera(for: a)
                canvas.focus(c)
                #expect(canvas.animation?.to == Self.framing(CGRect(x: 0, y: 0, width: 1220, height: 400)))
            }
            // Zoomed out: back to 100% on it, its group framed.
            Self.onCanvas(canvas) {
                canvas.camera = canvas.overviewCamera()
                canvas.focus(b)
                #expect(canvas.animation?.to == Self.framing(CGRect(x: 0, y: 0, width: 1220, height: 400)))
            }
        }
    }

    @Test("NAV-60 Zoomed out, hovering a window in a group outlines the group")
    func nav60() {
        let (a, b, c) = Self.groupLayout()
        let canvas = TestCanvas.make(windows: [a, b, c])
        Self.onCanvas(canvas) {
            canvas.camera = canvas.overviewCamera()
            let v = canvas.view
            v.hovered = b
            v.render()
            let box = v.groupOutline.path?.boundingBox
            let around = canvas.camera.toView(CGRect(x: 0, y: 0, width: 1220, height: 400)).insetBy(dx: -12, dy: -12)
            #expect(box.map { Self.near($0.width, around.width, 0.5) && Self.near($0.height, around.height, 0.5) } == true)
            // A window on its own: no outline.
            v.hovered = a
            v.render()
            #expect(v.groupOutline.path == nil)
            // Nothing hovered, or a selection of several (its own box shows): none either.
            v.hovered = nil
            v.render()
            #expect(v.groupOutline.path == nil)
            v.hovered = b
            v.selected = [b.id, a.id]
            v.render()
            #expect(v.groupOutline.path == nil)
            v.selected = []
            v.hovered = nil
        }
        // At 100% nothing's drawn over the real windows.
        canvas.view.hovered = b
        canvas.view.render()
        #expect(canvas.view.groupOutline.path == nil)
        canvas.view.hovered = nil
    }
}
