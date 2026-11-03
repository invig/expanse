import Testing
import AppKit
import SwiftUI
@_private(sourceFile: "Onboarding.swift") @testable import Expanse
@_private(sourceFile: "AppDelegate.swift") @testable import Expanse
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "MenuPanel.swift") @testable import Expanse
@_private(sourceFile: "HotCorner.swift") @testable import Expanse

/// docs/regression/first-launch.md
@MainActor @Suite("SETUP: First launch and permissions", .serialized) struct SETUPTests {

    // MARK: Helpers

    /// Values as macOS's preferences give them back (NSNumber, NSArray, NSDictionary).
    static func plist(_ d: [String: Any]) -> [String: Any] {
        let data = try! PropertyListSerialization.data(fromPropertyList: d, format: .binary, options: 0)
        return try! PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }

    /// The Dock's preferences, for SystemShortcuts.hotCorners(in:value:).
    static func dock(_ values: [String: Int]) -> (String) -> Any? {
        let d = plist(values)
        return { d[$0] }
    }

    static let control = 0x40000, function = 0x800000, shift = 0x20000, option = 0x80000, command = 0x100000
    static let left = 123, right = 124, down = 125, up = 126

    /// An AppleSymbolicHotKeys entry, as macOS writes it.
    static func hotKey(_ enabled: Bool, key: Int, modifiers: Int) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": [65535, key, modifiers], "type": "standard"] as [String: Any]]
    }

    static func controlArrows(_ entries: [String: [String: Any]]) -> [String] {
        SystemShortcuts.controlArrows(in: plist(entries))
    }

    /// A walkthrough model with nothing done yet (whatever this Mac's own settings are).
    static func model() -> SetupModel {
        let m = SetupModel()
        m.accessibility = false
        m.screenRecording = false
        m.screenRecordingRequested = false
        m.cornersInTheWay = ["bottom‑right corner for Quick Note"]
        m.arrowsInTheWay = ["Mission Control (⌃↑)"]
        return m
    }

    /// A step page's card: whether it's ticked, and what it says.
    static func card(_ view: Any) throws -> (done: Bool, doneText: String, problem: String?, action: String) {
        let r = try #require(UITests.record(with: "doneText", in: view))
        func text(_ key: String) -> String? { (r[key] as? String).map { $0.replacingOccurrences(of: "\u{00A0}", with: " ") } }
        return (r["done"] as? Bool ?? false, text("doneText") ?? "", text("problem"), text("actionTitle") ?? "")
    }

    static let pages = OnboardingView(finish: {}).pages

    static func button(page: Int, _ m: SetupModel) -> String {
        OnboardingView.mainButton(page: page, pages: pages, stepDone: OnboardingView.stepDone(page: page, model: m))
    }

    // MARK: Cases

    @Test("SETUP-01 First launch: the walkthrough comes before any macOS prompt (logic)") func setup01() {
        Env.withDefaults([Onboarding.doneKey: nil]) {
            #expect(Onboarding.needed)
        }
    }

    @Test("SETUP-03 Screen Recording: Expanse reopens itself to apply it (logic)") func setup03() {
        // Back on the page you were on.
        Env.withDefaults([Onboarding.doneKey: nil, Onboarding.pageKey: 2]) {
            #expect(Onboarding.startPage == 2)
        }
    }

    @Test("SETUP-04 The corner and ⌃-arrow steps show what macOS has in the way") func setup04() throws {
        let all = HotCorner.Corner.all.corners
        // Top left: Mission Control, then set to "–".
        let missionControl = SystemShortcuts.hotCorners(in: all, value: Self.dock(["wvous-tl-corner": 2, "wvous-tl-modifier": 0]))
        #expect(missionControl == ["top‑left corner for Mission Control"])
        #expect(SystemShortcuts.hotCorners(in: all, value: Self.dock(["wvous-tl-corner": 1, "wvous-tl-modifier": 0])).isEmpty)

        // Mission Control's ⌃-arrows on (never changed), then off.
        #expect(Self.controlArrows([:]).count == 4)
        let off = ["32": Self.hotKey(false, key: Self.up, modifiers: Self.control | Self.function),
                   "33": Self.hotKey(false, key: Self.down, modifiers: Self.control | Self.function),
                   "79": Self.hotKey(false, key: Self.left, modifiers: Self.control | Self.function),
                   "81": Self.hotKey(false, key: Self.right, modifiers: Self.control | Self.function)]
        #expect(Self.controlArrows(off).isEmpty)

        // Each step names what's in the way, and ticks once it's gone.
        let m = Self.model()
        m.cornersInTheWay = missionControl
        let corners = try Self.card(HotCornerPage(model: m).body)
        #expect(!corners.done)
        #expect(corners.problem == "macOS uses the top‑left corner for Mission Control")
        m.arrowsInTheWay = Self.controlArrows([:])
        let arrows = try Self.card(ArrowKeysPage(model: m).body)
        #expect(!arrows.done)
        #expect(arrows.problem?.hasPrefix("Still on: ") == true)
        m.cornersInTheWay = []
        m.arrowsInTheWay = []
        #expect(try Self.card(HotCornerPage(model: m).body).done)
        #expect(try Self.card(ArrowKeysPage(model: m).body).done)
    }

    @Test("SETUP-05 Closing the walkthrough releases it (logic)") func setup05() {
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled, .closable],
                         backing: .buffered, defer: true)
        w.isReleasedWhenClosed = false
        w.contentView = NSView()
        Onboarding.window = w
        Onboarding.onFinish = {}
        Onboarding.closer.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: w))
        #expect(w.contentView == nil)
        #expect(Onboarding.window == nil)
        #expect(Onboarding.onFinish == nil)

        // The once-a-second check stops with the model.
        weak var timer: Timer?
        do {
            let m = SetupModel()
            timer = m.timer
            #expect(m.timer?.isValid == true)
        }
        #expect(timer?.isValid != true)
    }

    @Test("SETUP-09 The welcome page lists the four steps with live ticks") func setup09() {
        let m = Self.model()
        #expect(!m.accessibility && !m.screenRecording && !m.cornersDone && !m.arrowsDone)

        func rows() -> [(Int, String, Bool)] {
            UITests.reflected(ChecklistRow.self, in: WelcomePage(model: m).body).map { ($0.number, $0.title, $0.done) }
        }
        let titles = ["Let Expanse move your windows", "Let Expanse show your windows", "Free up a screen corner", "Free up ⌃ + arrow keys"]
        #expect(rows().map(\.0) == [1, 2, 3, 4])
        #expect(rows().map(\.1) == titles)
        #expect(rows().map(\.2) == [false, false, false, false])

        // Each ticks as soon as the model sees it done.
        m.accessibility = true
        #expect(rows().map(\.2) == [true, false, false, false])
        m.screenRecording = true
        #expect(rows().map(\.2) == [true, true, false, false])
        m.cornersInTheWay = []
        #expect(m.cornersDone)
        #expect(rows().map(\.2) == [true, true, true, false])
        m.arrowsInTheWay = []
        #expect(m.arrowsDone)
        #expect(rows().map(\.2) == [true, true, true, true])

        let text = UITests.strings(in: WelcomePage(model: m).body)
        for s in ["Welcome to Expanse", "Your Mac, on an infinite canvas.", "Four quick steps",
                  "No hacks or SIP changes. Quit any time and every window goes back where it was."] {
            #expect(text.contains(s), "\(s)")
        }
        #expect(OnboardingView.size == CGSize(width: 960, height: 620))
        #expect(Self.button(page: 0, m) == "Get started")
    }

    @Test("SETUP-09 Screen Recording counts as done once asked for (it takes effect after a relaunch)") func setup09b() {
        let m = Self.model()
        #expect(!m.screenRecordingDone)
        m.screenRecordingRequested = true
        #expect(m.screenRecordingDone)
        m.screenRecordingRequested = false
        m.screenRecording = true
        #expect(m.screenRecordingDone)
    }

    @Test("SETUP-10 The hot corner step names the macOS corner in the way and ticks off once it's freed") func setup10() throws {
        let all = HotCorner.Corner.all.corners
        let quickNote = SystemShortcuts.hotCorners(in: all, value: Self.dock(["wvous-br-corner": 14, "wvous-br-modifier": 0]))
        #expect(quickNote == ["bottom‑right corner for Quick Note"])

        let m = Self.model()
        #expect(m.corner == .all)
        m.cornersInTheWay = quickNote
        let before = try Self.card(HotCornerPage(model: m).body)
        #expect(!before.done)
        #expect(before.problem == "macOS uses the bottom‑right corner for Quick Note")
        #expect(before.action == "Open Settings")
        #expect(Self.button(page: 3, m) == "Skip for now")
        #expect(UITests.strings(in: HotCornerPage(model: m).body).contains("Step 3 of 4"))
        #expect(UITests.strings(in: HotCornerPage(model: m).body).contains("Flick to a corner to see everything."))

        // Several corners: joined with "and the".
        m.cornersInTheWay = SystemShortcuts.hotCorners(in: all, value: Self.dock(["wvous-tl-corner": 2, "wvous-br-corner": 14]))
        #expect(try Self.card(HotCornerPage(model: m).body).problem
                == "macOS uses the top‑left corner for Mission Control and the bottom‑right corner for Quick Note")

        // Set to "–".
        m.cornersInTheWay = SystemShortcuts.hotCorners(in: all, value: Self.dock(["wvous-br-corner": 1, "wvous-br-modifier": 0]))
        let after = try Self.card(HotCornerPage(model: m).body)
        #expect(after.done)
        #expect(after.doneText == "Free for Expanse")
        #expect(Self.button(page: 3, m) == "Continue")
    }

    @Test("SETUP-11 A macOS hot corner that needs a modifier key doesn't count as in the way") func setup11() {
        let all = HotCorner.Corner.all.corners
        // ⌘ held for bottom-left Mission Control.
        #expect(SystemShortcuts.hotCorners(in: all, value: Self.dock(["wvous-bl-corner": 2, "wvous-bl-modifier": Self.command])).isEmpty)
        #expect(SystemShortcuts.hotCorners(in: all, value: Self.dock(["wvous-bl-corner": 2, "wvous-bl-modifier": 131072])).isEmpty)
        // "–" (0 or 1), or never set.
        #expect(SystemShortcuts.hotCorners(in: all, value: Self.dock(["wvous-bl-corner": 0, "wvous-bl-modifier": 0])).isEmpty)
        #expect(SystemShortcuts.hotCorners(in: all, value: Self.dock(["wvous-bl-corner": 1, "wvous-bl-modifier": 0])).isEmpty)
        #expect(SystemShortcuts.hotCorners(in: all, value: Self.dock([:])).isEmpty)
        // Without the modifier it is in the way.
        #expect(SystemShortcuts.hotCorners(in: all, value: Self.dock(["wvous-bl-corner": 2, "wvous-bl-modifier": 0]))
                == ["bottom‑left corner for Mission Control"])
    }

    @Test("SETUP-12 Picking Expanse's own corner on the hot corner step") func setup12() throws {
        try Env.withDefaults([HotCorner.defaultsKey: nil]) {
            let saved = Onboarding.hotCorner
            defer { Onboarding.hotCorner = saved }
            let hotCorner = HotCorner()
            Onboarding.hotCorner = hotCorner
            let m = SetupModel()
            #expect(m.corner == .all)

            // Bottom left: only that corner is checked, so a bottom-right Quick Note doesn't block.
            m.corner = .bottomLeft
            #expect(hotCorner.corner == .bottomLeft)
            #expect(UserDefaults.standard.string(forKey: HotCorner.defaultsKey) == "bottomLeft")
            #expect(m.corner.corners == [.bottomLeft])
            let quickNote = Self.dock(["wvous-br-corner": 14, "wvous-br-modifier": 0])
            #expect(SystemShortcuts.hotCorners(in: m.corner.corners, value: quickNote).isEmpty)
            #expect(SystemShortcuts.hotCorners(in: HotCorner.Corner.all.corners, value: quickNote).count == 1)
            #expect(HotCorner.Corner.all.corners == [.topLeft, .topRight, .bottomLeft, .bottomRight])

            // Off: nothing to check, and the card says so.
            m.corner = .off
            #expect(hotCorner.corner == .off)
            #expect(HotCorner.Corner.off.corners.isEmpty)
            #expect(m.cornersInTheWay.isEmpty && m.cornersDone)
            let card = try Self.card(HotCornerPage(model: m).body)
            #expect(card.done)
            #expect(card.doneText == "Expanse’s hot corner is off")

            // The last page.
            #expect(UITests.strings(in: ReadyPage(corner: .off).body)
                .contains("Press ⌥` to zoom out, then click any window to dive back in."))
        }
    }

    @Test("SETUP-13 The ⌃ + arrows step lists the macOS shortcuts still on") func setup13() throws {
        let fn = Self.control | Self.function
        let ids = ["33", "32", "79", "81"]
        let names = ["Application windows (⌃↓)", "Mission Control (⌃↑)", "Move left a space (⌃←)", "Move right a space (⌃→)"]
        let keys = ["33": Self.down, "32": Self.up, "79": Self.left, "81": Self.right]

        // Never changed: all four, sorted.
        #expect(Self.controlArrows([:]) == names)
        // On as macOS writes them: the same.
        #expect(Self.controlArrows(Dictionary(uniqueKeysWithValues: ids.map { ($0, Self.hotKey(true, key: keys[$0]!, modifiers: fn)) })) == names)

        // Switched off one at a time.
        var entries: [String: [String: Any]] = [:]
        for (i, id) in ["32", "33", "79", "81"].enumerated() {
            entries[id] = Self.hotKey(false, key: keys[id]!, modifiers: fn)
            let left = Self.controlArrows(entries)
            #expect(left.count == 3 - i)
            #expect(!left.contains(where: { $0.hasPrefix(["Mission Control", "Application windows", "Move left a space", "Move right a space"][i]) }))
        }
        #expect(Self.controlArrows(entries).isEmpty)

        // ⌃ with ⇧, ⌥ or ⌘ as well isn't listed; any other ⌃ + arrow on its own is.
        for extra in [Self.shift, Self.option, Self.command] {
            var e = entries
            e["200"] = Self.hotKey(true, key: Self.right, modifiers: Self.control | extra)
            #expect(Self.controlArrows(e).isEmpty)
        }
        var other = entries
        other["200"] = Self.hotKey(true, key: Self.right, modifiers: Self.control)
        #expect(Self.controlArrows(other) == ["A macOS shortcut (⌃→)"])
        other["200"] = Self.hotKey(false, key: Self.right, modifiers: Self.control)
        #expect(Self.controlArrows(other).isEmpty)
        // Not an arrow key.
        other["200"] = Self.hotKey(true, key: 49, modifiers: Self.control)
        #expect(Self.controlArrows(other).isEmpty)

        // The card.
        let m = Self.model()
        m.arrowsInTheWay = Self.controlArrows([:])
        let before = try Self.card(ArrowKeysPage(model: m).body)
        #expect(before.problem == "Still on: Application windows (⌃↓), Mission Control (⌃↑), Move left a space (⌃←), Move right a space (⌃→)")
        #expect(Self.button(page: 4, m) == "Skip for now")
        m.arrowsInTheWay = Self.controlArrows(entries)
        let after = try Self.card(ArrowKeysPage(model: m).body)
        #expect(after.done)
        #expect(after.doneText == "Free for Expanse")
        #expect(Self.button(page: 4, m) == "Continue")
    }

    @Test("SETUP-14 Footer buttons: Skip for now until a step is done, then Continue") func setup14() {
        let m = Self.model()
        #expect(Self.pages == 6)
        // Nothing done: the welcome and last pages have nothing to do.
        #expect((0..<Self.pages).map { OnboardingView.stepDone(page: $0, model: m) } == [true, false, false, false, false, true])
        #expect((0..<Self.pages).map { Self.button(page: $0, m) }
                == ["Get started", "Skip for now", "Skip for now", "Skip for now", "Skip for now", "Start using Expanse"])
        // Each step page follows its own step.
        m.accessibility = true
        #expect(OnboardingView.stepDone(page: 1, model: m) && Self.button(page: 1, m) == "Continue")
        #expect(!OnboardingView.stepDone(page: 2, model: m))
        m.screenRecordingRequested = true
        #expect(OnboardingView.stepDone(page: 2, model: m) && Self.button(page: 2, m) == "Continue")
        m.cornersInTheWay = []
        #expect(OnboardingView.stepDone(page: 3, model: m) && Self.button(page: 3, m) == "Continue")
        #expect(!OnboardingView.stepDone(page: 4, model: m))
        m.arrowsInTheWay = []
        #expect(OnboardingView.stepDone(page: 4, model: m) && Self.button(page: 4, m) == "Continue")
        #expect(Self.button(page: 0, m) == "Get started")
        #expect(Self.button(page: 5, m) == "Start using Expanse")
    }

    @Test("SETUP-15 The last page is a cheat sheet (logic)") func setup15() {
        let page = ReadyPage(corner: .all)
        #expect(page.rows.map(\.0) == [["⌥", "`"], ["Click"], ["⌃", "← → ↑ ↓"], ["⌃", "⌥", "C"], ["Pinch", "Scroll"],
                                       ["Space", "Drag"], ["Drag"], ["⇧", "Click"], ["T"]])
        #expect(page.rows[3].1 == "Centre the window you're in")
        let text = UITests.strings(in: page.body)
        for s in ["All set", "Try it now.", "Find this again under the menu bar icon › Welcome & Shortcuts."] {
            #expect(text.contains(s), "\(s)")
        }
        #expect(Self.button(page: Self.pages - 1, Self.model()) == "Start using Expanse")
    }

    @Test("SETUP-16 Expanse does nothing until the walkthrough is finished, skipped or closed: closing it finishes it, once")
    func setup16a() {
        var finished = 0
        Onboarding.window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled, .closable],
                                     backing: .buffered, defer: true)
        Onboarding.onFinish = { finished += 1 }
        Onboarding.closer.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(finished == 1)
        Onboarding.closer.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        #expect(finished == 1)
    }

    @Test("SETUP-16 Expanse does nothing until the walkthrough is finished: links wait, and it starts only once")
    func setup16b() {
        Env.isolate()
        let app = AppDelegate()
        let c = app.controller
        #expect(!app.isOn)
        // A link that only starts a camera animation (nothing moves until a frame is drawn) shows
        // whether it ran: zoom, as if zoomed out (at 100% it does nothing, URL-28).
        let zoom = URL(string: "expanse://zoom?scale=0.5")!
        c.isActive = true
        app.application(NSApplication.shared, open: [zoom])
        #expect(c.animation == nil)

        app.isOn = true
        app.application(NSApplication.shared, open: [zoom])
        #expect(c.animation != nil)
        c.cancelAnimation()
        c.isActive = false

        // Started already: a second turnOn does nothing (no second set of shortcuts).
        app.turnOn()
        #expect(app.hotKey == nil && app.centreHotKey == nil && app.centreWindowHotKey == nil && app.arrowHotKeys.isEmpty)
    }

    @Test("SETUP-16 Before the walkthrough is done, the panel's canvas actions are disabled") func setup16c() {
        for action in [MenuPanel.Action.toggleCanvas, .centreWindow, .tidy, .restoreAll, .takeSnapshot, .setPaused(true)] {
            #expect(action.needsCanvas)
        }
    }

    @Test("SETUP-17 macOS's Screen Recording prompt comes to the front (logic)") func setup17() throws {
        let m = Self.model()
        let before = try Self.card(ScreenRecordingPage(model: m).body)
        #expect(before.problem == "Off" && before.action == "Open Settings")
        // Asked: the card says to reopen, and the step counts as done.
        m.screenRecordingRequested = true
        let after = try Self.card(ScreenRecordingPage(model: m).body)
        #expect(after.problem == "Switched it on? Reopen Expanse to finish.")
        #expect(after.action == "Reopen Expanse")
        #expect(Self.button(page: 2, m) == "Continue")
    }

    @Test("SETUP-18 Finishing with Screen Recording pending relaunches, and Expanse starts then") func setup18() {
        let m = Self.model()
        Env.withDefaults([Onboarding.doneKey: nil, Onboarding.pageKey: 5]) {
            m.screenRecordingRequested = true
            m.screenRecording = false
            var calls: [String] = []
            OnboardingView.lastPage(m, finish: { calls.append("finish") }, relaunch: {
                calls.append("relaunch, done \(UserDefaults.standard.bool(forKey: Onboarding.doneKey))")
            })
            #expect(calls == ["relaunch, done true"])
            #expect(UserDefaults.standard.object(forKey: Onboarding.pageKey) == nil)
        }
        // Nothing pending: it just finishes.
        for (requested, granted) in [(false, false), (false, true), (true, true)] {
            Env.withDefaults([Onboarding.doneKey: nil, Onboarding.pageKey: 5]) {
                m.screenRecordingRequested = requested
                m.screenRecording = granted
                var calls: [String] = []
                OnboardingView.lastPage(m, finish: { calls.append("finish") }, relaunch: { calls.append("relaunch") })
                #expect(calls == ["finish"])
            }
        }
    }

    @Test("SETUP-20 macOS's Accessibility prompt comes to the front (logic)") func setup20() throws {
        let m = Self.model()
        let off = try Self.card(AccessibilityPage(model: m).body)
        #expect(!off.done && off.problem == "Off" && off.action == "Open Settings")
        m.accessibility = true
        let on = try Self.card(AccessibilityPage(model: m).body)
        #expect(on.done && on.doneText == "On")
    }

    @Test("SETUP-21 After reopening for Screen Recording, the walkthrough picks up where you were") func setup21a() {
        Env.withDefaults([Onboarding.doneKey: nil, Onboarding.pageKey: 2]) {
            #expect(Onboarding.startPage == 2)
            Onboarding.markDone()
            #expect(UserDefaults.standard.bool(forKey: Onboarding.doneKey))
            #expect(UserDefaults.standard.object(forKey: Onboarding.pageKey) == nil)
            #expect(Onboarding.startPage == 0)
        }
        // Finished: from page 1, whatever page was saved.
        Env.withDefaults([Onboarding.doneKey: true, Onboarding.pageKey: 3]) {
            #expect(Onboarding.startPage == 0)
        }
        Env.withDefaults([Onboarding.doneKey: nil, Onboarding.pageKey: nil]) {
            #expect(Onboarding.startPage == 0)
        }
    }

    @Test("SETUP-21 Moving through the walkthrough saves the page") func setup21b() {
        Env.withDefaults([Onboarding.pageKey: nil]) {
            OnboardingView(finish: {}).go(to: 2)
            #expect(UserDefaults.standard.integer(forKey: Onboarding.pageKey) == 2)
        }
    }

    @Test("SETUP-22 The walkthrough window is exactly the page's size (logic)") func setup22() {
        #expect(OnboardingView.size == CGSize(width: 960, height: 620))
    }

    @Test("SETUP-23 Opening the walkthrough while zoomed out leaves the canvas first") func setup23() async throws {
        Env.isolate()
        let app = AppDelegate()
        let c = app.controller
        var shown = 0
        Onboarding.showOverride = { _ in shown += 1 }
        defer { Onboarding.showOverride = nil }

        // Zoomed out: back to 100% first; the walkthrough waits for the canvas to be gone (UI-11).
        c.isActive = true
        app.showWelcome()
        #expect(c.animation?.handsBack == true)
        #expect(shown == 0)
        c.cancelAnimation()
        c.isActive = false
        // Mid-glide: the glide finishes on its own, then the walkthrough.
        c.gliding = true
        app.showWelcome()
        #expect(c.animation == nil)
        #expect(shown == 0)
        c.gliding = false
        try await Task.sleep(for: .milliseconds(150))
        #expect(shown == 1)
        // At 100%: straight away.
        app.showWelcome()
        #expect(c.animation == nil)
        #expect(shown == 2)
    }
}
