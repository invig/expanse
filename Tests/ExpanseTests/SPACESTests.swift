import Testing
import AppKit
import ScreenCaptureKit
import os
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "CanvasView.swift") @testable import Expanse
@_private(sourceFile: "SpacesBar.swift") @testable import Expanse
@_private(sourceFile: "SpaceSwipe.swift") @testable import Expanse
@_private(sourceFile: "Wallpaper.swift") @testable import Expanse

/// docs/regression/spaces-and-full-screen.md. The window server's Spaces are stood in for by
/// Spaces.displaysOverride, swipes are caught (SpaceSwipe.post) rather than posted, and nothing
/// switches Spaces, activates an app or moves a real window.
@MainActor @Suite("SPACES: Full-screen apps and Spaces", .serialized)
struct SPACESTests {

    // MARK: Helpers

    /// A desktop, as CGSCopyManagedDisplaySpaces lists it.
    private static func desktop(_ id: UInt64, managedKey: Bool = false) -> [String: Any] {
        [managedKey ? "ManagedSpaceID" : "id64": NSNumber(value: id), "type": NSNumber(value: 0)]
    }

    /// A full-screen app's Space: one tile per app (two for split view), each app with a pid and
    /// window of its own.
    private static func fullScreen(_ id: UInt64, pid: pid_t, window: CGWindowID, apps: [String],
                                   topLevel: Bool = true) -> [String: Any] {
        let tiles: [[String: Any]] = apps.enumerated().map { i, name in
            ["appName": name, "pid": NSNumber(value: pid + Int32(i)), "TileWindowID": NSNumber(value: window + UInt32(i))]
        }
        var s: [String: Any] = ["id64": NSNumber(value: id), "type": NSNumber(value: 4),
                                "TileLayoutManager": ["TileSpaces": tiles]]
        if topLevel {
            s["pid"] = NSNumber(value: pid)
            s["fs_wid"] = NSNumber(value: window)
        }
        return s
    }

    private static func display(_ spaces: [[String: Any]], current: UInt64, currentType: Int? = nil,
                                id: String = "Main") -> [String: Any] {
        var cur: [String: Any] = ["id64": NSNumber(value: current)]
        if let currentType { cur["type"] = NSNumber(value: currentType) }
        return ["Display Identifier": id, "Spaces": spaces, "Current Space": cur]
    }

    /// Desktop 1 (the canvas's), Safari full screen, Desktop 2; `current` is showing.
    private static func usual(current: UInt64) -> [[String: Any]] {
        [display([desktop(1), fullScreen(5, pid: 90_501, window: 77, apps: ["Safari"]), desktop(3)], current: current)]
    }

    /// Runs `body` with the window server's Spaces stood in for by `displays`.
    private static func withSpaces<T>(_ displays: [[String: Any]], _ body: () throws -> T) rethrows -> T {
        let old = Spaces.displaysOverride
        Spaces.displaysOverride = displays
        defer { Spaces.displaysOverride = old }
        return try body()
    }

    /// Runs `body` with swipes caught instead of posted; returns what it returned and the events.
    private static func catchingSwipes<T>(_ body: () throws -> T) rethrows -> (T, [CGEvent]) {
        let old = SpaceSwipe.post
        var posted: [CGEvent] = []
        SpaceSwipe.post = { posted.append($0) }
        defer { SpaceSwipe.post = old }
        let result = try body()
        return (result, posted)
    }

    /// Stops everything the test left scheduled, and pauses the canvas so anything queued does nothing.
    private static func finish(_ c: CanvasController) {
        c.relayoutWork.forEach { $0.cancel() }
        [c.saveWork, c.reassertWork, c.putBackWork, c.focusSettleWork, c.syncSoonWork, c.recheckWork,
         c.streamingWork, c.lingerWork].forEach { $0?.cancel() }
        c.cancelAnimation()
        c.snapshotTimer?.invalidate()
        c.isPaused = true
    }

    /// Window IDs no real window has (the window server's are far smaller), for anything that asks
    /// the window server about a canvas window's Space.
    private static let firstID: CGWindowID = 3_900_000_001

    // MARK: SPACES-01

    @Test("SPACES-01 Spaces.fullScreenWindows lists every full-screen window, on every display")
    func spaces01a() {
        let displays = [
            Self.display([Self.desktop(1), Self.fullScreen(5, pid: 90_501, window: 77, apps: ["Safari"]),
                          Self.fullScreen(6, pid: 90_502, window: 88, apps: ["Safari", "Notes"])], current: 1),
            Self.display([Self.desktop(7), Self.fullScreen(8, pid: 90_503, window: 99, apps: ["Mail"], topLevel: false)],
                         current: 7, id: "Other"),
        ]
        Self.withSpaces(displays) {
            #expect(Spaces.fullScreenWindows() == [77, 88, 89, 99])
        }
        Self.withSpaces([Self.display([Self.desktop(1), Self.desktop(2)], current: 1)]) {
            #expect(Spaces.fullScreenWindows().isEmpty)
        }
    }

    @Test("SPACES-01 On a full-screen app's Space no scan is applied: the canvas keeps its windows")
    func spaces01b() throws {
        try Self.withSpaces(Self.usual(current: 5)) {
            try #require(Spaces.inFullScreenSpace)
            let ws = (0..<3).map { Fake.window(id: Self.firstID + CGWindowID($0), canvas: CGRect(x: 700 * $0, y: 0, width: 600, height: 400)) }
            let c = TestCanvas.make(windows: ws)
            defer { Self.finish(c) }
            let before = c.windows.map(\.canvasFrame)
            var done = false
            c.sync { done = true }
            #expect(done)
            #expect(!c.syncing)
            #expect(c.syncToken == 0, "no scan started")
            #expect(c.windows.map(\.id) == ws.map(\.id))
            #expect(c.windows.map(\.canvasFrame) == before)
        }
    }

    // MARK: SPACES-02

    @Test("SPACES-02 Spaces.list reads desktops and full-screen apps in Mission Control's order")
    func spaces02a() {
        Self.withSpaces(Self.usual(current: 3)) {
            let (spaces, active) = Spaces.list()
            #expect(spaces.map(\.id) == [1, 5, 3])
            #expect(spaces.map(\.name) == ["Desktop 1", "Safari", "Desktop 2"])
            #expect(spaces.map(\.isDesktop) == [true, false, true])
            #expect(spaces[1].pid == 90_501 && spaces[1].window == 77)
            #expect(active == 3)
            #expect(Spaces.current?.name == "Desktop 2")
            #expect(Spaces.order().ids == [1, 5, 3] && Spaces.order().active == 3)
        }
    }

    @Test("SPACES-02 Split view is named for both apps; one desktop is just Desktop")
    func spaces02b() {
        let displays = [
            // Another display first: the main one is found by its identifier.
            Self.display([Self.desktop(40), Self.desktop(41)], current: 40, id: "Other"),
            Self.display([Self.desktop(1, managedKey: true),
                          Self.fullScreen(6, pid: 90_502, window: 88, apps: ["Safari", "Notes"]),
                          Self.fullScreen(8, pid: 90_503, window: 99, apps: ["Mail"], topLevel: false),
                          ["id64": NSNumber(value: 9), "type": NSNumber(value: 2)]],   // a kind Expanse doesn't show
                         current: 6),
        ]
        Self.withSpaces(displays) {
            let (spaces, active) = Spaces.list()
            #expect(spaces.map(\.name) == ["Desktop", "Safari & Notes", "Mail"])
            #expect(spaces.map(\.id) == [1, 6, 8])
            // Without the Space's own pid and window, the first tile's.
            #expect(spaces[2].pid == 90_503 && spaces[2].window == 99)
            #expect(active == 6)
        }
    }

    @Test("SPACES-02 The Spaces panel names each Space and rings the current one")
    func spaces02c() {
        let spaces = [Spaces.Space(id: 1, pid: nil, window: nil, name: "Expanse"),
                      Spaces.Space(id: 3, pid: nil, window: nil, name: "Desktop 2"),
                      Spaces.Space(id: 5, pid: 90_501, window: 77, name: "Safari")]
        let bar = SpacesBar()
        bar.update(spaces: spaces, active: 5, wallpaper: nil)
        #expect(!bar.isHidden)
        #expect(bar.labels.map { $0.string as? String } == ["Expanse", "Desktop 2", "Safari"])
        #expect(bar.rings.map(\.isHidden) == [true, true, false])
        #expect(bar.rings[2].borderWidth == 2.5)
        #expect(bar.labels[2].font as? NSFont == NSFont.systemFont(ofSize: 11, weight: .semibold))
        #expect(bar.labels[0].font as? NSFont == NSFont.systemFont(ofSize: 11, weight: .regular))
        // Hovering a tile gives it a quiet ring.
        bar.hovered = 1
        #expect(bar.rings.map(\.isHidden) == [true, false, false])
        #expect(bar.rings[1].borderWidth == 1.5)
    }

    // MARK: SPACES-03

    @Test("SPACES-03 No Spaces panel when there's only one Space")
    func spaces03() {
        let bar = SpacesBar()
        bar.update(spaces: [Spaces.Space(id: 1, pid: nil, window: nil, name: "Expanse")], active: 1, wallpaper: nil)
        #expect(bar.isHidden)
        #expect(bar.tile(at: CGPoint(x: 64, y: 60)) == nil)
        bar.update(spaces: [], active: nil, wallpaper: nil)
        #expect(bar.isHidden)
        bar.update(spaces: [Spaces.Space(id: 1, pid: nil, window: nil, name: "Expanse"),
                            Spaces.Space(id: 2, pid: nil, window: nil, name: "Desktop 2")], active: 1, wallpaper: nil)
        #expect(!bar.isHidden)
        #expect(bar.tile(at: CGPoint(x: 64, y: 60)) == 0)
    }

    // MARK: SPACES-04

    /// A window-list entry, as CGWindowListCopyWindowInfo gives it.
    private static func listed(_ id: CGWindowID, pid: pid_t, width: Double = 800, height: Double = 600) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: id), kCGWindowOwnerPID as String: NSNumber(value: pid),
         kCGWindowLayer as String: NSNumber(value: 0),
         kCGWindowBounds as String: ["X": 0.0, "Y": 0.0, "Width": width, "Height": height]]
    }

    @Test("SPACES-04 Spaces.someWindow returns nil for an empty Space")
    func spaces04() {
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.processIdentifier
        let pid = finder ?? 1
        let info = [Self.listed(10, pid: pid), Self.listed(11, pid: pid)]
        let spaceOf: [CGWindowID: [UInt64]] = [10: [1], 11: [5]]
        #expect(Spaces.someWindow(on: 3, info: info, spacesOf: { spaceOf[$0] ?? [] }) == nil)
        #expect(Spaces.someWindow(on: 3, info: [], spacesOf: { _ in [] }) == nil)
        // (Finder, an app in the Dock, has a window on Space 1.)
        if finder != nil {
            #expect(Spaces.someWindow(on: 1, info: info, spacesOf: { spaceOf[$0] ?? [] })?.id == 10)
        }
    }

    @Test("SPACES-08 Switching to another desktop picks its front-most window (logic)")
    func spaces08() throws {
        let finder = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
        let pid = finder.processIdentifier
        // Front to back: a small panel, then two windows on Desktop 2, one on Desktop 1.
        let info = [Self.listed(20, pid: pid, width: 80, height: 40), Self.listed(21, pid: pid),
                    Self.listed(22, pid: pid), Self.listed(23, pid: pid)]
        let spaceOf: [CGWindowID: [UInt64]] = [20: [3], 21: [1], 22: [3], 23: [3]]
        let found = Spaces.someWindow(on: 3, info: info, spacesOf: { spaceOf[$0] ?? [] })
        #expect(found?.id == 22)
        #expect(found?.pid == pid)
        // Not another app's that isn't in the Dock.
        let agent = [Self.listed(30, pid: Fake.firstPID)]
        #expect(Spaces.someWindow(on: 3, info: agent, spacesOf: { _ in [3] }) == nil)
    }

    // MARK: SPACES-10, SPACES-19

    private static let mainFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test("SPACES-10 With the pointer on another display, go(to:) returns false and posts nothing")
    func spaces10() {
        Self.withSpaces(Self.usual(current: 1)) {
            for pointer in [CGPoint(x: -1, y: 500), CGPoint(x: 1513, y: 500), CGPoint(x: 700, y: -1), CGPoint(x: 700, y: 983),
                            CGPoint(x: 2400, y: 700)] {
                let (went, posted) = Self.catchingSwipes { SpaceSwipe.go(to: 3, pointer: pointer, mainScreen: Self.mainFrame) }
                #expect(!went, "pointer at \(pointer)")
                #expect(posted.isEmpty)
            }
            // Nor for a Space that isn't on the main display, or with no display at all.
            let (other, posted) = Self.catchingSwipes {
                [SpaceSwipe.go(to: 40, pointer: CGPoint(x: 700, y: 500), mainScreen: Self.mainFrame),
                 SpaceSwipe.go(to: 3, pointer: CGPoint(x: 700, y: 500), mainScreen: nil)]
            }
            #expect(other == [false, false])
            #expect(posted.isEmpty)
        }
    }

    @Test("SPACES-19 go(to:) counts the pointer on the screen's edges as on the main display")
    func spaces19() {
        Self.withSpaces(Self.usual(current: 1)) {
            let f = Self.mainFrame
            // Already there: true as soon as the pointer counts as on the main display (nothing to post).
            for pointer in [CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.maxX, y: f.minY), CGPoint(x: f.minX, y: f.maxY),
                            CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.midX, y: f.maxY)] {
                let (went, posted) = Self.catchingSwipes { SpaceSwipe.go(to: 1, pointer: pointer, mainScreen: f) }
                #expect(went, "pointer at \(pointer)")
                #expect(posted.isEmpty)
            }
            // Resting in the top-right corner, a switch is made: two Spaces on, two swipes.
            let (went, posted) = Self.catchingSwipes { SpaceSwipe.go(to: 3, pointer: CGPoint(x: f.maxX, y: f.maxY), mainScreen: f) }
            #expect(went)
            #expect(posted.count == 2 * 3 * (SpaceSwipe.modern ? 2 : 1))
        }
    }

    // MARK: SPACES-11

    @Test("SPACES-11 The swipe's direction follows the Natural scrolling setting")
    func spaces11() throws {
        func sign(right: Bool, natural: Bool) throws -> (progress: Double, velocity: Double) {
            let events = try #require(SpaceSwipe.modernEvents(phase: SpaceSwipe.ended, right: right, natural: natural))
            #expect(events.count == 2)
            return (events[0].getDoubleValueField(SpaceSwipe.progressField), events[0].getDoubleValueField(SpaceSwipe.velocityX))
        }
        // Right is negative with Natural scrolling on, positive with it off; left the opposite.
        let rightNatural = try sign(right: true, natural: true)
        let rightPlain = try sign(right: true, natural: false)
        let leftNatural = try sign(right: false, natural: true)
        let leftPlain = try sign(right: false, natural: false)
        #expect(rightNatural.progress < 0 && rightNatural.velocity < 0)
        #expect(rightPlain.progress > 0 && rightPlain.velocity > 0)
        #expect(leftNatural.progress > 0 && leftNatural.velocity > 0)
        #expect(leftPlain.progress < 0 && leftPlain.velocity < 0)
    }

    // MARK: SPACES-15, SPACES-20

    @Test("SPACES-15 The canvas comes along to a desktop Space (logic)")
    func spaces15() {
        let c = TestCanvas.make()
        defer { Self.finish(c) }
        c.isActive = true
        Self.withSpaces(Self.usual(current: 1)) { #expect(c.canvasShouldFollowSpace) }
        Self.withSpaces(Self.usual(current: 3)) { #expect(c.canvasShouldFollowSpace) }
        // Not to a full-screen app's Space (the canvas is on its way out), nor at 100%.
        Self.withSpaces(Self.usual(current: 5)) { #expect(!c.canvasShouldFollowSpace) }
        c.isActive = false
        Self.withSpaces(Self.usual(current: 1)) { #expect(!c.canvasShouldFollowSpace) }
    }

    @Test("SPACES-20 canvasFollowsSpace doesn't bring the canvas back once leaving is under way")
    func spaces20() {
        let c = TestCanvas.make()
        defer { Self.finish(c) }
        c.isActive = true
        c.gliding = true
        Self.withSpaces(Self.usual(current: 1)) {
            #expect(!c.canvasShouldFollowSpace)
        }
    }

    // MARK: SPACES-25

    @Test("SPACES-25 At 100% the backdrop is shown again on a desktop Space (logic)")
    func spaces25() {
        let c = TestCanvas.make()
        defer { Self.finish(c) }
        Self.withSpaces(Self.usual(current: 1)) { #expect(c.backdropShouldFollowSpace) }
        Self.withSpaces(Self.usual(current: 3)) { #expect(c.backdropShouldFollowSpace) }
        // Not on a full-screen app's Space, where the app covers it; not with the canvas open or
        // gliding (it's in front then); not while paused (it's put away).
        Self.withSpaces(Self.usual(current: 5)) { #expect(!c.backdropShouldFollowSpace) }
        c.isActive = true
        Self.withSpaces(Self.usual(current: 1)) { #expect(!c.backdropShouldFollowSpace) }
        c.isActive = false
        c.isPaused = true
        Self.withSpaces(Self.usual(current: 1)) { #expect(!c.backdropShouldFollowSpace) }
        c.isPaused = false
    }

    // MARK: SPACES-16

    @Test("SPACES-16 Focus taken by another of the app's windows just after a pick is given back")
    func spaces16a() {
        let a = Fake.window(id: Self.firstID, appName: "TextEdit", canvas: CGRect(x: 4000, y: 0, width: 600, height: 400))
        let b = Fake.window(id: Self.firstID + 1, appName: "TextEdit", canvas: CGRect(x: 100, y: 100, width: 600, height: 400))
        let c = TestCanvas.make(windows: [a, b])
        defer { Self.finish(c) }
        c.lastFocusRequest = (a.id, a.pid, CACurrentMediaTime(), false)
        c.focusSettled(on: b.id)
        #expect(c.lastFocusRequest?.id == a.id)
        #expect(c.lastFocusRequest?.reasserted == true)
        #expect(c.focusedWindowByApp[a.pid] == a.id)
        #expect(!c.isActive && !c.gliding)
    }

    @Test("SPACES-16 Focus is given back only once, within a second, and only from the same app")
    func spaces16b() {
        Env.withDefaults(["autoCentre": false]) {
            let a = Fake.window(id: Self.firstID, appName: "TextEdit", canvas: CGRect(x: 4000, y: 0, width: 600, height: 400))
            // B, and another app's window, fully on screen: the view has no reason to move.
            let b = Fake.window(id: Self.firstID + 1, appName: "TextEdit", canvas: CGRect(x: 100, y: 100, width: 600, height: 400))
            let other = Fake.window(id: Self.firstID + 2, pid: Fake.firstPID + 1, bundleID: "com.example.other", appName: "Other",
                                    canvas: CGRect(x: 800, y: 100, width: 600, height: 400))
            let c = TestCanvas.make(windows: [a, b, other])
            defer { Self.finish(c) }
            let now = CACurrentMediaTime()
            // Already given back once: the app wins.
            c.lastFocusRequest = (a.id, a.pid, now, true)
            c.focusSettled(on: b.id)
            #expect(c.lastFocusRequest?.reasserted == true && c.lastFocusRequest?.at == now)
            #expect(c.focusedWindowByApp[a.pid] == nil)
            // More than a second after the pick.
            c.lastFocusRequest = (a.id, a.pid, now - 1.2, false)
            c.focusSettled(on: b.id)
            #expect(c.lastFocusRequest?.reasserted == false)
            #expect(c.focusedWindowByApp[a.pid] == nil)
            // Another app's window.
            c.lastFocusRequest = (a.id, a.pid, CACurrentMediaTime(), false)
            c.focusSettled(on: other.id)
            #expect(c.lastFocusRequest?.reasserted == false)
            #expect(c.focusedWindowByApp[a.pid] == nil)
            #expect(!c.isActive && !c.gliding)
        }
    }

    // MARK: SPACES-17, SPACES-24

    @Test("SPACES-17 At 100%, the tile of the Space you're on does nothing")
    func spaces17a() {
        Self.withSpaces(Self.usual(current: 1)) {
            let c = TestCanvas.make()
            defer { Self.finish(c) }
            let camera = c.camera
            c.switchToSpace(Spaces.Space(id: 1, pid: nil, window: nil, name: "Expanse"))
            #expect(!c.isActive)
            #expect(c.animation == nil)
            #expect(c.camera == camera)
            #expect(c.lastFocusRequest == nil && c.activationRequest == nil)
        }
    }

    @Test("SPACES-17 Zoomed out, the current Space's tile just leaves the canvas")
    func spaces17b() {
        // On the canvas's desktop, and over a full-screen app (back to it).
        for current: UInt64 in [1, 5] {
            Self.withSpaces(Self.usual(current: current)) {
                let c = TestCanvas.make()
                defer { Self.finish(c) }
                c.isActive = true
                c.camera = Camera(origin: CGPoint(x: -500, y: -300), scale: 0.4)
                let space = Spaces.list().spaces.first { $0.id == current }!
                let (_, posted) = Self.catchingSwipes { c.switchToSpace(space) }
                #expect(posted.isEmpty, "no switch")
                let a = c.animation
                #expect(a?.handsBack == true, "leaving the canvas, on Space \(current)")
                #expect(a?.to.scale == 1)
            }
        }
    }

    @Test("SPACES-24 Clicking Expanse's own Space tile goes back to 100%, to the view you left (logic)")
    func spaces24() {
        Self.withSpaces(Self.usual(current: 1)) {
            let c = TestCanvas.make()
            defer { Self.finish(c) }
            let left = Camera(origin: CGPoint(x: 300, y: 200), scale: 1)
            c.isActive = true
            c.returnCamera = left
            c.camera = Camera(origin: CGPoint(x: -500, y: -300), scale: 0.4)
            let (_, posted) = Self.catchingSwipes { c.switchToSpace(Spaces.Space(id: 1, pid: nil, window: nil, name: "Expanse")) }
            #expect(posted.isEmpty)
            #expect(c.animation?.to == left)
            #expect(c.animation?.handsBack == true)
            // Leaving it is still pending (the zoom back in); nothing else happened.
            #expect(c.lastFocusRequest == nil)
        }
    }

    // MARK: SPACES-18

    @Test("SPACES-18 Spaces.inFullScreenSpace reads the current Space's kind")
    func spaces18a() {
        Self.withSpaces(Self.usual(current: 5)) { #expect(Spaces.inFullScreenSpace) }
        Self.withSpaces(Self.usual(current: 3)) { #expect(!Spaces.inFullScreenSpace) }
        // The current Space's own kind, when the window server gives it.
        Self.withSpaces([Self.display([Self.desktop(1)], current: 1, currentType: 4)]) { #expect(Spaces.inFullScreenSpace) }
        Self.withSpaces([Self.display([Self.desktop(1), Self.fullScreen(5, pid: 90_501, window: 77, apps: ["Safari"])],
                                      current: 5, currentType: 0)]) { #expect(!Spaces.inFullScreenSpace) }
    }

    @Test("SPACES-18 No window scans while a full-screen app's Space is showing")
    func spaces18b() throws {
        try Self.withSpaces(Self.usual(current: 5)) {
            try #require(Spaces.inFullScreenSpace)
            let c = TestCanvas.make()
            defer { Self.finish(c) }
            var done = 0
            c.sync { done += 1 }
            c.sync { done += 1 }
            #expect(done == 2, "whoever waits gets an answer straight away")
            #expect(!c.syncing)
            #expect(c.syncToken == 0, "no scan started")
            #expect(!c.hasSynced)
            // Only the Spaces panel is brought up to date (once Screen Recording is allowed, which
            // sync checks first).
            if CGPreflightScreenCaptureAccess() {
                #expect(c.view.spacesBar.spaces.map(\.id) == [1, 5, 3])
                #expect(c.view.spacesBar.active == 5)
            }
        }
    }

    // MARK: SPACES-21

    @Test("SPACES-21 Moves while a full-screen window comes or goes are noted to be put back")
    func spaces21a() {
        let w = Fake.window(id: Self.firstID, appName: "Brave Browser", canvas: CGRect(x: 3000, y: 0, width: 800, height: 600))
        let c = TestCanvas.make(windows: [w])
        defer { Self.finish(c) }
        // Long after any full-screen change, on a desktop: not ours to put back.
        #expect(!c.movedByFullScreen(w, inFullScreenSpace: false))
        #expect(c.putBackWork == nil)
        // On a full-screen app's Space it is.
        #expect(c.movedByFullScreen(w, inFullScreenSpace: true))
        c.movedAroundFullScreen = []
        // And for 1.5s after a full-screen window comes or goes.
        c.fullScreenChanging()
        #expect(abs(c.fullScreenSettleUntil - CACurrentMediaTime() - 1.5) < 0.1)
        #expect(c.movedByFullScreen(w, inFullScreenSpace: false))
        #expect(c.movedAroundFullScreen == [w.id])
        #expect(c.putBackWork != nil)
        c.fullScreenSettleUntil = CACurrentMediaTime() - 0.01
        c.movedAroundFullScreen = []
        #expect(!c.movedByFullScreen(w, inFullScreenSpace: false))
    }

    @Test("SPACES-21 Half a second after the moves stop, they're put back where the canvas has them")
    func spaces21b() throws {
        let ws = [Fake.window(id: Self.firstID, appName: "Brave Browser", canvas: CGRect(x: 3000, y: 0, width: 800, height: 600)),
                  Fake.window(id: Self.firstID + 1, appName: "Brave Browser", canvas: CGRect(x: 100, y: 100, width: 800, height: 600)),
                  Fake.window(id: Self.firstID + 2, appName: "Notes", canvas: CGRect(x: 1000, y: 100, width: 400, height: 300))]
        let c = TestCanvas.make(windows: ws)
        defer { Self.finish(c) }
        for w in ws { w.lastPlaced = CGPoint(x: w.canvasFrame.minX, y: w.canvasFrame.minY + c.viewport.minY) }
        let canvas = ws.map(\.canvasFrame)
        c.fullScreenChanging()
        // The browser fits its windows onto the screen, in a burst.
        #expect(c.movedByFullScreen(ws[0], inFullScreenSpace: false))
        let first = try #require(c.putBackWork)
        #expect(c.movedByFullScreen(ws[1], inFullScreenSpace: false))
        let last = try #require(c.putBackWork)
        #expect(first.isCancelled && !last.isCancelled, "timed from the last move")
        // Zoomed out, so the put-back itself moves nothing; the next commit does.
        c.isActive = true
        last.perform()
        #expect(c.movedAroundFullScreen.isEmpty)
        #expect(ws[0].lastPlaced == nil && ws[1].lastPlaced == nil)
        #expect(ws[2].lastPlaced != nil, "a window that didn't move is left alone")
        #expect(ws.map(\.canvasFrame) == canvas, "not followed")
    }

    // MARK: SPACES-23

    @Test("SPACES-23 A window macOS shoved just before a full-screen window came back is put back (logic)")
    func spaces23b() {
        let a = Fake.window(id: Self.firstID, appName: "Notes", canvas: CGRect(x: 100, y: 100, width: 600, height: 400))
        let left = Fake.window(id: Self.firstID + 1, appName: "Notes", canvas: CGRect(x: -120, y: 300, width: 600, height: 400))
        let c = TestCanvas.make(windows: [a, left])
        defer { Self.finish(c) }
        left.lastPlaced = CGPoint(x: -120, y: 300 + c.viewport.minY)
        left.home = CGPoint(x: -120, y: 300)
        // Leaving full screen, macOS moves Left (half off the screen) onto it, before A says it's back.
        c.realWindowChanged(left, AXUIElementCreateApplication(left.pid), userDragging: false,
                            size: left.canvasFrame.size, position: CGPoint(x: 100, y: 92), inFullScreenSpace: false)
        #expect(left.canvasFrame.origin != CGPoint(x: -120, y: 300), "followed, for now")
        // A says it's back: Left goes back to its spot, home and all, to be put back.
        c.fullScreenChanging(a)
        #expect(left.canvasFrame.origin == CGPoint(x: -120, y: 300))
        #expect(left.home == CGPoint(x: -120, y: 300))
        #expect(c.movedAroundFullScreen == [left.id])
        // A move you made (a drag) isn't undone.
        c.putBackWork?.cancel()
        c.movedAroundFullScreen = []
        left.lastDraggedAt = CACurrentMediaTime()
        c.realWindowChanged(left, AXUIElementCreateApplication(left.pid), userDragging: true,
                            size: left.canvasFrame.size, position: CGPoint(x: 300, y: 200), inFullScreenSpace: false)
        let dragged = left.canvasFrame.origin
        c.fullScreenChanging(a)
        #expect(left.canvasFrame.origin == dragged)
        #expect(c.movedAroundFullScreen.isEmpty)
    }

    @Test("SPACES-23 A window a scan finds moved, seconds after full screen, is put back, not followed (logic)")
    func spaces23c() {
        let left = Fake.window(id: Self.firstID, appName: "Notes", canvas: CGRect(x: -120, y: 300, width: 600, height: 400))
        let c = TestCanvas.make(windows: [left])
        defer { Self.finish(c) }
        c.firstSync = false
        left.lastPlaced = CGPoint(x: -120, y: 300 + c.viewport.minY)   // hanging off the left edge
        let whole = CGRect(x: 100, y: 92, width: 600, height: 400)       // where macOS set it down
        // A full-screen window came back 8 s ago (past the 1.5 s for moves it reports).
        c.fullScreenChanging()
        c.fullScreenSettleUntil = 0
        c.lastFullScreenChange -= 8
        c.apply([Fake.scWindow(id: left.id, appName: "Notes", frame: whole)], ax: CanvasController.AXSnapshot())
        #expect(left.canvasFrame.origin == CGPoint(x: -120, y: 300), "not followed")
        #expect(c.movedAroundFullScreen == [left.id], "to be put back")
        // So is one that was whole on screen (the window back from full screen, set down where
        // it was before Expanse moved it).
        c.putBackWork?.cancel()
        c.movedAroundFullScreen = []
        left.lastPlaced = CGPoint(x: 500, y: 301)
        c.apply([Fake.scWindow(id: left.id, appName: "Notes", frame: CGRect(x: 130, y: 122, width: 600, height: 400))],
                ax: CanvasController.AXSnapshot())
        #expect(left.canvasFrame.origin == CGPoint(x: -120, y: 300))
        #expect(c.movedAroundFullScreen == [left.id])
        // Long after, the same find is a move to follow.
        left.lastPlaced = CGPoint(x: -120, y: 300 + c.viewport.minY)
        c.putBackWork?.cancel()
        c.movedAroundFullScreen = []
        c.lastFullScreenChange -= 60
        c.apply([Fake.scWindow(id: left.id, appName: "Notes", frame: whole)], ax: CanvasController.AXSnapshot())
        #expect(left.canvasFrame.origin == c.canvasPoint(forGlobal: whole.origin))
    }

    @Test("SPACES-23 A scan just after full screen doesn't take where macOS set a window down (logic)")
    func spaces23() {
        let w = Fake.window(id: Self.firstID, appName: "Calendar", canvas: CGRect(x: 100, y: 100, width: 800, height: 600))
        let c = TestCanvas.make(windows: [w])
        defer { Self.finish(c) }
        c.firstSync = false
        let setDown = CGRect(x: 400, y: 300, width: 800, height: 600)   // where macOS put it
        let scan = [Fake.scWindow(id: w.id, appName: "Calendar", frame: setDown)]
        // Just back from full screen (not placed since).
        w.lastPlaced = nil
        c.fullScreenChanging()
        c.apply(scan, ax: CanvasController.AXSnapshot())
        #expect(w.canvasFrame.origin == CGPoint(x: 100, y: 100))
        #expect(c.movedAroundFullScreen == [w.id])
        // Long after, a window found elsewhere was moved by you or its app: followed.
        c.putBackWork?.cancel()
        c.movedAroundFullScreen = []
        c.fullScreenSettleUntil = 0
        c.apply(scan, ax: CanvasController.AXSnapshot())
        #expect(w.canvasFrame.origin == c.canvasPoint(forGlobal: setDown.origin))
    }

    // MARK: SPACES-26

    @Test("SPACES-26 The Expanse tile is the desktop's, with a window of the canvas full screen")
    func spaces26() {
        let spaces: [CGWindowID: [UInt64]] = [1: [3], 2: [3], 9: [41]]   // 9 full screen, on Space 41
        let of = { (id: CGWindowID) in spaces[id] ?? [] }
        // Window 9, front-most, went full screen: the canvas is still on desktop 3.
        #expect(CanvasController.canvasDesktop(front: [1, 2, 9], desktops: [3, 5], spacesOf: of) == 3)
        #expect(CanvasController.canvasDesktop(front: [9, 1, 2], desktops: [3, 5], spacesOf: of) == 3)
        // Nothing on a desktop (every window full screen, or none): no tile to point at.
        #expect(CanvasController.canvasDesktop(front: [9], desktops: [3, 5], spacesOf: of) == nil)
        #expect(CanvasController.canvasDesktop(front: [], desktops: [3, 5], spacesOf: of) == nil)
    }

    // MARK: SPACES-27 and SPACES-28

    private static func picture() -> CGImage {
        CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    /// A canvas with the desktop picture on, and a picture already on it.
    private static func pictureCanvas(_ first: CGImage) -> CanvasController {
        let c = TestCanvas.make()
        c.view.setWallpaper(first)
        return c
    }

    @Test("SPACES-27 Over a full-screen app the canvas keeps its desktop picture and asks for no other")
    func spaces27a() {
        Env.withDefaults([Wallpaper.defaultsKey: nil]) {
            Self.withSpaces(Self.usual(current: 5)) {
                let first = Self.picture()
                let c = Self.pictureCanvas(first)
                defer { Self.finish(c) }
                var asked = 0
                c.takeDesktopPicture = { _, _ in asked += 1 }
                c.takeWallpaper(request: c.wallpaperRequest, tries: 1)
                #expect(asked == 0, "what's on that Space is macOS's black backdrop, not the desktop")
                #expect(c.view.desktopPicture === first)

                // With none to keep (Expanse opened on that Space), the picture's file, still not a capture.
                c.view.setWallpaper(nil)
                c.takeWallpaper(request: c.wallpaperRequest, tries: 1)
                #expect(asked == 0)
                #expect(c.view.hasWallpaper == (Wallpaper.fromFile(screen: c.screen) != nil))
            }
        }
    }

    @Test("SPACES-27 A picture that lands after moving to a full-screen app's Space is dropped")
    func spaces27b() {
        Env.withDefaults([Wallpaper.defaultsKey: nil]) {
            Self.withSpaces(Self.usual(current: 1)) {
                let first = Self.picture()
                let c = Self.pictureCanvas(first)
                defer { Self.finish(c) }
                var answer: ((Wallpaper.Result) -> Void)?
                c.takeDesktopPicture = { _, done in answer = done }
                c.takeWallpaper(request: c.wallpaperRequest, tries: 1)
                Self.withSpaces(Self.usual(current: 5)) { answer?(.picture(Self.picture())) }
                #expect(c.view.desktopPicture === first)
            }
        }
    }

    @Test("SPACES-27 The strip goes over the app's top edge only with the canvas up on its Space")
    func spaces27c() {
        let c = TestCanvas.make()
        defer { Self.finish(c) }
        Self.withSpaces(Self.usual(current: 5)) {
            #expect(c.menuBarStripFrame == nil, "at 100% the app has the screen")
            c.isActive = true
            let display = TestDisplay.laptop
            #expect(c.menuBarStripFrame == NSRect(x: display.frame.minX, y: display.frame.maxY - display.menuBar,
                                                  width: display.frame.width, height: display.menuBar))
            #expect(c.menuBarStrip == nil, "the tests put no windows on the screen")
        }
        Self.withSpaces(Self.usual(current: 1)) {
            #expect(c.menuBarStripFrame == nil, "macOS's menu bar is there on a desktop")
        }
        Self.withSpaces(Self.usual(current: 5)) {
            // A display with no menu bar in the way has no gap to cover.
            c.displayOverride = (TestDisplay.laptop.frame, TestDisplay.laptop.frame)
            #expect(c.menuBarStripFrame == nil)
            c.isActive = false
        }
    }

    @Test("SPACES-27 The strip takes clicks, not the keyboard, and shows the canvas's desktop")
    func spaces27d() {
        let strip = MenuBarStrip()
        #expect(strip.level == OverlayWindow.canvasLevel)
        #expect(!strip.ignoresMouseEvents, "a click there mustn't reach the app under it")
        #expect(!strip.canBecomeKey, "the canvas keeps the keyboard")
        #expect(strip.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(strip.collectionBehavior.contains(.canJoinAllSpaces))
        let image = Self.picture()
        strip.update(frame: NSRect(x: 0, y: 870, width: 1440, height: 30), screenHeight: 900, image: image,
                     background: NSColor.gray.cgColor)
        #expect(strip.picture.contents as! CGImage === image)
        // As the canvas draws it, its top along the screen's top: the strip shows that part.
        #expect(strip.picture.frame == CGRect(x: 0, y: -870, width: 1440, height: 900))
        #expect(strip.isVisible == false)
        // macOS would otherwise move it down below the menu bar, behind the canvas.
        let top = NSRect(x: 0, y: 870, width: 1440, height: 30)
        #expect(strip.constrainFrameRect(top, to: NSScreen.main) == top)
    }

    private static let wallpaperLevels = (-2147483625)...(-2147483623)

    private static func desktop(x: CGFloat, y: CGFloat = 0, width: CGFloat = 2048, height: CGFloat = 1152, layer: Int,
                                _ title: String? = nil) -> Wallpaper.DesktopWindow {
        Wallpaper.DesktopWindow(frame: CGRect(x: x, y: y, width: width, height: height), layer: layer, title: title)
    }

    @Test("SPACES-28 Only a desktop at rest is a desktop to take a picture of")
    func spaces28a() {
        let screen = CGRect(x: 0, y: 0, width: 2048, height: 1152)
        func state(_ windows: [Wallpaper.DesktopWindow], display: CGRect = screen) -> Wallpaper.DesktopState {
            Wallpaper.desktopState(windows, display: display, levels: Self.wallpaperLevels)
        }
        // These frames are what a Mac reported on 6 Nov (2048 × 1152), Finder's and the wallpaper's.
        let backstop = Self.desktop(x: 0, layer: -2147483626, "Display 3 Backstop")
        func scene(at x: CGFloat) -> [Wallpaper.DesktopWindow] {
            [backstop,
             Self.desktop(x: x, layer: -2147483624, "Wallpaper"),
             Self.desktop(x: x, layer: -2147483603),
             Self.desktop(x: x, height: 97, layer: -2147483602, "underbelly")]
        }
        #expect(state(scene(at: 0)) == .atRest)
        // Sliding off to a full-screen app's Space, with its backdrop coming in.
        #expect(state(scene(at: -554) + [Self.desktop(x: 1558, layer: -2147483622, "Fullscreen Backdrop")]) == .moving)
        #expect(state(scene(at: -2034) + [Self.desktop(x: 78, layer: -2147483622, "Fullscreen Backdrop")]) == .moving)
        // Just a little way off.
        #expect(state(scene(at: 1)) == .moving)
        // Arrived there: black, in place.
        #expect(state([backstop, Self.desktop(x: 0, layer: -2147483624, "Wallpaper"),
                       Self.desktop(x: 0, layer: -2147483622, "Fullscreen Backdrop")]) == .moving)
        // Off this display altogether, for a moment.
        #expect(state([Self.desktop(x: -2048, layer: -2147483624, "Wallpaper")]) == .moving)

        // A window that isn't as wide as the screen (a widget, say) doesn't say anything.
        #expect(state(scene(at: 0) + [Self.desktop(x: 300, y: 300, width: 200, height: 200, layer: -2147483603)]) == .atRest)
        // No wallpaper window (an older macOS): the picture's file, as before.
        #expect(state([backstop]) == .absent)
        #expect(state([Self.desktop(x: 0, width: 1920, height: 1080, layer: -2147483624, "Wallpaper")]) == .absent)

        // Another display the same size has a wallpaper of its own, and can show a full-screen app.
        let other: [Wallpaper.DesktopWindow] = [Self.desktop(x: 2048, layer: -2147483624, "Wallpaper"),
                                                Self.desktop(x: 2048, layer: -2147483622, "Fullscreen Backdrop")]
        #expect(state(scene(at: 0) + other) == .atRest)
        // On a display that isn't at the origin.
        #expect(state(scene(at: 2048), display: screen.offsetBy(dx: 2048, dy: 0)) == .atRest)
    }

    @Test("SPACES-28 A desktop still moving is asked again, and a picture of it comes through")
    func spaces28b() async throws {
        let displays = Self.usual(current: 1)
        let old = Spaces.displaysOverride
        Spaces.displaysOverride = displays
        defer { Spaces.displaysOverride = old }
        let first = Self.picture(), second = Self.picture()
        let c = Self.pictureCanvas(first)
        defer { Self.finish(c) }
        var asked = 0
        c.takeDesktopPicture = { _, done in
            asked += 1
            done(asked == 1 ? .notSettled : .picture(second))
        }
        c.takeWallpaper(request: c.wallpaperRequest, tries: 3)
        #expect(asked == 1)
        #expect(c.view.desktopPicture === first, "the last one stays till then")
        try await Task.sleep(for: .seconds(CanvasController.wallpaperRetryDelay + 0.15))
        #expect(asked == 2)
        #expect(c.view.desktopPicture === second)
    }

    @Test("SPACES-28 A desktop that never settles keeps the last picture, and stops asking")
    func spaces28c() async throws {
        let old = Spaces.displaysOverride
        Spaces.displaysOverride = Self.usual(current: 1)
        defer { Spaces.displaysOverride = old }
        let first = Self.picture()
        let c = Self.pictureCanvas(first)
        defer { Self.finish(c) }
        var asked = 0
        c.takeDesktopPicture = { _, done in asked += 1; done(.notSettled) }
        c.takeWallpaper(request: c.wallpaperRequest, tries: 2)
        try await Task.sleep(for: .seconds(CanvasController.wallpaperRetryDelay * 3))
        #expect(asked == 2)
        #expect(c.view.desktopPicture === first)
    }

    @Test("SPACES-28 Just after the Space changes, the picture waits for the slide to finish")
    func spaces28d() async throws {
        let old = Spaces.displaysOverride
        Spaces.displaysOverride = Self.usual(current: 1)
        defer { Spaces.displaysOverride = old }
        let c = Self.pictureCanvas(Self.picture())
        defer { Self.finish(c) }
        var asked = 0
        c.takeDesktopPicture = { _, _ in asked += 1 }
        c.spaceChangedAt = CACurrentMediaTime()
        c.takeWallpaper(request: c.wallpaperRequest, tries: 1)
        #expect(asked == 0)
        try await Task.sleep(for: .seconds(CanvasController.spaceSettleTime + 0.2))
        #expect(asked == 1)
    }

    @Test("SPACES-28 A newer ask replaces an older one, its answer and its next try")
    func spaces28e() async throws {
        let old = Spaces.displaysOverride
        Spaces.displaysOverride = Self.usual(current: 1)
        defer { Spaces.displaysOverride = old }
        let first = Self.picture()
        let c = Self.pictureCanvas(first)
        defer { Self.finish(c) }
        var asked = 0
        var answers: [(Wallpaper.Result) -> Void] = []
        c.takeDesktopPicture = { _, done in asked += 1; answers.append(done) }
        c.wallpaperRequest = 1
        c.takeWallpaper(request: 1, tries: 3)
        c.wallpaperRequest = 2
        answers[0](.picture(Self.picture()))
        #expect(c.view.desktopPicture === first)
        answers[0](.notSettled)
        try await Task.sleep(for: .seconds(CanvasController.wallpaperRetryDelay + 0.15))
        #expect(asked == 1, "no second try for the old ask")
        // And a try already on its way stops by itself.
        c.takeWallpaper(request: 1, tries: 3)
        #expect(asked == 1)
    }

    // MARK: SPACES-29

    /// A picture of one colour.
    private static func solid(_ color: CGColor, width: Int = 4, height: Int = 4) -> CGImage {
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(color)
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return c.makeImage()!
    }

    private static let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private static let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

    /// The red and blue of the pixel at `x`, half way up.
    private static func redBlue(_ image: CGImage, x: Int) -> (red: UInt8, blue: UInt8) {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let c = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let at = (image.height / 2 * image.width + x) * 4
        return (pixels[at], pixels[at + 2])
    }

    @Test("SPACES-29 Spaces.list gives each full-screen Space's windows: both in split view")
    func spaces29a() {
        let onlyItsOwn: [String: Any] = ["id64": NSNumber(value: 9), "type": NSNumber(value: 4),
                                         "pid": NSNumber(value: 90_504), "fs_wid": NSNumber(value: 111)]
        let displays = [Self.display([Self.desktop(1),
                                      Self.fullScreen(5, pid: 90_501, window: 77, apps: ["Safari"]),
                                      Self.fullScreen(6, pid: 90_502, window: 88, apps: ["Safari", "Notes"]),
                                      Self.fullScreen(8, pid: 90_503, window: 99, apps: ["Mail"], topLevel: false),
                                      onlyItsOwn], current: 1)]
        Self.withSpaces(displays) {
            #expect(Spaces.list().spaces.map(\.windows) == [[], [77], [88, 89], [99], [111]])
        }
    }

    @Test("SPACES-29 A tile's picture is the size that fills it, with each window where it sits")
    func spaces29b() {
        let tile = CGSize(width: 100, height: 63)
        // Wider than the tile: it's the height that has to fill it.
        let one = SpacePicture.layout([CGRect(x: 0, y: 0, width: 2048, height: 1152)], tile: tile, scale: 2)
        #expect(one.size == CGSize(width: 224, height: 126))
        #expect(one.rects == [CGRect(x: 0, y: 0, width: 224, height: 126)])
        // Taller than the tile: the width.
        let tall = SpacePicture.layout([CGRect(x: 0, y: 0, width: 1000, height: 1000)], tile: tile, scale: 1)
        #expect(tall.size == CGSize(width: 100, height: 100))
        // Split view, side by side.
        let split = SpacePicture.layout([CGRect(x: 0, y: 0, width: 1024, height: 1152),
                                         CGRect(x: 1024, y: 0, width: 1024, height: 1152)], tile: tile, scale: 2)
        #expect(split.size == CGSize(width: 224, height: 126))
        #expect(split.rects == [CGRect(x: 0, y: 0, width: 112, height: 126), CGRect(x: 112, y: 0, width: 112, height: 126)])
        // One over the other: the upper window's at the top of the picture, whose origin is at the bottom.
        let stacked = SpacePicture.layout([CGRect(x: 0, y: 0, width: 1000, height: 500),
                                           CGRect(x: 0, y: 500, width: 1000, height: 500)], tile: tile, scale: 1)
        #expect(stacked.rects == [CGRect(x: 0, y: 50, width: 100, height: 50), CGRect(x: 0, y: 0, width: 100, height: 50)])
        // Part way through a Space's slide the frames are off the screen: it's the windows that count.
        let moving = SpacePicture.layout([CGRect(x: -554, y: 0, width: 2048, height: 1152)], tile: tile, scale: 2)
        #expect(moving.rects == one.rects)
        // Nothing to draw.
        #expect(SpacePicture.layout([], tile: tile, scale: 2).rects.isEmpty)
        #expect(SpacePicture.layout([CGRect(x: 0, y: 0, width: 0, height: 0)], tile: tile, scale: 2).rects.isEmpty)
    }

    @Test("SPACES-29 A picture of the right size is used as it is; others are drawn to it, split view's two together")
    func spaces29c() throws {
        let red = Self.solid(Self.red), blue = Self.solid(Self.blue)
        #expect(SpacePicture.compose([], size: .zero) == nil)
        #expect(SpacePicture.compose([(red, CGRect(x: 0, y: 0, width: 4, height: 4))], size: CGSize(width: 4, height: 4)) === red)
        let both = try #require(SpacePicture.compose([(red, CGRect(x: 0, y: 0, width: 4, height: 4)),
                                                      (blue, CGRect(x: 4, y: 0, width: 4, height: 4))],
                                                     size: CGSize(width: 8, height: 4)))
        #expect(both.width == 8 && both.height == 4)
        let left = Self.redBlue(both, x: 1), right = Self.redBlue(both, x: 6)
        #expect(left.red > 200 && left.blue < 50, "\(left)")
        #expect(right.blue > 200 && right.red < 50, "\(right)")
        // The window server's come at the window's full size.
        let full = Self.solid(Self.red, width: 1600, height: 1000)
        let small = try #require(SpacePicture.compose([(full, CGRect(x: 0, y: 0, width: 202, height: 126))], size: CGSize(width: 201.6, height: 126)))
        #expect(small.width == 202 && small.height == 126)
        #expect(Self.redBlue(small, x: 100).red > 200)
    }

    @Test("SPACES-29 A full-screen app's tile shows its picture, and its icon before there is one")
    func spaces29d() {
        let own = ProcessInfo.processInfo.processIdentifier
        let spaces = [Spaces.Space(id: 1, pid: nil, window: nil, name: "Expanse"),
                      Spaces.Space(id: 5, pid: own, window: 77, name: "Safari", windows: [77])]
        let wallpaper = Self.picture(), first = Self.picture(), second = Self.picture()
        let bar = SpacesBar()
        bar.update(spaces: spaces, active: 1, wallpaper: wallpaper)
        #expect(bar.tiles[1].contents == nil, "no picture to show yet")
        if NSRunningApplication(processIdentifier: own)?.icon != nil {
            #expect(bar.tiles[1].sublayers?.count == 1, "the app's icon")
        }

        bar.update(spaces: spaces, active: 1, wallpaper: wallpaper, pictures: [5: first])
        #expect(bar.tiles[1].contents as! CGImage === first)
        #expect(bar.tiles[1].contentsGravity == .resizeAspectFill)
        #expect(bar.tiles[1].sublayers == nil, "the picture instead of the icon")
        #expect(bar.tiles[0].contents as! CGImage === wallpaper, "a desktop's tile is still its picture")

        // The same picture rebuilds nothing; a new one is shown.
        let tile = bar.tiles[1]
        bar.update(spaces: spaces, active: 1, wallpaper: wallpaper, pictures: [5: first])
        #expect(bar.tiles[1] === tile)
        bar.update(spaces: spaces, active: 1, wallpaper: wallpaper, pictures: [5: second])
        #expect(bar.tiles[1].contents as! CGImage === second)
    }

    @Test("SPACES-29 Pictures are only asked for with the canvas up, every 2s at most, and kept")
    func spaces29e() {
        Self.withSpaces(Self.usual(current: 1)) {
            let c = TestCanvas.make()
            defer { Self.finish(c) }
            var asked: [[Spaces.Space]] = []
            var answers: [(Spaces.Space, CGImage?) -> Void] = []
            c.takeSpacePictures = { spaces, _, answer in asked.append(spaces); answers.append(answer) }

            // At 100%: the panel shows there, but every capture would make protected video blink.
            c.isActive = false
            c.refreshSpacePictures()
            #expect(asked.isEmpty)

            c.isActive = true
            c.refreshSpacePictures()
            #expect(asked.count == 1)
            #expect(asked[0].map(\.id) == [5], "the full-screen app's Space, not the desktops")
            #expect(asked[0][0].windows == [77])
            let first = Self.picture()
            answers[0](asked[0][0], first)
            #expect(c.spacePictures[5] === first)
            #expect(c.view.spacesBar.pictures[5] === first, "on its tile straight away")

            // Open again straight away: the one it has will do.
            c.refreshSpacePictures()
            #expect(asked.count == 1)

            // Later: a fresh one. None to be had keeps the last.
            c.lastSpacePictures = 0
            c.refreshSpacePictures()
            #expect(asked.count == 2)
            answers[1](asked[1][0], nil)
            #expect(c.spacePictures[5] === first)
            let second = Self.picture()
            answers[1](asked[1][0], second)
            #expect(c.view.spacesBar.pictures[5] === second)

            // Not while paused, or while replayd isn't answering.
            c.lastSpacePictures = 0
            c.isPaused = true
            c.refreshSpacePictures()
            c.isPaused = false
            WindowCapture.replaydStuck = true
            c.refreshSpacePictures()
            WindowCapture.replaydStuck = false
            #expect(asked.count == 2)
        }
    }

    @Test("SPACES-29 A Space that's gone takes its picture with it; with no full-screen app nothing's asked")
    func spaces29f() {
        let c = TestCanvas.make()
        defer { Self.finish(c) }
        var asked = 0
        c.takeSpacePictures = { _, _, _ in asked += 1 }
        c.isActive = true
        c.spacePictures = [5: Self.picture(), 6: Self.picture()]
        Self.withSpaces(Self.usual(current: 1)) { c.refreshSpacePictures() }
        #expect(asked == 1)
        #expect(Array(c.spacePictures.keys) == [5])
        c.lastSpacePictures = 0
        Self.withSpaces([Self.display([Self.desktop(1), Self.desktop(3)], current: 1)]) { c.refreshSpacePictures() }
        #expect(asked == 1)
        #expect(c.spacePictures.isEmpty)
    }

    /// ScreenCaptureKit's and the window server's picture calls stood in for, for `body`.
    private static func withShots(_ windowServer: @escaping (CGWindowID) -> CGImage? = { _ in nil },
                                  _ body: (_ shots: () -> [(window: SCWindow, width: Int, height: Int, done: (CGImage?, Error?) -> Void)]) async throws -> Void) async rethrows {
        let oldShot = SpacePicture.shot, oldWindowServer = SpacePicture.windowServerShot
        defer { SpacePicture.shot = oldShot; SpacePicture.windowServerShot = oldWindowServer }
        var shots: [(window: SCWindow, width: Int, height: Int, done: (CGImage?, Error?) -> Void)] = []
        SpacePicture.shot = { window, config, done in shots.append((window, config.width, config.height, done)) }
        SpacePicture.windowServerShot = windowServer
        try await body({ shots })
    }

    @Test("SPACES-29 Spaces are captured one at a time, at the tile's size, and quitting stops them")
    func spaces29g() async throws {
        try await Self.withShots { shots in
            let windows: [CGWindowID: SCWindow] = [
                77: Fake.scWindow(id: 77, frame: CGRect(x: 0, y: 0, width: 2048, height: 1152)),
                88: Fake.scWindow(id: 88, frame: CGRect(x: 0, y: 0, width: 1024, height: 1152)),
                89: Fake.scWindow(id: 89, frame: CGRect(x: 1024, y: 0, width: 1024, height: 1152)),
            ]
            let spaces = [Spaces.Space(id: 5, pid: 90_501, window: 77, name: "Safari", windows: [77]),
                          Spaces.Space(id: 6, pid: 90_502, window: 88, name: "Safari & Notes", windows: [88, 89]),
                          Spaces.Space(id: 7, pid: 90_503, window: 66, name: "Gone", windows: [66]),
                          Spaces.Space(id: 8, pid: 90_504, window: 77, name: "Not reached", windows: [77])]
            var answered: [(UInt64, CGImage?)] = []
            let before = WindowCapture.unanswered
            WindowCapture.requestSent()
            SpacePicture.captureNext(spaces[...], windows: windows, scale: 2) { answered.append(($0.id, $1)) }
            #expect(shots().map(\.window.windowID) == [77], "the second Space waits for the first")
            #expect(shots()[0].width == 224 && shots()[0].height == 126)

            let one = Self.solid(Self.red, width: 224, height: 126)
            shots()[0].done(one, nil)
            try await Task.sleep(for: .milliseconds(100))
            #expect(answered.map(\.0) == [5])
            #expect(answered[0].1 === one, "ScreenCaptureKit's picture, at the size asked for, as it is")
            #expect(shots().map(\.window.windowID) == [77, 88, 89], "split view's two windows")
            #expect(shots()[1].width == 112 && shots()[1].height == 126)

            // Quitting while they're on their way stops there: nothing new for replayd.
            WindowCapture.closing = true
            defer { WindowCapture.closing = false }
            shots()[1].done(Self.solid(Self.red, width: 112, height: 126), nil)
            shots()[2].done(Self.solid(Self.blue, width: 112, height: 126), nil)
            try await Task.sleep(for: .milliseconds(100))
            #expect(answered.map(\.0) == [5, 6])
            #expect(answered[1].1?.width == 224, "both windows, in one picture")
            #expect(shots().count == 3)
            #expect(WindowCapture.unanswered == before, "nothing left for quitting to wait for")

            // A window ScreenCaptureKit doesn't list, or a picture nobody gives: none, and on to the next.
            WindowCapture.closing = false
            answered = []
            WindowCapture.requestSent()
            SpacePicture.captureNext(spaces[2...], windows: windows, scale: 2) { answered.append(($0.id, $1)) }
            try await Task.sleep(for: .milliseconds(100))
            #expect(answered.map(\.0) == [7])
            #expect(answered[0].1 == nil)
            #expect(shots().count == 4)
            shots()[3].done(nil, CocoaError(.fileNoSuchFile))
            try await Task.sleep(for: .milliseconds(100))
            #expect(answered.map(\.0) == [7, 8])
            #expect(answered[1].1 == nil)
            #expect(WindowCapture.unanswered == before)
        }
    }

    @Test("SPACES-29 A window ScreenCaptureKit refuses comes from the window server, off replayd's queue, at the tile's size")
    func spaces29h() async throws {
        let onMainThread = OSAllocatedUnfairLock(initialState: [Bool]())
        let asked = OSAllocatedUnfairLock(initialState: [CGWindowID]())
        let full = Self.solid(Self.blue, width: 1600, height: 1000)
        try await Self.withShots({ id in
            asked.withLock { $0.append(id) }
            onMainThread.withLock { $0.append(Thread.isMainThread) }
            return full
        }) { shots in
            let windows: [CGWindowID: SCWindow] = [77: Fake.scWindow(id: 77, frame: CGRect(x: 0, y: 0, width: 1600, height: 1000))]
            let space = Spaces.Space(id: 5, pid: 90_501, window: 77, name: "Safari", windows: [77])
            var answered: [CGImage?] = []
            WindowCapture.requestSent()
            SpacePicture.captureNext([space][...], windows: windows, scale: 2) { answered.append($1) }
            #expect(shots().count == 1)
            #expect(asked.withLock { $0.isEmpty }, "ScreenCaptureKit's asked first")
            let refused = CocoaError(.fileNoSuchFile)
            // On a queue of its own, as ScreenCaptureKit calls back: the call mustn't run on it.
            let callback = DispatchQueue(label: "stands in for replayd's")
            let done = shots()[0].done
            callback.async { done(nil, refused) }
            try await Task.sleep(for: .milliseconds(150))
            #expect(asked.withLock { $0 } == [77])
            #expect(onMainThread.withLock { $0 } == [false])
            let picture = try #require(answered.first ?? nil)
            #expect(picture.width == 202 && picture.height == 126, "not the 1600x1000 it came at")
            #expect(Self.redBlue(picture, x: 100).blue > 200)

            // ScreenCaptureKit's answer stands when there is one.
            asked.withLock { $0 = [] }
            WindowCapture.requestSent()
            SpacePicture.captureNext([space][...], windows: windows, scale: 2) { answered.append($1) }
            shots()[1].done(Self.solid(Self.red, width: 202, height: 126), nil)
            try await Task.sleep(for: .milliseconds(100))
            #expect(asked.withLock { $0.isEmpty })
        }
    }
}
