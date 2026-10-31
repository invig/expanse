import AppKit
import Security

/// The manual cases in docs/regression/security.md.
///
/// SEC-04 and SEC-28 need a Developer ID–signed release, and Expanse Tests drives a development
/// build: given `--release /path/to/Expanse.app` they quit the development build, run the release
/// for the case, and start the development build again; without it they're skipped.
@MainActor enum SEC {
    static let cases: [Case] = [
        Case("SEC-04", "Debug link commands are ignored by release builds") { t in
            let debug = expanseDefault("debugURLCommands")
            setExpanseDefault("debugURLCommands", true)
            defer { setExpanseDefault("debugURLCommands", debug) }
            let f = try await t.fixture("SEC-04", windows: 1)
            guard let id = f.windows.first, let fixture = f.pid else { throw Failure("the fixture has no window") }
            let start = t.log.mark()
            try await secWithRelease(t) { release, _ in
                if let line = t.log.lines(since: start).first(where: { $0.hasPrefix("accessibility=") }), line.contains("false") {
                    throw Skip("the release can't manage windows here (\(line)): give it Accessibility and Screen Recording")
                }
                guard await t.log.wait(since: start, timeout: 15, { $0.hasPrefix("tracking ") && $0.contains("[\(id)]") }) != nil else {
                    throw Skip("the release didn't take on the fixture's window (is its walkthrough done?)")
                }
                try await t.pause(2)
                let frame = realFrame(id)
                let snapshots = secSnapshots()
                let logging = secSetting("detailedLogging") as? Bool
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("SEC-04", forType: .string)
                // 1: every debug command, each ignored.
                let mark = t.log.mark()
                let links = ["place?id=\(id)&x=0&y=0&commit=1", "prefer?id=\(id)&w=800&h=600", "dump", "screen?w=1280&h=800", "update",
                             "appearance?mode=dark", "logging?on=1", "copylogs", "snapshot", "poweroff"]
                for link in links {
                    try await secOpen("expanse://\(link)", with: release)
                    try await t.pause(0.1)
                }
                for link in links {
                    let name = String(link.prefix { $0 != "?" })
                    try await t.expectLog("ignored debug URL command \(name) (debugURLCommands is off)", since: mark, timeout: 5)
                }
                try await t.pause(2)
                let lines = t.log.lines(since: mark)
                for sign in ["dump viewport=", "display changed:", "logging out or restarting", "preferred size", "update check failed",
                             "up to date", "update available", "paused"] {
                    if let ran = lines.first(where: { $0.hasPrefix(sign) }) { throw Failure("a debug command ran in the release: “\(ran)”") }
                }
                if let frame, let now = realFrame(id) { try t.expectNear(now, frame, within: 2, "the fixture's window after place in the release") }
                try t.expect(secSnapshots() == snapshots, "snapshot made a snapshot in the release")
                try t.expect(NSPasteboard.general.string(forType: .string) == "SEC-04", "copylogs put a report on the clipboard in the release")
                let loggingNow = secSetting("detailedLogging") as? Bool
                if loggingNow != logging { setExpanseDefault("detailedLogging", logging) }
                try t.expect(loggingNow == logging, "logging changed Detailed Logging in the release")
                // 2: focus?id= does nothing; focus?app= still goes to the app's front window.
                bringToFront(.current)
                try await t.until("Expanse Tests in front", timeout: 5) { NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() }
                var m = t.log.mark()
                try await secOpen("expanse://focus?id=\(id)", with: release)
                try await t.expectLog("url command focus", since: m, timeout: 5)
                if let waiting = t.log.lines(since: m).first(where: { $0.contains("walkthrough is done") }) { throw Skip("the release isn't started: \(waiting)") }
                try await t.pause(2)
                try t.expect(NSWorkspace.shared.frontmostApplication?.processIdentifier != fixture, "focus?id= focused the window in the release")
                try t.expect(!t.log.lines(since: m).contains { $0.hasPrefix("glide to") || $0.hasPrefix("centre ") }, "focus?id= glided in the release")
                m = t.log.mark()
                try await secOpen("expanse://focus?app=Expanse%20Tests", with: release)
                try await t.until("focus?app= to bring the fixture's window forward", timeout: 8) {
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == fixture
                }
                try await t.expectLog("glide to", since: m, timeout: 2)
            }
        },
        Case("SEC-14", "A link from a web page asks before it runs", .guided) { t in
            try secNeedsSafari()
            guard let expanse = t.expanse?.processIdentifier else { throw Failure("Expanse isn't running") }
            try await t.window("SEC-14 A")
            try t.open(try secPage("SEC-14", "<p><a href=\"expanse://tidy\">Tidy</a></p>"), in: "Safari")
            var mark = t.log.mark()
            try await t.ask("In Safari, click “Tidy” on the Expanse Tests page (or type expanse://tidy into its address bar), and allow Safari to open Expanse. "
                            + "Leave Expanse's question unanswered, and click Done.")
            try await t.expectLog("url command tidy from Safari", since: mark, timeout: 10)
            try t.expect(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.invignation.expanse", "Expanse didn't come forward with its question")
            try t.expect(secModalUp(expanse), "Expanse isn't asking about the link")
            if AXIsProcessTrusted() {
                guard let d = secDialog(expanse) else { throw Failure("couldn't read Expanse's question with Accessibility") }
                let message = "A web page in Safari wants Expanse to run \u{201C}tidy\u{201D}"
                let detail = "Links from web pages can move your windows and switch apps. Allow it only if you clicked the link yourself, expecting this."
                try t.expect(d.texts.contains(message) && d.texts.contains(detail), "Expanse's question says: \(d.texts)")
                try t.expect(d.buttons.sorted() == ["Allow", "Don't Allow"], "the question's buttons: \(d.buttons)")
                try t.expect(d.defaultButton == "Don't Allow", "the default button is \(d.defaultButton ?? "none") (Don't Allow expected)")
            } else {
                try await t.look("Does Expanse ask “A web page in Safari wants Expanse to run “tidy””, saying links from web pages can move your windows "
                                 + "and switch apps, with Don't Allow as the default button and Allow beside it?")
            }
            mark = t.log.mark()
            try await t.ask("In Expanse's question, click Don't Allow. Then click Done.")
            try await t.expectLog("URL command tidy from a web page in Safari: not allowed", since: mark, timeout: 5)
            try await t.noLog("layout fitted:", since: mark, within: 1.5)
            let after = try await t.state()
            try t.expect(!after.active, "tidy ran after Don't Allow")
            // It asks every time; Allow runs it.
            mark = t.log.mark()
            let asked = secWatch { secModalUp(expanse) }
            try await t.ask("Click “Tidy” in Safari again (allowing Safari again if it asks). When Expanse asks, click Allow. Then click Done.")
            asked.cancel()
            try await t.expectLog("url command tidy from Safari", since: mark, timeout: 5)
            try t.expect(await asked.value, "Expanse didn't ask the second time (it should ask every time)")
            try await t.expectLog("layout fitted:", since: mark, timeout: 6)
        },
        Case("SEC-15", "A web page's link while zoomed out is refused without asking", .guided) { t in
            try secNeedsSafari()
            // The catalogue has Chrome set to always allow the page. Here Safari asks, and Expanse
            // Tests answers Allow for you once the canvas covers Safari's question.
            guard AXIsProcessTrusted() else {
                throw Skip("needs Accessibility for Expanse Tests, to click Allow in Safari's question while the canvas covers it")
            }
            guard let expanse = t.expanse?.processIdentifier else { throw Failure("Expanse isn't running") }
            try await t.window("SEC-15 A")
            try t.open(try secPage("SEC-15", "<p><a href=\"expanse://tidy\">Tidy</a></p>"), in: "Safari")
            var mark = t.log.mark()
            try await t.ask("In Safari, click “Tidy” on the Expanse Tests page. When Safari asks whether to allow the page to open Expanse, "
                            + "don't answer it: click Done here.")
            if let ran = t.log.lines(since: mark).first(where: { $0.hasPrefix("url command tidy") }) {
                // Safari didn't ask: Expanse got it at 100%, and asks itself.
                if let d = secDialog(expanse), let no = d.elements["Don't Allow"] { AXUIElementPerformAction(no, kAXPressAction as CFString) }
                throw Skip("Safari opened the link without asking (“\(ran)”), so it couldn't arrive while zoomed out")
            }
            guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first?.processIdentifier else {
                throw Failure("Safari isn't running")
            }
            guard secButton("Allow", in: safari) != nil else { throw Failure("couldn't find Allow in Safari's question (with Accessibility)") }
            t.link("enter")
            try await t.until("the canvas to open", timeout: 8) { try await t.settle().active }
            mark = t.log.mark()
            let asked = secWatch(for: 6) { secModalUp(expanse) }
            guard let allow = secButton("Allow", in: safari) else { throw Failure("Safari's Allow button went away") }
            AXUIElementPerformAction(allow, kAXPressAction as CFString)
            try await t.expectLog("url command tidy from Safari", since: mark, timeout: 8)
            try await t.expectLog("URL command tidy from a web page in Safari: not allowed", since: mark, timeout: 3)
            try t.expect(!(await asked.value), "Expanse asked about the link under the canvas")
            try await t.noLog("layout fitted:", since: mark, within: 1.5)
            let s = try await t.state()
            try t.expect(s.active, "the canvas closed")
        },
        Case("SEC-16", "welcome and menu links from a web page run without asking", .guided) { t in
            try secNeedsSafari()
            guard let expanse = t.expanse?.processIdentifier else { throw Failure("Expanse isn't running") }
            try t.open(try secPage("SEC-16", "<p><a href=\"expanse://menu\">Menu</a></p><p><a href=\"expanse://welcome\">Welcome</a></p>"), in: "Safari")
            // 1: the menu bar panel.
            var mark = t.log.mark()
            let panel = secWatch(for: 3600) { secWindows(expanse).contains { $0.layer == secPopUpLevel && $0.frame.height >= 200 } }
            var asked = secWatch(for: 3600) { secModalUp(expanse) }
            try await t.ask("In Safari, click “Menu” on the Expanse Tests page and allow Safari to open Expanse. Then click Done.")
            panel.cancel()
            asked.cancel()
            try await t.expectLog("url command menu from Safari", since: mark, timeout: 5)
            try t.expect(await panel.value, "the menu bar panel didn't open")
            try t.expect(!(await asked.value), "Expanse asked about the menu link")
            if let refused = t.log.lines(since: mark).first(where: { $0.contains("not allowed") }) { throw Failure(refused) }
            // 2: the walkthrough.
            mark = t.log.mark()
            let before = Set(secWindows(expanse).filter { $0.layer == 0 }.map(\.id))
            let axBefore = secAXWindows(expanse)
            asked = secWatch(for: 3600) { secModalUp(expanse) }
            try await t.ask("Now click “Welcome” on the page (allowing Safari again if it asks). Then click Done.")
            asked.cancel()
            try await t.expectLog("url command welcome from Safari", since: mark, timeout: 5)
            try t.expect(!(await asked.value), "Expanse asked about the welcome link")
            if let refused = t.log.lines(since: mark).first(where: { $0.contains("not allowed") }) { throw Failure(refused) }
            let opened = secWindows(expanse).filter { $0.layer == 0 && !before.contains($0.id) }
            try t.expect(!opened.isEmpty, "the walkthrough didn't open")
            // Closed again.
            let new = secAXWindows(expanse).filter { w in !axBefore.contains { CFEqual($0, w) } }
            let closers = new.compactMap { secAXElement($0, kAXCloseButtonAttribute) }
            if closers.isEmpty {
                try await t.ask("Close Expanse's welcome window. Then click Done.")
            } else {
                for c in closers { AXUIElementPerformAction(c, kAXPressAction as CFString) }
            }
        },
        Case("SEC-17", "Links from scripts and other apps run without asking") { t in
            guard let expanse = t.expanse?.processIdentifier else { throw Failure("Expanse isn't running") }
            try await t.window("SEC-17 A")
            let senders: [(String, @MainActor () throws -> Void)] = [
                ("Expanse Tests (another app)", { t.link("tidy") }),
                ("`open` in Terminal", { try secRunNow("/usr/bin/open", ["expanse://tidy"]) }),
                ("a script, as Shortcuts or Raycast run it (osascript)", { try secRunNow("/usr/bin/osascript", ["-e", "open location \"expanse://tidy\""]) }),
            ]
            for (sender, send) in senders {
                let mark = t.log.mark()
                try send()
                guard let line = await t.log.wait(since: mark, timeout: 8, { $0.hasPrefix("url command tidy") }) else {
                    throw Failure("no “url command tidy” line for a link from \(sender)")
                }
                try t.expect(line == "url command tidy", "a link from \(sender) was taken for a web page's: “\(line)”")
                try await t.expectLog("layout fitted:", since: mark, timeout: 6)
                try t.expect(!secModalUp(expanse), "Expanse asked about a link from \(sender)")
                if let refused = t.log.lines(since: mark).first(where: { $0.hasPrefix("URL command tidy") }) { throw Failure(refused) }
                t.link("exit")
                try await t.until("back at 100%", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
            }
        },
        Case("SEC-18", "Debug link commands work in a development build when turned on") { t in
            let debug = expanseDefault("debugURLCommands")
            defer { setExpanseDefault("debugURLCommands", debug) }
            let a = try await t.window("SEC-18 A")
            let b = try await t.window("SEC-18 B")
            t.place(a, at: CGPoint(x: 7000, y: 5000))
            try await t.until("A out of view", timeout: 8) { try await t.state().window(a.id)?.parked == true }
            b.focus()
            try await t.settle()
            // 1: off, dump (and focus?id=) are ignored.
            setExpanseDefault("debugURLCommands", false)
            var mark = t.log.mark()
            t.link("dump")
            try await t.expectLog("ignored debug URL command dump (debugURLCommands is off)", since: mark)
            t.link("focus", ["id": a.id])
            try await t.expectLog("url command focus", since: mark)
            try await t.pause(2)
            try t.expect(!t.log.lines(since: mark).contains { $0.hasPrefix("dump viewport=") }, "dump ran with debugURLCommands off")
            try t.expect(!t.log.lines(since: mark).contains { $0.hasPrefix("glide to") }, "focus?id= glided with debugURLCommands off")
            // 2: on, dump writes the layout, and focus?id= goes to that window.
            setExpanseDefault("debugURLCommands", true)
            mark = t.log.mark()
            let s = try await t.state()
            try t.expect(s.window(a.id) != nil && s.window(b.id) != nil, "dump should list both windows")
            t.link("focus", ["id": a.id])
            try await t.expectLog("glide to \(s.window(a.id)?.app ?? "Expanse Tests")[\(a.id)]", since: mark)
            try await t.until("the view on A", timeout: 10) {
                let s = try await t.settle()
                guard let f = s.window(a.id)?.canvas else { return false }
                return s.visibleCanvas.contains(CGPoint(x: f.midX, y: f.midY))
            }
        },
        Case("SEC-28", "Unpacking an update stops after a minute", .guided) { t in
            try await secWithRelease(t) { _, app in
                let mark = t.log.mark()
                try await t.ask("In the release of Expanse now running, open Settings (menu bar icon › Settings) and click Check Now, with your stand-in "
                                + "for GitHub's latest-release answer offering a newer version whose zip takes ditto more than a minute to unpack. "
                                + "Then click Done.")
                let available = try await t.expectLog("update available: ", since: mark, timeout: 60)
                let version = String(available.dropFirst("update available: ".count))
                // ditto unpacking it, stopped after 60 s.
                var found: (pid: Int, folder: String)?
                let deadline = Date().addingTimeInterval(300)
                while found == nil {
                    if Date() > deadline { throw Failure("ditto never started unpacking \(version) (see the log: download stopped, or not unpacked?)") }
                    found = await secDitto()
                    if found == nil { try await t.pause(0.5) }
                }
                guard let ditto = found else { return }
                let started = Date()
                while await secDitto()?.pid == ditto.pid {
                    if Date().timeIntervalSince(started) > 120 { throw Failure("ditto still running after 2 minutes (it should be stopped after 60 s)") }
                    try await t.pause(0.5)
                }
                let ran = Date().timeIntervalSince(started)
                if ran < 58 { throw Skip(String(format: "ditto finished in %.0f s: the zip wasn't slow enough to reach the 60 s limit", ran)) }
                try t.expect(ran <= 66, String(format: "ditto was stopped after %.0f s (60 s expected)", ran))
                try await t.pause(3)
                try t.expect(!FileManager.default.fileExists(atPath: ditto.folder), "the temporary folder is still there: \(ditto.folder)")
                let lines = t.log.lines(since: mark)
                if let checked = lines.first(where: { $0.hasPrefix("update \(version) checks:") }) { throw Failure("the update was checked after ditto was stopped: \(checked)") }
                if let installed = lines.first(where: { $0.hasPrefix("installed ") }) { throw Failure("the update was installed: \(installed)") }
                // Not offered: "Couldn't download Expanse <version>".
                try await t.until("Expanse's message", timeout: 10) { secModalUp(app.processIdentifier) }
                if AXIsProcessTrusted(), let d = secDialog(app.processIdentifier) {
                    try t.expect(d.texts.contains("Couldn't download Expanse \(version)"), "Expanse says: \(d.texts)")
                    if let ok = d.elements["OK"] ?? d.elements.values.first { AXUIElementPerformAction(ok, kAXPressAction as CFString) }
                } else {
                    try await t.look("Does Expanse say “Couldn't download Expanse \(version)”?")
                    try await t.ask("Click OK in Expanse's message. Then click Done.")
                }
            }
        },
    ]
}

// MARK: - Helpers

private let secModalLevel = Int(CGWindowLevelForKey(.modalPanelWindow))
private let secPopUpLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))

/// One of Expanse's settings as Expanse has it now (re-read: Expanse writes them itself).
private func secSetting(_ key: String) -> Any? {
    CFPreferencesAppSynchronize("com.invignation.expanse" as CFString)
    return CFPreferencesCopyAppValue(key as CFString, "com.invignation.expanse" as CFString)
}

private func secNeedsSafari() throws {
    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") == nil { throw Skip("needs Safari") }
}

/// A page for the browser cases, in a folder of Expanse Tests' own; its path.
private func secPage(_ name: String, _ body: String) throws -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ExpanseTests", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("\(name).html")
    let html = "<!doctype html><meta charset=\"utf-8\"><title>Expanse Tests \(name)</title>"
        + "<body style=\"font: 28px -apple-system, sans-serif; margin: 48px\"><h1>Expanse Tests: \(name)</h1>\(body)</body>"
    try html.write(to: file, atomically: true, encoding: .utf8)
    return file.path
}

/// Runs a command and waits for it.
private func secRunNow(_ path: String, _ arguments: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = arguments
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
    if p.terminationStatus != 0 { throw Failure("\(path) \(arguments.joined(separator: " ")) failed (status \(p.terminationStatus))") }
}

/// A command's output (run off the main thread).
private func secRun(_ path: String, _ arguments: [String]) async -> String {
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

/// The `ditto -x -k` unpacking an update, if one's running: its pid and the folder it unpacks into.
private func secDitto() async -> (pid: Int, folder: String)? {
    let ps = await secRun("/bin/ps", ["-axo", "pid=,command="])
    for line in ps.split(separator: "\n") where line.contains("ditto -x -k") && line.contains("Expanse-update-") {
        let parts = line.split(separator: " ")
        guard let pid = parts.first.flatMap({ Int($0) }), let folder = parts.last(where: { $0.contains("Expanse-update-") }) else { continue }
        return (pid, String(folder))
    }
    return nil
}

private func secSnapshots() -> Set<String> {
    let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Expanse/Snapshots")
    return Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
}

/// `pid`'s windows on screen: ID, level (layer) and frame.
private func secWindows(_ pid: pid_t) -> [(id: CGWindowID, layer: Int, frame: CGRect)] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid, let id = w[kCGWindowNumber as String] as? CGWindowID,
              let layer = w[kCGWindowLayer as String] as? Int,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) else { return nil }
        return (id, layer, r)
    }
}

/// Expanse is asking something (an alert: a window at the modal panel level).
private func secModalUp(_ pid: pid_t) -> Bool { secWindows(pid).contains { $0.layer == secModalLevel } }

/// Watches (every tenth of a second) for `condition`, until it holds, `seconds` pass or it's
/// cancelled; whether it held.
@MainActor private func secWatch(for seconds: TimeInterval = 3600, _ condition: @escaping @MainActor () -> Bool) -> Task<Bool, Never> {
    Task { @MainActor in
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline && !Task.isCancelled {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return condition()
    }
}

// Accessibility, to read and answer questions.

private func secAX(_ e: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success ? value : nil
}

private func secAXString(_ e: AXUIElement, _ attribute: String) -> String? { secAX(e, attribute) as? String }

private func secAXElements(_ e: AXUIElement, _ attribute: String) -> [AXUIElement] { secAX(e, attribute) as? [AXUIElement] ?? [] }

private func secAXElement(_ e: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let v = secAX(e, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

private func secAXWindows(_ pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    return secAXElements(app, kAXWindowsAttribute)
}

/// Elements under `root`, a level at a time, until `match` accepts one (or `limit` are looked at).
private func secAXFind(_ root: AXUIElement, depth: Int = 14, limit: Int = 5000, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    var level = [root], seen = 0
    for _ in 0..<depth where !level.isEmpty && seen < limit {
        level = level.flatMap { secAXElements($0, kAXChildrenAttribute) }
        seen += level.count
        if let hit = level.first(where: match) { return hit }
    }
    return nil
}

/// A button titled `title` in one of `pid`'s windows (a question it's showing).
private func secButton(_ title: String, in pid: pid_t) -> AXUIElement? {
    for w in secAXWindows(pid) {
        if let b = secAXFind(w, { secAXString($0, kAXRoleAttribute) == kAXButtonRole && secAXString($0, kAXTitleAttribute) == title }) { return b }
    }
    return nil
}

/// What a question (an alert) of `pid`'s says, its buttons, and which is the default.
private struct SecDialog {
    let texts: [String]
    let elements: [String: AXUIElement]
    let defaultButton: String?
    var buttons: [String] { Array(elements.keys) }
}

private func secDialog(_ pid: pid_t) -> SecDialog? {
    for w in secAXWindows(pid) {
        var all: [AXUIElement] = [], level = [w]
        for _ in 0..<5 {
            level = level.flatMap { secAXElements($0, kAXChildrenAttribute) }
            all += level
        }
        var buttons: [String: AXUIElement] = [:]
        for e in all where secAXString(e, kAXRoleAttribute) == kAXButtonRole {
            if let title = secAXString(e, kAXTitleAttribute), !title.isEmpty { buttons[title] = e }
        }
        let texts = all.filter { secAXString($0, kAXRoleAttribute) == kAXStaticTextRole }.compactMap { secAXString($0, kAXValueAttribute) }
        guard secAXString(w, kAXSubroleAttribute) == kAXDialogSubrole || secAXString(w, kAXSubroleAttribute) == kAXSystemDialogSubrole,
              !buttons.isEmpty else { continue }
        let defaultButton = secAXElement(w, kAXDefaultButtonAttribute).flatMap { secAXString($0, kAXTitleAttribute) }
        return SecDialog(texts: texts, elements: buttons, defaultButton: defaultButton)
    }
    return nil
}

// A release build, for the cases that need one.

/// Signed with a Developer ID, as Expanse's Updater.isRelease checks itself.
private func secDeveloperIDSigned(_ app: URL) -> Bool {
    var code: SecStaticCode?
    var requirement: SecRequirement?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
          SecRequirementCreateWithString("anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]" as CFString,
                                         [], &requirement) == errSecSuccess, let requirement
    else { return false }
    return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
}

/// Opens a link in that copy of Expanse (both copies answer expanse:// links).
@MainActor private func secOpen(_ link: String, with app: URL) async throws {
    guard let url = URL(string: link) else { throw Failure("bad link \(link)") }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
}

/// Runs `body` with the release given by --release in place of the development build, which is
/// quit first and started again after.
@MainActor private func secWithRelease(_ t: Ctx, _ body: (URL, NSRunningApplication) async throws -> Void) async throws {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--release"), args.indices.contains(i + 1) else {
        throw Skip("needs a Developer ID–signed release (Expanse Tests drives a development build): run with --release /path/to/Expanse.app")
    }
    let url = URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath)
    guard Bundle(url: url)?.bundleIdentifier == "com.invignation.expanse" else { throw Skip("--release \(url.path) isn't a copy of Expanse") }
    guard secDeveloperIDSigned(url) else { throw Skip("--release \(url.path) isn't signed with a Developer ID, so it isn't a release") }
    guard url.standardizedFileURL != t.expanseURL.standardizedFileURL else { throw Skip("--release is the copy Expanse Tests drives") }
    try await t.quitExpanse()
    try await t.pause(1)
    var failure: Error?
    var release: NSRunningApplication?
    do {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        release = app
        // Up once it handles links: a debug one is ignored before anything else is looked at.
        try await t.until("the release to answer links", timeout: 25) {
            let mark = t.log.mark()
            try await secOpen("expanse://dump", with: url)
            return await t.log.wait(since: mark, timeout: 2, { $0.hasPrefix("ignored debug URL command dump") || $0.hasPrefix("dump viewport=") }) != nil
        }
        try await body(url, app)
    } catch {
        failure = error
    }
    // Back to the development build.
    if let release, !release.isTerminated {
        release.terminate()
        for _ in 0..<150 where !release.isTerminated { try? await Task.sleep(nanoseconds: 100_000_000) }
    }
    if release?.isTerminated == false {
        throw failure ?? Failure("the release didn't quit, so the development build wasn't started again")
    }
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    try await t.launchExpanse()
    if let failure { throw failure }
}
