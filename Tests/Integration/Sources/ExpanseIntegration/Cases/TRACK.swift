import AppKit

/// The manual cases in docs/regression/tracking.md. Other apps' windows (TextEdit, Finder, Preview, Calculator
/// in the catalogue) are fixtures: ⌘-Tab is bringing one forward, the Dock its unhide or restore, ⌘W and ⌘M its
/// own close and minimise. Cases set their windows out in an empty part of the canvas (trackHere), so windows
/// of yours don't get in the way of hops and new windows' spots.
@MainActor enum TRACK {
    static let cases: [Case] = [
        Case("TRACK-04", "⌘-Tab or the Dock to an off-screen window glides to it") { t in
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let f = try await t.fixture("Track04")
            guard let x = f.windows.first, let pid = f.pid else { throw Failure("the fixture has no window") }
            try await t.trackOnCanvas([x], "TextEdit's stand-in")
            let mine = try await t.window("TRACK-04 Mine")
            try await t.trackPlace([(mine.id, trackAt(0, 0)), (x, trackAt(7000, 3000))])
            try await t.trackShow(mine.id)
            let parked = try await t.state().window(x)?.parked == true
            try t.expect(parked, "the fixture's window should start out of view (parked)")
            // Another app in front, then ⌘-Tab to the fixture.
            mine.focus()
            try await t.pause(0.5)
            let mark = t.log.mark()
            await trackActivate(f)
            let line = try await t.trackLine("focus-settled glide to ", "[\(x)]", since: mark, timeout: 5)
            try t.expect(line.contains("[\(x)]: parked"), "the glide should start from the parked window: \(line)")
            try await t.until("the fixture in front with the keyboard", timeout: 5) {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && trackFrontWindow() == x
            }
            try await t.trackViewOn(x, "the view centred on the fixture's window")
        },
        Case("TRACK-05", "Clicking a partly visible window at 100% centres it, and typing goes to it") { t in
            try t.needsInput()
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let a = try await t.window("TRACK-05 A")
            let b = try await t.window("TRACK-05 B")
            let field = trackTypingField(b)
            try await t.trackPlace([(a.id, trackAt(0, 0)), (b.id, trackAt(3000, 0))])
            // At 100% after a glide, not after panning.
            let s = try await t.trackShow(a.id)
            // B partly off the right edge: 300pt of it showing, near the top, away from the minimap.
            let v = s.visibleCanvas
            try await t.trackPlace([(b.id, CGPoint(x: (v.maxX - 300).rounded(), y: (v.minY + 60).rounded()))])
            try await t.until("B partly on screen at the right edge") {
                guard let r = b.real else { return false }
                return r.maxX > t.screen.maxX && t.screen.maxX - r.minX >= 250
            }
            guard let r = b.real else { throw Failure("B isn't on screen") }
            a.focus()
            try await t.pause(0.5)
            let mark = t.log.mark()
            Input.click(at: CGPoint(x: t.screen.maxX - 150, y: r.midY))
            for k: Input.Key in [.a, .c, .a, .w] { Input.key(k) }
            try await t.trackLine("glide to ", "[\(b.id)]", since: mark, timeout: 4)
            try await t.until("every letter typed into B", timeout: 4) { field.stringValue == "acaw" }
            try t.expect(NSApp.isActive && b.window.isKeyWindow, "B should keep the keyboard through the glide (it has “\(field.stringValue)”)")
            try await t.trackViewOn(b.id, "the view centred on B")
        },
        Case("TRACK-06", "Moving a window yourself at 100% is followed") { t in
            try t.needsInput()
            let f = try await t.fixture("Track06")
            guard let x = f.windows.first else { throw Failure("the fixture has no window") }
            try await t.trackOnCanvas([x], "the fixture's window")
            let other = try await t.window("TRACK-06 Other")
            try await t.trackPlace([(x, trackAt(0, 0)), (other.id, trackAt(700, 0))])
            let s0 = try await t.trackShow(x)
            guard let c0 = s0.window(x)?.canvas, let o0 = s0.window(other.id)?.canvas, let r0 = realFrame(x) else {
                throw Failure("the windows aren't set out")
            }
            // Drag it by its title bar.
            let d = CGVector(dx: -160, dy: 90)
            let grab = CGPoint(x: r0.minX + r0.width * 0.65, y: r0.minY + 12)
            let mark = t.log.mark()
            await trackDrag([grab, CGPoint(x: grab.x + d.dx, y: grab.y + d.dy)], seconds: 0.6)
            try await t.trackLine("follow ", "[\(x)]", since: mark, timeout: 3)
            // macOS moves the window as far as the drag carried it, which can be a little short
            // of the pointer's path: the canvas must follow wherever it landed.
            try await t.pause(1.5)
            guard let r1 = realFrame(x) else { throw Failure("the window is gone") }
            try t.expectNear(r1.origin, CGPoint(x: r0.minX + d.dx, y: r0.minY + d.dy), within: 24, "the drag should have moved the window (it mustn't be put back)")
            let moved = CGPoint(x: c0.minX + r1.minX - r0.minX, y: c0.minY + r1.minY - r0.minY)
            try await t.until("the canvas to follow the move", timeout: 4) {
                guard let c = try await t.state().window(x)?.canvas else { return false }
                return hypot(c.minX - moved.x, c.minY - moved.y) <= 3
            }
            t.link("enter")
            let out = try await t.settle()
            try t.expect(out.active, "⌥` should zoom out")
            guard let c = out.window(x)?.canvas, let o = out.window(other.id)?.canvas else { throw Failure("a window left the canvas") }
            try t.expectNear(c.origin, moved, within: 3, "the moved window on the canvas")
            try t.expectNear(o, o0, within: 1, "the other window, which wasn't moved")
        },
        Case("TRACK-07", "A closed window leaves the canvas") { t in
            let a = try await t.window("TRACK-07 A")
            try await t.trackPlace([(a.id, trackAt(0, 0))])
            try await t.trackShow(a.id)
            let mark = t.log.mark()
            a.close()
            try await t.until("A off the canvas within a moment", timeout: 3) { try await t.state().window(a.id) == nil }
            try await t.trackLine("dropped ", "[\(a.id)]: not in the window list", since: mark, timeout: 2)
            t.link("enter")
            let s = try await t.settle()
            try t.expect(s.window(a.id) == nil, "the closed window is on the canvas again")
        },
        Case("TRACK-10", "A minimised or hidden window comes back to its own spot") { t in
            let f = try await t.fixture("Track10")
            guard let x = f.windows.first else { throw Failure("the fixture has no window") }
            try await t.trackOnCanvas([x], "TextEdit's stand-in")
            try await t.trackPlace([(x, trackAt(0, 0))])
            let s0 = try await t.trackShow(x)
            guard let spot = s0.window(x)?.canvas else { throw Failure("the window isn't on the canvas") }
            // ⌘M, then the window in the Dock (which brings its app forward too).
            try await f.minimise(0)
            try await t.trackOffCanvas(x, "the minimised window")
            await trackActivate(f)
            try await f.send("restore", ["index": "0"])
            try await t.trackOnCanvas([x], "the window back from the Dock")
            try await t.trackSameSpot(x, spot, "after ⌘M and the Dock")
            // ⌘H, then ⌘-Tab back.
            f.hide()
            try await t.trackOffCanvas(x, "the hidden app's window")
            await trackActivate(f)
            f.unhide()
            try await t.trackOnCanvas([x], "the window back after ⌘-Tab")
            try await t.trackSameSpot(x, spot, "after ⌘H and ⌘-Tab")
            t.link("enter")
            let out = try await t.settle()
            guard let c = out.window(x)?.canvas else { throw Failure("the window isn't on the canvas") }
            try t.expectNear(c, spot, within: 1, "its spot, zoomed out")
        },
        Case("TRACK-11", "A stranded window in the parking corner is brought into view") { t in
            // Paused, Expanse leaves windows alone (and has saved the layout): A is put in the parking corner, as a
            // crash leaves windows, and Expanse quit there. It then launches with no layout to say where A belongs.
            let a = try await t.window("TRACK-11 A", CGRect(x: 300, y: 260, width: 520, height: 360))
            t.link("pause")
            try await t.until("paused") { try await t.state().paused }
            guard let screen = NSScreen.screens.first else { throw Skip("no display") }
            let full = screen.frame, usable = screen.visibleFrame
            // As CanvasController.parkingCorner works it out.
            let corner = CGPoint(x: full.width - max(0, full.maxX - usable.maxX) - 40, y: full.height - max(0, usable.minY - full.minY) - 80)
            a.setFrame(CGRect(x: corner.x + 12, y: corner.y + 30, width: 520, height: 360))
            try await t.pause(0.5)
            guard let stranded = a.real, stranded.minX >= corner.x, stranded.minY >= corner.y else {
                t.link("resume")
                throw Skip("macOS wouldn't leave a window in the parking corner (it put it at \(a.real.map { NSStringFromRect($0) } ?? "?"))")
            }
            let folder = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Expanse")
            let layout = folder.appendingPathComponent("layout.json"), aside = folder.appendingPathComponent("layout.json.track11")
            try await t.quitExpanse()
            try? FileManager.default.removeItem(at: aside)
            let hadLayout = (try? FileManager.default.moveItem(at: layout, to: aside)) != nil
            // Puts your layout back: quit (windows go back where macOS has them), the saved layout back, launch.
            func putBack() async {
                try? await t.quitExpanse()
                if hadLayout {
                    if FileManager.default.fileExists(atPath: layout.path) {
                        _ = try? FileManager.default.replaceItemAt(layout, withItemAt: aside)
                    } else {
                        try? FileManager.default.moveItem(at: aside, to: layout)
                    }
                }
                try? await t.launchExpanse()
            }
            do {
                try await t.launchExpanse()
                let vp = try await t.state().viewport
                let want = CGPoint(x: vp.midX - stranded.width / 2, y: vp.minY + 40)
                try await t.until("A out of the corner, centred 40pt below the top of the usable screen", timeout: 10) {
                    guard let r = a.real else { return false }
                    return hypot(r.minX - want.x, r.minY - want.y) <= 2
                }
                try await t.until("A on the canvas") { try await t.state().window(a.id) != nil }
                guard let r = a.real else { throw Failure("A is gone") }
                try t.expect(t.screen.contains(r), "A should be wholly in view, not at \(NSStringFromRect(r))")
            } catch {
                await putBack()
                throw error
            }
            await putBack()
        },
        Case("TRACK-12", "Opening a document centres its new window, not the old one") { t in
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let f = try await t.fixture("Track12")
            guard let first = f.windows.first else { throw Failure("the fixture has no window") }
            try await t.trackOnCanvas([first], "the app's first window")
            // A window filling the screen, so the new one goes off screen; the app's first window out of view.
            let vp = try await t.state().viewport
            let big = try await t.window("TRACK-12 Big", CGRect(x: 40, y: vp.minY + 40, width: vp.width - 80, height: vp.height - 140))
            try await t.trackPlace([(big.id, trackAt(0, 0)), (first, trackAt(0, 6000))])
            try await t.trackShow(big.id)
            big.focus()
            try await t.pause(0.5)
            let mark = t.log.mark()
            // Opening a document: the app comes forward, focus on its old window for a moment, then its new one.
            await trackActivate(f)
            try await f.openWindow()
            guard let new = f.windows.last, new != first else { throw Failure("the app didn't open a second window") }
            try await t.trackLine("glide to ", "[\(new)]", since: mark, timeout: 6)
            try await t.trackViewOn(new, "the view centred on the new window")
            try await t.pause(1)
            let wrong = t.trackLines("glide to ", "[\(first)]", since: mark)
            try t.expect(wrong.isEmpty, "Expanse glided to the old window: \(wrong.first ?? "")")
        },
        Case("TRACK-13", "A window that comes back by itself returns quietly to its spot") { t in
            let f = try await t.fixture("Track13")
            guard let x = f.windows.first else { throw Failure("the fixture has no window") }
            try await t.trackOnCanvas([x], "TextEdit's stand-in")
            let front = try await t.window("TRACK-13 Front")
            try await t.trackPlace([(front.id, trackAt(0, 0)), (x, trackAt(7000, -3000))])
            try await t.trackShow(front.id)
            let before = try await t.settle()
            guard let spot = before.window(x)?.canvas, before.window(x)?.parked == true else {
                throw Failure("TextEdit's stand-in should start out of view (parked)")
            }
            front.focus()
            try await t.pause(0.5)
            // Hide Others, then Show All: it goes and comes back without you asking for it.
            let mark = t.log.mark()
            f.hide()
            try await t.trackLine("dropped ", "[\(x)]", since: mark, timeout: 6)
            f.unhide()
            try await t.trackLine("tracking ", "[\(x)]", since: mark, timeout: 6)
            try await t.pause(1.5)
            let frontmost = NSWorkspace.shared.frontmostApplication
            try t.expect(frontmost?.processIdentifier == getpid(), "Expanse Tests (Finder's part) should stay in front, not \(frontmost?.localizedName ?? "-")")
            let after = try await t.settle()
            try t.expectNear(after.camera, before.camera, within: 1, "the view")
            guard let w = after.window(x) else { throw Failure("the window isn't back on the canvas") }
            try t.expectNear(w.canvas, spot, within: 1, "its spot")
            try t.expect(w.parked, "it should still be out of view")
            let glides = t.trackLines("glide to ", since: mark)
            try t.expect(glides.isEmpty, "something glided: \(glides.first ?? "")")
            t.link("enter")
            let out = try await t.settle()
            try t.expectNear(out.window(x)?.canvas ?? .zero, spot, within: 1, "its spot, zoomed out")
        },
        Case("TRACK-14", "Apple's system prompts stay above app windows", .guided) { t in
            let already = Set(trackSystemPrompts())
            let mark = t.log.mark()
            try await t.ask("Bring up a prompt from macOS itself, not an app's alert. For example, in Terminal run   osascript -e 'do shell script \"true\" with administrator privileges'   and leave the password prompt open. Click Done once it's showing.")
            try await t.pause(0.5)
            guard let prompt = trackSystemPrompts().first(where: { !already.contains($0) }), let pr = realFrame(prompt) else {
                throw Skip("no new prompt of a macOS background process among app windows (this case covers those; prompts at dialog level are another)")
            }
            try await t.trackLine("raised system prompt [\(prompt)]", since: mark, timeout: 8)
            // A large window of another app, in front of where the prompt is, and one to its right to hop to.
            let big = try await t.window("TRACK-14 Big", CGRect(x: 100, y: 120, width: 1000, height: 640))
            let right = try await t.window("TRACK-14 Right")
            let s = try await t.settle()
            let at = CGPoint(x: (s.camera.x + pr.midX - 500 - s.viewport.minX).rounded(),
                             y: (s.camera.y + max(pr.midY - 320, s.viewport.minY + 10) - s.viewport.minY).rounded())
            try await t.trackPlace([(big.id, at), (right.id, CGPoint(x: at.x + 1040, y: at.y))])
            // Click it so it comes in front.
            var since = t.log.mark()
            big.focus()
            try await t.trackLine("raised system prompt [\(prompt)]", since: since, timeout: 6)
            try await t.until("the prompt above the big window", timeout: 3) { trackInFront(prompt, of: [big.id]) }
            // Hop with ⌃→.
            since = t.log.mark()
            t.link("nav", ["dir": "right"])
            try await t.trackLine("navigate to ", "[\(right.id)]", since: since, timeout: 4)
            try await t.trackLine("raised system prompt [\(prompt)]", since: since, timeout: 6)
            try await t.until("the prompt above app windows after the hop", timeout: 3) { trackInFront(prompt, of: [big.id, right.id]) }
            try await t.ask("Cancel the prompt now, then click Done.")
        },
        Case("TRACK-15", "A window back from hiding keeps its macOS spot and chosen size") { t in
            let chosen = CGSize(width: 1000, height: 700)
            let vp = try await t.state().viewport
            guard vp.width >= chosen.width + 80, vp.height >= chosen.height + 80 else {
                throw Skip("needs a display with room for a 1000×700 window (this one's \(Int(vp.width))×\(Int(vp.height)) below the menu bar)")
            }
            // Where macOS has it before Expanse has anything to do with it.
            let a = try await t.window("TRACK-15 A", CGRect(x: 260, y: 220, width: 600, height: 380), managed: false)
            // The window server lists a new window a moment after it's made (before Expanse moves it).
            var first: CGRect?
            try await t.until("A on screen", timeout: 3) { first = a.real; return first != nil }
            guard let macOS = first else { throw Failure("A isn't on screen") }
            try await t.until("Expanse to take on A", timeout: 10) { try await t.state().window(a.id) != nil }
            try await t.trackPlace([(a.id, trackAt(0, 0))])
            try await t.trackShow(a.id)
            // The size you chose: 1000×700.
            let mark = t.log.mark()
            t.link("prefer", ["id": a.id, "w": Int(chosen.width), "h": Int(chosen.height)])
            try await t.trackLine("preferred size ", "[\(a.id)] = {1000, 700}", since: mark)
            if let r = a.real { a.setFrame(CGRect(origin: r.origin, size: chosen)) }
            try await t.until("A at 1000×700", timeout: 5) { try await trackSized(t, a.id, chosen) }
            // 1: minimise, and back from the Dock.
            a.minimise()
            try await t.trackOffCanvas(a.id, "minimised A")
            a.restore()
            try await t.trackOnCanvas([a.id], "A back from the Dock")
            // 2: a smaller display, and back (A the window you're in, which a display change keeps in view).
            a.focus()
            try await t.pause(0.5)
            t.link("screen", ["w": 900, "h": 600])
            try await t.until("A shrunk for the smaller display", timeout: 10) {
                (try await t.state().window(a.id)?.canvas.width ?? 0) < chosen.width - 1
            }
            t.link("screen")
            try await t.until("A grown back to the 1000×700 you chose", timeout: 12) {
                guard try await trackSized(t, a.id, chosen), let r = a.real else { return false }
                return abs(r.width - chosen.width) <= 1 && abs(r.height - chosen.height) <= 1
            }
            // 3: quit Expanse; A goes back where macOS had it, at that size.
            try await t.quitExpanse()
            do {
                try await t.until("A back where macOS had it, at its size then", timeout: 6) {
                    guard let r = a.real else { return false }
                    return max(abs(r.minX - macOS.minX), abs(r.minY - macOS.minY), abs(r.width - macOS.width), abs(r.height - macOS.height)) <= 2
                }
            } catch {
                try? await t.launchExpanse()
                throw Failure("after quitting, A is at \(a.real.map { NSStringFromRect($0) } ?? "?"), not where macOS had it: \(NSStringFromRect(macOS))")
            }
            try await t.launchExpanse()
        },
        Case("TRACK-17", "A frozen app can't freeze Expanse") { t in
            let f = try await t.fixture("Track17")
            guard let x = f.windows.first, let pid = f.pid else { throw Failure("the fixture has no window") }
            try await t.trackOnCanvas([x], "TextEdit's stand-in")
            let mine = try await t.window("TRACK-17 Mine")
            let other = try await t.window("TRACK-17 Other")
            try await t.trackPlace([(x, trackAt(0, 0)), (mine.id, trackAt(700, 0)), (other.id, trackAt(1400, 0))])
            try await t.trackShow(mine.id)
            // kill -STOP. Expanse's dump asks every app where its windows are, so until it's going again, this
            // case watches Expanse through its log and the window server instead.
            kill(pid, SIGSTOP)
            var hung = true
            defer { if hung { kill(pid, SIGCONT) } }
            try await trackStillAnswers(t, "the app hung")
            t.link("enter")
            try await t.until("the canvas to open", timeout: 4) { trackCanvasUp(t) }
            try await trackStillAnswers(t, "zooming out")
            t.link("nav", ["dir": "left"])
            try await trackStillAnswers(t, "a hop")
            let p = trackAt(1400, 500)
            t.link("place", ["id": other.id, "x": Int(p.x), "y": Int(p.y), "commit": 0])
            try await trackStillAnswers(t, "moving a window")
            // Click the hung app's window, which leaves the canvas.
            t.link("focus", ["id": x])
            try await t.until("the canvas to go when the hung app's window is picked (the overlay mustn't stick)", timeout: 5) { !trackCanvasUp(t) }
            try await trackStillAnswers(t, "picking the hung app’s window")
            t.link("enter")
            try await t.until("the canvas to open again", timeout: 4) { trackCanvasUp(t) }
            t.link("exit")
            try await t.until("the canvas to go again", timeout: 5) { !trackCanvasUp(t) }
            try await trackStillAnswers(t, "leaving the canvas")
            // kill -CONT.
            kill(pid, SIGCONT)
            hung = false
            try await t.pause(1)
            let s = try await t.settle()
            try t.expect(!s.active, "the canvas should be closed")
            try t.expect(s.window(x) != nil, "the app's window should still be on the canvas")
        },
        Case("TRACK-21", "Dragging a real window at 100% is followed smoothly") { t in
            try t.needsInput()
            let f = try await t.fixture("Track21")
            guard let x = f.windows.first else { throw Failure("the fixture has no window") }
            try await t.trackOnCanvas([x], "the fixture's window")
            try await t.trackPlace([(x, trackAt(0, 0))])
            let s0 = try await t.trackShow(x)
            guard let c0 = s0.window(x)?.canvas, let r0 = realFrame(x) else { throw Failure("the window isn't set out") }
            // Around the screen by its title bar for 5 seconds, then dropped.
            let g = CGPoint(x: r0.minX + r0.width * 0.65, y: r0.minY + 12)
            let path = [g, CGPoint(x: g.x + 260, y: g.y), CGPoint(x: g.x + 260, y: g.y + 180), CGPoint(x: g.x - 120, y: g.y + 180),
                        CGPoint(x: g.x - 120, y: g.y - 60), CGPoint(x: g.x + 100, y: g.y + 120)]
            let drop = CGVector(dx: 100, dy: 120)
            var worst: CGFloat = 0
            var n = 0
            let mark = t.log.mark()
            let began = Date()
            let events = await trackDrag(path, seconds: 5) { p in
                n += 1
                guard n % 20 == 0, let r = realFrame(x) else { return }
                worst = max(worst, hypot(r.minX - (r0.minX + p.x - g.x), r.minY - (r0.minY + p.y - g.y)))
            }
            let took = Date().timeIntervalSince(began)
            try await t.pause(0.6)
            // At most one look at the window per 50ms of dragging, give or take the ends.
            let follows = t.trackLines("follow ", "[\(x)]", since: mark)
            try t.expect(!follows.isEmpty, "the drag wasn't followed (no “follow …[\(x)]” lines)")
            try t.expect(follows.count <= Int(took / 0.05) + 10,
                         "\(follows.count) follow lines for \(events) drag events in \(String(format: "%.1f", took))s: the window was looked at more often than every 50ms")
            try t.expect(worst <= 60, "the window fell \(Int(worst))pt behind the pointer during the drag: something moved it")
            guard let r1 = realFrame(x) else { throw Failure("the window is gone") }
            // macOS can leave the window a few points short of the pointer's path (see TRACK-06).
            try t.expectNear(r1.origin, CGPoint(x: r0.minX + drop.dx, y: r0.minY + drop.dy), within: 24, "where it was dropped")
            try await t.pause(1.5)
            let putBack = t.trackLines("[\(x)]", "putting it back", since: mark)
            try t.expect(putBack.isEmpty, "Expanse took the drag for an app's move: \(putBack.first ?? "")")
            guard let r2 = realFrame(x) else { throw Failure("the window is gone") }
            try t.expectNear(r2.origin, r1.origin, within: 1, "the dropped window, a moment later (it mustn't be moved again)")
            t.link("enter")
            let out = try await t.settle()
            guard let c = out.window(x)?.canvas else { throw Failure("the window left the canvas") }
            try t.expectNear(c.origin, CGPoint(x: c0.minX + r1.minX - r0.minX, y: c0.minY + r1.minY - r0.minY), within: 3,
                             "the window on the canvas (where it was dropped)")
        },
        Case("TRACK-23", "Window scans don't ask apps about windows already in place") { t in
            // Twenty windows of another app on top of yours (fifty in the catalogue; the case's limit is 90s).
            let f = try await t.fixture("Track23", windows: 20, size: CGSize(width: 400, height: 300))
            let onScreen = f.windows.filter { id in realFrame(id).map { t.screen.intersects($0) } ?? false }
            try await t.trackOnCanvas(onScreen, "the fixture's windows", timeout: 30)
            // Until they're all placed: no window placed or glided to for 3 seconds.
            var quietSince = Date()
            var seen = t.log.mark()
            try await t.until("the new windows to settle", timeout: 25) {
                let now = t.log.mark()
                if !t.trackLines("placed new window", since: seen).isEmpty || !t.trackLines("glide to ", since: seen).isEmpty {
                    quietSince = Date()
                }
                seen = now
                return Date().timeIntervalSince(quietSince) >= 3
            }
            // Idle (40s here, 2 minutes in the catalogue): eight regular scans.
            let mark = t.log.mark()
            try await t.pause(40)
            for line in t.trackLines("slow: window scan took", since: mark) {
                let calls = line.firstMatch(of: #/(\d+) Accessibility calls/#).flatMap { Int($0.1) } ?? 0
                try t.expect(calls <= 4, "a scan asked apps about windows already in place: \(line)")
            }
        },
        Case("TRACK-24", "A newly launched app's first window is taken on in about a second") { t in
            // (Auto-centre off, a new window only goes in a free spot that's in view; this one's not.)
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let work = try await t.window("TRACK-24 Work")
            try await t.trackPlace([(work.id, trackAt(0, 0))])
            try await t.trackShow(work.id)
            work.focus()
            try await t.pause(0.5)
            let mark = t.log.mark()
            // An app that isn't running yet (a name of its own, so no saved spot is its).
            let f = try await t.fixture("Track24-\(Int.random(in: 1000...9999))")
            let opened = Date()
            guard let x = f.windows.first else { throw Failure("the new app has no window") }
            let line = try await t.trackLine("placed new window ", since: mark, timeout: 5)
            let took = Date().timeIntervalSince(opened)
            try t.expect(took <= 2.5, "the new app's window was taken on \(String(format: "%.1f", took))s after it opened (about a second expected)")
            try t.expect(line.contains("beside ") && line.contains("[\(work.id)]"), "it should go beside the window you're in (TRACK-24 Work): \(line)")
            try await t.trackOnCanvas([x], "the new app's window")
            let s = try await t.settle()
            guard let spot = s.window(x)?.canvas, let w = s.window(work.id)?.canvas else { throw Failure("a window left the canvas") }
            try t.expect(trackBeside(spot, w), "the new window at \(NSStringFromRect(spot)) should be beside TRACK-24 Work at \(NSStringFromRect(w))")
            let overlap = s.windows.first { $0.id != x && $0.canvas.intersects(spot) }
            try t.expect(overlap == nil, "the new window should be in a free spot, but it overlaps \(overlap?.app ?? "")[\(overlap?.id ?? 0)]")
        },
        Case("TRACK-25", "A window restored from the Dock is back straight away") { t in
            let a = try await t.window("TRACK-25 A")
            try await t.trackPlace([(a.id, trackAt(0, 0))])
            let s0 = try await t.trackShow(a.id)
            guard let spot = s0.window(a.id)?.canvas else { throw Failure("A isn't on the canvas") }
            a.minimise()
            try await t.trackOffCanvas(a.id, "the minimised window")
            try await t.pause(1)
            let mark = t.log.mark()
            let restored = Date()
            a.restore()
            try await t.trackLine("tracking ", "[\(a.id)]", since: mark, timeout: 6)
            let took = Date().timeIntervalSince(restored)
            try t.expect(took <= 2, "A was back on the canvas \(String(format: "%.1f", took))s after the restore (straight away expected, not at the next regular scan)")
            // ⌥` at once.
            t.link("enter")
            let s = try await t.settle()
            guard let c = s.window(a.id)?.canvas else { throw Failure("A isn't on the canvas") }
            try t.expectNear(c, spot, within: 1, "A's spot")
        },
        Case("TRACK-27", "Switching apps quickly doesn't pull you back") { t in
            try t.needsInput()
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let fa = try await t.fixture("Track27A")
            let fb = try await t.fixture("Track27B")
            guard let a = fa.windows.first, let b = fb.windows.first, let pa = fa.pid, let pb = fb.pid else {
                throw Failure("a fixture has no window")
            }
            try await t.trackOnCanvas([a, b], "A's and B's windows")
            let mine = try await t.window("TRACK-27 Mine")
            let target = try await t.window("TRACK-27 Target")
            // You're far left; A with the hop's target just right of it; B far below.
            try await t.trackPlace([(mine.id, trackAt(0, 0)), (a, trackAt(8000, 0)), (target.id, trackAt(8700, 0)), (b, trackAt(8000, 4000))])
            // Expanse knows each app's window, as it does once you've used them.
            try await t.trackShow(a)
            try await t.trackShow(b)
            try await t.trackShow(mine.id)
            // A is slow to say which window has focus (stopped for a moment), so its answer comes after you've moved on.
            var stopped = false
            defer { if stopped { kill(pa, SIGCONT) } }
            // 1: ⌘-Tab to A and straight away to B.
            mine.focus()
            try await t.pause(0.5)
            var mark = t.log.mark()
            trackFront(pa)
            try await t.pause(0.04)   // in front, and Expanse told; it asks which window 0.12s on
            kill(pa, SIGSTOP)
            stopped = true
            try await t.pause(0.35)
            trackFront(pb)
            try await t.trackLine("glide to ", "[\(b)]", since: mark, timeout: 5)
            try await t.pause(0.6)
            kill(pa, SIGCONT)
            stopped = false
            try await t.pause(1.5)
            var back = t.trackLines("glide to ", "[\(a)]", since: mark)
            try t.expect(back.isEmpty, "1: Expanse glided back to A after the switch to B: \(back.first ?? "")")
            try await t.trackViewOn(b, "1: the view ending on B")
            // 2: ⌘-Tab to A and straight away ⌃→.
            try await t.trackShow(mine.id)
            mine.focus()
            try await t.pause(0.5)
            mark = t.log.mark()
            trackFront(pa)
            try await t.pause(0.04)   // in front, and Expanse told; it asks which window 0.12s on
            kill(pa, SIGSTOP)
            stopped = true
            try await t.pause(0.3)
            Input.key(.right, .maskControl)
            try await t.trackLine("navigate to ", "[\(target.id)]", since: mark, timeout: 4)
            try await t.pause(0.6)
            kill(pa, SIGCONT)
            stopped = false
            try await t.pause(1.5)
            back = t.trackLines("glide to ", "[\(a)]", since: mark)
            try t.expect(back.isEmpty, "2: Expanse glided back to A after the hop: \(back.first ?? "")")
            try await t.trackViewOn(target.id, "2: the view ending on the hop's target")
        },
        Case("TRACK-31", "Opening many windows at once doesn't freeze the canvas") { t in
            let ws = try await t.row(["TRACK-31 A", "TRACK-31 B", "TRACK-31 C"], origin: trackHere)
            let f = try await t.fixture("Track31", windows: 1, size: CGSize(width: 400, height: 300))
            try await t.trackOnCanvas(f.windows, "the fixture's window")
            try await t.trackShow(ws[1].id)
            ws[1].focus()
            try await t.pause(0.5)
            // ⌘N ten times, as fast as the app takes them.
            for _ in 0..<10 {
                DistributedNotificationCenter.default().postNotificationName(Fixture.commandNote, object: f.name, userInfo: ["do": "open"],
                                                                             deliverImmediately: true)
            }
            // Straight away: hops, ⌥`, a zoom (for the pinch). Each must be taken at once: Expanse logs a link the
            // moment its main thread gets it, so a stall shows as a late line.
            for dir in ["right", "left", "left", "right", "right", "left"] {
                try await trackAnswers(t, "nav", ["dir": dir], within: 0.75)
                try await t.pause(0.12)
            }
            try await trackAnswers(t, "toggle", [:], within: 0.75)
            try await t.until("the canvas open", timeout: 4) { try await t.settle().active }
            try await trackAnswers(t, "zoom", ["scale": 0.3], within: 0.75)
            try await t.until("the zoom", timeout: 4) { let s = try await t.settle(); return abs(s.scale - 0.3) < 0.02 }
            try await t.until("all ten new windows open", timeout: 4) { f.windows.count >= 11 }
            t.link("exit")
            try await t.until("back at 100%") { try await !t.settle().active }
        },
        Case("TRACK-35", "Closing a window keeps the view where it is") { t in
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let f = try await t.fixture("Track35", windows: 2)
            guard f.windows.count == 2, let pid = f.pid else { throw Failure("the fixture should have two windows") }
            let f1 = f.windows[0], f2 = f.windows[1]
            try await t.trackOnCanvas([f1, f2], "the app's two windows")
            try await t.trackPlace([(f1, trackAt(0, 0)), (f2, trackAt(8000, 3000))])
            // F1 in view, with the keyboard; F2 far off screen.
            try await t.trackShow(f1)
            try await t.until("F1 with the keyboard", timeout: 4) { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
            try await t.pause(0.5)
            let before = try await t.settle()
            let mark = t.log.mark()
            // ⌘W in F1; macOS gives F2 the keyboard.
            try await f.closeWindow(0)
            try await t.trackLine("[\(f2)] got focus after a window of its app closed; the view stays", since: mark, timeout: 4)
            try await t.pause(2)
            let after = try await t.settle()
            try t.expectNear(after.camera, before.camera, within: 1, "the view after F1 closed")
            let glides = t.trackLines("glide to ", "[\(f2)]", since: mark)
            try t.expect(glides.isEmpty, "Expanse glided to F2 after F1 closed: \(glides.first ?? "")")
            try t.expect(after.window(f1) == nil, "F1 should be off the canvas")
            // Afterwards, a switch of yours to the app is followed as usual: away to Finder, and back.
            guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
                throw Skip("the rest passed; switching back needs Finder running")
            }
            await bringForward(finder)
            try await t.pause(1.5)
            let since = t.log.mark()
            await trackActivate(f)
            try await t.trackLine("glide to ", "[\(f2)]", since: since, timeout: 8)
        },
        Case("TRACK-36", "Hiding an app, then ⌘-Tab to it, glides to its window") { t in
            let f = try await t.fixture("Track36")
            guard let x = f.windows.first else { throw Failure("the fixture has no window") }
            try await t.trackOnCanvas([x], "TextEdit's stand-in")
            let mine = try await t.window("TRACK-36 Mine")
            try await t.trackPlace([(x, trackAt(0, 0)), (mine.id, trackAt(6000, 0))])
            // Glide into it, ⌘H, hop away so its spot is off screen, ⌘-Tab back to it.
            try await t.trackShow(x)
            f.hide()
            try await t.trackOffCanvas(x, "the hidden app's window")
            try await t.trackShow(mine.id)
            var mark = t.log.mark()
            // ⌘-Tab shows the app and brings it forward together (a hidden app can't be brought forward).
            f.unhide()
            await trackActivate(f)
            try await t.trackLine("glide to ", "[\(x)]", since: mark, timeout: 8)
            try await t.trackViewOn(x, "the view on the app's window")
            // Hidden while its window is on screen: back, it just reappears, and the view stays. Mine, small, below
            // it and in view, has the keyboard, so hiding the app (in the background) moves no focus. (With no
            // window of ours in front, focus would go to some other app's window, and rightly glide there.)
            let xs = try await t.state()
            guard let xf = xs.window(x)?.canvas else { throw Failure("the app's window isn't on the canvas") }
            mine.setFrame(CGRect(origin: mine.real?.origin ?? .zero, size: CGSize(width: 300, height: 180)))
            try await t.trackPlace([(mine.id, CGPoint(x: xf.minX, y: xf.maxY + 20))])
            try await t.trackShow(x)
            mine.focus()
            try await t.until("Mine with the keyboard", timeout: 3) {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() && mine.window?.isKeyWindow == true
            }
            try await t.pause(1)
            let inView = try await t.state()
            guard let mf = inView.window(mine.id)?.canvas, inView.visibleCanvas.contains(mf), let xv = inView.window(x)?.canvas,
                  inView.visibleCanvas.contains(xv) else { throw Failure("the app's window and Mine should both be in view") }
            f.hide()
            try await t.trackOffCanvas(x, "the hidden app's window")
            let before = try await t.settle()
            mark = t.log.mark()
            f.unhide()
            await trackActivate(f)
            try await t.trackOnCanvas([x], "the app's window back")
            try await t.pause(1.5)
            let after = try await t.settle()
            try t.expectNear(after.camera, before.camera, within: 1, "the view, with the window already on screen")
            let glides = t.trackLines("glide to ", "[\(x)]", since: mark)
            try t.expect(glides.isEmpty, "the window was on screen, yet Expanse glided: \(glides.first ?? "")")
        },
        Case("TRACK-37", "A window brought back from the Dock glides into view") { t in
            let f = try await t.fixture("Track37")
            guard let x = f.windows.first else { throw Failure("the fixture has no window") }
            try await t.trackOnCanvas([x], "TextEdit's stand-in")
            let mine = try await t.window("TRACK-37 Mine")
            try await t.trackPlace([(x, trackAt(0, 0)), (mine.id, trackAt(6000, 0))])
            // Glide into it, ⌘M, hop away, then the window in the Dock (which brings its app forward too).
            let s0 = try await t.trackShow(x)
            guard let spot = s0.window(x)?.canvas else { throw Failure("the window isn't on the canvas") }
            try await f.minimise(0)
            try await t.trackOffCanvas(x, "the minimised window")
            try await t.trackShow(mine.id)
            let mark = t.log.mark()
            // The Dock restores the window and brings its app forward together.
            try await f.send("restore", ["index": "0"])
            await trackActivate(f)
            try await t.trackLine("glide to ", "[\(x)]", since: mark, timeout: 8)
            try await t.trackViewOn(x, "the view on the restored window")
            let s = try await t.state()
            try t.expectNear(s.window(x)?.canvas ?? .zero, spot, within: 1, "its own spot")
        },
        Case("TRACK-38", "Windows back after a Space switch come back quietly", .guided) { t in
            let a = try await t.window("TRACK-38 A")
            let b = try await t.window("TRACK-38 B")
            try await t.trackPlace([(a.id, trackAt(0, 0)), (b.id, trackAt(6000, 0))])
            try await t.trackShow(a.id)
            a.focus()
            try await t.pause(0.5)
            var before = try await t.settle()
            var mark = t.log.mark()
            try await t.ask("Go to Desktop 2 with Mission Control (not ⌃→, which is Expanse's), wait there a few seconds, then come back to this desktop the same way. Click Done once you're back.")
            try await trackCameBackQuietly(t, [a.id, b.id], before, since: mark, "after the Space switch")
            guard t.displayCount > 1 else { throw Skip("the Space switch passed; the display half needs an external display") }
            a.focus()
            try await t.pause(0.5)
            before = try await t.settle()
            mark = t.log.mark()
            try await t.ask("Unplug the external display and wait for the windows to settle, then plug it back in and wait again. Click Done once it's back.")
            try await trackCameBackQuietly(t, [a.id, b.id], before, since: mark, "after the display came back")
        },
        Case("TRACK-39", "An app you quit and open again opens beside your work") { t in
            // Saved spots are for windows coming back in Expanse's first 3 minutes; this needs it running longer.
            if let launched = t.expanse?.launchDate {
                let wait = 190 - Date().timeIntervalSince(launched)
                if wait > 60 { throw Skip("Expanse started \(Int(190 - wait))s ago; this needs it running for 3 minutes") }
                if wait > 0 { try await t.pause(wait) }
            }
            let old = expanseDefault("autoCentre")
            setExpanseDefault("autoCentre", true)
            defer { setExpanseDefault("autoCentre", old) }
            let name = "Track39-\(Int.random(in: 1000...9999))"
            let first = try await t.fixture(name)
            guard let x = first.windows.first else { throw Failure("the app has no window") }
            try await t.trackOnCanvas([x], "the app's window")
            let work = try await t.window("TRACK-39 Work")
            // The app well away from where you're working.
            try await t.trackPlace([(work.id, trackAt(0, 0)), (x, trackAt(9000, -4000))])
            try await t.trackShow(work.id)
            guard let oldSpot = try await t.state().window(x)?.canvas else { throw Failure("the app's window isn't on the canvas") }
            work.focus()
            try await t.pause(0.5)
            let mark = t.log.mark()
            let appName = first.app?.localizedName ?? "Expanse Tests"
            await first.quit()
            try await t.trackLine("\(appName) quit", since: mark, timeout: 5)
            try await t.pause(3)
            let since = t.log.mark()
            let again = try await t.fixture(name)
            guard let y = again.windows.first else { throw Failure("the app opened again with no window") }
            let line = try await t.trackLine("placed new window ", since: since, timeout: 5)
            try t.expect(line.contains("beside ") && line.contains("[\(work.id)]"), "it should go beside the window you're in (TRACK-39 Work): \(line)")
            try await t.trackOnCanvas([y], "the app's window")
            let s = try await t.settle()
            guard let spot = s.window(y)?.canvas, let w = s.window(work.id)?.canvas else { throw Failure("a window left the canvas") }
            try t.expect(hypot(spot.minX - oldSpot.minX, spot.minY - oldSpot.minY) > 100, "it went back to its old spot \(NSStringFromRect(oldSpot))")
            try t.expect(trackBeside(spot, w), "it's at \(NSStringFromRect(spot)), not beside TRACK-39 Work at \(NSStringFromRect(w))")
            let kept = t.trackLines("keeping ", "window spots", since: mark)
            try t.expect(kept.isEmpty, "Expanse kept the quit app's spots: \(kept.first ?? "")")
        },
    ]
}

// MARK: Helpers

/// An empty part of the canvas, far from anything of yours, where these cases set out their windows.
private let trackHere = CGPoint(x: -60000, y: 40000)

private func trackAt(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: trackHere.x + dx, y: trackHere.y + dy) }

/// The view is at 100%, with `f` in the middle (as a glide leaves it: top-aligned when it's taller than the screen).
private func trackIsCentred(_ s: ExpanseState, _ f: CGRect, within d: CGFloat = 4) -> Bool {
    let v = s.visibleCanvas
    let dy = f.height > v.height ? abs(v.minY - f.minY) : abs(v.midY - f.midY)
    return abs(s.scale - 1) < 0.001 && abs(v.midX - f.midX) <= d && dy <= d
}

/// `a` is next to `b`: side by side or one above the other, a gap or so apart.
private func trackBeside(_ a: CGRect, _ b: CGRect) -> Bool {
    let gapX = max(b.minX - a.maxX, a.minX - b.maxX), gapY = max(b.minY - a.maxY, a.minY - b.maxY)
    return (gapX >= 0 && gapX <= 40 && gapY < 0) || (gapY >= 0 && gapY <= 40 && gapX < 0)
}

@MainActor private func trackSized(_ t: Ctx, _ id: CGWindowID, _ size: CGSize) async throws -> Bool {
    guard let c = try await t.state().window(id)?.canvas else { return false }
    return abs(c.width - size.width) <= 1 && abs(c.height - size.height) <= 1
}

/// Brings a fixture's app forward, as ⌘-Tab does. Through Accessibility when Expanse Tests has it (at once,
/// whichever app is active, as Expanse itself does); otherwise with NSRunningApplication, which macOS may refuse
/// to an app that isn't active itself.
@MainActor private func trackActivate(_ f: Fixture) async {
    guard let app = f.app else { return }
    await bringForward(app)
}

/// Makes an app the front one through Accessibility (needs it).
private func trackFront(_ pid: pid_t) {
    AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
}

/// The front-most ordinary window on screen (layer 0, as big as Expanse manages), as the window server stacks them.
private func trackFrontWindow() -> CGWindowID? {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
        guard let id = w[kCGWindowNumber as String] as? CGWindowID, let b = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b), r.width >= 100, r.height >= 60,
              (w[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
        return id
    }
    return nil
}

/// Whether `top` is in front of each of `others` that's on screen.
private func trackInFront(_ top: CGWindowID, of others: [CGWindowID]) -> Bool {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let order = info.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    guard let i = order.firstIndex(of: top) else { return false }
    return others.allSatisfy { o in order.firstIndex(of: o).map { $0 > i } ?? true }
}

/// Prompts from macOS on screen among app windows: windows of a com.apple background process (not an app in
/// the Dock), at app-window level and 150×80 or bigger. What Expanse keeps above app windows.
private func trackSystemPrompts() -> [CGWindowID] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        guard (w[kCGWindowLayer as String] as? Int) == 0, let id = w[kCGWindowNumber as String] as? CGWindowID,
              let pid = w[kCGWindowOwnerPID as String] as? pid_t, let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier?.hasPrefix("com.apple.") == true, app.activationPolicy != .regular,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
              r.width >= 150, r.height >= 80 else { return nil }
        return id
    }
}

/// Whether Expanse's canvas is up (zoomed out, or a glide): its overlay on screen above app windows. At 100% it's
/// under them. Asks the window server, not Expanse.
@MainActor private func trackCanvasUp(_ t: Ctx) -> Bool {
    guard let pid = t.expanse?.processIdentifier else { return false }
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.contains { w in
        guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid, (w[kCGWindowLayer as String] as? Int ?? 0) > 0,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) else { return false }
        return r.width >= t.screen.width - 1
    }
}

/// Opens expanse://`command` and checks Expanse's main thread took it within `limit`: it logs a link the moment it
/// gets it ("url command …"), so a stall shows as a late line. (The log stream adds a little.)
@MainActor private func trackAnswers(_ t: Ctx, _ command: String, _ query: [String: Any], within limit: TimeInterval) async throws {
    let mark = t.log.mark()
    let sent = Date()
    t.link(command, query)
    guard await t.log.wait(since: mark, timeout: limit + 4, { $0.contains("url command \(command)") }) != nil else {
        throw Failure("Expanse never took expanse://\(command)")
    }
    let took = Date().timeIntervalSince(sent)
    try t.expect(took <= limit, "Expanse took \(String(format: "%.2f", took))s to take expanse://\(command): it stalled")
}

/// Checks Expanse still answers at once after `what`, with a link it ignores (it logs an unknown one straight away,
/// and does nothing else).
@MainActor private func trackStillAnswers(_ t: Ctx, _ what: String) async throws {
    let mark = t.log.mark()
    let sent = Date()
    t.link("trackprobe")
    guard await t.log.wait(since: mark, timeout: 8, { $0.contains("ignored unknown URL command") }) != nil else {
        throw Failure("Expanse stopped answering after \(what)")
    }
    let took = Date().timeIntervalSince(sent)
    try t.expect(took <= 1.5, "Expanse took \(String(format: "%.1f", took))s to answer after \(what): frozen")
}

/// A text field filling `w`, ready for typing: what's typed while `w` has the keyboard lands in it.
@MainActor private func trackTypingField(_ w: TestWindow) -> NSTextField {
    let field = NSTextField(string: "")
    field.isEditable = true
    field.font = .systemFont(ofSize: 18)
    if let content = w.window.contentView {
        field.frame = content.bounds.insetBy(dx: 16, dy: 16)
        field.autoresizingMask = [.width, .height]
        content.addSubview(field)
    }
    w.window.makeFirstResponder(field)
    return field
}

/// A drag with the left button along `path` (global points) over `seconds`, in steps as a hand makes them. Unlike
/// Input.drag it awaits between steps, so this app stays free to handle them (its own windows can be dragged).
/// `each` sees every step's pointer. Returns how many drag events it posted.
@MainActor @discardableResult
private func trackDrag(_ path: [CGPoint], seconds: Double, each: ((CGPoint) -> Void)? = nil) async -> Int {
    guard let first = path.first, let last = path.last else { return 0 }
    func post(_ type: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    let legs = zip(path, path.dropFirst()).map { pair in (a: pair.0, b: pair.1, length: hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)) }
    let total = max(1, legs.reduce(0) { $0 + $1.length })
    func point(at distance: CGFloat) -> CGPoint {
        var rest = distance
        for leg in legs {
            if rest <= leg.length, leg.length > 0 {
                let k = rest / leg.length
                return CGPoint(x: leg.a.x + (leg.b.x - leg.a.x) * k, y: leg.a.y + (leg.b.y - leg.a.y) * k)
            }
            rest -= leg.length
        }
        return last
    }
    post(.mouseMoved, first)
    try? await Task.sleep(nanoseconds: 50_000_000)
    post(.leftMouseDown, first)
    try? await Task.sleep(nanoseconds: 100_000_000)
    let steps = max(2, Int(seconds / 0.016))
    for i in 1...steps {
        let p = point(at: total * CGFloat(i) / CGFloat(steps))
        post(.leftMouseDragged, p)
        each?(p)
        try? await Task.sleep(nanoseconds: 16_000_000)
    }
    try? await Task.sleep(nanoseconds: 60_000_000)
    post(.leftMouseUp, last)
    try? await Task.sleep(nanoseconds: 60_000_000)
    return steps
}

/// TRACK-38: the windows are back at their spots, the view hasn't moved, and nothing glided.
@MainActor private func trackCameBackQuietly(_ t: Ctx, _ ids: [CGWindowID], _ before: ExpanseState, since mark: Int, _ when: String) async throws {
    try await t.trackOnCanvas(ids, "the windows back \(when)", timeout: 15)
    try await t.pause(2)
    let s = try await t.settle()
    try t.expectNear(s.camera, before.camera, within: 2, "the view \(when)")
    for id in ids {
        guard let was = before.window(id), let now = s.window(id) else { continue }
        try t.expectNear(now.canvas, was.canvas, within: 2, "[\(id)]'s spot \(when)")
        try t.expect(now.parked == was.parked, "[\(id)] should be \(was.parked ? "out of view" : "on screen") \(when)")
    }
    let glides = t.trackLines("glide to ", since: mark)
    try t.expect(glides.isEmpty, "something glided \(when): \(glides.first ?? "")")
}

@MainActor fileprivate extension Ctx {
    /// The first log line since `mark` with every one of `parts` in it.
    @discardableResult
    func trackLine(_ parts: String..., since mark: Int, timeout: TimeInterval = 8) async throws -> String {
        guard let line = await log.wait(since: mark, timeout: timeout, { l in parts.allSatisfy { l.contains($0) } }) else {
            throw Failure("no log line with “\(parts.joined(separator: "…"))”")
        }
        return line
    }

    /// Every log line since `mark` with every one of `parts` in it.
    func trackLines(_ parts: String..., since mark: Int) -> [String] {
        log.lines(since: mark).filter { l in parts.allSatisfy { l.contains($0) } }
    }

    /// Puts windows at canvas spots (expanse://place, committed) and waits until they're there.
    func trackPlace(_ spots: [(CGWindowID, CGPoint)]) async throws {
        for (id, p) in spots { link("place", ["id": id, "x": Int(p.x), "y": Int(p.y), "commit": 1]) }
        try await until("windows at their spots on the canvas", timeout: 10) {
            let s = try await settle()
            return spots.allSatisfy { spot in
                s.window(spot.0).map { hypot($0.canvas.minX - spot.1.x, $0.canvas.minY - spot.1.y) < 1.5 } ?? false
            }
        }
    }

    /// Glides the view onto a window (expanse://focus?id=, as a hop does), and waits until it's in the middle.
    @discardableResult
    func trackShow(_ id: CGWindowID) async throws -> ExpanseState {
        link("focus", ["id": id])
        return try await trackViewOn(id, "the view to glide to [\(id)]")
    }

    /// Waits until the view is at 100% with the window in the middle.
    @discardableResult
    func trackViewOn(_ id: CGWindowID, _ what: String = "the view on the window", timeout: TimeInterval = 8) async throws -> ExpanseState {
        var last = ExpanseState(lines: [])
        try await until(what, timeout: timeout) {
            last = try await settle()
            return !last.active && (last.window(id).map { trackIsCentred(last, $0.canvas) } ?? false)
        }
        return last
    }

    func trackOnCanvas(_ ids: [CGWindowID], _ what: String, timeout: TimeInterval = 10) async throws {
        try await until("\(what) on the canvas", timeout: timeout) {
            let s = try await state()
            return ids.allSatisfy { s.window($0) != nil }
        }
    }

    func trackOffCanvas(_ id: CGWindowID, _ what: String, timeout: TimeInterval = 6) async throws {
        try await until("\(what) off the canvas", timeout: timeout) { try await state().window(id) == nil }
    }

    /// After a moment (for anything that would move it), the window is still at `spot` on the canvas.
    func trackSameSpot(_ id: CGWindowID, _ spot: CGRect, _ when: String) async throws {
        try await pause(1.5)
        guard let c = try await settle().window(id)?.canvas else { throw Failure("the window isn't on the canvas \(when)") }
        try expectNear(c, spot, within: 1, "its spot \(when)")
    }
}
