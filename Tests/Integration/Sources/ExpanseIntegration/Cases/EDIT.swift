import AppKit

/// The manual cases in docs/regression/arranging.md.
///
/// Most work zoomed out on the runner's own windows, put at a spot on the canvas well clear of
/// everything else (see editClearSpot), so nothing of yours is near enough to snap to. Input on
/// the canvas (drags, ⇧-clicks, ⌘A, Esc, T, ×) is posted for real; links only set things up.
/// The selection isn't in expanse://dump, so it's read back the way you'd see it: drag one
/// selected window (with ⌘, so nothing snaps) and see which move with it (see editMovesWith).
@MainActor enum EDIT {
    static let cases: [Case] = [
        Case("EDIT-01", "Drag a window on the canvas to move it") { t in
            try t.needsInput()
            let (ws, o) = try await t.editRow(["EDIT-01 A", "EDIT-01 B"])
            let (a, b) = (ws[0], ws[1])
            // (The middle of the screen, which a dragged window snaps to, away from B's path.)
            let s = try await t.editZoomOut(on: CGPoint(x: o.x + 600, y: o.y + 350), scale: 0.5)
            let fb = try s.editFrame(b)
            let realBefore = b.real
            // Down and to the right, to empty canvas, clear of anything to snap to.
            let from = s.editCentre(fb)
            let to = CGPoint(x: from.x + 60, y: from.y + 260)
            let target = fb.offsetBy(dx: 60 / s.scale, dy: 260 / s.scale)
            let drag = EditDrag(from: from)
            defer { drag.release() }
            await drag.move(to: CGPoint(x: from.x + 30, y: from.y + 130), steps: 15)
            try await t.pause(0.2)
            let halfway = try await t.canvasFrame(b)
            try t.expectNear(halfway.origin, fb.offsetBy(dx: 30 / s.scale, dy: 130 / s.scale).origin, within: 2,
                             "B's picture halfway through the drag (it should follow the pointer)")
            await drag.move(to: to, steps: 15)
            drag.release()
            try await t.pause(0.3)
            let dropped = try await t.settle()
            try t.expect(dropped.active, "letting go of B shouldn't leave the canvas")
            try t.expectNear(try dropped.editFrame(b).origin, target.origin, within: 2, "B where it was dropped")
            if let before = realBefore, let now = b.real {
                try t.expectNear(now, before, within: 1, "the real B while still zoomed out (it moves only when you leave the canvas)")
            }
            try await t.editKeysToCanvas()
            Input.key(.escape)
            try await t.until("back at 100%", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
            let back = try await t.settle()
            try t.expectNear(try back.editFrame(b).origin, target.origin, within: 2, "B's spot on the canvas after leaving it")
            var onScreen: [(TestWindow, CGRect)] = []
            for w in [a, b] {
                guard let cw = back.window(w.id) else { throw Failure("\(w.title) left the canvas") }
                if cw.parked { continue }
                let spot = back.screenPoint(cw.canvas.origin)
                try await t.until("\(w.title) at its spot on screen", timeout: 5) {
                    guard let r = w.real else { return false }
                    return hypot(r.minX - spot.x, r.minY - spot.y) < 2
                }
                onScreen.append((w, cw.canvas))
            }
            if onScreen.count == 2, let ra = a.real, let rb = b.real {
                let real = CGPoint(x: rb.minX - ra.minX, y: rb.minY - ra.minY)
                let canvas = CGPoint(x: onScreen[1].1.minX - onScreen[0].1.minX, y: onScreen[1].1.minY - onScreen[0].1.minY)
                try t.expectNear(real, canvas, within: 2, "the real B relative to the real A")
            }
            try await t.until("the layout file to have B's new spot", timeout: 5) {
                editSavedSpot(b.id).map { hypot($0.x - target.minX, $0.y - target.minY) < 2 } ?? false
            }
        },

        Case("EDIT-02", "A tiny drag still counts as a click") { t in
            try t.needsInput()
            let (ws, o) = try await t.editRow(["EDIT-02 A", "EDIT-02 B"])
            let a = ws[0]
            let s = try await t.editZoomOut(on: CGPoint(x: o.x + 410, y: o.y + 300), scale: 0.5)
            let fa = try s.editFrame(a)
            let p = s.editCentre(fa)
            await Input.dragAsync(from: p, to: CGPoint(x: p.x + 2, y: p.y + 1), steps: 3)
            try await t.until("Expanse to dive into A", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
            let back = try await t.settle()
            try t.expectNear(try back.editFrame(a).origin, fa.origin, within: 0.5, "A on the canvas (a drag under 3 points shouldn't move it)")
            try await t.editCentred(a, in: back.viewport)
            try await t.until("A to have focus", timeout: 5) { a.window.isKeyWindow && NSApp.isActive }
        },

        Case("EDIT-04", "Hold ⌘ while dragging to skip snapping") { t in
            try t.needsInput()
            let (ws, o) = try await t.editRow(["EDIT-04 A", "EDIT-04 B"], gap: 300)
            let (a, b) = (ws[0], ws[1])
            let s = try await t.editZoomOut(on: CGPoint(x: o.x + 550, y: o.y + 260), scale: 0.5)
            let fa = try s.editFrame(a), fb = try s.editFrame(b)
            // With ⌘: B's left edge to 12pt right of the standard gap beside A, and its top 12pt
            // below A's. Both are within snapping reach (10 screen points, 20 canvas points here).
            let held = CGPoint(x: fa.maxX + 20 + 12, y: fa.minY + 12)
            let start = s.editCentre(fb)
            let path = CGPoint(x: start.x + (held.x - fb.minX) * s.scale, y: start.y + (held.y - fb.minY) * s.scale)
            editKey(55, down: true, flags: .maskCommand)
            var commandDown = true
            defer { if commandDown { editKey(55, down: false, flags: []) } }
            let drag = EditDrag(from: start, flags: .maskCommand)
            defer { drag.release() }
            await drag.move(to: path, steps: 40)
            try await t.pause(0.2)
            try t.expectNear(try await t.canvasFrame(b).origin, held, within: 1,
                             "B with ⌘ held (it should follow the pointer exactly, without snapping to A)")
            // Let go of ⌘ mid-drag: the next movement snaps again.
            editKey(55, down: false, flags: [])
            commandDown = false
            await drag.move(to: CGPoint(x: path.x - 1, y: path.y), steps: 1, flags: [])
            try await t.pause(0.2)
            let snapped = CGPoint(x: fa.maxX + 20, y: fa.minY)
            try t.expectNear(try await t.canvasFrame(b).origin, snapped, within: 0.5,
                             "B after letting go of ⌘ (it should snap to 20pt beside A, tops lined up)")
            drag.release()
            try await t.pause(0.3)
            try t.expectNear(try await t.canvasFrame(b).origin, snapped, within: 0.5, "B where it was dropped")
        },

        Case("EDIT-09", "Clicking a window in the selection dives into it") { t in
            try t.needsInput()
            let (ws, o) = try await t.editRow(["EDIT-09 A", "EDIT-09 B", "EDIT-09 C"])
            let s = try await t.editZoomOut(on: CGPoint(x: o.x + 630, y: o.y + 300), scale: 0.5)
            for w in ws {
                Input.click(at: s.editCentre(try s.editFrame(w)), flags: .maskShift)
                try await t.pause(0.15)
            }
            let moved = try await t.editMovesWith(ws[1].id).moved
            try t.expect(moved == Set(ws.map(\.id)), "⇧-clicking A, B and C should select the three (\(moved.count) moved with B)")
            Input.click(at: s.editCentre(try s.editFrame(ws[1])))
            try await t.until("Expanse to dive into B", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
            let back = try await t.settle()
            try t.expectNear(try back.editFrame(ws[1]).origin, try s.editFrame(ws[1]).origin, within: 0.5, "B on the canvas (a click shouldn't move it)")
            try await t.editCentred(ws[1], in: back.viewport)
            try await t.until("B to have focus", timeout: 5) { ws[1].window.isKeyWindow && NSApp.isActive }
        },

        Case("EDIT-10", "Drag on empty canvas to select windows", .look) { t in
            try t.needsInput()
            let spot = editClearSpot(try await t.state())
            let ws = try await t.row((1...5).map { "EDIT-10 \($0)" }, size: CGSize(width: 360, height: 220), gap: 120, origin: spot)
            let h = try await t.canvasFrame(ws[0]).height
            let s = try await t.editZoomOut(on: CGPoint(x: spot.x + 1140, y: spot.y + h / 2 + 40), scale: 0.35)
            let fr = try ws.map { try s.editFrame($0) }
            try await t.ask("Watch the canvas: when you click Done, Expanse Tests drags a box from below the gap between 1 and 2 up across 2, 3 and 4, slowly, and lets go.")
            // From empty canvas in the gap below 1 and 2, to inside 4.
            let drag = EditDrag(from: s.screenPoint(CGPoint(x: fr[1].minX - 50, y: fr[1].maxY + 90)))
            defer { drag.release() }
            await drag.move(to: s.screenPoint(CGPoint(x: fr[3].minX + 60, y: fr[1].midY)), steps: 150)
            try await t.pause(0.5)
            drag.release()
            try await t.look("While it dragged, did a lightly tinted accent-coloured box follow the pointer?")
            try await t.look("Now that it's let go: do windows 2, 3 and 4 (and only those) have a thick accent-coloured border, with a dashed rounded outline around the three?")
            let moved = try await t.editMovesWith(ws[2].id).moved.intersection(Set(ws.map(\.id)))
            try t.expect(moved == Set([ws[1].id, ws[2].id, ws[3].id]),
                         "the box should have selected 2, 3 and 4, and kept them selected after letting go (moved with 3: \(editNames(moved, ws)))")
        },

        Case("EDIT-11", "⇧-click and ⇧-drag add to the selection") { t in
            try t.needsInput()
            let spot = editClearSpot(try await t.state())
            let size = CGSize(width: 360, height: 220)
            let top = try await t.row(["EDIT-11 1", "EDIT-11 2", "EDIT-11 3"], size: size, gap: 120, origin: spot)
            let h = try await t.canvasFrame(top[0]).height
            let bottom = try await t.row(["EDIT-11 4", "EDIT-11 5", "EDIT-11 6"], size: size, gap: 120,
                                         origin: CGPoint(x: spot.x, y: spot.y + h + 120))
            let ws = top + bottom
            let s = try await t.editZoomOut(on: CGPoint(x: spot.x + 660, y: spot.y + h + 60), scale: 0.4)
            let fr = try ws.map { try s.editFrame($0) }
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { s.screenPoint(CGPoint(x: x, y: y)) }
            @MainActor func check(_ step: String, probe: Int, _ expected: [Int]) async throws {
                let moved = try await t.editMovesWith(ws[probe].id).moved.intersection(Set(ws.map { $0.id }))
                let want = Set(expected.map { ws[$0].id })
                try t.expect(moved == want, "after \(step), the selection should be \(editNames(want, ws)), not \(editNames(moved, ws))")
            }
            // Two selected with a box (EDIT-10): from empty canvas above-left of 1 to inside 2.
            await Input.dragAsync(from: at(fr[0].minX - 60, fr[0].minY - 60), to: at(fr[1].midX, fr[0].midY), steps: 20)
            try await check("a box over 1 and 2", probe: 0, [0, 1])
            Input.click(at: s.editCentre(fr[2]), flags: .maskShift)
            try await check("⇧-clicking 3", probe: 0, [0, 1, 2])
            Input.click(at: s.editCentre(fr[2]), flags: .maskShift)
            try await check("⇧-clicking 3 again", probe: 0, [0, 1])
            // From empty canvas below-left of 4 to inside 5.
            await Input.dragAsync(from: at(fr[3].minX - 60, fr[3].maxY + 60), to: at(fr[4].midX, fr[3].midY), flags: .maskShift, steps: 20)
            try await check("⇧-dragging a box over 4 and 5", probe: 0, [0, 1, 3, 4])
            // From empty canvas right of 3 to inside 6, without ⇧.
            await Input.dragAsync(from: at(fr[2].maxX + 60, fr[2].midY), to: at(fr[5].midX, fr[5].maxY + 60), steps: 20)
            try await check("a box over 3 and 6 without ⇧", probe: 2, [2, 5])
        },

        Case("EDIT-12", "⌘A selects every window; Esc clears it, then leaves") { t in
            try t.needsInput()
            let (ws, o) = try await t.editRow(["EDIT-12 A", "EDIT-12 B", "EDIT-12 C"])
            let s = try await t.editZoomOut(on: CGPoint(x: o.x + 630, y: o.y + 300), scale: 0.5)
            try await t.editKeysToCanvas()
            Input.key(.a, .maskCommand)
            try await t.pause(0.3)
            // Every window on the canvas, yours too, moves with A and comes back exactly (⌘: no snapping).
            let probe = try await t.editMovesWith(ws[0].id)
            let missed = probe.all.subtracting(probe.moved)
            try t.expect(missed.isEmpty, "⌘A should select every window: \(missed.count) of \(probe.all.count) didn't move with A")
            Input.key(.escape)
            try await t.pause(0.8)
            let cleared = try await t.settle()
            try t.expect(cleared.active, "the first Esc should clear the selection and stay zoomed out, not leave")
            try t.expect(abs(cleared.scale - s.scale) < 0.001, "the first Esc shouldn't zoom (scale \(s.scale) -> \(cleared.scale))")
            Input.key(.escape)
            try await t.until("the second Esc to go back to 100%", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
        },

        Case("EDIT-14", "Tidy Up from 100% opens the canvas first") { t in
            let spot = editClearSpot(try await t.state())
            // One untidy group: B 70pt right of A and 25pt lower, C overlapping B by 60pt.
            let offsets = [CGPoint(x: 0, y: 0), CGPoint(x: 470, y: 25), CGPoint(x: 810, y: 40)]
            var ws: [TestWindow] = []
            for (i, off) in offsets.enumerated() {
                let w = try await t.window("EDIT-14 \(["A", "B", "C"][i])",
                                           CGRect(x: 120 + 30 * CGFloat(i), y: 140 + 30 * CGFloat(i), width: 400, height: 260))
                t.place(w, at: CGPoint(x: spot.x + off.x, y: spot.y + off.y))
                ws.append(w)
            }
            let before = try await t.settle()
            try t.expect(!before.active, "this starts at 100%")
            let app = before.window(ws[0].id)?.app ?? "Expanse Tests"
            let mark = t.log.mark()
            // Panel › Tidy up, pressed with Accessibility; the link runs the same command if the
            // button can't be found.
            let pressed = Input.allowed ? try await t.editPressPanelButton("Tidy up") : false
            if !pressed { t.link("tidy") }
            try await t.until("the canvas to open", timeout: 8) { try await t.state().active }
            try await t.expectLog("layout fitted:", since: mark, timeout: 8)
            for w in ws.dropFirst() { try await t.expectLog("tidy moved \(app)[\(w.id)]", since: mark) }
            let s = try await t.settle()
            let fr = try ws.map { try s.editFrame($0) }
            try editExpectRow(t, fr, ["A", "B", "C"])
            try t.expectNear(fr[0].origin, CGPoint(x: spot.x, y: spot.y), within: 1, "A, the group's left end, shouldn't move")
            if s.scale > 0.031 {
                let view = s.visibleCanvas.insetBy(dx: -1, dy: -1)
                let outside = s.windows.filter { !view.contains($0.canvas) }
                try t.expect(outside.isEmpty, "the view should zoom to fit every window: \(outside.count) are outside it (scale \(s.scale))")
            }
        },

        Case("EDIT-19", "Dragging on the canvas stays smooth with busy apps") { t in
            try t.needsInput()
            let spot = editClearSpot(try await t.state())
            let f = try await t.fixture("EDIT-19", windows: 24, size: CGSize(width: 320, height: 200))
            let crowd = f.windows
            try await t.until("Expanse to take on the fixture's \(crowd.count) windows", timeout: 40) {
                let s = try await t.state()
                return crowd.allSatisfy { s.window($0) != nil }
            }
            guard let cell = try await t.state().window(crowd[0])?.canvas.size else { throw Failure("the fixture's window left the canvas") }
            // A grid of them, all in view (and captured) while one of ours is dragged around below.
            for (i, id) in crowd.enumerated() {
                t.link("place", ["id": id, "x": Int(spot.x + CGFloat(i % 6) * (cell.width + 40)),
                                 "y": Int(spot.y + CGFloat(i / 6) * (cell.height + 40)), "commit": i == crowd.count - 1 ? 1 : 0])
            }
            let gridHeight = 4 * (cell.height + 40)
            let d = try await t.window("EDIT-19 Drag", CGRect(x: 200, y: 200, width: 360, height: 220))
            t.place(d, at: CGPoint(x: spot.x + 900, y: spot.y + gridHeight + 260))
            try await t.settle(timeout: 15)
            let s = try await t.editZoomOut(on: CGPoint(x: spot.x + 1060, y: spot.y + gridHeight / 2 + 240), scale: 0.4)
            let centre = s.editCentre(try s.editFrame(d))
            let mark = t.log.mark()
            let drag = EditDrag(from: centre)
            defer { drag.release() }
            // Round and round for 10s at 60 events a second, off the main thread so the runner's own
            // work can't space them out.
            let mover = Task.detached { () -> CGPoint in
                var p = centre
                let began = Date()
                while Date().timeIntervalSince(began) < 10 {
                    let a = Date().timeIntervalSince(began) * 2 * .pi / 2.5
                    p = CGPoint(x: centre.x + 110 * sin(a), y: centre.y - 110 + 110 * cos(a))
                    editMouse(.leftMouseDragged, p)
                    usleep(16_000)
                }
                return p
            }
            // A window opening mid-drag: its scan should wait until the drag ends.
            try await t.pause(3)
            let known = Set(crowd)
            try await f.openWindow()
            guard let added = f.windows.first(where: { !known.contains($0) }) else { throw Failure("the fixture didn't open another window") }
            drag.point = await mover.value
            let upMark = t.log.mark()
            drag.release()
            let during = Array(t.log.lines(since: mark).prefix(max(0, upMark - mark)))
            let slow = during.first { $0.contains("slow: drag step took") || $0.contains("ms between drag events") }
            try t.expectTiming(slow == nil, "the drag had a hitch: \(slow ?? "")")
            let taken: (String) -> Bool = { $0.hasPrefix("tracking ") && $0.contains("[\(added)]") }
            try t.expect(!during.contains(where: taken), "the window that opened mid-drag was taken on during the drag: window scans should wait until it ends")
            guard await t.log.wait(since: upMark, timeout: 10, taken) != nil else {
                throw Failure("the window that opened mid-drag wasn't taken on within 10s of the drag ending")
            }
        },

        Case("EDIT-23", "Closing from the canvas still asks about unsaved changes") { t in
            try t.needsInput()
            let bundle = "com.apple.TextEdit"
            let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Expanse Tests EDIT-23", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("EDIT-23 saved.txt")
            try "Expanse Tests: a saved document, closed from the canvas.\n".write(to: file, atomically: true, encoding: .utf8)
            var opened: [AXUIElement] = []
            defer {
                // Nothing of yours: only the two documents this case made, the unsaved one deleted.
                for w in opened { editAXDiscard(w) }
                if !wasRunning { NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.terminate() }
                try? FileManager.default.removeItem(at: folder)
            }
            // The saved document, then a new one (File › New) with a letter typed into it.
            let saved = try await t.editNewTextEditWindow(titled: "EDIT-23 saved") { try t.open(file.path, in: "TextEdit") }
            opened.append(saved.ax)
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier else {
                throw Failure("TextEdit isn't running")
            }
            let unsaved = try await t.editNewTextEditWindow {
                guard let item = editAXMenuItem(pid, ["File", "New"]) else { throw Skip("couldn't find TextEdit's File › New") }
                AXUIElementPerformAction(item, kAXPressAction as CFString)
            }
            opened.append(unsaved.ax)
            let spot = editClearSpot(try await t.state())
            guard let sw = try await t.state().window(saved.id)?.canvas.size else { throw Failure("the saved document isn't on the canvas") }
            t.link("place", ["id": saved.id, "x": Int(spot.x), "y": Int(spot.y), "commit": 1])
            t.link("place", ["id": unsaved.id, "x": Int(spot.x + sw.width + 120), "y": Int(spot.y), "commit": 1])
            try await t.settle()
            t.link("focus", ["id": unsaved.id])
            try await t.settle()
            try await t.until("the new document to have focus in TextEdit", timeout: 6) {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle
                    && editAXFocusedWindow(pid).map { CFEqual($0, unsaved.ax) } == true
            }
            Input.key(.a)
            try await t.pause(0.5)
            // Zoomed out so both are wide enough on screen to show ×.
            let s0 = try await t.state()
            let fs = try s0.editFrame(saved.id), fu = try s0.editFrame(unsaved.id)
            let scale = min(1, max(0.5, 280 / min(fs.width, fu.width)))
            guard (fu.maxX - fs.minX) * scale < s0.viewport.width - 160 else { throw Skip("TextEdit's windows are too wide to show both with × on this screen") }
            let s = try await t.editZoomOut(on: CGPoint(x: (fs.minX + fu.maxX) / 2, y: fs.midY), scale: scale)
            let rs = try s.editFrame(saved.id), ru = try s.editFrame(unsaved.id)
            Input.click(at: s.editCentre(rs), flags: .maskShift)
            try await t.pause(0.15)
            Input.click(at: s.editCentre(ru), flags: .maskShift)
            try await t.pause(0.15)
            Input.move(to: s.editCentre(rs))
            try await t.pause(0.4)
            let onScreen = CGRect(origin: s.screenPoint(rs.origin), size: CGSize(width: rs.width * s.scale, height: rs.height * s.scale))
            let mark = t.log.mark()
            Input.click(at: CGPoint(x: onScreen.maxX - 23, y: onScreen.minY + 23))
            try await t.expectLog("closing 2 windows", since: mark, timeout: 5)
            try await t.until("the saved document to close", timeout: 8) { realFrame(saved.id) == nil }
            try await t.until("Expanse to drop the saved document", timeout: 8) { try await t.state().window(saved.id) == nil }
            try await t.until("TextEdit to ask about the unsaved one", timeout: 6) { editAXSheet(unsaved.ax) != nil }
            try t.expect(realFrame(unsaved.id) != nil, "the unsaved document shouldn't be closed without asking")
            let asked = Date()
            _ = try await t.state()
            try t.expect(Date().timeIntervalSince(asked) < 2, "Expanse should answer while TextEdit waits (took \(Date().timeIntervalSince(asked))s)")
            try t.expect(try await t.state().window(unsaved.id) != nil, "the unsaved document should still be on the canvas while TextEdit asks")
            // Answer it: delete the new document.
            guard let sheet = editAXSheet(unsaved.ax), let delete = editAXButton(in: sheet, ["Delete", "Don't Save", "Don’t Save"]) else {
                throw Failure("couldn't find Delete in TextEdit's question (answer it yourself)")
            }
            AXUIElementPerformAction(delete, kAXPressAction as CFString)
            try await t.until("the unsaved document to go once answered", timeout: 8) { realFrame(unsaved.id) == nil }
            opened.removeAll()
        },

        Case("EDIT-26", "Tidy Up right after a drag keeps what you dragged") { t in
            try t.needsInput()
            let spot = editClearSpot(try await t.state())
            // An untidy group: gaps of 50 and 70, tops 30 and 10 lower than A's.
            let offsets = [CGPoint(x: 0, y: 0), CGPoint(x: 450, y: 30), CGPoint(x: 920, y: 10)]
            var ws: [TestWindow] = []
            for (i, off) in offsets.enumerated() {
                let w = try await t.window("EDIT-26 \(["A", "B", "C"][i])",
                                           CGRect(x: 120 + 30 * CGFloat(i), y: 140 + 30 * CGFloat(i), width: 400, height: 260))
                t.place(w, at: CGPoint(x: spot.x + off.x, y: spot.y + off.y))
                ws.append(w)
            }
            let s = try await t.editZoomOut(on: CGPoint(x: spot.x + 500, y: spot.y + 350), scale: 0.5)
            let fr = try ws.map { try s.editFrame($0) }
            for r in fr {
                Input.click(at: s.editCentre(r), flags: .maskShift)
                try await t.pause(0.15)
            }
            try await t.editKeysToCanvas()
            let from = s.editCentre(fr[1])
            let down: CGFloat = 300
            let mark = t.log.mark()
            await Input.dragAsync(from: from, to: CGPoint(x: from.x, y: from.y + down), steps: 25)
            Input.key(.t)
            try await t.expectLog("layout fitted:", since: mark, timeout: 8)
            let after = try await t.settle()
            let now = try ws.map { try after.editFrame($0) }
            let dropped = CGPoint(x: fr[0].minX, y: fr[0].minY + down / s.scale)
            try t.expect(now[0].minY - fr[0].minY > down / s.scale / 2,
                         "the group should be tidied where it was dragged, not put back: A is at \(now[0].origin), it started at \(fr[0].origin)")
            try t.expectNear(now[0].origin, dropped, within: 21, "A, the group's left end, where it was dropped")
            try editExpectRow(t, now, ["A", "B", "C"])
        },
    ]
}

// MARK: Helpers

/// A spot on the canvas well clear of every window on it: right of and above them all, so none
/// of their edges (which a dragged window snaps to, wherever they are) is anywhere near.
private func editClearSpot(_ s: ExpanseState) -> CGPoint {
    let all = s.windows.map(\.canvas).reduce(CGRect.null) { $0.union($1) }
    guard !all.isNull else { return .zero }
    return CGPoint(x: (all.maxX + 3000).rounded(), y: (all.minY - 3000).rounded())
}

/// Tidy: in a row, 20pt apart, tops lined up.
@MainActor private func editExpectRow(_ t: Ctx, _ fr: [CGRect], _ names: [String]) throws {
    for i in 1..<fr.count {
        try t.expect(abs(fr[i].minX - fr[i - 1].maxX - 20) <= 1,
                     "\(names[i]) should be 20pt right of \(names[i - 1]) after Tidy Up (gap \(fr[i].minX - fr[i - 1].maxX))")
        try t.expect(abs(fr[i].minY - fr[0].minY) <= 1,
                     "\(names[i])'s top should line up with \(names[0])'s after Tidy Up (\(fr[i].minY - fr[0].minY)pt off)")
    }
}

@MainActor private func editNames(_ ids: Set<CGWindowID>, _ ws: [TestWindow]) -> String {
    let names = ws.filter { ids.contains($0.id) }.map { $0.title.components(separatedBy: " ").last ?? $0.title }
    let others = ids.count - names.count
    return "{" + (names + (others > 0 ? ["\(others) others"] : [])).joined(separator: ", ") + "}"
}

/// Where Expanse's layout file has window `id`.
private func editSavedSpot(_ id: CGWindowID) -> CGPoint? {
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Expanse/layout.json")
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let windows = json["windows"] as? [[String: Any]],
          let e = windows.first(where: { ($0["id"] as? NSNumber)?.uint32Value == id }),
          let x = (e["x"] as? NSNumber)?.doubleValue, let y = (e["y"] as? NSNumber)?.doubleValue else { return nil }
    return CGPoint(x: x, y: y)
}

func editMouse(_ type: CGEventType, _ p: CGPoint, _ flags: CGEventFlags = []) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
    e?.flags = flags
    e?.setIntegerValueField(.mouseEventClickState, value: 1)
    e?.post(tap: .cghidEventTap)
}

/// A key going down or up on its own (55 is ⌘): for a modifier held across part of a drag.
private func editKey(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
    let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: code, keyDown: down)
    e?.flags = flags
    e?.post(tap: .cghidEventTap)
    usleep(20_000)
}

/// A drag with the left button, a step at a time, so a case can look at Expanse mid-drag or
/// change the modifier keys on the way. Release it in a `defer`, so a failure never leaves the
/// button down.
@MainActor final class EditDrag {
    var point: CGPoint
    private var flags: CGEventFlags
    private var held = true

    init(from p: CGPoint, flags: CGEventFlags = []) {
        point = p
        self.flags = flags
        Input.move(to: p)
        editMouse(.leftMouseDown, p, flags)
        usleep(50_000)
    }

    /// To `p` in `steps` drag events, 12ms apart, with `flags` from now on if given.
    func move(to p: CGPoint, steps: Int = 20, flags: CGEventFlags? = nil) async {
        if let flags { self.flags = flags }
        let from = point, n = max(1, steps)
        for i in 1...n {
            let k = CGFloat(i) / CGFloat(n)
            point = CGPoint(x: from.x + (p.x - from.x) * k, y: from.y + (p.y - from.y) * k)
            editMouse(.leftMouseDragged, point, self.flags)
            try? await Task.sleep(nanoseconds: 12_000_000)
        }
    }

    func release() {
        guard held else { return }
        held = false
        editMouse(.leftMouseUp, point, flags)
        usleep(50_000)
    }
}

extension ExpanseState {
    @MainActor func editFrame(_ w: TestWindow) throws -> CGRect { try editFrame(w.id) }

    func editFrame(_ id: CGWindowID) throws -> CGRect {
        guard let f = window(id)?.canvas else { throw Failure("window \(id) isn't on the canvas") }
        return f
    }

    /// Where the middle of a canvas rect is on screen.
    func editCentre(_ r: CGRect) -> CGPoint { screenPoint(CGPoint(x: r.midX, y: r.midY)) }
}

extension Ctx {
    /// The runner's windows in a row, `gap` apart, at a clear spot on the canvas (see editClearSpot).
    func editRow(_ titles: [String], size: CGSize = CGSize(width: 400, height: 260), gap: CGFloat = 20) async throws -> ([TestWindow], CGPoint) {
        let spot = editClearSpot(try await state())
        return (try await row(titles, size: size, gap: gap, origin: spot), spot)
    }

    /// Zoomed out to `scale`, with the canvas point `centre` in the middle of the screen.
    @discardableResult
    func editZoomOut(on centre: CGPoint, scale: CGFloat) async throws -> ExpanseState {
        link("enter", ["zoomOut": 0])
        try await until("the canvas to open", timeout: 10) { try await self.state().active }
        try await settle()
        link("zoom", ["scale": Double(scale)])
        try await until("the zoom to \(scale)") { abs(try await self.settle().scale - scale) < 0.001 }
        let s = try await settle()
        let v = s.visibleCanvas
        link("pan", ["dx": Double((v.midX - centre.x) * s.scale), "dy": Double((v.midY - centre.y) * s.scale)])
        try await until("the view to move to \(centre)") {
            let v = try await self.state().visibleCanvas
            return hypot(v.midX - centre.x, v.midY - centre.y) < 2
        }
        return try await settle()
    }

    /// Keys go to the frontmost app: the canvas, once Expanse is in front.
    func editKeysToCanvas() async throws {
        try await until("Expanse in front, so the canvas gets the keys", timeout: 4) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.invignation.expanse"
        }
    }

    /// Dived into: at 100% on it, centred (top-aligned if taller than the screen), or its group
    /// framed (ExpanseState.isViewOn).
    func editCentred(_ w: TestWindow, in vp: CGRect) async throws {
        try await until("\(w.title) centred on screen, or its group framed", timeout: 5) { try await self.settle().isViewOn(w.id) }
    }

    /// The windows that move with `probe` when it's dragged 30 points down and back (holding ⌘,
    /// so nothing snaps, and everything ends exactly where it was): the selection, if `probe` is
    /// in one of two or more windows; otherwise just `probe`. `all`: every window on the canvas.
    func editMovesWith(_ probe: CGWindowID) async throws -> (moved: Set<CGWindowID>, all: Set<CGWindowID>) {
        let before = try await settle()
        let at = before.editCentre(try before.editFrame(probe))
        let drag = EditDrag(from: at, flags: .maskCommand)
        defer { drag.release() }
        await drag.move(to: CGPoint(x: at.x, y: at.y + 30), steps: 10)
        try await pause(0.2)
        let during = try await state()
        await drag.move(to: at, steps: 10)
        drag.release()
        try await pause(0.3)
        let after = try await settle()
        let shift = 30 / before.scale
        var moved = Set<CGWindowID>()
        for w in before.windows {
            guard let d = during.window(w.id)?.canvas else { continue }
            if hypot(d.minX - w.canvas.minX, d.minY - w.canvas.minY) > 1 {
                try expectNear(d.origin, CGPoint(x: w.canvas.minX, y: w.canvas.minY + shift), within: 1.5, "\(w.app)[\(w.id)] mid-drag")
                moved.insert(w.id)
            }
            if let a = after.window(w.id)?.canvas {
                try expectNear(a.origin, w.canvas.origin, within: 1, "\(w.app)[\(w.id)] after the probe drag put it back")
            }
        }
        return (moved, Set(before.windows.map(\.id)))
    }

    /// Opens the menu bar panel and presses its button `title` with Accessibility. False (with
    /// the panel closed again) if the button can't be found.
    func editPressPanelButton(_ title: String) async throws -> Bool {
        guard let pid = expanse?.processIdentifier else { throw Failure("Expanse isn't running") }
        let mark = log.mark()
        link("menu")
        try await expectLog("url command menu", since: mark)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        for _ in 0..<12 {
            try await pause(0.25)
            for window in editAXChildren(app, kAXWindowsAttribute) {
                var budget = 4000
                if let button = editAXFind(window, &budget, { el in
                    editAXString(el, kAXRoleAttribute) == kAXButtonRole as String && editAXMentions(el, title)
                }) {
                    AXUIElementPerformAction(button, kAXPressAction as CFString)
                    return true
                }
            }
        }
        if Input.allowed { Input.key(.escape) }
        return false
    }

    /// A TextEdit window that `open` brings (titled starting `titled`, if given), once Expanse has
    /// it: its window ID and its element, paired by where they are (TextEdit starting may also
    /// bring back windows of yours).
    func editNewTextEditWindow(titled: String? = nil, _ open: () throws -> Void) async throws -> (id: CGWindowID, ax: AXUIElement) {
        let bundle = "com.apple.TextEdit"
        let ids = Set(windowsOf(owner: "TextEdit").map(\.id))
        let elements = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
            .map { editAXChildren(AXUIElementCreateApplication($0.processIdentifier), kAXWindowsAttribute) } ?? []
        try open()
        var found: (CGWindowID, AXUIElement)?
        try await until("a new TextEdit window on the canvas", timeout: 15) {
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier else { return false }
            let fresh = editAXChildren(AXUIElementCreateApplication(pid), kAXWindowsAttribute).filter { e in
                editAXString(e, kAXSubroleAttribute) == kAXStandardWindowSubrole as String && !elements.contains { CFEqual($0, e) }
                    && (titled.map { (editAXString(e, kAXTitleAttribute) ?? "").hasPrefix($0) } ?? true)
            }
            for (id, frame) in self.windowsOf(owner: "TextEdit") where !ids.contains(id) {
                guard let el = fresh.first(where: { editAXFrame($0).map { f in
                    abs(f.minX - frame.minX) < 2 && abs(f.minY - frame.minY) < 2 && abs(f.width - frame.width) < 2 && abs(f.height - frame.height) < 2
                } ?? false }) else { continue }
                guard try await self.state().window(id) != nil else { return false }
                found = (id, el)
                return true
            }
            return false
        }
        guard let found else { throw Failure("no new TextEdit window") }
        return found
    }
}

// MARK: Accessibility (other apps' windows, and Expanse's panel)

private func editAXValue(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}

private func editAXString(_ e: AXUIElement, _ name: String) -> String? { editAXValue(e, name) as? String }

private func editAXElement(_ e: AXUIElement, _ name: String) -> AXUIElement? {
    guard let v = editAXValue(e, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

private func editAXChildren(_ e: AXUIElement, _ name: String = kAXChildrenAttribute) -> [AXUIElement] {
    (editAXValue(e, name) as? [AXUIElement]) ?? []
}

/// Depth first, looking at no more than `budget` elements.
private func editAXFind(_ e: AXUIElement, _ budget: inout Int, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    budget -= 1
    guard budget > 0 else { return nil }
    if match(e) { return e }
    for child in editAXChildren(e) {
        if let hit = editAXFind(child, &budget, match) { return hit }
    }
    return nil
}

/// Whether `text` is in its title, description or value, or in a child's (a SwiftUI button's label).
private func editAXMentions(_ e: AXUIElement, _ text: String, depth: Int = 0) -> Bool {
    let own = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { editAXString(e, $0) }
    if own.contains(where: { $0.contains(text) }) { return true }
    guard depth < 4 else { return false }
    return editAXChildren(e).contains { editAXMentions($0, text, depth: depth + 1) }
}

/// An app's menu item by its titles from the menu bar down, e.g. ["File", "New"].
private func editAXMenuItem(_ pid: pid_t, _ path: [String]) -> AXUIElement? {
    guard var here = editAXElement(AXUIElementCreateApplication(pid), kAXMenuBarAttribute) else { return nil }
    for (i, title) in path.enumerated() {
        // A menu bar's children are its items; an item's child is its menu, whose children are items.
        let items = i == 0 ? editAXChildren(here) : editAXChildren(here).flatMap { editAXChildren($0) }
        guard let next = items.first(where: { editAXString($0, kAXTitleAttribute) == title }) else { return nil }
        here = next
    }
    return here
}

private func editAXFrame(_ e: AXUIElement) -> CGRect? {
    guard let p = editAXValue(e, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
          let z = editAXValue(e, kAXSizeAttribute), CFGetTypeID(z) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(z as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: origin, size: size)
}

private func editAXFocusedWindow(_ pid: pid_t) -> AXUIElement? {
    editAXElement(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute)
}

private func editAXSheet(_ window: AXUIElement) -> AXUIElement? {
    editAXChildren(window).first { editAXString($0, kAXRoleAttribute) == kAXSheetRole as String }
}

private func editAXButton(in e: AXUIElement, _ titles: [String]) -> AXUIElement? {
    var budget = 400
    return editAXFind(e, &budget) { el in
        editAXString(el, kAXRoleAttribute) == kAXButtonRole as String && titles.contains(editAXString(el, kAXTitleAttribute) ?? "")
    }
}

/// Closes a document window this case made, deleting it if its app asks about unsaved changes.
private func editAXDiscard(_ window: AXUIElement) {
    func answer() {
        if let sheet = editAXSheet(window), let delete = editAXButton(in: sheet, ["Delete", "Don't Save", "Don’t Save"]) {
            AXUIElementPerformAction(delete, kAXPressAction as CFString)
        }
    }
    answer()
    usleep(300_000)
    if let close = editAXElement(window, kAXCloseButtonAttribute) {
        AXUIElementPerformAction(close, kAXPressAction as CFString)
        usleep(500_000)
        answer()
    }
}
