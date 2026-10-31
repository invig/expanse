import AppKit

/// The manual cases in docs/regression/capture-and-performance.md.
///
/// What Expanse captures is read three ways: `capturing=` in expanse://dump (a stream running or
/// starting), its `capturing N of M windows, K more by snapshot` line, and replayd's own log (it
/// runs every ScreenCaptureKit capture on the Mac), which shows each picture, stream start and
/// window scan asked of it. replayd's log counts every app's requests, not only Expanse's.
@MainActor enum CAPTURE {
    static let cases: [Case] = [
        Case("CAPTURE-01", "Zoomed out, windows are live pictures and never move", .look) { t in
            let budget = captureBudget
            // Clocks stand in for the catalogue's playing video: content that keeps changing.
            var ids: [CGWindowID] = []
            for i in 1...3 {
                let w = try await t.window("CAPTURE-01 Clock \(i)", CGRect(x: 100 + 40 * CGFloat(i), y: 140, width: 400, height: 280))
                captureClock(w)
                ids.append(w.id)
            }
            ids += try await t.captureFixtures("CAPTURE-01", windows: 20)
            try await t.captureGrid(ids, columns: 6)
            let replayd = try await captureStartReplayd()
            defer { replayd.stop() }
            let mark = t.log.mark()
            let view = try await t.captureView(ids)
            let streams = min(budget, ids.count)
            try await t.until("\(streams) of the windows in view to stream", timeout: 15) {
                captureStreaming(try await t.state(), ids) >= streams
            }
            for _ in 0..<4 {
                let n = captureStreaming(try await t.state())
                try t.expect(n <= budget, "\(n) windows stream zoomed out (at most \(budget) expected)")
                try await t.pause(0.5)
            }
            guard let line = t.log.lines(since: mark).compactMap(captureCountLine).last else {
                throw Failure("no “capturing N of M windows, K more by snapshot” line")
            }
            try t.expect(line.running <= budget && line.snapshots >= ids.count - line.running,
                         "“capturing \(line.running) of \(line.total) windows, \(line.snapshots) more by snapshot”: at most \(budget) streams, "
                         + "and the other \(ids.count - line.running) windows in view refreshed by snapshot, expected")
            // The rest refresh by one-off pictures, each about every 1.5 s (about ten a second in all).
            let rmark = replayd.mark()
            try await t.pause(9)
            let pictures = replayd.count(.picture, since: rmark)
            let rate = min(Double(ids.count - streams) / 1.5, 10)
            try t.expect(Double(pictures) >= 0.4 * rate * 9 && pictures <= 110,
                         "\(pictures) one-off pictures in 9 s for \(ids.count - streams) windows not streamed (about \(Int(rate * 9)) expected)")
            // Pan and zoom about: no real window moves.
            let before = Dictionary(ids.compactMap { id in realFrame(id).map { (id, $0) } }, uniquingKeysWith: { a, _ in a })
            let moveMark = t.log.mark()
            for i in 0..<6 {
                t.link("pan", ["dx": i % 2 == 0 ? 400 : -400, "dy": i % 2 == 0 ? 150 : -150])
                try await t.pause(0.4)
                t.link("zoom", ["scale": view.scale * (i % 2 == 0 ? 1.4 : 1)])
                try await t.pause(0.6)
            }
            let after = try await t.settle()
            try t.expect(after.active, "the canvas closed while panning and zooming")
            for (id, frame) in before {
                guard let now = realFrame(id) else { throw Failure("window \(id) went away") }
                try t.expectNear(now, frame, within: 1, "window \(id)'s real frame while panning and zooming")
            }
            if let moved = t.log.lines(since: moveMark).first(where: { $0.hasPrefix("move ") }) {
                throw Failure("a real window moved while zoomed out: \(moved)")
            }
            try await t.look("On the canvas, do the clocks in the three “CAPTURE-01 Clock” windows keep ticking "
                             + "(smoothly if streamed, or every second or two)?")
        },
        Case("CAPTURE-04", "At 100%, windows on screen carry no purple capture badge", .look) { t in
            let ws = try await t.row(["CAPTURE-04 A", "CAPTURE-04 B", "CAPTURE-04 C"])
            t.link("focus", ["id": ws[0].id])
            try await t.captureNoStreamsOnScreen("the first glide")
            try await t.ask("Watch the traffic lights of the windows on screen while Expanse Tests hops between windows, "
                            + "zooms out and comes back. Click Done to start.")
            for dir in ["right", "right", "left"] {
                t.link("nav", ["dir": dir])
                try await t.captureNoStreamsOnScreen("a hop \(dir)")
            }
            t.link("toggle")
            try await t.until("the canvas to open", timeout: 8) { try await t.settle().active }
            try await t.pause(1)
            t.link("toggle")
            try await t.captureNoStreamsOnScreen("zooming back in")
            t.link("nav", ["dir": "left"])
            try await t.captureNoStreamsOnScreen("a hop left")
            try await t.look("Once each move had settled, was every window on screen free of macOS's purple capture badge over its traffic lights?")
        },
        Case("CAPTURE-05", "With 50+ windows, zooming, panning and dragging stay smooth", .look) { t in
            let names = expanseDefault("showWindowNames")
            setExpanseDefault("showWindowNames", true)
            defer { setExpanseDefault("showWindowNames", names) }
            let ids = try await t.captureFixtures("CAPTURE-05", windows: 52)
            try await t.captureGrid(ids, columns: 9)
            let view = try await t.captureView(ids)
            try await t.ask("Watch the canvas for about 20 seconds while Expanse Tests zooms, pans and drags its 52 windows. Click Done to start.")
            let mark = t.log.mark()
            var zooms = 0
            for i in 0..<8 {
                t.link("zoom", ["scale": view.scale * (i % 2 == 0 ? 2.2 : 1)])
                zooms += 1
                try await t.pause(0.9)
                for _ in 0..<6 {
                    t.link("pan", ["dx": i % 2 == 0 ? 50 : -50, "dy": i % 2 == 0 ? 20 : -20])
                    try await t.pause(0.05)
                }
                try await t.pause(0.5)
            }
            // Drags on the canvas need Accessibility for Expanse Tests; without it, zooms and pans only.
            if Input.allowed {
                for id in ids.prefix(4) {
                    let s = try await t.settle()
                    guard let f = s.window(id)?.canvas else { continue }
                    let from = s.screenPoint(CGPoint(x: f.midX, y: f.midY))
                    await Input.dragAsync(from: from, to: CGPoint(x: from.x + 90, y: from.y + 50))
                    try await t.pause(0.4)
                }
            }
            try await t.settle()
            let lines = t.log.lines(since: mark)
            let slowZooms = lines.filter { $0.hasPrefix("slow: animation") }
            let slowCaptures = lines.filter { $0.hasPrefix("slow: updating captures") }
            try t.expect(slowZooms.count <= zooms / 4, "\(slowZooms.count) of \(zooms) zooms logged “slow: animation” (few or none expected): \(slowZooms.prefix(3))")
            try t.expect(slowCaptures.count <= 5, "\(slowCaptures.count) “slow: updating captures” lines in about 20 s (few or none expected): \(slowCaptures.prefix(3))")
            try await t.look("Was the motion smooth throughout, with no stutters or pauses, and the window names steady rather than jittering as it zoomed?")
        },
        Case("CAPTURE-07", "Going straight back to the canvas reuses its pictures") { t in
            let budget = captureBudget
            let ids = try await t.captureFixtures("CAPTURE-07", windows: 21)
            try await t.captureGrid(ids, columns: 7)
            // The overview (as ⌥` opens it), both times: the same view ranks the same windows into
            // the streams. (Zoomed onto a few, then the overview, other windows rightly take over.)
            t.link("enter")
            try await t.settle()
            try await t.until("the streams to come up", timeout: 15) { captureStreaming(try await t.state()) >= budget }
            // 1: leave, and zoom out again (as ⌥` does) within 5 s.
            var mark = t.log.mark()
            t.link("exit")
            try await t.until("back at 100%", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
            try await t.pause(1)
            let lingering = Set(try await t.state().windows.filter(\.capturing).map(\.id))
            try t.expect(!lingering.isEmpty, "a second after leaving the canvas no window out of view still streamed (streams linger 5 s)")
            t.link("enter")
            let again = try await t.capturePics()
            try t.expect(again.state.active, "the canvas didn't open again")
            let kept = lingering.filter { again.pics[$0]?.capturing == true }
            try t.expect(!kept.isEmpty, "going straight back, all \(lingering.count) lingering streams had stopped (they should still be running)")
            if let zero = t.log.lines(since: mark).first(where: { $0.hasPrefix("capturing 0 of") }) {
                throw Failure("every stream stopped between leaving and coming back within 5 s: “\(zero)”")
            }
            let blank = ids.filter { (again.pics[$0]?.pic ?? 0) == 0 }
            try t.expect(blank.isEmpty, "going straight back, \(blank.count) windows showed no picture")
            try await t.settle()
            // 2: leave and stay: the streams stop about 5 s later.
            mark = t.log.mark()
            let left = Date()
            t.link("exit")
            guard let zero = await t.log.wait(since: mark, timeout: 12, { $0.hasPrefix("capturing 0 of") }) else {
                throw Failure("no “capturing 0 of N windows” line within 12 s of leaving the canvas")
            }
            let stoppedAfter = Date().timeIntervalSince(left)
            try t.expect(stoppedAfter >= 4 && stoppedAfter <= 9,
                         String(format: "the streams stopped %.1f s after leaving the canvas (about 5 s expected): ", stoppedAfter) + zero)
            let rest = try await t.state()
            try t.expect(captureStreaming(rest) == 0, "\(captureStreaming(rest)) windows still stream at 100% after the linger")
            try await t.pause(max(0, 10 - Date().timeIntervalSince(left)))
            // Zooming out later shows the last pictures at once, and starts the streams again.
            t.link("enter")
            let out = try await t.capturePics()
            let missing = ids.filter { (out.pics[$0]?.pic ?? 0) == 0 }
            try t.expect(missing.isEmpty, "zooming out again, \(missing.count) windows showed no picture while their streams started")
            // Any window's: the overview ranks the biggest on screen first, which needn't be these.
            try await t.until("the streams to start again", timeout: 10) { captureStreaming(try await t.state()) > 0 }
        },
        Case("CAPTURE-10", "A new window's first picture appears straight away") { t in
            let ids = try await t.captureFixtures("CAPTURE-10", windows: 30)
            try await t.captureGrid(ids, columns: 6)
            _ = try await t.captureView(ids)
            try await t.pause(2)
            guard let f = t.fixtures.last else { throw Failure("no fixture") }
            let replayd = try await captureStartReplayd()
            defer { replayd.stop() }
            let before = Set(f.windows)
            let rmark = replayd.mark()
            let opened = Date()
            try await f.openWindow()
            guard let id = Set(f.windows).subtracting(before).first else { throw Failure("the fixture didn't open a window") }
            var streamedFirst = false
            var pictured: Date?
            try await t.until("the new window on the canvas with a picture", timeout: 8) {
                let d = try await t.capturePics()
                guard let p = d.pics[id] else { return false }
                if p.first && p.capturing { streamedFirst = true }
                if !p.first && p.pic > 0 { pictured = Date(); return true }
                return false
            }
            let took = (pictured ?? Date()).timeIntervalSince(opened)
            try t.expect(took <= 2.5, String(format: "the new window's first picture took %.1f s (about a second expected)", took))
            try t.expect(!streamedFirst, "a stream started for the new window before its first picture (that should be a snapshot)")
            try t.expect(replayd.count(.picture, since: rmark) >= 1, "replayd was asked for no picture after the window opened (its first should be a snapshot)")
            let s = try await t.state()
            try t.expect(s.active, "the canvas closed")
        },
        Case("CAPTURE-12", "Glides only stream what's on screen at the start and the end") { t in
            let size = CGSize(width: 500, height: 340)
            let span = t.screen.width * 1.5
            func make(_ title: String) async throws -> TestWindow {
                try await t.window(title, CGRect(x: 160, y: 160, width: size.width, height: size.height))
            }
            let start = try await make("CAPTURE-12 Start")
            var passed: [TestWindow] = []
            for i in 1...3 { passed.append(try await make("CAPTURE-12 Passed \(i)")) }
            let far = try await make("CAPTURE-12 Far")
            // Far out on the canvas, in a line: Start, then (well out of view of both ends) the
            // windows passed on the way, then Far.
            let x0: CGFloat = 40000, y: CGFloat = 40000
            t.place(start, at: CGPoint(x: x0, y: y), commit: false)
            for (i, w) in passed.enumerated() {
                t.place(w, at: CGPoint(x: x0 + span + CGFloat(i) * (size.width + 200), y: y), commit: false)
            }
            t.place(far, at: CGPoint(x: x0 + span * 2 + 3 * (size.width + 200), y: y), commit: true)
            try await t.settle()
            try await t.captureFocus(start.id)
            // Nothing lingering from earlier glides.
            try await t.until("no streams at 100%", timeout: 12) { captureStreaming(try await t.state()) == 0 }
            let before = try await t.state()
            let mark = t.log.mark()
            try await t.captureFocus(far.id)
            // Straight away: a stream started on the way would still be running (streams linger).
            let after = try await t.state()
            func shown(_ s: ExpanseState) -> Set<CGWindowID> { Set(s.windows.filter { $0.canvas.intersects(s.visibleCanvas) }.map(\.id)) }
            let ends = shown(before).union(shown(after))
            try t.expect(!passed.contains { ends.contains($0.id) }, "setup: a window to pass was on screen at the start or the end")
            let streamed = passed.filter { after.window($0.id)?.capturing == true }
            try t.expect(streamed.isEmpty, "\(streamed.map(\.title)) streamed though the glide only passed them")
            let counts = t.log.lines(since: mark).compactMap(captureCountLine).map(\.running)
            try t.expect((counts.max() ?? 0) <= ends.count,
                         "during the glide up to \(counts.max() ?? 0) windows streamed, but only \(ends.count) were on screen at its start and end")
        },
        Case("CAPTURE-15", "Expanse uses almost no CPU at rest") { t in
            guard let pid = t.expanse?.processIdentifier else { throw Failure("Expanse isn't running") }
            _ = try await t.captureFixtures("CAPTURE-15", windows: 33)
            try await t.settle()
            // First pictures, scans for the new windows and the 5 s linger: then nothing to do.
            try await t.until("no streams at 100%", timeout: 15) { captureStreaming(try await t.state()) == 0 }
            try await t.pause(4)
            let replayd = try await captureStartReplayd()
            defer { replayd.stop() }
            let rpid = await captureReplaydPID()
            let rmark = replayd.mark()
            let c0 = await captureCPU(pid)
            var r0: Double?
            if let rpid { r0 = await captureCPU(rpid) }
            let began = Date()
            try await t.pause(40)
            let c1 = await captureCPU(pid)
            var r1: Double?
            // (A different replayd now: it restarted, and its time can't be compared.)
            if let rpid, await captureReplaydPID() == rpid { r1 = await captureCPU(rpid) }
            let span = Date().timeIntervalSince(began)
            guard let c0, let c1 else { throw Failure("couldn't read Expanse's CPU time with ps") }
            let cpu = (c1 - c0) / span * 100
            try t.expect(cpu <= 1.5, String(format: "Expanse used %.1f%% CPU at rest over %.0f s (about 0.5–1%% expected)", cpu, span))
            if let r0, let r1, r1 >= r0 {
                let rcpu = (r1 - r0) / span * 100
                try t.expect(rcpu <= 1.5, String(format: "replayd used %.1f%% CPU while Expanse was at rest (under about 1%% expected)", rcpu))
            }
            let s = try await t.state()
            try t.expect(captureStreaming(s) == 0, "\(captureStreaming(s)) windows stream at rest at 100% (none expected: no purple dot)")
            let pictures = replayd.count(.picture, since: rmark), starts = replayd.count(.streamStart, since: rmark)
            try t.expect(pictures == 0 && starts == 0, "at rest replayd was asked for \(pictures) pictures and \(starts) streams (none expected)")
            let scans = replayd.count(.scan, since: rmark)
            if scans == 0 { throw Skip("CPU fine, but replayd logged no window scan in 40 s, so the 5 s safety-net scan couldn't be checked") }
            try t.expect(scans <= Int(span / 5) + 3, "\(scans) window scans in \(Int(span)) s (the safety-net scan runs every 5 s)")
        },
        Case("CAPTURE-16", "Other apps can still capture the screen while you're zoomed out", .guided) { t in
            var ids: [CGWindowID] = []
            for i in 1...2 {
                let w = try await t.window("CAPTURE-16 Clock \(i)", CGRect(x: 100 + 40 * CGFloat(i), y: 140, width: 400, height: 280))
                captureClock(w)
                ids.append(w.id)
            }
            ids += try await t.captureFixtures("CAPTURE-16", windows: 48)
            try await t.captureGrid(ids, columns: 10)
            _ = try await t.captureView(ids)
            try await t.until("the streams to come up", timeout: 15) { captureStreaming(try await t.state(), ids) >= min(captureBudget, ids.count) }
            try await t.ask("Start a recording of the whole screen with QuickTime Player (File › New Screen Recording, then record the entire screen), "
                            + "or start a screen share, and leave it running. Then click Done.")
            let replayd = try await captureStartReplayd()
            defer { replayd.stop() }
            let rmark = replayd.mark(), mark = t.log.mark()
            var fewest = Int.max
            for _ in 0..<6 {
                try await t.pause(5)
                let s = try await t.state()
                try t.expect(s.active, "the canvas closed")
                fewest = min(fewest, captureStreaming(s, ids))
            }
            try t.expect(fewest > 0, "Expanse's streams all stopped while the other app captured")
            let pictures = replayd.count(.picture, since: rmark)
            try t.expect(pictures >= 30, "only \(pictures) one-off pictures in 30 s for the windows not streamed (hundreds expected)")
            if let failed = t.log.lines(since: mark).first(where: { $0.contains("timed out") || $0.hasPrefix("startCapture failed") }) {
                throw Failure("Expanse's captures failed while the other app captured: \(failed)")
            }
            try await t.look("Is the other app's recording or screen share still running and capturing, "
                             + "and do the clocks in the two “CAPTURE-16 Clock” windows on the canvas keep ticking?")
            try await t.ask("Stop the recording or screen share (you can discard the recording). Then click Done.")
        },
        Case("CAPTURE-21", "Live pictures recover after replayd crashes",
             known: "zoomed out, streams replayd's crash stopped stay stopped until the camera moves: a stopped stream only asks for a scan, and askAgain's updateStreamingSoon returns while the canvas is up") { t in
            let ids = try await t.captureFixtures("CAPTURE-21", windows: 8)
            try await t.captureGrid(ids, columns: 4)
            _ = try await t.captureView(ids)
            let streams = min(captureBudget, ids.count)
            try await t.until("the windows to stream", timeout: 15) { captureStreaming(try await t.state(), ids) >= streams }
            let replayd = try await captureStartReplayd()
            defer { replayd.stop() }
            guard let old = await captureReplaydPID() else { throw Failure("replayd isn't running") }
            let rmark = replayd.mark()
            // Force Quit, as Activity Monitor does.
            try captureSignalReplayd("KILL")
            try await t.until("macOS to start replayd again", timeout: 25) {
                guard let now = await captureReplaydPID() else { return false }
                return now != old
            }
            // Staying zoomed out, without touching it: the pictures update again.
            try await t.until("pictures to update again after replayd came back (a stream or a picture asked of it)", timeout: 15) {
                guard replayd.count(.streamStart, since: rmark) + replayd.count(.picture, since: rmark) > 0 else { return false }
                return captureStreaming(try await t.state(), ids) > 0
            }
            try await t.pause(5)
            let d = try await t.capturePics()
            try t.expect(d.state.active, "the canvas closed")
            let gone = ids.filter { d.state.window($0) == nil }
            try t.expect(gone.isEmpty, "\(gone.count) windows dropped off the canvas when replayd crashed")
            let blank = ids.filter { (d.pics[$0]?.pic ?? 0) == 0 }
            try t.expect(blank.isEmpty, "\(blank.count) windows have no picture after replayd came back")
            // Back to 100%, then out again: live pictures.
            t.link("exit")
            try await t.until("back at 100%", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
            _ = try await t.captureView(ids)
            try await t.until("live pictures zooming out again", timeout: 12) { captureStreaming(try await t.state(), ids) >= streams }
        },
        Case("CAPTURE-23", "No purple badge on a window after a hop", .look) { t in
            let centre = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", centre) }
            let ws = try await t.row(["CAPTURE-23 A", "CAPTURE-23 B", "CAPTURE-23 C", "CAPTURE-23 D"])
            t.link("focus", ["id": ws[0].id])
            try await t.captureNoStreamsOnScreen("the first glide")
            ws[0].focus()
            try await t.ask("Watch the traffic lights of the windows on screen while Expanse Tests hops right once, "
                            + "then several times quickly, then back left. Click Done to start.")
            let mark = t.log.mark()
            t.link("nav", ["dir": "right"])
            try await t.captureNoStreamsOnScreen("a hop right")
            for _ in 0..<2 {
                t.link("nav", ["dir": "right"])
                try await t.pause(0.12)
            }
            try await t.captureNoStreamsOnScreen("quick hops right")
            t.link("nav", ["dir": "left"])
            try await t.captureNoStreamsOnScreen("a hop left")
            try t.captureHandBacks(since: mark)
            try await t.look("Did every hop land with no purple badge over the traffic lights of any window on screen, not even briefly?")
        },
        Case("CAPTURE-24", "No purple badge after zooming back in from the canvas", .look) { t in
            let ws = try await t.row(["CAPTURE-24 A", "CAPTURE-24 B", "CAPTURE-24 C"])
            t.link("focus", ["id": ws[1].id])
            try await t.captureNoStreamsOnScreen("the first glide")
            try await t.ask("Watch the traffic lights of the windows on screen as Expanse Tests zooms out and back in, "
                            + "then zooms out and glides into a window. Click Done to start.")
            let mark = t.log.mark()
            let ids = ws.map(\.id)
            t.link("toggle")
            try await t.until("live pictures on the canvas", timeout: 10) { let s = try await t.state(); return s.active && captureStreaming(s, ids) > 0 }
            t.link("toggle")
            try await t.captureNoStreamsOnScreen("zooming back in")
            t.link("toggle")
            try await t.until("live pictures on the canvas", timeout: 10) { let s = try await t.state(); return s.active && captureStreaming(s, ids) > 0 }
            // As clicking it on the canvas: back to 100% on that window.
            t.link("focus", ["id": ws[2].id])
            try await t.captureNoStreamsOnScreen("gliding into a window from the canvas")
            try t.captureHandBacks(since: mark)
            try await t.look("Both times, did the windows land at 100% with no purple badge on any window on screen?")
        },
        Case("CAPTURE-25", "No purple badge after a display change puts windows back", .look) { t in
            let ws = try await t.row(["CAPTURE-25 A", "CAPTURE-25 B"])
            t.link("focus", ["id": ws[0].id])
            try await t.captureNoStreamsOnScreen("the first glide")
            let real = t.screen.size
            let fake = abs(real.width - 1440) < 1 && abs(real.height - 900) < 1 ? CGSize(width: 1280, height: 800) : CGSize(width: 1440, height: 900)
            try await t.ask("Watch the traffic lights of the windows on screen: Expanse Tests will pretend the display changes size, "
                            + "then changes back. Click Done to start.")
            var mark = t.log.mark()
            t.link("screen", ["w": Int(fake.width), "h": Int(fake.height)])
            try await t.expectLog("display changed:", since: mark, timeout: 10)
            try await t.pause(3)
            try await t.captureNoStreamsOnScreen("the display change")
            mark = t.log.mark()
            t.link("screen")
            try await t.expectLog("display changed:", since: mark, timeout: 10)
            try await t.pause(3)
            try await t.captureNoStreamsOnScreen("the display changing back")
            try await t.look("Both times, did the windows come back in place with no purple badge on any window on screen?")
        },
        Case("CAPTURE-26", "streamBudget lowers the number of live window streams") { t in
            let ids = try await t.captureFixtures("CAPTURE-26", windows: 18)
            try await t.captureGrid(ids, columns: 6)
            let old = expanseDefault("streamBudget")
            var failure: Error?
            do {
                // Read once at launch: each value needs a relaunch.
                for (value, expected) in [(4, 4), (0, 16), (50, 16)] {
                    setExpanseDefault("streamBudget", value)
                    try await t.relaunchExpanse()
                    try await t.until("Expanse to take the windows back on", timeout: 20) {
                        let s = try await t.state()
                        return ids.allSatisfy { s.window($0) != nil }
                    }
                    // Every window in view (the catalogue's 0 on the canvas, for these windows). The
                    // "capturing N of M" line comes as the streams start, during the zoom.
                    let mark = t.log.mark()
                    _ = try await t.captureView(ids)
                    try await t.until("\(expected) windows streaming with streamBudget \(value)", timeout: 12) {
                        captureStreaming(try await t.state(), ids) >= expected
                    }
                    try await t.pause(1.5)
                    let n = captureStreaming(try await t.state())
                    try t.expect(n <= expected, "with streamBudget \(value), \(n) windows stream (at most \(expected) expected)")
                    // The others still update, as one-off pictures in turn.
                    guard let line = t.log.lines(since: mark).compactMap(captureCountLine).last else {
                        throw Failure("with streamBudget \(value): no “capturing N of M windows” line")
                    }
                    // Only windows in view queue for one (minus any the panels cover), so not every other one.
                    try t.expect(line.snapshots > 0,
                                 "with streamBudget \(value): “\(line.snapshots) more by snapshot”: the windows in view without a stream should get one-off pictures")
                }
            } catch {
                failure = error
            }
            setExpanseDefault("streamBudget", old)
            try await t.relaunchExpanse()
            if let failure { throw failure }
        },
        Case("CAPTURE-27", "Windows stay on the canvas when macOS restarts its capture service") { t in
            let ids = try await t.captureFixtures("CAPTURE-27", windows: 6)
            guard let f = t.fixtures.last else { throw Failure("no fixture") }
            try await t.captureGrid(ids, columns: 3)
            _ = try await t.captureView(ids)
            let streams = min(captureBudget, ids.count)
            try await t.until("the windows to stream", timeout: 15) { captureStreaming(try await t.state(), ids) >= streams }
            let streaming = try await t.state().windows.filter { ids.contains($0.id) && $0.capturing }
            let mark = t.log.mark()
            try captureSignalReplayd("KILL")   // replayd ignores TERM; launchd starts a new one
            for w in streaming {
                try await t.expectLog("\(w.app)[\(w.id)]: its capture stopped; checking it's still open", since: mark, timeout: 15)
            }
            try await t.pause(15)
            let s = try await t.state()
            let gone = ids.filter { s.window($0) == nil }
            try t.expect(gone.isEmpty, "\(gone.count) open windows dropped off the canvas when replayd restarted")
            // Zoom in and out: the pictures come back.
            t.link("exit")
            try await t.until("back at 100%", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
            _ = try await t.captureView(ids)
            try await t.until("live pictures again", timeout: 12) { captureStreaming(try await t.state(), ids) >= streams }
            let d = try await t.capturePics()
            let blank = ids.filter { (d.pics[$0]?.pic ?? 0) == 0 }
            try t.expect(blank.isEmpty, "\(blank.count) windows have no picture after replayd restarted")
            // A window closed while zoomed out still drops off, once a scan confirms it.
            guard let closing = f.windows.first else { throw Failure("the fixture has no window") }
            let closeMark = t.log.mark()
            try await f.closeWindow(0)
            try await t.expectLog("dropped \(s.window(closing)?.app ?? "Expanse Tests")[\(closing)]: not in the window list", since: closeMark, timeout: 15)
            let after = try await t.state()
            try t.expect(after.window(closing) == nil, "the closed window is still on the canvas")
            try t.expect(ids.filter { $0 != closing }.allSatisfy { after.window($0) != nil }, "an open window dropped off with the closed one")
        },
        Case("CAPTURE-28", "A scan with no answer is given up, so new windows are still taken on") { t in
            let f = try await t.fixture("CAPTURE-28", windows: 2)
            let sources = f.windows
            try await t.until("Expanse to take on the fixture's windows", timeout: 15) {
                let s = try await t.state()
                return sources.allSatisfy { s.window($0) != nil }
            }
            guard let source = sources.first else { throw Failure("the fixture has no window") }
            try await t.captureFocus(source)
            let mark = t.log.mark()
            // Restart replayd while Expanse is scanning (opening the canvas scans).
            t.link("enter", ["zoomOut": 0])
            try captureSignalReplayd("KILL")   // replayd ignores TERM; launchd starts a new one
            try await t.pause(1)
            t.link("exit")
            try await t.until("back at 100%", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
            try await t.pause(2)
            let before = Set(f.windows)
            let opened = Date()
            try await f.openWindow()
            guard let id = Set(f.windows).subtracting(before).first else { throw Failure("the fixture didn't open a window") }
            try await t.until("Expanse to take on the new window", timeout: 40) { try await t.state().window(id) != nil }
            let took = Date().timeIntervalSince(opened)
            let hung = t.log.lines(since: mark).first { $0.hasPrefix("window scan got no answer in 10s") }
            // Within seconds; up to a scan's 10 s timeout and the next scan if one hung.
            try t.expect(took <= (hung == nil ? 10 : 35),
                         String(format: "the new window took %.0f s to be taken on", took) + (hung.map { " (after “\($0)”)" } ?? ""))
            let app = try await t.state().window(id)?.app ?? "Expanse Tests"
            try await t.expectLog("tracking \(app) [\(id)]", since: mark, timeout: 2)
            // Beside its source: the app's window in view.
            let placed = t.log.lines(since: mark).filter { $0.hasPrefix("placed new window \(app) at") }
            try t.expect(placed.contains { line in line.contains(" beside ") && sources.contains { line.contains("[\($0)]") } },
                         "the new window wasn't placed beside its app's window: \(placed.isEmpty ? "no “placed new window” line" : placed.joined(separator: "; "))")
        },
        Case("CAPTURE-29", "Window scans back off while macOS's capture service is stuck") { t in
            try captureNeedsTime(780)
            let f = try await t.fixture("CAPTURE-29", windows: 1)
            try await t.until("Expanse to take on the fixture's window", timeout: 15) { try await t.state().window(f.windows.first ?? 0) != nil }
            var mark = t.log.mark()
            // replayd stops answering every app until it's continued: always continue it.
            try captureSignalReplayd("STOP")
            defer { try? captureSignalReplayd("CONT") }
            var last: Date?
            var opened: CGWindowID?
            for (i, (wait, next)) in [(10, 20), (20, 40), (40, 80), (80, 160), (160, 320), (320, 320)].enumerated() {
                let expected = "window scan got no answer in \(wait)s (macOS's capture service stuck or restarting?); the next waits \(next)s"
                guard let line = try await t.captureNext(after: &mark, timeout: Double(wait) + 25, { $0.hasPrefix("window scan got no answer") }) else {
                    throw Failure("no “window scan got no answer in \(wait)s …” line within \(wait + 25) s")
                }
                try t.expect(line == expected, "expected “\(expected)”, got “\(line)”")
                let now = Date()
                if let last {
                    let gap = now.timeIntervalSince(last)
                    try t.expect(abs(gap - Double(wait)) <= 4, String(format: "%.0f s between unanswered scans, %d s expected", gap, wait))
                }
                last = now
                if i == 1 {
                    // A window opened while replayd is stuck turns up once it answers.
                    let before = Set(f.windows)
                    try await f.openWindow()
                    opened = Set(f.windows).subtracting(before).first
                }
            }
            try captureSignalReplayd("CONT")
            guard let opened else { throw Failure("the fixture didn't open a window") }
            try await t.until("the window opened meanwhile to be taken on", timeout: 30) { try await t.state().window(opened) != nil }
            // Back to normal: the next unanswered scan waits 10 s again.
            mark = t.log.mark()
            try captureSignalReplayd("STOP")
            let again = try await t.captureNext(after: &mark, timeout: 30, { $0.hasPrefix("window scan got no answer") })
            try captureSignalReplayd("CONT")
            guard let again else { throw Failure("no “window scan got no answer” line within 30 s of stopping replayd again") }
            try t.expect(again.hasPrefix("window scan got no answer in 10s"), "once replayd answered, the next wait should start at 10 s again: “\(again)”")
        },
        Case("CAPTURE-30", "A late answer to a scan already given up on is dropped") { t in
            try captureNeedsTime(200)
            let f = try await t.fixture("CAPTURE-30", windows: 3)
            let ids = f.windows
            try await t.until("Expanse to take on the fixture's windows", timeout: 15) {
                let s = try await t.state()
                return ids.allSatisfy { s.window($0) != nil }
            }
            guard let closed = ids.first else { throw Failure("the fixture has no window") }
            var mark = t.log.mark()
            try captureSignalReplayd("STOP")
            defer { try? captureSignalReplayd("CONT") }
            var opened: CGWindowID?
            for n in 1...3 {
                guard try await t.captureNext(after: &mark, timeout: 75, { $0.hasPrefix("window scan got no answer") }) != nil else {
                    throw Failure("only \(n - 1) “window scan got no answer” lines while replayd was stopped (three expected)")
                }
                if n == 1 {
                    // The windows change while replayd is stuck: the canvas must show them as they are now.
                    try await f.closeWindow(0)
                    let before = Set(f.windows)
                    try await f.openWindow()
                    opened = Set(f.windows).subtracting(before).first
                }
            }
            let resumed = t.log.mark()
            try captureSignalReplayd("CONT")
            // Straight away: the canvas, and a hop. Expanse answers promptly throughout.
            var slowest = 0.0
            let commands: [(String, [String: Any])] = [("toggle", [:]), ("toggle", [:]), ("nav", ["dir": "right"])]
            for (command, query) in commands {
                t.link(command, query)
                let asked = Date()
                _ = try await t.state()
                slowest = max(slowest, Date().timeIntervalSince(asked))
                try await t.pause(0.6)
            }
            try t.expect(slowest < 3, String(format: "Expanse took %.1f s to answer while replayd caught up (it should stay responsive)", slowest))
            try await t.until("the canvas to show the windows as they are now", timeout: 20) {
                let s = try await t.settle()
                return s.window(closed) == nil && (opened.map { s.window($0) != nil } ?? true)
            }
            try await t.pause(3)
            let slow = t.log.lines(since: resumed).filter { $0.hasPrefix("slow: window scan took") }
            try t.expect(slow.count <= 1, "a run of \(slow.count) “slow: window scan took …” lines after the resume "
                         + "(answers to scans given up on should stop before asking apps about their windows): \(slow.prefix(3))")
        },
        Case("CAPTURE-34", "Refused window scans back off", .guided) { t in
            let ids = try await t.captureFixtures("CAPTURE-34", windows: 4)
            try await t.ask("Open System Settings › Privacy & Security › Screen & System Audio Recording and turn Expanse off "
                            + "(if macOS offers to quit Expanse, choose Later). Then click Done.")
            var mark = t.log.mark()
            // The first refusal; none at all if macOS now says Expanse has no access (then it
            // doesn't scan in the first place: also right).
            if try await t.captureNext(after: &mark, timeout: 40, { $0.hasPrefix("SCShareableContent failed:") }) != nil {
                // Each refusal doubles the wait: about 10, 20, 40, 80, 160 s (the next scan comes
                // on the 5 s timer once the wait is over), not every 5 s.
                var last = Date()
                for wait in [10, 20, 40, 80, 160] {
                    guard try await t.captureNext(after: &mark, timeout: Double(wait) + 30, { $0.hasPrefix("SCShareableContent failed:") }) != nil else {
                        throw Failure("no “SCShareableContent failed” line within \(wait + 30) s of the last")
                    }
                    let gap = Date().timeIntervalSince(last)
                    last = Date()
                    try t.expect(gap >= Double(wait) - 1.5 && gap <= Double(wait) + 7,
                                 String(format: "%.0f s between refused scans (about %d s expected, not every 5 s)", gap, wait))
                }
            }
            // Meanwhile no pictures or streams are asked for, even zoomed out over the windows.
            let replayd = try await captureStartReplayd()
            defer { replayd.stop() }
            let rmark = replayd.mark()
            t.link("enter")
            try await t.until("the canvas to open", timeout: 8) { try await t.settle().active }
            try await t.pause(5)
            let s = try await t.state()
            try t.expect(captureStreaming(s, ids) == 0, "\(captureStreaming(s, ids)) windows streamed while macOS refused Expanse's scans")
            let asked = replayd.count(.picture, since: rmark) + replayd.count(.streamStart, since: rmark)
            try t.expect(asked == 0, "replayd was asked for \(asked) pictures or streams while macOS refused Expanse's scans")
            t.link("exit")
            try await t.until("back at 100%", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
            try await t.ask("Turn Expanse back on in Screen & System Audio Recording (if macOS offers to quit and reopen it, choose Later: "
                            + "Expanse Tests restarts it). Then click Done.")
            try await t.relaunchExpanse()
            try await t.until("Expanse to take the windows back on", timeout: 20) {
                let s = try await t.state()
                return ids.allSatisfy { s.window($0) != nil }
            }
            let resumed = t.log.mark()
            t.link("enter")
            try await t.until("captures to resume", timeout: 15) { captureStreaming(try await t.state(), ids) > 0 }
            try await t.noLog("SCShareableContent failed:", since: resumed, within: 1)
        },
        Case("CAPTURE-35", "The desktop picture isn't re-taken within 2 s, or while capture is stuck") { t in
            let background = expanseDefault("background")
            setExpanseDefault("background", "wallpaper")
            defer { setExpanseDefault("background", background) }
            // On its own far out on the canvas, so no other window's picture is taken meanwhile.
            let a = try await t.window("CAPTURE-35 A")
            t.place(a, at: CGPoint(x: 50000, y: 50000))
            try await t.settle()
            try await t.captureFocus(a.id)
            try await t.until("no streams at 100%", timeout: 12) { captureStreaming(try await t.state()) == 0 }
            try await t.pause(2.5)
            let replayd = try await captureStartReplayd()
            defer { replayd.stop() }
            // 1: the canvas opened and closed four times within 2 s.
            var rmark = replayd.mark()
            for _ in 0..<4 {
                t.link("enter", ["zoomOut": 0])
                try await t.pause(0.2)
                t.link("exit")
                try await t.pause(0.25)
            }
            try await t.settle()
            try await t.pause(1.5)
            let burst = replayd.count(.picture, since: rmark)
            try t.expect(burst <= 1, "opening the canvas 4 times within 2 s took \(burst) pictures (the desktop at most once every 2 s)")
            // 2: while scans get no answer, opening the canvas asks for no desktop picture.
            let mark = t.log.mark()
            try captureSignalReplayd("STOP")
            defer { try? captureSignalReplayd("CONT") }
            guard await t.log.wait(since: mark, timeout: 25, { $0.hasPrefix("window scan got no answer") }) != nil else {
                throw Failure("no “window scan got no answer” line within 25 s of stopping replayd")
            }
            t.link("enter", ["zoomOut": 0])
            try await t.until("the canvas to open", timeout: 8) { try await t.state().active }
            try await t.pause(1)
            // A request made while replayd was stopped is answered (and logged) once it carries on.
            rmark = replayd.mark()
            try captureSignalReplayd("CONT")
            try await t.pause(5)
            let late = replayd.count(.picture, since: rmark)
            try t.expect(late == 0, "\(late) pictures were taken once replayd carried on: the desktop's, asked for while scans got no answer")
            t.link("exit")
        },
        Case("CAPTURE-36", "Protected video doesn't blink while you're at 100%", .guided) { t in
            try await t.ask("Play protected video in a window (Prime Video, Apple TV+ or Netflix in Safari), not full screen. "
                            + "Then click Done, and leave the Mac alone until Expanse Tests asks again.")
            guard let player = NSWorkspace.shared.frontmostApplication, let name = player.localizedName,
                  player.bundleIdentifier != "com.invignation.expanse.integration" else {
                throw Failure("the video's app isn't in front")
            }
            // Slivers of parked windows at both edges of the screen, around the video's window.
            let left = try await t.window("CAPTURE-36 Left", CGRect(x: 120, y: 160, width: 640, height: 420))
            let right = try await t.window("CAPTURE-36 Right", CGRect(x: 160, y: 200, width: 640, height: 420))
            t.link("focus", ["app": name.lowercased()])
            try await t.pause(1)
            let s = try await t.settle()
            let v = s.visibleCanvas
            t.place(left, at: CGPoint(x: v.minX - 640 + 60, y: v.midY - 210), commit: false)
            t.place(right, at: CGPoint(x: v.maxX - 60, y: v.midY - 210))
            try await t.settle()
            let placed = try await t.state()
            try t.expect(placed.window(left.id)?.parked == true && placed.window(right.id)?.parked == true,
                         "setup: the sliver windows weren't parked at the screen's edges")
            // Each sliver's one picture, then the 5 s linger.
            try await t.until("no streams at 100%", timeout: 15) { captureStreaming(try await t.state()) == 0 }
            try await t.pause(3)
            let replayd = try await captureStartReplayd()
            defer { replayd.stop() }
            @MainActor func quiet(_ what: String) async throws {
                let mark = replayd.mark()
                try await t.pause(80)
                let pictures = replayd.count(.picture, since: mark), streams = replayd.count(.streamStart, since: mark)
                try t.expect(pictures == 0 && streams == 0,
                             "\(what): replayd was asked for \(pictures) pictures and \(streams) streams in 80 s (none expected: each capture blinks protected video)")
                let s = try await t.state()
                try t.expect(captureStreaming(s) == 0, "\(what): \(captureStreaming(s)) windows stream (none expected: no purple dot)")
            }
            try await quiet("At 100% with the video in a window")
            try await t.ask("Make the video full screen. Then click Done, and leave the Mac alone until Expanse Tests asks again.")
            try await quiet("At 100% with the video full screen")
            t.link("pause")
            try await t.until("Expanse to pause", timeout: 8) { try await t.state().paused }
            try await quiet("Paused")
            // Asked before resuming: taking the windows on again takes their first pictures.
            try await t.look("While Expanse Tests waited (the three spells of 80 seconds), did the video play without a single blink?")
            t.link("resume")
            try await t.until("Expanse to resume", timeout: 8) { try await !t.state().paused }
        },
        Case("CAPTURE-38", "The desktop picture is captured as the canvas opens, not on a timer", .guided) { t in
            let background = expanseDefault("background")
            setExpanseDefault("background", "wallpaper")
            defer { setExpanseDefault("background", background) }
            try await t.until("no streams at 100%", timeout: 12) { captureStreaming(try await t.state()) == 0 }
            let replayd = try await captureStartReplayd()
            defer { replayd.stop() }
            // 1: over five minutes at 100%: no capture at the 5-minute mark (or any other).
            try await t.ask("Expanse Tests will now check that nothing is captured for 5 minutes at 100%. "
                            + "Leave the Mac alone until it asks again. Click Done to start.")
            var mark = replayd.mark()
            try await t.pause(310)
            let pictures = replayd.count(.picture, since: mark), streams = replayd.count(.streamStart, since: mark)
            try t.expect(pictures == 0 && streams == 0, "over 5 minutes at rest replayd was asked for \(pictures) pictures and \(streams) streams (none expected)")
            // 2: the canvas opening takes the desktop as it is now.
            try await t.ask("Change the desktop picture in System Settings › Wallpaper to one that's easy to tell apart "
                            + "(you can change it back afterwards). Then click Done.")
            mark = replayd.mark()
            t.link("enter")
            try await t.until("the canvas to open", timeout: 8) { try await t.settle().active }
            try await t.pause(2)
            try t.expect(replayd.count(.picture, since: mark) >= 1, "opening the canvas took no picture of the desktop")
            try await t.look("Does the canvas's backdrop show the new desktop picture?")
            t.link("exit")
            try await t.until("back at 100%", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
            // 3: paused, a Space change takes no picture.
            t.link("pause")
            try await t.until("Expanse to pause", timeout: 8) { try await t.state().paused }
            try await t.pause(1)
            mark = replayd.mark()
            try await t.ask("Switch to another Space and back again (with Mission Control, or a four-finger swipe). Then click Done.")
            try await t.pause(2)
            let paused = replayd.count(.picture, since: mark)
            try t.expect(paused == 0, "switching Spaces while paused took \(paused) pictures (none expected)")
            t.link("resume")
            try await t.until("Expanse to resume", timeout: 8) { try await !t.state().paused }
            // Windows are taken on afresh (first pictures): let that pass.
            try await t.pause(10)
            // 4: running, a Space change does.
            mark = replayd.mark()
            try await t.ask("Switch to another Space and back again. Then click Done.")
            try await t.pause(2)
            try t.expect(replayd.count(.picture, since: mark) >= 1, "switching Spaces while running took no picture of the desktop")
            // 5: so does a display change.
            var logMark = t.log.mark()
            mark = replayd.mark()
            let real = t.screen.size
            t.link("screen", ["w": Int(real.width) == 1280 ? 1440 : 1280, "h": Int(real.height) == 800 ? 900 : 800])
            try await t.expectLog("display changed:", since: logMark, timeout: 10)
            try await t.pause(3)
            try t.expect(replayd.count(.picture, since: mark) >= 1, "a display change took no picture of the desktop")
            logMark = t.log.mark()
            t.link("screen")
            try await t.expectLog("display changed:", since: logMark, timeout: 10)
            try await t.pause(3)
            // 6: and turning the switch on.
            t.link("menu")
            mark = replayd.mark()
            try await t.ask("In Expanse's menu bar panel, turn Desktop picture background off, then on again. Then click Done.")
            try await t.pause(2)
            try t.expect(replayd.count(.picture, since: mark) >= 1, "turning Desktop picture background on took no picture of the desktop")
        },
    ]
}

// MARK: - Helpers

/// The most windows Expanse streams at once: streamBudget if it's 1–16 (read at launch), else 16.
@MainActor private var captureBudget: Int {
    let n = expanseDefault("streamBudget") as? Int ?? 0
    return (1...16).contains(n) ? n : 16
}

/// How many windows stream (or are starting to), of `ids` or of all.
private func captureStreaming(_ s: ExpanseState, _ ids: [CGWindowID]? = nil) -> Int {
    s.windows.filter { $0.capturing && (ids?.contains($0.id) ?? true) }.count
}

/// Expanse's `capturing N of M windows, K more by snapshot` line.
private func captureCountLine(_ line: String) -> (running: Int, total: Int, snapshots: Int)? {
    guard let m = line.firstMatch(of: #/^capturing (\d+) of (\d+) windows, (\d+) more by snapshot/#),
          let running = Int(m.1), let total = Int(m.2), let snapshots = Int(m.3) else { return nil }
    return (running, total, snapshots)
}

/// What a dump line says about a window's picture (ExpanseState leaves it out).
private struct CapturePic {
    /// A stream running or starting.
    let capturing: Bool
    /// Still waiting for its first picture.
    let first: Bool
    /// Its picture's width in pixels (0: none yet).
    let pic: Int
}

/// A clock in a test window, so its picture on the canvas visibly keeps changing.
@MainActor private func captureClock(_ w: TestWindow) {
    guard let box = w.window.contentView else { return }
    let clock = NSTextField(labelWithString: "")
    clock.font = .monospacedDigitSystemFont(ofSize: 34, weight: .bold)
    clock.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(clock)
    NSLayoutConstraint.activate([clock.centerXAnchor.constraint(equalTo: box.centerXAnchor),
                                 clock.centerYAnchor.constraint(equalTo: box.centerYAnchor, constant: 48)])
    let format = DateFormatter()
    format.dateFormat = "HH:mm:ss.S"
    let timer = Timer(timeInterval: 0.1, repeats: true) { [weak clock] timer in
        MainActor.assumeIsolated {
            guard let clock else { timer.invalidate(); return }
            clock.stringValue = format.string(from: Date())
        }
    }
    RunLoop.main.add(timer, forMode: .common)
}

/// Long cases need the runner's --timeout raised (auto cases get 90 s unless told otherwise).
private func captureNeedsTime(_ seconds: Int) throws {
    let args = CommandLine.arguments
    let given = args.firstIndex(of: "--timeout").flatMap { args.indices.contains($0 + 1) ? Double(args[$0 + 1]) : nil } ?? 90
    if given < Double(seconds) {
        throw Skip("takes about \(seconds / 60 + 1) minutes: run it with --timeout \(seconds) or more")
    }
}

/// A command's output (run off the main thread).
private func captureRun(_ path: String, _ arguments: [String]) async -> String {
    await Task.detached {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }.value
}

/// The CPU time a process has used so far, in seconds (ps's TIME: user and system).
private func captureCPU(_ pid: pid_t) async -> Double? {
    let text = await captureRun("/bin/ps", ["-o", "time=", "-p", "\(pid)"]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    var seconds = 0.0
    for part in text.split(separator: ":") {
        guard let v = Double(part) else { return nil }
        seconds = seconds * 60 + v
    }
    return seconds
}

private func captureReplaydPID() async -> pid_t? {
    let text = await captureRun("/usr/bin/pgrep", ["-x", "replayd"])
    return text.split(separator: "\n").first.flatMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
}

/// Signals replayd (it runs as you): KILL as a crash (Force Quit), TERM as a restart, STOP and CONT
/// to have it stop answering and carry on. STOP stops every app's screen capture: always CONT.
private func captureSignalReplayd(_ signal: String) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    p.arguments = ["-\(signal)", "replayd"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
    if p.terminationStatus != 0 {
        throw Failure("killall -\(signal) replayd failed (status \(p.terminationStatus)): is replayd running?")
    }
}

/// replayd's log as it's written, to count what it's asked for: pictures (one-off captures),
/// stream starts and window scans. Its messages name the request, not the app asking.
private final class CaptureReplayd: @unchecked Sendable {
    enum Request: String {
        case picture = "RPConnectionManager captureScreenshot:"
        case streamStart = "RPConnectionManager startCapture:"
        case scan = "RPConnectionManager fetchShareableContentWithOption:"
    }

    private let lock = NSLock()
    private var lines: [String] = []
    private var process: Process?

    func start() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["stream", "--style", "ndjson", "--predicate", "process == \"replayd\""]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        var pending = Data()
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            pending.append(chunk)
            while let nl = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<nl]
                pending.removeSubrange(pending.startIndex...nl)
                guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let message = json["eventMessage"] as? String else { continue }
                self?.append(message)
            }
        }
        try p.run()
        process = p
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func append(_ line: String) {
        lock.lock(); lines.append(line); lock.unlock()
    }

    func mark() -> Int {
        lock.lock(); defer { lock.unlock() }
        return lines.count
    }

    /// Requests of this kind since `mark` (each logs once as asked, and again as answered).
    func count(_ request: Request, since mark: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        guard mark < lines.count else { return 0 }
        return lines[mark...].filter { $0.contains(request.rawValue) && !$0.contains("_block_invoke") }.count
    }
}

/// replayd's log, running (it takes a moment to start).
@MainActor private func captureStartReplayd() async throws -> CaptureReplayd {
    let r = CaptureReplayd()
    do { try r.start() } catch { throw Skip("couldn't start `log stream` for replayd: \(error)") }
    try await Task.sleep(nanoseconds: 1_500_000_000)
    return r
}

fileprivate extension Ctx {
    /// `count` windows of other apps: fixtures of at most ten windows each (so every one opens on
    /// screen, where Expanse takes it on), once Expanse has them all.
    func captureFixtures(_ name: String, windows count: Int, size: CGSize = CGSize(width: 400, height: 280)) async throws -> [CGWindowID] {
        var ids: [CGWindowID] = []
        var left = count, n = 0
        while left > 0 {
            n += 1
            let f = try await fixture("\(name) \(n)", windows: min(left, 10), size: size)
            ids += f.windows
            left -= min(left, 10)
        }
        try await until("Expanse to take on all \(count) windows", timeout: 30 + Double(count) / 2) {
            let s = try await self.state()
            return ids.allSatisfy { s.window($0) != nil }
        }
        return ids
    }

    /// Puts the windows in a grid on the canvas, far from anything else (the last place commits
    /// them all), and waits for them to get there.
    func captureGrid(_ ids: [CGWindowID], columns: Int, at origin: CGPoint = CGPoint(x: 30000, y: 30000)) async throws {
        let s = try await state()
        let sizes = ids.compactMap { s.window($0)?.canvas.size }
        let cell = CGSize(width: (sizes.map(\.width).max() ?? 640) + 40, height: (sizes.map(\.height).max() ?? 420) + 40)
        func spot(_ i: Int) -> CGPoint {
            CGPoint(x: origin.x + CGFloat(i % columns) * cell.width, y: origin.y + CGFloat(i / columns) * cell.height)
        }
        for (i, id) in ids.enumerated() {
            let p = spot(i)
            link("place", ["id": id, "x": Int(p.x), "y": Int(p.y), "commit": i == ids.count - 1 ? 1 : 0])
            try await pause(0.02)
        }
        try await until("the windows to reach their spots in the grid", timeout: 15) {
            let s = try await self.settle(timeout: 15)
            return ids.enumerated().allSatisfy { i, id in
                guard let f = s.window(id)?.canvas else { return false }
                return abs(f.minX - spot(i).x) < 2 && abs(f.minY - spot(i).y) < 2
            }
        }
    }

    /// Glides to a window at 100% (expanse://focus?id=) and waits until it's in the middle of the view.
    func captureFocus(_ id: CGWindowID) async throws {
        let s = try await state()
        if s.active {
            link("exit")
            try await until("back at 100%", timeout: 8) { let s = try await self.state(); return !s.active && s.idle }
        }
        link("focus", ["id": id])
        try await until("a glide to window \(id)", timeout: 10) {
            let s = try await self.settle()
            guard !s.active, let f = s.window(id)?.canvas else { return false }
            return s.visibleCanvas.contains(CGPoint(x: f.midX, y: f.midY))
        }
    }

    /// The canvas open over the windows (a grid from captureGrid), zoomed out so they all show and
    /// little else: 100% on the window nearest their middle, the canvas opened there, then a zoom
    /// (which keeps the middle of the view where it is).
    func captureView(_ ids: [CGWindowID]) async throws -> ExpanseState {
        let s = try await state()
        let frames = ids.compactMap { id in s.window(id).map { (id, $0.canvas) } }
        guard let first = frames.first else { throw Failure("none of the windows is on the canvas") }
        let bounds = frames.reduce(first.1) { $0.union($1.1) }
        func distance(_ r: CGRect) -> CGFloat { hypot(r.midX - bounds.midX, r.midY - bounds.midY) }
        guard let (mid, middle) = frames.min(by: { distance($0.1) < distance($1.1) }) else { throw Failure("no window to centre on") }
        try await captureFocus(mid)
        link("enter", ["zoomOut": 0])
        try await until("the canvas to open", timeout: 8) { try await self.state().active }
        let open = try await settle()
        let c = CGPoint(x: middle.midX, y: middle.midY)
        let halfWidth = max(c.x - bounds.minX, bounds.maxX - c.x) + 60
        let halfHeight = max(c.y - bounds.minY, bounds.maxY - c.y) + 60
        let scale = min(open.viewport.width / (2 * halfWidth), open.viewport.height / (2 * halfHeight), 0.6)
        link("zoom", ["scale": scale])
        try await pause(0.3)
        let view = try await settle()
        let outside = ids.filter { id in !(view.window(id).map { view.visibleCanvas.intersects($0.canvas) } ?? false) }
        try expect(view.active && outside.isEmpty, "setup: zoomed out over the windows, \(outside.count) of them aren't in view")
        return view
    }

    /// expanse://dump with each window's picture (pic=) and first= as well.
    func capturePics() async throws -> (state: ExpanseState, pics: [CGWindowID: CapturePic]) {
        let mark = log.mark()
        link("dump")
        guard await log.wait(since: mark, timeout: 8, { $0.hasPrefix("dump viewport=") }) != nil else {
            throw Failure("Expanse didn't answer expanse://dump")
        }
        let lines = await log.settled(since: mark, prefix: "dump ")
        var pics: [CGWindowID: CapturePic] = [:]
        for line in lines {
            guard let m = line.firstMatch(of: #/^dump .*\[(\d+)\] sc=.* capturing=(true|false) first=(true|false) pic=(\d+) /#),
                  let id = CGWindowID(m.1) else { continue }
            pics[id] = CapturePic(capturing: m.2 == "true", first: m.3 == "true", pic: Int(m.4) ?? 0)
        }
        return (ExpanseState(lines: lines), pics)
    }

    /// Once back at 100% and still: no window on screen streams, now or over the next second or
    /// so. (macOS badges a streamed window's traffic lights, inside its own window.)
    func captureNoStreamsOnScreen(_ after: String) async throws {
        try await pause(0.3)
        try await until("100% after \(after)", timeout: 10) { let s = try await self.state(); return !s.active && s.idle }
        for _ in 0..<4 {
            let s = try await state()
            let streaming = s.windows.filter { !$0.parked && $0.capturing }
            if !streaming.isEmpty {
                throw Failure("after \(after), at 100%: \(streaming.map { "\($0.app)[\($0.id)]" }.joined(separator: ", ")) on screen still streaming (macOS badges it)")
            }
            try await pause(0.25)
        }
    }

    /// `hand-back waited <n>ms` lines: never more than a quarter of a second (and a frame).
    func captureHandBacks(since mark: Int) throws {
        for line in log.lines(since: mark) {
            guard let m = line.firstMatch(of: #/^hand-back waited (\d+)ms/#), let ms = Int(m.1) else { continue }
            if ms > 300 { throw Failure("a hand-back waited \(ms)ms (never more than a quarter of a second expected): \(line)") }
        }
    }

    /// The next line after `mark` that `match` accepts, waiting up to `timeout` (and stopping when
    /// the case is cancelled); `mark` moves past it.
    func captureNext(after mark: inout Int, timeout: TimeInterval, _ match: (String) -> Bool) async throws -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let lines = log.lines(since: mark)
            if let i = lines.firstIndex(where: match) {
                mark += i + 1
                return lines[i]
            }
            if Date() > deadline { return nil }
            try await pause(0.2)
        }
    }
}
