import AppKit

/// One regression case (docs/regression), run against the real Expanse.
struct Case {
    enum Kind: String {
        /// Runs on its own.
        case auto
        /// Needs you to do something (close the lid, unlock, plug in a display), then checks the result.
        case guided
        /// Needs your eyes: you're shown what to look at and asked whether it's right.
        case look
    }
    let id: String
    let title: String
    let kind: Kind
    /// A bug in Expanse this case shows, not yet fixed (docs/regression/README.md, Known issues):
    /// its failure is reported as known, not as a failure. Remove it once the bug is fixed.
    let known: String?
    let run: @MainActor (Ctx) async throws -> Void

    init(_ id: String, _ title: String, _ kind: Kind = .auto, known: String? = nil, _ run: @escaping @MainActor (Ctx) async throws -> Void) {
        self.id = id
        self.title = title
        self.kind = kind
        self.known = known
        self.run = run
    }

    var area: String { String(id.prefix { $0 != "-" }) }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

/// The case can't run here (a missing permission, one display when it needs two, a development
/// build when it needs a release). Reported as skipped, with the reason.
struct Skip: Error, CustomStringConvertible {
    let description: String
    init(_ reason: String) { description = reason }
}

/// What a case works with: Expanse's links and state, its log, test windows, input, and you.
@MainActor final class Ctx {
    let log: LogTail
    let expanseURL: URL
    let human: Human
    private(set) var windows: [TestWindow] = []
    private(set) var fixtures: [Fixture] = []
    /// Where the log was when the case started.
    private(set) var start = 0
    /// A case pretended the display is another size (expanse://screen?w=&h=): cleanUp puts it back.
    private var pretendDisplay = false

    init(log: LogTail, expanseURL: URL, human: Human) {
        self.log = log
        self.expanseURL = expanseURL
        self.human = human
    }

    // MARK: Expanse

    var expanse: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.invignation.expanse").first { !$0.isTerminated }
    }

    /// Opens expanse://command?query.
    func link(_ command: String, _ query: [String: Any] = [:]) {
        var c = URLComponents()
        c.scheme = "expanse"
        c.host = command
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: "\($0.value)") } }
        if command == "screen" { pretendDisplay = !query.isEmpty }
        // Without bringing Expanse forward: the app you're in keeps the keyboard, as with a script.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(c.url!, configuration: config)
    }

    /// Expanse's state now (expanse://dump, read back from the log).
    func state() async throws -> ExpanseState {
        let mark = log.mark()
        link("dump")
        guard await log.wait(since: mark, timeout: 8, { $0.hasPrefix("dump viewport=") }) != nil else {
            throw Failure("Expanse didn't answer expanse://dump (is a development build running, with debugURLCommands on?)")
        }
        return ExpanseState(lines: await log.settled(since: mark, prefix: "dump "))
    }

    /// Waits until `condition` holds, checking every quarter second.
    func until(_ what: String, timeout: TimeInterval = 8, _ condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if try await condition() { return }
            if Date() > deadline { throw Failure("timed out waiting for: \(what)") }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    /// Waits for Expanse to finish moving (no glide or camera animation), and returns its state.
    @discardableResult
    func settle(timeout: TimeInterval = 8) async throws -> ExpanseState {
        var s = try await state()
        let deadline = Date().addingTimeInterval(timeout)
        while !s.idle {
            if Date() > deadline { throw Failure("Expanse was still moving after \(Int(timeout))s") }
            try await pause(0.2)
            s = try await state()
        }
        return s
    }

    func pause(_ seconds: TimeInterval) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }

    /// Waits for a log line containing `text` since `mark` (the case's start if not given). Dump
    /// lines don't count (they contain "paused=" and the like) unless `text` is one.
    @discardableResult
    func expectLog(_ text: String, since mark: Int? = nil, timeout: TimeInterval = 8) async throws -> String {
        guard let line = await log.wait(since: mark ?? start, timeout: timeout, { Self.matches($0, text) }) else {
            throw Failure("no log line containing “\(text)”")
        }
        return line
    }

    func noLog(_ text: String, since mark: Int? = nil, within seconds: TimeInterval = 2) async throws {
        if let line = await log.wait(since: mark ?? start, timeout: seconds, { Self.matches($0, text) }) {
            throw Failure("unexpected log line: \(line)")
        }
    }

    private static func matches(_ line: String, _ text: String) -> Bool {
        line.contains(text) && (!line.hasPrefix("dump ") || text.hasPrefix("dump"))
    }

    /// Quits Expanse the ordinary way (it puts windows back) and waits for it to go.
    func quitExpanse() async throws {
        guard let app = expanse else { return }
        app.terminate()
        try await until("Expanse to quit", timeout: 15) { app.isTerminated }
    }

    /// Starts Expanse (the build given with --expanse) and waits until it answers.
    func launchExpanse() async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        _ = try await NSWorkspace.shared.openApplication(at: expanseURL, configuration: config)
        try await until("Expanse to answer after launch", timeout: 20) { (try? await self.state()) != nil }
    }

    func relaunchExpanse() async throws {
        try await quitExpanse()
        try await pause(1)
        try await launchExpanse()
    }

    // MARK: Windows

    /// A window of Expanse Tests at `frame` (global CG; macOS may nudge it), taken on by Expanse.
    @discardableResult
    func window(_ title: String, _ frame: CGRect = CGRect(x: 200, y: 200, width: 640, height: 420), managed: Bool = true) async throws -> TestWindow {
        bringToFront(.current)
        let w = TestWindow(title: title, frame: frame)
        windows.append(w)
        if managed {
            try await until("Expanse to take on “\(title)”", timeout: 10) { try await self.state().window(w.id) != nil }
        }
        return w
    }

    /// Several windows in a row, `gap` apart, starting at `origin` on the canvas, placed there
    /// with expanse://place.
    func row(_ titles: [String], size: CGSize = CGSize(width: 600, height: 400), gap: CGFloat = 20,
             origin: CGPoint = CGPoint(x: 0, y: 0)) async throws -> [TestWindow] {
        var made: [TestWindow] = []
        for (i, t) in titles.enumerated() {
            let w = try await window(t, CGRect(x: 100 + 30 * CGFloat(i), y: 120 + 30 * CGFloat(i), width: size.width, height: size.height))
            made.append(w)
            place(w, at: CGPoint(x: origin.x + CGFloat(i) * (size.width + gap), y: origin.y), commit: true)
        }
        try await settle()
        return made
    }

    /// Puts a window's canvas spot at `p` (expanse://place; debug builds).
    func place(_ w: TestWindow, at p: CGPoint, commit: Bool = true) {
        link("place", ["id": w.id, "x": Int(p.x), "y": Int(p.y), "commit": commit ? 1 : 0])
    }

    func canvasFrame(_ w: TestWindow) async throws -> CGRect {
        guard let f = try await state().window(w.id)?.canvas else { throw Failure("“\(w.title)” isn't on the canvas") }
        return f
    }

    func fixture(_ name: String, windows count: Int = 1, size: CGSize = CGSize(width: 640, height: 420)) async throws -> Fixture {
        let f = Fixture(name: name)
        fixtures.append(f)
        try await f.launch(windows: count, size: size)
        return f
    }

    /// Opens a file in an app with `open -a` (no Apple Events, so no Automation prompt).
    /// `newCopy`: `open -n`, another copy of an app that's running.
    func open(_ path: String, in app: String? = nil, newCopy: Bool = false) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = (newCopy ? ["-n"] : []) + (app.map { ["-a", $0] } ?? []) + [path]
        try p.run()
        p.waitUntilExit()
    }

    /// Windows of other apps, by owner name, as the window server lists them now.
    func windowsOf(owner: String) -> [(id: CGWindowID, frame: CGRect)] {
        let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { w in
            guard w[kCGWindowOwnerName as String] as? String == owner, (w[kCGWindowLayer as String] as? Int) == 0,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
                  r.width >= 100 else { return nil }
            return (id, r)
        }
    }

    // MARK: Screen

    var screen: CGRect { NSScreen.screens.first.map { CGRect(origin: .zero, size: $0.frame.size) } ?? .zero }
    var displayCount: Int { NSScreen.screens.count }

    // MARK: Checks

    func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw Failure(message()) }
    }

    func expectNear(_ a: CGPoint, _ b: CGPoint, within d: CGFloat = 2, _ what: String) throws {
        if hypot(a.x - b.x, a.y - b.y) > d { throw Failure("\(what): \(a) isn't within \(d)pt of \(b)") }
    }

    func expectNear(_ a: CGRect, _ b: CGRect, within d: CGFloat = 2, _ what: String) throws {
        let off = max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height))
        if off > d { throw Failure("\(what): \(a) isn't within \(d)pt of \(b)") }
    }

    /// Input (keys, the pointer, scrolls) needs Accessibility for Expanse Tests.
    func needsInput() throws {
        if !Input.allowed { throw Skip("needs Accessibility for Expanse Tests, to post keys and pointer events") }
    }

    // MARK: You

    /// Asks you to do something, then carries on. Throws if you say it couldn't be done.
    func ask(_ instruction: String) async throws {
        switch await human.ask(instruction, buttons: ["Done", "Can't do this here"]) {
        case 0: return
        default: throw Skip("skipped by the tester: \(instruction)")
        }
    }

    /// Asks whether something looks right.
    func look(_ question: String) async throws {
        switch await human.ask(question, buttons: ["Yes", "No", "Can't tell here"]) {
        case 0: return
        case 1: throw Failure("the tester said no: \(question)")
        default: throw Skip("the tester couldn't check: \(question)")
        }
    }

    // MARK: Between cases

    func begin() { start = log.mark() }

    /// Closes this case's windows and fixtures, and leaves Expanse at 100%, running, on the real display.
    func cleanUp() async {
        for w in windows { w.close() }
        windows = []
        for f in fixtures { await f.quit() }
        fixtures = []
        if expanse == nil { try? await launchExpanse() }
        guard let s = try? await state() else { return }
        if s.paused { link("resume") }
        if pretendDisplay {
            // Back to the real display, and past the settle period that follows a display change
            // (CanvasController.settleDuration), so the next case starts as after any other.
            link("screen")
            pretendDisplay = false
            try? await Task.sleep(nanoseconds: 21_000_000_000)
        }
        if s.active { link("exit") }
        _ = try? await settle()
    }
}

/// Changes one of Expanse's settings (its defaults domain), as `defaults write` would; nil removes
/// it. Expanse reads most of them as it goes; some only at launch (see the case).
func setExpanseDefault(_ key: String, _ value: Any?) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    switch value {
    case nil: p.arguments = ["delete", "com.invignation.expanse", key]
    case let b as Bool: p.arguments = ["write", "com.invignation.expanse", key, "-bool", b ? "true" : "false"]
    case let i as Int: p.arguments = ["write", "com.invignation.expanse", key, "-int", "\(i)"]
    case let d as Double: p.arguments = ["write", "com.invignation.expanse", key, "-float", "\(d)"]
    default: p.arguments = ["write", "com.invignation.expanse", key, "-string", "\(value!)"]
    }
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
}

/// Reads one of Expanse's settings.
func expanseDefault(_ key: String) -> Any? {
    CFPreferencesCopyAppValue(key as CFString, "com.invignation.expanse" as CFString)
}
