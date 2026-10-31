import Testing
import AppKit
import OSLog
import ScreenCaptureKit
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "Log.swift") @testable import Expanse
@_private(sourceFile: "BugReport.swift") @testable import Expanse

/// docs/regression/troubleshooting.md. Log files are written to temp folders only (LogFile(folder:)),
/// with Expanse's own one (LogFile.shared) checked to be off first, so nothing reaches ~/Library/Logs.
@MainActor @Suite("SUPPORT: Troubleshooting and logs", .serialized) struct SUPPORTTests {

    @Test("SUPPORT-04 Detailed Logging writes Expanse's log to a file")
    func support04() throws {
        #expect(LogFile.shared.url.path.hasSuffix("/Library/Logs/Expanse/Expanse.log"))
        try withLogFile { log, folder in
            #expect(!log.isEnabled)
            log.write("info", "hop while off")
            _ = log.recent(maxCharacters: 100)
            #expect(!FileManager.default.fileExists(atPath: folder.path))
            // Step 1: on.
            log.isEnabled = true
            // Step 2: activity.
            log.write("info", "glide to Example[42]")
            var got = try lines(of: log)
            let stamp = #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}"#
            #expect(got.count == 2)
            #expect(got.first?.wholeMatch(of: try Regex(stamp + #" \[notice\] detailed logging on \(Expanse .+\)"#)) != nil)
            #expect(got.last?.wholeMatch(of: try Regex(stamp + #" \[info\] glide to Example\[42\]"#)) != nil)
            // Step 3: off; nothing after.
            log.isEnabled = false
            log.write("info", "hop after")
            got = try lines(of: log)
            #expect(got.count == 3)
            #expect(got.last?.wholeMatch(of: try Regex(stamp + #" \[notice\] detailed logging off"#)) != nil)
            // Step 4: remembered.
            log.isEnabled = true
            #expect(UserDefaults.standard.bool(forKey: LogFile.enabledKey))
            #expect(LogFile(folder: folder).isEnabled)
            log.isEnabled = false
            #expect(!LogFile(folder: folder).isEnabled)
        }
    }

    @Test("SUPPORT-05 Copy Logs takes the end of the log, at most 45,000 characters, from a whole line")
    func support05() throws {
        #expect(BugReport.maxLogCharacters == 45_000)
        try withLogFile { log, folder in
            #expect(log.recent(maxCharacters: BugReport.maxLogCharacters) == "")
            log.isEnabled = true
            for i in 0..<2000 { log.write("info", "line \(i) " + String(repeating: "x", count: i % 50)) }
            let all = log.recent(maxCharacters: 10_000_000)
            #expect(all.count > 100_000)
            let firstLine = try #require(try lines(of: log).first)
            #expect(all.hasPrefix(firstLine))
            for limit in [BugReport.maxLogCharacters, 1000, 200] {
                let end = log.recent(maxCharacters: limit)
                #expect(end.count <= limit && end.count > limit - 120, "limit \(limit)")
                #expect(all.hasSuffix(end))
                // From a whole line: what comes before it ends a line.
                #expect(all.dropLast(end.count).last == "\n", "limit \(limit)")
                #expect(end.hasSuffix("line 1999 " + String(repeating: "x", count: 1999 % 50) + "\n"))
            }
        }
    }

    @Test("SUPPORT-07 Window titles stay out of the log file and the report")
    func support07() throws {
        let title = "Secret-Plan"
        let app = "TextEdit"
        let id: CGWindowID = 4242
        // As CanvasController logs a window it takes on.
        let tracking: LogMessage = "tracking \(app, privacy: .public) [\(id)] \(title, privacy: .private)"
        #expect(tracking.text == "tracking TextEdit [4242] <private>")
        // Private unless marked public...
        let plain: LogMessage = "window \(title)"
        #expect(plain.text == "window <private>")
        let shown: LogMessage = "app \(app, privacy: .public)"
        #expect(shown.text == "app TextEdit")
        // ...except numbers and true/false.
        let numbers: LogMessage = "\(3) \(2.5) \(CGFloat(1.5)) \(id) \(Int32(-7)) \(true)"
        #expect(numbers.text == "3 2.5 1.5 4242 -7 true")
        let point = CGPoint(x: 1, y: 2)
        let other: LogMessage = "at \(point)"
        #expect(other.text == "at <private>")
        try withLogFile { log, _ in
            log.isEnabled = true
            log.write("notice", tracking.text)
            log.write("info", plain.text)
            let text = log.recent(maxCharacters: 45_000)
            #expect(!text.contains(title))
            #expect(text.contains("tracking TextEdit [4242] <private>"))
        }
    }

    @Test("SUPPORT-09 The log file is capped at 5 MB")
    func support09() throws {
        #expect(LogFile.maxBytes == 5_000_000)
        try withLogFile { log, folder in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let older = folder.appendingPathComponent("Expanse.1.log")
            let filler = String(repeating: "x", count: 99) + "\n"
            try Data(String(repeating: filler, count: 51_000).utf8).write(to: log.url)    // 5.1 MB
            try Data("OLD\n".utf8).write(to: older)
            log.isEnabled = true
            for i in 0..<20 { log.write("info", "hop \(i)") }
            _ = log.recent(maxCharacters: 1)
            // The big file became Expanse.1.log (the old one replaced); a new one took the next lines.
            let newest = try String(contentsOf: log.url, encoding: .utf8)
            let previous = try String(contentsOf: older, encoding: .utf8)
            #expect(try lines(of: log).count == 20)
            #expect(!newest.contains("xxx") && newest.contains("[info] hop 0"))
            #expect(!previous.hasPrefix("OLD"))
            #expect(previous.utf8.count > 5_000_000)
            #expect(previous.hasSuffix("[notice] detailed logging on (Expanse \(version))\n"))
            // Copy Logs: the newest file, then the one before if it needs more.
            let short = log.recent(maxCharacters: 300)
            #expect(!short.isEmpty && !short.contains("x") && short.hasSuffix("hop 19\n"))
            let long = log.recent(maxCharacters: 5_000)
            #expect(long.contains("detailed logging on") && long.contains(filler) && long.hasSuffix("hop 19\n"))
        }
        // Under the cap: no rotation.
        try withLogFile { log, folder in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(String(repeating: "y", count: 4_990_000).utf8).write(to: log.url)
            log.isEnabled = true
            log.write("info", "hop")
            _ = log.recent(maxCharacters: 1)
            #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Expanse.1.log").path))
        }
    }

    @Test("SUPPORT-11 A window left off the canvas logs why, once")
    func support11() async throws {
        let c = TestCanvas.make()
        let base = CGWindowID.random(in: 3_000_000_000...3_900_000_000)
        let started = Date().addingTimeInterval(-1)
        let windows = (0..<3).map {
            Fake.scWindow(id: base + CGWindowID($0), appName: "Skipper", title: "Settings", frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let why = "Skipper isn't an app in the Dock (a menu-bar extra or background process)"
        c.noteSkipped([base: why, base + 1: why], in: windows)
        #expect(c.loggedSkips == [base, base + 1])
        // Scan after scan: only the new one.
        c.noteSkipped([base: why, base + 1: why, base + 2: why], in: windows)
        c.noteSkipped([base: why, base + 2: why], in: windows)
        #expect(c.loggedSkips == [base, base + 1, base + 2])
        // In the system log (notice: kept on disk), one line each.
        let expected = (0..<3).map { "not on the canvas: Skipper[\(base + CGWindowID($0))]: \(why)" }
        var found: [String] = []
        for _ in 0..<3 {
            found = try systemLog(since: started, containing: "not on the canvas: Skipper[").filter { line in
                expected.contains { line.hasPrefix(String($0.prefix(while: { $0 != "]" }))) }
            }
            if found.count >= 3 { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        #expect(found.sorted() == expected)
        // The record is bounded: past 5,000 windows it starts again.
        c.loggedSkips = Set((0..<5001).map { CGWindowID($0) + 1 })
        c.noteSkipped([base: why], in: windows)
        #expect(c.loggedSkips == [base])
    }

    @Test("SUPPORT-11 The reasons a scan gives for leaving a window off")
    func support11b() {
        let menuExtra: pid_t = 90_211, dockApp: pid_t = 90_212
        let now = CACurrentMediaTime()
        CanvasController.appPolicyLock.lock()
        CanvasController.appOwners[menuExtra] = (nil, now + 1_000_000)
        CanvasController.appPolicyLock.unlock()
        Fake.regularApp(dockApp)
        defer {
            CanvasController.appPolicyLock.lock()
            CanvasController.appOwners[menuExtra] = nil
            CanvasController.appOwners[dockApp] = nil
            CanvasController.appPolicyLock.unlock()
        }
        let frame = CGRect(x: 100, y: 100, width: 500, height: 400)
        let settings = Fake.scWindow(id: 501, pid: menuExtra, appName: "Skipper", title: "Settings", frame: frame)
        let popover = Fake.scWindow(id: 502, pid: menuExtra, appName: "Skipper", title: "", frame: frame)
        let unlisted = Fake.scWindow(id: 503, pid: dockApp, appName: "Docked", title: "Doc", frame: frame)
        let opening = Fake.scWindow(id: 504, pid: dockApp, appName: "Docked", title: "New", frame: frame)
        var input = CanvasController.ScanInput()
        input.kinds[503] = CanvasController.WindowKind(standard: false, at: now - 100)
        let scan = CanvasController.axSnapshot(for: [settings, popover, unlisted, opening], input: input)
        #expect(scan.skipped[501] == "Skipper isn't an app in the Dock (a menu-bar extra or background process)")
        // Untitled windows of non-Dock apps (popovers) aren't logged.
        #expect(scan.skipped[502] == nil)
        #expect(scan.skipped[503] == "its app doesn't list it as one of its windows (Accessibility) yet; asked again every 2s for a minute, then every 10s")
        // Just opening: asked again for its first few seconds before it counts.
        #expect(scan.skipped[504] == nil)
        #expect(scan.pending)
    }

    // MARK: Logic of the manual cases

    @Test("SUPPORT-08 Show Log File in Finder and Report an Issue on GitHub (logic)")
    func support08() throws {
        #expect(BugReport.issuesURL.absoluteString == "https://github.com/invig/expanse/issues/new")
        try withLogFile { log, _ in
            // No log file until Detailed Logging has been on (the menu greys the item meanwhile).
            log.write("info", "hop")
            _ = log.recent(maxCharacters: 10)
            #expect(!FileManager.default.fileExists(atPath: log.url.path))
            log.isEnabled = true
            _ = log.recent(maxCharacters: 10)
            #expect(FileManager.default.fileExists(atPath: log.url.path))
            #expect(log.url.lastPathComponent == "Expanse.log")
        }
    }

    @Test("SUPPORT-10 Troubleshooting from the panel's footer (logic)")
    func support10() {
        // Detailed Logging leaves the panel open; the commands close it.
        #expect(!MenuPanel.Action.detailedLogging(true).closesPanel)
        #expect(!MenuPanel.Action.detailedLogging(false).closesPanel)
        #expect(MenuPanel.Action.copyLogs.closesPanel)
        #expect(MenuPanel.Action.showLogFile.closesPanel)
        #expect(MenuPanel.Action.reportIssue.closesPanel)
        // None of them waits for the canvas.
        for action in [MenuPanel.Action.detailedLogging(true), .copyLogs, .showLogFile, .reportIssue] {
            #expect(!action.needsCanvas)
        }
    }
}

// MARK: - Helpers

/// The version the log's "detailed logging on" line names (the test runner's, here).
private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

/// A LogFile of its own in a temp folder (not made yet), with Detailed Logging's setting put back
/// afterwards. Expanse's own log file is checked to be off first: its first use reads the setting.
private func withLogFile(_ body: (LogFile, URL) throws -> Void) throws {
    try Env.withDefaults([LogFile.enabledKey: nil]) {
        try #require(!LogFile.shared.isEnabled)
        let temp = Env.tempFolder()
        defer { try? FileManager.default.removeItem(at: temp) }
        let folder = temp.appendingPathComponent("Logs", isDirectory: true)
        let log = LogFile(folder: folder)
        try body(log, folder)
        log.isEnabled = false
        _ = log.recent(maxCharacters: 1)
    }
}

/// The log file's lines, once what's been written has reached it.
private func lines(of log: LogFile) throws -> [String] {
    _ = log.recent(maxCharacters: 1)
    let text = (try? String(contentsOf: log.url, encoding: .utf8)) ?? ""
    return text.split(separator: "\n").map(String.init)
}

/// Expanse's lines in this test process's system log since `start`.
private func systemLog(since start: Date, containing needle: String) throws -> [String] {
    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let entries = try store.getEntries(at: store.position(date: start),
                                       matching: NSPredicate(format: "subsystem == %@", "com.invignation.expanse"))
    return entries.compactMap { ($0 as? OSLogEntryLog)?.composedMessage }.filter { $0.contains(needle) }
}
