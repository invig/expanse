import AppKit
import ApplicationServices
import Security

/// The manual cases in docs/regression/first-launch.md, and SETUP-09's live ticks (its done
/// flags are a unit case). The walkthrough and Settings are read and pressed through
/// Accessibility. A fresh permission state is yours to make (`tccutil`, which Expanse Tests never
/// runs); Expanse's own settings are backed up first and put back after.
@MainActor enum SETUP {
    static let cases: [Case] = [
        Case("SETUP-01", "First launch: the walkthrough comes before any macOS prompt", .guided) { t in
            try t.needsInput()
            try await t.setupFirstLaunch(reset: ["Accessibility", "ScreenCapture"], clear: ["*"]) {
                // The welcome window with its four-step checklist, and no macOS prompt before a button's pressed.
                let tree = try await t.setupWelcomeTree()
                for text in ["Welcome to Expanse", "Your Mac, on an infinite canvas.", "Four quick steps", "Let Expanse move your windows",
                             "Let Expanse show your windows", "Free up a screen corner", "Free up ⌃ + arrow keys"] {
                    try t.expect(tree.has(text), "the welcome page should say “\(text)”")
                }
                for _ in 0..<6 {
                    try t.expect(setupPrompt() == nil, "a macOS permission prompt came up before any button was pressed")
                    try await t.pause(0.5)
                }
                // ⌥`, ⌃→ and expanse://toggle do nothing yet, and no window moves.
                let w = try await t.window("SETUP-01 A", managed: false)
                try await t.pause(0.5)
                let before = w.real
                let mark = t.log.mark()
                Input.key(.grave, .maskAlternate)
                // (Not while macOS has ⌃→ itself: it would switch Space.)
                if !setupMacHas(controlArrow: 81) { Input.key(.right, .maskControl) }
                t.link("toggle")
                try await t.expectLog("ignored URL command toggle: Expanse starts once the walkthrough is done", since: mark)
                try await t.pause(1)
                if let before, let now = w.real { try t.expectNear(now, before, "“SETUP-01 A” moved before the walkthrough was done") }
                try t.expect(!t.setupWindows().contains { $0.layer == setupCanvasLevel }, "the canvas opened before the walkthrough was done")
                try t.expect(setupPrompt() == nil, "a macOS permission prompt came up without a button being pressed")
            }
        },
        Case("SETUP-02", "Permission steps show live status and open the right Settings pane", .guided) { t in
            try t.needsInput()
            try await t.setupFirstLaunch(reset: ["Accessibility", "ScreenCapture"], clear: ["*"]) {
                let pid = t.setupPID
                try await t.setupWalkthrough(to: "STEP 1 OF 4")
                // The step's button: macOS's prompt in front, or the Accessibility pane.
                try t.setupPressInWelcome("Open Settings")
                try await t.setupPromptOrSystemSettings()
                // Switched on in System Settings, the card ticks within about a second, with no relaunch.
                try await t.ask("Switch Expanse on in System Settings › Privacy & Security › Accessibility (macOS's prompt's Open System Settings goes there). Leave the walkthrough as it is.")
                try await t.until("the Accessibility card to say On", timeout: 3) { (try? await t.setupWelcomeTree())?.has("On") == true }
                try t.expect(t.setupPID == pid, "Expanse relaunched: the tick should come without one")
                // The Screen Recording step's button.
                try await t.setupWalkthrough(to: "STEP 2 OF 4")
                try t.setupPressInWelcome("Open Settings")
                try await t.setupPromptOrSystemSettings()
            }
        },
        Case("SETUP-03", "Screen Recording: Expanse reopens itself to apply it", .guided) { t in
            try t.needsInput()
            try await t.setupFirstLaunch(reset: ["ScreenCapture"], clear: ["onboardingDone", "onboardingPage"]) {
                try await t.setupWalkthrough(to: "STEP 2 OF 4")
                try t.setupPressInWelcome("Open Settings")
                try await t.ask("Allow Screen Recording: click Open System Settings in macOS's prompt and switch Expanse on. If macOS offers to quit and reopen Expanse, choose Later.")
                try await t.until("the step's button to read Reopen Expanse", timeout: 5) {
                    (try? await t.setupWelcomeTree())?.button("Reopen Expanse") != nil
                }
                guard let old = t.expanse else { throw Failure("Expanse isn't running") }
                try t.setupPressInWelcome("Reopen Expanse")
                try await t.until("Expanse to quit", timeout: 15) { old.isTerminated }
                try await t.until("Expanse to open again", timeout: 20) { t.expanse != nil }
                try await t.until("the walkthrough to come back", timeout: 15) { t.setupWelcome() != nil }
                let tree = try await t.setupWelcomeTree()
                try t.expect(tree.has("STEP 2 OF 4"), "the walkthrough should come back on the page you were on (Step 2)")
                try t.expect(tree.has("On"), "Screen Recording should be ticked (On) once Expanse has reopened")
            }
        },
        Case("SETUP-05", "Closing the walkthrough releases it") { t in
            try await t.setupClosingUp {
                try t.needsInput()
                let idle = try await t.setupCPU(over: 4)
                t.link("welcome")
                try await t.until("the walkthrough to open") { t.setupWelcome() != nil }
                guard let first = t.setupWelcome() else { throw Failure("the walkthrough closed by itself") }
                try await t.pause(1)
                try await t.setupCloseWelcome()
                try await t.pause(1)
                let after = try await t.setupCPU(over: 4)
                try t.expect(after <= max(idle * 2, idle + 0.05),
                             "Expanse's CPU use stayed up once the walkthrough was closed (\(setupPercent(after)) of a core; \(setupPercent(idle)) before it opened)")
                // It reopens fresh: a new window, on its first page.
                t.link("welcome")
                try await t.until("the walkthrough to open again") { t.setupWelcome() != nil }
                guard let second = t.setupWelcome() else { throw Failure("the walkthrough closed by itself") }
                try t.expect(second.id != first.id, "the walkthrough should reopen as a new window, not the one that was closed")
                try t.expect(try await t.setupWelcomeTree().has("Welcome to Expanse"), "the walkthrough should reopen on its first page")
                try await t.setupCloseWelcome()
                // Expanse's shortcuts work.
                Input.key(.grave, .maskAlternate)
                try await t.until("⌥` to open the canvas", timeout: 3) { try await t.state().active }
            }
        },
        Case("SETUP-06", "No repeated Screen Recording prompts before the relaunch", .guided) { t in
            try t.needsInput()
            try await t.setupFirstLaunch(reset: ["ScreenCapture"], clear: ["onboardingPage"]) {
                try await t.setupWalkthrough(to: "STEP 2 OF 4")
                try t.setupPressInWelcome("Open Settings")
                try await t.ask("Click Open System Settings in macOS's prompt and switch Expanse on. If macOS offers to quit and reopen Expanse, choose Later: don't reopen it.")
                let pid = t.setupPID
                // Closing the walkthrough starts Expanse, as finishing does.
                try await t.setupCloseWelcome()
                try await t.until("Expanse to start", timeout: 10) { (try? await t.state()) != nil }
                let w = try await t.window("SETUP-06 A", managed: false)
                // For 30s macOS's prompt doesn't come back, and the canvas takes on no windows.
                var prompts = Set<CGWindowID>()
                for _ in 0..<60 {
                    if let p = setupPrompt() { prompts.insert(p.id) }
                    try await t.pause(0.5)
                }
                try t.expect(prompts.isEmpty, "macOS's Screen Recording prompt came up \(prompts.count) times before Expanse was reopened")
                let s = try await t.state()
                try t.expect(s.windows.isEmpty, "until it's reopened, the canvas should take on no windows (it has \(s.windows.count), “SETUP-06 A” \(s.window(w.id) == nil ? "not " : "")among them)")
                try t.expect(t.setupPID == pid, "Expanse reopened by itself")
                t.link("enter")
                try await t.settle()
                try await t.look("Zoomed out: the canvas is plain, with no desktop picture and no windows?")
                t.link("exit")
                try await t.settle()
                // Once reopened, it takes windows on.
                try await t.relaunchExpanse()
                try await t.until("Expanse to take on “SETUP-06 A”", timeout: 20) { try await t.state().window(w.id) != nil }
            }
        },
        // Guided: a copy opened by Expanse Tests (even through `open -n`) counts as its request, and macOS hands
        // the front back to it as the copy quits; opened from Finder, the Dock or Spotlight, it doesn't.
        Case("SETUP-07", "A second copy quits and shows the running one's welcome window", .guided) { t in
            try await t.setupClosingUp {
                try t.setupNeedsAX()
                let a = try await t.window("SETUP-07 A")
                for zoomedOut in [false, true] {
                    let before = try await t.settle()
                    let real = a.real
                    if zoomedOut {
                        t.link("enter")
                        try await t.until("zoomed out") { try await t.settle().active }
                    }
                    guard let running = t.expanse else { throw Failure("Expanse isn't running") }
                    try await t.ask(zoomedOut
                        ? "Open Expanse again with Spotlight (⌘-Space, type Expanse, Return): the canvas covers the Dock. Then click Done."
                        : "Open Expanse again the way you usually would: from Finder, the Dock or Spotlight. Then click Done.")
                    // The second copy exits at once, leaving the running one.
                    try await t.until("the second copy to quit", timeout: 5) {
                        NSRunningApplication.runningApplications(withBundleIdentifier: "com.invignation.expanse")
                            .filter { !$0.isTerminated }.map(\.processIdentifier) == [running.processIdentifier]
                    }
                    // The running copy shows its welcome window in front, having left the canvas.
                    try await t.until("the welcome window", timeout: 5) { t.setupWelcome() != nil }
                    let s = try await t.settle()
                    try t.expect(!s.active, "the running copy should leave the canvas before showing its welcome window")
                    if let w = t.setupWelcome() { try t.setupExpectInFront(w, "the welcome window") }
                    // No window moved.
                    if let real, let now = a.real { try t.expectNear(now, real, "“SETUP-07 A” moved") }
                    if let f = before.window(a.id)?.canvas, let g = s.window(a.id)?.canvas { try t.expectNear(g, f, within: 1, "“SETUP-07 A”'s spot on the canvas moved") }
                    try await t.setupCloseWelcome()
                }
            }
        },
        Case("SETUP-08", "Reopening Expanse waits for the old copy to quit", .guided) { t in
            try t.needsInput()
            let page = expanseDefault("onboardingPage")
            defer { setExpanseDefault("onboardingPage", page) }
            let settingsRan = setupSystemSettingsRunning()
            defer { if !settingsRan { setupQuitSystemSettings() } }
            do {
                // 30 windows out of view, for quitting to put back.
                let f = try await t.fixture("SETUP-08", windows: 30, size: CGSize(width: 320, height: 220))
                try await t.until("Expanse to take on the 30 windows", timeout: 40) {
                    let s = try await t.state()
                    return f.windows.allSatisfy { s.window($0) != nil }
                }
                for (i, id) in f.windows.enumerated() { t.link("place", ["id": id, "x": 6000 + (i % 6) * 360, "y": (i / 6) * 260, "commit": 1]) }
                try await t.settle(timeout: 20)
                try await t.ask("In Terminal, run: tccutil reset ScreenCapture com.invignation.expanse")
                t.link("welcome")
                try await t.until("the walkthrough to open") { t.setupWelcome() != nil }
                try await t.setupWalkthrough(to: "STEP 2 OF 4")
                try t.setupPressInWelcome("Open Settings")
                try await t.ask("Allow Screen Recording: click Open System Settings in macOS's prompt and switch Expanse on. If macOS offers to quit and reopen Expanse, choose Later.")
                try await t.until("the step's button to read Reopen Expanse", timeout: 5) {
                    (try? await t.setupWelcomeTree())?.button("Reopen Expanse") != nil
                }
                guard let old = t.expanse else { throw Failure("Expanse isn't running") }
                try t.setupPressInWelcome("Reopen Expanse")
                // The old copy quits, putting the windows back; only then does the new one open, and it stays.
                try await t.until("the old copy to quit", timeout: 40) { old.isTerminated }
                let gone = Date()
                try await t.until("Expanse to open again", timeout: 20) { t.expanse != nil }
                guard let new = t.expanse else { throw Failure("Expanse didn't come back") }
                if let launched = new.launchDate {
                    try t.expect(launched > gone.addingTimeInterval(-1), "the new copy started before the old one had quit")
                }
                try await t.pause(5)
                try t.expect(!new.isTerminated, "the new copy quit: Expanse stayed closed")
                try await t.until("Expanse to carry on, with the windows on the canvas", timeout: 40) {
                    let s = try await t.state()
                    return f.windows.allSatisfy { s.window($0) != nil }
                }
            } catch {
                try? await t.setupPutBack(nil)
                throw error
            }
        },
        Case("SETUP-09", "The welcome page lists the four steps with live ticks", .guided) { t in
            try t.needsInput()
            try await t.setupFirstLaunch(clear: ["onboardingDone", "onboardingPage"]) {
                guard let w = t.setupWelcome() else { throw Failure("the walkthrough isn't open") }
                try t.expect(abs(w.frame.width - 960) < 1 && abs(w.frame.height - 620) < 1, "the walkthrough should be 960×620 (it's \(w.frame.size))")
                let tree = try await t.setupWelcomeTree()
                for text in ["Welcome to Expanse", "Your Mac, on an infinite canvas.", "Four quick steps", "Let Expanse move your windows",
                             "Let Expanse show your windows", "Free up a screen corner", "Free up ⌃ + arrow keys",
                             "No hacks or SIP changes. Quit any time and every window goes back where it was."] {
                    try t.expect(tree.has(text), "the welcome page should say “\(text)”")
                }
                try t.expect(tree.button("Get started") != nil, "the footer should have a Get started button")
                // A tick for each step that's done, its number otherwise. Expanse logs its permissions as it starts.
                let started = t.log.lines(since: t.start).last { $0.hasPrefix("accessibility=") } ?? ""
                let done = [started.contains("accessibility=true"), started.contains("screenRecording=true"),
                            setupCornersInTheWay().isEmpty, setupArrowsInTheWay().isEmpty]
                try t.expect(setupTicks(tree) == done, "the four rows' ticks \(setupTicks(tree)) don't match what's done \(done)")
                // Changed in System Settings, the matching row follows within about a second.
                try await t.ask("In System Settings change one of the last two steps: set a macOS hot corner that Expanse uses to – (or back to an action), or switch one of Mission Control's ⌃-arrow shortcuts off (or on).")
                let now = [done[0], done[1], setupCornersInTheWay().isEmpty, setupArrowsInTheWay().isEmpty]
                try t.expect(now != done, "neither macOS's hot corners nor its ⌃-arrow shortcuts changed in a way the walkthrough shows")
                try await t.until("the rows to follow the change", timeout: 3) {
                    (try? await t.setupWelcomeTree()).map { setupTicks($0) == now } ?? false
                }
                try await t.ask("Put that setting back as it was.")
            }
        },
        Case("SETUP-15", "The last page is a cheat sheet") { t in
            try await t.setupClosingUp {
                try t.setupNeedsAX()
                let page = expanseDefault("onboardingPage")
                defer { setExpanseDefault("onboardingPage", page) }
                t.link("welcome")
                try await t.until("the walkthrough to open") { t.setupWelcome() != nil }
                try await t.setupWalkthrough(to: "ALL SET")
                let tree = try await t.setupWelcomeTree()
                let sheet = ["Try it now.", "Zoom out to every window, and back", "Dive into a window", "Hop to the nearest window that way",
                             "Centre the window you're in", "Zoom and pan the canvas", "Hold Space and drag to move around",
                             "Move windows; they snap into place", "Select several, then drag or close them together",
                             "Tidy up: line up each group, where it is", "Find this again under the menu bar icon › Welcome & Shortcuts.",
                             "⌥", "`", "Click", "⌃", "← → ↑ ↓", "C", "Pinch", "Scroll", "Space", "Drag", "⇧", "T"]
                let missing = sheet.filter { !tree.has($0) }
                try t.expect(missing.isEmpty, "the last page is missing: \(missing.joined(separator: "; "))")
                // Start using Expanse closes the walkthrough, and Expanse is running.
                guard let start = tree.button("Start using Expanse") else { throw Failure("no Start using Expanse button on the last page") }
                start.press()
                try await t.until("the walkthrough to close", timeout: 3) { t.setupWelcome() == nil }
                let s = try await t.state()
                try t.expect(!s.paused, "Expanse should be running once the walkthrough closes")
            }
        },
        Case("SETUP-17", "macOS's Screen Recording prompt comes to the front", .guided) { t in
            try t.needsInput()
            try await t.setupFirstLaunch(reset: ["ScreenCapture"], clear: ["onboardingPage"]) {
                try await t.setupWalkthrough(to: "STEP 2 OF 4")
                try await t.setupExpectPromptInFront(pressing: "Open Settings")
                try await t.ask("In macOS's prompt, click Open System Settings.")
                try await t.until("System Settings in front", timeout: 6) { setupSystemSettingsInFront() }
                try await t.look("System Settings is at Privacy & Security › Screen Recording, with Expanse in the list?")
                let tree = try await t.setupWelcomeTree()
                try t.expect(tree.has("Switched it on? Reopen Expanse to finish."), "the card should read “Switched it on? Reopen Expanse to finish.”")
                try t.expect(tree.button("Reopen Expanse") != nil, "the card's button should read Reopen Expanse")
                try t.expect(tree.button("Continue") != nil, "the step should count as done (the footer's button reads Continue)")
            }
        },
        Case("SETUP-19", "System Settings opens in front of the walkthrough") { t in
            try await t.setupClosingUp {
                try t.setupNeedsAX()
                let settingsRan = setupSystemSettingsRunning()
                defer { if !settingsRan { setupQuitSystemSettings() } }
                let page = expanseDefault("onboardingPage")
                defer { setExpanseDefault("onboardingPage", page) }
                t.link("welcome")
                try await t.until("the walkthrough to open") { t.setupWelcome() != nil }
                guard let w = t.setupWelcome() else { throw Failure("the walkthrough closed by itself") }
                try t.expect(w.layer == 0, "the walkthrough should be an ordinary window (level 0, not \(w.layer))")
                for (heading, pane) in [("STEP 3 OF 4", "Desktop & Dock"), ("STEP 4 OF 4", "Keyboard")] {
                    try await t.setupWalkthrough(to: heading)
                    t.link("welcome")   // the walkthrough in front again
                    try await t.until("the walkthrough in front") { NSWorkspace.shared.frontmostApplication?.processIdentifier == t.setupPID }
                    try t.setupPressInWelcome("Open Settings")
                    try await t.until("System Settings (\(pane)) to open in front of the walkthrough", timeout: 10) {
                        setupSystemSettingsInFront() && t.setupSystemSettingsAbove(w.id)
                    }
                }
                try await t.setupCloseWelcome()
            }
        },
        Case("SETUP-20", "macOS's Accessibility prompt comes to the front", .guided) { t in
            try t.needsInput()
            try await t.setupFirstLaunch(reset: ["Accessibility"], clear: ["onboardingPage"]) {
                try await t.setupWalkthrough(to: "STEP 1 OF 4")
                try await t.setupExpectPromptInFront(pressing: "Open Settings")
                try await t.ask("In macOS's prompt click Open System Settings, then switch Expanse on in the Accessibility list.")
                try await t.until("the Accessibility card to say On", timeout: 3) { (try? await t.setupWelcomeTree())?.has("On") == true }
            }
        },
        Case("SETUP-22", "The walkthrough window is exactly the page's size", .look) { t in
            try await t.setupClosingUp {
                try t.setupNeedsAX()
                let before = Set(t.setupWindows().map(\.id))
                t.link("welcome")
                var found: SetupWin?
                try await t.until("the walkthrough to open") {
                    found = t.setupWindows().first { $0.layer == 0 && !before.contains($0.id) && $0.frame.width > 400 }
                    return found != nil
                }
                guard let w = found else { throw Failure("the walkthrough didn't open") }
                try t.expect(abs(w.frame.width - 960) < 1 && abs(w.frame.height - 620) < 1,
                             "the walkthrough window should be 960×620 (it's \(Int(w.frame.width))×\(Int(w.frame.height)))")
                try await t.look("The walkthrough's page and illustration run right to the window's edges and up under its see-through title bar, with no empty strip along the bottom?")
                try await t.setupCloseWelcome()
            }
        },
        Case("SETUP-24", "A release build opens at login after its first start", .guided) { t in
            throw Skip(setupIsRelease(t.expanseURL)
                ? "the runner drives development builds (a release ignores the debug links it uses), and this needs logging out and in"
                : "needs a Developer ID–signed release (a development build never registers itself; see SETUP-25), and logging out and in")
        },
        Case("SETUP-25", "Open at Login stays as you set it; development builds don't register") { t in
            try await t.setupClosingUp {
                try t.setupNeedsAX()
                guard !setupIsRelease(t.expanseURL) else { throw Skip("the runner drives development builds; this one is a release") }
                let wasOn = try await t.setupOpenSettings().tree.first("Open Expanse at login", role: kAXCheckBoxRole)?.on
                try await t.setupCloseSettings()
                let old = expanseDefault("loginItemSetUp")
                defer { setExpanseDefault("loginItemSetUp", old) }
                // A fresh development build, loginItemSetUp deleted: it never registers by itself.
                try await t.quitExpanse()
                setExpanseDefault("loginItemSetUp", nil)
                let mark = t.log.mark()
                try await t.launchExpanse()
                try await t.pause(3)
                try t.expect(!t.log.lines(since: mark).contains { $0.hasPrefix("login item registered") || $0.hasPrefix("login item registration failed") },
                             "a development build tried to register itself as a login item as it started")
                try t.expect(expanseDefault("loginItemSetUp") == nil, "a development build set loginItemSetUp by itself")
                let settings = try await t.setupOpenSettings()
                try t.expect(settings.tree.has(setupDevNote), "Settings should say “\(setupDevNote)”")
                let isOn = settings.tree.first("Open Expanse at login", role: kAXCheckBoxRole)?.on
                try t.expect(isOn == wasOn, "Open Expanse at login changed by itself (\(wasOn == true ? "on" : "off") before, \(isOn == true ? "on" : "off") now)")
                try await t.setupCloseSettings()
                throw Skip("development build checked (step 3: it doesn't register itself); steps 1–2 need a Developer ID–signed release that's registered at login")
            }
        },
        Case("SETUP-26", "Turning Open at Login back on after switching it off in System Settings", .guided) { t in
            try await t.setupClosingUp {
                try t.needsInput()
                let settingsRan = setupSystemSettingsRunning()
                defer { if !settingsRan { setupQuitSystemSettings() } }
                let old = expanseDefault("loginItemSetUp")
                defer { setExpanseDefault("loginItemSetUp", old) }
                // (The case is written for a release; a development build's login item works the same since 4045597.)
                let wasOn = try await t.setupOpenSettings().tree.first("Open Expanse at login", role: kAXCheckBoxRole)?.on ?? false
                try await t.setupSetLogin(true, approving: true)
                NSWorkspace.shared.open(setupLoginItemsPane)
                try await t.ask("In System Settings › General › Login Items, select Expanse under Open at Login and click −.")
                // The switch follows when Settings is key again.
                _ = try await t.setupOpenSettings()
                try await t.until("the switch to show off", timeout: 5) { t.setupLoginSwitch() == false }
                // On again from Expanse's Settings: on at once, or System Settings opens at Login Items for your OK,
                // and the switch shows on only once it's really on.
                guard let sw = t.setupSettings()?.tree.first("Open Expanse at login", role: kAXCheckBoxRole) else { throw Failure("Expanse Settings isn't open") }
                sw.press()
                try await t.pause(1.5)
                if t.setupLoginSwitch() != true {
                    try await t.until("System Settings at Login Items, for your OK", timeout: 5) { setupSystemSettingsInFront() }
                    try await t.look("System Settings opened at Login Items, asking you to allow Expanse, and Expanse's switch still shows off?")
                    try await t.ask("Allow Expanse there (switch it on).")
                    _ = try await t.setupOpenSettings()
                    try await t.until("the switch to show on", timeout: 5) { t.setupLoginSwitch() == true }
                }
                if !wasOn { try await t.setupSetLogin(false, approving: false) }
                try await t.setupCloseSettings()
            }
        },
        Case("SETUP-27", "A development build can open at login", .look) { t in
            try await t.setupClosingUp {
                try t.needsInput()
                guard !setupIsRelease(t.expanseURL) else { throw Skip("this is about development builds; the one running is a release") }
                let settingsRan = setupSystemSettingsRunning()
                defer { if !settingsRan { setupQuitSystemSettings() } }
                let old = expanseDefault("loginItemSetUp")
                defer { setExpanseDefault("loginItemSetUp", old) }
                let settings = try await t.setupOpenSettings()
                try t.expect(settings.tree.has(setupDevNote), "Settings should say “\(setupDevNote)”")
                guard let sw = settings.tree.first("Open Expanse at login", role: kAXCheckBoxRole) else { throw Failure("no “Open Expanse at login” switch") }
                try t.expect(sw.enabled, "a development build's “Open Expanse at login” should work, not be greyed out")
                let wasOn = sw.on ?? false
                if wasOn { try await t.setupSetLogin(false, approving: false) }
                try await t.setupSetLogin(true, approving: true)
                NSWorkspace.shared.open(setupLoginItemsPane)
                try await t.look("System Settings › General › Login Items lists Expanse under Open at Login (this copy, \(t.expanseURL.path))? (Logging out and in isn't part of this run.)")
                _ = try await t.setupOpenSettings()
                if !wasOn { try await t.setupSetLogin(false, approving: false) }
                try await t.setupCloseSettings()
            }
        },
    ]
}

// MARK: - Levels, sizes, settings

private let setupCanvasLevel = Int(CGWindowLevelForKey(.mainMenuWindow)) - 1
private let setupPanelLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
private let setupPanelWidth: CGFloat = 360 + 2 * 24
private let setupDevNote = "This is a development build: it has no updates, and opening at login opens this copy."
private let setupLoginItemsPane = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

private func setupPercent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

private func setupSame(_ a: CGRect, _ b: CGRect) -> Bool {
    max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height)) <= 2
}

/// Runs `defaults` with `arguments`.
@discardableResult
private func setupDefaults(_ arguments: [String]) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    p.arguments = arguments
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

/// Expanse's settings, saved to a file (nil: it has none).
private func setupBackUpSettings() -> URL? {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("expanse-settings-\(UUID().uuidString).plist")
    return setupDefaults(["export", "com.invignation.expanse", file.path]) ? file : nil
}

/// Expanse's settings exactly as `backup` has them (Expanse quit, so it doesn't write over them).
private func setupRestoreSettings(_ backup: URL?) {
    setupDefaults(["delete", "com.invignation.expanse"])
    if let backup { setupDefaults(["import", "com.invignation.expanse", backup.path]) }
}

private func setupSystemSettingsRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").isEmpty
}

private func setupQuitSystemSettings() {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").forEach { $0.terminate() }
}

private func setupSystemSettingsInFront() -> Bool {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
}

/// Signed with a Developer ID, as Updater.isRelease checks.
private func setupIsRelease(_ app: URL) -> Bool {
    var code: SecStaticCode?, requirement: SecRequirement?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
          SecRequirementCreateWithString("anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]" as CFString,
                                         [], &requirement) == errSecSuccess, let requirement else { return false }
    return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
}

/// Whether macOS's own shortcut `id` (79/81 move left/right a space, 32 Mission Control, 33
/// application windows) is on: on until it's been changed.
private func setupMacHas(controlArrow id: Int) -> Bool {
    let domain = "com.apple.symbolichotkeys" as CFString
    CFPreferencesAppSynchronize(domain)
    let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
    guard let entry = all[String(id)] as? [String: Any] else { return true }
    return entry["enabled"] as? Bool ?? false
}

/// macOS's hot corners in the way of Expanse's own, as the walkthrough works them out
/// (SystemShortcuts.hotCorners): an action, and no key to hold.
private func setupCornersInTheWay() -> [String] {
    let dock = "com.apple.dock" as CFString
    CFPreferencesAppSynchronize(dock)
    let mine: [String: [String]] = ["off": [], "topLeft": ["tl"], "topRight": ["tr"], "bottomLeft": ["bl"], "bottomRight": ["br"]]
    let keys = mine[expanseDefault("hotCorner") as? String ?? "all"] ?? ["tl", "tr", "bl", "br"]
    return keys.filter { key in
        let action = CFPreferencesCopyAppValue("wvous-\(key)-corner" as CFString, dock) as? Int ?? 1
        let modifier = CFPreferencesCopyAppValue("wvous-\(key)-modifier" as CFString, dock) as? Int ?? 0
        return action > 1 && modifier == 0
    }
}

/// macOS's ⌃ + arrow shortcuts that are on, as the walkthrough works them out (SystemShortcuts.controlArrows).
private func setupArrowsInTheWay() -> [String] {
    let domain = "com.apple.symbolichotkeys" as CFString
    CFPreferencesAppSynchronize(domain)
    let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
    var on = [32, 33, 79, 81].filter { all[String($0)] == nil }.map(String.init)
    for (id, value) in all {
        guard let entry = value as? [String: Any], entry["enabled"] as? Bool == true,
              let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int], params.count == 3,
              (123...126).contains(params[1]), params[2] & 0x40000 != 0, params[2] & (0x20000 | 0x80000 | 0x100000) == 0 else { continue }
        on.append(id)
    }
    return on
}

// MARK: - Windows, as the window server has them

/// A window: where, at what level, and whose.
private struct SetupWin {
    let id: CGWindowID
    let frame: CGRect
    let layer: Int
    let pid: pid_t
}

/// On-screen windows front to back, any level.
private func setupScreenWindows() -> [SetupWin] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        guard let id = w[kCGWindowNumber as String] as? CGWindowID, let pid = w[kCGWindowOwnerPID as String] as? Int,
              (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) else { return nil }
        return SetupWin(id: id, frame: r, layer: w[kCGWindowLayer as String] as? Int ?? 0, pid: pid_t(pid))
    }
}

/// One of macOS's permission prompts on screen (see Permissions.prompts in Onboarding.swift).
private func setupPrompt() -> SetupWin? {
    let pids = Set(NSWorkspace.shared.runningApplications.filter { $0.executableURL?.lastPathComponent == "universalAccessAuthWarn" }.map(\.processIdentifier))
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let owners = Set(info.compactMap { w -> pid_t? in
        w[kCGWindowOwnerName as String] as? String == "universalAccessAuthWarn" ? (w[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) : nil
    })
    return setupScreenWindows().first { pids.union(owners).contains($0.pid) }
}

/// Where the window server lists window `id`, front to back among those on screen.
private func setupFrontIndex(of id: CGWindowID) -> Int? { setupScreenWindows().firstIndex { $0.id == id } }

fileprivate extension Ctx {
    var setupPID: pid_t? { expanse?.processIdentifier }

    func setupWindows() -> [SetupWin] {
        guard let pid = setupPID else { return [] }
        return setupScreenWindows().filter { $0.pid == pid }
    }

    /// The walkthrough (or Welcome & Shortcuts) window.
    func setupWelcome() -> SetupWin? {
        setupWindows().first { $0.layer == 0 && abs($0.frame.width - 960) < 2 && abs($0.frame.height - 620) < 2 }
    }

    /// Expanse is the active app and `w` the front ordinary window.
    func setupExpectInFront(_ w: SetupWin, _ what: String) throws {
        let front = NSWorkspace.shared.frontmostApplication
        try expect(front?.processIdentifier == setupPID, "\(what) should come to the front (the frontmost app is \(front?.localizedName ?? "none"))")
        let ordinary = setupScreenWindows().first { $0.layer == 0 && $0.frame.width >= 100 && $0.frame.height >= 100 }
        try expect(ordinary?.id == w.id, "\(what) should be in front of every other window")
    }

    /// A System Settings window is in front of the walkthrough's.
    func setupSystemSettingsAbove(_ welcome: CGWindowID) -> Bool {
        let settings = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").map(\.processIdentifier))
        let list = setupScreenWindows()
        guard let mine = list.firstIndex(where: { $0.id == welcome }),
              let theirs = list.firstIndex(where: { settings.contains($0.pid) && $0.layer == 0 && $0.frame.width >= 100 }) else { return false }
        return theirs < mine
    }

    /// Reading Expanse's walkthrough and Settings needs Accessibility for Expanse Tests, as input does.
    func setupNeedsAX() throws {
        if !AXIsProcessTrusted() { throw Skip("needs Accessibility for Expanse Tests, to read and press Expanse's windows") }
    }

    /// Expanse's CPU use over `seconds`, as a share of one core.
    func setupCPU(over seconds: TimeInterval) async throws -> Double {
        guard let pid = setupPID, let a = setupCPUTime(pid) else { throw Failure("can't read Expanse's CPU time") }
        try await pause(seconds)
        guard let b = setupCPUTime(pid) else { throw Failure("can't read Expanse's CPU time") }
        return (b - a) / seconds
    }

    /// A first launch, or as near as this Mac allows: Expanse quit; `reset` privacy services reset
    /// by you; `clear` settings removed (every one for ["*"]); then Expanse started, with its
    /// walkthrough up, for `body`. Afterwards Expanse's settings are as they were, and it's
    /// running and answering again.
    func setupFirstLaunch(reset: [String] = [], clear: [String], _ body: () async throws -> Void) async throws {
        let backup = setupBackUpSettings()
        let settingsRan = setupSystemSettingsRunning()
        var failure: Error?
        do {
            try await quitExpanse()
            if !reset.isEmpty {
                try await ask("Expanse has quit. In Terminal, run: "
                              + reset.map { "tccutil reset \($0) com.invignation.expanse" }.joined(separator: "; ")
                              + (clear == ["*"] ? "  (Expanse Tests clears Expanse's settings itself, and puts them back afterwards.)" : ""))
            }
            if clear == ["*"] { setupDefaults(["delete", "com.invignation.expanse"]) } else { clear.forEach { setExpanseDefault($0, nil) } }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: expanseURL, configuration: config)
            try await until("the walkthrough to open", timeout: 20) { self.setupWelcome() != nil }
            try await body()
        } catch {
            failure = error
        }
        do { try await setupPutBack(backup) } catch { failure = failure ?? error }
        if !settingsRan { setupQuitSystemSettings() }
        if let failure { throw failure }
    }

    /// Expanse running and answering again, with `backup`'s settings (if given). Should it still
    /// lack a permission, you're asked to finish its walkthrough.
    func setupPutBack(_ backup: URL?) async throws {
        func restart() async throws {
            while let app = expanse {
                app.terminate()
                try await until("Expanse to quit", timeout: 15) { app.isTerminated }
            }
            if let backup { setupRestoreSettings(backup) }
            try await launchExpanse()
        }
        if (try? await restart()) != nil { return }
        try await ask("Expanse isn't answering, most likely because it lacks a permission: finish its walkthrough, giving it Accessibility and Screen Recording (Reopen Expanse when it asks).")
        try await restart()
    }
}

/// Expanse's CPU time so far, in seconds (`ps`: [[hh:]mm:]ss.cc).
private func setupCPUTime(_ pid: pid_t) -> Double? {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-o", "time=", "-p", "\(pid)"]
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    p.waitUntilExit()
    let parts = text.split(separator: ":").map { Double($0) }
    guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
    return parts.reduce(0) { $0 * 60 + ($1 ?? 0) }
}

// MARK: - Accessibility: the walkthrough, the panel, Settings

/// Part of Expanse's interface as Accessibility has it, read in one go per element.
private final class SetupNode {
    let el: AXUIElement
    let role: String, title: String, label: String, help: String
    let value: AnyObject?
    let enabled: Bool
    let frame: CGRect?
    let children: [SetupNode]
    lazy var flat: [SetupNode] = [self] + children.flatMap { $0.flat }

    private static let names = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute,
                                kAXEnabledAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute] as CFArray

    /// Reads `el` and (while `budget` lasts) everything in it.
    init(_ el: AXUIElement, budget: inout Int, depth: Int = 0) {
        self.el = el
        var out: CFArray?
        AXUIElementCopyMultipleAttributeValues(el, Self.names, [], &out)
        let values = (out as? [AnyObject]) ?? []
        func at(_ i: Int) -> AnyObject? {
            guard i < values.count else { return nil }
            let v = values[i]
            if CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetType(unsafeBitCast(v, to: AXValue.self)) == .axError { return nil }
            return v
        }
        role = at(0) as? String ?? ""
        title = at(1) as? String ?? ""
        label = at(2) as? String ?? ""
        help = at(3) as? String ?? ""
        value = at(4)
        enabled = at(5) as? Bool ?? true
        var origin = CGPoint.zero, size = CGSize.zero
        if let p = at(6), let s = at(7), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID(),
           AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &origin),
           AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) {
            frame = CGRect(origin: origin, size: size)
        } else {
            frame = nil
        }
        budget -= 1
        var kids: [SetupNode] = []
        if depth < 40, let list = at(8) as? [AnyObject] {
            for k in list where budget > 0 && CFGetTypeID(k) == AXUIElementGetTypeID() {
                kids.append(SetupNode(unsafeBitCast(k, to: AXUIElement.self), budget: &budget, depth: depth + 1))
            }
        }
        children = kids
    }

    var string: String { value as? String ?? "" }
    var on: Bool? { (value as? NSNumber)?.boolValue }
    var words: [String] { [title, label, string, help].filter { !$0.isEmpty } }
    func says(_ s: String) -> Bool { words.contains { $0.caseInsensitiveCompare(s) == .orderedSame } }
    func has(_ s: String) -> Bool { flat.contains { $0.says(s) } }
    func first(_ s: String, role: String? = nil) -> SetupNode? { flat.first { (role == nil || $0.role == role) && $0.says(s) } }

    /// A button that says `s`, or holds a text that does.
    func button(_ s: String) -> SetupNode? {
        let buttons = flat.filter { $0.role == kAXButtonRole }
        return buttons.first { $0.says(s) } ?? buttons.first { $0.flat.dropFirst().contains { $0.says(s) } }
    }

    @discardableResult func press() -> Bool { AXUIElementPerformAction(el, kAXPressAction as CFString) == .success }

    /// The window's close button, pressed.
    func pressClose() -> Bool {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXCloseButtonAttribute as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXUIElementGetTypeID() else { return false }
        return AXUIElementPerformAction(unsafeBitCast(v, to: AXUIElement.self), kAXPressAction as CFString) == .success
    }
}

/// The walkthrough's four checklist rows: done (a tick) or not (its number).
private func setupTicks(_ tree: SetupNode) -> [Bool] {
    (1...4).map { n in !tree.flat.contains { $0.role == kAXStaticTextRole && $0.string == "\(n)" } }
}

fileprivate extension Ctx {
    /// Expanse's windows as Accessibility lists them (its panels too, which some lists leave out).
    func setupAXWindows() -> [AXUIElement] {
        guard let pid = setupPID else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 3)
        var found: [AXUIElement] = []
        for attribute in [kAXWindowsAttribute, kAXChildrenAttribute, kAXFocusedWindowAttribute] {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, attribute as CFString, &v) == .success, let v else { continue }
            let list: [AnyObject] = CFGetTypeID(v) == AXUIElementGetTypeID() ? [v] : (v as? [AnyObject] ?? [])
            for item in list where CFGetTypeID(item) == AXUIElementGetTypeID() {
                let el = unsafeBitCast(item, to: AXUIElement.self)
                if !found.contains(where: { CFEqual($0, el) }) { found.append(el) }
            }
        }
        return found
    }

    /// The contents of Expanse's window at `frame` (as the window server has it).
    func setupTree(at frame: CGRect) -> SetupNode? {
        for el in setupAXWindows() {
            var one = 1
            guard let f = SetupNode(el, budget: &one).frame, setupSame(f, frame) else { continue }
            var budget = 3000
            return SetupNode(el, budget: &budget)
        }
        return nil
    }

    /// Runs `body`, then closes whatever of Expanse's it left open (the walkthrough, Settings, the
    /// menu bar panel), passing or failing, so the next case starts clear.
    func setupClosingUp(_ body: () async throws -> Void) async throws {
        var failure: Error?
        do { try await body() } catch { failure = error }
        if setupPanel() != nil, Input.allowed { Input.key(.escape) }
        if let w = setupWelcome(), let tree = setupTree(at: w.frame) { _ = tree.pressClose() }
        if let settings = setupSettings() { _ = settings.tree.pressClose() }
        if let failure { throw failure }
    }

    /// The walkthrough's contents (it must be open).
    func setupWelcomeTree() async throws -> SetupNode {
        var tree: SetupNode?
        try await until("the walkthrough's contents (through Accessibility)", timeout: 4) {
            guard let w = self.setupWelcome() else { return false }
            tree = self.setupTree(at: w.frame)
            return tree.map { !$0.flat.filter { $0.role == kAXButtonRole }.isEmpty } ?? false
        }
        return tree!
    }

    func setupPressInWelcome(_ label: String) throws {
        guard let w = setupWelcome(), let tree = setupTree(at: w.frame) else { throw Failure("the walkthrough isn't open") }
        guard let b = tree.button(label) else { throw Failure("no “\(label)” button in the walkthrough") }
        try expect(b.press(), "couldn't press “\(label)” in the walkthrough")
    }

    /// The walkthrough's main button (Get started, Continue, Skip for now) until the page's heading
    /// reads `heading` (as shown: “STEP 2 OF 4”).
    func setupWalkthrough(to heading: String) async throws {
        for _ in 0..<6 {
            let tree = try await setupWelcomeTree()
            if tree.has(heading) { return }
            guard let next = ["Get started", "Continue", "Skip for now"].lazy.compactMap({ tree.button($0) }).first else {
                throw Failure("no Get started, Continue or Skip for now button in the walkthrough")
            }
            next.press()
            try await pause(0.8)   // the page fades in
        }
        throw Failure("the walkthrough never showed “\(heading)”")
    }

    /// Closes the walkthrough with its close button.
    func setupCloseWelcome() async throws {
        guard let w = setupWelcome() else { return }
        guard let tree = setupTree(at: w.frame), tree.pressClose() else { throw Failure("couldn't press the walkthrough's close button") }
        try await until("the walkthrough to close", timeout: 3) { self.setupWelcome() == nil }
    }

    /// After a permission step's button: macOS's prompt in front of the walkthrough, or System Settings.
    func setupPromptOrSystemSettings() async throws {
        try await until("macOS's permission prompt, or System Settings", timeout: 6) {
            if setupSystemSettingsInFront() { return true }
            guard let prompt = setupPrompt(), let welcome = self.setupWelcome(),
                  let p = setupFrontIndex(of: prompt.id), let w = setupFrontIndex(of: welcome.id) else { return false }
            return p < w
        }
    }

    /// A permission step's button brings macOS's own prompt in front of everything, the walkthrough
    /// included, and System Settings doesn't open over it.
    func setupExpectPromptInFront(pressing button: String) async throws {
        let settingsRan = setupSystemSettingsRunning()
        let mark = log.mark()
        try setupPressInWelcome(button)
        var prompt: SetupWin?
        try await until("macOS's permission prompt", timeout: 5) {
            prompt = setupPrompt()
            return prompt != nil
        }
        guard let prompt else { throw Failure("no permission prompt") }
        try await expectLog("permission prompt up [\(prompt.id)]", since: mark)
        try await until("the prompt in front of every window", timeout: 3) {
            let list = setupScreenWindows()
            guard let p = list.firstIndex(where: { $0.id == prompt.id }) else { return false }
            return !list[..<p].contains { $0.layer == 0 && $0.frame.width >= 100 && $0.frame.height >= 100 }
        }
        // With no prompt, System Settings would open by itself after about a second and a half.
        try await pause(2)
        try expect(settingsRan ? !setupSystemSettingsInFront() : !setupSystemSettingsRunning(), "System Settings opened by itself, over macOS's prompt")
    }

    /// The menu bar panel, while it's open.
    func setupPanel() -> SetupWin? {
        setupWindows().first { $0.layer == setupPanelLevel && abs($0.frame.width - setupPanelWidth) < 2 }
    }

    /// The Expanse Settings window and its contents, if it's open.
    func setupSettings() -> (win: SetupWin, tree: SetupNode)? {
        for el in setupAXWindows() {
            var one = 1
            let shallow = SetupNode(el, budget: &one)
            guard shallow.title == "Expanse Settings", let f = shallow.frame,
                  let win = setupWindows().first(where: { $0.layer == 0 && setupSame($0.frame, f) }) else { continue }
            var budget = 2000
            return (win, SetupNode(el, budget: &budget))
        }
        return nil
    }

    /// Settings, from the menu bar panel's gear (which also brings it back, and makes it key).
    func setupOpenSettings() async throws -> (win: SetupWin, tree: SetupNode) {
        if setupPanel() == nil { link("menu") }
        var panel: SetupNode?
        try await until("the menu bar panel", timeout: 5) {
            guard let p = self.setupPanel() else { return false }
            panel = self.setupTree(at: p.frame)
            return panel?.has("Quit Expanse") == true
        }
        guard let gear = panel?.button("Settings…") else { throw Failure("no Settings… button in the menu bar panel") }
        try expect(gear.press(), "couldn't press Settings… in the menu bar panel")
        var found: (win: SetupWin, tree: SetupNode)?
        try await until("the Expanse Settings window", timeout: 5) {
            found = self.setupSettings()
            return found != nil
        }
        return found!
    }

    func setupCloseSettings() async throws {
        guard let settings = setupSettings() else { return }
        try expect(settings.tree.pressClose(), "couldn't close Expanse Settings")
        try await until("Expanse Settings to close", timeout: 3) { self.setupSettings() == nil }
    }

    func setupLoginSwitch() -> Bool? { setupSettings()?.tree.first("Open Expanse at login", role: kAXCheckBoxRole)?.on }

    /// Settings' “Open Expanse at login” flipped to `on` if it isn't. Switched off in System
    /// Settings, macOS may want your OK there first (`approving`: ask you for it).
    func setupSetLogin(_ on: Bool, approving: Bool) async throws {
        guard let sw = setupSettings()?.tree.first("Open Expanse at login", role: kAXCheckBoxRole) else { throw Failure("Expanse Settings isn't open") }
        if sw.on == on { return }
        sw.press()
        do {
            try await until("“Open Expanse at login” to turn \(on ? "on" : "off")", timeout: 3) { self.setupLoginSwitch() == on }
        } catch where on && approving {
            try await ask("macOS wants your OK: in System Settings › Login Items, switch Expanse on.")
            _ = try await setupOpenSettings()
            try await until("“Open Expanse at login” to show on", timeout: 5) { self.setupLoginSwitch() == true }
        }
    }
}
