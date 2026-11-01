import AppKit
import ApplicationServices

/// The manual cases in docs/regression/layouts-and-restarts.md.
///
/// Windows a case arranges go far out on the canvas (persistOrigin), away from yours, so gaps
/// and spots are only between its own windows. A case that quits Expanse starts it again, failed
/// or not; one that takes snapshots puts your earlier layouts back afterwards.
@MainActor enum PERSIST {
    static let cases: [Case] = [
        Case("PERSIST-03", "Quitting puts every window back where macOS had it") { t in
            let (parked, parkedAt) = try await t.persistWindow("PERSIST-03 Parked", CGRect(x: 120, y: 140, width: 520, height: 360))
            let (moved, movedAt) = try await t.persistWindow("PERSIST-03 Moved", CGRect(x: 220, y: 200, width: 560, height: 380))
            let (mini, miniAt) = try await t.persistWindow("PERSIST-03 Minimised", CGRect(x: 320, y: 260, width: 480, height: 340))
            let (f, fid, hiddenAt) = try await t.persistFixture("PERSIST-03 Hidden")
            // Rearranged on the canvas: one parked, one moved and made smaller, one minimised, and
            // an app hidden (its window parked first).
            t.place(parked, at: persistOrigin)
            t.persistPlace(fid, at: CGPoint(x: persistOrigin.x + 800, y: persistOrigin.y))
            try await t.until("the windows parked", timeout: 10) {
                let s = try await t.state()
                return s.window(parked.id)?.parked == true && s.window(fid)?.parked == true
            }
            let vis = try await t.settle().visibleCanvas
            t.place(moved, at: CGPoint(x: vis.minX + 40, y: vis.minY + 40))
            try await t.until("the moved window somewhere else", timeout: 5) { moved.real.map { !persistNear($0, movedAt, 20) } ?? false }
            if let r = moved.real { moved.setFrame(CGRect(origin: r.origin, size: CGSize(width: 420, height: 300))) }
            try await t.until("Expanse to take the moved window's new size", timeout: 5) {
                guard let c = try await t.state().window(moved.id)?.canvas else { return false }
                return abs(c.width - 420) <= 2 && abs(c.height - 300) <= 2
            }
            mini.minimise()
            f.hide()
            try await t.until("the minimised and hidden windows off the canvas", timeout: 10) {
                let s = try await t.state()
                return s.window(mini.id) == nil && s.window(fid) == nil
            }
            try await t.persistRelaunchingAfter {
                try await t.quitExpanse()
                try await t.persistExpectBack(parked.id, "the parked window", at: parkedAt)
                try await t.persistExpectBack(moved.id, "the moved and resized window", at: movedAt)
                mini.restore()
                try await t.until("the minimised window back from the Dock", timeout: 5) { mini.onScreen }
                try await t.persistExpectBack(mini.id, "the minimised window", at: miniAt)
                f.unhide()
                try await t.until("the hidden app's window shown again", timeout: 5) { isOnScreen(fid) }
                try await t.persistExpectBack(fid, "the hidden app's window", at: hiddenAt)
            }
        },
        Case("PERSIST-05", "kill or Ctrl-C puts windows back too") { t in
            let (a, aAt) = try await t.persistWindow("PERSIST-05 A", CGRect(x: 160, y: 180, width: 520, height: 360))
            let (b, bAt) = try await t.persistWindow("PERSIST-05 B", CGRect(x: 300, y: 260, width: 480, height: 320))
            t.place(a, at: persistOrigin)
            t.place(b, at: CGPoint(x: persistOrigin.x + 600, y: persistOrigin.y))
            try await t.persistRelaunchingAfter {
                for (sig, name) in [(SIGTERM, "kill (SIGTERM)"), (SIGINT, "Ctrl-C (SIGINT)")] {
                    // (After the relaunch, they're back at their spots out of view, parked again.)
                    try await t.until("A and B parked", timeout: 10) {
                        let s = try await t.state()
                        return s.window(a.id)?.parked == true && s.window(b.id)?.parked == true
                    }
                    guard let app = t.expanse else { throw Failure("Expanse isn't running") }
                    kill(app.processIdentifier, sig)
                    do {
                        try await t.until("Expanse to exit", timeout: 15) { app.isTerminated }
                    } catch {
                        throw Failure("Expanse didn't exit after \(name)")
                    }
                    try await t.persistExpectBack(a.id, "A after \(name)", at: aAt)
                    try await t.persistExpectBack(b.id, "B after \(name)", at: bAt)
                    try await t.launchExpanse()
                }
            }
        },
        Case("PERSIST-07", "Pause puts windows back and stops managing them") { t in
            let (a, aAt) = try await t.persistWindow("PERSIST-07 Parked", CGRect(x: 140, y: 160, width: 520, height: 360))
            let (b, bAt) = try await t.persistWindow("PERSIST-07 Moved", CGRect(x: 260, y: 240, width: 480, height: 320))
            t.place(a, at: persistOrigin)
            let vis = try await t.settle().visibleCanvas
            t.place(b, at: CGPoint(x: vis.minX + 60, y: vis.minY + 60))
            try await t.until("A parked, B moved", timeout: 8) {
                let s = try await t.state()
                return s.window(a.id)?.parked == true && b.real.map { !persistNear($0, bAt, 20) } ?? false
            }
            let backdrop = t.persistBackdropShown()
            let mark = t.log.mark()
            t.link("pause")
            try await t.persistExpectLine("paused", since: mark)
            try await t.untilPaused("paused")
            try await t.persistExpectBack(a.id, "the parked window", at: aAt)
            try await t.persistExpectBack(b.id, "the moved window", at: bAt)
            let s = try await t.state()
            try t.expect(s.window(a.id) == nil && s.window(b.id) == nil, "paused, Expanse should stop managing windows, but the dump still lists them")
            // (Only if the window server showed the backdrop to begin with.)
            if backdrop { try t.expect(!t.persistBackdropShown(), "the backdrop should go when Expanse pauses") }
            if let panel = try await t.persistPanel() {
                try t.expect(panel.texts.contains("Paused \u{B7} windows back in the macOS layout"),
                             "the panel should say “Paused · windows back in the macOS layout”")
            }
            // Step 2: a window you move while paused stays where you put it.
            let mark2 = t.log.mark()
            let moved = try await t.persistMoveYourself(b)
            try await t.pause(2)
            try t.expectNear(b.real ?? .zero, moved, within: 2, "the window moved while paused")
            try await t.noLog("follow ", since: mark2, within: 0.1)
        },
        Case("PERSIST-08", "While paused, only ⌥` and the switch bring Expanse back") { t in
            try t.needsInput()
            let ws = try await t.row(["PERSIST-08 A", "PERSIST-08 B"], size: CGSize(width: 480, height: 320), origin: persistOrigin)
            t.link("focus", ["id": ws[0].id])
            try await t.until("A in view") { try await t.settle().window(ws[0].id)?.parked == false }
            t.link("pause")
            try await t.untilPaused("paused")
            try await t.pause(0.5)
            let frames = ws.map(\.real)
            let mark = t.log.mark()
            // Step 1: the hot corner, ⌃→ and ⌃⌥C do nothing.
            let pointer = Input.pointer
            if let corner = persistSafeHotCorner(t) {
                Input.move(to: corner)
                try await t.pause(0.6)
                Input.move(to: pointer)
            }
            Input.key(.right, .maskControl)
            try await t.pause(0.6)
            Input.key(.c, [.maskControl, .maskAlternate])
            try await t.pause(1.5)
            let s = try await t.state()
            try t.expect(s.paused, "Expanse resumed while paused, without ⌥` or the switch")
            if let line = t.log.lines(since: mark).first(where: { $0.hasPrefix("navigate") || $0.hasPrefix("centre ") || $0.contains("glide to ") }) {
                throw Failure("paused, Expanse acted on a shortcut: \(line)")
            }
            for (w, f) in zip(ws, frames) {
                try t.expectNear(w.real ?? .zero, f ?? .zero, within: 1, "\(w.title) while paused")
            }
            // Step 2: ⌥` resumes, and doesn't zoom out too.
            let mark2 = t.log.mark()
            Input.key(.grave, .maskAlternate)
            try await t.persistExpectLine("resumed", since: mark2)
            try await t.until("resumed") { try await !t.state().paused }
            try await t.pause(1.5)
            let after = try await t.settle()
            try t.expect(!after.active, "⌥` while paused should only resume Expanse, not zoom out")
        },
        Case("PERSIST-09", "Resume brings the canvas back as you left it") { t in
            let ws = try await t.row(["PERSIST-09 A", "PERSIST-09 B"], size: CGSize(width: 520, height: 360), origin: persistOrigin)
            t.link("focus", ["id": ws[0].id])
            try await t.until("A in view") { try await t.settle().window(ws[0].id)?.parked == false }
            t.place(ws[1], at: CGPoint(x: persistOrigin.x + 6000, y: persistOrigin.y + 4000))
            try await t.until("B parked") { try await t.state().window(ws[1].id)?.parked == true }
            let before = try await t.settle()
            t.link("pause")
            try await t.untilPaused("paused")
            try await t.pause(1)
            let mark = t.log.mark()
            t.link("resume")
            let resumed = try await t.persistExpectLine("resumed", since: mark)
            try await t.expectLog("first sync:", since: resumed, timeout: 10)
            try await t.until("A and B back on the canvas", timeout: 10) {
                let s = try await t.state()
                return ws.allSatisfy { s.window($0.id) != nil }
            }
            try await t.pause(1)
            let after = try await t.settle()
            for w in ws {
                guard let a = before.window(w.id), let b = after.window(w.id) else { throw Failure("\(w.title) isn't on the canvas") }
                try t.expectNear(b.canvas, a.canvas, within: 1, "\(w.title)'s spot after resuming")
                try t.expect(b.parked == a.parked, "\(w.title) should be \(a.parked ? "parked" : "on screen") again after resuming")
            }
            try t.expectNear(after.camera, before.camera, within: 1, "the view after resuming")
            try await t.persistExpectInPlace(ws)
            if let panel = try await t.persistPanel() {
                try t.expect(panel.texts.contains { $0.hasPrefix("On \u{B7} ") && $0.hasSuffix(" on the canvas") },
                             "the panel should say “On · N windows on the canvas”")
            }
        },
        Case("PERSIST-10", "Hidden and minimised windows also go back on Quit and Pause") { t in
            let (m, mAt) = try await t.persistWindow("PERSIST-10 Minimised", CGRect(x: 180, y: 200, width: 500, height: 340))
            let (f, fid, fAt) = try await t.persistFixture("PERSIST-10 TextEdit")
            @MainActor func outOfView() async throws {
                // Clear of wherever the view is: an earlier case can leave it at persistOrigin.
                let vis = try await t.state().visibleCanvas
                let away = CGPoint(x: (vis.maxX + 3000).rounded(), y: vis.minY.rounded())
                t.place(m, at: away)
                t.persistPlace(fid, at: CGPoint(x: away.x + 700, y: away.y))
                try await t.until("both parked", timeout: 10) {
                    let s = try await t.state()
                    return s.window(m.id)?.parked == true && s.window(fid)?.parked == true
                }
                f.hide()
                m.minimise()
                try await t.until("the hidden and minimised windows off the canvas", timeout: 10) {
                    let s = try await t.state()
                    return s.window(m.id) == nil && s.window(fid) == nil
                }
            }
            @MainActor func shownAgain(_ when: String) async throws {
                f.unhide()
                m.restore()
                try await t.until("both shown again", timeout: 6) { isOnScreen(fid) && m.onScreen }
                try await t.persistExpectBack(fid, "the hidden app's window after \(when)", at: fAt)
                try await t.persistExpectBack(m.id, "the minimised window after \(when)", at: mAt)
            }
            // Pause.
            try await outOfView()
            t.link("pause")
            try await t.untilPaused("paused")
            try await shownAgain("pausing")
            t.link("resume")
            try await t.until("both back on the canvas", timeout: 10) {
                let s = try await t.state()
                return !s.paused && s.window(m.id) != nil && s.window(fid) != nil
            }
            // Quit.
            try await outOfView()
            try await t.persistRelaunchingAfter {
                try await t.quitExpanse()
                try await shownAgain("quitting")
            }
        },
        Case("PERSIST-13", "Quit or Pause during a hop leaves nothing parked") { t in
            var ws: [(TestWindow, CGRect)] = []
            for i in 0..<6 {
                ws.append(try await t.persistWindow("PERSIST-13 \(i + 1)", CGRect(x: 80 + 60 * CGFloat(i), y: 100 + 40 * CGFloat(i), width: 420, height: 300)))
            }
            for (i, (w, _)) in ws.enumerated() { t.place(w, at: CGPoint(x: persistOrigin.x + CGFloat(i) * 440, y: persistOrigin.y)) }
            @MainActor func hopFromFirst() async throws {
                t.link("focus", ["id": ws[0].0.id])
                try await t.until("the first window in view", timeout: 8) { try await t.settle().window(ws[0].0.id)?.parked == false }
            }
            @MainActor func expectAllBack(_ when: String) async throws {
                for (w, at) in ws { try await t.persistExpectBack(w.id, "\(w.title) after \(when)", at: at) }
            }
            try await hopFromFirst()
            try await t.persistRelaunchingAfter {
                // Step 1: a hop, and Quit while it's under way.
                let mark = t.log.mark()
                t.link("nav", ["dir": "right"])
                guard await t.log.wait(since: mark, timeout: 2, { $0.hasPrefix("navigate to") }) != nil else {
                    throw Failure("the hop didn't start (no “navigate to” line)")
                }
                try await t.quitExpanse()
                try await expectAllBack("quitting during a hop")
                try await t.launchExpanse()
            }
            try await t.until("the windows back on the canvas", timeout: 15) {
                let s = try await t.state()
                return ws.allSatisfy { s.window($0.0.id) != nil }
            }
            try await hopFromFirst()
            // Step 2: a hop, and Pause straight after: it waits for the hop to land.
            let mark = t.log.mark()
            t.link("nav", ["dir": "right"])
            // (A beat, so the links arrive in that order.)
            try await t.pause(0.05)
            t.link("pause")
            let hop = try await t.persistLogIndex("navigate to", since: mark)
            let landed = try await t.persistLogIndex("glide timing:", since: hop)
            _ = try await t.persistExpectLine("paused", since: landed, timeout: 8)
            try await t.untilPaused("paused")
            try await expectAllBack("pausing during a hop")
        },
        Case("PERSIST-14", "Windows put back on Quit come back at full size") { t in
            let big = CGSize(width: min(1200, t.screen.width - 200), height: min(800, t.screen.height - 220))
            let (w, at) = try await t.persistWindow("PERSIST-14 Big", CGRect(x: 60, y: 90, width: big.width, height: big.height))
            // Made smaller at 100%, then parked.
            if let r = w.real { w.setFrame(CGRect(origin: r.origin, size: CGSize(width: 600, height: 400))) }
            try await t.until("Expanse to take its new size", timeout: 5) {
                guard let c = try await t.state().window(w.id)?.canvas else { return false }
                return abs(c.width - 600) <= 2 && abs(c.height - 400) <= 2
            }
            t.place(w, at: persistOrigin)
            try await t.until("parked") { try await t.state().window(w.id)?.parked == true }
            try await t.persistRelaunchingAfter {
                try await t.quitExpanse()
                try await t.persistExpectBack(w.id, "the window", at: at)
            }
        },
        Case("PERSIST-18", "A hidden app's windows keep their spots across an Expanse restart") { t in
            let f = try await t.fixture("PERSIST-18 Safari", windows: 2, size: CGSize(width: 560, height: 380))
            let ids = f.windows
            guard ids.count == 2 else { throw Failure("the fixture opened \(ids.count) windows, not 2") }
            try await t.until("Expanse to take on both windows", timeout: 10) {
                let s = try await t.state()
                return ids.allSatisfy { s.window($0) != nil }
            }
            // Well apart.
            t.persistPlace(ids[0], at: persistOrigin)
            t.persistPlace(ids[1], at: CGPoint(x: persistOrigin.x + 1400, y: persistOrigin.y + 900))
            try await t.pause(0.5)
            let before = try await t.settle()
            let spots = try ids.map { id -> CGRect in
                guard let c = before.window(id)?.canvas else { throw Failure("the fixture's window [\(id)] isn't on the canvas") }
                return c
            }
            f.hide()
            try await t.until("the hidden windows off the canvas", timeout: 10) {
                let s = try await t.state()
                return ids.allSatisfy { s.window($0) == nil }
            }
            try await t.persistRelaunchingAfter {
                try await t.quitExpanse()
                guard let saved = PersistLayout(persistLayoutFile), let pid = f.pid else { throw Failure("can't read layout.json") }
                for id in ids {
                    guard let e = saved.entry(id, pid: pid) else { throw Failure("layout.json has no entry for the hidden window [\(id)]") }
                    try t.expect(e["away"] as? Bool == true, "layout.json should mark the hidden window [\(id)] \"away\": true")
                }
                try await t.launchExpanse()
            }
            // ⌘-Tab to the app: its windows come back.
            f.unhide()
            f.activate()
            do {
                try await t.until("both windows back at their spots", timeout: 10) {
                    let s = try await t.state()
                    return zip(ids, spots).allSatisfy { id, spot in s.window(id).map { persistNear($0.canvas, spot, 2) } ?? false }
                }
            } catch {
                let s = try await t.state()
                let now = ids.map { id in s.window(id).map { NSStringFromRect($0.canvas) } ?? "not on the canvas" }
                throw Failure("the hidden app's windows should be back at \(spots.map(NSStringFromRect)), but are at \(now)")
            }
        },
        Case("PERSIST-22", "Restore Layout puts windows back where a snapshot had them") { t in
            let keep = persistKeepSnapshots()
            defer { keep() }
            let ws = try await t.row(["PERSIST-22 A", "PERSIST-22 B", "PERSIST-22 C"], size: CGSize(width: 500, height: 340), origin: persistOrigin)
            let file = try await t.persistTakeSnapshot()
            guard let snap = PersistLayout(file) else { throw Failure("can't read the snapshot \(file.lastPathComponent)") }
            let spots = try ws.map { w -> CGRect in
                guard let r = snap.spot(w.id, pid: getpid()) else { throw Failure("the snapshot has no entry for \(w.title)") }
                return r
            }
            // Since then: two windows moved, one made smaller (its chosen size too).
            t.place(ws[0], at: CGPoint(x: persistOrigin.x, y: persistOrigin.y + 900))
            t.place(ws[1], at: CGPoint(x: persistOrigin.x + 2500, y: persistOrigin.y + 300))
            if let r = ws[2].real { ws[2].setFrame(CGRect(origin: r.origin, size: CGSize(width: 380, height: 260))) }
            t.link("prefer", ["id": ws[2].id, "w": 380, "h": 260])
            try await t.until("C smaller", timeout: 5) {
                guard let c = try await t.state().window(ws[2].id)?.canvas else { return false }
                return abs(c.width - 380) <= 2
            }
            let s0 = try await t.settle()
            try t.expect(!s0.active, "should be at 100% before restoring")
            let mark = t.log.mark()
            t.link("layout")
            let line = try await t.expectLog("restored a layout:", since: mark, timeout: 10)
            if let counts = persistRestoredCount(line) { try t.expect(counts.0 >= ws.count, "the restore should count all three windows: \(line)") }
            try await t.until("every window back at its snapshot spot and size", timeout: 8) {
                let s = try await t.settle()
                return zip(ws, spots).allSatisfy { w, spot in s.window(w.id).map { persistNear($0.canvas, spot, 2) } ?? false }
            }
            let s = try await t.settle()
            try t.expect(s.active, "restoring should open the canvas zoomed out")
            for w in ws {
                guard let c = s.window(w.id)?.canvas else { continue }
                try t.expect(s.visibleCanvas.insetBy(dx: -1, dy: -1).contains(c), "zoomed out to fit, \(w.title) should be in view")
            }
        },
        Case("PERSIST-24", "A restore can be undone") { t in
            let keep = persistKeepSnapshots()
            defer { keep() }
            let ws = try await t.row(["PERSIST-24 A", "PERSIST-24 B"], size: CGSize(width: 500, height: 340), origin: persistOrigin)
            let sFile = try await t.persistTakeSnapshot()
            guard let snap = PersistLayout(sFile) else { throw Failure("can't read the snapshot") }
            // Layout L: both moved.
            t.place(ws[0], at: CGPoint(x: persistOrigin.x, y: persistOrigin.y + 1000))
            t.place(ws[1], at: CGPoint(x: persistOrigin.x + 1800, y: persistOrigin.y + 1000))
            let l = try await t.settle()
            @MainActor func spots(_ state: ExpanseState) throws -> [CGRect] {
                try ws.map { w in
                    guard let c = state.window(w.id)?.canvas else { throw Failure("\(w.title) isn't on the canvas") }
                    return c
                }
            }
            let inL = try spots(l)
            let inS = try ws.map { w -> CGRect in
                guard let r = snap.spot(w.id, pid: getpid()) else { throw Failure("the snapshot has no entry for \(w.title)") }
                return r
            }
            // (Snapshots are named for the second they're taken.)
            try await t.pause(1.1)
            // Step 1: restore S.
            var mark = t.log.mark()
            t.link("layout")
            try await t.expectLog("restored a layout:", since: mark, timeout: 10)
            try await t.until("the windows at S's spots", timeout: 8) {
                let now = try spots(await t.settle())
                return zip(now, inS).allSatisfy { persistNear($0, $1, 2) }
            }
            // Step 2: the newest snapshot now is L, taken just before.
            guard let newest = persistSnapshots().first, newest != sFile, let undo = PersistLayout(newest) else {
                throw Failure("restoring should first take a snapshot of the layout it replaces")
            }
            for (w, spot) in zip(ws, inL) {
                guard let e = undo.spot(w.id, pid: getpid()) else { throw Failure("the new snapshot has no entry for \(w.title)") }
                try t.expectNear(e.origin, spot.origin, within: 1, "\(w.title) in the snapshot taken before the restore")
            }
            // Step 3: restoring that one puts L back.
            try await t.pause(1.1)
            mark = t.log.mark()
            t.link("layout")
            try await t.expectLog("restored a layout:", since: mark, timeout: 10)
            try await t.until("the windows back as in L", timeout: 8) {
                let now = try spots(await t.settle())
                return zip(now, inL).allSatisfy { persistNear($0, $1, 2) }
            }
        },
        Case("PERSIST-25", "Restore Layout does nothing while Expanse is paused") { t in
            let keep = persistKeepSnapshots()
            defer { keep() }
            let ws = try await t.row(["PERSIST-25 A", "PERSIST-25 B"], size: CGSize(width: 500, height: 340), origin: persistOrigin)
            _ = try await t.persistTakeSnapshot()
            // Moved since, so a restore would show.
            t.place(ws[0], at: CGPoint(x: persistOrigin.x, y: persistOrigin.y + 900))
            try await t.settle()
            t.link("pause")
            try await t.untilPaused("paused")
            try await t.pause(0.5)
            let frames = ws.map(\.real)
            let mark = t.log.mark()
            // The panel's thumbnails: greyed out, and pressing one does nothing.
            if let panel = try await t.persistPanel(pressingThumbnail: true) {
                let thumbnails = panel.nodes.filter { $0.help.hasPrefix("Put the windows back where they were") }
                try t.expect(thumbnails.allSatisfy { !$0.enabled }, "paused, the Earlier layouts thumbnails should be greyed out (disabled)")
            }
            t.link("layout", ["snapshot": 0])
            try await t.noLog("restored a layout:", since: mark, within: 2.5)
            let s = try await t.state()
            try t.expect(s.paused, "a restore shouldn't resume Expanse")
            for (w, f) in zip(ws, frames) { try t.expectNear(w.real ?? .zero, f ?? .zero, within: 1, "\(w.title) after the restore while paused") }
        },
        Case("PERSIST-26", "Restoring a snapshot taken on another screen fits it to this one") { t in
            let keep = persistKeepSnapshots()
            defer { keep() }
            let small = persistSmallScreen(t)
            let (a, b, c) = try await t.persistBigLayout("PERSIST-26", widerThan: small)
            let file = try await t.persistTakeSnapshot()
            guard let snap = PersistLayout(file), let sa = snap.spot(a.id, pid: getpid()), let sb = snap.spot(b.id, pid: getpid()) else {
                throw Failure("the snapshot has no entries for the windows")
            }
            // Rearranged since, and now on a smaller screen.
            t.place(b, at: CGPoint(x: persistOrigin.x, y: persistOrigin.y + 3000))
            t.place(c, at: CGPoint(x: persistOrigin.x + 3000, y: persistOrigin.y))
            try await t.persistScreen(small)
            let mark = t.log.mark()
            t.link("layout")
            try await t.expectLog("restored a layout:", since: mark, timeout: 10)
            try await t.pause(1)
            let s = try await t.settle()
            try t.persistExpectFitted(s, a: a, b: b, c: c, chosenA: sa.size)
            guard let fa = s.window(a.id)?.canvas, let fb = s.window(b.id)?.canvas else { throw Failure("a window left the canvas") }
            try t.expect(fa.width < sa.width - 1, "the big window should be smaller than on the big screen (\(fa.size))")
            try t.expect(fb.minX < sb.minX - 1, "B should have moved in with the tightened layout, not stayed at the big screen's spot (\(fb.origin))")
            try await t.persistScreen(nil)
        },
        Case("PERSIST-27", "Relaunching Expanse on the same screen moves nothing") { t in
            let ws = try await t.row(["PERSIST-27 A", "PERSIST-27 B", "PERSIST-27 C"], size: CGSize(width: 480, height: 320), origin: persistOrigin)
            // And one put under A and B by hand.
            let d = try await t.window("PERSIST-27 D", CGRect(x: 300, y: 300, width: 400, height: 280))
            t.place(d, at: CGPoint(x: persistOrigin.x + 260, y: persistOrigin.y + 360))
            let all = ws + [d]
            t.link("focus", ["id": ws[1].id])
            try await t.settle()
            try await t.pause(1.5)
            let before = try await t.settle()
            let mark = t.log.mark()
            try await t.persistRelaunchingAfter { try await t.relaunchExpanse() }
            try await t.until("every window back on the canvas", timeout: 15) {
                let s = try await t.state()
                return all.allSatisfy { s.window($0.id) != nil }
            }
            let fitted = try await t.expectLog("layout fitted:", since: mark, timeout: 10)
            try t.expect(fitted.hasPrefix("layout fitted: 0 of "), "relaunching on the same screen should move nothing: “\(fitted)”")
            try await t.pause(1)
            let after = try await t.settle()
            for w in all {
                guard let a = before.window(w.id)?.canvas, let b = after.window(w.id)?.canvas else { throw Failure("\(w.title) isn't on the canvas") }
                try t.expectNear(b, a, within: 1, "\(w.title) after relaunching")
            }
            try t.expectNear(after.camera, before.camera, within: 1, "the view after relaunching")
            do {
                try await t.until("layout.json to name the screen it was fitted to", timeout: 6) {
                    PersistLayout(persistLayoutFile)?.fitted.map { persistNear($0, after.viewport.size, 0.5) } ?? false
                }
            } catch {
                throw Failure("layout.json's fittedWidth and fittedHeight should be \(after.viewport.size) (they're \(PersistLayout(persistLayoutFile)?.fitted.map { "\($0)" } ?? "missing"))")
            }
        },
        Case("PERSIST-30", "Restore Layout puts windows exactly where the snapshot had them") { t in
            let keep = persistKeepSnapshots()
            defer { keep() }
            let size = CGSize(width: 480, height: 320)
            var ws: [TestWindow] = []
            for i in 0..<4 { ws.append(try await t.window("PERSIST-30 \(i + 1)", CGRect(x: 120 + 50 * CGFloat(i), y: 140 + 40 * CGFloat(i), width: size.width, height: size.height))) }
            let pitch = try await t.canvasFrame(ws[0]).size
            for (i, w) in ws.enumerated() {
                t.place(w, at: CGPoint(x: persistOrigin.x + CGFloat(i % 2) * (pitch.width + 20), y: persistOrigin.y + CGFloat(i / 2) * (pitch.height + 20)))
            }
            try await t.settle()
            let file = try await t.persistTakeSnapshot()
            guard let snap = PersistLayout(file) else { throw Failure("can't read the snapshot") }
            let spots = try ws.map { w -> CGPoint in
                guard let r = snap.spot(w.id, pid: getpid()) else { throw Failure("the snapshot has no entry for \(w.title)") }
                return r.origin
            }
            // Dragged to new places since.
            t.place(ws[0], at: CGPoint(x: persistOrigin.x + 2000, y: persistOrigin.y))
            t.place(ws[2], at: CGPoint(x: persistOrigin.x - 1500, y: persistOrigin.y + 300))
            t.place(ws[3], at: CGPoint(x: persistOrigin.x + 300, y: persistOrigin.y + 1500))
            try await t.settle()
            try await t.pause(1.1)
            let mark = t.log.mark()
            t.link("layout")
            let restored = try await t.persistLogIndex("restored a layout:", since: mark, timeout: 10)
            try await t.noLog("re-homed", since: restored, within: 2)
            let s = try await t.settle()
            for (w, spot) in zip(ws, spots) {
                guard let c = s.window(w.id)?.canvas else { throw Failure("\(w.title) isn't on the canvas") }
                try t.expectNear(c.origin, spot, within: 1, "\(w.title) after the restore (the snapshot's x, y)")
                try t.expect(s.visibleCanvas.insetBy(dx: -1, dy: -1).contains(c), "the view should zoom out to show \(w.title)")
            }
            try t.expect(s.active, "the view should zoom out to show the restored layout")
            guard let newest = persistSnapshots().first, newest != file,
                  let undo = PersistLayout(newest), let moved = undo.spot(ws[0].id, pid: getpid()) else {
                throw Failure("the layout the restore replaced should be a snapshot itself")
            }
            try t.expectNear(moved.origin, CGPoint(x: persistOrigin.x + 2000, y: persistOrigin.y), within: 1, "the replaced layout's snapshot")
        },
        Case("PERSIST-31", "Restore Layout on another screen keeps the snapshot's home spots") { t in
            let keep = persistKeepSnapshots()
            defer { keep() }
            let small = persistSmallScreen(t)
            let (a, b, c) = try await t.persistBigLayout("PERSIST-31", widerThan: small)
            let file = try await t.persistTakeSnapshot()
            guard let snap = PersistLayout(file) else { throw Failure("can't read the snapshot") }
            let spots = try [a, b, c].map { w -> CGRect in
                guard let r = snap.spot(w.id, pid: getpid()) else { throw Failure("the snapshot has no entry for \(w.title)") }
                return r
            }
            // Moved since; then the big display goes (expanse://screen stands in for unplugging it).
            t.place(b, at: CGPoint(x: persistOrigin.x + 200, y: persistOrigin.y + 2500))
            t.place(c, at: CGPoint(x: persistOrigin.x + 2600, y: persistOrigin.y + 200))
            try await t.persistScreen(small)
            // Step 2: restored on the small screen, from the snapshot's home spots, tightened.
            let mark = t.log.mark()
            t.link("layout")
            try await t.expectLog("restored a layout:", since: mark, timeout: 10)
            try await t.pause(1)
            let s = try await t.settle()
            try t.persistExpectFitted(s, a: a, b: b, c: c, chosenA: spots[0].size)
            // Step 3: back on the big display, exactly the snapshot.
            t.link("exit")
            try await t.settle()
            try await t.persistScreen(nil)
            let back = try await t.settle()
            for (w, spot) in zip([a, b, c], spots) {
                guard let f = back.window(w.id)?.canvas else { throw Failure("\(w.title) isn't on the canvas") }
                try t.expectNear(f, spot, within: 1, "\(w.title) back on the big screen (the snapshot's spot and size)")
            }
        },
        Case("PERSIST-36", "Logging out puts windows back in the macOS layout first") { t in
            let (a, aAt) = try await t.persistWindow("PERSIST-36 Parked", CGRect(x: 140, y: 160, width: 520, height: 360))
            let (b, bAt) = try await t.persistWindow("PERSIST-36 Moved", CGRect(x: 280, y: 240, width: 480, height: 320))
            t.place(a, at: persistOrigin)
            let vis = try await t.settle().visibleCanvas
            t.place(b, at: CGPoint(x: vis.minX + 60, y: vis.minY + 60))
            try await t.until("A parked, B moved", timeout: 8) {
                let s = try await t.state()
                return s.window(a.id)?.parked == true && b.real.map { !persistNear($0, bAt, 20) } ?? false
            }
            let before = try await t.settle()
            guard let aSpot = before.window(a.id)?.canvas, let bSpot = before.window(b.id)?.canvas else { throw Failure("a window isn't on the canvas") }
            let mark = t.log.mark()
            t.link("poweroff")
            let notice = try await t.persistLogIndex("logging out or restarting: windows back to the macOS layout, layout kept for next time", since: mark)
            try await t.persistExpectLine("paused", since: notice)
            try await t.until("paused at once", timeout: 3) { try await t.state().paused }
            try await t.persistExpectBack(a.id, "the parked window", at: aAt)
            try await t.persistExpectBack(b.id, "the moved window", at: bAt)
            // The layout as it was, kept for next time.
            guard let saved = PersistLayout(persistLayoutFile) else { throw Failure("can't read layout.json") }
            try t.expect(saved.cleanExit == true, "layout.json should be saved with cleanExit true (windows put back)")
            for (w, spot) in [(a, aSpot), (b, bSpot)] {
                guard let e = saved.spot(w.id, pid: getpid()) else { throw Failure("layout.json has no entry for \(w.title)") }
                try t.expectNear(e.origin, spot.origin, within: 1, "\(w.title)'s spot in layout.json")
            }
            if let panel = try await t.persistPanel() {
                try t.expect(panel.texts.contains("Paused \u{B7} windows back in the macOS layout"),
                             "the panel should say “Paused · windows back in the macOS layout”")
            }
            let modified = persistModified(persistLayoutFile)
            // No further saves while paused, whatever happens to windows; and a second logout
            // notice does nothing.
            b.setFrame(bAt.offsetBy(dx: 80, dy: 50))
            let mark2 = t.log.mark()
            t.link("poweroff")
            try await t.noLog("logging out or restarting", since: mark2, within: 2.5)
            let s = try await t.state()
            try t.expect(s.paused, "Expanse should still be paused")
            try t.expect(persistModified(persistLayoutFile) == modified, "layout.json was saved again while paused")
            t.link("resume")
            try await t.until("resumed") { try await !t.state().paused }
        },
        Case("PERSIST-38", "A cancelled logout resumes Expanse after 3 minutes") { t in
            // The timer is three minutes on the running app, and this waits it out twice.
            let needed: TimeInterval = 420
            guard runnerTimeout >= needed else {
                throw Skip("waits out the 3-minute timer twice (about 6½ minutes): run it with --timeout \(Int(needed))")
            }
            let a = try await t.window("PERSIST-38 A")
            t.place(a, at: persistOrigin)
            try await t.settle()
            let spot = try await t.canvasFrame(a)
            // Steps 1-2: a logout that doesn't happen. Three minutes on, Expanse resumes by itself.
            var mark = t.log.mark()
            t.link("poweroff")
            let began = try await t.persistLogIndex("logging out or restarting", since: mark)
            let start = Date()
            try await t.untilPaused("paused")
            let notice = try await t.persistLogIndex("still running: the logout was cancelled, so resuming", since: began, timeout: 200)
            let waited = Date().timeIntervalSince(start)
            try t.expect(waited > 170, "Expanse resumed by itself after \(Int(waited))s, not 3 minutes")
            try await t.persistExpectLine("resumed", since: notice)
            try await t.until("resumed, A back at its spot", timeout: 10) {
                let s = try await t.state()
                return !s.paused && s.window(a.id).map { persistNear($0.canvas, spot, 1) } == true
            }
            // Step 3: resumed by you, then paused by you, before the 3 minutes are up: that pause stays.
            mark = t.log.mark()
            t.link("poweroff")
            _ = try await t.persistLogIndex("logging out or restarting", since: mark)
            let again = Date()
            try await t.untilPaused("paused")
            try await t.pause(5)
            t.link("resume")
            try await t.until("resumed by you") { try await !t.state().paused }
            try await t.pause(2)
            t.link("pause")
            try await t.untilPaused("paused by you")
            try await t.noLog("still running: the logout was cancelled", since: mark, within: max(185 - Date().timeIntervalSince(again), 1))
            let paused = try await t.state().paused
            try t.expect(paused, "the pause you made should stay after the 3 minutes")
            t.link("resume")
        },
        Case("PERSIST-39", "A real restart brings the layout back", .guided) { t in
            // Two runs: one before restarting (it notes where every window is), one after.
            let record = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/ExpanseTests/PERSIST-39 before restart.json")
            let mine = NSRunningApplication.current.localizedName ?? "Expanse Tests"
            if let before = persistRestartRecord(record), before.taken < persistBootTime() {
                defer { try? FileManager.default.removeItem(at: record) }
                var result = (matched: 0, missing: [String]())
                do {
                    // Apps macOS reopens can take a while.
                    try await t.until("the windows from before the restart back at their spots", timeout: 90) {
                        let now = try await t.state()
                        result = persistRestartCompare(before.windows, now)
                        return result.missing.isEmpty && result.matched > 0
                    }
                } catch {
                    if result.matched == 0 && result.missing.isEmpty { throw Failure("no app with windows before the restart has any on the canvas now") }
                    throw Failure("after the restart, not every window is back at its spot: \(result.missing.joined(separator: "; "))")
                }
                return
            }
            guard CommandLine.arguments.contains("--only") else {
                throw Skip("needs a real restart: run it on its own (--only PERSIST-39), once before restarting and once after")
            }
            try await t.ask("Arrange several apps' windows on the canvas (not Expanse Tests'), some of them out of view. Then press Done.")
            let s = try await t.settle()
            let theirs = s.windows.filter { $0.app != mine }
            guard Set(theirs.map(\.app)).count >= 2, theirs.contains(where: \.parked) else {
                throw Skip("needs windows of two or more apps on the canvas, some out of view")
            }
            try persistWriteRestartRecord(record, theirs.map { ($0.app, $0.canvas.origin) })
            try await t.ask("Restart the Mac now (Apple menu › Restart…, with “Reopen windows when logging back in” ticked). After logging in, run Expanse Tests again with --only PERSIST-39.")
            throw Skip("waiting for the restart: run --only PERSIST-39 again after logging back in")
        },
    ]
}

// MARK: Helpers

/// Out on the canvas, away from your windows, so a case's windows are only near each other
/// (not so far that zooming out to fit everything would need more than Expanse's smallest zoom).
@MainActor private var persistOrigin: CGPoint { clearSpot }

private let persistFolder = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Expanse", isDirectory: true)
private let persistLayoutFile = persistFolder.appendingPathComponent("layout.json")
private let persistSnapshotsFolder = persistFolder.appendingPathComponent("Snapshots", isDirectory: true)

private func persistNear(_ a: CGRect, _ b: CGRect, _ d: CGFloat) -> Bool {
    max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height)) <= d
}

private func persistNear(_ a: CGSize, _ b: CGSize, _ d: CGFloat) -> Bool {
    abs(a.width - b.width) <= d && abs(a.height - b.height) <= d
}

/// A screen 70% the size of this one, for expanse://screen (a laptop's, with a big display unplugged).
@MainActor private func persistSmallScreen(_ t: Ctx) -> CGSize {
    CGSize(width: (t.screen.width * 0.7).rounded(), height: (t.screen.height * 0.7).rounded())
}

/// "restored a layout: N of M windows" → (N, M).
private func persistRestoredCount(_ line: String) -> (Int, Int)? {
    guard let m = line.firstMatch(of: #/restored a layout: (\d+) of (\d+) windows/#), let n = Int(m.1), let of = Int(m.2) else { return nil }
    return (n, of)
}

private func persistModified(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}

/// A layout file (layout.json or a snapshot), as it is on disk.
private struct PersistLayout {
    let json: [String: Any]

    init?(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        self.json = json
    }

    var windows: [[String: Any]] { json["windows"] as? [[String: Any]] ?? [] }
    var cleanExit: Bool? { json["cleanExit"] as? Bool }
    var fitted: CGSize? {
        guard let w = json["fittedWidth"] as? Double, let h = json["fittedHeight"] as? Double else { return nil }
        return CGSize(width: w, height: h)
    }

    /// The entry for a window: the same window ID in the same app process.
    func entry(_ id: CGWindowID, pid: pid_t) -> [String: Any]? {
        windows.first { ($0["id"] as? Int) == Int(id) && ($0["pid"] as? Int) == Int(pid) }
    }

    /// Its canvas spot and size.
    func spot(_ id: CGWindowID, pid: pid_t) -> CGRect? {
        guard let e = entry(id, pid: pid), let x = e["x"] as? Double, let y = e["y"] as? Double else { return nil }
        return CGRect(x: x, y: y, width: e["w"] as? Double ?? 0, height: e["h"] as? Double ?? 0)
    }
}

/// Snapshot files, newest first (each named for the second it was taken).
private func persistSnapshots() -> [URL] {
    func time(_ url: URL) -> TimeInterval? { TimeInterval(url.deletingPathExtension().lastPathComponent) }
    return ((try? FileManager.default.contentsOfDirectory(at: persistSnapshotsFolder, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension == "json" && time($0) != nil }
        .sorted { (time($0) ?? 0) > (time($1) ?? 0) }
}

/// Your earlier layouts (the Snapshots folder) as they are now: the closure puts them back, and
/// takes away the case's. Only the newest three are kept, so a case's snapshots would push yours out.
private func persistKeepSnapshots() -> () -> Void {
    let fm = FileManager.default
    let yours = persistSnapshots().compactMap { url in (try? Data(contentsOf: url)).map { (url.lastPathComponent, $0) } }
    return {
        for url in persistSnapshots() { try? fm.removeItem(at: url) }
        for (name, data) in yours { try? data.write(to: persistSnapshotsFolder.appendingPathComponent(name)) }
    }
}

/// A corner of the main display to rest the pointer in for Expanse's hot corner: one its setting
/// covers, and that macOS's own hot corners leave alone (no Lock Screen, Mission Control or Quick
/// Note going off mid-run). Nil if there's none.
@MainActor private func persistSafeHotCorner(_ t: Ctx) -> CGPoint? {
    let setting = expanseDefault("hotCorner") as? String ?? "all"
    guard setting != "off" else { return nil }
    let w = t.screen.width, h = t.screen.height
    let corners: [(name: String, dock: String, at: CGPoint)] = [
        ("topLeft", "tl", CGPoint(x: 1, y: 1)), ("topRight", "tr", CGPoint(x: w - 2, y: 1)),
        ("bottomLeft", "bl", CGPoint(x: 1, y: h - 2)), ("bottomRight", "br", CGPoint(x: w - 2, y: h - 2)),
    ]
    return corners.first { c in
        let action = CFPreferencesCopyAppValue("wvous-\(c.dock)-corner" as CFString, "com.apple.dock" as CFString) as? Int ?? 0
        return (setting == "all" || setting == c.name) && action <= 1
    }?.at
}

/// Expanse's backdrop (a window of Expanse's the size of the screen) is on screen.
@MainActor private extension Ctx {
    func persistBackdropShown() -> Bool {
        guard let pid = expanse?.processIdentifier else { return false }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid, let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b) else { return false }
            return r.width >= screen.width * 0.8 && r.height >= screen.height * 0.5
        }
    }
}

// MARK: Windows

@MainActor private extension Ctx {
    /// A window of Expanse Tests at `frame`, and where macOS put it before Expanse took it on: its
    /// place in the macOS layout, which quitting and pausing put back.
    func persistWindow(_ title: String, _ frame: CGRect) async throws -> (TestWindow, CGRect) {
        let w = try await window(title, frame, managed: false)
        try await until("Expanse to take on “\(title)”", timeout: 10) { try await self.state().window(w.id) != nil }
        return (w, w.opened)
    }

    /// A fixture app with one window, that window, and where macOS put it before Expanse took it on.
    func persistFixture(_ name: String) async throws -> (Fixture, CGWindowID, CGRect) {
        let f = try await fixture(name, windows: 1, size: CGSize(width: 520, height: 360))
        guard let id = f.windows.first, let original = f.opened[id] else { throw Failure("the fixture \(name) has no window") }
        try await until("Expanse to take on \(name)'s window", timeout: 10) { try await self.state().window(id) != nil }
        return (f, id, original)
    }

    /// expanse://place for any window by ID (a fixture's, say).
    func persistPlace(_ id: CGWindowID, at p: CGPoint) {
        link("place", ["id": id, "x": Int(p.x), "y": Int(p.y), "commit": 1])
    }

    /// Fails unless the window server has the window at `frame` (within 3pt): where macOS had it.
    func persistExpectBack(_ id: CGWindowID, _ name: String, at frame: CGRect, timeout: TimeInterval = 5) async throws {
        do {
            try await until("\(name) back where macOS had it", timeout: timeout) { realFrame(id).map { persistNear($0, frame, 3) } ?? false }
        } catch {
            let now = realFrame(id)
            let corner = now.map { $0.minX > screen.maxX - 200 && $0.minY > screen.maxY - 260 } ?? false
            throw Failure("\(name) should be back at \(NSStringFromRect(frame)), where macOS had it, but it's "
                          + (now.map { NSStringFromRect($0) + (corner ? ", in the parking corner" : "") } ?? "gone"))
        }
    }

    /// Every window is where the canvas has it: on screen at its spot and size for the camera, or
    /// parked in the bottom-right corner.
    func persistExpectInPlace(_ ws: [TestWindow], timeout: TimeInterval = 5) async throws {
        var problem = ""
        do {
            try await until("every window where the canvas has it", timeout: timeout) {
                let s = try await self.state()
                problem = ""
                for w in ws {
                    guard let c = s.window(w.id) else { problem = "\(w.title) isn't on the canvas"; break }
                    guard let real = w.real else { problem = "\(w.title) has no window"; break }
                    if c.parked {
                        if real.minX < s.viewport.maxX - 200 || real.minY < s.viewport.maxY - 260 {
                            problem = "\(w.title) is parked, but at \(NSStringFromRect(real)), not in the corner"; break
                        }
                    } else {
                        let p = s.screenPoint(c.canvas.origin)
                        if hypot(real.minX - p.x, real.minY - p.y) > 2 || !persistNear(real.size, c.canvas.size, 2) {
                            problem = "\(w.title) is at \(NSStringFromRect(real)), but the canvas has it at \(NSStringFromRect(CGRect(origin: p, size: c.canvas.size)))"; break
                        }
                    }
                }
                return problem.isEmpty
            }
        } catch {
            throw Failure(problem.isEmpty ? "\(error)" : problem)
        }
    }

    /// You move `w` yourself: a drag by its title bar with the pointer, or (without Accessibility
    /// for Expanse Tests) a move by its app. Where it ended up.
    func persistMoveYourself(_ w: TestWindow) async throws -> CGRect {
        guard let r = w.real else { throw Failure("\(w.title) has no window") }
        if Input.allowed {
            w.focus()
            try await pause(0.3)
            let grab = CGPoint(x: r.midX, y: r.minY + 12)
            await Input.dragAsync(from: grab, to: CGPoint(x: grab.x + 120, y: grab.y + 70))
        } else {
            w.setFrame(r.offsetBy(dx: 120, dy: 70))
        }
        try await pause(0.5)
        guard let now = w.real, !persistNear(now, r, 20) else { throw Failure("\(w.title) didn't move") }
        return now
    }

    /// A big window (wider than a `small` screen, though not this one), B to its right and C under
    /// it, the standard 20pt apart, far out on the canvas.
    func persistBigLayout(_ prefix: String, widerThan small: CGSize) async throws -> (TestWindow, TestWindow, TestWindow) {
        let bigWidth = min(screen.width - 120, small.width + 240)
        guard bigWidth > small.width + 60 else { throw Skip("this display is too small for a window wider than a smaller screen") }
        let a = try await window("\(prefix) Big", CGRect(x: 40, y: 90, width: bigWidth, height: 300))
        let b = try await window("\(prefix) B", CGRect(x: 200, y: 200, width: 420, height: 280))
        let c = try await window("\(prefix) C", CGRect(x: 260, y: 260, width: 420, height: 280))
        place(a, at: persistOrigin)
        try await settle()
        let fa = try await canvasFrame(a)
        place(b, at: CGPoint(x: fa.maxX + 20, y: fa.minY))
        place(c, at: CGPoint(x: fa.minX, y: fa.maxY + 20))
        try await settle()
        try await pause(1.2)
        return (a, b, c)
    }

    /// A, B and C fitted to the screen Expanse has now: A (chosen `chosenA`) capped at the screen
    /// less 16pt each side, B still 20pt right of A and C 20pt under it, nothing overlapping.
    func persistExpectFitted(_ s: ExpanseState, a: TestWindow, b: TestWindow, c: TestWindow, chosenA: CGSize) throws {
        guard let fa = s.window(a.id)?.canvas, let fb = s.window(b.id)?.canvas, let fc = s.window(c.id)?.canvas else {
            throw Failure("a window left the canvas")
        }
        let vp = s.viewport.size
        for (w, f) in [(a, fa), (b, fb), (c, fc)] {
            try expect(f.width <= vp.width + 1 && f.height <= vp.height + 1, "\(w.title) (\(f.size)) should fit the \(vp) screen")
        }
        if chosenA.width > vp.width {
            try expect(abs(fa.width - (vp.width - 32)) <= 1, "the big window should be capped at the screen less 16pt each side (\(vp.width - 32)), not \(fa.width)")
        }
        try expect(abs(fb.minX - fa.maxX - 20) <= 1 && abs(fb.minY - fa.minY) <= 1, "B should stay 20pt right of A, lined up (A \(fa), B \(fb))")
        try expect(abs(fc.minY - fa.maxY - 20) <= 1 && abs(fc.minX - fa.minX) <= 1, "C should stay 20pt under A, lined up (A \(fa), C \(fc))")
        for (x, y) in [(fa, fb), (fa, fc), (fb, fc)] where x.insetBy(dx: 0.5, dy: 0.5).intersects(y) {
            throw Failure("windows overlap after fitting: \(x) and \(y)")
        }
    }
}

// MARK: Expanse

@MainActor private extension Ctx {
    /// Runs `body`, which quits Expanse, and has Expanse running again afterwards, failed or not.
    func persistRelaunchingAfter(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch {
            if expanse == nil { try? await launchExpanse() }
            throw error
        }
        if expanse == nil { try await launchExpanse() }
    }

    /// expanse://screen (a size, or nil for the display's own), and the re-layout that follows done.
    func persistScreen(_ size: CGSize?) async throws {
        let mark = log.mark()
        if let size { link("screen", ["w": Int(size.width), "h": Int(size.height)]) } else { link("screen") }
        try await expectLog("layout fitted:", since: mark, timeout: 10)
        try await pause(0.5)
        try await settle(timeout: 10)
    }

    /// expanse://snapshot (Take snapshot in the panel), and the file it made.
    func persistTakeSnapshot() async throws -> URL {
        // Named for the second: one taken in the same second as another would replace it.
        try await pause(1.1)
        let before = persistSnapshots().first
        link("snapshot")
        var made: URL?
        try await until("a new snapshot file", timeout: 8) {
            made = persistSnapshots().first
            return made != nil && made != before
        }
        return made!
    }

    /// Where in the log the first line since `mark` containing `text` is (a mark to look on from).
    func persistLogIndex(_ text: String, since mark: Int, timeout: TimeInterval = 8) async throws -> Int {
        guard await log.wait(since: mark, timeout: timeout, { $0.contains(text) }) != nil,
              let i = log.lines(since: mark).firstIndex(where: { $0.contains(text) }) else {
            throw Failure("no log line containing “\(text)”")
        }
        return mark + i
    }

    /// The same for a line that's exactly `line` ("paused", "resumed": dump lines contain the words too).
    @discardableResult
    func persistExpectLine(_ line: String, since mark: Int, timeout: TimeInterval = 8) async throws -> Int {
        guard await log.wait(since: mark, timeout: timeout, { $0 == line }) != nil,
              let i = log.lines(since: mark).firstIndex(of: line) else {
            throw Failure("no “\(line)” line in the log")
        }
        return mark + i
    }
}

// MARK: The menu bar panel

/// One element of Expanse's menu bar panel, as Accessibility reads it.
private struct PersistAXNode: Sendable {
    let role: String
    let strings: [String]
    let help: String
    let enabled: Bool
}

private struct PersistPanel {
    let nodes: [PersistAXNode]
    var texts: [String] { nodes.flatMap(\.strings) }
}

/// Every element in Expanse's windows (the panel's, when it's open), read through Accessibility.
/// With `press`, presses the first element it accepts. Off the main thread, so Expanse Tests can
/// still answer Expanse about its own windows meanwhile.
private func persistAXNodes(pid: pid_t, press: (@Sendable (PersistAXNode) -> Bool)? = nil) async -> [PersistAXNode] {
    await Task.detached {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 2)
        func attribute(_ e: AXUIElement, _ name: String) -> AnyObject? {
            var value: AnyObject?
            return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
        }
        var nodes: [PersistAXNode] = []
        var pressed = false
        // Its windows (the panel is one), and its children, in case a panel isn't listed as a window.
        var queue = ((attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []) + ((attribute(app, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        while let e = queue.popLast(), nodes.count < 3000 {
            let node = PersistAXNode(role: attribute(e, kAXRoleAttribute) as? String ?? "",
                                     strings: [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].compactMap { attribute(e, $0) as? String },
                                     help: attribute(e, kAXHelpAttribute) as? String ?? "",
                                     enabled: attribute(e, kAXEnabledAttribute) as? Bool ?? true)
            nodes.append(node)
            if !pressed, let press, press(node) {
                pressed = true
                AXUIElementPerformAction(e, kAXPressAction as CFString)
            }
            queue.append(contentsOf: (attribute(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [])
        }
        return nodes
    }.value
}

@MainActor private extension Ctx {
    /// Opens Expanse's menu bar panel (expanse://menu), reads it through Accessibility, and closes it
    /// (Esc). With `pressingThumbnail`, presses the first Earlier layouts thumbnail while it's open.
    /// Nil if Expanse Tests doesn't have Accessibility.
    func persistPanel(pressingThumbnail: Bool = false) async throws -> PersistPanel? {
        guard Input.allowed, let pid = expanse?.processIdentifier else { return nil }
        link("menu")
        var nodes: [PersistAXNode] = []
        do {
            try await until("Expanse's menu bar panel to open", timeout: 5) {
                nodes = await persistAXNodes(pid: pid)
                return nodes.contains { $0.strings.contains("Earlier layouts") }
            }
        } catch {
            throw Failure("couldn't read Expanse's menu bar panel through Accessibility (no “Earlier layouts” in it)")
        }
        if pressingThumbnail {
            _ = await persistAXNodes(pid: pid) { $0.help.hasPrefix("Put the windows back where they were") }
            try await pause(1)
        }
        Input.key(.escape)
        try await pause(0.3)
        return PersistPanel(nodes: nodes)
    }
}

// MARK: A real restart (PERSIST-39)

private struct PersistRestartRecord {
    let taken: Date
    let windows: [(app: String, spot: CGPoint)]
}

private func persistRestartRecord(_ url: URL) -> PersistRestartRecord? {
    guard let data = try? Data(contentsOf: url), let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let taken = json["taken"] as? Double, let windows = json["windows"] as? [[String: Any]] else { return nil }
    return PersistRestartRecord(taken: Date(timeIntervalSince1970: taken), windows: windows.compactMap { w -> (app: String, spot: CGPoint)? in
        guard let app = w["app"] as? String, let x = w["x"] as? Double, let y = w["y"] as? Double else { return nil }
        return (app, CGPoint(x: x, y: y))
    })
}

private func persistWriteRestartRecord(_ url: URL, _ windows: [(String, CGPoint)]) throws {
    let json: [String: Any] = ["taken": Date().timeIntervalSince1970,
                               "windows": windows.map { ["app": $0.0, "x": Double($0.1.x), "y": Double($0.1.y)] }]
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted).write(to: url)
}

/// When the Mac last started up.
private func persistBootTime() -> Date {
    var tv = timeval()
    var size = MemoryLayout<timeval>.stride
    var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
    guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return .distantPast }
    return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
}

/// For each app that had windows before the restart and has some on the canvas now: as many of
/// them as both have should be at spots it had (window IDs change, so by app). Apps that didn't
/// reopen don't count. The windows matched, and the apps short of that.
private func persistRestartCompare(_ before: [(app: String, spot: CGPoint)], _ now: ExpanseState) -> (matched: Int, missing: [String]) {
    var matched = 0
    var missing: [String] = []
    for app in Set(before.map(\.app)).sorted() {
        var spots = before.filter { $0.app == app }.map(\.spot)
        let expected = min(spots.count, now.windows.filter { $0.app == app }.count)
        guard expected > 0 else { continue }
        var hits = 0
        for w in now.windows where w.app == app {
            if let i = spots.firstIndex(where: { hypot($0.x - w.canvas.minX, $0.y - w.canvas.minY) <= 2 }) {
                spots.remove(at: i)
                hits += 1
            }
        }
        matched += hits
        if hits < expected { missing.append("\(app): \(hits) of \(expected) windows at their spots") }
    }
    return (matched, missing)
}
