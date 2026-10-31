import AppKit

/// The manual cases in docs/regression/troubleshooting.md.
@MainActor enum SUPPORT {
    static let cases: [Case] = [
        Case("SUPPORT-01", "The log records every move, resize and glide") { t in
            try t.needsInput()
            if supportControlRightTaken() {
                throw Skip("macOS's own ⌃→ shortcut (Move right a space) is on, so ⌃→ never reaches Expanse")
            }
            // Titles that mustn't turn up in the log. B is another app's window: one of Expanse
            // Tests' own can't be dragged by posted events.
            let a = try await t.window("SUPPORT-01 Plum")
            let f = try await t.fixture("SUPPORT-01 Quince")
            guard let b = f.windows.first else { throw Failure("the fixture has no window") }
            try await t.until("Expanse to take on B", timeout: 10) { try await t.state().window(b) != nil }
            // Far from every other window, so ⌃→ from A can only go to B.
            t.place(a, at: CGPoint(x: 41_000, y: 41_000))
            try await t.settle()
            let row = try await t.canvasFrame(a)
            t.link("place", ["id": b, "x": Int(row.maxX + 20), "y": Int(row.minY), "commit": 1])
            try await t.settle()
            try await t.supportFocus(a.id)
            // B half off the screen's right edge, with a bigger size to grow to, so the hop glides
            // to it and resizes it.
            let s = try await t.state()
            guard let bf = s.window(b)?.canvas else { throw Failure("B isn't on the canvas") }
            t.link("place", ["id": b, "x": Int(s.visibleCanvas.maxX - 200), "y": Int(bf.minY), "commit": 1])
            try await t.settle()
            t.link("prefer", ["id": b, "w": Int(bf.width) + 80, "h": Int(bf.height) + 40])
            try await t.expectLog("preferred size ", timeout: 5)
            a.focus()
            try await t.pause(0.5)
            let app = try await t.state().window(b)?.app ?? "Expanse Tests"
            // 1: ⌃→ to a window that isn't fully on screen.
            var mark = t.log.mark()
            Input.key(.right, .maskControl)
            try await t.expectLog("hotkey 11 pressed", since: mark)
            try await t.expectLog("glide to \(app)[\(b)]", since: mark)
            try await t.supportExpectLine(since: mark, "a `resize` or `fit size` line for B") {
                $0.hasPrefix("resize \(app)[\(b)] ") || $0.hasPrefix("fit size \(app)[\(b)] ")
            }
            // A glide moves its windows together, logged as one line naming their apps; a single
            // move (expanse://place, say) as `move <App>[<id>] … (asked …)`.
            try await t.supportExpectLine(since: mark, "a `windows landed after …ms (…)` line for the glide's moves") {
                $0.hasPrefix("windows landed after ") && $0.contains(app)
            }
            try await t.settle()
            // A single move (Restore all windows bringing a parked one back) logs `move …`.
            t.link("place", ["id": b, "x": 47_000, "y": 47_000, "commit": 1])
            try await t.until("B out of view", timeout: 8) { try await t.state().window(b)?.parked == true }
            mark = t.log.mark()
            t.link("restore")
            try await t.supportExpectLine(since: mark, "a `move <App>[<id>] {x, y} -> {x, y} (asked {x, y})` line") {
                $0.firstMatch(of: #/^move .+\[\d+\] \{-?[\d.]+, -?[\d.]+\} -> \{-?[\d.]+, -?[\d.]+\} \(asked \{-?[\d.]+, -?[\d.]+\}\)$/#) != nil
            }
            try await t.settle()
            // 2: at 100%, drag the real window by its title bar.
            guard let real = realFrame(b) else { throw Failure("B has no real window") }
            mark = t.log.mark()
            let grab = CGPoint(x: real.minX + 150, y: real.minY + 12)
            await Input.dragAsync(from: grab, to: CGPoint(x: grab.x + 120, y: grab.y + 60))
            try await t.supportExpectLine(since: mark, "a `follow \(app)[\(b)] moved to {x, y} (last placed …)` line") {
                $0.firstMatch(of: #/^follow .+\[\d+\] moved to \{-?[\d.]+, -?[\d.]+\} \(last placed .+\)$/#) != nil && $0.contains("[\(b)]")
            }
            try await t.settle()
            // 3: ⌥`, then T, then Esc.
            mark = t.log.mark()
            Input.key(.grave, .maskAlternate)
            try await t.expectLog("hotkey 1 pressed", since: mark)
            try await t.until("the canvas to open", timeout: 8) { try await t.settle().active }
            Input.key(.t)
            try await t.expectLog("layout fitted:", since: mark)
            try await t.settle()
            Input.key(.escape)
            try await t.until("back at 100%", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
            // App names appear, but not window titles.
            let lines = t.log.lines(since: t.start)
            try t.expect(lines.contains { $0.contains("\(app)[") }, "no log line names the app")
            if let leak = lines.first(where: { $0.contains("Plum") || $0.contains("Quince") }) {
                throw Failure("a window title is in the log: \(leak)")
            }
        },
        Case("SUPPORT-02", "The log says why a window dropped off the canvas") { t in
            let since = Date().addingTimeInterval(-2)
            let f = try await t.fixture("SUPPORT-02", windows: 1)
            guard let id = f.windows.first else { throw Failure("the fixture has no window") }
            try await t.until("Expanse to take on the fixture's window", timeout: 10) { try await t.state().window(id) != nil }
            let app = try await t.state().window(id)?.app ?? "Expanse Tests"
            let tracking = "tracking \(app) [\(id)] <private>"
            let dropped = "dropped \(app)[\(id)]: not in the window list"
            try await t.expectLog(tracking)
            let mark = t.log.mark()
            try await f.closeWindow(0)
            try await t.expectLog(dropped, since: mark, timeout: 15)
            // Kept on disk at notice level: both in `log show` without --info.
            let deadline = Date().addingTimeInterval(30)
            var shown = ""
            while !(shown.contains(tracking) && shown.contains(dropped)) {
                if Date() > deadline {
                    let missing = [tracking, dropped].filter { !shown.contains($0) }
                    throw Failure("`log show` (no --info) hasn't kept: \(missing.map { "“\($0)”" }.joined(separator: ", "))")
                }
                try await t.pause(1)
                shown = await supportRun("/usr/bin/log", ["show", "--start", supportLogDate(since), "--style", "compact",
                                                          "--predicate", "subsystem == \"com.invignation.expanse\""])
            }
        },
        Case("SUPPORT-03", "expanse://dump lists app windows that aren't on the canvas") { t in
            guard let expanse = t.expanse?.processIdentifier else { throw Failure("Expanse isn't running") }
            let mine = try await t.window("SUPPORT-03 Managed")
            // An app window on screen that Expanse doesn't take on: a utility panel at the normal
            // level (layer 0), not a standard window.
            let panel = NSPanel(contentRect: appKitRect(CGRect(x: 360, y: 300, width: 360, height: 220)),
                                styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            panel.isFloatingPanel = false
            panel.level = .normal
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.title = "SUPPORT-03 Panel"
            panel.orderFrontRegardless()
            defer { panel.close() }
            let id = CGWindowID(panel.windowNumber)
            // Once a scan has looked at it, it says what it found (`never asked` before that).
            var line = ""
            try await t.until("a dump line for the panel saying what the last check found", timeout: 15) {
                let s = try await t.state()
                line = s.unmanaged.first { $0.id == id }?.line ?? ""
                return line.contains(" standard=")
            }
            let s0 = supportListedWindows(excluding: expanse)
            let mark = t.log.mark()
            t.link("dump")
            guard await t.log.wait(since: mark, timeout: 8, { $0.hasPrefix("dump viewport=") }) != nil else {
                throw Failure("Expanse didn't answer expanse://dump")
            }
            let lines = await t.dumpLines(since: mark)
            let s1 = supportListedWindows(excluding: expanse)
            let state = ExpanseState(lines: lines)
            try t.expect(state.window(mine.id) != nil && !state.unmanaged.contains { $0.id == mine.id },
                         "the window on the canvas should have an ordinary dump line, not an unmanaged one")
            try t.expect(state.window(id) == nil, "setup: Expanse took on the panel")
            // After the usual lines.
            if let firstUnmanaged = lines.firstIndex(where: { $0.hasPrefix("dump unmanaged ") }),
               let lastWindow = lines.lastIndex(where: { $0.hasPrefix("dump ") && $0.contains(" sc=") }) {
                try t.expect(lastWindow < firstUnmanaged, "a `dump unmanaged` line came before the canvas's windows' lines")
            }
            for u in lines where u.hasPrefix("dump unmanaged ") {
                try t.expect(u.firstMatch(of: #/^dump unmanaged .+\[\d+\] (standard=(true|false) pending=(true|false) age=\d+s|never asked) scanned=(true|false) fullScreen=(true|false) app=(\d+|none) recentlyRemoved=(true|false)$/#) != nil,
                             "malformed line: \(u)")
                try t.expect(!u.hasPrefix("dump unmanaged Expanse["), "Expanse's own window is listed: \(u)")
            }
            guard let panelLine = state.unmanaged.first(where: { $0.id == id })?.line else {
                throw Failure("the panel isn't listed as a window off the canvas")
            }
            try t.expect(panelLine.hasPrefix("dump unmanaged Expanse Tests[\(id)] standard=false pending=")
                         && panelLine.contains(" app=\(ProcessInfo.processInfo.processIdentifier) ") && panelLine.hasSuffix(" recentlyRemoved=false"),
                         "the panel's line should say it isn't a standard window, and name Expanse Tests' process: \(panelLine)")
            // Every ordinary window on screen and off the canvas gets one (those there throughout).
            let listed = Set(state.unmanaged.map(\.id))
            let missing = s0.intersection(s1).filter { state.window($0) == nil && !listed.contains($0) }
            try t.expect(missing.isEmpty, "windows on screen and off the canvas without a `dump unmanaged` line: \(missing.sorted())")
        },
        Case("SUPPORT-06", "Copy Logs with Detailed Logging off uses this run's system log") { t in
            guard let expanse = t.expanse else { throw Failure("Expanse isn't running") }
            let wasOn = supportSetting("detailedLogging") as? Bool ?? false
            if wasOn {
                t.link("logging", ["on": 0])
                try await t.until("Detailed Logging to turn off", timeout: 5) { supportSetting("detailedLogging") as? Bool == false }
                try await t.pause(0.5)
            }
            defer { if wasOn { t.link("logging", ["on": 1]) } }
            // An old Expanse.log with a line of its own: it mustn't be used. Put back as it was after.
            let fm = FileManager.default
            let file = supportLogFolder.appendingPathComponent("Expanse.log")
            let hadFolder = fm.fileExists(atPath: supportLogFolder.path), hadFile = fm.fileExists(atPath: file.path)
            let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.uint64Value ?? 0
            try fm.createDirectory(at: supportLogFolder, withIntermediateDirectories: true)
            if !hadFile { fm.createFile(atPath: file.path, contents: nil) }
            let marker = "SUPPORT-06 old line \(UUID().uuidString)"
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("2026-01-01 00:00:00.000 [notice] \(marker)\n".utf8))
            try handle.close()
            defer {
                if hadFile {
                    if let h = try? FileHandle(forWritingTo: file) { try? h.truncate(atOffset: size); try? h.close() }
                } else {
                    try? fm.removeItem(at: file)
                    if !hadFolder { try? fm.removeItem(at: supportLogFolder) }
                }
            }
            let toasts = SupportToasts(expanse.processIdentifier)
            defer { toasts.stop() }
            NSPasteboard.general.clearContents()
            t.link("copylogs")
            try await t.until("the bug report on the clipboard", timeout: 20) {
                (NSPasteboard.general.string(forType: .string) ?? "").hasPrefix("### Expanse")
            }
            try await t.pause(0.5)
            let report = NSPasteboard.general.string(forType: .string) ?? ""
            let copied = "Copied. For more, turn on Detailed Logging and try again."
            // The toast follows the clipboard by a moment (seconds in a busy VM).
            try? await t.until("the toast “\(copied)”", timeout: 10) { toasts.saw(copied) }
            try t.expect(toasts.saw(copied), "no toast “\(copied)” (saw \(toasts.texts))")
            // The summary, as SUPPORT-05 has it.
            let head = report.split(separator: "\n", omittingEmptySubsequences: false).prefix(7).map(String.init)
            let bullets = ["- Expanse ", "- macOS ", "- Displays: ", "- Accessibility: ", "- Canvas: ", "- Desktop picture background "]
            try t.expect(head.count == 7 && zip(head.dropFirst(), bullets).allSatisfy { $0.hasPrefix($1) },
                         "the report should start “### Expanse” and six bullets: \(head)")
            try t.expect(head.last?.hasSuffix("detailed logging off") == true, "the settings line should say detailed logging off: \(head.last ?? "")")
            let heading = "<details><summary>System log for this run (Detailed Logging is off: turn it on for more)</summary>"
            try t.expect(report.contains(heading), "the log section isn't headed “System log for this run (Detailed Logging is off: turn it on for more)”")
            try t.expect(!report.contains(marker), "the old Expanse.log was used")
            guard let open = report.range(of: "```\n"), let close = report.range(of: "\n```", range: open.upperBound..<report.endIndex) else {
                throw Failure("no log block in the report")
            }
            let log = String(report[open.upperBound..<close.lowerBound])
            try t.expect(log != "(nothing logged)" && !log.isEmpty, "the log section is empty (Expanse has logged this run)")
            try t.expect(log.count <= 45_000, "the log section is \(log.count) characters (at most 45,000)")
            let lines = log.split(separator: "\n").map(String.init)
            if let bad = lines.first(where: { $0.firstMatch(of: #/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \[(info|notice|error)\] /#) == nil }) {
                throw Failure("a log line isn't “<time> [info|notice|error] …”: \(bad)")
            }
            // This run's: none from before Expanse started.
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            if let launched = expanse.launchDate, let first = lines.first.flatMap({ format.date(from: String($0.prefix(23))) }) {
                try t.expect(first >= launched.addingTimeInterval(-2), "the log starts at \(first), before Expanse started (\(launched))")
            }
        },
        Case("SUPPORT-08", "Show Log File in Finder and Report an Issue on GitHub", .guided) { t in
            try await supportWithoutLogFile(t) {
                t.link("menu")
                try await t.look("Click the stethoscope (Troubleshooting) button at the bottom of Expanse's panel. "
                                 + "Is Show Log File in Finder greyed out? (Press Esc to close the menu, then answer.)")
                t.link("menu")
                try await t.ask("In Expanse's panel, click the stethoscope and choose Detailed Logging. Then open the stethoscope menu again, "
                                + "choose Show Log File in Finder, and click Done.")
                try t.expect(supportSetting("detailedLogging") as? Bool == true, "Detailed Logging didn't turn on")
                let file = supportLogFolder.appendingPathComponent("Expanse.log")
                try t.expect(FileManager.default.fileExists(atPath: file.path), "Detailed Logging didn't make \(file.path)")
                try await t.until("Finder in front", timeout: 5) { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" }
                try await t.look("Does Finder show the Expanse folder (in Logs) with Expanse.log selected?")
                t.link("menu")
                try await t.ask("In Expanse's panel, click the stethoscope and choose Report an Issue on GitHub…. Then click Done.")
                try await t.supportBrowserInFront()
                try await t.look("Does your browser show GitHub's new-issue page for invig/expanse "
                                 + "(github.com/invig/expanse/issues/new, or GitHub's sign-in page on the way there)?")
            }
        },
        Case("SUPPORT-10", "Troubleshooting from the panel's footer", .guided) { t in
            guard let expanse = t.expanse?.processIdentifier else { throw Failure("Expanse isn't running") }
            try await supportWithoutLogFile(t) {
                // 1: the menu.
                t.link("menu")
                try await t.look("Click the stethoscope button at the bottom of Expanse's panel. Does a menu open under the pointer, with the panel "
                                 + "still open, listing Detailed Logging (no tick), Copy Logs for a Bug Report, Show Log File in Finder (greyed out), "
                                 + "a separator, and Report an Issue on GitHub…? (Press Esc to close the menu, then answer.)")
                // 2: Detailed Logging ticks, says so, and leaves the panel open.
                t.link("menu")
                var toasts = SupportToasts(expanse)
                let panelWhenOn = supportWhen({ supportSetting("detailedLogging") as? Bool == true }, then: { supportPanelOpen(expanse) })
                try await t.ask("In Expanse's panel, click the stethoscope and choose Detailed Logging. Then click Done.")
                panelWhenOn.cancel()
                toasts.stop()
                try t.expect(supportSetting("detailedLogging") as? Bool == true, "Detailed Logging didn't turn on")
                try t.expect(await panelWhenOn.value == true, "choosing Detailed Logging closed the panel (it should stay open)")
                try t.expect(toasts.saw("Detailed logging on"), "no toast “Detailed logging on” (saw \(toasts.texts))")
                let file = supportLogFolder.appendingPathComponent("Expanse.log")
                let first = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").first.map(String.init) ?? ""
                try t.expect(first.firstMatch(of: #/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \[notice\] detailed logging on \(Expanse [^)]+\)$/#) != nil,
                             "Expanse.log should start “<date time> [notice] detailed logging on (Expanse <version>)”: “\(first)”")
                // 3: ticked now; Copy Logs closes the panel and puts the report on the clipboard.
                t.link("menu")
                try await t.look("Click the stethoscope again: does Detailed Logging have a tick now, and is Show Log File in Finder no longer greyed out? "
                                 + "(Press Esc to close the menu, then answer.)")
                t.link("menu")
                NSPasteboard.general.clearContents()
                toasts = SupportToasts(expanse)
                let panelWhenCopied = supportWhen({ (NSPasteboard.general.string(forType: .string) ?? "").hasPrefix("### Expanse") },
                                                  then: { supportPanelOpen(expanse) }, after: 0.5)
                try await t.ask("In Expanse's panel, click the stethoscope and choose Copy Logs for a Bug Report. Then click Done.")
                try await t.until("the bug report on the clipboard", timeout: 15) {
                    (NSPasteboard.general.string(forType: .string) ?? "").hasPrefix("### Expanse")
                }
                try await t.pause(1)
                panelWhenCopied.cancel()
                toasts.stop()
                try t.expect(await panelWhenCopied.value == false, "Copy Logs left the panel open (it should close it)")
                try t.expect(toasts.saw("Logs copied: paste them into a GitHub issue"), "no toast “Logs copied: paste them into a GitHub issue” (saw \(toasts.texts))")
                let report = NSPasteboard.general.string(forType: .string) ?? ""
                try t.expect(report.contains("<details><summary>Detailed log</summary>") && report.contains("detailed logging on (Expanse"),
                             "the report should hold the Detailed Logging file under “Detailed log”")
                // 4: Show Log File in Finder, then Report an Issue on GitHub.
                t.link("menu")
                try await t.ask("In Expanse's panel, click the stethoscope and choose Show Log File in Finder. Then click Done.")
                try await t.until("Finder in front", timeout: 5) { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" }
                try await t.look("Does Finder show Expanse.log selected, in the Expanse folder in Logs?")
                t.link("menu")
                try await t.ask("In Expanse's panel, click the stethoscope and choose Report an Issue on GitHub…. Then click Done.")
                try await t.supportBrowserInFront()
                try await t.look("Does your browser show GitHub's new-issue page for invig/expanse "
                                 + "(github.com/invig/expanse/issues/new, or GitHub's sign-in page on the way there)?")
            }
        },
    ]
}

// MARK: - Helpers

private let supportLogFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Expanse", isDirectory: true)

/// One of Expanse's settings as Expanse has it now (re-read: Expanse writes them itself).
private func supportSetting(_ key: String) -> Any? {
    CFPreferencesAppSynchronize("com.invignation.expanse" as CFString)
    return CFPreferencesCopyAppValue(key as CFString, "com.invignation.expanse" as CFString)
}

/// macOS's own ⌃→ (Move right a space) takes the key before Expanse's hotkey when it's on (as
/// Expanse's walkthrough works it out).
private func supportControlRightTaken() -> Bool {
    let domain = "com.apple.symbolichotkeys" as CFString
    CFPreferencesAppSynchronize(domain)
    let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
    if all["81"] == nil { return true }
    return all.values.contains { value in
        guard let entry = value as? [String: Any], entry["enabled"] as? Bool == true,
              let p = (entry["value"] as? [String: Any])?["parameters"] as? [Int], p.count == 3, p[1] == 124 else { return false }
        return p[2] & 0x40000 != 0 && p[2] & (0x20000 | 0x80000 | 0x100000) == 0
    }
}

/// A command's output (run off the main thread).
private func supportRun(_ path: String, _ arguments: [String]) async -> String {
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

/// `log show --start`'s form of a date.
private func supportLogDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.string(from: date)
}

/// Ordinary windows on screen (layer 0, at least 100pt wide) that aren't `pid`'s, as dump looks at them.
private func supportListedWindows(excluding pid: pid_t) -> Set<CGWindowID> {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return Set(info.compactMap { w in
        guard (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowOwnerPID as String] as? pid_t) != pid,
              let id = w[kCGWindowNumber as String] as? CGWindowID,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b), r.width >= 100 else { return nil }
        return id
    })
}

/// Expanse's menu bar panel is up (a window of its at the pop-up menu level, bigger than its
/// Troubleshooting menu).
private func supportPanelOpen(_ pid: pid_t) -> Bool {
    let level = Int(CGWindowLevelForKey(.popUpMenuWindow))
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.contains { w in
        guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid, (w[kCGWindowLayer as String] as? Int) == level,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) else { return false }
        return r.height >= 200 && r.width >= 200
    }
}

/// Expanse's toast now: whether one is on screen (a window of its at the status bar's level), and
/// its text where Accessibility can read it.
@MainActor private func supportToast(_ pid: pid_t) -> (shown: Bool, text: String?) {
    let level = Int(CGWindowLevelForKey(.statusWindow))
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let frame = info.lazy.compactMap({ w -> CGRect? in
        guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid, (w[kCGWindowLayer as String] as? Int) == level,
              (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let b = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: b)
    }).first else { return (false, nil) }
    guard AXIsProcessTrusted() else { return (true, nil) }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.5)
    for window in supportAXElements(app, kAXWindowsAttribute) {
        guard let r = supportAXFrame(window), abs(r.minX - frame.minX) < 2, abs(r.minY - frame.minY) < 2,
              abs(r.width - frame.width) < 2 else { continue }
        var texts: [String] = []
        var level = [window]
        for _ in 0..<4 {
            level = level.flatMap { supportAXElements($0, kAXChildrenAttribute) }
            texts += level.compactMap { e in
                supportAXString(e, kAXRoleAttribute) == kAXStaticTextRole ? supportAXString(e, kAXValueAttribute) : nil
            }
        }
        return (true, texts.isEmpty ? nil : texts.joined(separator: " "))
    }
    return (true, nil)
}

private func supportAXString(_ e: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return nil }
    return value as? String
}

private func supportAXElements(_ e: AXUIElement, _ attribute: String) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return [] }
    return value as? [AXUIElement] ?? []
}

/// A window's frame (global, top-left origin) as Accessibility gives it.
private func supportAXFrame(_ e: AXUIElement) -> CGRect? {
    var position: CFTypeRef?, size: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &position) == .success,
          AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &size) == .success,
          let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
    return CGRect(origin: p, size: s)
}

/// The toasts Expanse shows while this is watching (every tenth of a second).
@MainActor private final class SupportToasts {
    private(set) var shown = false
    private(set) var texts: [String] = []
    private var task: Task<Void, Never>?

    init(_ pid: pid_t) {
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let toast = supportToast(pid)
                if toast.shown {
                    self?.shown = true
                    if let text = toast.text, self?.texts.contains(text) == false { self?.texts.append(text) }
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    func stop() { task?.cancel() }

    /// It showed `text` (or, where Accessibility can't read toasts, showed one at all).
    func saw(_ text: String) -> Bool { texts.contains(text) || (shown && texts.isEmpty) }
}

/// Watches (every tenth of a second) for `condition`, then answers `then()` a moment `after` it
/// first holds; nil if it never does before being cancelled.
@MainActor private func supportWhen(_ condition: @escaping @MainActor () -> Bool, then: @escaping @MainActor () -> Bool,
                                    after delay: TimeInterval = 0) -> Task<Bool?, Never> {
    Task { @MainActor in
        while !Task.isCancelled {
            if condition() {
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
                return then()
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }
}

/// Detailed Logging off and no log folder, for a case that starts with no log file; both put back
/// afterwards (the folder is moved aside meanwhile, and the one the case made removed).
@MainActor private func supportWithoutLogFile(_ t: Ctx, _ body: () async throws -> Void) async throws {
    let fm = FileManager.default
    let wasOn = supportSetting("detailedLogging") as? Bool ?? false
    @MainActor func loggingOff() async {
        guard supportSetting("detailedLogging") as? Bool == true else { return }
        t.link("logging", ["on": 0])
        try? await t.until("Detailed Logging to turn off", timeout: 5) { supportSetting("detailedLogging") as? Bool == false }
        // Its last line is written (and the file closed) on Expanse's log queue.
        try? await Task.sleep(nanoseconds: 700_000_000)
    }
    await loggingOff()
    let aside = supportLogFolder.deletingLastPathComponent().appendingPathComponent("Expanse (moved aside by Expanse Tests)", isDirectory: true)
    let moved = fm.fileExists(atPath: supportLogFolder.path)
    if moved {
        if fm.fileExists(atPath: aside.path) {
            throw Failure("\(aside.path) is left from an earlier run: move it back to \(supportLogFolder.path) first")
        }
        try fm.moveItem(at: supportLogFolder, to: aside)
    }
    var failure: Error?
    do { try await body() } catch { failure = error }
    await loggingOff()
    try? fm.removeItem(at: supportLogFolder)
    if moved { try fm.moveItem(at: aside, to: supportLogFolder) }
    if wasOn { t.link("logging", ["on": 1]) }
    if let failure { throw failure }
}

fileprivate extension Ctx {
    /// Glides to a window at 100% (expanse://focus?id=) and waits until it's in the middle of the view.
    func supportFocus(_ id: CGWindowID) async throws {
        link("focus", ["id": id])
        try await until("a glide to window \(id)", timeout: 10) {
            let s = try await self.settle()
            guard !s.active, let f = s.window(id)?.canvas else { return false }
            return s.visibleCanvas.contains(CGPoint(x: f.midX, y: f.midY))
        }
    }

    /// Waits for a line since `mark` that `match` accepts.
    func supportExpectLine(since mark: Int, timeout: TimeInterval = 8, _ what: String, _ match: (String) -> Bool) async throws {
        if await log.wait(since: mark, timeout: timeout, match) == nil { throw Failure("no log line: \(what)") }
    }

    /// The default web browser comes to the front.
    func supportBrowserInFront() async throws {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://github.com")!),
              let id = Bundle(url: app)?.bundleIdentifier else { throw Failure("no web browser") }
        try await until("the web browser (\(id)) in front", timeout: 10) { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == id }
    }
}
