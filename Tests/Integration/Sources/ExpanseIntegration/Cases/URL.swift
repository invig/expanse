import AppKit

/// The manual cases in docs/regression/url-scripting.md. (Named so as not to hide Foundation's URL.)
@MainActor enum URLCases {
    static let cases: [Case] = [
        Case("URL-01", "expanse://toggle") { t in
            try await t.window("URL-01 A")
            t.link("toggle")
            try await t.until("the canvas to open") { try await t.state().active }
            try await t.expectLog("url command toggle")
            t.link("toggle")
            try await t.until("back at 100%") { let s = try await t.state(); return !s.active && s.idle }
            t.link("pause")
            try await t.until("paused") { try await t.state().paused }
            t.link("toggle")
            try await t.until("toggle to resume") { try await !t.state().paused }
        },
        Case("URL-02", "expanse://enter") { t in
            try await t.window("URL-02 A")
            t.link("enter")
            let out = try await t.settle()
            try t.expect(out.active && out.scale < 1, "enter should open the canvas zoomed out (scale \(out.scale))")
            t.link("exit")
            let back = try await t.settle()
            try t.expect(!back.active, "exit should go back to 100%")
            t.link("enter", ["zoomOut": 0])
            let at100 = try await t.settle()
            try t.expect(at100.active && abs(at100.scale - 1) < 0.001, "enter?zoomOut=0 should open the canvas at 100% (scale \(at100.scale))")
            try t.expectNear(at100.camera, back.camera, "enter?zoomOut=0 moved the view")
        },
        Case("URL-03", "expanse://exit") { t in
            try await t.window("URL-03 A")
            let before = try await t.settle()
            t.link("exit")
            let still = try await t.settle()
            try t.expect(!still.active, "exit at 100% should do nothing")
            try t.expectNear(still.camera, before.camera, "exit at 100% moved the view")
            t.link("enter")
            try await t.until("zoomed out") { try await t.settle().active }
            t.link("exit")
            let s = try await t.settle()
            try t.expect(!s.active && abs(s.scale - 1) < 0.001, "exit should leave the canvas at 100%")
        },
        Case("URL-07", "expanse://focus?app=") { t in
            // A real app with a name of its own (fixtures share Expanse Tests' name).
            let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.calculator").isEmpty
            try t.open("/System/Applications/Calculator.app")
            var id: CGWindowID = 0
            try await t.until("Expanse to take on Calculator's window", timeout: 15) {
                id = try await t.state().windows.last(where: { $0.app == "Calculator" })?.id ?? 0
                return id != 0
            }
            let mine = try await t.window("URL-07 Mine")
            // Put Calculator's window far out of view, and stay on ours.
            t.link("place", ["id": id, "x": 6000, "y": 4000, "commit": 1])
            mine.focus()
            try await t.until("Calculator out of view") { try await t.settle().window(id)?.parked == true }
            t.link("focus", ["app": "calculator"])
            try await t.until("a glide to Calculator's window") {
                let s = try await t.settle()
                guard let w = s.window(id) else { return false }
                return !w.parked && s.visibleCanvas.contains(CGPoint(x: w.canvas.midX, y: w.canvas.midY))
            }
            let before = try await t.settle()
            t.link("focus", ["app": "NoSuchApp"])
            try await t.pause(1)
            let after = try await t.settle()
            try t.expect(!after.active, "focus with an unknown app should do nothing")
            try t.expectNear(after.camera, before.camera, "focus with an unknown app moved the view")
            if !wasRunning { NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.calculator").forEach { $0.terminate() } }
        },
        Case("URL-08", "expanse://restore") { t in
            let a = try await t.window("URL-08 A")
            t.place(a, at: CGPoint(x: 8000, y: 6000))
            try await t.until("A out of view") { try await t.state().window(a.id)?.parked == true }
            t.link("restore")
            try await t.until("A back on screen") {
                guard let r = a.real else { return false }
                return t.screen.insetBy(dx: 40, dy: 40).intersects(r)
            }
        },
        Case("URL-09", "expanse://pause and expanse://resume") { t in
            try await t.window("URL-09 A")
            t.link("pause")
            try await t.until("paused") { try await t.state().paused }
            let mark = t.log.mark()
            t.link("pause")
            try await t.noLog("paused", since: mark + 1, within: 2)
            t.link("resume")
            try await t.until("resumed") { try await !t.state().paused }
            try await t.expectLog("resumed")
        },
        Case("URL-10", "expanse://dump writes the layout to the log (debug only)") { t in
            let a = try await t.window("URL-10 A")
            let s = try await t.state()
            try t.expect(s.window(a.id) != nil, "dump should list every window on the canvas")
            try t.expect(s.viewport.width > 0, "dump should give the viewport")
            setExpanseDefault("debugURLCommands", false)
            defer { setExpanseDefault("debugURLCommands", true) }
            let mark = t.log.mark()
            t.link("dump")
            try await t.expectLog("ignored debug URL command dump (debugURLCommands is off)", since: mark)
            try await t.noLog("dump viewport=", since: mark, within: 1.5)
        },
        Case("URL-11", "expanse://screen pretends the display is another size (debug only)") { t in
            let ws = try await t.row(["URL-11 A", "URL-11 B", "URL-11 C"])
            let before = try await t.state()
            let mark = t.log.mark()
            t.link("screen", ["w": 1280, "h": 800])
            try await t.expectLog("display changed:", since: mark, timeout: 10)
            try await t.pause(2)
            t.link("screen")
            try await t.pause(3)
            let after = try await t.settle()
            for w in ws {
                guard let a = before.window(w.id)?.canvas, let b = after.window(w.id)?.canvas else { throw Failure("\(w.title) left the canvas") }
                try t.expectNear(b, a, within: 1, "\(w.title) after the round trip")
            }
        },
        Case("URL-15", "The app is Expanse and answers expanse:// links") { t in
            try t.expect(t.expanse?.bundleIdentifier == "com.invignation.expanse", "the running app should be com.invignation.expanse")
            try t.expect(NSWorkspace.shared.urlForApplication(toOpen: URL(string: "expanse://toggle")!) != nil, "nothing answers expanse:// links")
            try await t.window("URL-15 A")
            t.link("toggle")
            try await t.until("the canvas to open") { try await t.state().active }
            t.link("toggle")
            try await t.until("back at 100%") { try await !t.settle().active }
        },
        Case("URL-21", "expanse://appearance switches Expanse between light and dark", .look) { t in
            try await t.window("URL-21 A")
            t.link("enter")
            try await t.settle()
            t.link("appearance", ["mode": "dark"])
            try await t.look("Expanse's minimap and Spaces panels are dark, and other apps haven't changed?")
            t.link("appearance", ["mode": "light"])
            try await t.look("They're light now?")
            t.link("appearance")
            try await t.look("They follow the Mac's own appearance again?")
        },
        Case("URL-22", "expanse://layout?snapshot=N restores a snapshot from a script") { t in
            let a = try await t.window("URL-22 A")
            t.place(a, at: CGPoint(x: 0, y: 0))
            try await t.settle()
            t.link("snapshot")
            try await t.pause(1.2)
            t.place(a, at: CGPoint(x: 900, y: 300))
            try await t.settle()
            var mark = t.log.mark()
            t.link("layout")
            try await t.expectLog("restored a layout:", since: mark, timeout: 10)
            try await t.until("A back at the snapshot's spot") {
                guard let f = try await t.state().window(a.id)?.canvas else { return false }
                return hypot(f.minX, f.minY) < 2
            }
            for bad in ["7000", "abc"] {
                mark = t.log.mark()
                t.link("layout", ["snapshot": bad])
                try await t.noLog("restored a layout:", since: mark, within: 2)
            }
        },
        Case("URL-23", "expanse://place moves a window's home spot with it") { t in
            let ws = try await t.row(["URL-23 A", "URL-23 B"])
            t.link("screen", ["w": 1280, "h": 800])
            try await t.pause(3)
            try await t.settle()
            // Move B below A, as if dragged there.
            let a = try await t.canvasFrame(ws[0])
            t.place(ws[1], at: CGPoint(x: a.minX, y: a.maxY + 20))
            try await t.settle()
            t.link("screen")
            try await t.pause(3)
            let s = try await t.settle()
            guard let fa = s.window(ws[0].id)?.canvas, let fb = s.window(ws[1].id)?.canvas else { throw Failure("a window left the canvas") }
            try t.expect(fb.minY >= fa.maxY - 1 && abs(fb.minX - fa.minX) < 40, "B should stay below A on the bigger screen (A \(fa), B \(fb))")
        },
        Case("URL-24", "expanse://logging and expanse://copylogs") { t in
            let file = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Expanse/Expanse.log")
            func fileSays(_ text: String) -> Bool { ((try? String(contentsOf: file, encoding: .utf8)) ?? "").contains(text) }
            t.link("logging", ["on": 1])
            try await t.expectLog("url command logging")
            try await t.until("“detailed logging on” in the log file") { fileSays("detailed logging on") }
            NSPasteboard.general.clearContents()
            t.link("copylogs")
            try await t.until("the report on the clipboard") { (NSPasteboard.general.string(forType: .string) ?? "").contains("Expanse") }
            t.link("logging", ["on": 0])
            try await t.until("“detailed logging off” in the log file") { fileSays("detailed logging off") }
            setExpanseDefault("debugURLCommands", false)
            defer { setExpanseDefault("debugURLCommands", true) }
            let mark = t.log.mark()
            t.link("logging", ["on": 1])
            try await t.expectLog("ignored debug URL command logging", since: mark)
        },
        Case("URL-25", "expanse://menu opens the panel", .look) { t in
            t.link("menu")
            try await t.expectLog("url command menu")
            try await t.look("The menu bar panel opened under Expanse's icon, as if you'd clicked it?")
            if Input.allowed { Input.key(.escape) }
        },
        Case("URL-26", "expanse://snapshot takes a snapshot (development builds)") { t in
            try await t.window("URL-26 A")
            let folder = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Expanse/Snapshots")
            func newest() -> String? {
                (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { $0.hasSuffix(".json") }.max()
            }
            let before = newest()
            try await t.pause(1.1)
            t.link("snapshot")
            try await t.until("a new snapshot file") { newest() != nil && newest() != before }
            let count = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { $0.hasSuffix(".json") }.count ?? 0
            try t.expect(count <= 3, "at most three snapshots are kept (\(count))")
            setExpanseDefault("debugURLCommands", false)
            defer { setExpanseDefault("debugURLCommands", true) }
            let mark = t.log.mark()
            t.link("snapshot")
            try await t.expectLog("ignored debug URL command snapshot (debugURLCommands is off)", since: mark)
        },
        Case("URL-27", "expanse://poweroff runs the logout handling (development builds)") { t in
            let a = try await t.window("URL-27 A")
            t.place(a, at: CGPoint(x: 7000, y: 5000))
            try await t.until("A parked") { try await t.state().window(a.id)?.parked == true }
            t.link("poweroff")
            try await t.expectLog("logging out or restarting")
            try await t.until("paused, windows back") { try await t.state().paused }
            try await t.until("A back on screen") { a.real.map { t.screen.intersects($0.insetBy(dx: 40, dy: 40)) } ?? false }
            t.link("resume")
            try await t.until("resumed") { try await !t.state().paused }
            setExpanseDefault("debugURLCommands", false)
            defer { setExpanseDefault("debugURLCommands", true) }
            let mark = t.log.mark()
            t.link("poweroff")
            try await t.expectLog("ignored debug URL command poweroff (debugURLCommands is off)", since: mark)
        },
    ]
}
