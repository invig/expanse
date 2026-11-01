import AppKit
import os

// Expanse Tests: runs the regression cases in docs/regression against a running development
// build of Expanse. See scripts/integration.sh, which builds this app and starts it.
//
//   --auto            the cases that run on their own (the default)
//   --all             every case; guided and look cases ask you in a panel at the top of the screen
//   --guided          only the cases that need you
//   --area NAV,EDIT   only these areas
//   --only NAV-03,…   only these cases
//   --list            write the list of cases to the report and quit
//   --ask-access      ask macOS for Accessibility (for keys and the pointer), then quit
//   --out DIR         where the report goes (default ~/Library/Logs/ExpanseTests)
//   --expanse PATH    the Expanse.app to relaunch when a case needs to (default: the running one)
//   --timeout SECS    for each automatic case (default 90)
//   --repeat N        run the chosen cases N times over (to tell a flaky case from a broken one)
//   --keep-logs       keep Expanse's log for every case, not only the failed ones
//   --forget-own-windows  take this app's closed windows out of Expanse's saved layout, then quit
//                     (with Expanse not running; scripts/vm-integration.sh does it before each run)
//
// With --fixture NAME it's instead a stand-in app for a case: it opens windows and does what the
// runner tells it (see Fixture in TestWindows.swift).

let args = CommandLine.arguments
func option(_ name: String) -> String? { args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }

if args.contains("--forget-own-windows") {
    forgetOwnWindowsInExpanseLayout()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate: NSApplicationDelegate = MainActor.assumeIsolated {
    if let name = option("--fixture") {
        return FixtureApp(name: name, count: Int(option("--windows") ?? "1") ?? 1, size: option("--size"))
    }
    return Runner()
}
app.delegate = delegate
app.run()

// MARK: Running the cases

@MainActor final class Runner: NSObject, NSApplicationDelegate {
    struct Result {
        let c: Case
        let outcome: String
        let detail: String
        let seconds: Double
    }

    private var results: [Result] = []
    private let out = URL(fileURLWithPath: option("--out") ?? (NSHomeDirectory() + "/Library/Logs/ExpanseTests"), isDirectory: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Which of Expanse Tests' windows has the keyboard, and when it's in front, logged under
        // Expanse's subsystem so a case's log shows it among Expanse's own lines.
        let log = Logger(subsystem: "com.invignation.expanse", category: "tests")
        let center = NotificationCenter.default
        for (name, what) in [(NSWindow.didBecomeKeyNotification, "key"), (NSWindow.didBecomeMainNotification, "main")] {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                // Its number (the window ID in Expanse's lines), never its title: SUPPORT-01 checks
                // no window title ever reaches this log.
                let number = (note.object as? NSWindow)?.windowNumber ?? 0
                log.info("tests: \(what, privacy: .public) window [\(number)]")
            }
        }
        for (name, what) in [(NSApplication.didBecomeActiveNotification, "active"), (NSApplication.didResignActiveNotification, "not active")] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in log.info("tests: Expanse Tests \(what, privacy: .public)") }
        }
        Task { @MainActor in
            let code = await run()
            exit(code)
        }
    }

    private func selected() -> [Case] {
        var cases = allCases
        if let areas = option("--area")?.uppercased().split(separator: ",").map(String.init) {
            cases = cases.filter { areas.contains($0.area) }
        }
        if let ids = option("--only")?.uppercased().split(separator: ",").map(String.init) {
            cases = cases.filter { ids.contains($0.id) }
        }
        if args.contains("--guided") { cases = cases.filter { $0.kind != .auto } }
        else if !args.contains("--all") && option("--only") == nil { cases = cases.filter { $0.kind == .auto } }
        let times = max(1, Int(option("--repeat") ?? "1") ?? 1)
        return Array(repeating: cases, count: times).flatMap { $0 }
    }

    private func run() async -> Int32 {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let cases = selected()
        if args.contains("--ask-access") {
            // macOS's own prompt: it lists Expanse Tests under Accessibility, for you to switch on.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            return 0
        }
        if args.contains("--list") {
            write(list: cases)
            return 0
        }
        let log = LogTail()
        do { try log.start() } catch {
            progress("couldn't start `log stream`: \(error)")
            return 2
        }
        let human = Human()
        human.present = args.contains("--all") || args.contains("--guided") || option("--only") != nil
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.invignation.expanse").first
        guard let expanseURL = option("--expanse").map({ URL(fileURLWithPath: $0) }) ?? running?.bundleURL else {
            progress("Expanse isn't running, and no --expanse was given")
            return 2
        }
        let t = Ctx(log: log, expanseURL: expanseURL, human: human)
        try? await Task.sleep(nanoseconds: 500_000_000)
        if t.expanse == nil { try? await t.launchExpanse() }
        do {
            let s = try await t.state()
            measureClearSpot(s)
            progress("Expanse: \(s.windows.count) windows on the canvas (\(s.windows.filter(\.parked).count) out of view), "
                     + "viewport \(NSStringFromRect(s.viewport)), scale \(s.scale), \(s.active ? "zoomed out" : "at 100%")\(s.paused ? ", paused" : "")")
        } catch {
            progress("\(error)")
            return 2
        }
        closeBackgroundItemNotices()
        progress("Expanse Tests: \(cases.count) cases; Accessibility for input: \(Input.allowed ? "yes" : "no")")
        let timeout = Double(option("--timeout") ?? "90") ?? 90
        for c in cases {
            human.caseLabel = "\(c.id) \(c.title)"
            if c.kind != .auto && !human.present {
                record(c, "skipped", "needs a person (run with --all or --guided)", 0)
                continue
            }
            await t.cleanUp()
            // A prompt of macOS's (Screen Recording asking again, say) sits in the middle of the
            // screen and takes the case's clicks: it needs answering, by hand, first.
            if c.kind == .auto, let prompt = macOSPromptOnScreen() {
                record(c, "skipped", "macOS is asking something on screen (\(prompt)): answer it, then run this case again", 0)
                continue
            }
            t.begin()
            let began = Date()
            do {
                try await withTimeout(c.kind == .auto ? max(timeout, c.time) : 3600) { try await c.run(t) }
                let timing = t.notes.isEmpty ? "" : "in a VM, so not failed on: \(t.notes.joined(separator: "; "))"
                record(c, "passed", c.known.map { "the known issue didn't show (\($0)): fixed?" } ?? timing, Date().timeIntervalSince(began))
                if args.contains("--keep-logs") { keepLog(c, t) }
            } catch let s as Skip {
                record(c, "skipped", s.description, Date().timeIntervalSince(began))
            } catch {
                if let known = c.known {
                    record(c, "known", "\(known) — \(error)", Date().timeIntervalSince(began))
                    keepLog(c, t)
                } else {
                    record(c, "FAILED", "\(error)", Date().timeIntervalSince(began))
                    // Expanse's log in a VM keeps info lines only for minutes: keep the case's now.
                    keepLog(c, t)
                }
            }
        }
        await t.cleanUp()
        log.stop()
        let failed = results.filter { $0.outcome == "FAILED" }.count
        let known = results.filter { $0.outcome == "known" }.count
        progress("done: \(results.filter { $0.outcome == "passed" }.count) passed, \(failed) failed, \(known) known issues, \(results.filter { $0.outcome == "skipped" }.count) skipped")
        return failed == 0 ? 0 : 1
    }

    private func withTimeout(_ seconds: Double, _ body: @escaping @MainActor () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
                throw Failure("timed out after \(Int(seconds))s")
            }
            try await group.next()
            group.cancelAll()
        }
    }

    /// Expanse's log during case `c`, next to the report: a VM keeps its info lines only for
    /// minutes. With --repeat, each run of a case keeps its own (NAV-36.log, NAV-36-2.log…).
    private func keepLog(_ c: Case, _ t: Ctx) {
        let runs = results.filter { $0.c.id == c.id }.count
        let name = runs > 1 ? "\(c.id)-\(runs).log" : "\(c.id).log"
        try? t.log.transcript(since: t.start).write(to: out.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func record(_ c: Case, _ outcome: String, _ detail: String, _ seconds: Double) {
        results.append(Result(c: c, outcome: outcome, detail: detail, seconds: seconds))
        let tag = ["passed": "ok  ", "skipped": "skip", "known": "know"][outcome] ?? "FAIL"
        progress("\(tag) \(c.id) \(c.title)\(detail.isEmpty ? "" : " — \(detail)")")
        writeReport()
    }

    private func progress(_ line: String) {
        let url = out.appendingPathComponent("progress.log")
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func writeReport() {
        var md = "# Expanse end-to-end tests\n\n\(Date())\n\n| Case | Title | Kind | Result | Time | Detail |\n|---|---|---|---|---|---|\n"
        for r in results {
            let time = String(format: "%.1fs", r.seconds)
            let detail = r.detail.replacingOccurrences(of: "|", with: "/")
            md += "| \(r.c.id) | \(r.c.title) | \(r.c.kind.rawValue) | \(r.outcome) | \(time) | \(detail) |\n"
        }
        try? md.write(to: out.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
    }

    private func write(list cases: [Case]) {
        var md = "| Case | Title | Kind |\n|---|---|---|\n"
        for c in cases { md += "| \(c.id) | \(c.title) | \(c.kind.rawValue) |\n" }
        try? md.write(to: out.appendingPathComponent("cases.md"), atomically: true, encoding: .utf8)
    }
}

// MARK: Fixture app

/// A stand-in app: `count` windows titled "NAME 1", "NAME 2"…, and commands from the runner.
@MainActor final class FixtureApp: NSObject, NSApplicationDelegate {
    let name: String
    let count: Int
    let size: CGSize
    private var windows: [TestWindow] = []

    init(name: String, count: Int, size: String?) {
        self.name = name
        self.count = count
        let parts = (size ?? "").split(separator: "x").compactMap { Double($0) }
        self.size = parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : CGSize(width: 640, height: 420)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DistributedNotificationCenter.default().addObserver(forName: Fixture.commandNote, object: name, queue: .main) { [weak self] note in
            let info = note.userInfo as? [String: String] ?? [:]
            MainActor.assumeIsolated { self?.handle(info) }
        }
        for _ in 0..<count { open() }
        NSApp.activate(ignoringOtherApps: true)
        report()
    }

    private func open() {
        let i = windows.count
        let offset = CGFloat(160 + 40 * i)
        windows.append(TestWindow(title: Fixture.title(name, i + 1), frame: CGRect(origin: CGPoint(x: offset, y: offset), size: size)))
    }

    private func handle(_ info: [String: String]) {
        let i = Int(info["index"] ?? "0") ?? 0
        let w = windows.indices.contains(i) ? windows[i] : nil
        switch info["do"] {
        case "open": open()
        case "close": w?.close()
        case "minimise": w?.minimise()
        case "restore": w?.restore()
        case "fullscreen": w?.toggleFullScreen()
        case "frame": if let f = info["frame"] { w?.setFrame(NSRectFromString(f)) }
        case "focus": w?.focus()
        case "hide": NSApp.hide(nil)
        case "quit": NSApp.terminate(nil); return
        default: break
        }
        // Give the window server a moment, so the IDs reported are on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.report() }
    }

    private func report() {
        // Every window still open: hidden and minimised ones too, not closed ones.
        let open = windows.filter(\.isOpen)
        DistributedNotificationCenter.default().postNotificationName(Fixture.stateNote, object: name,
                                                                     userInfo: ["windows": open.map { "\($0.id)" },
                                                                                "opened": open.map { NSStringFromRect($0.opened) }],
                                                                     deliverImmediately: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
