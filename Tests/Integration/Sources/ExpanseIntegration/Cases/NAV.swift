import AppKit

/// The manual cases in docs/regression/navigation.md.
///
/// Two things about Expanse shape these cases (see the helpers at the end):
/// - Opening a link (every `state()` is an expanse://dump) can bring Expanse to the front, which
///   takes the keyboard from the app you're in. A hop (⌃ + arrow) starts from the front app's
///   focused window, so a case gives a window the keyboard (a click, or `navFocus`), then presses
///   the key without asking Expanse anything in between, and checks focus before it asks again.
/// - cleanUp's expanse://screen runs a display-change pass even when nothing changed: windows are
///   re-placed 1.6s later, and for 20s focus changes you didn't make aren't followed. `navReady`
///   waits for the pass; switches between apps come with a key press, as ⌘-Tab's do.
@MainActor enum NAV {
    static let cases: [Case] = [
        Case("NAV-04", "⌘ + scroll zooms around the pointer") { t in
            try t.needsInput()
            try await t.navReady()
            let spot = try await t.navEmptySpot()
            _ = try await t.row(["NAV-04 A", "NAV-04 B", "NAV-04 C"], origin: spot)
            t.link("enter")
            try await t.until("the canvas to open") { try await t.state().active }
            try await t.settle()
            t.link("zoom", ["scale": 0.3])
            let s = try await t.settle()
            try t.expect(s.active && abs(s.scale - 0.3) < 0.01, "expanse://zoom?scale=0.3 should leave the canvas at 30% (it's at \(navPercent(s.scale)))")
            // Off the middle of the screen, so zooming round the pointer and round the middle differ.
            let p = CGPoint(x: s.viewport.minX + s.viewport.width * 0.3, y: s.viewport.minY + s.viewport.height * 0.35)
            Input.move(to: p)
            try await t.pause(0.2)
            /// One scroll with ⌘ held: it zooms, and the canvas point under the pointer stays under
            /// it (so nothing pans). Returns the size of the step (the log of the zoom factor).
            @MainActor func zoomStep(_ what: String, _ scroll: () -> Void) async throws -> Double {
                let before = try await t.settle()
                let under = navCanvasPoint(before, p)
                scroll()
                try await t.pause(0.4)
                let after = try await t.settle()
                try t.expect(after.active, "\(what) with ⌘ held left the canvas")
                try t.expect(abs(after.scale - before.scale) > 0.0005, "\(what) with ⌘ held should zoom (it stayed at \(navPercent(after.scale)))")
                try t.expectNear(after.screenPoint(under), p, within: 3, "\(what) with ⌘ held: the canvas point that was under the pointer")
                return abs(Darwin.log(Double(after.scale / before.scale)))
            }
            // The same amount each: a trackpad's 5 points, a mouse wheel's 5 lines.
            let pad = try await zoomStep("A trackpad scroll") {
                Input.scroll(dy: 0, flags: .maskCommand, phase: .began)
                Input.scroll(dy: 5, flags: .maskCommand, phase: .changed)
                Input.scroll(dy: 0, flags: .maskCommand, phase: .ended)
            }
            let wheel = try await zoomStep("A mouse wheel") { navWheel(dy: 5, flags: .maskCommand) }
            try t.expect(wheel > pad * 3, String(format: "a mouse wheel should zoom in bigger steps than a trackpad (5 lines ×%.3f, 5 points ×%.3f)", exp(wheel), exp(pad)))
            _ = try await zoomStep("A trackpad scroll the other way") { Input.trackpadScroll(dy: -40, steps: 4, flags: .maskCommand) }
            _ = try await zoomStep("A mouse wheel the other way") { navWheel(dy: -3, flags: .maskCommand) }
        },

        Case("NAV-07", "⌥ + pinch anywhere opens the canvas", .guided) { t in
            try await t.navReady()
            let w = try await t.window("NAV-07 Pinch over me")
            let before = try await t.navGlide(to: w.id)
            try await t.ask("Put the pointer over the window “NAV-07 Pinch over me”, hold ⌥ and pinch in (fingers together) until something happens, then press Done.")
            try await t.until("⌥ + pinch to open the canvas", timeout: 3) { try await t.state().active }
            try t.navExpectOverview(try await t.settle(), "⌥ + pinch")
            t.link("exit")
            try await t.until("back at 100%") { try await !t.settle().active }
            let back = try await t.settle()
            try t.expectNear(back.camera, before.camera, within: 1, "leaving the canvas should go back to the view the pinch started from")
            try await t.ask("Now pinch in over the same window again, without ⌥, then press Done.")
            try await t.pause(0.5)
            let after = try await t.settle()
            try t.expect(!after.active, "a pinch without ⌥ over a window opened the canvas")
            try t.expectNear(after.camera, back.camera, within: 1, "a pinch without ⌥ over a window moved the view")
        },

        Case("NAV-11", "Esc goes back to the 100% view you left") { t in
            try t.needsInput()
            try await t.navReady()
            let spot = try await t.navEmptySpot()
            let ws = try await t.row(["NAV-11 A", "NAV-11 B", "NAV-11 C"], origin: spot)
            // B in front, in the middle of the screen; the others part on screen or out of view.
            let before = try await t.navGlide(to: ws[1].id)
            let real = ws.map(\.real)
            Input.key(.grave, .maskAlternate)
            try await t.until("⌥` to zoom out") { let s = try await t.state(); return s.active && s.scale < 1 }
            try await t.settle()
            Input.key(.escape)
            // Before asking Expanse anything (see the note at the top).
            try await t.navHasKeyboard(ws[1], "B, the front-most window on screen,")
            try await t.until("Esc to leave the canvas") { try await !t.settle().active }
            let after = try await t.settle()
            try t.expect(abs(after.scale - 1) < 0.001, "Esc should leave the canvas at 100% (\(navPercent(after.scale)))")
            try t.expectNear(after.camera, before.camera, within: 0.5, "Esc should go back to exactly the 100% view you left")
            for (w, r) in zip(ws, real) {
                guard let r, let now = w.real else { continue }
                try t.expectNear(now, r, within: 1, "\(w.title)'s real window after Esc")
            }
        },

        Case("NAV-14", "Click a parked window's picture at 100% to go to it") { t in
            try t.needsInput()
            try await t.navReady()
            let a = try await t.window("NAV-14 A")
            try await t.window("NAV-14 B")      // has the keyboard meanwhile
            var s = try await t.navGoEmpty()
            // As TRACK-03 leaves it: A's top 150pt above the screen, so the real window is parked
            // and its picture is drawn at the top of the screen.
            guard let fa = s.window(a.id)?.canvas else { throw Failure("A isn't on the canvas") }
            let vis = s.visibleCanvas
            t.place(a, at: CGPoint(x: (vis.midX - fa.width / 2).rounded(), y: (vis.minY - 150).rounded()))
            try await t.until("A parked, cut off at the top") { try await t.state().window(a.id)?.parked == true }
            try await t.navFirstFrame(a.id)
            s = try await t.settle()
            guard let wa = s.window(a.id) else { throw Failure("A left the canvas") }
            let p = s.screenPoint(CGPoint(x: wa.canvas.midX, y: wa.canvas.maxY - 60))
            try t.expect(p.y > s.viewport.minY + 10, "A's picture should show at the top of the screen (its bottom is at \(p.y + 60))")
            let mark = t.log.mark()
            Input.click(at: p)
            try await t.navLog("glide to ", a.id, since: mark, timeout: 3)
            try await t.navHasKeyboard(a, "A")
            try await t.until("the view centred on A at 100%", timeout: 5) { let s = try await t.settle(); return navCentred(s, a.id) }
            s = try await t.settle()
            try t.expect(s.window(a.id)?.parked == false, "A's real window should be back from the corner")
            try t.navExpectInPlace(s, a.id, "A")
        },

        Case("NAV-15", "Pan with two-finger scroll or Space + drag", .look) { t in
            try t.needsInput()
            try await t.navReady()
            let spot = try await t.navEmptySpot()
            let ws = try await t.row(["NAV-15 A", "NAV-15 B", "NAV-15 C"], origin: spot)
            t.link("enter")
            try await t.until("the canvas to open") { try await t.state().active }
            var s = try await t.settle()
            Input.move(to: CGPoint(x: s.viewport.midX, y: s.viewport.minY + s.viewport.height * 0.4))
            try await t.pause(0.2)
            // 1. Two-finger scrolls pan, each way, and back to where they started.
            let start = s.camera
            for (dx, dy) in [(0, 150), (0, -150), (150, 0), (-150, 0)] as [(Int32, Int32)] {
                let before = try await t.settle()
                Input.trackpadScroll(dx: dx, dy: dy, steps: 10)
                try await t.pause(0.3)
                let after = try await t.settle()
                try t.expect(abs(after.scale - before.scale) < 0.0001, "a two-finger scroll zoomed (\(navPercent(before.scale)) → \(navPercent(after.scale)))")
                let moved = CGPoint(x: (after.camera.x - before.camera.x) * before.scale, y: (after.camera.y - before.camera.y) * before.scale)
                let along = dx != 0 ? abs(moved.x) : abs(moved.y), across = dx != 0 ? abs(moved.y) : abs(moved.x)
                try t.expect(along >= 100 && along <= 200 && across < 2, "a two-finger scroll of \(dx), \(dy) should pan 150pt that way (the view moved \(moved))")
            }
            s = try await t.settle()
            try t.expectNear(s.camera, start, within: 2 / s.scale, "scrolling each way and back should end where it started")
            // 3. With ⌘ held, a scroll zooms round the pointer instead.
            let p = CGPoint(x: s.viewport.minX + s.viewport.width * 0.3, y: s.viewport.minY + s.viewport.height * 0.4)
            Input.move(to: p)
            try await t.pause(0.2)
            let under = navCanvasPoint(s, p)
            let unzoomed = s.scale
            Input.trackpadScroll(dy: 40, steps: 4, flags: .maskCommand)
            try await t.pause(0.3)
            s = try await t.settle()
            try t.expect(abs(s.scale - unzoomed) > 0.0005, "⌘ + scroll should zoom (it stayed at \(navPercent(s.scale)))")
            try t.expectNear(s.screenPoint(under), p, within: 3, "⌘ + scroll should zoom round the pointer, not pan")
            // 2. Space + drag, starting over a window: the view pans and no window moves. Slowly,
            // so you can watch the pointer.
            try await t.ask("Watch the pointer: Expanse Tests will hold Space, drag across the canvas starting over a window, let go of the button, then of Space. Press Done to start.")
            s = try await t.settle()
            let frames = Dictionary(s.windows.map { ($0.id, $0.canvas) }, uniquingKeysWith: { first, _ in first })
            guard let fb = s.window(ws[1].id)?.canvas else { throw Failure("B left the canvas") }
            var from = s.screenPoint(navCentre(fb))
            from.x = min(max(from.x, s.viewport.minX + 300), s.viewport.maxX - 300)
            from.y = min(max(from.y, s.viewport.minY + 100), s.viewport.maxY - 260)
            let to = CGPoint(x: from.x - 220, y: from.y + 90)
            navSpace(true)
            try await t.pause(1)
            navSlowDrag(from: from, to: to, seconds: 1.5)
            try await t.pause(1)
            navSpace(false)
            try await t.pause(1)
            let after = try await t.settle()
            try t.expect(abs(after.scale - s.scale) < 0.0001, "Space + drag zoomed")
            let want = CGPoint(x: s.camera.x - (to.x - from.x) / s.scale, y: s.camera.y - (to.y - from.y) / s.scale)
            try t.expectNear(after.camera, want, within: 3 / s.scale, "Space + drag should pan the view with the pointer")
            for w in after.windows {
                guard let f = frames[w.id] else { continue }
                try t.expectNear(w.canvas, f, within: 0.5, "Space + drag moved \(w.app)[\(w.id)] on the canvas")
            }
            try await t.look("While Space was held, was the pointer an open hand, a closed hand while dragging, and the arrow again once Space was let go?")
        },

        Case("NAV-17", "After moving around zoomed out, leaving goes back to the window you were in", time: 180) { t in
            try t.needsInput()
            try await t.navReady()
            let spot = try await t.navEmptySpot()
            let ws = try await t.row(["NAV-17 A", "NAV-17 B", "NAV-17 C"], origin: spot)
            let moves: [(String, (ExpanseState) -> Void)] = [
                ("a two-finger scroll", { s in
                    Input.move(to: CGPoint(x: s.viewport.midX, y: s.viewport.minY + s.viewport.height * 0.4))
                    Input.trackpadScroll(dx: 240, dy: 90)
                }),
                ("⌘ + scroll", { s in
                    Input.move(to: CGPoint(x: s.viewport.minX + s.viewport.width * 0.25, y: s.viewport.minY + s.viewport.height * 0.4))
                    Input.trackpadScroll(dy: 60, steps: 6, flags: .maskCommand)
                }),
                ("0", { _ in Input.key(.zero) }),
                ("1", { _ in Input.key(.one) }),
                ("-", { _ in Input.key(.minus) }),
                ("=", { _ in Input.key(.equal) }),
                ("a click on the minimap", { s in
                    let m = navMinimap(s)
                    Input.click(at: CGPoint(x: m.minX + 45, y: m.midY + 10))
                }),
            ]
            for (i, (what, move)) in moves.enumerated() {
                let start = try await t.navGlide(to: ws[0].id)
                Input.key(.grave, .maskAlternate)
                try await t.until("⌥` to zoom out") { try await t.state().active }
                let out = try await t.settle()
                move(out)
                // Until the view stops moving (the last of a scroll can land a moment later).
                var moved = try await t.settle()
                for _ in 0..<20 {
                    try await t.pause(0.3)
                    let now = try await t.settle()
                    defer { moved = now }
                    if now.camera == moved.camera && now.scale == moved.scale { break }
                }
                try t.expect(moved.active, "\(what) left the canvas")
                try t.expect(navDistance(navViewCentre(moved), navViewCentre(start)) > 20, "after ⌥` and \(what), the view should have moved")
                // Esc, or ⌥` again (every other time): you didn't pick anywhere else.
                let leave = i % 2 == 0 ? "Esc" : "⌥`"
                if i % 2 == 0 { Input.key(.escape) } else { Input.key(.grave, .maskAlternate) }
                try await t.until("\(leave) to leave the canvas") { try await !t.settle().active }
                let back = try await t.settle()
                try t.expect(abs(back.scale - 1) < 0.001, "after \(what), \(leave) should leave at 100% (\(navPercent(back.scale)))")
                try t.expectNear(back.camera, start.camera, within: 1, "after \(what), \(leave) should go back to A as you left it")
                try await t.navHasKeyboard(ws[0], "A, back")
            }
            // A moved while zoomed out (dragged, or by Tidy Up): it's centred where it is now.
            _ = try await t.navGlide(to: ws[0].id)
            Input.key(.grave, .maskAlternate)
            try await t.until("⌥` to zoom out") { try await t.state().active }
            let out = try await t.settle()
            guard let fa = out.window(ws[0].id)?.canvas else { throw Failure("A isn't on the canvas") }
            t.place(ws[0], at: CGPoint(x: fa.minX + 2400, y: fa.minY + 900), commit: false)
            try await t.until("A moved on the canvas") { try await t.state().window(ws[0].id)?.canvas.minX == fa.minX + 2400 }
            Input.key(.escape)
            try await t.until("Esc to leave the canvas") { try await !t.settle().active }
            try await t.until("the view centred on A where it is now", timeout: 5) { let s = try await t.settle(); return navCentred(s, ws[0].id) }
            try await t.navHasKeyboard(ws[0], "A, moved")
        },

        Case("NAV-18", "Scrolling or pinching on the bare desktop opens the canvas", .guided) { t in
            try t.needsInput()
            try await t.navReady()
            try await t.window("NAV-18 A")
            // 1. A two-finger scroll: the first of it opens the canvas at 100%, the rest pans.
            var s = try await t.navGoEmpty()
            guard let p = navBarePoint(s) else { throw Skip("there's no bare desktop on screen to scroll on") }
            Input.move(to: p)
            try await t.pause(0.2)
            Input.scroll(dy: 0, phase: .began)
            try await t.pause(0.25)
            for _ in 0..<12 { Input.scroll(dy: 15, phase: .changed) }
            Input.scroll(dy: 0, phase: .ended)
            try await t.pause(0.5)
            var after = try await t.settle()
            try t.expect(after.active, "a two-finger scroll on the bare desktop should open the canvas")
            try t.expect(abs(after.scale - 1) < 0.001, "the canvas should open at 100% (\(navPercent(after.scale)))")
            try t.expect(navDistance(after.camera, s.camera) >= 90, "the rest of the scroll should move the view (it moved \(navDistance(after.camera, s.camera))pt of 180)")
            Input.key(.escape)
            try await t.until("Esc to go back to 100%") { try await !t.settle().active }
            // 2. A pinch.
            try await t.ask("Put the pointer on the bare desktop (no window under it, away from the minimap at the bottom right) and pinch slowly in or out, for a moment, then press Done.")
            try await t.until("the pinch to open the canvas", timeout: 2) { try await t.state().active }
            after = try await t.settle()
            try t.expect(abs(after.scale - 1) > 0.02, "the rest of the pinch should zoom the view (it's at \(navPercent(after.scale)))")
            Input.key(.escape)
            try await t.until("Esc to go back to 100%") { try await !t.settle().active }
            // 3. A mouse wheel: each tick counts, the first opens the canvas, the rest move it.
            s = try await t.settle()
            guard let q = navBarePoint(s) else { throw Skip("there's no bare desktop on screen to scroll on") }
            Input.move(to: q)
            try await t.pause(0.2)
            navWheel(dy: 2)
            try await t.pause(0.25)
            for _ in 0..<5 { navWheel(dy: 2); try await t.pause(0.04) }
            try await t.pause(0.5)
            after = try await t.settle()
            try t.expect(after.active && abs(after.scale - 1) < 0.001, "a mouse wheel on the bare desktop should open the canvas at 100%")
            try t.expect(navDistance(after.camera, s.camera) >= 40, "the rest of the wheel's ticks should move the view (it moved \(navDistance(after.camera, s.camera))pt)")
            Input.key(.escape)
        },

        Case("NAV-20", "Resting the pointer in a corner opens the canvas") { t in
            try t.needsInput()
            try await t.navReady()
            let setting = expanseDefault("hotCorner") as? String ?? "all"
            guard setting == "all" else { throw Skip("Expanse's hot corner is set to \(setting), not All corners (menu bar panel › Hot corner)") }
            let corners = try navHotCorners(t)
            let spot = try await t.navEmptySpot()
            let ws = try await t.row(["NAV-20 A", "NAV-20 B", "NAV-20 C"], origin: spot)
            try await t.navGlide(to: ws[1].id)
            let middle = CGPoint(x: t.screen.midX, y: t.screen.midY)
            for c in corners.free {
                Input.glide(to: middle)
                let start = try await t.settle()
                try t.expect(!start.active, "the canvas was up before trying the \(c.name) corner")
                Input.glide(to: c.point)
                try await t.until("the \(c.name) corner to open the canvas", timeout: 2) { try await t.state().active }
                let out = try await t.settle()
                try t.navExpectOverview(out, "resting in the \(c.name) corner")
                // Staying there does nothing more.
                try await t.pause(2)
                let still = try await t.settle()
                try t.expect(still.active, "staying in the \(c.name) corner toggled the canvas again")
                try t.expectNear(still.camera, out.camera, within: 0.5, "staying in the \(c.name) corner moved the view")
                // Out and back in: back to 100%, to the view you left. Out for long enough that the
                // corner's check of the pointer sees it gone (a busy main thread in a VM checks late).
                Input.glide(to: middle)
                try await t.pause(1)
                Input.glide(to: c.point)
                // (Back at 100% includes the windows' moves and the hand-back: seconds in a busy VM.)
                try await t.until("going back into the \(c.name) corner to toggle back to 100%", timeout: 10) { try await !t.settle().active }
                let back = try await t.settle()
                try t.expect(abs(back.scale - 1) < 0.001, "the \(c.name) corner should toggle back to 100% (\(navPercent(back.scale)))")
                try t.expectNear(back.camera, start.camera, within: 0.5, "the \(c.name) corner should toggle back to the view you left")
            }
            Input.glide(to: middle)
            if !corners.taken.isEmpty {
                throw Skip("the other corners passed; macOS's own hot corners are set for \(corners.taken.joined(separator: ", ")), so those weren't tried")
            }
        },

        Case("NAV-21", "Hot corners do nothing while Expanse is paused") { t in
            try t.needsInput()
            try await t.navReady()
            let corners = try navHotCorners(t)
            let a = try await t.window("NAV-21 A")
            t.link("pause")
            try await t.untilPaused("Expanse to pause")
            try await t.pause(1)
            let real = a.real
            let middle = CGPoint(x: t.screen.midX, y: t.screen.midY)
            for c in corners.free {
                Input.glide(to: c.point)
                try await t.pause(0.8)
                Input.glide(to: middle)
                try await t.pause(0.3)
            }
            let s = try await t.state()
            try t.expect(s.paused, "a hot corner resumed Expanse")
            try t.expect(!s.active, "a hot corner opened the canvas while Expanse was paused")
            if let real, let now = a.real { try t.expectNear(now, real, within: 1, "A moved while Expanse was paused") }
        },

        Case("NAV-23", "With auto-centre on, clicking a part-hidden window centres it") { t in
            try t.needsInput()
            try await t.navReady()
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let spot = try await t.navEmptySpot()
            let ws = try await t.row(["NAV-23 B", "NAV-23 A"], origin: spot)
            let b = ws[0], a = ws[1]
            // A glide brought the view here (not your own scrolling).
            let s = try await t.navGlide(to: b.id)
            guard let fa = s.window(a.id)?.canvas else { throw Failure("A isn't on the canvas") }
            t.place(a, at: CGPoint(x: (s.visibleCanvas.maxX - min(300, fa.width / 2)).rounded(), y: fa.minY))
            try await t.until("A running off the right edge", timeout: 4) {
                guard let r = a.real else { return false }
                return r.minX < t.screen.maxX - 100 && r.maxX > t.screen.maxX
            }
            try await t.pause(1.2)
            let mark = t.log.mark()
            try await t.navClick(a)
            let line = try await t.navLog("focus-settled glide to ", a.id, since: mark, timeout: 3)
            try t.expect(line.contains("]: on screen at"), "the glide should be for a window on screen: \(line)")
            try await t.navHasKeyboard(a, "A")
            try await t.until("the view centred on A", timeout: 5) { let s = try await t.settle(); return navCentred(s, a.id) }
        },

        Case("NAV-24", "With auto-centre off, focus never moves the view") { t in
            try t.needsInput()
            try await t.navReady()
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", false)
            defer { setExpanseDefault("autoCentre", old) }
            let c = try await t.fixture("NAV24C")
            let b = try await t.fixture("NAV24B")
            let a = try await t.fixture("NAV24A", windows: 2)
            guard a.windows.count == 2, let a1 = a.windows.first, let b1 = b.windows.first, let c1 = c.windows.first else {
                throw Failure("the fixture apps didn't open their windows")
            }
            let a2 = a.windows[1]
            try await t.until("Expanse to take on the fixtures' windows", timeout: 10) {
                let s = try await t.state()
                return [a1, a2, b1, c1].allSatisfy { s.window($0) != nil }
            }
            var s = try await t.settle()
            let vis = s.visibleCanvas
            // A's first window on screen, C's partly (off the right edge), A's second and B's out of view.
            t.navPlace(a1, CGPoint(x: vis.minX + 40, y: vis.minY + 40))
            t.navPlace(c1, CGPoint(x: vis.maxX - 240, y: vis.minY + 40))
            t.navPlace(a2, CGPoint(x: vis.maxX + 3000, y: vis.minY))
            t.navPlace(b1, CGPoint(x: vis.maxX + 6000, y: vis.minY))
            s = try await t.settle()
            try t.expect(s.window(b1)?.parked == true && s.window(a2)?.parked == true, "B's window and A's second should be out of view")
            try t.expect(s.window(c1)?.parked == false, "C's window should be partly on screen")
            guard let wa = s.window(a1) else { throw Failure("A's window left the canvas") }
            try t.expect(!wa.parked && s.viewport.insetBy(dx: -1, dy: -1).contains(navScreenRect(s, wa.canvas)), "A's first window should be whole on screen")
            // A's key window is its first (on screen), not the second it opened last (out of view):
            // switching to A then focuses one in view, with no toast of its own.
            try await a.send("focus", ["index": "0"])
            try await t.navSwitch(to: a)
            try await t.pause(1)
            let view = try await t.settle()
            let mark = t.log.mark()
            @MainActor func viewStill(_ what: String) async throws {
                let now = try await t.settle()
                try t.expect(!now.active, "\(what) opened the canvas")
                try t.expectNear(now.camera, view.camera, within: 0.5, "\(what) moved the view")
            }
            // 1. B, whose only window is out of view: a toast says where it is; the view stays.
            try await t.navSwitch(to: b)
            let toast = await t.navToast(within: 2)
            try t.expect(toast.shown, "switching to B, whose only window is out of view, should show the toast “… is off-screen · ⌥` to find it”")
            if let text = toast.text {
                try t.expect(text.contains("is off-screen · ⌥` to find it"), "the toast says “\(text)”")
            }
            try await viewStill("switching to B")
            try await t.pause(2)    // the toast fades
            // 2. A, then B again: no toast for the same window twice.
            try await t.navSwitch(to: a)
            try await t.pause(1)
            try await t.navSwitch(to: b)
            let again = await t.navToast(within: 2)
            try t.expect(!again.shown, "the toast for B's window should only show once")
            try await viewStill("switching back to B")
            // A window partly on screen just takes focus: no toast.
            try await t.navSwitch(to: c)
            let partly = await t.navToast(within: 1.5)
            try t.expect(!partly.shown, "switching to C, whose window is partly on screen, showed a toast")
            try await viewStill("switching to C")
            // 3. In A, close the window on screen: macOS focuses A's other one, out of view.
            try await t.navSwitch(to: a)
            try await a.send("focus", ["index": "0"])
            try await t.pause(1.6)
            try await a.closeWindow(0)
            try await t.pause(2)
            try await viewStill("closing A's window (focusing its other one, out of view)")
            try await t.noLog("glide to ", since: mark, within: 0.1)
        },

        Case("NAV-25", "⌃ + arrow with auto-centre off only moves focus to a window in view") { t in
            try t.needsInput()
            if let on = navMacArrowShortcuts([.right]) { throw Skip("macOS takes ⌃→ itself (\(on)): turn it off in System Settings › Keyboard › Keyboard Shortcuts › Mission Control") }
            try await t.navReady()
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", false)
            defer { setExpanseDefault("autoCentre", old) }
            let (l, r, more) = try await t.navSideBySide("NAV-25", more: ["NAV-25 Parked"])
            let p = more[0]
            var s = try await t.settle()
            guard let fr = s.window(r.id)?.canvas else { throw Failure("the right-hand window isn't on the canvas") }
            t.place(p, at: CGPoint(x: (s.visibleCanvas.maxX + 200).rounded(), y: fr.minY))
            try await t.until("the third window parked to the right") { try await t.state().window(p.id)?.parked == true }
            let view = try await t.settle()
            // 1. From the left window: the right one is on screen, so it only takes focus.
            try await t.navClick(l)
            var mark = t.log.mark()
            Input.key(.right, .maskControl)
            try await t.navLog("navigate to ", r.id, since: mark, timeout: 3)
            try await t.navHasKeyboard(r, "the right-hand window")
            try await t.until("the right-hand window raised", timeout: 1) { navFrontWindow(among: [l.id, r.id, p.id]) == r.id }
            try await t.pause(0.5)
            s = try await t.settle()
            try t.expect(!s.active, "the hop opened the canvas")
            try t.expectNear(s.camera, view.camera, within: 0.5, "with auto-centre off, a hop to a window on screen moved the view")
            try await t.noLog("glide to ", since: mark, within: 0.1)
            // 2. Again: the next window that way isn't on screen, so the view glides to it.
            try await t.navClick(r)
            mark = t.log.mark()
            Input.key(.right, .maskControl)
            try await t.navLog("navigate to ", p.id, since: mark, timeout: 3)
            try await t.navLog("glide to ", p.id, since: mark, timeout: 3)
            try await t.navHasKeyboard(p, "the parked window")
            try await t.until("the view centred on it", timeout: 5) { let s = try await t.settle(); return navCentred(s, p.id) }
        },

        Case("NAV-28", "A hop pressed during a glide carries on from where it was heading") { t in
            try t.needsInput()
            if let on = navMacArrowShortcuts([.right]) { throw Skip("macOS takes ⌃→ itself (\(on)): turn it off in System Settings › Keyboard › Keyboard Shortcuts › Mission Control") }
            try await t.navReady()
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            // Animated, whatever Reduce Motion says: in low motion each hop's over before the next.
            setExpanseDefault("motion", "glide")
            defer {
                setExpanseDefault("autoCentre", old)
                setExpanseDefault("motion", nil)
            }
            // Wider together than the screen.
            let size = CGSize(width: max(600, (t.screen.width / 3).rounded()), height: 400)
            let spot = try await t.navEmptySpot()
            let ws = try await t.row(["NAV-28 A", "NAV-28 B", "NAV-28 C", "NAV-28 D"], size: size, origin: spot)
            try await t.navGlide(to: ws[0].id)
            try await t.navClick(ws[0])
            let mark = t.log.mark()
            for _ in 0..<3 {
                Input.key(.right, .maskControl)
                try await t.pause(0.04)
            }
            try await t.navLog("navigate to ", ws[1].id, since: mark, timeout: 3)
            try await t.navLog("navigate (chained) to ", ws[2].id, since: mark, timeout: 3)
            try await t.navLog("navigate (chained) to ", ws[3].id, since: mark, timeout: 3)
            try await t.navHasKeyboard(ws[3], "D")
            try await t.until("the view centred on D", timeout: 5) { let s = try await t.settle(); return navCentred(s, ws[3].id) }
            try await t.pause(0.5)
            let s = try await t.settle()
            for w in ws { try t.navExpectInPlace(s, w.id, w.title) }
            let handBacks = t.log.lines(since: mark).filter { $0.hasPrefix("glide timing:") }.count
            try t.expect(handBacks == 1, "only the last hop should hand back (\(handBacks) glides finished)")
        },

        Case("NAV-29", "Scrolls, clicks and the canvas toggle can't cut a glide short") { t in
            try t.needsInput()
            if let on = navMacArrowShortcuts([.right]) { throw Skip("macOS takes ⌃→ itself (\(on)): turn it off in System Settings › Keyboard › Keyboard Shortcuts › Mission Control") }
            try await t.navReady()
            let corners = try navHotCorners(t)
            let spot = try await t.navEmptySpot()
            let here = try await t.window("NAV-29 Here")
            let far = try await t.window("NAV-29 Far")
            t.place(here, at: spot)
            t.place(far, at: CGPoint(x: spot.x + 3000, y: spot.y))
            try await t.settle()
            try await t.navFocus(here)
            let middle = CGPoint(x: t.screen.midX, y: t.screen.midY)
            // A bottom corner is under the canvas while it glides, so the scroll and the click can
            // go there too: the pointer gets to the corner first (its dwell is the slowest part)
            // and stays (leaving would re-arm it). A top corner is the menu bar's: not clicked.
            let bottom = corners.free.first { $0.name.hasPrefix("bottom") }
            let corner = bottom ?? corners.free[0]
            Input.move(to: middle)
            try await t.pause(0.2)
            let mark = t.log.mark()
            Input.key(.right, .maskControl)
            if bottom != nil {
                Input.move(to: corner.point)
                navWheel(dy: 3)
                Input.click(at: corner.point)
                Input.key(.grave, .maskAlternate)
            } else {
                navWheel(dy: 3)
                Input.click(at: middle)
                Input.key(.grave, .maskAlternate)
                Input.move(to: corner.point)
            }
            try await t.navLog("glide to ", far.id, since: mark, timeout: 3)
            try await t.navHasKeyboard(far, "the far window")
            try await t.until("the glide to land on the far window", timeout: 5) { let s = try await t.settle(); return navCentred(s, far.id) }
            try await t.pause(1)
            var s = try await t.settle()
            try t.expect(!s.active, "the canvas is up after the glide: ⌥`, the click or the hot corner got through mid-glide (or came after it)")
            try t.navExpectInPlace(s, far.id, "the far window")
            // Still in the corner: nothing until it's rested in again.
            try await t.pause(1)
            s = try await t.state()
            try t.expect(!s.active, "the hot corner fired after the glide without the pointer leaving it")
            Input.glide(to: middle)
            try await t.pause(0.3)
            Input.glide(to: corner.point)
            try await t.until("resting in the \(corner.name) corner again to open the canvas", timeout: 3) { try await t.state().active }
            Input.glide(to: middle)
        },

        Case("NAV-30", "Glides and hops are quick, and their timing is logged") { t in
            try t.needsInput()
            if let on = navMacArrowShortcuts([.left, .right]) { throw Skip("macOS takes ⌃← / ⌃→ itself (\(on)): turn them off in System Settings › Keyboard › Keyboard Shortcuts › Mission Control") }
            if let slow = expanseDefault("animationSlowdown") as? Double, slow > 1 { throw Skip("animationSlowdown is \(slow): glides are slowed down on purpose") }
            try await t.navReady()
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let size = CGSize(width: 500, height: 320)
            let other = try await t.fixture("NAV30", windows: 5, size: size)
            guard let otherPID = other.pid, other.windows.count == 5 else { throw Failure("the fixture app didn't open its 5 windows") }
            var mine: [TestWindow] = []
            for i in 1...5 { mine.append(try await t.window("NAV-30 \(i)", CGRect(x: 100 + 20 * CGFloat(i), y: 140, width: size.width, height: size.height))) }
            try await t.until("Expanse to take on the other app's windows", timeout: 10) {
                let s = try await t.state()
                return other.windows.allSatisfy { s.window($0) != nil }
            }
            // Ours and theirs taking turns, so every hop switches app.
            let row: [(id: CGWindowID, pid: pid_t)] = (0..<5).flatMap { [(mine[$0].id, getpid()), (other.windows[$0], otherPID)] }
            _ = try await t.navRow(row.map(\.id), at: try await t.navEmptySpot())
            try await t.navFocus(row[0].id, pid: getpid())
            let mark = t.log.mark()
            let hops: [(key: Input.Key, to: Int)] = (1..<10).map { (.right, $0) } + [(.left, 8)]
            var timings: [String] = []
            for hop in hops {
                let target = row[hop.to]
                let m = t.log.mark()
                Input.key(hop.key, .maskControl)
                try await t.navLog("navigate to ", target.id, since: m, timeout: 3)
                timings.append(try await t.expectLog("glide timing:", since: m, timeout: 6))
                try await t.until("[\(target.id)]'s app in front", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid }
                try await t.pause(0.35)
            }
            // The typical hop, not every one: in a VM the window server stalls now and then (a
            // hop's prep or a frame gap of 100–300ms, the hops either side of it fine). Waiting
            // on an app would slow every hop.
            var preps: [Int] = [], firsts: [Int] = [], frames: [Int] = [], gaps: [Int] = []
            for line in timings {
                guard let m = line.firstMatch(of: #/prep (\d+)ms, first frame after (\d+)ms, (\d+) frames, max gap (\d+)ms/#),
                      let prep = Int(m.1), let first = Int(m.2), let n = Int(m.3), let gap = Int(m.4) else { throw Failure("can't read “\(line)”") }
                preps.append(prep); firsts.append(first); frames.append(n); gaps.append(gap)
            }
            let all = timings.joined(separator: "; ")
            try t.expectTiming(navMedian(preps) <= 50 && navMedian(firsts) <= 50, "hops should start straight away (prep \(preps) ms, first frame after \(firsts) ms): \(all)")
            try t.expectTiming(navMedian(frames) >= 8, "a glide of about 0.3s draws many more frames than \(frames): \(all)")
            try t.expectTiming(navMedian(gaps) <= 50, "glides should be smooth (max gaps \(gaps) ms): \(all)")
            let lines = t.log.lines(since: mark)
            let activations = lines.compactMap { line in line.firstMatch(of: #/^activation took (\d+)ms/#).flatMap { Int($0.1) } }.sorted()
            try t.expect(activations.count >= 5, "only \(activations.count) “activation took” lines for 10 hops between two apps")
            try t.expectTiming(navMedian(activations) <= 100 && activations.last! <= 500, "focus should land within a few tens of milliseconds (activation took \(activations) ms)")
            let s = try await t.settle()
            try t.expect(navCentred(s, row[8].id), "the last hop should leave the view centred on its window")
        },

        Case("NAV-31", "Chrome-based browsers move as quickly as other apps", .guided) { t in
            try t.needsInput()
            if let on = navMacArrowShortcuts([.left, .right]) { throw Skip("macOS takes ⌃← / ⌃→ itself (\(on)): turn them off in System Settings › Keyboard › Keyboard Shortcuts › Mission Control") }
            try await t.navReady()
            let browser = try await t.navBrowser(3)
            let mine = try await t.window("NAV-31 Another app")
            // Browser, ours, browser, browser.
            let ids = [browser.ids[0], mine.id, browser.ids[1], browser.ids[2]]
            let pids = [browser.pid, getpid(), browser.pid, browser.pid]
            _ = try await t.navRow(ids, at: try await t.navEmptySpot())
            let enhanced = navEnhancedUI(browser.pid)
            let mark = t.log.mark()
            try await t.navFocus(ids[0], pid: browser.pid)
            for (key, to) in [(Input.Key.right, 1), (.right, 2), (.right, 3), (.left, 2), (.left, 1), (.left, 0)] {
                let m = t.log.mark()
                Input.key(key, .maskControl)
                try await t.navLog("navigate to ", ids[to], since: m, timeout: 3)
                _ = try await t.expectLog("glide timing:", since: m, timeout: 6)
                try await t.until("[\(ids[to])]'s app in front", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pids[to] }
                try await t.pause(0.35)
            }
            var s = try await t.settle()
            for id in browser.ids { try t.navExpectInPlace(s, id, "\(browser.app) [\(id)]") }
            // Zoomed out, click the browser window furthest from here.
            Input.key(.grave, .maskAlternate)
            try await t.until("⌥` to zoom out") { try await t.state().active }
            s = try await t.settle()
            guard let farthest = s.window(ids[3]) else { throw Failure("the browser window left the canvas") }
            Input.click(at: s.screenPoint(navCentre(farthest.canvas)))
            try await t.until("\(browser.app) in front, the clicked window first", timeout: 4) {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == browser.pid && navFrontWindow(among: browser.ids) == ids[3]
            }
            try await t.until("back at 100% on the clicked window", timeout: 5) { let s = try await t.settle(); return !s.active && navCentred(s, ids[3]) }
            s = try await t.settle()
            for id in browser.ids { try t.navExpectInPlace(s, id, "\(browser.app) [\(id)]") }
            let lines = t.log.lines(since: mark)
            if let stall = lines.first(where: { $0.contains("gave up on windows landing") && $0.contains(browser.app) }) {
                throw Failure("\(browser.app)'s windows hadn't landed when the canvas handed back: \(stall)")
            }
            if let slow = lines.first(where: { $0.hasPrefix("slow: moving") && $0.contains("(\(browser.app):") }) {
                throw Failure("moving \(browser.app)'s windows was slow: \(slow)")
            }
            try t.expect(navEnhancedUI(browser.pid) == enhanced, "Chromium's animated moves (AXEnhancedUserInterface) should be back \(enhanced ? "on" : "off") after Expanse moved its windows")
        },

        Case("NAV-32", "Zooming out and straight back returns to the same view") { t in
            try t.needsInput()
            try await t.navReady()
            let spot = try await t.navEmptySpot()
            let ws = try await t.row(["NAV-32 A", "NAV-32 B", "NAV-32 C"], origin: spot)
            var s = try await t.navGlide(to: ws[1].id)
            // A and C partly on screen, at the left and right edges.
            let vis = s.visibleCanvas
            if let fa = s.window(ws[0].id)?.canvas { t.place(ws[0], at: CGPoint(x: (vis.minX - fa.width / 2).rounded(), y: fa.minY)) }
            if let fc = s.window(ws[2].id)?.canvas { t.place(ws[2], at: CGPoint(x: (vis.maxX - fc.width / 2).rounded(), y: fc.minY)) }
            s = try await t.settle()
            for (how, key, flags) in [("⌥` again", Input.Key.grave, CGEventFlags.maskAlternate), ("Esc", .escape, [])] {
                let before = try await t.settle()
                let real = ws.map(\.real)
                Input.key(.grave, .maskAlternate)
                try await t.until("⌥` to zoom out") { let s = try await t.state(); return s.active && s.idle }
                Input.key(key, flags)
                try await t.until("\(how) to go back to 100%") { try await !t.settle().active }
                let after = try await t.settle()
                try t.expect(abs(after.scale - 1) < 0.001, "⌥` then \(how) should leave the canvas at 100% (\(navPercent(after.scale)))")
                try t.expectNear(after.camera, before.camera, within: 0.5, "⌥` then \(how) should come back to exactly the same view")
                for (w, r) in zip(ws, real) {
                    try t.expect(after.window(w.id)?.parked == before.window(w.id)?.parked, "\(w.title) went \(after.window(w.id)?.parked == true ? "out of view" : "on screen")")
                    if let r, let now = w.real { try t.expectNear(now, r, within: 1, "\(w.title)'s real window after ⌥` then \(how)") }
                }
            }
        },

        Case("NAV-34", "Every hop centres its window when auto-centre is on") { t in
            try t.needsInput()
            if let on = navMacArrowShortcuts([.right]) { throw Skip("macOS takes ⌃→ itself (\(on)): turn it off in System Settings › Keyboard › Keyboard Shortcuts › Mission Control") }
            try await t.navReady()
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let (l, r, _) = try await t.navSideBySide("NAV-34")
            try await t.navClick(l)
            let mark = t.log.mark()
            Input.key(.right, .maskControl)
            try await t.navLog("navigate to ", r.id, since: mark, timeout: 3)
            try await t.navLog("glide to ", r.id, since: mark, timeout: 3)
            try await t.navHasKeyboard(r, "the right-hand window")
            try await t.until("the view centred on the right-hand window", timeout: 5) { let s = try await t.settle(); return navCentred(s, r.id) }
        },

        Case("NAV-36", "⌥` zooms out without waiting for a window scan", time: 240) { t in
            try t.needsInput()
            try await t.navReady()
            let many = try await t.fixture("NAV36", windows: 50, size: CGSize(width: 400, height: 280))
            try t.expect(many.windows.count == 50, "the fixture app opened \(many.windows.count) windows, not 50")
            try await t.until("Expanse to take on all 50", timeout: 40) {
                let s = try await t.state()
                return many.windows.allSatisfy { s.window($0) != nil }
            }
            try await t.settle(timeout: 15)
            // 1. Ten times: the canvas is up within a moment (a window scan takes seconds). Not
            // the very next answer: the link asking can reach Expanse before the key does.
            for i in 1...10 {
                // From Expanse's own lines, the key's arrival to "canvas up": not a dump (with 67
                // windows one takes a second or more to write in a VM, as each window's line asks
                // Accessibility where it is), and not counting how long the VM takes to deliver the
                // key or the log. A window scan takes seconds; waiting for one is what this catches.
                try await t.pause(0.3)
                let m = t.log.mark()
                Input.key(.grave, .maskAlternate)
                guard await t.log.wait(since: m, timeout: 10, { $0.hasPrefix("canvas up") }) != nil else {
                    throw Failure("round \(i): no “canvas up” within 10s of ⌥`")
                }
                let lines = t.log.timedLines(since: m)
                if let key = lines.first(where: { $0.line.hasPrefix("hotkey 1 pressed") }), let up = lines.first(where: { $0.line.hasPrefix("canvas up") }) {
                    try t.expect(up.time - key.time < 1.5, String(format: "round %d: the canvas came up %.1fs after Expanse got ⌥` (did it wait for a window scan?)", i, up.time - key.time))
                }
                // With 67 windows a VM's window server can hold a zoom up for seconds (NAV-38 is
                // the case about smoothness); what counts here is the canvas coming up at once.
                try await t.settle(timeout: 20)
                Input.key(.escape)
                try await t.until("round \(i): back at 100%", timeout: 20) { try await !t.settle(timeout: 20).active }
                try await t.pause(0.5)
            }
            // 2. A new window, then ⌥` straight away: a scan right after brings it onto the canvas.
            let w = try await t.window("NAV-36 New", CGRect(x: 300, y: 260, width: 500, height: 320), managed: false)
            Input.key(.grave, .maskAlternate)
            try await t.until("the canvas to open") { try await t.state().active }
            try await t.until("the new window on the zoomed-out canvas", timeout: 4) {
                let s = try await t.state()
                return s.active && s.window(w.id) != nil
            }
            Input.key(.escape)
        },

        Case("NAV-37", "One busy app doesn't hold up other apps' windows") { t in
            try t.needsInput()
            if let on = navMacArrowShortcuts([.right]) { throw Skip("macOS takes ⌃→ itself (\(on)): turn it off in System Settings › Keyboard › Keyboard Shortcuts › Mission Control") }
            try await t.navReady()
            let busy = try await t.fixture("NAV37", windows: 15, size: CGSize(width: 300, height: 200))
            guard let busyPID = busy.pid, busy.windows.count == 15 else { throw Failure("the busy app didn't open its 15 windows") }
            try await t.until("Expanse to take on the busy app's windows", timeout: 20) {
                let s = try await t.state()
                return busy.windows.allSatisfy { s.window($0) != nil }
            }
            let one = try await t.window("NAV-37 One")
            let two = try await t.window("NAV-37 Two")
            let spot = try await t.navEmptySpot()
            t.place(one, at: spot)
            t.place(two, at: CGPoint(x: spot.x + 3000, y: spot.y))
            var s = try await t.navGlide(to: one.id)
            // Some of the busy app's windows round One, on screen: the hop away has to park them.
            guard let f1 = s.window(one.id)?.canvas, let fb = s.window(busy.windows[0])?.canvas else { throw Failure("a window left the canvas") }
            let vis = s.visibleCanvas
            var spots: [CGPoint] = []
            for y in [f1.maxY + 20, f1.minY - 20 - fb.height] where y >= vis.minY + 2 && y + 60 <= vis.maxY {
                var x = vis.minX + 10
                while x + fb.width <= vis.maxX - 10 {
                    spots.append(CGPoint(x: x.rounded(), y: y.rounded()))
                    x += fb.width + 20
                }
            }
            for (id, p) in zip(busy.windows, spots) { t.navPlace(id, p) }
            s = try await t.settle()
            let busyOnScreen = busy.windows.filter { s.window($0)?.parked == false }
            try t.expect(busyOnScreen.count >= 2, "at least two of the busy app's windows should be on screen round One (\(busyOnScreen.count))")
            guard let f2 = s.window(two.id)?.canvas else { throw Failure("Two left the canvas") }
            let cam = navFocusCamera(f2, s)
            let wantTwo = CGPoint(x: f2.minX - cam.x + s.viewport.minX, y: f2.minY - cam.y + s.viewport.minY)
            try await t.navFocus(one)
            // The busy app stops answering, as one that's hung does (kill -STOP).
            kill(busyPID, SIGSTOP)
            defer { kill(busyPID, SIGCONT) }
            let mark = t.log.mark()
            Input.key(.right, .maskControl)
            try await t.navLog("glide to ", two.id, since: mark, timeout: 3)
            try await t.until("Two's real window in the middle of the screen", timeout: 1.5) {
                two.real.map { navDistance($0.origin, wantTwo) <= 2 } ?? false
            }
            try await t.until("One's real window parked", timeout: 1.5) {
                one.real.map { $0.minX > t.screen.maxX - 120 } ?? false
            }
            // e.g. "slow: moving 9 windows took 4521ms (Expanse Tests: 4519ms)": the busy app's.
            let slow = try await t.expectLog("slow: moving", since: mark, timeout: 20)
            guard let m = slow.firstMatch(of: #/took (\d+)ms \(.*: (\d+)ms\)/#), let total = Int(m.1), let slowest = Int(m.2) else {
                throw Failure("can't read “\(slow)”")
            }
            try t.expect(total >= 150 && slowest >= 150, "the slow app should be named with its time: \(slow)")
            kill(busyPID, SIGCONT)
            try await t.settle(timeout: 20)
        },

        Case("NAV-38", "Leaving the canvas doesn't freeze, even with 50 windows") { t in
            try t.needsInput()
            try await t.navReady()
            let many = try await t.fixture("NAV38", windows: 50, size: CGSize(width: 400, height: 280))
            guard let manyPID = many.pid, many.windows.count == 50 else { throw Failure("the fixture app opened \(many.windows.count) windows, not 50") }
            try await t.until("Expanse to take on all 50", timeout: 40) {
                let s = try await t.state()
                return many.windows.allSatisfy { s.window($0) != nil }
            }
            try await t.settle(timeout: 15)
            let away = try await t.window("NAV-38 Far away")
            t.place(away, at: try await t.navEmptySpot())
            try await t.navGlide(to: away.id)
            Input.key(.grave, .maskAlternate)
            try await t.until("⌥` to zoom out") { try await t.state().active }
            var s = try await t.settle()
            // One in the middle of the 50: leaving moves many real windows.
            let cluster = many.windows.compactMap { s.window($0) }
            guard let first = cluster.first else { throw Failure("the 50 windows left the canvas") }
            let middle = navCentre(cluster.map(\.canvas).reduce(first.canvas) { $0.union($1) })
            let target = cluster.min { navDistance(navCentre($0.canvas), middle) < navDistance(navCentre($1.canvas), middle) }!
            let mark = t.log.mark()
            Input.click(at: s.screenPoint(navCentre(target.canvas)))
            try await t.until("the clicked window's app in front, its window first", timeout: 4) {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == manyPID && navFrontWindow(among: many.windows) == target.id
            }
            try await t.until("back at 100% on the clicked window", timeout: 5) { let s = try await t.settle(); return !s.active && navCentred(s, target.id) }
            try await t.pause(0.5)
            s = try await t.settle()
            for w in cluster { try t.navExpectInPlace(s, w.id, "window [\(w.id)] of the 50") }
            let slow = t.log.lines(since: mark).first { $0.hasPrefix("slow: animation") }
            try t.expectTiming(slow == nil, "the zoom in wasn't smooth: \(slow ?? "")")
        },

        Case("NAV-39", "Hops start without waiting for the app") { t in
            try t.needsInput()
            if let on = navMacArrowShortcuts([.right]) { throw Skip("macOS takes ⌃→ itself (\(on)): turn it off in System Settings › Keyboard › Keyboard Shortcuts › Mission Control") }
            try await t.navReady()
            let busy = try await t.fixture("NAV39", windows: 2)
            guard let busyPID = busy.pid, busy.windows.count == 2 else { throw Failure("the busy app didn't open its 2 windows") }
            try await t.until("Expanse to take on the busy app's windows", timeout: 10) {
                let s = try await t.state()
                return busy.windows.allSatisfy { s.window($0) != nil }
            }
            let spot = try await t.navEmptySpot()
            t.navPlace(busy.windows[0], spot)
            t.navPlace(busy.windows[1], CGPoint(x: spot.x + 3000, y: spot.y))
            try await t.settle()
            // How long a link takes to show in the log here, to compare the hop with.
            var m = t.log.mark()
            var asked = Date()
            t.link("dump")
            guard await t.log.wait(since: m, timeout: 5, { $0.hasPrefix("dump viewport=") }) != nil else { throw Failure("Expanse didn't answer expanse://dump") }
            let baseline = Date().timeIntervalSince(asked)
            try await t.pause(0.6)
            // The busy app in front, with the window it's in known from its notifications.
            try await t.navFocus(busy.windows[0], pid: busyPID)
            kill(busyPID, SIGSTOP)
            defer { kill(busyPID, SIGCONT) }
            m = t.log.mark()
            asked = Date()
            Input.key(.right, .maskControl)
            try await t.navLog("navigate to ", busy.windows[1], since: m, timeout: 3)
            let started = Date().timeIntervalSince(asked)
            // Asking the stopped app which window it's in would take half a second (the time-out).
            try t.expect(started - baseline < 0.3, "the hop took \(Int(started * 1000))ms to start (a link shows in \(Int(baseline * 1000))ms): did Expanse ask the busy app which window it's in?")
            let timing = try await t.expectLog("glide timing:", since: m, timeout: 20)
            guard let match = timing.firstMatch(of: #/prep (\d+)ms/#), let prep = Int(match.1) else { throw Failure("can't read “\(timing)”") }
            // Over the limit, the "slow: glide prep" line says where the time went: only "fit" asks
            // the app anything (in a VM, "level", a window list, can take 100ms+ on its own).
            let parts = t.log.lines(since: m).first { $0.hasPrefix("slow: glide prep") } ?? ""
            try t.expectTiming(prep <= 50, "the glide's prep should stay small with a busy app in front: \(timing) \(parts)")
            kill(busyPID, SIGCONT)
            try await t.settle(timeout: 20)
        },

        Case("NAV-40", "A hop lands without flashing the old layout", .guided) { t in
            try t.needsInput()
            if let on = navMacArrowShortcuts([.left, .right]) { throw Skip("macOS takes ⌃← / ⌃→ itself (\(on)): turn them off in System Settings › Keyboard › Keyboard Shortcuts › Mission Control") }
            try await t.navReady()
            let browser = try await t.navBrowser(3)
            _ = try await t.navRow(browser.ids, at: try await t.navEmptySpot())
            try await t.ask("Watch the screen: once you press Done, Expanse Tests hops along the \(browser.app) windows with ⌃→ and back with ⌃←.")
            let mark = t.log.mark()
            try await t.navFocus(browser.ids[0], pid: browser.pid)
            let n = browser.ids.count
            let hops = Array(browser.ids.dropFirst()) + Array(browser.ids.dropLast().reversed())
            for (i, target) in hops.enumerated() {
                let m = t.log.mark()
                Input.key(i < n - 1 ? .right : .left, .maskControl)
                try await t.navLog("navigate to ", target, since: m, timeout: 3)
                _ = try await t.expectLog("glide timing:", since: m, timeout: 6)
                try await t.until("\(browser.app) in front", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == browser.pid }
                try await t.pause(0.6)
            }
            let s = try await t.settle()
            for id in browser.ids { try t.navExpectInPlace(s, id, "\(browser.app) [\(id)]") }
            try navExpectHandBacks(t, since: mark, app: browser.app)
            try await t.look("Did every hop land with the windows already in their new places: no flash of the old layout, and no other app's window blinking on top?")
        },

        Case("NAV-41", "Leaving the canvas onto a window doesn't flash either", .guided) { t in
            try t.needsInput()
            try await t.navReady()
            let browser = try await t.navBrowser(3)
            // Far apart, so the click is far from the view you left.
            let spot = try await t.navEmptySpot()
            for (i, id) in browser.ids.enumerated() { t.navPlace(id, CGPoint(x: spot.x + CGFloat(i) * 3000, y: spot.y)) }
            try await t.settle()
            try await t.navGlide(to: browser.ids[0])
            try await t.ask("Watch the screen: once you press Done, Expanse Tests zooms out and clicks the \(browser.app) window furthest from here. Watch it zoom in and the canvas drop away.")
            Input.key(.grave, .maskAlternate)
            try await t.until("⌥` to zoom out") { try await t.state().active }
            var s = try await t.settle()
            guard let far = s.window(browser.ids[2]) else { throw Failure("the browser window left the canvas") }
            let mark = t.log.mark()
            Input.click(at: s.screenPoint(navCentre(far.canvas)))
            try await t.until("\(browser.app) in front, the clicked window first", timeout: 4) {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == browser.pid && navFrontWindow(among: browser.ids) == far.id
            }
            try await t.until("back at 100% on the clicked window", timeout: 5) { let s = try await t.settle(); return !s.active && navCentred(s, far.id) }
            s = try await t.settle()
            for id in browser.ids { try t.navExpectInPlace(s, id, "\(browser.app) [\(id)]") }
            try navExpectHandBacks(t, since: mark, app: browser.app)
            try await t.look("When the canvas dropped away, was every window already in place, the clicked one in front, with nothing blinking?")
        },

        Case("NAV-42", "Clicking the minimap zooms out; clicking the bare desktop doesn't") { t in
            try t.needsInput()
            try await t.navReady()
            try await t.window("NAV-42 A")
            let s = try await t.navGoEmpty()
            guard let p = navBarePoint(s) else { throw Skip("there's no bare desktop on screen to click") }
            // 1. The bare desktop: Finder takes the click, as usual; the canvas stays shut.
            Input.click(at: p)
            if (CFPreferencesCopyAppValue("CreateDesktop" as CFString, "com.apple.finder" as CFString) as? Bool) ?? true {
                try await t.until("Finder to become active", timeout: 3) { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" }
            }
            try await t.pause(0.8)
            let after = try await t.settle()
            try t.expect(!after.active, "clicking the bare desktop opened the canvas")
            // 2. The minimap (its left part: parked windows peek in at the corner): it zooms out.
            let m = navMinimap(after)
            let q = CGPoint(x: m.minX + 60, y: m.midY + 8)
            if let cover = navOnScreenWindows().first(where: { $0.layer == 0 && $0.alpha > 0 && $0.frame.contains(q) }) {
                throw Skip("\(cover.owner)'s window covers the minimap")
            }
            Input.click(at: q)
            try await t.until("clicking the minimap to open the canvas", timeout: 3) { try await t.state().active }
            try t.navExpectOverview(try await t.settle(), "clicking the minimap")
        },

        Case("NAV-44", "⌃⌥C while zoomed out goes back to 100% on your window") { t in
            try t.needsInput()
            try await t.navReady()
            let spot = try await t.navEmptySpot()
            let ws = try await t.row(["NAV-44 X", "NAV-44 B", "NAV-44 C"], origin: spot)
            let x = ws[0]
            try await t.navFocus(x)
            Input.key(.grave, .maskAlternate)
            try await t.until("⌥` to zoom out") { try await t.state().active }
            var s = try await t.settle()
            // Pan away from X.
            Input.move(to: CGPoint(x: s.viewport.midX, y: s.viewport.minY + s.viewport.height * 0.4))
            Input.trackpadScroll(dx: -300, dy: 200, steps: 10)
            try await t.pause(0.3)
            s = try await t.settle()
            try t.expect(s.active, "panning left the canvas")
            let mark = t.log.mark()
            Input.key(.c, [.maskControl, .maskAlternate])
            try await t.navLog("centre ", x.id, since: mark, timeout: 3)
            try await t.navHasKeyboard(x, "X")
            try await t.until("back at 100% on X", timeout: 5) { let s = try await t.settle(); return !s.active && navCentred(s, x.id) }
        },

        Case("NAV-46", "animationSlowdown makes camera moves slower") { t in
            // Animated, whatever Reduce Motion says: low motion has nothing to slow down.
            setExpanseDefault("motion", "glide")
            defer { setExpanseDefault("motion", nil) }
            try t.needsInput()
            if let on = navMacArrowShortcuts([.right]) { throw Skip("macOS takes ⌃→ itself (\(on)): turn it off in System Settings › Keyboard › Keyboard Shortcuts › Mission Control") }
            try await t.navReady()
            let key = "animationSlowdown"
            let old = expanseDefault(key)
            // It's read at launch: each setting needs a restart, and so does putting it back.
            @MainActor func measured(_ value: Any?, _ tag: String) async throws -> (zoomBusy: Bool, glide: Double, frames: Int) {
                setExpanseDefault(key, value)
                do {
                    try await t.relaunchExpanse()
                    return try await navMeasureMoves(t, tag)
                } catch {
                    setExpanseDefault(key, old)
                    try? await t.relaunchExpanse()
                    throw error
                }
            }
            let slow = try await measured(3.0, "slowed")
            let normal = try await measured(nil, "normal")
            setExpanseDefault(key, old)
            if old != nil { try await t.relaunchExpanse() }
            try t.expect(slow.zoomBusy, "with animationSlowdown 3, ⌥`'s zoom should still be going 0.35s in (it takes 0.66s)")
            try t.expect(!normal.zoomBusy, "without animationSlowdown, ⌥`'s zoom should be over 0.35s in (it takes 0.22s)")
            let slowGlide = String(format: "%.2f", slow.glide), normalGlide = String(format: "%.2f", normal.glide)
            let longer = slow.glide - normal.glide
            try t.expect(longer > 0.4, "with animationSlowdown 3 a hop's glide should take about 0.6s longer (0.9s, not 0.3s): \(slowGlide)s against \(normalGlide)s")
            let ratio = Double(slow.frames) / Double(max(normal.frames, 1))
            try t.expect(ratio > 2 && ratio < 4.5, "a glide drew \(slow.frames) frames with animationSlowdown 3 and \(normal.frames) without: about three times as many expected")
        },

        Case("NAV-47", "After you pan at 100%, clicking a window you can see doesn't recentre") { t in
            try t.needsInput()
            try await t.navReady()
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let spot = try await t.navEmptySpot()
            let ws = try await t.row(["NAV-47 A", "NAV-47 B"], origin: spot)
            try await t.navGlide(to: ws[0].id)
            // 1–3. Scroll on the desktop, Space-drag B a third onto the screen, Esc.
            let placed = try await t.navPlaceView(partly: ws[1])
            // 4. Click B.
            let mark = t.log.mark()
            try await t.navClick(ws[1])
            let line = try await t.navFocusOutcome(ws[1].id, since: mark)
            try t.expect(line.hasPrefix("view placed by you: ") && line.contains("[\(ws[1].id)] focused where it is"),
                         "B, partly on screen in a view you placed, should get focus where it is: \(line)")
            try await t.pause(0.8)
            let after = try await t.settle()
            try t.expect(!after.active, "clicking B opened the canvas")
            try t.expectNear(after.camera, placed.camera, within: 0.5, "clicking B, partly on screen in a view you placed, moved the view")
            try await t.noLog("glide to ", since: mark, within: 0.1)
        },

        Case("NAV-49", "The next glide, zoom or display change ends the placed view") { t in
            try t.needsInput()
            try await t.navReady()
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let spot = try await t.navEmptySpot()
            let ws = try await t.row(["NAV-49 A", "NAV-49 B"], origin: spot)
            let a = ws[0], b = ws[1]
            // One window to click after each, never focused before, out of the way until then.
            var targets: [TestWindow] = []
            for name in ["Hop", "Zoom", "Display"] { targets.append(try await t.window("NAV-49 After \(name)")) }
            for (i, w) in targets.enumerated() { t.place(w, at: CGPoint(x: spot.x + 6000 + CGFloat(i) * 1000, y: spot.y + 3000)) }
            try await t.settle()

            /// Step 2: `w` partly on screen at the right edge, clicked: the view glides to centre it.
            @MainActor func clickRecentres(_ w: TestWindow, after what: String) async throws {
                let s = try await t.settle()
                guard let f = s.window(w.id)?.canvas else { throw Failure("“\(w.title)” isn't on the canvas") }
                t.place(w, at: CGPoint(x: (s.visibleCanvas.maxX - f.width / 3).rounded(), y: (s.visibleCanvas.midY - f.height / 2).rounded()))
                try await t.until("“\(w.title)” partly on screen", timeout: 4) {
                    guard let r = w.real else { return false }
                    return r.minX < t.screen.maxX - 100 && r.maxX > t.screen.maxX
                }
                // In front of B, which the placed view left cut off at the same edge: the click is
                // for this window (without the keyboard yet: that's the click's to give).
                w.window.orderFrontRegardless()
                try await t.pause(0.5)
                let mark = t.log.mark()
                try await t.navClick(w)
                let line = try await t.navFocusOutcome(w.id, since: mark)
                try t.expect(line.hasPrefix("focus-settled glide to ") && line.contains("]: on screen at"),
                             "after \(what), clicking a window partly on screen should glide to centre it: \(line)")
                try await t.until("the view centred on “\(w.title)”", timeout: 5) { let s = try await t.settle(); return navCentred(s, w.id) }
            }

            var skipped: [String] = []
            // 1. A hop.
            if let on = navMacArrowShortcuts([.right]) {
                skipped.append("the hop (macOS takes ⌃→: \(on))")
            } else {
                try await t.navGlide(to: a.id)
                _ = try await t.navPlaceView(partly: b)
                try await t.navClick(a)
                let mark = t.log.mark()
                Input.key(.right, .maskControl)
                try await t.navLog("glide to ", b.id, since: mark, timeout: 3)
                try await clickRecentres(targets[0], after: "a hop")
            }
            // 3. A zoom: ⌘ + scroll.
            try await t.navGlide(to: a.id)
            _ = try await t.navPlaceView(partly: b)
            var mark = t.log.mark()
            t.link("enter", ["zoomOut": 0])
            try await t.until("the canvas at 100%") { try await t.state().active }
            var s = try await t.settle()
            Input.move(to: CGPoint(x: s.viewport.midX, y: s.viewport.midY))
            Input.trackpadScroll(dy: 20, steps: 2, flags: .maskCommand)
            try await t.pause(0.3)
            s = try await t.settle()
            try t.expect(abs(s.scale - 1) > 0.01, "⌘ + scroll should zoom (\(navPercent(s.scale)))")
            Input.key(.escape)
            try await t.until("back at 100%") { try await !t.settle().active }
            try await t.noLog("view placed by you", since: mark, within: 0.5)
            try await clickRecentres(targets[1], after: "a zoom")
            // 3. A display change (pretend, and back).
            try await t.navGlide(to: a.id)
            _ = try await t.navPlaceView(partly: b)
            for size in [CGSize(width: t.screen.width - 200, height: t.screen.height - 100), nil] {
                mark = t.log.mark()
                if let size { t.link("screen", ["w": Int(size.width), "h": Int(size.height)]) } else { t.link("screen") }
                try await t.expectLog("display changed:", since: mark, timeout: 10)
                try await t.expectLog("layout fitted:", since: mark, timeout: 10)
                try await t.settle()
            }
            try await clickRecentres(targets[2], after: "a display change")
            if !skipped.isEmpty { throw Skip("the rest passed; skipped \(skipped.joined(separator: ", "))") }
        },

        Case("NAV-50", "Scrolling over a window doesn't open the canvas") { t in
            // Step 3, a pinch without ⌥ over a window, is NAV-07's second step (it needs a person).
            try t.needsInput()
            try await t.navReady()
            let w = try await t.window("NAV-50 Page")
            try await t.navGlide(to: w.id)
            var notTried: [String] = []
            @MainActor func scrollDoesNothing(at p: CGPoint, _ what: String, dx: Int32 = 0, dy: Int32 = 60) async throws {
                Input.move(to: p)
                try await t.pause(0.2)
                Input.trackpadScroll(dx: dx, dy: dy, steps: 6)
                try await t.pause(0.6)
                let after = try await t.settle()
                try t.expect(!after.active, "a two-finger scroll over \(what) opened the canvas")
            }
            // 1. Over the window.
            guard let r = w.real?.intersection(t.screen), !r.isNull else { throw Failure("the window isn't on screen") }
            try await scrollDoesNothing(at: CGPoint(x: r.midX, y: r.midY), "a window")
            // 2. Over the menu bar…
            let bar = CGPoint(x: t.screen.midX + 120, y: 6)
            if navCovered(bar) { try await scrollDoesNothing(at: bar, "the menu bar") } else { notTried.append("the menu bar (hidden)") }
            // …the Dock, sideways (an upward scroll on an icon can show its windows)…
            let dockLevel = Int(CGWindowLevelForKey(.dockWindow)), maxHeight = t.screen.height / 3
            func isDock(_ w: NavWindowInfo) -> Bool {
                w.owner == "Dock" && w.layer == dockLevel && w.frame.height < maxHeight && w.frame.width > 40
            }
            if let dock = navOnScreenWindows().first(where: isDock) {
                try await scrollDoesNothing(at: CGPoint(x: dock.frame.midX, y: dock.frame.midY), "the Dock", dx: 40, dy: 0)
            } else {
                notTried.append("the Dock (hidden)")
            }
            // …and another app's floating panel.
            let s = try await t.settle()
            guard let q = navBarePoint(s) else { throw Skip("there's no room on screen for a panel") }
            let panel = NSPanel(contentRect: appKitRect(CGRect(x: q.x - 160, y: q.y - 90, width: 320, height: 180)),
                                styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "NAV-50 Panel"
            panel.isFloatingPanel = true
            panel.isReleasedWhenClosed = false
            panel.orderFrontRegardless()
            defer { panel.close() }
            try await t.pause(1)
            try await scrollDoesNothing(at: q, "another app's panel")
            if !notTried.isEmpty { throw Skip("the rest passed; not tried: \(notTried.joined(separator: ", "))") }
        },

        Case("NAV-62", "A wheel on the bare desktop opens the canvas, under an invisible window or with Expanse in front") { t in
            try t.needsInput()
            try await t.navReady()
            try await t.window("NAV-62 A")
            let s = try await t.navGoEmpty()
            guard let p = navBarePoint(s) else { throw Skip("there's no bare desktop on screen to scroll on") }
            Input.move(to: p)
            try await t.pause(0.2)
            // A notch: the canvas opens at 100% (the rest of the turn moves it).
            navWheel(dy: -2)
            do {
                try await t.until("the wheel to open the canvas", timeout: 2) { try await t.state().active }
            } catch {
                let listed = navOnScreenWindows().filter { $0.layer >= 0 && $0.alpha > 0 && $0.frame.contains(p) }.map { "\($0.owner) (layer \($0.layer))" }
                throw Failure("a mouse wheel on the bare desktop at \(p) didn't open the canvas (listed over it: \(listed.isEmpty ? "nothing" : listed.joined(separator: ", ")))")
            }
            let opened = try await t.settle()
            try t.expect(abs(opened.scale - 1) < 0.001, "the canvas should open at 100% (\(navPercent(opened.scale)))")
            // Notches a pause apart, each a scroll of its own: each moves the view on (24pt down).
            for n in 1...3 {
                navWheel(dy: -2)
                try await t.pause(0.5)
                let now = try await t.settle()
                try t.expect(now.camera.y - opened.camera.y >= CGFloat(n) * 24 - 2,
                             "notch \(n) should have moved the view \(n * 24)pt down from where the canvas opened; it's \(Int(now.camera.y - opened.camera.y))pt")
            }
            Input.key(.escape)
            try await t.until("Esc to go back to 100%") { try await !t.settle().active }
        },

        Case("NAV-52", "A mouse-wheel scroll snaps after a short pause") { t in
            try t.needsInput()
            try await t.navReady()
            let count = Int(t.screen.width / 620) + 3
            let spot = try await t.navEmptySpot()
            let ws = try await t.row((1...count).map { "NAV-52 \($0)" }, origin: spot)
            try await t.navGlide(to: ws[0].id)
            t.link("enter", ["zoomOut": 0])
            try await t.until("the canvas at 100%") { try await t.state().active }
            var s = try await t.settle()
            // The second window cut off by the left edge, the row level with the middle of the screen,
            // and the third's left edge where the ticks (12pt each) leave it 30pt short of lining up
            // 20pt in: a wheel's snap goes no further than 40pt, and only on its way (NAV-63).
            guard let f2 = s.window(ws[2].id)?.canvas else { throw Failure("a window left the canvas") }
            let target = CGPoint(x: f2.minX - 20 - 30 - 72, y: (f2.midY - s.viewport.height / 2).rounded())
            t.link("pan", ["dx": Int((s.camera.x - target.x).rounded()), "dy": Int((s.camera.y - target.y).rounded())])
            try await t.until("the view moved there") { let s = try await t.settle(); return navDistance(s.camera, target) < 2 }
            s = try await t.settle()
            Input.move(to: CGPoint(x: s.viewport.midX, y: s.viewport.minY + s.viewport.height * 0.4))
            try await t.pause(0.2)
            let mark = t.log.mark()
            // Sideways ticks a sixth of a second apart: no snap until they stop.
            for _ in 0..<6 {
                navWheel(dx: -1, dy: 0)
                try await t.pause(0.15)
            }
            let line = try await t.expectLog("scroll ended: view snapped by", since: mark, timeout: 2)
            try await t.pause(0.8)
            let snaps = t.log.lines(since: mark).filter { $0.hasPrefix("scroll ended: view snapped by") }.count
            try t.expect(snaps == 1, "the view snapped \(snaps) times: it should wait until the wheel stops")
            let after = try await t.settle()
            guard let m = line.firstMatch(of: #/snapped by (-?[0-9.]+), (-?[0-9.]+)/#), let dx = Double(m.1), let dy = Double(m.2) else {
                throw Failure("can't read “\(line)”")
            }
            try t.expect(abs(after.scale - 1) < 0.001 && after.active, "the canvas should still be up at 100%")
            let vw = after.viewport.width, vh = after.viewport.height
            try t.expect(abs(dx) <= vw / 2 && abs(dy) <= vh / 2, "the snap moved more than half a screen: \(line)")
            let before = CGPoint(x: after.camera.x - dx, y: after.camera.y - dy)
            let screen = CGRect(x: 0, y: 0, width: vw, height: vh)
            @MainActor func views(_ camera: CGPoint) -> [CGRect] {
                ws.compactMap { after.window($0.id)?.canvas }.map { $0.offsetBy(dx: -camera.x, dy: -camera.y) }
            }
            func cut(_ rs: [CGRect]) -> Int { rs.filter { !$0.intersection(screen).isEmpty && !screen.contains($0) }.count }
            let was = views(before), now = views(after.camera)
            try t.expect(cut(now) <= cut(was), "the snap should leave fewer windows cut off (\(cut(was)) before, \(cut(now)) after)")
            try t.expect(now.contains { screen.contains($0) }, "the snap should leave at least one window whole")
            try t.expect(now.contains { abs($0.minX - 20) < 1.5 || abs($0.maxX - (vw - 20)) < 1.5 || abs($0.midX - vw / 2) < 1.5 },
                         "the snap should line a window's edge up 20pt in from the screen's edge")
            Input.key(.escape)
        },

        // MARK: Groups (NAV-55 to NAV-60)

        Case("NAV-55", "Windows arranged to fit the screen together are a group") { t in
            let (a, b, c) = try await navGroupScene(t)
            // Going to B frames B and C together.
            var mark = t.log.mark()
            t.link("focus", ["id": b.id])
            try await t.expectLog("[\(b.id)] (group of 2)", since: mark)
            try await t.until("the view framing B and C", timeout: 8) { let s = try await t.settle(); return s.isViewOn(b.id) }
            let s = try await t.settle()
            guard let fb = s.window(b.id)?.canvas, let fc = s.window(c.id)?.canvas else { throw Failure("B or C left the canvas") }
            try t.expect(s.viewport.contains(s.screenPoint(fb.origin)) && s.viewport.contains(s.screenPoint(CGPoint(x: fc.maxX, y: fc.maxY))),
                         "framing the group should show all of B and C")
            try t.expect(s.screenGroup(of: a.id) == nil, "A, on its own, shouldn't be in a group")
            // Moved more than 40pt from B, C is on its own: going to it centres it alone.
            t.place(c, at: CGPoint(x: fb.maxX + 60, y: fb.minY))
            try await t.settle()
            mark = t.log.mark()
            t.link("focus", ["id": c.id])
            try await t.navLog("glide to ", c.id, since: mark)
            try await t.noLog("(group of", since: mark, within: 1)
            try await t.until("the view centred on C alone", timeout: 8) { try await t.settle().isViewOn(c.id) }
            try t.expect(try await t.state().screenGroup(of: c.id) == nil, "B and C 60pt apart shouldn't be a group")
        },

        Case("NAV-56", "A hop to a window in a group frames the whole group") { t in
            try t.needsInput()
            if let on = navMacArrowShortcuts([.right]) { throw Skip("macOS takes ⌃→ itself (\(on))") }
            let (a, b, _) = try await navGroupScene(t)
            try await t.navGlide(to: a.id)
            try await t.navClick(a)
            let mark = t.log.mark()
            Input.key(.right, .maskControl)
            try await t.expectLog("[\(b.id)] (group of 2)", since: mark)
            try await t.until("the view framing B's group", timeout: 8) { try await t.settle().isViewOn(b.id) }
            try await t.navHasKeyboard(b, "B, the window the hop reached")
        },

        Case("NAV-57", "Hops between the windows of a group on screen only move focus") { t in
            try t.needsInput()
            if let on = navMacArrowShortcuts([.right, .left]) { throw Skip("macOS takes ⌃← or ⌃→ itself (\(on))") }
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let (_, b, c) = try await navGroupScene(t)
            let d = try await t.window("NAV-57 D", CGRect(x: 300, y: 300, width: 600, height: 400))
            guard let fc = try await t.state().window(c.id)?.canvas else { throw Failure("C isn't on the canvas") }
            t.place(d, at: CGPoint(x: fc.maxX + 3000, y: fc.minY))
            try await t.navGlide(to: b.id)
            try await t.navClick(b)
            let view = try await t.settle().camera
            // Inside the group: focus moves, the view stays.
            for (key, to) in [(Input.Key.right, c), (.left, b)] {
                let mark = t.log.mark()
                Input.key(key, .maskControl)
                try await t.navHasKeyboard(to, "\(to.title), the hop's window")
                try await t.noLog("glide to ", since: mark, within: 1)
                try t.expectNear(try await t.settle().camera, view, within: 1, "a hop inside the group moved the view")
            }
            // From the group's edge, the hop leaves it.
            try await t.navClick(c)
            let mark = t.log.mark()
            Input.key(.right, .maskControl)
            try await t.navLog("glide to ", d.id, since: mark)
            try await t.until("the view on D", timeout: 8) { try await t.settle().isViewOn(d.id) }
        },

        Case("NAV-58", "Clicking a window in a group zoomed out zooms to the group") { t in
            try t.needsInput()
            let (a, b, c) = try await navGroupScene(t)
            for (picked, alone) in [(c, false), (a, true)] {
                try await t.navGlide(to: b.id)
                t.link("enter")
                try await t.until("zoomed out") { try await t.settle().active }
                let s = try await t.settle()
                guard let f = s.window(picked.id)?.canvas else { throw Failure("\(picked.title) isn't on the canvas") }
                Input.click(at: s.screenPoint(CGPoint(x: f.midX, y: f.midY)))
                try await t.until("back at 100%") { try await !t.settle().active }
                try await t.until(alone ? "the view centred on A" : "the view framing C's group", timeout: 8) { try await t.settle().isViewOn(picked.id) }
                try await t.navHasKeyboard(picked, "\(picked.title), the window clicked")
            }
        },

        Case("NAV-59", "⌃⌥C frames the group of the window you're in") { t in
            try t.needsInput()
            let (_, b, c) = try await navGroupScene(t)
            try await t.navGlide(to: b.id)
            try await t.navClick(b)
            // The group moved half off screen (its windows moved, the view didn't); you're still in B.
            for w in [b, c] {
                guard let f = try await t.state().window(w.id)?.canvas else { throw Failure("\(w.title) left the canvas") }
                t.place(w, at: CGPoint(x: f.minX + 700, y: f.minY))
            }
            try await t.settle()
            b.focus()
            try await t.navHasKeyboard(b, "B")
            try t.expect(!(try await t.settle().isViewOn(b.id)), "the group should be off its framing before ⌃⌥C")
            Input.key(.c, [.maskControl, .maskAlternate])
            try await t.until("⌃⌥C framing B's group", timeout: 8) { try await t.settle().isViewOn(b.id) }
            try await t.navHasKeyboard(b, "B, after ⌃⌥C")
            // Zoomed out and panned: ⌃⌥C goes back to 100%, the group framed.
            t.link("enter")
            try await t.until("zoomed out") { try await t.settle().active }
            t.link("pan", ["dx": 400, "dy": 200])
            try await t.settle()
            Input.key(.c, [.maskControl, .maskAlternate])
            try await t.until("back at 100% framing B's group", timeout: 8) { let s = try await t.settle(); return !s.active && s.isViewOn(b.id) }
        },

        Case("NAV-60", "Zoomed out, hovering a window in a group outlines the group", .look) { t in
            try t.needsInput()
            let (a, b, _) = try await navGroupScene(t)
            try await t.navGlide(to: b.id)
            t.link("enter")
            try await t.until("zoomed out") { try await t.settle().active }
            let s = try await t.settle()
            guard let fb = s.window(b.id)?.canvas, let fa = s.window(a.id)?.canvas else { throw Failure("A or B isn't on the canvas") }
            Input.glide(to: s.screenPoint(CGPoint(x: fb.midX, y: fb.midY)))
            try await t.look("Hovering B: a soft accent outline around both B and C, a little outside them?")
            Input.glide(to: s.screenPoint(CGPoint(x: fa.midX, y: fa.midY)))
            try await t.look("Hovering A, on its own: only A's own outline, no group outline?")
        },
        Case("NAV-64", "Low motion: hops, zooming out and going back jump to where they end") { t in
            setExpanseDefault("motion", "jump")
            defer { setExpanseDefault("motion", nil) }
            // Too far apart to be a group, so going from one to the other moves the view.
            let ws = try await t.row(["NAV-64 A", "NAV-64 B"], gap: 900)
            let (a, b) = (ws[0], ws[1])
            try await t.pause(0.5)
            var mark = t.log.mark()
            let there = try await t.navGlide(to: b.id)
            try t.expect(navCentred(there, b.id), "the view should be on B")
            try await t.expectLog("low motion: the view jumps", since: mark)
            let timing = try await t.expectLog("glide timing:", since: mark, timeout: 6)
            try t.expect(timing.contains(" 1 frames"), "a jump should take one frame: \(timing)")
            // Over, and handed back: B has the keyboard's app in front, not the canvas.
            try await t.until("the canvas gone after the jump") { !(try await t.settle().active) }
            mark = t.log.mark()
            t.link("enter")
            try await t.until("zoomed out") { try await t.settle().active }
            try await t.expectLog("low motion: the view jumps", since: mark)
            mark = t.log.mark()
            t.link("exit")
            try await t.until("back at 100%") { !(try await t.settle().active) }
            try await t.expectLog("low motion: the view jumps", since: mark)
            // A change counts from the next move, without a restart.
            setExpanseDefault("motion", "glide")
            try await t.pause(0.5)
            mark = t.log.mark()
            let back = try await t.navGlide(to: a.id)
            try t.expect(navCentred(back, a.id), "the view should be on A")
            try await t.noLog("low motion: the view jumps", since: mark, within: 0.5)
        },
    ]
}

// MARK: - Helpers (NAV only)

/// Where a canvas rect is on screen (global CG) at the state's camera.
private func navScreenRect(_ s: ExpanseState, _ r: CGRect) -> CGRect {
    let o = s.screenPoint(r.origin)
    return CGRect(x: o.x, y: o.y, width: r.width * s.scale, height: r.height * s.scale)
}

private func navCentre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

private func navDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

/// How far a point is from a rect (0 inside it).
private func navDistance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
    hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
}

private func navPercent(_ scale: CGFloat) -> String { String(format: "%.1f%%", Double(scale) * 100) }

/// The canvas point in the middle of the screen.
private func navViewCentre(_ s: ExpanseState) -> CGPoint { navCentre(s.visibleCanvas) }

/// The canvas point under a screen point (global CG).
private func navCanvasPoint(_ s: ExpanseState, _ p: CGPoint) -> CGPoint {
    CGPoint(x: (p.x - s.viewport.minX) / s.scale + s.camera.x, y: (p.y - s.viewport.minY) / s.scale + s.camera.y)
}

/// The camera that centres a window at 100% (CanvasController.focusCamera: top-aligned if it's
/// taller than the screen).
private func navFocusCamera(_ f: CGRect, _ s: ExpanseState) -> CGPoint {
    let v = s.viewport.size
    let x = (v.width - f.width) / 2
    let y = f.height > v.height ? 0 : (v.height - f.height) / 2
    return CGPoint(x: (f.minX - x).rounded(), y: (f.minY - y).rounded())
}

/// The view is at 100% on window `id`, as a glide or a dive leaves it: centred, or its group
/// framed (ExpanseState.isViewOn).
private func navCentred(_ s: ExpanseState, _ id: CGWindowID) -> Bool {
    s.isViewOn(id)
}

/// ⌥`'s view (CanvasController.overviewCamera): every window in view with 80pt of canvas round
/// them, centred, at 60% at most and 3% at least.
private func navOverview(_ s: ExpanseState) -> (centre: CGPoint, scale: CGFloat)? {
    guard let first = s.windows.first?.canvas else { return nil }
    let b = s.windows.map(\.canvas).reduce(first) { $0.union($1) }.insetBy(dx: -80, dy: -80)
    return (navCentre(b), max(min(s.viewport.width / b.width, s.viewport.height / b.height, 0.6), 0.03))
}

/// Where the minimap is (global CG): 208×136, 16pt in from the bottom right of the canvas.
private func navMinimap(_ s: ExpanseState) -> CGRect {
    CGRect(x: s.viewport.maxX - 16 - 208, y: s.viewport.maxY - 16 - 136, width: 208, height: 136)
}

private struct NavWindowInfo {
    let owner: String
    let pid: pid_t
    let id: CGWindowID
    let layer: Int
    let alpha: Double
    let frame: CGRect
}

/// The window server's on-screen windows, front to back, without the desktop's own: the list
/// Expanse checks before taking a scroll or pinch on the desktop (handleDesktopGesture).
private func navOnScreenWindows() -> [NavWindowInfo] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        guard let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) else { return nil }
        return NavWindowInfo(owner: w[kCGWindowOwnerName as String] as? String ?? "?", pid: w[kCGWindowOwnerPID as String] as? pid_t ?? 0,
                             id: w[kCGWindowNumber as String] as? CGWindowID ?? 0, layer: w[kCGWindowLayer as String] as? Int ?? 0,
                             alpha: w[kCGWindowAlpha as String] as? Double ?? 1, frame: r)
    }
}

/// A window (app windows, the Dock, the menu bar, panels) is at `p`, as Expanse sees it.
/// The one a click there would reach, as the window server works it out (and Expanse asks): not
/// every window listed there. Some are invisible and let everything through, like the one
/// Notification Center keeps over the whole screen on macOS 27.
@MainActor private func navCovered(_ p: CGPoint) -> Bool {
    guard let id = navHit(p) else { return false }
    return navOnScreenWindows().contains { $0.id == id && $0.layer >= 0 }
}

/// The window a click at `p` (global) would reach; nil for none (the desktop's own windows count
/// as none only if they're left out of navOnScreenWindows, which leaves them out).
@MainActor private func navHit(_ p: CGPoint) -> CGWindowID? {
    let h = NSScreen.screens.first?.frame.height ?? 0
    let n = NSWindow.windowNumber(at: NSPoint(x: p.x, y: h - p.y), belowWindowWithWindowNumber: 0)
    return n > 0 ? CGWindowID(n) : nil
}

/// Windows listed on screen above the desktop that do take clicks somewhere: one of their middle
/// and corners (24pt in) reaches them.
@MainActor private func navSolidWindows() -> [NavWindowInfo] {
    navOnScreenWindows().filter { w in
        guard w.layer >= 0, w.alpha > 0 else { return false }
        let r = w.frame.insetBy(dx: min(24, w.frame.width / 3), dy: min(24, w.frame.height / 3))
        return [CGPoint(x: r.midX, y: r.midY), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)].contains { navHit($0) == w.id }
    }
}

/// Which of `ids` (one app's windows) is in front, as the window server has them.
private func navFrontWindow(among ids: [CGWindowID]) -> CGWindowID? {
    navOnScreenWindows().first { $0.layer == 0 && ids.contains($0.id) }?.id
}

/// A point on the bare desktop: no window there that takes clicks (as Expanse checks), none of the canvas's windows
/// or their pictures, clear of the minimap and Spaces panels along the bottom right and of the
/// screen's corners. The one furthest from all of those; nil if nothing is clear by 24pt.
@MainActor private func navBarePoint(_ s: ExpanseState) -> CGPoint? {
    let vp = s.viewport
    var blocked = navSolidWindows().map(\.frame)
    blocked += s.windows.map { navScreenRect(s, $0.canvas) }
    blocked.append(CGRect(x: vp.midX, y: vp.maxY - 200, width: vp.width / 2, height: 200))
    var spots: [(point: CGPoint, clear: CGFloat)] = []
    for y in stride(from: vp.minY + 50, to: vp.maxY - 120, by: 40) {
        for x in stride(from: vp.minX + 60, to: vp.maxX - 60, by: 40) {
            let p = CGPoint(x: x, y: y)
            let clear = blocked.map { navDistance(p, $0) }.min() ?? .greatestFiniteMagnitude
            if clear >= 24 { spots.append((p, clear)) }
        }
    }
    // The clearest where a click (as Expanse asks) reaches nothing, there or 24pt around: a window
    // that takes clicks in only part of it, like Stage Manager's strip of apps at the left, is
    // left out of `blocked`.
    return spots.sorted { $0.clear > $1.clear }.first { spot in
        [CGPoint.zero, CGPoint(x: 24, y: 0), CGPoint(x: -24, y: 0), CGPoint(x: 0, y: 24), CGPoint(x: 0, y: -24)]
            .allSatisfy { !navCovered(CGPoint(x: spot.point.x + $0.x, y: spot.point.y + $0.y)) }
    }?.point
}

/// macOS's own shortcuts on ⌃ + arrows (Mission Control › Move left / right a space, Mission
/// Control, Application windows) take the keys before Expanse's hops. Nil when the ones for
/// `keys` are off; otherwise their names. On unless the setting says off (as on a new Mac).
private func navMacArrowShortcuts(_ keys: [Input.Key]) -> String? {
    let ids: [Input.Key: (id: String, name: String)] = [.left: ("79", "Move left a space"), .right: ("81", "Move right a space"),
                                                        .up: ("32", "Mission Control"), .down: ("33", "Application windows")]
    let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any] ?? [:]
    let on = keys.compactMap { key -> String? in
        guard let shortcut = ids[key] else { return nil }
        let enabled = ((all[shortcut.id] as? [String: Any])?["enabled"] as? Bool) ?? true
        return enabled ? shortcut.name : nil
    }
    return on.isEmpty ? nil : on.joined(separator: ", ")
}

/// The main display's corners Expanse's hot corner watches (its setting; All corners by default),
/// less any where macOS has a hot corner of its own (System Settings › Desktop & Dock › Hot
/// Corners), which would fire too.
@MainActor private func navHotCorners(_ t: Ctx) throws -> (free: [(name: String, point: CGPoint)], taken: [String]) {
    let setting = expanseDefault("hotCorner") as? String ?? "all"
    guard setting != "off" else { throw Skip("Expanse's hot corner is off (menu bar panel › Hot corner)") }
    let s = t.screen
    let corners: [(raw: String, name: String, dock: String, point: CGPoint)] = [
        ("topLeft", "top-left", "wvous-tl-corner", CGPoint(x: s.minX, y: s.minY)),
        ("topRight", "top-right", "wvous-tr-corner", CGPoint(x: s.maxX - 1, y: s.minY)),
        ("bottomLeft", "bottom-left", "wvous-bl-corner", CGPoint(x: s.minX, y: s.maxY - 1)),
        ("bottomRight", "bottom-right", "wvous-br-corner", CGPoint(x: s.maxX - 1, y: s.maxY - 1)),
    ]
    var free: [(name: String, point: CGPoint)] = [], taken: [String] = []
    for c in corners where setting == "all" || setting == c.raw {
        // 0 and 1 are "–" (no action).
        let action = CFPreferencesCopyAppValue(c.dock as CFString, "com.apple.dock" as CFString) as? Int ?? 0
        if action > 1 { taken.append(c.name) } else { free.append((c.name, c.point)) }
    }
    if free.isEmpty {
        throw Skip("macOS's own hot corners are set for the \(taken.joined(separator: ", ")) corner: set them to “–” in System Settings › Desktop & Dock › Hot Corners")
    }
    return (free, taken)
}

/// A mouse wheel's tick: in lines, with no phases, not continuous (a trackpad's scroll is all three).
/// The middle value (the upper one of an even count): a typical timing, unmoved by one stall.
private func navMedian(_ xs: [Int]) -> Int { xs.sorted()[xs.count / 2] }

private func navWheel(dx: Int32 = 0, dy: Int32, flags: CGEventFlags = []) {
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
    e?.flags = flags
    e?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
    e?.post(tap: .cghidEventTap)
    usleep(16_000)
}

/// Space down, or up, on its own (Input.key presses and lets go at once).
private func navSpace(_ down: Bool) {
    let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: Input.Key.space.rawValue, keyDown: down)
    e?.post(tap: .cghidEventTap)
    usleep(20_000)
}

/// A drag slow enough to watch the pointer during it (Input.drag takes a third of a second).
private func navSlowDrag(from a: CGPoint, to b: CGPoint, seconds: TimeInterval) {
    // No modifiers: left unset, a key still held elsewhere comes along (see Input.dragAsync).
    func post(_ type: CGEventType, _ p: CGPoint) {
        let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
        e?.flags = []
        e?.post(tap: .cghidEventTap)
    }
    Input.move(to: a)
    post(.leftMouseDown, a)
    let steps = max(10, Int(seconds / 0.025))
    for i in 1...steps {
        usleep(UInt32(seconds / Double(steps) * 1_000_000))
        let k = CGFloat(i) / CGFloat(steps)
        post(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k))
    }
    usleep(300_000)
    post(.leftMouseUp, b)
    usleep(50_000)
}

/// Chromium's animated moves for assistive apps (AXEnhancedUserInterface), as the app has them now.
private func navEnhancedUI(_ pid: pid_t) -> Bool {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), "AXEnhancedUserInterface" as CFString, &value) == .success else { return false }
    return (value as? Bool) ?? false
}

/// Chrome, Brave, Edge and other browsers built on Chromium, by app name.
private func navChromium(_ app: String) -> Bool {
    ["Google Chrome", "Brave Browser", "Microsoft Edge", "Chromium", "Vivaldi", "Opera", "Arc", "Dia", "Thorium"].contains { app.hasPrefix($0) }
}

/// The hand-backs since `mark` (NAV-40, NAV-41): never longer than a quarter of a second, and
/// never with the app's windows still on their way.
@MainActor private func navExpectHandBacks(_ t: Ctx, since mark: Int, app: String) throws {
    let lines = t.log.lines(since: mark)
    for line in lines where line.hasPrefix("hand-back waited ") {
        guard let m = line.firstMatch(of: #/^hand-back waited (\d+)ms/#), let ms = Int(m.1) else { continue }
        try t.expect(ms <= 270, "the hand-back took longer than a quarter of a second: \(line)")
    }
    if let stall = lines.first(where: { $0.hasPrefix("gave up on windows landing") && $0.contains(app) }) {
        throw Failure("the canvas handed back before \(app)'s windows had landed: \(stall)")
    }
}

/// NAV-46: ⌥` and a hop, with whatever animationSlowdown Expanse launched with. Whether each is
/// still moving a little after it should have finished at normal speed, and how many frames the
/// glide drew.
/// `glide`: seconds from the hop's key press to its "glide timing" line, less the commit it
/// reports. (A dump can't look mid-glide: links wait for a glide to finish, see whenIdle.)
@MainActor private func navMeasureMoves(_ t: Ctx, _ tag: String) async throws -> (zoomBusy: Bool, glide: Double, frames: Int) {
    let a = try await t.window("NAV-46 \(tag) A")
    let b = try await t.window("NAV-46 \(tag) B")
    let spot = try await t.navEmptySpot()
    t.place(a, at: spot)
    t.place(b, at: CGPoint(x: spot.x + 3000, y: spot.y))
    try await t.settle()
    try await t.navFocus(a)
    Input.key(.grave, .maskAlternate)
    try await t.pause(0.35)
    let zoom = try await t.state()
    try t.expect(zoom.active, "⌥` didn't open the canvas")
    try await t.settle()
    Input.key(.escape)
    try await t.until("back at 100%") { try await !t.settle().active }
    try await t.navFocus(a)
    let mark = t.log.mark()
    let pressed = Date()
    Input.key(.right, .maskControl)
    let line = try await t.expectLog("glide timing:", since: mark, timeout: 10)
    let elapsed = Date().timeIntervalSince(pressed)
    guard let m = line.firstMatch(of: #/(\d+) frames/#), let frames = Int(m.1),
          let c = line.firstMatch(of: #/commit (\d+)ms/#), let commit = Double(c.1) else { throw Failure("can't read “\(line)”") }
    try await t.settle()
    return (zoom.animating, elapsed - commit / 1000, frames)
}

fileprivate extension Ctx {
    /// cleanUp's expanse://screen runs a display-change pass even when the size hasn't changed
    /// (CanvasController.simulateScreen): 1.6s later every window is re-placed under the canvas
    /// (ending in "layout fitted:"). Waits for that pass, so it can't land in the middle of the case.
    func navReady() async throws {
        let all = log.lines(since: 0)
        if let screen = all[..<min(start, all.count)].lastIndex(where: { $0.hasPrefix("url command screen") }) {
            _ = await log.wait(since: screen, timeout: 5) { $0.hasPrefix("layout fitted:") }
        }
        try await settle()
    }

    /// The first log line since `mark` with `text` and window `id` ("App[id]").
    @discardableResult
    func navLog(_ text: String, _ id: CGWindowID, since mark: Int, timeout: TimeInterval = 5) async throws -> String {
        guard let line = await log.wait(since: mark, timeout: timeout, { $0.contains(text) && $0.contains("[\(id)]") }) else {
            throw Failure("no log line with “\(text)” for window [\(id)]")
        }
        return line
    }

    /// What Expanse did when window `id` got focus: the first line since `mark` that says it
    /// glided there, or that it focused it where it is in a view you placed.
    func navFocusOutcome(_ id: CGWindowID, since mark: Int, timeout: TimeInterval = 3) async throws -> String {
        guard let line = await log.wait(since: mark, timeout: timeout, { line in
            line.contains("[\(id)]") && (line.contains("glide to ") || line.hasPrefix("view placed by you: "))
        }) else {
            throw Failure("Expanse logged nothing about window [\(id)] getting focus (no glide, no “view placed by you”)")
        }
        return line
    }

    /// Puts window `id` (any app's) at a canvas spot and moves the real windows (expanse://place).
    func navPlace(_ id: CGWindowID, _ p: CGPoint) {
        link("place", ["id": id, "x": Int(p.x.rounded()), "y": Int(p.y.rounded()), "commit": 1])
    }

    /// Windows in a row from `spot`, in the order given, 20pt apart.
    func navRow(_ ids: [CGWindowID], at spot: CGPoint) async throws -> ExpanseState {
        let s = try await settle()
        var x = spot.x
        for id in ids {
            guard let f = s.window(id)?.canvas else { throw Failure("window [\(id)] isn't on the canvas") }
            navPlace(id, CGPoint(x: x, y: spot.y))
            x += f.width + 20
        }
        return try await settle()
    }

    /// A canvas spot well to the right of every window, for a case's windows to have to themselves.
    func navEmptySpot() async throws -> CGPoint {
        let s = try await settle()
        let all = s.windows.map(\.canvas).reduce(CGRect.null) { $0.union($1) }
        if all.isNull { return CGPoint(x: (s.visibleCanvas.maxX + 3000).rounded(), y: s.visibleCanvas.minY.rounded()) }
        return CGPoint(x: (all.maxX + 3000).rounded(), y: all.minY.rounded())
    }

    /// The view at 100% over bare canvas, every window out of view: the canvas opened at 100%,
    /// zoomed out, panned well to the right of everything (zoomed out, so it isn't a view you
    /// placed), zoomed back in, and left. Opened at 100%, leaving stays where the view is; opened
    /// zoomed out (⌥`), it would go back to the window you were in (NAV-17).
    func navGoEmpty() async throws -> ExpanseState {
        let s0 = try await settle()
        let all = s0.windows.map(\.canvas).reduce(CGRect.null) { $0.union($1) }
        let target = all.isNull ? CGPoint(x: navViewCentre(s0).x + 4000, y: navViewCentre(s0).y) : CGPoint(x: all.maxX + 4000, y: all.midY)
        link("enter", ["zoomOut": 0])
        try await until("the canvas to open") { try await self.state().active }
        link("zoom", ["scale": 0.5])
        try await until("the canvas zoomed out") { try await self.settle().scale < 0.9 }
        let out = try await settle()
        let c = navViewCentre(out)
        link("pan", ["dx": Int(((c.x - target.x) * out.scale).rounded()), "dy": Int(((c.y - target.y) * out.scale).rounded())])
        try await until("the view over bare canvas") {
            let s = try await self.settle()
            return navDistance(navViewCentre(s), target) < 2 / s.scale + 1
        }
        link("zoom", ["scale": 1])
        try await until("the canvas back at 100%") { abs(try await self.settle().scale - 1) < 0.001 }
        link("exit")
        try await until("back at 100%") { try await !self.settle().active }
        return try await settle()
    }

    /// Glides to window `id` (expanse://focus?id=) and waits until the view is centred on it.
    /// Afterwards Expanse may be in front (see the note at the top): give a window the keyboard
    /// before pressing a hop.
    @discardableResult
    func navGlide(to id: CGWindowID) async throws -> ExpanseState {
        let mark = log.mark()
        link("focus", ["id": id])
        try await navLog("glide to ", id, since: mark)
        try await until("the view centred on [\(id)]", timeout: 8) { let s = try await self.settle(); return navCentred(s, id) }
        return try await settle()
    }

    /// Has Expanse glide to window `id` and give it the keyboard, then waits for that and for the
    /// hand-back, without asking Expanse anything (a link would bring Expanse to the front).
    func navFocus(_ id: CGWindowID, pid: pid_t) async throws {
        let mark = log.mark()
        link("focus", ["id": id])
        try await navLog("glide to ", id, since: mark)
        try await expectLog("glide timing:", since: mark, timeout: 6)
        try await until("[\(id)]'s app in front", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
        // The hand-back is at most a quarter of a second after the windows have moved.
        try await pause(0.35)
    }

    func navFocus(_ w: TestWindow) async throws {
        try await navFocus(w.id, pid: getpid())
        try await navHasKeyboard(w, "“\(w.title)”")
    }

    func navHasKeyboard(_ w: TestWindow, _ what: String, timeout: TimeInterval = 3) async throws {
        do {
            try await until("\(what) to have the keyboard", timeout: timeout) { NSApp.isActive && w.window.isKeyWindow }
        } catch {
            // Who has it instead.
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "nothing"
            let key = NSApp.keyWindow?.title ?? "none"
            throw Failure("\(error) (in front: \(front); Expanse Tests \(NSApp.isActive ? "active" : "not active"), its key window: \(key))")
        }
    }

    /// Clicks the middle of the part of `w` on screen, as you would to use it, and waits for it to
    /// have the keyboard.
    func navClick(_ w: TestWindow) async throws {
        guard let r = w.real?.intersection(screen.insetBy(dx: 2, dy: 2)), !r.isNull, r.width > 20, r.height > 20 else {
            throw Failure("“\(w.title)” isn't on screen to click")
        }
        Input.click(at: CGPoint(x: r.midX, y: r.midY))
        try await navHasKeyboard(w, "“\(w.title)”")
        // And Expanse has heard: a hop starts from the window it last heard had focus, and in a
        // VM the notification can come well after the click.
        try await until("Expanse to hear “\(w.title)” has focus", timeout: 3) { try await self.state().focusedByApp[getpid()] == w.id }
    }

    /// Switches to a fixture app as ⌘-Tab does, as far as Expanse can tell: a key goes down and up
    /// (so it counts as you switching), and the app comes to the front.
    func navSwitch(to f: Fixture) async throws {
        guard let pid = f.pid else { throw Failure("\(f.name) isn't running") }
        Input.holding(.maskCommand) {}
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        f.activate()
        do {
            try await until("\(f.name) in front", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
        } catch {
            throw Skip("couldn't bring \(f.name) to the front")
        }
    }

    /// Two windows side by side in the middle of the screen, both whole, at 100%, with nothing
    /// else on screen; `more` are made too, and are out of view. 60pt apart, more than a screen
    /// group's reach (NAV-55), so each is a window on its own: NAV-57 is the group case.
    func navSideBySide(_ prefix: String, more: [String] = []) async throws -> (TestWindow, TestWindow, [TestWindow]) {
        let width = min(600, (screen.width - 140) / 2), height = min(400, screen.height - 220)
        let l = try await window("\(prefix) Left", CGRect(x: 100, y: 120, width: width, height: height))
        let r = try await window("\(prefix) Right", CGRect(x: 140, y: 160, width: width, height: height))
        var others: [TestWindow] = []
        for title in more { others.append(try await window(title, CGRect(x: 180, y: 200, width: width, height: height))) }
        let s = try await navGoEmpty()
        guard let fl = s.window(l.id)?.canvas, let fr = s.window(r.id)?.canvas else { throw Failure("a window isn't on the canvas") }
        let vis = s.visibleCanvas
        let y = (vis.midY - fl.height / 2).rounded()
        place(l, at: CGPoint(x: (vis.midX - 30 - fl.width).rounded(), y: y))
        place(r, at: CGPoint(x: (vis.midX + 30).rounded(), y: y))
        let after = try await settle()
        for (w, f) in [(l, fl), (r, fr)] {
            guard let now = after.window(w.id) else { throw Failure("“\(w.title)” left the canvas") }
            try expect(!now.parked && after.viewport.insetBy(dx: -1, dy: -1).contains(navScreenRect(after, now.canvas)),
                       "“\(w.title)” (\(f.size)) should be whole on screen")
        }
        return (l, r, others)
    }

    /// NAV-47's steps 1–3: scroll on the bare desktop (the canvas opens at 100%), hold Space and
    /// drag so `w` is about a third on screen at the right, Esc. The view is then one you placed.
    func navPlaceView(partly w: TestWindow) async throws -> ExpanseState {
        var s = try await settle()
        guard let p = navBarePoint(s) else { throw Skip("there's no bare desktop on screen to scroll on") }
        Input.move(to: p)
        try await pause(0.15)
        Input.trackpadScroll(dx: 0, dy: 4, steps: 2)
        try await until("a scroll on the desktop to open the canvas", timeout: 3) { try await self.state().active }
        // A scroll at 100% may snap when it ends (NAV-51).
        try await pause(0.4)
        s = try await settle()
        try expect(abs(s.scale - 1) < 0.001, "a scroll on the desktop should open the canvas at 100% (\(navPercent(s.scale)))")
        guard let f = s.window(w.id)?.canvas else { throw Failure("“\(w.title)” isn't on the canvas") }
        let dx = (s.viewport.maxX - f.width / 3) - navScreenRect(s, f).minX
        let y = s.viewport.minY + s.viewport.height * 0.3
        let from = CGPoint(x: s.viewport.midX - dx / 2, y: y), to = CGPoint(x: s.viewport.midX + dx / 2, y: y)
        navSpace(true)
        try await pause(0.15)
        await Input.dragAsync(from: from, to: to)
        try await pause(0.15)
        navSpace(false)
        try await pause(0.3)
        Input.key(.escape)
        try await until("Esc to leave the canvas") { try await !self.settle().active }
        s = try await settle()
        guard let now = s.window(w.id) else { throw Failure("“\(w.title)” left the canvas") }
        let shown = navScreenRect(s, now.canvas).intersection(s.viewport)
        try expect(!now.parked && shown.width >= 48 && shown.width < now.canvas.width - 1,
                   "“\(w.title)” should be partly on screen after the drag (\(Int(shown.width))pt of \(Int(now.canvas.width)) showing\(now.parked ? ", parked" : ""))")
        return s
    }

    /// A Chromium browser with `count` windows on the canvas; asks you to open them if there's none.
    func navBrowser(_ count: Int) async throws -> (app: String, pid: pid_t, ids: [CGWindowID]) {
        func find(_ s: ExpanseState) -> (app: String, ids: [CGWindowID])? {
            let byApp = Dictionary(grouping: s.windows.filter { navChromium($0.app) }, by: \.app)
            return byApp.filter { $0.value.count >= count }.max { $0.value.count < $1.value.count }.map { ($0.key, $0.value.map(\.id)) }
        }
        var found = find(try await state())
        if found == nil {
            try await ask("Open \(count) windows of a Chromium browser (Chrome, Brave or Edge: ⌘N), showing any page, then press Done. Close them whenever you like afterwards.")
            try await until("\(count) browser windows on the canvas", timeout: 15) {
                found = find(try await self.state())
                return found != nil
            }
        }
        guard let found, let pid = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == found.app })?.processIdentifier else {
            throw Skip("no Chromium browser with \(count) windows on the canvas")
        }
        return (found.app, pid, Array(found.ids.prefix(count)))
    }

    /// Expanse has a picture of window `id` (its first frame), so it's drawn on the backdrop.
    func navFirstFrame(_ id: CGWindowID, timeout: TimeInterval = 6) async throws {
        try await until("a picture of window [\(id)]", timeout: timeout) {
            let mark = self.log.mark()
            self.link("dump")
            let lines = await self.dumpLines(since: mark)
            return lines.contains { $0.contains("[\(id)] sc=") && $0.contains(" first=false") }
        }
    }

    /// ⌥`'s view: every window in view, centred.
    func navExpectOverview(_ s: ExpanseState, _ what: String) throws {
        try expect(s.active, "\(what) should open the canvas")
        guard let o = navOverview(s) else { return }
        try expect(abs(s.scale - o.scale) <= max(0.002, o.scale * 0.02),
                   "\(what) should zoom out to \(navPercent(o.scale)), which fits every window (it's at \(navPercent(s.scale)))")
        try expectNear(navViewCentre(s), o.centre, within: 3 / s.scale, "\(what): the middle of the view should be the middle of every window")
    }

    /// The real window is where the canvas says: on screen at its spot, or parked in the corner.
    func navExpectInPlace(_ s: ExpanseState, _ id: CGWindowID, _ name: String) throws {
        guard let w = s.window(id) else { throw Failure("\(name) isn't on the canvas") }
        guard let real = realFrame(id) else { throw Failure("\(name) has no window") }
        if w.parked {
            try expect(real.minX > screen.maxX - 120 && real.minY > screen.maxY - 260, "\(name) should be parked in the bottom-right corner (it's at \(real))")
        } else {
            try expectNear(real.origin, s.screenPoint(w.canvas.origin), within: 2, "\(name)'s real window")
        }
    }

    /// Whether Expanse shows a toast (Toast.show: a window at status-bar level near the bottom of
    /// the screen) within `seconds`, and its text if Accessibility can read it.
    func navToast(within seconds: TimeInterval) async -> (shown: Bool, text: String?) {
        guard let pid = expanse?.processIdentifier else { return (false, nil) }
        let level = Int(CGWindowLevelForKey(.statusWindow))
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let toast = navOnScreenWindows().first(where: { $0.pid == pid && $0.layer == level && $0.alpha > 0.05 && $0.frame.midY > screen.midY }) {
                return (true, navAXTexts(pid: pid, near: toast.frame).joined(separator: " "))
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return (false, nil)
    }
}

/// The text in app `pid`'s window at `frame`, as Accessibility has it (empty if it can't say).
private func navAXTexts(pid: pid_t, near frame: CGRect) -> [String] {
    func value(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    func texts(_ e: AXUIElement, depth: Int) -> [String] {
        var out: [String] = []
        if value(e, kAXRoleAttribute) as? String == kAXStaticTextRole as String, let s = value(e, kAXValueAttribute) as? String { out.append(s) }
        guard depth < 5, let children = value(e, kAXChildrenAttribute) as? [AXUIElement] else { return out }
        for child in children { out += texts(child, depth: depth + 1) }
        return out
    }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.5)
    for w in value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        var p = CGPoint.zero
        if let v = value(w, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
        if abs(p.x - frame.minX) < 4 && abs(p.y - frame.minY) < 4 { return texts(w, depth: 0) }
    }
    return []
}

/// NAV-55 to NAV-60: B and C side by side, 20pt apart (a group: 1220pt wide fits the screen), and
/// A on its own 3000pt to their left, in a row somewhere clear.
@MainActor private func navGroupScene(_ t: Ctx) async throws -> (a: TestWindow, b: TestWindow, c: TestWindow) {
    let spot = try await t.navEmptySpot()
    let a = try await t.window("Groups A", CGRect(x: 120, y: 160, width: 600, height: 400))
    let b = try await t.window("Groups B", CGRect(x: 160, y: 200, width: 600, height: 400))
    let c = try await t.window("Groups C", CGRect(x: 200, y: 240, width: 600, height: 400))
    t.place(a, at: spot)
    t.place(b, at: CGPoint(x: spot.x + 3600, y: spot.y))
    t.place(c, at: CGPoint(x: spot.x + 4220, y: spot.y))
    try await t.until("A, B and C in place", timeout: 8) {
        let s = try await t.settle()
        return s.window(c.id)?.canvas.minX == spot.x + 4220 && s.window(a.id)?.canvas.minX == spot.x
    }
    let s = try await t.settle()
    try t.expect(s.screenGroup(of: b.id)?.count == 2, "B and C should make a group of two")
    return (a, b, c)
}
