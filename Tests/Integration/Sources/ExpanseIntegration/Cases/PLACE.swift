import AppKit

/// The manual cases in docs/regression/new-windows.md.
///
/// New windows come from fixture apps (another app's windows, opened in front or in the
/// background), or from Finder for the cases about Finder. Everything happens at a spot on the
/// canvas clear of your windows (see placeClearSpot), and Expanse's `placed new window … beside
/// App[id] at …` line says which window a new one was put beside.
@MainActor enum PLACE {
    static let cases: [Case] = [
        Case("PLACE-04", "With no free spot in view, the view glides to the new window") { t in
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let s0 = try await t.state()
            let spot = placeClearSpot(s0)
            // Nearly the size of the screen: with one centred, no other its size fits on screen.
            let size = CGSize(width: (s0.viewport.width - 100).rounded(), height: (s0.viewport.height - 160).rounded())
            let f = try await t.fixture("PLACE-04", windows: 1, size: size)
            let source = try await t.placeFirstWindow(of: f)
            t.link("place", ["id": source, "x": Int(spot.x), "y": Int(spot.y), "commit": 1])
            try await t.settle()
            // Working in it: centred at 100%, its app in front.
            t.link("focus", ["id": source])
            try await t.until("the fixture's window centred, at 100%", timeout: 10) {
                let s = try await t.settle()
                return !s.active && s.isViewOn(source)
            }
            let s1 = try await t.settle()
            let from = try s1.placeFrame(source)
            let app = s1.window(source)?.app ?? "Expanse Tests"
            let mark = t.log.mark()
            let known = Set(f.windows)
            try await f.openWindow()
            guard let new = f.windows.first(where: { !known.contains($0) }) else { throw Failure("the fixture didn't open a second window") }
            let placed = try await t.placePlaced(app, since: mark)
            try t.expect(placed.anchor == source, "the new window should go beside the window it came from [\(source)], not [\(placed.anchor.map { "\($0)" } ?? "none")]: \(placed.line)")
            try await t.until("the new window on the canvas", timeout: 8) { try await t.state().window(new) != nil }
            let r = CGRect(origin: placed.spot, size: try await t.state().placeFrame(new).size)
            try t.expect(placeBeside(r, from), "the new window should be in a spot along an edge of the one it came from, 20pt away and lined up: it's at \(r), that one at \(from)")
            try t.expect(!s1.visibleCanvas.contains(r), "with the screen full, the new window's spot should be off screen (\(r) is in view \(s1.visibleCanvas))")
            try await t.until("the view to glide to the new window and centre it at 100%", timeout: 10) {
                let s = try await t.settle()
                return !s.active && s.isViewOn(new)
            }
            try await t.placeFocused(f, title: f.title(2))
            let s2 = try await t.settle()
            let landed = try s2.placeFrame(new)
            try t.expectNear(landed.origin, placed.spot, within: 2, "the new window on the canvas")
            if let hit = s2.windows.first(where: { $0.id != new && $0.canvas.insetBy(dx: 1, dy: 1).intersects(landed) }) {
                throw Failure("the new window overlaps \(hit.app)[\(hit.id)] at \(hit.canvas)")
            }
        },

        Case("PLACE-05", "A glide asked for while another runs still happens") { t in
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let s0 = try await t.state()
            let spot = placeClearSpot(s0)
            let size = CGSize(width: (s0.viewport.width - 100).rounded(), height: (s0.viewport.height - 160).rounded())
            let f = try await t.fixture("PLACE-05", windows: 1, size: size)
            let only = try await t.placeFirstWindow(of: f)
            // Its only window out of view, and you in one of ours far from it.
            t.link("place", ["id": only, "x": Int(spot.x), "y": Int(spot.y), "commit": 1])
            let here = try await t.window("PLACE-05 Here", CGRect(x: 160, y: 160, width: 400, height: 260))
            t.place(here, at: CGPoint(x: spot.x, y: spot.y + size.height + 3000))
            try await t.settle()
            t.link("focus", ["id": here.id])
            try await t.until("the fixture's window out of view", timeout: 10) {
                let s = try await t.settle()
                return !s.active && s.window(only)?.parked == true
            }
            let app = try await t.state().window(only)?.app ?? "Expanse Tests"
            let mark = t.log.mark()
            let known = Set(f.windows)
            // As when a document opens: its app comes forward (focus goes to its parked window, and
            // the view glides there), and the new window, too big to fit on screen, comes at once.
            f.activate()
            try await f.openWindow()
            guard let new = f.windows.first(where: { !known.contains($0) }) else { throw Failure("the fixture didn't open a second window") }
            try await t.until("the view to end centred on the new window, at 100%", timeout: 15) {
                let s = try await t.settle()
                return !s.active && s.window(new) != nil && s.isViewOn(new)
            }
            try await t.expectLog("glide to \(app)[\(new)]", since: mark)
            try await t.placeFocused(f, title: f.title(2))
            try await t.pause(1)
            let s = try await t.settle()
            try t.expect(!s.active && s.isViewOn(new), "the view should stay on the new window (nothing should glide away again)")
        },

        Case("PLACE-12", "A new window opens beside its own app's window") { t in
            let spot = placeClearSpot(try await t.state())
            let f = try await t.fixture("PLACE-12", windows: 1, size: CGSize(width: 400, height: 260))
            let own = try await t.placeFirstWindow(of: f)
            let front = try await t.window("PLACE-12 Front", CGRect(x: 200, y: 200, width: 400, height: 260))
            // The app's window on the left, another app's on the right and in front (gone to, so
            // it's also in front on the canvas), free space around both, both on screen.
            t.link("place", ["id": own, "x": Int(spot.x), "y": Int(spot.y), "commit": 0])
            t.place(front, at: CGPoint(x: spot.x + 560, y: spot.y))
            try await t.settle()
            t.link("focus", ["id": front.id])
            try await t.until("ours in view and in front", timeout: 10) {
                let s = try await t.settle()
                return !s.active && s.window(front.id)?.parked == false
                    && NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            }
            let s1 = try await t.settle()
            guard let o = s1.window(own), !o.parked else { throw Skip("the screen is too narrow to show both windows at 100%") }
            // The app opens a window while in the background (as `open -g` does).
            var mark = t.log.mark()
            var known = Set(f.windows)
            try await f.openWindow()
            guard let second = f.windows.first(where: { !known.contains($0) }) else { throw Failure("the fixture didn't open a second window") }
            var placed = try await t.placePlaced(o.app, since: mark)
            try t.expect(placed.anchor == own, "the new window should open beside its own app's window [\(own)], not beside [\(placed.anchor.map { "\($0)" } ?? "none")] (the one in front is [\(front.id)]): \(placed.line)")
            try await t.until("the new window on the canvas", timeout: 8) { try await t.state().window(second) != nil }
            var r = CGRect(origin: placed.spot, size: try await t.state().placeFrame(second).size)
            try t.expect(placeBeside(r, o.canvas), "the new window should be along an edge of its app's window, 20pt away and lined up: it's at \(r), that one at \(o.canvas)")
            // None of its app's windows on screen: beside the window in front.
            for (i, id) in f.windows.enumerated() {
                t.link("place", ["id": id, "x": Int(spot.x + 8000 + CGFloat(i) * 700), "y": Int(spot.y), "commit": i == f.windows.count - 1 ? 1 : 0])
            }
            t.link("focus", ["id": front.id])
            try await t.until("the fixture's windows out of view, ours in view and in front", timeout: 10) {
                let s = try await t.settle()
                return !s.active && f.windows.allSatisfy { s.window($0)?.parked == true } && s.window(front.id)?.parked == false
                    && NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            }
            let s2 = try await t.settle()
            let anchor = try s2.placeFrame(front.id)
            mark = t.log.mark()
            known = Set(f.windows)
            try await f.openWindow()
            guard let third = f.windows.first(where: { !known.contains($0) }) else { throw Failure("the fixture didn't open a third window") }
            placed = try await t.placePlaced(o.app, since: mark)
            try t.expect(placed.anchor == front.id, "with none of its app's windows on screen, the new window should open beside the window in front, [\(front.id)], not [\(placed.anchor.map { "\($0)" } ?? "none")]: \(placed.line)")
            try await t.until("the third window on the canvas", timeout: 8) { try await t.state().window(third) != nil }
            r = CGRect(origin: placed.spot, size: try await t.state().placeFrame(third).size)
            try t.expect(placeBeside(r, anchor), "the third window should be along an edge of the window in front: it's at \(r), that one at \(anchor)")
        },

        Case("PLACE-16", "A new Finder window opens beside you") { t in
            try t.needsInput()
            guard placeFinderPID != nil else { throw Skip("Finder isn't running") }
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let folders = try placeFolders("PLACE-16", count: 4)
            var opened: [AXUIElement] = []
            defer {
                opened.forEach(placeAXClose)
                placeRemove(folders)
            }
            let first = try await t.placeOpenFinder(folders[0])
            opened.append(first.ax)
            let spot = placeClearSpot(try await t.state())
            t.link("place", ["id": first.id, "x": Int(spot.x), "y": Int(spot.y), "commit": 1])
            try await t.settle()
            // Working in it: at 100%, Finder in front.
            t.link("focus", ["id": first.id])
            try await t.until("Finder in front, its window in view", timeout: 10) {
                let s = try await t.settle()
                return !s.active && s.window(first.id)?.parked == false && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
            }
            var current = first.id
            for (n, folder) in folders.enumerated().dropFirst() {
                let before = try await t.settle()
                let anchor = try before.placeFrame(current)
                let mark = t.log.mark()
                let new = try await t.placeOpenFinder(folder)
                opened.append(new.ax)
                if t.log.lines(since: mark).contains(where: { $0.hasPrefix("tab Finder[\(new.id)]") }) {
                    throw Skip("Finder opened a tab, not a window (Desktop & Dock › Prefer tabs is set to Always?)")
                }
                let placed = try await t.placePlaced("Finder", since: mark)
                try t.expect(placed.anchor == current, "new Finder window \(n) should open beside the Finder window you're in [\(current)], not [\(placed.anchor.map { "\($0)" } ?? "none")]: \(placed.line)")
                let size = try await t.state().placeFrame(new.id).size
                let r = CGRect(origin: placed.spot, size: size)
                try t.expect(placeBeside(r, anchor), "new Finder window \(n) should be along an edge of the one you're in, 20pt away and lined up (not at an old Finder spot): it's at \(r), that one at \(anchor)")
                if before.visibleCanvas.insetBy(dx: -1, dy: -1).contains(r) {
                    try await t.pause(1)
                    let s = try await t.settle()
                    try t.expectNear(s.camera, before.camera, within: 2, "the view after new Finder window \(n) opened on screen (it shouldn't glide)")
                } else {
                    try await t.until("the view to glide to new Finder window \(n), which opened off screen", timeout: 10) {
                        let s = try await t.settle()
                        return !s.active && (s.window(new.id).map { s.visibleCanvas.insetBy(dx: -1, dy: -1).contains($0.canvas) } ?? false)
                    }
                }
                let s = try await t.settle()
                try t.expectNear(try s.placeFrame(new.id).origin, placed.spot, within: 2, "new Finder window \(n) on the canvas")
                current = new.id
            }
        },

        Case("PLACE-17", "A new window that reuses a closed window's ID isn't sent to its spot") { t in
            try t.needsInput()
            guard placeFinderPID != nil else { throw Skip("Finder isn't running") }
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let folders = try placeFolders("PLACE-17", count: 3)
            var opened: [AXUIElement] = []
            defer {
                opened.forEach(placeAXClose)
                placeRemove(folders)
            }
            let f1 = try await t.placeOpenFinder(folders[0])
            opened.append(f1.ax)
            let f2 = try await t.placeOpenFinder(folders[1])
            opened.append(f2.ax)
            let spot = placeClearSpot(try await t.state())
            // F1 where you work, F2 far off (parked).
            t.link("place", ["id": f1.id, "x": Int(spot.x), "y": Int(spot.y), "commit": 0])
            t.link("place", ["id": f2.id, "x": Int(spot.x + 6000), "y": Int(spot.y), "commit": 1])
            try await t.settle()
            t.link("focus", ["id": f1.id])
            try await t.until("F1 in view, F2 out of it", timeout: 10) {
                let s = try await t.settle()
                return !s.active && s.window(f1.id)?.parked == false && s.window(f2.id)?.parked == true
            }
            let s1 = try await t.settle()
            let home1 = try s1.placeFrame(f1.id).origin
            let spot2 = try s1.placeFrame(f2.id).origin
            // 1. Minimised and back from the Dock: F1 comes back to its own spot.
            placeAXMinimise(f1.ax, true)
            try await t.until("Expanse to let go of F1 while it's minimised", timeout: 10) { try await t.state().window(f1.id) == nil }
            placeAXMinimise(f1.ax, false)
            try await t.until("F1 back on the canvas", timeout: 10) { try await t.state().window(f1.id) != nil }
            try t.expectNear(try await t.settle().placeFrame(f1.id).origin, home1, within: 1, "F1 back from the Dock (it should come back to its own spot)")
            // 2. F2 into view, closed there, then back to F1.
            t.link("focus", ["id": f2.id])
            try await t.until("F2 in view", timeout: 10) { let s = try await t.settle(); return !s.active && s.window(f2.id)?.parked == false }
            placeAXClose(f2.ax)
            try await t.until("F2 to close", timeout: 8) { !t.windowsOf(owner: "Finder").contains { $0.id == f2.id } }
            try await t.until("Expanse to drop F2", timeout: 8) { try await t.state().window(f2.id) == nil }
            t.link("focus", ["id": f1.id])
            try await t.until("back in F1", timeout: 10) { let s = try await t.settle(); return !s.active && s.window(f1.id)?.parked == false }
            let anchor = try await t.settle().placeFrame(f1.id)
            // 3. More than 2s later (a window at a closed one's spot within 2s is a tab), a new window.
            try await t.pause(3)
            let mark = t.log.mark()
            let new = try await t.placeOpenFinder(folders[2])
            opened.append(new.ax)
            let reused = new.id == f2.id ? " (Finder gave it F2's old ID)" : ""
            if t.log.lines(since: mark).contains(where: { $0.hasPrefix("tab Finder[\(new.id)]") }) {
                throw Skip("Finder opened a tab, not a window (Desktop & Dock › Prefer tabs is set to Always?)")
            }
            try await t.expectLog("tracking Finder [\(new.id)]", since: mark)
            let placed = try await t.placePlaced("Finder", since: mark)
            try t.expect(placed.anchor == f1.id, "the new window\(reused) should be placed beside F1 [\(f1.id)], not [\(placed.anchor.map { "\($0)" } ?? "none")]: \(placed.line)")
            let landed = try await t.settle().placeFrame(new.id)
            try t.expect(hypot(landed.minX - spot2.x, landed.minY - spot2.y) > 40, "the new window\(reused) shouldn't go to F2's old spot \(spot2)")
            try t.expect(placeBeside(landed, anchor), "the new window\(reused) should be along an edge of F1, 20pt away and lined up: it's at \(landed), F1 at \(anchor)")
        },
        Case("PLACE-18", "A tab dragged out into a new window is left alone until you let go") { t in
            try t.needsInput()
            let spot = placeClearSpot(try await t.state())
            let f = try await t.fixture("PLACE-18", windows: 1, size: CGSize(width: 520, height: 340))
            let own = try await t.placeFirstWindow(of: f)
            t.link("place", ["id": own, "x": Int(spot.x), "y": Int(spot.y), "commit": 1])
            t.link("focus", ["id": own])
            try await t.until("the fixture's window in view", timeout: 10) {
                let s = try await t.settle()
                return !s.active && s.window(own)?.parked == false
            }
            let s0 = try await t.settle()
            guard let app = s0.window(own)?.app, let src = realFrame(own) else { throw Failure("the fixture's window isn't on screen") }
            // The button down in its page (not its title bar, which would drag the window itself),
            // then a tab out of it: a new window under the pointer that the app moves with it.
            let press = CGPoint(x: src.minX + 100, y: src.minY + 100)
            placePost(.mouseMoved, press)
            try await t.pause(0.05)
            let mark = t.log.mark()
            placePost(.leftMouseDown, press)
            try await t.pause(0.1)
            var torn: CGWindowID?
            do {
                let known = Set(f.windows)
                try await f.send("tearoff")
                torn = f.windows.first { !known.contains($0) }
                guard let torn else { throw Failure("the fixture didn't tear a window off") }
                // Dragged 300pt right and 150 down over 2.5s, longer than a scan takes to come (0.15s).
                let grab = Fixture.tearOffGrab
                var worst: CGFloat = 0
                let steps = 150
                for i in 1...steps {
                    let p = CGPoint(x: press.x + 300 * CGFloat(i) / CGFloat(steps), y: press.y + 150 * CGFloat(i) / CGFloat(steps))
                    placePost(.leftMouseDragged, p)
                    try await t.pause(0.016)
                    if i % 15 == 0, let r = realFrame(torn) {
                        worst = max(worst, hypot(r.minX + grab.dx - p.x, r.minY + grab.dy - p.y))
                    }
                }
                let taken = t.log.lines(since: mark).first { $0.hasPrefix("tracking ") && $0.contains("[\(torn)]") }
                try t.expect(taken == nil, "Expanse took the new window on while the button was held: “\(taken ?? "")”")
                try t.expect(worst <= 24, "the new window should stay under the pointer while it's dragged; it was \(Int(worst))pt away")
            } catch {
                placePost(.leftMouseUp, press)
                throw error
            }
            let end = CGPoint(x: press.x + 300, y: press.y + 150)
            placePost(.leftMouseUp, end)
            guard let torn else { return }
            // Let go: beside the window it came from, as any new window of its app.
            let placed = try await t.placePlaced(app, since: mark)
            try t.expect(placed.anchor == own, "the new window should go beside the window it came from [\(own)], not [\(placed.anchor.map { "\($0)" } ?? "none")]: \(placed.line)")
            try await t.until("the new window on the canvas", timeout: 8) { try await t.state().window(torn) != nil }
            let s1 = try await t.settle()
            let r = CGRect(origin: placed.spot, size: try s1.placeFrame(torn).size)
            try t.expect(placeBeside(r, try s1.placeFrame(own)), "the new window should be along an edge of its own, 20pt away and lined up: it's at \(r)")
            try await t.until("the real window at its spot", timeout: 8) {
                let s = try await t.settle()
                guard let w = s.window(torn), !w.parked, let real = realFrame(torn) else { return false }
                return hypot(real.minX - s.screenPoint(w.canvas.origin).x, real.minY - s.screenPoint(w.canvas.origin).y) < 3
            }
        },
    ]
}

// MARK: Helpers

/// A spot on the canvas clear of every window on it: right of and above them all.
/// A mouse event at `p` (global), with no modifiers (left unset, a key held elsewhere comes along).
private func placePost(_ type: CGEventType, _ p: CGPoint) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
    e?.flags = []
    e?.post(tap: .cghidEventTap)
}

private func placeClearSpot(_ s: ExpanseState) -> CGPoint {
    let all = s.windows.map(\.canvas).reduce(CGRect.null) { $0.union($1) }
    guard !all.isNull else { return .zero }
    return CGPoint(x: (all.maxX + 3000).rounded(), y: (all.minY - 3000).rounded())
}

/// Whether `r` is one of the spots along an edge of `a` that a new window from it is tried in:
/// 20pt to its right or left (tops, bottoms or centres lined up), or below or above it (left
/// edges, right edges or centres lined up).
private func placeBeside(_ r: CGRect, _ a: CGRect) -> Bool {
    let g: CGFloat = 20
    let ys = [a.minY, a.maxY - r.height, a.midY - r.height / 2]
    let xs = [a.minX, a.maxX - r.width, a.midX - r.width / 2]
    let spots = ys.flatMap { [CGPoint(x: a.maxX + g, y: $0), CGPoint(x: a.minX - g - r.width, y: $0)] }
        + xs.flatMap { [CGPoint(x: $0, y: a.maxY + g), CGPoint(x: $0, y: a.minY - g - r.height)] }
    return spots.contains { abs($0.x - r.minX) <= 1.5 && abs($0.y - r.minY) <= 1.5 }
}

/// Expanse's `placed new window App at {x, y} beside App[id] at {{…}}`.
private struct PlacePlaced {
    let line: String
    let spot: CGPoint
    let anchor: CGWindowID?
}

private var placeFinderPID: pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.processIdentifier
}

/// Empty folders to open in Finder, named so their windows are told apart by title.
private func placeFolders(_ name: String, count: Int) throws -> [URL] {
    try (1...count).map { i in
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Expanse Tests \(name) \(i)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private func placeRemove(_ folders: [URL]) {
    for f in folders { try? FileManager.default.removeItem(at: f) }
}

extension ExpanseState {
    fileprivate func placeFrame(_ id: CGWindowID) throws -> CGRect {
        guard let f = window(id)?.canvas else { throw Failure("window \(id) isn't on the canvas") }
        return f
    }
}

fileprivate extension Ctx {
    /// The fixture's first window, once Expanse has it.
    func placeFirstWindow(of f: Fixture) async throws -> CGWindowID {
        guard let id = f.windows.first else { throw Failure("the fixture has no window") }
        try await until("Expanse to take on the fixture's window", timeout: 10) { try await self.state().window(id) != nil }
        return id
    }

    /// The next `placed new window App at …` line since `mark`.
    func placePlaced(_ app: String, since mark: Int) async throws -> PlacePlaced {
        let prefix = "placed new window \(app) at "
        guard let line = await log.wait(since: mark, timeout: 10, { $0.hasPrefix(prefix) }) else {
            throw Failure("no “\(prefix)…” line: the new window wasn't placed as a new window")
        }
        guard let m = line.firstMatch(of: #/ at (\{[^}]*\})(?: beside .*\[(\d+)\] at )?/#) else { throw Failure("couldn't read “\(line)”") }
        return PlacePlaced(line: line, spot: NSPointFromString(String(m.1)), anchor: m.2.flatMap { CGWindowID($0) })
    }

    /// The fixture's app in front, with its window `title` focused.
    func placeFocused(_ f: Fixture, title: String) async throws {
        try await until("the fixture's app in front", timeout: 5) { NSWorkspace.shared.frontmostApplication?.processIdentifier == f.pid }
        guard Input.allowed, let pid = f.pid else { return }
        try await until("“\(title)” to have focus", timeout: 5) {
            placeAXElement(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute).flatMap { placeAXString($0, kAXTitleAttribute) } == title
        }
    }

    /// Opens `folder` in a Finder window and waits for Expanse to have it: its ID and its element.
    func placeOpenFinder(_ folder: URL) async throws -> (id: CGWindowID, ax: AXUIElement) {
        guard let pid = placeFinderPID else { throw Skip("Finder isn't running") }
        let ids = Set(windowsOf(owner: "Finder").map(\.id))
        try open(folder.path)
        var found: (CGWindowID, AXUIElement)?
        try await until("a Finder window for “\(folder.lastPathComponent)” on the canvas", timeout: 15) {
            guard let el = placeAXChildren(AXUIElementCreateApplication(pid), kAXWindowsAttribute)
                    .first(where: { el in
                        // The folder's name, or its whole path if Finder is set to show that.
                        let title = placeAXString(el, kAXTitleAttribute) ?? ""
                        return title == folder.lastPathComponent || title.hasSuffix("/" + folder.lastPathComponent)
                    }),
                  let at = placeAXFrame(el),
                  let id = self.windowsOf(owner: "Finder").first(where: { w in
                      !ids.contains(w.id) && abs(w.frame.minX - at.minX) < 2 && abs(w.frame.minY - at.minY) < 2
                          && abs(w.frame.width - at.width) < 2 && abs(w.frame.height - at.height) < 2
                  })?.id,
                  try await self.state().window(id) != nil else { return false }
            found = (id, el)
            return true
        }
        guard let found else { throw Failure("no Finder window for \(folder.lastPathComponent)") }
        return found
    }
}

// MARK: Accessibility (Finder's windows, and which of a fixture's has focus)

private func placeAXValue(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}

private func placeAXString(_ e: AXUIElement, _ name: String) -> String? { placeAXValue(e, name) as? String }

private func placeAXElement(_ e: AXUIElement, _ name: String) -> AXUIElement? {
    guard let v = placeAXValue(e, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

private func placeAXChildren(_ e: AXUIElement, _ name: String) -> [AXUIElement] {
    (placeAXValue(e, name) as? [AXUIElement]) ?? []
}

private func placeAXFrame(_ e: AXUIElement) -> CGRect? {
    guard let p = placeAXValue(e, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
          let z = placeAXValue(e, kAXSizeAttribute), CFGetTypeID(z) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(z as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: origin, size: size)
}

/// Presses the window's close button (nothing happens if it's gone already).
private func placeAXClose(_ window: AXUIElement) {
    guard let button = placeAXElement(window, kAXCloseButtonAttribute) else { return }
    AXUIElementPerformAction(button, kAXPressAction as CFString)
}

private func placeAXMinimise(_ window: AXUIElement, _ on: Bool) {
    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
}
