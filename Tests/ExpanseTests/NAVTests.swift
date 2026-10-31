import Testing
import AppKit
import Carbon.HIToolbox
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "CanvasView.swift") @testable import Expanse
@_private(sourceFile: "Minimap.swift") @testable import Expanse

/// docs/regression/navigation.md: the camera, zooming, and getting about the canvas. This file:
/// camera targets and zoom (NAV-01 to NAV-17, NAV-32, NAV-46). NAVTests+Navigation: hops, focus and
/// the hot corner. NAVTests+Snap: the snap after a scroll at 100%.
///
/// Nothing here raises the overlay or touches a real window: "zoomed out" is `isActive` set on a
/// TestCanvas (see onCanvas), and a camera move is read from `animation` and stopped, never run.
@MainActor @Suite("NAV: Canvas, zoom and navigation", .serialized) struct NAVTests {

    // MARK: Zooming out

    @Test("NAV-01 ⌥` zooms out to every window, and back")
    func nav01() {
        let ws = [Self.win(1, -2000, -600, 800, 600), Self.win(2, 0, 0, 1000, 700), Self.win(3, 1800, 200, 900, 700),
                  Self.win(4, 3500, -900, 600, 500), Self.win(5, 900, 1400, 1200, 800)]
        let c = TestCanvas.make(windows: ws)
        let t = c.overviewCamera()
        #expect(t == c.fitCamera(maxScale: 0.6))
        // Every window in view, 80pt of canvas round them all, the lot centred.
        let all = Self.bounds(ws)
        #expect(Self.screen.insetBy(dx: 80 * t.scale - 0.01, dy: 80 * t.scale - 0.01).contains(t.toView(all)))
        #expect(Self.near(t.toView(all).center, Self.screen.center, 0.01))
        for w in ws { #expect(Self.screen.contains(t.toView(w.canvasFrame))) }
    }

    @Test("NAV-01 ⌥` again goes back to the 100% view you had (logic)")
    func nav01b() {
        let c = TestCanvas.make(windows: [Self.win(1, 0, 0, 800, 600), Self.win(2, 2500, 900, 800, 600)])
        let left = Camera(origin: CGPoint(x: 312, y: -45), scale: 1)
        Self.onCanvas(c) {
            // As enterNow leaves it: the view you left kept, the overview showing.
            c.returnCamera = left
            c.camera = c.overviewCamera()
            c.toggle()
            #expect(c.animation?.to == left)
            #expect(c.animation?.handsBack == true)
        }
    }

    @Test("NAV-02 Zooming out never goes past 60%")
    func nav02() {
        let c = TestCanvas.make(windows: [Self.win(1, 100, 100, 300, 200), Self.win(2, 420, 100, 300, 200)])
        let t = c.overviewCamera()
        #expect(t.scale == 0.6)
        #expect(Self.near(t.center(in: Self.viewSize), CGPoint(x: 410, y: 200)))
        // The minimap's figure.
        let m = Minimap()
        m.update(windows: c.windows.map(\.canvasFrame), viewport: t.toCanvas(Self.screen), scale: t.scale)
        #expect(m.zoomText.string as? String == "60%")
    }

    @Test("NAV-02 With many windows it zooms out as far as needed, 80pt margin, down to 3%")
    func nav02b() {
        let ws = [Self.win(1, -3000, -500, 900, 700), Self.win(2, 2000, 300, 900, 700), Self.win(3, 0, 1800, 800, 600)]
        let t = TestCanvas.make(windows: ws).overviewCamera()
        let b = Self.bounds(ws).insetBy(dx: -80, dy: -80)
        #expect(Self.near(t.scale, min(Self.viewSize.width / b.width, Self.viewSize.height / b.height)))
        #expect(Self.near(t.center(in: Self.viewSize), b.center))

        let far = TestCanvas.make(windows: [Self.win(4, -60_000, 0, 800, 600), Self.win(5, 60_000, 0, 800, 600)])
        #expect(far.overviewCamera().scale == Camera.minScale)
        #expect(Camera.minScale == 0.03)
    }

    // MARK: Zooming

    @Test("NAV-03 Pinch zooms around the pointer")
    func nav03() {
        var cam = Camera(origin: CGPoint(x: -500, y: 300), scale: 0.4)
        for (s, anchor) in [(0.8, CGPoint(x: 300, y: 200)), (0.25, CGPoint(x: 1200, y: 800)),
                            (1.1, CGPoint(x: 0, y: 0)), (0.05, CGPoint(x: 1511, y: 948))] as [(CGFloat, CGPoint)] {
            let under = cam.toCanvas(anchor)
            cam.zoom(to: s, anchor: anchor)
            #expect(cam.scale == s)
            #expect(Self.near(cam.toCanvas(anchor), under))
        }
    }

    @Test("NAV-03 A pinch on the canvas keeps the point under the pointer")
    func nav03b() {
        let c = TestCanvas.make(windows: [Self.win(1, 0, 0, 800, 600)])
        Self.onCanvas(c) {
            c.camera = Camera(origin: CGPoint(x: -900, y: -400), scale: 0.4)
            let pointer = CGPoint(x: 333, y: 222)
            let under = c.camera.toCanvas(pointer)
            // What CanvasView.magnify does with a pinch.
            c.zoom(by: 1 + 0.25, at: pointer)
            #expect(Self.near(c.camera.scale, 0.5))
            #expect(Self.near(c.camera.toCanvas(pointer), under))
            c.zoom(by: 1 - 0.4, at: pointer)
            #expect(Self.near(c.camera.scale, 0.3))
            #expect(Self.near(c.camera.toCanvas(pointer), under))
        }
    }

    @Test("NAV-04 ⌘ + scroll zooms around the pointer (logic)")
    func nav04() throws {
        let c = TestCanvas.make(windows: [Self.win(1, 0, 0, 800, 600)])
        try Self.onCanvas(c) {
            let trackpad = try #require(Self.scroll(12, precise: true, command: true))
            let wheel = try #require(Self.scroll(1, precise: false, command: true))
            try #require(trackpad.hasPreciseScrollingDeltas && !wheel.hasPreciseScrollingDeltas)
            var perDelta: [CGFloat] = []
            for e in [trackpad, wheel] {
                try #require(e.scrollingDeltaY != 0)
                c.camera = Camera(origin: CGPoint(x: -900, y: -400), scale: 0.4)
                let pointer = c.view.point(e)
                let under = c.camera.toCanvas(pointer)
                c.view.scrollWheel(with: e)
                #expect(c.camera.scale != 0.4)
                // Zoomed around the pointer, and no pan on top.
                #expect(Self.near(c.camera.toCanvas(pointer), under, 0.01))
                // Nor a scroll's snap afterwards (see NAV-54).
                #expect(c.view.scrollEnd == nil)
                perDelta.append(log(c.camera.scale / 0.4) / e.scrollingDeltaY)
            }
            // A wheel zooms in bigger steps than the trackpad.
            #expect(perDelta[1] > perDelta[0] * 5)
        }
    }

    @Test("NAV-05 Zoom stops at 3% and 150%")
    func nav05() {
        #expect(Camera.minScale == 0.03 && Camera.maxScale == 1.5)
        let anchor = CGPoint(x: 700, y: 400)
        var cam = Camera(origin: CGPoint(x: 40, y: -70), scale: 0.1)
        cam.zoom(to: 0.001, anchor: anchor)
        #expect(cam.scale == 0.03)
        let out = cam
        cam.zoom(to: cam.scale / 1.5, anchor: anchor) // further input does nothing
        #expect(Self.near(cam, out))
        cam.zoom(to: 40, anchor: anchor)
        #expect(cam.scale == 1.5)
        let inn = cam
        cam.zoom(to: cam.scale * 1.5, anchor: anchor)
        #expect(Self.near(cam, inn))
        // The minimap's figure at each end.
        let m = Minimap()
        for (scale, figure) in [(Camera.minScale, "3%"), (Camera.maxScale, "150%")] {
            m.update(windows: [CGRect(x: 0, y: 0, width: 800, height: 600)], viewport: Self.screen, scale: scale)
            #expect(m.zoomText.string as? String == figure)
        }
    }

    @Test("NAV-06 Two-finger double-tap swaps between the overview and 100%")
    func nav06() {
        let c = TestCanvas.make(windows: [Self.win(1, 0, 0, 800, 600), Self.win(2, 2400, 1200, 900, 700)])
        Self.onCanvas(c) {
            c.camera = Camera(origin: CGPoint(x: -1500, y: -900), scale: 0.3)
            let pointer = CGPoint(x: 400, y: 300)
            let under = c.camera.toCanvas(pointer)
            c.toggleOverview(at: pointer)
            let in100 = c.animation?.to
            #expect(in100?.scale == 1)
            #expect(in100.map { Self.near($0.toCanvas(pointer), under, 0.01) } == true)
            // Staying on the canvas: no window entered, nothing handed back.
            #expect(c.animation?.handsBack == false)
            #expect(c.isActive && !c.gliding)
            // At 100% (95% and up), back out to the overview.
            c.cancelAnimation()
            c.camera = in100 ?? c.camera
            c.toggleOverview(at: pointer)
            #expect(c.animation?.to == c.overviewCamera())
            c.cancelAnimation()
            c.camera.zoom(to: 0.96, anchor: pointer)
            c.toggleOverview(at: pointer)
            #expect(c.animation?.to == c.overviewCamera())
            c.cancelAnimation()
            c.camera.zoom(to: 0.94, anchor: pointer)
            c.toggleOverview(at: pointer)
            #expect(c.animation?.to.scale == 1)
        }
    }

    @Test("NAV-08 0 fits every window")
    func nav08() {
        let small = [Self.win(1, 100, 100, 300, 200), Self.win(2, 420, 100, 300, 200)]
        let c = TestCanvas.make(windows: small)
        c.camera = Camera(origin: CGPoint(x: -4000, y: 2500), scale: 0.2) // panned and zoomed away
        let t = c.fitCamera()
        #expect(t.scale == 1) // up to 100%, unlike the overview's 60%
        #expect(Self.near(t.center(in: Self.viewSize), CGPoint(x: 410, y: 200)))

        let spread = small + [Self.win(3, -3000, -800, 900, 700), Self.win(4, 2500, 1600, 800, 600)]
        let d = TestCanvas.make(windows: spread)
        let f = d.fitCamera()
        #expect(f.scale < 1)
        #expect(Self.screen.insetBy(dx: 80 * f.scale - 0.01, dy: 80 * f.scale - 0.01).contains(f.toView(Self.bounds(spread))))
    }

    @Test("NAV-08 Pressing 0 on the canvas animates to the fit")
    func nav08b() {
        let c = TestCanvas.make(windows: [Self.win(1, -3000, -800, 900, 700), Self.win(2, 2500, 1600, 800, 600)])
        Self.onCanvas(c) {
            c.camera = Camera(origin: CGPoint(x: 9000, y: 9000), scale: 0.5)
            c.returnCamera = Camera()
            c.view.keyDown(with: Self.key(kVK_ANSI_0))
            #expect(c.animation?.to == c.fitCamera())
            // Kept: leaving still goes back to the window you were in (NAV-17).
            #expect(c.returnCamera == Camera())
        }
    }

    @Test("NAV-09 1 goes to 100% on the canvas")
    func nav09() {
        let c = TestCanvas.make(windows: [Self.win(1, 0, 0, 800, 600), Self.win(2, 2400, 1200, 900, 700)])
        Self.onCanvas(c) {
            for go in [{ c.zoomAnimated(to: 1) }, { c.view.keyDown(with: Self.key(kVK_ANSI_1)) }] {
                c.cancelAnimation()
                c.camera = Camera(origin: CGPoint(x: -1500, y: -900), scale: 0.3)
                let middle = c.camera.center(in: Self.viewSize)
                go()
                let to = c.animation?.to
                #expect(to?.scale == 1)
                // Around the middle of the screen.
                #expect(to.map { Self.near($0.center(in: Self.viewSize), middle, 0.01) } == true)
                // Still the canvas: nothing handed back to the real windows.
                #expect(c.animation?.handsBack == false)
                #expect(c.isActive && !c.gliding)
            }
        }
    }

    @Test("NAV-10 - and = zoom out and in by steps")
    func nav10() {
        let middle = CGPoint(x: Self.viewSize.width / 2, y: Self.viewSize.height / 2)
        let start = Camera(origin: CGPoint(x: -1200, y: -700), scale: 0.4)
        var cam = start
        cam.zoom(to: cam.scale / 1.5, anchor: middle)
        cam.zoom(to: cam.scale / 1.5, anchor: middle)
        #expect(Self.near(cam.scale, 0.4 / 2.25))
        #expect(Self.near(cam.center(in: Self.viewSize), start.center(in: Self.viewSize)))
        cam.zoom(to: cam.scale * 1.5, anchor: middle)
        cam.zoom(to: cam.scale * 1.5, anchor: middle)
        #expect(Self.near(cam, start))
        // Within 3%-150%.
        var low = Camera(origin: .zero, scale: 0.04)
        low.zoom(to: low.scale / 1.5, anchor: middle)
        #expect(low.scale == Camera.minScale)
        var high = Camera(origin: .zero, scale: 1.2)
        high.zoom(to: high.scale * 1.5, anchor: middle)
        #expect(high.scale == Camera.maxScale)
    }

    @Test("NAV-10 The - and = keys animate a step around the middle of the screen")
    func nav10b() throws {
        let c = TestCanvas.make(windows: [Self.win(1, 0, 0, 800, 600)])
        try #require(c.view.bounds.size == Self.viewSize)
        Self.onCanvas(c) {
            let start = Camera(origin: CGPoint(x: -1200, y: -700), scale: 0.4)
            for (key, factor) in [(kVK_ANSI_Minus, 1 / 1.5), (kVK_ANSI_Equal, 1.5)] as [(Int, CGFloat)] {
                c.cancelAnimation()
                c.camera = start
                c.returnCamera = Camera()
                c.view.keyDown(with: Self.key(key))
                let to = c.animation?.to
                #expect(to.map { Self.near($0.scale, 0.4 * factor) } == true)
                #expect(to.map { Self.near($0.center(in: Self.viewSize), start.center(in: Self.viewSize), 0.01) } == true)
                #expect(c.returnCamera == Camera()) // kept (NAV-17)
            }
        }
    }

    @Test("NAV-11 Esc goes back to the 100% view you left (logic)")
    func nav11() {
        let a = Self.win(1, 0, 0, 800, 600)
        let c = TestCanvas.make(windows: [a, Self.win(2, 2400, 1200, 900, 700)])
        let left = Camera(origin: CGPoint(x: -88, y: 140), scale: 1)
        Self.onCanvas(c) {
            c.returnCamera = left
            c.camera = c.overviewCamera()
            c.view.keyDown(with: Self.key(kVK_Escape))
            #expect(c.animation?.to == left)
            #expect(c.animation?.handsBack == true)
            // With a selection, the first Esc clears it instead (EDIT-12).
            c.cancelAnimation()
            c.view.selected = [a.id]
            c.view.keyDown(with: Self.key(kVK_Escape))
            #expect(c.view.selected.isEmpty)
            #expect(c.animation == nil)
        }
    }

    // MARK: Going to a window

    @Test("NAV-12 Click a window on the canvas to glide to it and use it")
    func nav12() {
        let w = Self.win(1, 3000, -1200, 800, 600)
        let c = TestCanvas.make(windows: [w])
        let t = c.focusCamera(for: w)
        #expect(t.scale == 1)
        // Centred (to the nearest point: the camera's origin is whole points).
        #expect(Self.near(t.toView(w.canvasFrame).center, Self.screen.center, 0.5))
        // Taller than the screen: top-aligned, still centred across.
        let tall = Self.win(2, -700, 400, 900, 1400)
        let top = TestCanvas.make(windows: [tall]).focusCamera(for: tall)
        #expect(top.toView(tall.canvasFrame).minY == 0)
        #expect(Self.near(top.toView(tall.canvasFrame).midX, Self.screen.midX, 0.5))
    }

    @Test("NAV-12 Clicking a window zooms in onto it, in about a fifth of a second (logic)")
    func nav12b() {
        Env.withDefaults(["animationSlowdown": nil]) {
            let w = Self.win(1, 3000, -1200, 800, 600)
            let c = TestCanvas.make(windows: [w, Self.win(2, 0, 0, 800, 600)])
            Self.onCanvas(c) {
                c.camera = c.overviewCamera()
                c.exit(focus: w)
                #expect(c.animation?.to == c.focusCamera(for: w))
                #expect(c.animation.map { Self.near($0.duration, 0.18) } == true)
                #expect(c.animation?.handsBack == true)
            }
        }
    }

    @Test("NAV-13 The minimap moves the zoomed-out view")
    func nav13() {
        let frames = [CGRect(x: -800, y: -300, width: 700, height: 500), CGRect(x: 400, y: 200, width: 1000, height: 700),
                      CGRect(x: 2600, y: 1300, width: 600, height: 400)]
        let viewport = Camera(origin: CGPoint(x: -1500, y: -600), scale: 0.2).toCanvas(Self.screen)
        let m = Minimap()
        m.update(windows: frames, viewport: viewport, scale: 0.2)
        // A point on the map goes back to the canvas point drawn there (the map is y-up).
        for r in frames + [viewport] {
            let drawn = m.toMap(r)
            #expect(Self.near(m.canvasPoint(at: CGPoint(x: drawn.minX, y: drawn.maxY)), r.origin, 0.01))
            #expect(Self.near(m.canvasPoint(at: CGPoint(x: drawn.maxX, y: drawn.minY)), CGPoint(x: r.maxX, y: r.maxY), 0.01))
        }
    }

    @Test("NAV-13 A minimap click centres the view there, at the same zoom, moving no window")
    func nav13b() {
        let ws = [Self.win(1, -800, -300, 700, 500), Self.win(2, 2600, 1300, 600, 400)]
        let c = TestCanvas.make(windows: ws)
        Self.onCanvas(c) {
            c.camera = Camera(origin: CGPoint(x: -1500, y: -600), scale: 0.2)
            c.returnCamera = Camera()
            let frames = c.windows.map(\.canvasFrame)
            c.center(on: CGPoint(x: 2100, y: 1250))
            #expect(c.camera.scale == 0.2)
            #expect(Self.near(c.camera.center(in: Self.viewSize), CGPoint(x: 2100, y: 1250), 0.01))
            #expect(c.windows.map(\.canvasFrame) == frames)
            #expect(c.view.selected.isEmpty)
            #expect(c.returnCamera == Camera()) // kept (NAV-17)
        }
    }

    @Test("NAV-14 Click a parked window's picture at 100% to go to it (logic)")
    func nav14() {
        Env.withDefaults(["animationSlowdown": nil]) {
            let parked = Self.win(1, 1400, 300, 800, 600)
            parked.parked = true
            let shown = Self.win(2, 200, 100, 800, 600)
            let c = TestCanvas.make(windows: [parked, shown])
            // The parked window's picture at the right edge; a click elsewhere isn't on one.
            #expect(c.window(atView: CGPoint(x: 1450, y: 400), parkedOnly: true) === parked)
            #expect(c.window(atView: CGPoint(x: 300, y: 200), parkedOnly: true) == nil)
            #expect(c.window(atView: CGPoint(x: 300, y: 200)) === shown)
            // Going to it is a glide (gliding is set beforehand so it doesn't raise the overlay).
            Self.onCanvas(c, active: false, gliding: true) {
                c.focus(parked)
                #expect(c.glideTarget === parked)
                #expect(c.animation?.to == c.focusCamera(for: parked))
                #expect(c.animation.map { Self.near($0.duration, 0.3) } == true)
            }
        }
    }

    // MARK: Moving about zoomed out

    @Test("NAV-15 Two-finger scroll pans the canvas and moves no window (logic)")
    func nav15() throws {
        let c = TestCanvas.make(windows: [Self.win(1, 0, 0, 800, 600), Self.win(2, 1200, 900, 800, 600)])
        try Self.onCanvas(c) {
            let e = try #require(Self.scroll(-30, dx: 20, precise: true))
            try #require(e.scrollingDeltaX != 0 && e.scrollingDeltaY != 0)
            c.camera = Camera(origin: CGPoint(x: -900, y: -400), scale: 0.5)
            let frames = c.windows.map(\.canvasFrame)
            let p = CGPoint(x: 100, y: 100)
            let before = c.camera.toView(p)
            c.view.scrollWheel(with: e)
            let after = c.camera.toView(p)
            #expect(c.camera.scale == 0.5)
            // The canvas moves with the fingers.
            #expect(Self.near(after.x - before.x, e.scrollingDeltaX) && Self.near(after.y - before.y, e.scrollingDeltaY))
            #expect(c.windows.map(\.canvasFrame) == frames)
        }
    }

    @Test("NAV-17 After moving around zoomed out, leaving goes back to the window you were in (logic)")
    func nav17() {
        let c = TestCanvas.make(windows: [Self.win(1, 0, 0, 800, 600), Self.win(2, 3000, 1500, 800, 600)])
        let left = Camera(origin: CGPoint(x: 100, y: 50), scale: 1)
        Self.onCanvas(c) {
            let moves: [(String, () -> Void)] = [
                ("pan", { c.pan(by: CGVector(dx: -300, dy: 120)) }),
                ("pinch or ⌘-scroll", { c.zoom(by: 1.3, at: CGPoint(x: 200, y: 700)) }),
                ("0", { c.view.keyDown(with: Self.key(kVK_ANSI_0)) }),
                ("1", { c.view.keyDown(with: Self.key(kVK_ANSI_1)) }),
                ("-", { c.view.keyDown(with: Self.key(kVK_ANSI_Minus)) }),
                ("=", { c.view.keyDown(with: Self.key(kVK_ANSI_Equal)) }),
                ("minimap", { c.center(on: CGPoint(x: 2000, y: 900)) }),
                ("double-tap", { c.toggleOverview(at: CGPoint(x: 600, y: 400)) }),
            ]
            for (name, move) in moves {
                c.cancelAnimation()
                c.returnCamera = left // as zooming out leaves it
                c.returnWindow = c.windows[0]
                c.returnFrame = c.windows[0].canvasFrame
                c.camera = c.overviewCamera()
                move()
                if let to = c.animation?.to { c.cancelAnimation(); c.camera = to } // landed
                c.exit()
                // You didn't pick anywhere else: back to the view you left, however you moved around.
                #expect(c.animation?.to == left, "after \(name)")
            }
        }
    }

    @Test("NAV-17 Leaving goes back to the window you were in, centred where it is now if it moved (logic)")
    func nav17b() {
        let a = Self.win(1, 0, 0, 800, 600)
        let c = TestCanvas.make(windows: [a, Self.win(2, 3000, 1500, 800, 600)])
        Self.onCanvas(c) {
            c.returnCamera = Camera(origin: CGPoint(x: -356, y: -174), scale: 1)
            c.returnWindow = a
            c.returnFrame = a.canvasFrame
            c.camera = c.overviewCamera()
            // Dragged (or tidied) while zoomed out.
            a.canvasFrame.origin = CGPoint(x: 1200, y: 400)
            c.exit()
            #expect(c.animation?.to == c.focusCamera(for: a))
            #expect(!c.viewPlaced)
            // A view you'd placed yourself comes back placed, so its window, cut off, isn't glided to.
            c.cancelAnimation()
            c.isActive = true
            a.canvasFrame.origin = CGPoint(x: 0, y: 0)
            c.returnFrame = a.canvasFrame
            c.returnPlaced = true
            c.viewPlaced = false
            c.exit()
            #expect(c.animation?.to == c.returnCamera)
            #expect(c.viewPlaced)
        }
    }

    @Test("NAV-32 Zooming out and straight back returns to the same view (logic)")
    func nav32() {
        Env.withDefaults(["animationSlowdown": nil]) {
            let c = TestCanvas.make(windows: [Self.win(1, 0, 0, 800, 600), Self.win(2, 2400, 1200, 900, 700)])
            let left = Camera(origin: CGPoint(x: 140, y: -60), scale: 1)
            Self.onCanvas(c) {
                // Zooming out (enterNow) takes about 0.22s...
                c.animate(to: c.overviewCamera())
                #expect(c.animation.map { Self.near($0.duration, 0.22) } == true)
                c.cancelAnimation()
                // ...and, without a pan or zoom since, back to exactly the view you left in 0.18s.
                c.returnCamera = left
                c.camera = c.overviewCamera()
                c.exit()
                #expect(c.animation?.to == left)
                #expect(c.animation.map { Self.near($0.duration, 0.18) } == true)
            }
        }
    }

    @Test("NAV-46 animationSlowdown makes camera moves slower (logic)")
    func nav46() {
        for (value, duration) in [(3.0, 0.9), (0.5, 0.3), (nil, 0.3)] as [(Double?, Double)] {
            Env.withDefaults(["animationSlowdown": value]) {
                let c = TestCanvas.make()
                c.animate(to: Camera(origin: CGPoint(x: 500, y: 0), scale: 1), duration: 0.3)
                defer { c.cancelAnimation() }
                #expect(c.animation.map { Self.near($0.duration, duration) } == true, "animationSlowdown \(String(describing: value))")
            }
        }
    }
}

// MARK: Helpers

extension NAVTests {
    /// TestDisplay.laptop's view: the screen less its 33pt menu bar.
    static let viewSize = CGSize(width: 1512, height: 949)
    static var screen: CGRect { CGRect(origin: .zero, size: viewSize) }

    /// A fake window at this canvas frame. It wants no first picture, so nothing asks
    /// ScreenCaptureKit for one.
    static func win(_ id: CGWindowID, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> ManagedWindow {
        let m = Fake.window(id: id, canvas: CGRect(x: x, y: y, width: w, height: h))
        m.needsFirstFrame = false
        return m
    }

    static func bounds(_ ws: [ManagedWindow]) -> CGRect {
        ws.dropFirst().reduce(ws[0].canvasFrame) { $0.union($1.canvasFrame) }
    }

    /// Runs `body` with `c` zoomed out as far as it knows (`isActive`), but no overlay on screen.
    /// Meanwhile nothing is asked of ScreenCaptureKit (as when replayd is stuck), so the fake
    /// windows get no streams or pictures; afterwards any camera move is stopped. `gliding`: a
    /// glide under way, so one started meanwhile doesn't raise the overlay either.
    static func onCanvas(_ c: CanvasController, active: Bool = true, gliding: Bool = false, _ body: () throws -> Void) rethrows {
        let stuck = WindowCapture.replaydStuck
        WindowCapture.replaydStuck = true
        c.isActive = active
        c.gliding = gliding
        defer {
            c.cancelAnimation()
            c.isActive = false
            c.gliding = false
            c.glideTarget = nil
            WindowCapture.replaydStuck = stuck
        }
        try body()
    }

    static func key(_ code: Int) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code))!
    }

    /// A scroll event (never posted): trackpad-like (`precise`, in points) or a wheel's lines.
    static func scroll(_ dy: Int32, dx: Int32 = 0, precise: Bool, command: Bool = false) -> NSEvent? {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 2,
                               wheel1: dy, wheel2: dx, wheel3: 0) else { return nil }
        cg.flags = command ? .maskCommand : []
        return NSEvent(cgEvent: cg)
    }

    static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.001) -> Bool { abs(a - b) <= tolerance }
    static func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 0.001) -> Bool {
        near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance)
    }
    static func near(_ a: Camera, _ b: Camera, _ tolerance: CGFloat = 0.001) -> Bool {
        near(a.origin, b.origin, tolerance) && near(a.scale, b.scale, tolerance / 1000)
    }
}
