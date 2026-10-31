import AppKit
import ApplicationServices

/// The manual cases in docs/regression/displays-lock-sleep.md.
///
/// expanse://screen stands in for a display change wherever the case doesn't need macOS's own
/// behaviour with real hardware: the lid and plugging displays in are yours, and so are locking
/// and unlocking (your password). Windows a case arranges go far out on the canvas
/// (displayOrigin), away from yours.
@MainActor enum DISPLAY {
    static let cases: [Case] = [
        Case("DISPLAY-01", "For 20s after a display change, only your drags count as moves") { t in
            try t.needsInput()
            let a = try await t.window("DISPLAY-01 A", CGRect(x: 120, y: 160, width: 360, height: 240))
            // B is another app's window, to be dragged (Expanse Tests' own can't be, by posted events).
            let fb = try await t.fixture("DISPLAY-01 B", windows: 1, size: CGSize(width: 360, height: 240))
            guard let b = fb.windows.first, let bApp = fb.app else { throw Failure("the fixture has no window") }
            try await t.until("Expanse to take on B", timeout: 10) { try await t.state().window(b) != nil }
            // Both on screen, side by side.
            let vis = try await t.settle().visibleCanvas
            t.place(a, at: CGPoint(x: vis.minX + 80, y: vis.minY + 80))
            t.link("place", ["id": b, "x": Int(vis.minX + 500), "y": Int(vis.minY + 80), "commit": 1])
            try await t.until("A and B on screen", timeout: 8) {
                let s = try await t.settle()
                return s.window(a.id)?.parked == false && s.window(b)?.parked == false
            }
            // A display change: to the display's own size, so the layout itself needn't move.
            let mark = t.log.mark()
            t.link("screen", ["w": Int(t.screen.width), "h": Int(t.screen.height)])
            let fitted = try await t.displayLogIndex("layout fitted:", since: mark, timeout: 10)
            let changed = Date()
            try await t.settle()
            guard let aAt = a.real else { throw Failure("A isn't on screen") }
            let aSpot = try await t.canvasFrame(a)
            // macOS moving A while the display settles: put back.
            a.setFrame(aAt.offsetBy(dx: 120, dy: 70))
            try await t.expectLog("re-placing windows moved by macOS during a display change", since: fitted, timeout: 4)
            do {
                try await t.until("A put back", timeout: 4) { a.real.map { displayNear($0, aAt, 2) } ?? false }
            } catch {
                throw Failure("A, moved while the display settled (not by you), should be put back at \(NSStringFromRect(aAt)); it's at \(a.real.map(NSStringFromRect) ?? "nowhere")")
            }
            // Your drag of B (mouse button down): followed and kept.
            await bringForward(bApp)
            try await t.pause(0.4)
            guard let bAt = realFrame(b) else { throw Failure("B isn't on screen") }
            guard let bSpot = try await t.state().window(b)?.canvas else { throw Failure("B isn't on the canvas") }
            let grab = CGPoint(x: bAt.midX, y: bAt.minY + 12)
            await Input.dragAsync(from: grab, to: CGPoint(x: grab.x + 160, y: grab.y + 90))
            // Where the drag left the real window (macOS can stop a little short of the pointer).
            try await t.pause(0.3)
            guard let bNow = realFrame(b) else { throw Failure("B isn't on screen after the drag") }
            // In a VM the window server can fall behind the pointer, and the window ends short of
            // it: what counts is that B moved, and that its spot follows wherever it ended.
            try t.expect(hypot(bNow.minX - bAt.minX, bNow.minY - bAt.minY) > 40, "the drag didn't move B (it's at \(NSStringFromRect(bNow)))")
            let target = CGPoint(x: bSpot.minX + bNow.minX - bAt.minX, y: bSpot.minY + bNow.minY - bAt.minY)
            do {
                try await t.until("B's canvas spot to follow your drag", timeout: 4) {
                    guard let c = try await t.state().window(b)?.canvas else { return false }
                    return hypot(c.minX - target.x, c.minY - target.y) <= 6
                }
            } catch {
                throw Failure("your drag of B during the display change should be followed: its canvas spot is \(try await t.state().window(b)?.canvas.origin ?? .zero), not about \(target)")
            }
            guard let dragged = try await t.state().window(b)?.canvas else { throw Failure("B left the canvas") }
            // About 20s on, the display change counts as settled.
            try await t.expectLog("display change settled", since: fitted, timeout: 26)
            let took = Date().timeIntervalSince(changed)
            try t.expect(took > 15, "the display change settled after \(Int(took))s, not about 20s")
            let s = try await t.settle()
            try t.expectNear(s.window(b)?.canvas ?? .zero, dragged, within: 1, "B after the display change settled (your drag kept)")
            try t.expectNear(s.window(a.id)?.canvas ?? .zero, aSpot, within: 1, "A after the display change settled")
            try await t.displayExpectInPlace([a])
        },
        Case("DISPLAY-03", "Closing the lid with no other display doesn't crash Expanse", .guided) { t in
            guard t.displayCount >= 2 else { throw Skip("needs a MacBook with an external display plugged in") }
            let ws = try await t.displayRow("DISPLAY-03", count: 3)
            guard let pid = t.expanse?.processIdentifier else { throw Failure("Expanse isn't running") }
            for step in ["Close the lid, so the external display is the only screen. Wait 10 seconds, then open the lid again.",
                         "Close the lid again, then unplug the external display. Wait 10 seconds, then open the lid."] {
                let mark = t.log.mark()
                try await t.ask(step)
                try t.expect(t.expanse?.processIdentifier == pid, "Expanse stopped running (crashed?) after: \(step)")
                // Re-placed on the display there is now.
                try await t.displayAfterRelayout(since: mark, timeout: 30)
                try await t.displayExpectInPlace(ws)
            }
        },
        Case("DISPLAY-04", "After unlocking, windows are back where the canvas has them", .guided) { t in
            let ws = try await t.displayRow("DISPLAY-04", count: 10)
            let before = try await t.settle()
            let mark = t.log.mark()
            try await t.ask("Lock the Mac (⌃⌘Q), wait a minute, then unlock it.")
            let unlocked = try await t.displayLockedThenUnlocked(since: mark)
            try await t.displayAfterRelayout(since: unlocked)
            let after = try await t.settle()
            try t.displayExpectSame(ws, before, after)
            try await t.displayExpectInPlace(ws)
            // ⌥`: zoomed out, everything where the canvas had it.
            t.link("enter")
            let out = try await t.settle()
            try t.expect(out.active, "the canvas should open")
            try t.displayExpectSame(ws, before, out)
        },
        Case("DISPLAY-08", "Display changes while paused leave windows alone") { t in
            let small = displaySmallScreen(t, 0.7)
            let (big, beside) = try await t.displayBigAndBeside("DISPLAY-08", widerThan: small)
            let chosen = try await t.canvasFrame(big).size
            t.link("pause")
            try await t.untilPaused("paused")
            try await t.pause(0.5)
            let frames = [big, beside].map(\.real)
            // Step 1: the display changes; nothing moves, and the log says nothing of it.
            let mark = t.log.mark()
            t.link("screen", ["w": Int(small.width), "h": Int(small.height)])
            try await t.expectLog("url command screen", since: mark)
            try await t.pause(5)
            let moves = t.log.lines(since: mark).filter { line in
                line.hasPrefix("move ") || ["display changed", "layout fitted", "re-placing", "fit size", "follow ", "slow: moving"].contains { line.contains($0) }
            }
            try t.expect(moves.isEmpty, "paused, a display change shouldn't move anything: “\(moves.first ?? "")”")
            for (w, f) in zip([big, beside], frames) {
                try t.expectNear(w.real ?? .zero, f ?? .zero, within: 1, "\(w.title) after the display change while paused")
            }
            // Step 2: resumed, the layout comes back, fitted to this screen.
            let mark2 = t.log.mark()
            t.link("resume")
            try await t.expectLog("first sync:", since: mark2, timeout: 10)
            try await t.expectLog("layout fitted:", since: mark2, timeout: 10)
            try await t.until("both back on the canvas", timeout: 10) {
                let s = try await t.state()
                return s.window(big.id) != nil && s.window(beside.id) != nil
            }
            try await t.pause(1)
            let s = try await t.settle()
            try t.expect(abs(s.viewport.width - small.width) <= 1, "Expanse should be using the \(small) screen now (viewport \(s.viewport.size))")
            try t.displayExpectFitted(s, big: big, beside: beside, chosen: chosen)
            try await t.displayExpectInPlace([big, beside])
            try await t.displayScreen(nil)
        },
        Case("DISPLAY-10", "A display change with 50 windows doesn't freeze Expanse") { t in
            // Expanse's answers to Accessibility questions come from its main thread: how long it
            // takes to answer is how long it's frozen.
            guard Input.allowed else { throw Skip("needs Accessibility for Expanse Tests, to time Expanse's answers") }
            guard let pid = t.expanse?.processIdentifier else { throw Failure("Expanse isn't running") }
            var ws: [TestWindow] = []
            for i in 0..<50 {
                let frame = CGRect(x: 60 + CGFloat(i % 10) * 30, y: 90 + CGFloat(i / 10) * 30, width: 240, height: 160)
                ws.append(try await t.window("DISPLAY-10 \(i + 1)", frame, managed: false))
            }
            try await t.until("Expanse to take on all 50 windows", timeout: 40) {
                let s = try await t.state()
                return ws.allSatisfy { s.window($0.id) != nil }
            }
            try await t.settle(timeout: 15)
            let small = displaySmallScreen(t, 0.8)
            let probe = displayWorstAnswer(pid: pid, for: 8)
            let mark = t.log.mark()
            t.link("screen", ["w": Int(small.width), "h": Int(small.height)])
            try await t.expectLog("layout fitted:", since: mark, timeout: 15)
            let worst = await probe.value
            // In a VM every window macOS moves costs Expanse window-server calls of 50–200ms each
            // (its Space, the window's place): a Mac's answer, not a VM's, says whether it froze.
            try t.expectTiming(worst < 1, "Expanse didn't answer for \(Int(worst * 1000))ms during the display change: it froze")
            try await t.pause(1)
            try await t.settle(timeout: 20)
            try await t.displayExpectInPlace(ws, timeout: 10)
            try await t.displayScreen(nil)
        },
        Case("DISPLAY-12", "A display change waits for windows still moving") { t in
            let ws = try await t.displayRow("DISPLAY-12", count: 4)
            let sizes = try await ws.asyncMap { try await t.canvasFrame($0).size }
            let small = displaySmallScreen(t, 0.8)
            // The display changes; its re-layout is due 1.6s later, just as a hop to the right is
            // under way (⌃→).
            let mark = t.log.mark()
            t.link("screen", ["w": Int(small.width), "h": Int(small.height)])
            try await t.pause(1.45)
            t.link("nav", ["dir": "right"])
            try await t.expectLog("navigate to", since: mark, timeout: 5)
            try await t.expectLog("layout fitted:", since: mark, timeout: 15)
            try await t.pause(1)
            let s = try await t.settle(timeout: 15)
            try t.expect(abs(s.viewport.width - small.width) <= 1, "Expanse should be using the \(small) screen now (viewport \(s.viewport.size))")
            for (w, size) in zip(ws, sizes) {
                guard let c = s.window(w.id)?.canvas else { throw Failure("\(w.title) isn't on the canvas") }
                try t.expect(displayNear(c.size, size, 2), "\(w.title) should be at its chosen size \(size), not \(c.size)")
            }
            // Placed for the new screen, not where the old one wanted them.
            try await t.displayExpectInPlace(ws)
            try await t.displayScreen(nil)
        },
        Case("DISPLAY-17", "Relaunching on a bigger screen fits the saved layout to it") { t in
            // Quitting puts windows back in the macOS layout, and one whose macOS spot is off the
            // (pretend) smaller screen comes back at its top (PERSIST-04): so the smaller screen
            // here is only a little smaller, to leave your windows' macOS spots alone.
            let small = CGSize(width: t.screen.width - 300, height: t.screen.height - 120)
            let (big, beside) = try await t.displayBigAndBeside("DISPLAY-17", widerThan: small)
            let home = try await t.settle()
            guard let hb = home.window(big.id)?.canvas else { throw Failure("the big window isn't on the canvas") }
            // Step 1: the big display goes; the layout tightens.
            try await t.displayScreen(small)
            let tight = try await t.settle()
            guard let tb = tight.window(big.id)?.canvas else { throw Failure("the big window left the canvas") }
            try t.expect(tb.width < hb.width - 1, "on the smaller screen the big window should shrink (\(tb.size))")
            try await t.pause(1.5)
            // Steps 2-4: quit; the big display's back (a new Expanse has no pretend screen); open Expanse.
            let mark = t.log.mark()
            try await t.displayRelaunchingAfter {
                try await t.quitExpanse()
                try await t.pause(1)
                try await t.launchExpanse()
            }
            try await t.until("both windows back on the canvas", timeout: 15) {
                let s = try await t.state()
                return s.window(big.id) != nil && s.window(beside.id) != nil
            }
            let fitted = try await t.expectLog("layout fitted:", since: mark, timeout: 10)
            try t.expect(fitted.hasSuffix("derived=false"), "relaunched on the bigger screen, windows should be at their chosen sizes: “\(fitted)”")
            try await t.pause(1)
            let s = try await t.settle()
            for w in [big, beside] {
                guard let a = home.window(w.id)?.canvas, let b = s.window(w.id)?.canvas else { throw Failure("\(w.title) isn't on the canvas") }
                try t.expectNear(b, a, within: 2, "\(w.title) after relaunching on the bigger screen (its home spot and size there)")
            }
            try await t.displayExpectInPlace([big, beside])
        },
        Case("DISPLAY-18", "A display change while zoomed out fits the layout") { t in
            let small = displaySmallScreen(t, 0.7)
            let (big, beside) = try await t.displayBigAndBeside("DISPLAY-18", widerThan: small)
            let chosen = try await t.canvasFrame(big).size
            t.link("enter")
            let out = try await t.settle()
            try t.expect(out.active, "the canvas should open")
            let mark = t.log.mark()
            t.link("screen", ["w": Int(small.width), "h": Int(small.height)])
            let changed = try await t.displayLogIndex("display changed:", since: mark, timeout: 10)
            // Each window it shrinks is a resize its app has to answer: a second or so each in a VM.
            try await t.expectLog("layout fitted:", since: changed, timeout: 30)
            try await t.pause(3)
            // Still zoomed out, the canvas shows the layout fitted to the new screen, and the view
            // isn't recentred on any window.
            let s = try await t.settle()
            try t.expect(s.active, "the canvas should stay zoomed out through the display change")
            try t.expect(abs(s.scale - out.scale) < 0.001, "the zoom changed with the display (\(out.scale) → \(s.scale))")
            try t.expectNear(displayMiddle(s), displayMiddle(out), within: 2, "the canvas point in the middle of the view (no glide to a window)")
            try await t.noLog("display change: centred on", since: mark, within: 0.1)
            try t.displayExpectFitted(s, big: big, beside: beside, chosen: chosen)
            // Zooming in, the real windows follow.
            t.link("exit")
            try await t.until("back at 100%") { try await !t.settle().active }
            try await t.displayExpectInPlace([big, beside])
            try await t.displayScreen(nil)
        },
        Case("DISPLAY-23", "Locking the Mac doesn't move windows", .guided) { t in
            let ws = try await t.displayRow("DISPLAY-23", count: 10)
            try await t.pause(1.5)
            let before = try await t.settle()
            let saved = displaySavedSpots(ws)
            let mark = t.log.mark()
            try await t.ask("Lock the Mac (⌃⌘Q) and leave it locked for a few minutes, until the displays sleep. Then unlock it.")
            let unlocked = try await t.displayLockedThenUnlocked(since: mark)
            try await t.displayAfterRelayout(since: unlocked)
            let after = try await t.settle()
            try t.displayExpectSame(ws, before, after)
            try await t.displayExpectInPlace(ws)
            // Nothing piled up at one spot.
            let onScreen = ws.filter { after.window($0.id)?.parked == false }.compactMap { $0.real?.origin }
            for (i, p) in onScreen.enumerated() where onScreen[..<i].contains(where: { hypot($0.x - p.x, $0.y - p.y) < 2 }) {
                throw Failure("two windows are piled up at \(p) after unlocking")
            }
            // The saved layout's positions are unchanged.
            try await t.pause(2)
            let now = displaySavedSpots(ws)
            for w in ws {
                guard let a = saved[w.id] else { continue }
                guard let b = now[w.id] else { throw Failure("layout.json lost \(w.title)") }
                try t.expectNear(b, a, within: 1, "\(w.title)'s spot in layout.json after the lock screen")
            }
        },
        Case("DISPLAY-24", "Sleeping the displays doesn't move windows", .guided) { t in
            let ws = try await t.displayRow("DISPLAY-24", count: 6)
            let before = try await t.settle()
            try await t.ask("Press Done, then leave the Mac alone for about half a minute: the displays will sleep and wake by themselves. If the Mac locks as they sleep, unlock it.")
            let mark = t.log.mark()
            try displayRun("/usr/bin/pmset", ["displaysleepnow"])
            let asleep = try await t.displayLogIndex("displays asleep: window moves not followed until they wake", since: mark, timeout: 15)
            try await t.pause(20)
            // A key press or the mouse, as far as macOS is concerned.
            try displayRun("/usr/bin/caffeinate", ["-u", "-t", "2"], wait: false)
            var from = try await t.displayLogIndex("displays awake: re-placing windows", since: asleep, timeout: 120)
            if displayScreenLocked() || t.log.lines(since: mark).contains(where: { $0.contains("locked: window moves not followed until unlocked") }) {
                // It locked too: the windows go back once you've unlocked.
                from = try await t.displayLogIndex("unlocked: re-placing windows", since: mark, timeout: 600)
            }
            try await t.displayAfterRelayout(since: from)
            let after = try await t.settle()
            try t.displayExpectSame(ws, before, after)
            try await t.displayExpectInPlace(ws)
        },
        Case("DISPLAY-25", "A display change while locked isn't followed before you unlock", .guided) { t in
            // expanse://screen stands in for unplugging the display, sent while you're at the lock screen.
            let small = displaySmallScreen(t, 0.7)
            let (big, beside) = try await t.displayBigAndBeside("DISPLAY-25", widerThan: small)
            let chosen = try await t.canvasFrame(big).size
            let before = try await t.settle()
            let mark = t.log.mark()
            let times = DisplayTimes()
            let change = t.displayWatch(for: "locked: window moves not followed until unlocked", since: mark) {
                try await t.pause(1)
                t.link("screen", ["w": Int(small.width), "h": Int(small.height)])
            }
            let unlock = t.displayWatch(for: "unlocked: re-placing windows", since: mark) {
                times.settled = await t.displayWaitFor("display change settled", since: t.log.mark(), timeout: 40)
            }
            try await t.displayAsk("Lock the Mac (⌃⌘Q) and stay at the lock screen for at least 30 seconds. Then unlock it.", [change, unlock])
            guard let changedAt = try await t.displayWatched(change) else { throw Failure("no “locked: …” line in the log: did the Mac lock?") }
            guard let unlockedAt = try await t.displayWatched(unlock, timeout: 45) else { throw Failure("no “unlocked: re-placing windows” line in the log") }
            guard unlockedAt.timeIntervalSince(changedAt) > 22 else {
                throw Skip("unlocked \(Int(unlockedAt.timeIntervalSince(changedAt)))s after the display change: stay at the lock screen for at least 30 seconds")
            }
            let locked = try await t.displayLogIndex("locked: window moves not followed until unlocked", since: mark)
            let unlocked = try await t.displayLogIndex("unlocked: re-placing windows", since: locked)
            try await t.expectLog("display changed:", since: locked, timeout: 1)
            if let line = t.log.lines(since: locked).prefix(unlocked - locked).first(where: { $0.contains("display change settled") }) {
                throw Failure("the display change settled while the Mac was locked: “\(line)”")
            }
            // After unlocking: settled about 20s on, the layout fitted to the smaller screen.
            guard let settledAt = times.settled else { throw Failure("no “display change settled” within 40s of unlocking") }
            let took = settledAt.timeIntervalSince(unlockedAt)
            try t.expect(took > 15 && took < 32, "the display change settled \(Int(took))s after unlocking, not about 20s")
            try await t.displayAfterRelayout(since: unlocked)
            let s = try await t.settle()
            try t.displayExpectFitted(s, big: big, beside: beside, chosen: chosen)
            try await t.displayExpectInPlace([big, beside])
            // Back on the bigger display: every window exactly where it was.
            try await t.displayScreen(nil)
            let after = try await t.settle()
            for w in [big, beside] {
                guard let a = before.window(w.id)?.canvas, let b = after.window(w.id)?.canvas else { throw Failure("\(w.title) isn't on the canvas") }
                try t.expectNear(b, a, within: 1, "\(w.title) back on the bigger screen")
            }
        },
        Case("DISPLAY-26", "After unlocking, ⌘-Tab follows to the app's window", .guided) { t in
            try t.needsInput()
            let (f, fid, _) = try await t.displayAwayAppAndHere("DISPLAY-26")
            let mark = t.log.mark()
            // Straight after the unlock, before the windows are back in place: ⌘-Tab to the app
            // (the ⌘ key, and the app comes forward).
            let switched = t.displayWatch(for: "unlocked: re-placing windows", since: mark) {
                Input.holding(.maskCommand) {}
                try await t.displaySwitch(to: f)
            }
            try await t.displayAsk("Lock the Mac (⌃⌘Q), then unlock it.", [switched])
            guard try await t.displayWatched(switched, timeout: 10) != nil else {
                throw Failure("no “unlocked: re-placing windows” line in the log: did the Mac lock?")
            }
            do {
                try await t.until("the view to glide to the app's window", timeout: 10) {
                    let s = try await t.settle()
                    guard let w = s.window(fid) else { return false }
                    return !w.parked && s.visibleCanvas.contains(CGPoint(x: w.canvas.midX, y: w.canvas.midY))
                }
            } catch {
                throw Failure("switching to the app just after unlocking should glide to its window once windows are back; it's still out of view")
            }
        },
        Case("DISPLAY-27", "After unlocking, focus changes macOS makes itself aren't followed", .guided) { t in
            let (f, fid, _) = try await t.displayAwayAppAndHere("DISPLAY-27")
            let before = try await t.settle()
            let mark = t.log.mark()
            // While the displays settle after the unlock, and once you've stopped typing your
            // password, the app comes forward with no click or key from you.
            let switched = t.displayWatch(for: "unlocked: re-placing windows", since: mark) {
                try await t.pause(3)
                try await t.until("no clicks or keys for 1.5s", timeout: 15) { displayNoInput(for: 1.6) }
                try await t.displaySwitch(to: f)
            }
            try await t.displayAsk("Lock the Mac (⌃⌘Q) and unlock it. Then leave the keyboard and mouse alone for 20 seconds before pressing Done.", [switched])
            guard try await t.displayWatched(switched, timeout: 25) != nil else {
                throw Failure("no “unlocked: re-placing windows” line in the log: did the Mac lock?")
            }
            let unlocked = try await t.displayLogIndex("unlocked: re-placing windows", since: mark)
            try await t.expectLog("[\(fid)] focused while displays settle, not by you: not followed", since: unlocked, timeout: 5)
            if let line = t.log.lines(since: mark).first(where: { $0.contains("glide to ") && $0.contains("[\(fid)]") }) {
                throw Failure("a focus change you didn't make was followed: “\(line)”")
            }
            let s = try await t.settle()
            try t.expect(s.window(fid)?.parked == true, "the app's window should still be out of view")
            try t.expectNear(s.camera, before.camera, within: 2, "the view after unlocking")
        },
        Case("DISPLAY-28", "A window opened just after unlocking goes beside your work", .guided) { t in
            let here = try await t.window("DISPLAY-28 Here", CGRect(x: 200, y: 200, width: 520, height: 360))
            t.place(here, at: displayOrigin)
            t.link("focus", ["id": here.id])
            try await t.until("Here in view") { try await t.settle().window(here.id)?.parked == false }
            let mark = t.log.mark()
            let opened = DisplayOpened()
            let watch = t.displayWatch(for: "unlocked: re-placing windows", since: mark) {
                // Before the layout's back in place: an app that wasn't running opens (Calculator).
                opened.app = try await t.fixture("DISPLAY-28 Calculator", windows: 1, size: CGSize(width: 320, height: 420))
                // And once it's back in place, another window.
                try await t.pause(6)
                opened.later = try await t.window("DISPLAY-28 Later", CGRect(x: 260, y: 240, width: 420, height: 300), managed: false)
            }
            try await t.displayAsk("Lock the Mac (⌃⌘Q), then unlock it.", [watch])
            guard try await t.displayWatched(watch, timeout: 20) != nil else {
                throw Failure("no “unlocked: re-placing windows” line in the log: did the Mac lock?")
            }
            guard let appWindow = opened.app?.windows.first, let later = opened.later else { throw Failure("the new windows didn't open") }
            try await t.until("both new windows on the canvas", timeout: 15) {
                let s = try await t.state()
                return s.window(appWindow) != nil && s.window(later.id) != nil
            }
            try await t.pause(1)
            let s = try await t.settle(timeout: 15)
            guard let work = s.window(here.id)?.canvas else { throw Failure("Here isn't on the canvas") }
            let news: [(CGWindowID, String)] = [(appWindow, "the app opened just after unlocking"), (later.id, "the window opened once things settled")]
            for (id, name) in news {
                guard let f = s.window(id)?.canvas else { throw Failure("\(name) isn't on the canvas") }
                if let other = s.windows.first(where: { $0.id != id && $0.canvas.insetBy(dx: 1, dy: 1).intersects(f) }) {
                    throw Failure("\(name) (\(f)) overlaps \(other.app)[\(other.id)] (\(other.canvas))")
                }
                let neighbours = [work] + news.filter { $0.0 != id }.compactMap { s.window($0.0)?.canvas }
                try t.expect(displayBeside(f, work) || (id == later.id && neighbours.contains { displayBeside(f, $0) }),
                             "\(name) (\(f)) should be in a free spot beside the window you're in (\(work)), 20pt away")
            }
            try await t.displayExpectInPlace(ids: [(here.id, here.title)] + news)
        },
    ]
}

// MARK: Helpers

/// Out on the canvas, away from your windows, so a case's windows are only near each other
/// (not so far that zooming out to fit everything would need more than Expanse's smallest zoom).
private let displayOrigin = CGPoint(x: 12_000, y: 12_000)

private func displayNear(_ a: CGRect, _ b: CGRect, _ d: CGFloat) -> Bool {
    max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height)) <= d
}

private func displayNear(_ a: CGSize, _ b: CGSize, _ d: CGFloat) -> Bool {
    abs(a.width - b.width) <= d && abs(a.height - b.height) <= d
}

/// `k` times the size of this display, for expanse://screen.
@MainActor private func displaySmallScreen(_ t: Ctx, _ k: CGFloat) -> CGSize {
    CGSize(width: (t.screen.width * k).rounded(), height: (t.screen.height * k).rounded())
}

/// The canvas point in the middle of the view.
private func displayMiddle(_ s: ExpanseState) -> CGPoint {
    CGPoint(x: s.camera.x + s.viewport.width / (2 * s.scale), y: s.camera.y + s.viewport.height / (2 * s.scale))
}

/// `a` is beside `b`: the standard 20pt from it, side by side or one above the other.
private func displayBeside(_ a: CGRect, _ b: CGRect) -> Bool {
    let across = min(a.maxY, b.maxY) - max(a.minY, b.minY) > 0, along = min(a.maxX, b.maxX) - max(a.minX, b.minX) > 0
    let xGap = max(a.minX - b.maxX, b.minX - a.maxX), yGap = max(a.minY - b.maxY, b.minY - a.maxY)
    return (abs(xGap - 20) <= 1 && across) || (abs(yGap - 20) <= 1 && along)
}

/// No click or key press (yours or posted) for `seconds`: what Expanse goes by to tell your
/// switches from macOS's.
private func displayNoInput(for seconds: TimeInterval) -> Bool {
    [CGEventType.leftMouseDown, .rightMouseDown, .keyDown, .flagsChanged].allSatisfy {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) >= seconds
    }
}

private func displayScreenLocked() -> Bool {
    (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
}

private func displayRun(_ path: String, _ arguments: [String], wait: Bool = true) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = arguments
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    if wait { p.waitUntilExit() }
}

/// Where layout.json has each window (by window ID in this process).
@MainActor private func displaySavedSpots(_ ws: [TestWindow]) -> [CGWindowID: CGPoint] {
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Expanse/layout.json")
    guard let data = try? Data(contentsOf: url), let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let entries = json["windows"] as? [[String: Any]] else { return [:] }
    var spots: [CGWindowID: CGPoint] = [:]
    for e in entries where (e["pid"] as? Int) == Int(getpid()) {
        guard let id = e["id"] as? Int, let x = e["x"] as? Double, let y = e["y"] as? Double else { continue }
        spots[CGWindowID(id)] = CGPoint(x: x, y: y)
    }
    return spots.filter { id, _ in ws.contains { $0.id == id } }
}

/// The longest Expanse took to answer an Accessibility question, asked every 50ms for `seconds`,
/// off the main thread (so Expanse Tests can answer Expanse about its windows meanwhile).
private func displayWorstAnswer(pid: pid_t, for seconds: TimeInterval) -> Task<TimeInterval, Never> {
    Task.detached {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 10)
        var worst: TimeInterval = 0
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            let asked = Date()
            var value: AnyObject?
            _ = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
            worst = max(worst, Date().timeIntervalSince(asked))
            usleep(50_000)
        }
        return worst
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for e in self { out.append(try await transform(e)) }
        return out
    }
}

/// What a watcher noted (see displayWatch).
@MainActor private final class DisplayTimes {
    var settled: Date?
}

@MainActor private final class DisplayOpened {
    var app: Fixture?
    var later: TestWindow?
}

/// Something done in the background once a line turns up in the log, while you're asked to do
/// something (lock the Mac, say).
private struct DisplayWatcher {
    let task: Task<Date?, Error>
    let text: String
    let mark: Int
}

@MainActor private extension Ctx {
    /// A row of `count` windows far out on the canvas, the view on the first: those beyond the
    /// screen are parked.
    func displayRow(_ prefix: String, count: Int) async throws -> [TestWindow] {
        let ws = try await row((1...count).map { "\(prefix) \($0)" }, size: CGSize(width: 420, height: 300), origin: displayOrigin)
        link("focus", ["id": ws[0].id])
        try await until("the first window in view") { try await self.settle().window(ws[0].id)?.parked == false }
        return ws
    }

    /// A big window (wider than a `small` screen, though not this one) and one 20pt to its right,
    /// far out on the canvas.
    func displayBigAndBeside(_ prefix: String, widerThan small: CGSize) async throws -> (TestWindow, TestWindow) {
        let bigWidth = min(screen.width - 120, small.width + 240)
        guard bigWidth > small.width + 60 else { throw Skip("this display is too small for a window wider than a smaller screen") }
        let big = try await window("\(prefix) Big", CGRect(x: 40, y: 90, width: bigWidth, height: 300))
        let beside = try await window("\(prefix) Beside", CGRect(x: 200, y: 200, width: 420, height: 280))
        place(big, at: displayOrigin)
        try await settle()
        let f = try await canvasFrame(big)
        place(beside, at: CGPoint(x: f.maxX + 20, y: f.minY))
        try await settle()
        try await pause(1.2)
        return (big, beside)
    }

    /// A fixture app with its window parked far away, and a window of yours ("Here") at 100% in
    /// the middle of the view, the one you're in.
    func displayAwayAppAndHere(_ prefix: String) async throws -> (Fixture, CGWindowID, TestWindow) {
        let f = try await fixture("\(prefix) Outlook")
        guard let id = f.windows.first else { throw Failure("the fixture has no window") }
        try await until("Expanse to take on the fixture's window", timeout: 10) { try await self.state().window(id) != nil }
        link("place", ["id": id, "x": Int(displayOrigin.x) + 6000, "y": Int(displayOrigin.y) + 3000, "commit": 1])
        let here = try await window("\(prefix) Here", CGRect(x: 200, y: 200, width: 520, height: 360))
        place(here, at: displayOrigin)
        link("focus", ["id": here.id])
        try await until("the app's window parked and Here in view", timeout: 10) {
            let s = try await self.settle()
            return s.window(id)?.parked == true && s.window(here.id)?.parked == false
        }
        return (f, id, here)
    }

    /// Brings the fixture app forward (as ⌘-Tab or macOS would), and waits until it's in front.
    func displaySwitch(to f: Fixture) async throws {
        if let app = f.app { NSApp.yieldActivation(to: app) }
        f.activate()
        try await f.send("focus", ["index": "0"])
        do {
            try await until("the app in front", timeout: 3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == f.pid }
        } catch {
            throw Skip("macOS didn't bring the fixture app forward (it refused the activation)")
        }
    }

    /// expanse://screen (a size, or nil for the display's own), and the re-layout that follows done.
    func displayScreen(_ size: CGSize?) async throws {
        let mark = log.mark()
        if let size { link("screen", ["w": Int(size.width), "h": Int(size.height)]) } else { link("screen") }
        try await displayAfterRelayout(since: mark, timeout: 10)
    }

    /// Waits for the re-layout after a display change, an unlock or a wake (since `mark`) to finish.
    func displayAfterRelayout(since mark: Int, timeout: TimeInterval = 15) async throws {
        try await expectLog("layout fitted:", since: mark, timeout: timeout)
        try await pause(1)
        try await settle(timeout: 15)
    }

    /// The lock and unlock lines since `mark`, in that order; where the unlock line is.
    func displayLockedThenUnlocked(since mark: Int) async throws -> Int {
        let locked = try await displayLogIndex("locked: window moves not followed until unlocked", since: mark, timeout: 2)
        return try await displayLogIndex("unlocked: re-placing windows", since: locked, timeout: 10)
    }

    /// Where in the log the first line since `mark` containing `text` is (a mark to look on from).
    func displayLogIndex(_ text: String, since mark: Int, timeout: TimeInterval = 8) async throws -> Int {
        guard await log.wait(since: mark, timeout: timeout, { $0.contains(text) }) != nil,
              let i = log.lines(since: mark).firstIndex(where: { $0.contains(text) }) else {
            throw Failure("no log line containing “\(text)”")
        }
        return mark + i
    }

    /// When a line containing `text` turns up after `mark` (nil if it doesn't within `timeout`).
    func displayWaitFor(_ text: String, since mark: Int, timeout: TimeInterval) async -> Date? {
        let deadline = Date().addingTimeInterval(timeout)
        while !Task.isCancelled, Date() < deadline {
            if log.lines(since: mark).contains(where: { $0.contains(text) }) { return Date() }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }

    /// Runs `action` as soon as a log line containing `text` turns up after `mark`, in the
    /// background. See displayWatched for when.
    func displayWatch(for text: String, since mark: Int, _ action: @escaping @MainActor () async throws -> Void) -> DisplayWatcher {
        let task = Task { @MainActor () throws -> Date? in
            guard let seen = await self.displayWaitFor(text, since: mark, timeout: 1800) else { return nil }
            try await action()
            return seen
        }
        return DisplayWatcher(task: task, text: text, mark: mark)
    }

    /// When the watcher's line turned up, once its action is done; nil (and it's stopped) if the
    /// line doesn't turn up within `timeout`.
    func displayWatched(_ w: DisplayWatcher, timeout: TimeInterval = 2) async throws -> Date? {
        guard await displayWaitFor(w.text, since: w.mark, timeout: timeout) != nil else {
            w.task.cancel()
            return nil
        }
        return try await w.task.value
    }

    /// Asks you to do something while watchers wait on the log; stops them if you can't.
    func displayAsk(_ instruction: String, _ watchers: [DisplayWatcher]) async throws {
        do {
            try await ask(instruction)
        } catch {
            watchers.forEach { $0.task.cancel() }
            throw error
        }
    }

    /// Runs `body`, which quits Expanse, and has Expanse running again afterwards, failed or not.
    func displayRelaunchingAfter(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch {
            if expanse == nil { try? await launchExpanse() }
            throw error
        }
        if expanse == nil { try await launchExpanse() }
    }

    /// Each window has the same spot and size on the canvas, and is parked or not, as before.
    func displayExpectSame(_ ws: [TestWindow], _ before: ExpanseState, _ after: ExpanseState) throws {
        for w in ws {
            guard let a = before.window(w.id) else { continue }
            guard let b = after.window(w.id) else { throw Failure("\(w.title) left the canvas") }
            try expectNear(b.canvas, a.canvas, within: 1, "\(w.title)'s spot on the canvas")
            try expect(b.parked == a.parked, "\(w.title) should still be \(a.parked ? "parked (out of view)" : "on screen")")
        }
    }

    /// The big window and the one beside it fitted to the screen Expanse has now: the big one
    /// (chosen `chosen`) capped at the screen less 16pt each side, the other still 20pt to its
    /// right, nothing bigger than the screen, no overlap.
    func displayExpectFitted(_ s: ExpanseState, big: TestWindow, beside: TestWindow, chosen: CGSize) throws {
        guard let fb = s.window(big.id)?.canvas, let fs = s.window(beside.id)?.canvas else { throw Failure("a window left the canvas") }
        let vp = s.viewport.size
        for (w, f) in [(big, fb), (beside, fs)] {
            try expect(f.width <= vp.width + 1 && f.height <= vp.height + 1, "\(w.title) (\(f.size)) should fit the \(vp) screen")
        }
        if chosen.width > vp.width {
            try expect(abs(fb.width - (vp.width - 32)) <= 1, "the big window should be the screen less 16pt each side (\(vp.width - 32) wide), not \(fb.width)")
        }
        try expect(abs(fs.minX - fb.maxX - 20) <= 1 && abs(fs.minY - fb.minY) <= 1, "the window beside the big one should stay 20pt to its right (\(fb), \(fs))")
        try expect(!fb.insetBy(dx: 0.5, dy: 0.5).intersects(fs), "the windows overlap after fitting")
    }

    func displayExpectInPlace(_ ws: [TestWindow], timeout: TimeInterval = 5) async throws {
        try await displayExpectInPlace(ids: ws.map { ($0.id, $0.title) }, timeout: timeout)
    }

    /// Every window is where the canvas has it: on screen at its spot and size for the camera, or
    /// parked in the bottom-right corner.
    func displayExpectInPlace(ids: [(CGWindowID, String)], timeout: TimeInterval = 5) async throws {
        var problem = ""
        do {
            try await until("every window where the canvas has it", timeout: timeout) {
                let s = try await self.state()
                problem = ""
                for (id, name) in ids {
                    guard let c = s.window(id) else { problem = "\(name) isn't on the canvas"; break }
                    guard let real = realFrame(id) else { problem = "\(name) has no window"; break }
                    if c.parked {
                        if real.minX < s.viewport.maxX - 200 || real.minY < s.viewport.maxY - 260 {
                            problem = "\(name) is parked, but at \(NSStringFromRect(real)), not in the corner"; break
                        }
                    } else {
                        let p = s.screenPoint(c.canvas.origin)
                        if hypot(real.minX - p.x, real.minY - p.y) > 2 || !displayNear(real.size, c.canvas.size, 2) {
                            problem = "\(name) is at \(NSStringFromRect(real)), but the canvas has it at \(NSStringFromRect(CGRect(origin: p, size: c.canvas.size)))"; break
                        }
                    }
                }
                return problem.isEmpty
            }
        } catch {
            throw Failure(problem.isEmpty ? "\(error)" : problem)
        }
    }
}
