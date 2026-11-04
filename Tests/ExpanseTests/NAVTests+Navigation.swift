import Testing
import AppKit
import Carbon.HIToolbox
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "CanvasView.swift") @testable import Expanse
@_private(sourceFile: "HotCorner.swift") @testable import Expanse
@_private(sourceFile: "AppDelegate.swift") @testable import Expanse

/// NAV cases about getting from window to window: arrow keys and hops, focus and auto-centre,
/// centring, the hot corner.
extension NAVTests {

    // MARK: Nearest window that way

    @Test("NAV-16 On the canvas, arrow keys move a highlight and Return dives in")
    func nav16() {
        let f = Self.row().map(\.canvasFrame) // A B C in a row, D under B
        #expect(CanvasController.nearest(.right, from: f[0], in: f) == 1)
        #expect(CanvasController.nearest(.down, from: f[1], in: f) == 3)
        #expect(CanvasController.nearest(.up, from: f[3], in: f) == 1)
        #expect(CanvasController.nearest(.left, from: f[1], in: f) == 0)
        #expect(CanvasController.nearest(.left, from: f[0], in: f) == nil)
        #expect(CanvasController.nearest(.up, from: f[0], in: f) == nil)
    }

    @Test("NAV-16 Each arrow highlights the next window and pans to it without changing zoom")
    func nav16b() {
        let ws = Self.row()
        let (a, b, d) = (ws[0], ws[1], ws[3])
        let c = TestCanvas.make(windows: ws)
        Self.onCanvas(c) {
            c.camera = Camera(origin: CGPoint(x: -1000, y: -800), scale: 0.35)
            c.view.hovered = a
            for (key, target) in [(kVK_RightArrow, b), (kVK_DownArrow, d), (kVK_UpArrow, b), (kVK_LeftArrow, a)] {
                c.view.keyDown(with: Self.key(key))
                #expect(c.view.hovered === target)
                #expect(c.animation?.to == Camera.centered(on: target.canvasFrame.center, scale: 0.35, viewSize: Self.viewSize))
                #expect(c.isActive && !c.gliding)
                c.cancelAnimation() // the pan lands
            }
        }
    }

    @Test("NAV-26 ⌃ + arrow keys hop to the next window that way")
    func nav26() {
        let f = Self.row().map(\.canvasFrame)
        // From A: ⌃→ B, ⌃→ C, ⌃← B, ⌃↓ D.
        #expect(CanvasController.nearest(.right, from: f[0], in: f) == 1)
        #expect(CanvasController.nearest(.right, from: f[1], in: f) == 2)
        #expect(CanvasController.nearest(.left, from: f[2], in: f) == 1)
        #expect(CanvasController.nearest(.down, from: f[1], in: f) == 3)
    }

    @Test("NAV-27 Arrow hops prefer windows in the same row or column")
    func nav27() {
        let a = CGRect(x: 0, y: 0, width: 600, height: 400)
        let b = CGRect(x: 1400, y: 0, width: 600, height: 400) // level with A, 800pt to its right
        // 60pt to the right of A, overlapping a quarter of its height, 30° above level.
        let c = CGRect(x: 660, y: -300, width: 500, height: 400)
        #expect(CanvasController.nearest(.right, from: a, in: [a, b, c]) == 1)
        #expect(CanvasController.nearest(.right, from: a, in: [a, c, b]) == 2)
        // B closed: C counts, being within 35° of straight right...
        #expect(CanvasController.nearest(.right, from: a, in: [a, c]) == 1)
        // ...but not further up (50°), nor one mostly above and barely to the right.
        let high = CGRect(x: 660, y: -700, width: 500, height: 400)
        let above = CGRect(x: 100, y: -500, width: 600, height: 400)
        #expect(CanvasController.nearest(.right, from: a, in: [a, high]) == nil)
        #expect(CanvasController.nearest(.right, from: a, in: [a, above]) == nil)
    }

    @Test("NAV-35 Equal gaps: the hop goes to the better-aligned window")
    func nav35() {
        let a = CGRect(x: 0, y: 0, width: 600, height: 400)
        // Both 20pt below A, side by side; B's centre nearer A's.
        let b = CGRect(x: -100, y: 420, width: 500, height: 400)
        let c = CGRect(x: 420, y: 420, width: 500, height: 400)
        #expect(CanvasController.nearest(.down, from: a, in: [a, b, c]) == 1)
        #expect(CanvasController.nearest(.down, from: a, in: [a, c, b]) == 2)
    }

    // MARK: Hops and glides

    @Test("NAV-28 A hop pressed during a glide carries on from where it was heading (logic)")
    func nav28() {
        Env.withDefaults(["animationSlowdown": nil]) {
            let ws = (0..<4).map { Self.win(CGWindowID(1 + $0), CGFloat($0) * 820, 0, 800, 600) } // A B C D
            let c = TestCanvas.make(windows: ws)
            Self.onCanvas(c, gliding: true) {
                c.glideTarget = ws[0] // a glide to A under way
                for next in ws.dropFirst() {
                    let generation = c.glideGeneration
                    c.navigate(.right)
                    // Re-aimed at once, on from the window it was heading to.
                    #expect(c.glideTarget === next)
                    #expect(c.animation?.to == c.focusCamera(for: next))
                    #expect(c.animation.map { Self.near($0.duration, 0.3) } == true)
                    // Each hop a new generation: only the newest one hands back.
                    #expect(c.glideGeneration == generation + 1)
                    #expect(c.gliding)
                }
            }
        }
    }

    @Test("NAV-29 Scrolls, clicks and the canvas toggle can't cut a glide short (logic)")
    func nav29() throws {
        let ws = [Self.win(1, 0, 0, 800, 600), Self.win(2, 2400, 0, 800, 600)]
        let c = TestCanvas.make(windows: ws)
        try Self.onCanvas(c, gliding: true) {
            c.glideTarget = ws[1]
            c.animate(to: c.focusCamera(for: ws[1]), duration: 0.3)
            let heading = c.animation?.to, camera = c.camera
            let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 300, y: 300), modifierFlags: [],
                                                         timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                         clickCount: 1, pressure: 1))
            c.toggle() // ⌥`, or the hot corner
            c.view.scrollWheel(with: try #require(Self.scroll(-40, precise: true)))
            c.view.mouseDown(with: click)
            for k in [kVK_Escape, kVK_ANSI_1, kVK_ANSI_Minus, kVK_ANSI_0] { c.view.keyDown(with: Self.key(k)) }
            #expect(c.animation?.to == heading)
            #expect(c.animation?.handsBack == false)
            #expect(c.camera == camera)
            #expect(c.isActive && c.gliding)
            #expect(c.glideTarget === ws[1])
        }
    }

    @Test("NAV-33 Menu, link and Tidy actions wait for a glide to land")
    func nav33() async throws {
        let c = TestCanvas.make()
        var ran = 0
        c.whenIdle { ran += 1 }
        #expect(ran == 1) // no glide: straight away
        c.gliding = true
        defer { c.gliding = false }
        c.whenIdle { ran += 1 }
        #expect(ran == 1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(ran == 1) // still gliding
        c.gliding = false // landed
        try await Task.sleep(for: .milliseconds(300))
        #expect(ran == 2)
        // It gives up after its attempts (50ms apart) rather than waiting for ever.
        c.gliding = true
        c.whenIdle(attempts: 2) { ran += 1 }
        try await Task.sleep(for: .milliseconds(400))
        c.gliding = false
        try await Task.sleep(for: .milliseconds(300))
        #expect(ran == 2)
    }

    // MARK: Focus and auto-centre

    @Test("NAV-22 ⌥⇧` turns auto-centre on and off")
    func nav22() {
        Env.withDefaults(["autoCentre": nil]) {
            let c = TestCanvas.make()
            #expect(c.autoCentre) // on by default
            c.autoCentre.toggle() // what ⌥⇧` does
            #expect(!c.autoCentre)
            #expect(UserDefaults.standard.object(forKey: "autoCentre") as? Bool == false)
            #expect(!TestCanvas.make().autoCentre) // still off after a relaunch
            c.autoCentre.toggle()
            #expect(TestCanvas.make().autoCentre)
        }
    }

    @Test("NAV-22 The panel's Auto-centre switch flips the same setting")
    func nav22b() {
        Env.withDefaults(["autoCentre": nil]) {
            Env.isolate()
            let app = AppDelegate() // not launched: no status item, no shortcuts, no scans
            app.perform(.autoCentre(false))
            #expect(!app.controller.autoCentre)
            #expect(!TestCanvas.make().autoCentre)
            app.perform(.autoCentre(true))
            #expect(app.controller.autoCentre)
        }
    }

    @Test("NAV-23 With auto-centre on, clicking a part-hidden window centres it (logic)")
    func nav23() {
        Env.withDefaults(["autoCentre": true]) {
            let w = Self.win(1, 1112, 100, 600, 400) // runs off the right edge
            let c = TestCanvas.make(windows: [Self.win(2, 0, 100, 600, 400), w])
            // The view got here by a glide (viewPlaced is false). Gliding is set so the glide this
            // starts doesn't raise the overlay.
            Self.onCanvas(c, active: false, gliding: true) {
                c.focusSettled(on: w.id)
                #expect(c.glideTarget === w)
                #expect(c.animation?.to == c.focusCamera(for: w))
            }
        }
    }

    @Test("NAV-24 With auto-centre off, focus on a window partly on screen never moves the view (logic)")
    func nav24() {
        Env.withDefaults(["autoCentre": false]) {
            let w = Self.win(1, 1112, 100, 600, 400)
            let c = TestCanvas.make(windows: [Self.win(2, 0, 100, 600, 400), w])
            Self.onCanvas(c, active: false, gliding: true) {
                let camera = c.camera
                c.focusSettled(on: w.id)
                #expect(c.glideTarget == nil)
                #expect(c.animation == nil)
                #expect(c.camera == camera)
                #expect(c.lastHiddenHint == nil) // no "off-screen" toast either
            }
        }
    }

    @Test("NAV-47 After you pan at 100%, clicking a window you can see doesn't recentre (logic)")
    func nav47() {
        Env.withDefaults(["autoCentre": true]) {
            let w = Self.win(1, 1112, 100, 600, 400) // a third off the right edge
            let c = TestCanvas.make(windows: [Self.win(2, 0, 100, 600, 400), w])
            Self.onCanvas(c, active: false, gliding: true) {
                c.viewPlaced = true // you scrolled the view here at 100%
                let camera = c.camera
                c.focusSettled(on: w.id)
                #expect(c.glideTarget == nil)
                #expect(c.animation == nil)
                #expect(c.camera == camera)
                #expect(c.viewPlaced)
            }
        }
    }

    @Test("NAV-49 The next glide, zoom or display change ends the placed view (logic)")
    func nav49() {
        Env.withDefaults(["autoCentre": true]) {
            let w = Self.win(1, 1112, 100, 600, 400)
            let other = Self.win(2, 0, 100, 600, 400)
            let c = TestCanvas.make(windows: [other, w])
            Self.onCanvas(c) {
                // Panning at 100% places the view; panning zoomed out doesn't.
                c.pan(by: CGVector(dx: -10, dy: 0))
                #expect(c.viewPlaced)
                c.camera.scale = 0.5
                c.pan(by: CGVector(dx: -10, dy: 0))
                #expect(!c.viewPlaced)
                c.camera = Camera()
                // A zoom ends it.
                c.pan(by: CGVector(dx: -10, dy: 0))
                c.zoom(by: 0.9, at: CGPoint(x: 700, y: 400))
                #expect(!c.viewPlaced)
                // So does a hop.
                c.camera = Camera()
                c.pan(by: CGVector(dx: -10, dy: 0))
                c.view.hovered = other
                c.navigate(.right)
                #expect(!c.viewPlaced)
            }
            // ...and a glide (a hop's, ⌃⌥C's, or focus going to a window off screen).
            c.camera = Camera()
            Self.onCanvas(c, active: false, gliding: true) {
                c.viewPlaced = true
                c.glide(to: other)
                #expect(!c.viewPlaced)
            }
            // After which clicking a partly visible window recentres it again.
            c.camera = Camera()
            Self.onCanvas(c, active: false, gliding: true) {
                c.focusSettled(on: w.id)
                #expect(c.glideTarget === w)
                #expect(c.animation?.to == c.focusCamera(for: w))
            }
        }
    }

    @Test("NAV-48 Diving into a window you can see keeps the view you placed")
    func nav48() {
        let vp = CGRect(x: 0, y: 33, width: 1512, height: 949)
        let panels = CGRect(x: vp.maxX - 230, y: vp.maxY - 170, width: 214, height: 154) // the minimap's corner
        func on(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 600, _ h: CGFloat = 400) -> Bool {
            CanvasController.goesOnScreen(CGRect(x: x, y: vp.minY + y, width: w, height: h), in: vp, panels: panels)
        }
        #expect(on(1112, 100))  // a third on screen
        #expect(on(1464, 100))  // 48pt showing
        #expect(!on(1470, 100)) // 42pt: too little
        #expect(!on(300, -50))  // top cut off by the menu bar
        #expect(on(300, 901))   // 48pt showing at the bottom
        #expect(!on(300, 905))  // 44pt
        // A sliver at the edge stays parked only where it would cover the minimap or Spaces.
        #expect(on(1412, 100))
        #expect(!on(1412, vp.height - 300))
        // The controller asks with the view's own panels.
        let c = TestCanvas.make()
        #expect(c.goesOnScreen(CGRect(x: 1112, y: 133, width: 600, height: 400), in: c.viewport))
        #expect(!c.goesOnScreen(CGRect(x: 1480, y: 133, width: 600, height: 400), in: c.viewport))
    }

    @Test("NAV-48 Diving in where you placed the view drops the canvas in place (logic)")
    func nav48b() {
        let seen = Self.win(1, 1112, 100, 600, 400)  // 400pt on screen
        let edge = Self.win(2, 1480, 500, 600, 400)  // 32pt on screen
        let cut = Self.win(3, 300, -50, 600, 400)    // its top under the menu bar
        let c = TestCanvas.make(windows: [Self.win(4, 0, 100, 600, 400), seen, edge, cut])
        Self.onCanvas(c) {
            c.camera = Camera(origin: CGPoint(x: 0.4, y: -0.3), scale: 1)
            c.viewPlaced = true
            c.exit(focus: seen)
            #expect(c.animation?.to == Camera(origin: .zero, scale: 1)) // where it is (whole points)
            #expect(c.viewPlaced)
            for w in [edge, cut] {
                c.cancelAnimation()
                c.camera = Camera()
                c.viewPlaced = true
                c.exit(focus: w)
                #expect(c.animation?.to == c.viewCamera(for: w)) // as usual: centred, or its group framed (NAV-55)
                #expect(!c.viewPlaced)
            }
        }
    }

    // MARK: Centring

    @Test("NAV-43 ⌃⌥C centres the window you're in: the front app's focused window")
    func nav43() throws {
        let front = try #require(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        let (x, helper) = Self.windowOfFrontApp(front, id: 1)
        defer { Self.forget(helper) }
        let y = Self.win(2, 0, 0, 800, 600) // front-most on screen, another app's
        let c = TestCanvas.make(windows: [x, y])
        c.focusedWindowByApp[helper] = x.id // as its focus notifications left it
        #expect(c.currentWindow() === x)
    }

    @Test("NAV-43 ⌃⌥C otherwise centres the front-most window on screen")
    func nav43b() throws {
        let front = try #require(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        // The front app's window here isn't the focused one (Accessibility, asked about the fake
        // helper process, finds none): the front-most window not parked is.
        let (x, helper) = Self.windowOfFrontApp(front, id: 1)
        defer { Self.forget(helper) }
        let y = Self.win(2, 0, 0, 800, 600), z = Self.win(3, 900, 0, 800, 600)
        z.parked = true
        let c = TestCanvas.make(windows: [x, y, z])
        #expect(c.currentWindow() === y)
    }

    @Test("NAV-44 ⌃⌥C while zoomed out goes back to 100% on your window (logic)")
    func nav44() throws {
        let front = try #require(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        let (x, helper) = Self.windowOfFrontApp(front, id: 1)
        defer { Self.forget(helper) }
        let c = TestCanvas.make(windows: [x, Self.win(2, 2500, 900, 800, 600)])
        c.focusedWindowByApp[helper] = x.id
        Self.onCanvas(c) {
            c.camera = Camera(origin: CGPoint(x: 4000, y: 3000), scale: 0.25) // zoomed out and panned away
            c.centreCurrentWindow()
            #expect(c.animation?.to == c.viewCamera(for: x)) // centred, or its group framed (NAV-59)
            #expect(c.animation?.handsBack == true)
        }
    }

    @Test("NAV-45 Centring does nothing while Expanse is paused")
    func nav45() throws {
        let x = Self.win(1, 3000, 0, 800, 600)
        let c = TestCanvas.make(windows: [x])
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier { c.focusedWindowByApp[front] = x.id }
        c.isPaused = true
        c.viewPlaced = true
        // A camera move in flight: were the pause ignored, the glide would stop at it, before
        // raising the overlay, having only marked the view and focus as moved on.
        c.animate(to: c.camera)
        defer { c.cancelAnimation() }
        let query = c.focusQuery, camera = c.camera, frame = x.canvasFrame
        c.centreCurrentWindow()
        #expect(c.focusQuery == query)
        #expect(c.viewPlaced)
        #expect(c.camera == camera && x.canvasFrame == frame)
        #expect(!c.gliding && !c.isActive)
    }

    @Test("NAV-45 Before Expanse has started, Centre window and ⌃⌥C do nothing")
    func nav45b() {
        // The panel refuses the canvas's commands until Expanse has started (MenuPanel.run).
        #expect(MenuPanel.Action.centreWindow.needsCanvas)
        // And ⌃⌥C is only registered once it has (AppDelegate.turnOn).
        Env.isolate()
        #expect(AppDelegate().centreWindowHotKey == nil)
    }

    // MARK: The hot corner

    @Test("NAV-19 The hot corner fires once per visit, never mid-drag")
    func nav19() {
        Self.hotCorner(.all) { h, fired in
            var t: CFTimeInterval = 1000
            let display = Self.mainDisplay
            func rest(_ p: CGPoint, buttons: Int = 0, for seconds: Double) {
                for _ in 0..<Int(seconds * 30) {
                    h.poll(pointer: p, buttons: buttons, screen: display, now: t)
                    t += 1.0 / 30
                }
            }
            let corner = CGPoint(x: 1, y: 981), away = CGPoint(x: 700, y: 500)
            rest(corner, for: 3)
            #expect(fired() == 1) // once, however long it stays
            rest(away, for: 0.2)
            rest(corner, for: 1)
            #expect(fired() == 2) // leaving re-armed it
            rest(away, for: 0.2)
            rest(corner, buttons: 1, for: 2) // dragging a window into the corner
            #expect(fired() == 2)
        }
    }

    @Test("NAV-20 Resting the pointer in a corner opens the canvas (logic)")
    func nav20() {
        let f = Self.mainDisplay
        // AppKit coordinates (y up), each within the 3pt tolerance of its corner.
        let corners: [(HotCorner.Corner, CGPoint)] = [(.topLeft, CGPoint(x: 2, y: f.maxY - 1)), (.topRight, CGPoint(x: f.maxX - 2, y: f.maxY)),
                                                      (.bottomLeft, CGPoint(x: 0, y: 3)), (.bottomRight, CGPoint(x: f.maxX, y: 1))]
        // Within about a tenth of a second, at the 30-a-second polling.
        func firesAfter(_ setting: HotCorner.Corner, at p: CGPoint) -> Double? {
            var after: Double?
            Self.hotCorner(setting) { h, fired in
                for i in 0..<30 where after == nil {
                    h.poll(pointer: p, buttons: 0, screen: f, now: 500 + Double(i) / 30)
                    if fired() > 0 { after = Double(i) / 30 }
                }
            }
            return after
        }
        for (corner, p) in corners {
            let all = firesAfter(.all, at: p)
            #expect(all.map { $0 > 0.04 && $0 <= 0.1 } == true, "\(corner) with All corners")
            #expect(firesAfter(corner, at: p) != nil, "\(corner) on its own")
            for (other, _) in corners where other != corner {
                #expect(firesAfter(other, at: p) == nil, "\(other) set, pointer at \(corner)")
            }
            #expect(firesAfter(.off, at: p) == nil)
        }
        // Just outside the tolerance isn't the corner.
        #expect(firesAfter(.all, at: CGPoint(x: 5, y: f.maxY - 1)) == nil)
        #expect(firesAfter(.all, at: CGPoint(x: 2, y: f.maxY - 5)) == nil)
    }
}

// MARK: Helpers

extension NAVTests {
    /// A, B, C in a row 20pt apart, and D under B (NAV-26).
    static func row() -> [ManagedWindow] {
        [win(11, 0, 0, 600, 400), win(12, 620, 0, 600, 400), win(13, 1240, 0, 600, 400), win(14, 620, 420, 600, 400)]
    }

    /// A window of the front app `front`, drawn by a (fake) helper process of its: currentWindow
    /// and focusedWindow find it through the app, without asking the real app anything.
    static func windowOfFrontApp(_ front: pid_t, id: CGWindowID) -> (ManagedWindow, helper: pid_t) {
        let helper: pid_t = 90_777
        Fake.regularApp(helper, ownedBy: front)
        let w = ManagedWindow(scWindow: Fake.scWindow(id: id, pid: helper, frame: CGRect(x: 2000, y: 600, width: 800, height: 600)),
                              canvasFrame: CGRect(x: 2000, y: 600, width: 800, height: 600))
        w.needsFirstFrame = false
        return (w, helper)
    }

    /// Drops what windowOfFrontApp told the app cache about `helper`.
    static func forget(_ helper: pid_t) {
        CanvasController.appPolicyLock.lock()
        CanvasController.appOwners[helper] = nil
        CanvasController.appPolicyLock.unlock()
    }

    /// The main display's frame as HotCorner gets it (AppKit coordinates).
    static let mainDisplay = CGRect(x: 0, y: 0, width: 1512, height: 982)

    final class Counter { var n = 0 }

    /// A hot corner set to `corner` (the setting put back afterwards); `fired()` counts triggers.
    static func hotCorner(_ corner: HotCorner.Corner, _ body: (HotCorner, () -> Int) -> Void) {
        Env.withDefaults([HotCorner.defaultsKey: nil]) {
            let h = HotCorner()
            h.corner = corner
            let count = Counter()
            h.onTrigger = { count.n += 1 }
            body(h) { count.n }
        }
    }
}

// MARK: - Low motion

extension NAVTests {
    /// Runs `body` with Settings at `setting` and macOS's Reduce Motion as `reduce`.
    static func withMotion(_ setting: String?, reduce: Bool = false, _ body: () throws -> Void) rethrows {
        let saved = UserDefaults.standard.object(forKey: CanvasController.motionKey)
        let savedReduce = CanvasController.reduceMotion
        UserDefaults.standard.set(setting, forKey: CanvasController.motionKey)
        CanvasController.reduceMotion = { reduce }
        defer {
            UserDefaults.standard.set(saved, forKey: CanvasController.motionKey)
            CanvasController.reduceMotion = savedReduce
        }
        try body()
    }

    @Test("NAV-64 Low motion: a camera move goes straight to where it ends, and what follows it still runs")
    func nav64() {
        let (a, b, c) = Self.groupLayout()
        let canvas = TestCanvas.make(windows: [a, b, c])
        let target = Camera(origin: CGPoint(x: 300, y: 40), scale: 0.5)
        Self.withMotion("jump") {
            Self.onCanvas(canvas) {
                var done = false
                canvas.animate(to: target) { done = true }
                #expect(canvas.animation?.duration == 0)
                #expect(!done) // never during the call: callers count on it coming after
                canvas.advanceAnimation()
                #expect(canvas.camera == target)
                #expect(canvas.animation == nil)
                #expect(done)
                // Every way of moving the view goes through it: the ones that ask for a time too.
                canvas.zoomAnimated(to: 0.8)
                #expect(canvas.animation?.duration == 0)
                canvas.cancelAnimation()
                canvas.enter(zoomOut: true)
                #expect(canvas.animation?.duration == 0)
                canvas.cancelAnimation()
                canvas.exit(focus: a)
                #expect(canvas.animation?.duration == 0)
                #expect(canvas.animation?.handsBack == true)
                canvas.cancelAnimation()
            }
            Self.onCanvas(canvas, active: false, gliding: true) {
                canvas.glide(to: c)
                #expect(canvas.animation?.duration == 0)
            }
        }
        // Animated, it starts on its way and takes its time.
        Self.withMotion("glide") {
            Self.onCanvas(canvas) {
                canvas.camera = Camera(origin: .zero, scale: 1)
                canvas.animate(to: target)
                #expect((canvas.animation?.duration ?? 0) > 0)
                canvas.advanceAnimation()
                #expect(canvas.animation != nil)
                #expect(canvas.camera != target)
            }
        }
    }

    @Test("NAV-65 Low motion follows macOS's Reduce Motion unless Settings says otherwise")
    func nav65() {
        // Match macOS: unset (as for everyone at first), chosen, or anything unknown.
        for setting in [nil, "follow", "something else"] as [String?] {
            #expect(CanvasController.lowMotion(setting: setting, reduceMotion: true))
            #expect(!CanvasController.lowMotion(setting: setting, reduceMotion: false))
        }
        // Settings wins, either way.
        #expect(CanvasController.lowMotion(setting: "jump", reduceMotion: false))
        #expect(!CanvasController.lowMotion(setting: "glide", reduceMotion: true))
        // And they're what a move reads, at the move.
        Self.withMotion(nil, reduce: true) { #expect(CanvasController.lowMotion) }
        Self.withMotion(nil, reduce: false) { #expect(!CanvasController.lowMotion) }
        Self.withMotion("glide", reduce: true) { #expect(!CanvasController.lowMotion) }
        Self.withMotion("jump", reduce: false) { #expect(CanvasController.lowMotion) }
    }
}
