import Testing
import AppKit
import ScreenCaptureKit
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "LayoutStore.swift") @testable import Expanse
@_private(sourceFile: "AppDelegate.swift") @testable import Expanse
@_private(sourceFile: "MenuPanel.swift") @testable import Expanse

/// docs/regression/layouts-and-restarts.md. Each test keeps its layout and snapshots in a temp
/// folder of its own (Env.isolate, which TestCanvas.make calls). The checks of manual cases'
/// logic are in PERSISTTests+Logic.swift.
@MainActor @Suite("PERSIST: Layouts, restarts and snapshots", .serialized)
struct PERSISTTests {

    // MARK: Helpers

    /// Window IDs far above any the window server hands out, so LayoutStore.exists never finds one.
    static let farID: CGWindowID = 3_900_000_000

    /// A saved entry, its title hashed as a layout file has it.
    static func spot(_ bundleID: String = "com.example.app", title: String = "", x: Double, y: Double,
                     w: Double? = 600, h: Double? = 400, id: CGWindowID? = nil, pid: pid_t? = nil) -> SavedLayout.Window {
        .entry(bundleID: bundleID, appName: "Example", title: LayoutStore.titleKey(title), x: x, y: y, w: w, h: h, id: id, pid: pid)
    }

    /// layout.json in this test's folder.
    static var layoutFile: URL {
        precondition(LayoutStore.folderOverride != nil, "call Env.isolate() first")
        return LayoutStore.url
    }

    static func layoutJSON() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: layoutFile)) as? [String: Any])
    }

    /// A snapshot file as if taken `ago` seconds before now.
    @discardableResult
    static func snapshot(_ layout: SavedLayout = .with([]), ago: TimeInterval) -> URL {
        precondition(LayoutStore.folderOverride != nil, "call Env.isolate() first")
        let url = LayoutStore.snapshotFolder.appendingPathComponent("\(Int(Date().timeIntervalSince1970 - ago)).json")
        LayoutStore.write(layout, to: url)
        return url
    }

    /// Snapshots taken `ago` seconds before now, as `c` would have found them when it started.
    @discardableResult
    static func earlierLayouts(_ c: CanvasController, ago: [TimeInterval]) -> [URL] {
        let urls = ago.map { snapshot(.with([spot(title: "Earlier", x: 0, y: 0)]), ago: $0) }
        c.lastSnapshotAt = LayoutStore.snapshots().first?.date ?? .distantPast
        return urls
    }

    /// A canvas whose first window scan is done, so it saves.
    static func synced(_ windows: [ManagedWindow] = [], layout: SavedLayout? = nil) -> CanvasController {
        let c = TestCanvas.make(windows: windows, layout: layout)
        c.hasSynced = true
        return c
    }

    /// Runs `body` with ScreenCaptureKit held back, so nothing asks it for a picture of a fake
    /// window, then stops whatever the canvas set going: its picture timer, a camera animation,
    /// the pending save.
    @discardableResult
    static func quietly<T>(_ c: CanvasController, _ body: () throws -> T) rethrows -> T {
        let stuck = WindowCapture.replaydStuck
        WindowCapture.replaydStuck = true
        defer {
            c.snapshotTimer?.invalidate()
            c.snapshotTimer = nil
            c.cancelAnimation()
            c.saveWork?.cancel()
            c.captureSettleWork?.cancel()
            WindowCapture.replaydStuck = stuck
        }
        return try body()
    }

    /// A window gone out of view (its app hidden, minimised) or closed, as remove() records it.
    /// Its pid is this process by default: the layout only keeps those of apps still running.
    static func departed(_ c: CanvasController, id: CGWindowID, pid: pid_t = getpid(), bundleID: String = "com.example.app",
                         title: String = "", canvas: CGRect, at: Date = Date(), closed: Bool = false) {
        c.recentlyRemoved[id] = CanvasController.Departed(
            pid: pid, bundleID: bundleID, appName: "Example", title: title, canvasFrame: canvas, originalFrame: canvas,
            preferredSize: canvas.size, home: nil, parked: false, at: at, closed: closed)
    }

    /// Undoes Fake.window's record of `pid` as an ordinary app (for this process's own pid).
    static func forgetApp(_ pid: pid_t) {
        CanvasController.appPolicyLock.lock()
        CanvasController.appOwners[pid] = nil
        CanvasController.appPolicyLock.unlock()
    }

    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 600, _ h: CGFloat = 400) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: PERSIST-01

    @Test("PERSIST-01 A layout survives a save and load")
    func persist01a() throws {
        Env.isolate()
        var e = SavedLayout.Window.entry(bundleID: "com.apple.TextEdit", appName: "TextEdit", title: LayoutStore.titleKey("Notes.txt"),
                                         x: 120, y: -340, w: 800, h: 600, id: 4242, pid: 777)
        e.hx = 100; e.hy = -300; e.pw = 900; e.ph = 700
        e.ox = 40; e.oy = 60; e.ow = 1000; e.oh = 750; e.away = true
        let layout = SavedLayout(cameraX: -10, cameraY: 20, centerX: 746, centerY: 494.5, cleanExit: false,
                                 fittedWidth: 1512, fittedHeight: 949, windows: [e])
        LayoutStore.save(layout)
        let loaded = try #require(LayoutStore.load())
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(loaded) == encoder.encode(layout))
    }

    @Test("PERSIST-01 The saved layout has the camera, cleanExit false while running, and each window's app, hashed title, spots, sizes and macOS frame")
    func persist01b() throws {
        let a = Fake.window(id: Self.farID + 1, bundleID: "com.apple.TextEdit", appName: "TextEdit", title: "Secret plan.txt",
                            canvas: Self.rect(200, 150, 800, 600))
        a.home = CGPoint(x: 180, y: 140)
        a.preferredSize = CGSize(width: 900, height: 650)
        a.originalFrame = Self.rect(50, 80, 1000, 700)
        let c = Self.synced([a])
        c.save()

        let raw = try String(contentsOf: Self.layoutFile, encoding: .utf8)
        #expect(!raw.contains("Secret plan"))
        let json = try Self.layoutJSON()
        for key in ["cameraX", "cameraY", "centerX", "centerY", "cleanExit"] { #expect(json[key] != nil, "\(key)") }
        #expect(json["cleanExit"] as? Bool == false)
        #expect(json["centerX"] as? Double == 756 && json["centerY"] as? Double == 474.5)
        let windows = try #require(json["windows"] as? [[String: Any]])
        #expect(windows.count == 1)
        for key in ["bundleID", "appName", "title", "x", "y", "w", "h", "hx", "hy", "pw", "ph", "ox", "oy", "ow", "oh"] {
            #expect(windows.first?[key] != nil, "\(key)")
        }

        let e = try #require(LayoutStore.load()?.windows.first)
        #expect(e.bundleID == "com.apple.TextEdit" && e.appName == "TextEdit")
        #expect(e.title == LayoutStore.titleKey("Secret plan.txt") && e.title.hasPrefix("sha256:"))
        #expect(e.x == 200 && e.y == 150 && e.w == 800 && e.h == 600)
        #expect(e.hx == 180 && e.hy == 140)
        #expect(e.pw == 900 && e.ph == 650)
        #expect(e.ox == 50 && e.oy == 80 && e.ow == 1000 && e.oh == 700)
    }

    @Test("PERSIST-01 A change is written to layout.json about a second later")
    func persist01c() async throws {
        let c = Self.synced([Fake.window(id: Self.farID + 1, canvas: Self.rect(0, 40))])
        c.scheduleSave()
        #expect(!FileManager.default.fileExists(atPath: Self.layoutFile.path))
        try await Task.sleep(for: .milliseconds(1400))
        #expect(FileManager.default.fileExists(atPath: Self.layoutFile.path))
        #expect(LayoutStore.load()?.windows.count == 1)
    }

    // MARK: PERSIST-02

    @Test("PERSIST-02 A window's own saved spot (same ID and pid) comes before one with its title")
    func persist02a() {
        Env.isolate()
        let pid = Fake.firstPID
        var pool = [Self.spot(title: "Inbox", x: 0, y: 0, id: Self.farID + 9, pid: pid),
                    Self.spot(title: "Draft", x: 200, y: 0, id: Self.farID + 1, pid: pid)]
        let e = LayoutStore.takeMatch(bundleID: "com.example.app", title: "Inbox", id: Self.farID + 1, pid: pid, open: [], from: &pool)
        #expect(e?.x == 200)
        #expect(pool.count == 1)
    }

    @Test("PERSIST-02 With no spot of its own, a window takes one with its title, then any of its app's")
    func persist02b() {
        Env.isolate()
        var pool = [Self.spot("com.other.app", title: "Inbox", x: -100, y: 0),
                    Self.spot(title: "Other", x: 100, y: 0),
                    Self.spot(title: "Inbox", x: 0, y: 0)]
        func take(_ title: String, _ id: CGWindowID) -> Double? {
            LayoutStore.takeMatch(bundleID: "com.example.app", title: title, id: Self.farID + id, pid: Fake.firstPID, open: [], from: &pool)?.x
        }
        #expect(take("Inbox", 1) == 0)
        #expect(take("Notes", 2) == 100)
        #expect(take("Notes", 3) == nil)
        #expect(pool.map(\.bundleID) == ["com.other.app"])
    }

    @Test("PERSIST-02 Several windows with the same title each get their own spot back")
    func persist02c() {
        Env.isolate()
        let pid = Fake.firstPID
        var pool = (0..<3).map { i in
            Self.spot("com.apple.finder", title: "Downloads", x: Double(i) * 1000, y: 0, id: Self.farID + CGWindowID(i), pid: pid)
        }
        for i in [2, 0, 1] {
            let e = LayoutStore.takeMatch(bundleID: "com.apple.finder", title: "Downloads", id: Self.farID + CGWindowID(i), pid: pid,
                                          open: [], from: &pool)
            #expect(e?.x == Double(i) * 1000)
        }
    }

    @Test("PERSIST-02 At launch a window goes back to its saved canvas spot, chosen size and home spot")
    func persist02d() throws {
        var e = Self.spot(title: "Doc", x: 2400, y: -300, w: 700, h: 500, id: Self.farID + 1, pid: Fake.firstPID)
        e.hx = 2300; e.hy = -250; e.pw = 900; e.ph = 600
        let c = TestCanvas.make(layout: .with([e]))
        #expect(c.firstSync && c.savedPool.count == 1)
        Fake.regularApp()
        let sc = Fake.scWindow(id: Self.farID + 1, title: "Doc", frame: Self.rect(300, 200, 700, 500))
        let restored = Self.quietly(c) { c.add(sc, live: false, frame: sc.frame) }
        #expect(restored)
        let w = try #require(c.windows.first)
        #expect(w.canvasFrame.origin == CGPoint(x: 2400, y: -300))
        #expect(w.preferredSize == CGSize(width: 900, height: 600))
        #expect(w.home == CGPoint(x: 2300, y: -250))
        #expect(c.savedPool.isEmpty)
    }

    // MARK: PERSIST-04

    @Test("PERSIST-04 Quitting brings a window whose macOS spot is off this screen to the top, centred, 40pt below the menu bar")
    func persist04() {
        let c = TestCanvas.make()   // viewport (0, 33, 1512, 949)
        #expect(c.viewport == Self.rect(0, 33, 1512, 949))
        // Its spot was on a bigger screen: back in view at its own size.
        #expect(c.restoredFrame(Self.rect(2600, 300, 800, 600)) == Self.rect(356, 73, 800, 600))
        // Less than 40pt of it would show: as good as gone.
        #expect(c.restoredFrame(Self.rect(1512 - 30, 300, 800, 600)) == Self.rect(356, 73, 800, 600))
        // On screen, or enough of it: where it was.
        #expect(c.restoredFrame(Self.rect(300, 200, 800, 600)) == Self.rect(300, 200, 800, 600))
        #expect(c.restoredFrame(Self.rect(1512 - 50, 300, 800, 600)) == Self.rect(1462, 300, 800, 600))
        // No size: nothing to put back.
        #expect(c.restoredFrame(Self.rect(10, 10, 0, 0)) == nil)
    }

    // MARK: PERSIST-06

    @Test("PERSIST-06 After a crash, a window found at launch keeps the macOS frame the crashed run saved", arguments: [false, nil] as [Bool?])
    func persist06a(cleanExit: Bool?) throws {
        var e = Self.spot(title: "Doc", x: 500, y: 100, w: 700, h: 500, id: Self.farID + 1, pid: Fake.firstPID)
        e.ox = 40; e.oy = 60; e.ow = 1000; e.oh = 750
        let c = TestCanvas.make(layout: .with([e], cleanExit: cleanExit))
        Fake.regularApp()
        // Where the crash left it: parked in the corner.
        let sc = Fake.scWindow(id: Self.farID + 1, title: "Doc", frame: Self.rect(1511, 981, 700, 500))
        Self.quietly(c) { c.add(sc, live: false, frame: sc.frame) }
        let w = try #require(c.windows.first)
        #expect(w.originalFrame == Self.rect(40, 60, 1000, 750))
        #expect(w.canvasFrame.origin == CGPoint(x: 500, y: 100))
    }

    @Test("PERSIST-06 After a clean exit, the macOS frame is where the window is found")
    func persist06b() throws {
        var e = Self.spot(title: "Doc", x: 500, y: 100, w: 700, h: 500, id: Self.farID + 1, pid: Fake.firstPID)
        e.ox = 40; e.oy = 60; e.ow = 1000; e.oh = 750
        let c = TestCanvas.make(layout: .with([e], cleanExit: true))
        Fake.regularApp()
        let sc = Fake.scWindow(id: Self.farID + 1, title: "Doc", frame: Self.rect(300, 200, 700, 500))
        Self.quietly(c) { c.add(sc, live: false, frame: sc.frame) }
        #expect(c.windows.first?.originalFrame == Self.rect(300, 200, 700, 500))
    }

    // MARK: PERSIST-11

    @Test("PERSIST-11 Until a window scan has worked, saving leaves layout.json and its spots alone")
    func persist11() throws {
        let saved = SavedLayout.with([Self.spot(title: "Notes", x: 10, y: 20, id: Self.farID + 1, pid: Fake.firstPID)])
        let c = TestCanvas.make(layout: saved)
        let before = try Data(contentsOf: Self.layoutFile)
        #expect(!c.hasSynced)
        c.save()
        c.save(cleanExit: true)
        #expect(try Data(contentsOf: Self.layoutFile) == before)
        // Still there for when the scan works.
        #expect(c.savedPool.count == 1)

        c.windows = [Fake.window(id: Self.farID + 2, canvas: Self.rect(0, 40))]
        c.hasSynced = true
        c.save()
        #expect(try Data(contentsOf: Self.layoutFile) != before)
    }

    // MARK: PERSIST-12

    @Test("PERSIST-12 Spots of saved windows not open yet stay in layout.json, marked away")
    func persist12a() throws {
        let notes = Self.spot("com.apple.Notes", title: "Notes", x: 1800, y: 300, id: Self.farID + 1, pid: Fake.firstPID)
        let c = Self.synced([Fake.window(id: Self.farID + 2, canvas: Self.rect(0, 40))], layout: .with([notes]))
        c.save()
        let windows = try #require(LayoutStore.load()?.windows)
        let kept = try #require(windows.first { $0.bundleID == "com.apple.Notes" })
        #expect(kept.away == true && kept.x == 1800 && kept.y == 300)
        #expect(windows.first { $0.id == Self.farID + 2 }?.away == nil)
    }

    @Test("PERSIST-12 At most 60 kept spots are saved")
    func persist12b() throws {
        let c = Self.synced([Fake.window(id: Self.farID + 100, canvas: Self.rect(0, 40))])
        c.savedPool = (0..<70).map { Self.spot(title: "Doc \($0)", x: Double($0) * 10, y: 0) }
        c.save()
        let windows = try #require(LayoutStore.load()?.windows)
        #expect(windows.filter { $0.away == true }.count == 60)
    }

    @Test("PERSIST-12 A window opening after launch takes its kept spot, which then stops being kept")
    func persist12c() throws {
        let notes = Self.spot("com.apple.Notes", title: "Notes", x: 1800, y: 300, id: Self.farID + 1, pid: Fake.firstPID)
        let c = Self.synced([], layout: .with([notes]))
        // Notes started again: a new process, a new window.
        let e = LayoutStore.takeMatch(bundleID: "com.apple.Notes", title: "Notes", id: Self.farID + 5, pid: Fake.firstPID + 1,
                                      open: [], from: &c.savedPool)
        #expect(e?.x == 1800 && e?.y == 300)
        c.save()
        #expect(LayoutStore.load()?.windows.contains { $0.bundleID == "com.apple.Notes" } == false)
    }

    // MARK: PERSIST-15

    @Test("PERSIST-15 Same-titled windows each take back exactly their own spot, by window ID and pid")
    func persist15a() {
        Env.isolate()
        let pid = Fake.firstPID
        var pool = (0..<6).map { i in
            Self.spot("com.apple.finder", title: "Documents", x: Double(i) * 700, y: Double(i) * 30, id: Self.farID + CGWindowID(i), pid: pid)
        }
        let open = Set((0..<6).map { LayoutStore.windowKey(pid: pid, id: Self.farID + CGWindowID($0)) })
        for i in [3, 0, 5, 1, 4, 2] {
            let e = LayoutStore.takeMatch(bundleID: "com.apple.finder", title: "Documents", id: Self.farID + CGWindowID(i), pid: pid,
                                          open: open, from: &pool)
            #expect(e?.x == Double(i) * 700 && e?.y == Double(i) * 30, "window \(i)")
        }
        #expect(pool.isEmpty)
    }

    @Test("PERSIST-15 layout.json entries carry the window's ID and pid")
    func persist15b() throws {
        let a = Fake.window(id: Self.farID + 1, pid: Fake.firstPID, title: "Documents", canvas: Self.rect(0, 40))
        let b = Fake.window(id: Self.farID + 2, pid: Fake.firstPID, title: "Documents", canvas: Self.rect(700, 40))
        Self.synced([a, b]).save()
        let windows = try #require(LayoutStore.load()?.windows)
        #expect(windows.map(\.id) == [Self.farID + 1, Self.farID + 2])
        #expect(windows.map(\.pid) == [Fake.firstPID, Fake.firstPID])
    }

    // MARK: PERSIST-16

    @Test("PERSIST-16 A new same-titled window takes the closed window's spot, never an open window's")
    func persist16() {
        Env.isolate()
        let pid = Fake.firstPID
        var pool = (0..<6).map { i in
            Self.spot("com.apple.finder", title: "Documents", x: Double(i) * 700, y: 0, id: Self.farID + CGWindowID(i), pid: pid)
        }
        // Window 5 was closed; window 6 is new. Five old ones and the new one are open.
        let ids = [0, 1, 2, 3, 4, 6].map { Self.farID + CGWindowID($0) }
        let open = Set(ids.map { LayoutStore.windowKey(pid: pid, id: $0) })
        // The new window first, while every entry is still in the pool.
        let new = LayoutStore.takeMatch(bundleID: "com.apple.finder", title: "Documents", id: Self.farID + 6, pid: pid, open: open, from: &pool)
        #expect(new?.x == 3500)   // window 5's
        for i in 0..<5 {
            let e = LayoutStore.takeMatch(bundleID: "com.apple.finder", title: "Documents", id: Self.farID + CGWindowID(i), pid: pid,
                                          open: open, from: &pool)
            #expect(e?.x == Double(i) * 700, "window \(i)")
        }
    }

    // MARK: PERSIST-17

    @Test("PERSIST-17 Quitting before the walkthrough is done doesn't touch the saved layout")
    func persist17a() throws {
        Env.isolate()
        LayoutStore.save(.with([Self.spot(title: "Notes", x: 10, y: 20)]))
        let before = try Data(contentsOf: Self.layoutFile)
        let d = AppDelegate()
        // Were it to shut the canvas down, this would be saved over the layout.
        d.controller.hasSynced = true
        d.controller.windows = [Fake.window(id: Self.farID + 1, canvas: Self.rect(0, 40))]
        #expect(!d.isOn)
        Self.quietly(d.controller) { d.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        #expect(try Data(contentsOf: Self.layoutFile) == before)
        #expect(!d.controller.isPaused)
    }

    @Test("PERSIST-17 Once started, quitting does shut down and save")
    func persist17b() throws {
        Env.isolate()
        LayoutStore.save(.with([Self.spot(title: "Notes", x: 10, y: 20)]))
        let before = try Data(contentsOf: Self.layoutFile)
        let d = AppDelegate()
        d.controller.hasSynced = true
        d.controller.windows = [Fake.window(id: Self.farID + 1, canvas: Self.rect(0, 40))]
        d.isOn = true
        Self.quietly(d.controller) { d.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        #expect(try Data(contentsOf: Self.layoutFile) != before)
        #expect(d.controller.isPaused)
        #expect(LayoutStore.load()?.cleanExit == true)
    }

    // MARK: PERSIST-19

    @Test("PERSIST-19 A saved spot whose window still exists (minimised) isn't given to another window of its app")
    func persist19() throws {
        let c = TestCanvas.make()
        // A window the window server has but that isn't on screen: the canvas's own backdrop.
        let id = CGWindowID(c.overlay.windowNumber), pid = getpid()
        try #require(id > 0 && LayoutStore.exists(id: id, pid: pid))
        var pool = [Self.spot("com.apple.TextEdit", title: "A", x: 900, y: 100, id: id, pid: pid)]
        // C, a new window with another title, at launch: not A's spot.
        #expect(LayoutStore.takeMatch(bundleID: "com.apple.TextEdit", title: "C", id: Self.farID + 3, pid: pid,
                                      open: [], from: &pool) == nil)
        #expect(LayoutStore.largerSpot(bundleID: "com.apple.TextEdit", size: CGSize(width: 10, height: 10), open: [], in: pool) == nil)
        #expect(pool.count == 1)
        // A, back from the Dock, gets it.
        #expect(LayoutStore.takeMatch(bundleID: "com.apple.TextEdit", title: "A", id: id, pid: pid, open: [], from: &pool)?.x == 900)
    }

    // MARK: PERSIST-20

    @Test("PERSIST-20 Earlier layouts are the snapshot files, named for the time they were taken, newest first")
    func persist20a() throws {
        Env.isolate()
        #expect(LayoutStore.snapshots().isEmpty)
        let folder = LayoutStore.snapshotFolder
        for t in [1_761_000_000, 1_761_003_000, 1_761_001_500] {
            LayoutStore.write(.with([]), to: folder.appendingPathComponent("\(t).json"))
        }
        try Data("{}".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("draft.json"))
        #expect(LayoutStore.snapshots().map { Int($0.date.timeIntervalSince1970) } == [1_761_003_000, 1_761_001_500, 1_761_000_000])
    }

    @Test("PERSIST-20 The panel's thumbnails: none without snapshots, newest first, without windows that were out of view")
    func persist20b() throws {
        Env.isolate()
        #expect(MenuPanel.layouts().isEmpty)
        var away = Self.spot(title: "Hidden", x: 900, y: 0)
        away.away = true
        Self.snapshot(.with([Self.spot(title: "Old", x: 0, y: 0)]), ago: 3600)
        Self.snapshot(.with([Self.spot(title: "Shown", x: 10, y: 20, w: 300, h: 200), away]), ago: 120)
        let layouts = MenuPanel.layouts()
        #expect(layouts.count == 2)
        #expect(layouts.first?.windows == [Self.rect(10, 20, 300, 200)])
        #expect((layouts.first?.date ?? .distantPast) > (layouts.last?.date ?? .distantFuture))
    }

    @Test("PERSIST-20 A thumbnail reads Just now for its first minute, then N minutes ago")
    func persist20c() {
        let url = URL(fileURLWithPath: "/dev/null")
        #expect(LayoutThumbnail(layout: .init(id: url, date: Date().addingTimeInterval(-20), windows: []), action: {}).ago == "Just now")
        let older = LayoutThumbnail(layout: .init(id: url, date: Date().addingTimeInterval(-125), windows: []), action: {}).ago
        #expect(older != "Just now" && older.contains("2"))
        if Locale.current.language.languageCode == .english { #expect(older == "2 minutes ago") }
    }

    // MARK: PERSIST-21

    @Test("PERSIST-21 Three snapshots are kept, 15 minutes apart")
    func persist21a() {
        #expect(LayoutStore.snapshotsKept == 3)
        #expect(LayoutStore.snapshotSpacing == 15 * 60)
    }

    @Test("PERSIST-21 A snapshot is a file named for the time, seconds since 1970, and only the newest three stay")
    func persist21b() throws {
        Env.isolate()
        let oldest = Self.snapshot(ago: 3000)
        Self.snapshot(ago: 2000)
        Self.snapshot(ago: 1000)
        LayoutStore.saveSnapshot(.with([Self.spot(title: "New", x: 1, y: 2)]))
        let s = LayoutStore.snapshots()
        #expect(s.count == 3)
        #expect(!FileManager.default.fileExists(atPath: oldest.path))
        let newest = try #require(s.first)
        #expect(abs(newest.date.timeIntervalSinceNow) < 5)
        #expect(newest.url.lastPathComponent == "\(Int(newest.date.timeIntervalSince1970)).json")
        #expect(LayoutStore.load(newest)?.windows.first?.x == 1)
    }

    @Test("PERSIST-21 Saving takes a snapshot when the layout changed and the newest is 15 minutes old, not before")
    func persist21c() throws {
        let a = Fake.window(id: Self.farID + 1, canvas: Self.rect(0, 40))
        let c = Self.synced([a])
        Self.earlierLayouts(c, ago: [20 * 60])
        c.save()
        #expect(LayoutStore.snapshots().count == 2)
        // Moved again straight away: none.
        a.canvasFrame.origin.x += 300
        c.save()
        #expect(LayoutStore.snapshots().count == 2)
        // 15 minutes on.
        try Self.fifteenMinutesOn(c)
        a.canvasFrame.origin.x += 300
        c.save()
        #expect(LayoutStore.snapshots().count == 3)
        let latest = try #require(LayoutStore.snapshots().first)
        #expect(LayoutStore.load(latest)?.windows.first?.x == 600)
    }

    @Test("PERSIST-21 Saving a layout that hasn't changed takes no snapshot, however old the newest")
    func persist21d() throws {
        let c = Self.synced([Fake.window(id: Self.farID + 1, canvas: Self.rect(0, 40))])
        c.save()
        #expect(LayoutStore.snapshots().count == 1)
        // Twenty rounds: the same layout used to encode differently now and then (keys unsorted).
        for _ in 0..<20 {
            try Self.fifteenMinutesOn(c)
            c.save()
            #expect(LayoutStore.snapshots().count == 1)
            // Back to one, for the next round.
            for s in LayoutStore.snapshots().dropFirst() { try FileManager.default.removeItem(at: s.url) }
        }
    }

    /// As if the newest snapshot was taken 15 minutes ago: its file renamed to match (so the next
    /// one isn't given its name) and the canvas's record of it.
    static func fifteenMinutesOn(_ c: CanvasController) throws {
        let then = Int(Date().timeIntervalSince1970) - 15 * 60
        let newest = try #require(LayoutStore.snapshots().first)
        try FileManager.default.moveItem(at: newest.url, to: newest.url.deletingLastPathComponent().appendingPathComponent("\(then).json"))
        c.lastSnapshotAt = Date(timeIntervalSince1970: TimeInterval(then))
    }

    // MARK: PERSIST-23

    @Test("PERSIST-23 A window of an app the snapshot doesn't know gets no spot")
    func persist23() {
        Env.isolate()
        var pool = [Self.spot("com.apple.Safari", title: "Start", x: 0, y: 0, id: Self.farID + 1, pid: Fake.firstPID)]
        #expect(LayoutStore.takeMatch(bundleID: "com.apple.calculator", title: "Calculator", id: Self.farID + 2, pid: Fake.firstPID + 1,
                                      open: [], from: &pool) == nil)
        #expect(pool.count == 1)
    }

    // MARK: PERSIST-28

    @Test("PERSIST-28 A window of an app started again takes its saved spot by title")
    func persist28a() {
        Env.isolate()
        var pool = [Self.spot("com.apple.calculator", title: "Calculator", x: 2200, y: 600, w: 230, h: 400, id: Self.farID + 1, pid: Fake.firstPID),
                    Self.spot("com.apple.calculator", title: "Paper Tape", x: 2500, y: 600, w: 230, h: 400)]
        // The new process's window, with a new ID.
        let e = LayoutStore.takeMatch(bundleID: "com.apple.calculator", title: "Calculator", id: Self.farID + 50, pid: Fake.firstPID + 1,
                                      size: CGSize(width: 230, height: 400), open: [], from: &pool)
        #expect(e?.x == 2200 && e?.y == 600)
    }

    @Test("PERSIST-28 At launch, a window of an app started again goes to its saved spot")
    func persist28b() throws {
        let c = TestCanvas.make(layout: .with([
            Self.spot("com.apple.calculator", title: "Calculator", x: 2200, y: 600, w: 230, h: 400, id: Self.farID + 1, pid: Fake.firstPID)]))
        let pid = Fake.firstPID + 1
        Fake.regularApp(pid)
        let sc = Fake.scWindow(id: Self.farID + 50, pid: pid, bundleID: "com.apple.calculator", appName: "Calculator",
                               title: "Calculator", frame: Self.rect(600, 300, 230, 400))
        let restored = Self.quietly(c) { c.add(sc, live: false, frame: sc.frame) }
        #expect(restored)
        #expect(c.windows.first?.canvasFrame.origin == CGPoint(x: 2200, y: 600))
    }

    // MARK: PERSIST-29

    @Test("PERSIST-29 A window under a quarter of a saved spot's chosen size doesn't take it")
    func persist29a() {
        Env.isolate()
        var e = Self.spot("com.example.app", title: "Main", x: 100, y: 100, w: 1000, h: 700)
        e.pw = 1200; e.ph = 800   // a quarter: 240,000 square points
        var pool = [e]
        let small = CGSize(width: 500, height: 400)
        #expect(LayoutStore.takeMatch(bundleID: "com.example.app", title: "Settings", id: Self.farID + 1, pid: Fake.firstPID,
                                      size: small, open: [], from: &pool) == nil)
        // Not even with the same title.
        #expect(LayoutStore.takeMatch(bundleID: "com.example.app", title: "Main", id: Self.farID + 1, pid: Fake.firstPID,
                                      size: small, open: [], from: &pool) == nil)
        #expect(pool.count == 1)
        // Kept for the main window (see largerSpot).
        #expect(LayoutStore.largerSpot(bundleID: "com.example.app", size: small, open: [], in: pool)?.x == 100)
        // A quarter or more takes it.
        #expect(LayoutStore.takeMatch(bundleID: "com.example.app", title: "Main", id: Self.farID + 2, pid: Fake.firstPID,
                                      size: CGSize(width: 600, height: 400), open: [], from: &pool)?.x == 100)
    }

    @Test("PERSIST-29 Without a chosen size, the spot's own size counts")
    func persist29b() {
        Env.isolate()
        var pool = [Self.spot("com.example.app", title: "Main", x: 100, y: 100, w: 1200, h: 800)]
        #expect(LayoutStore.takeMatch(bundleID: "com.example.app", title: "Main", id: Self.farID + 1, pid: Fake.firstPID,
                                      size: CGSize(width: 400, height: 300), open: [], from: &pool) == nil)
        #expect(LayoutStore.takeMatch(bundleID: "com.example.app", title: "Main", id: Self.farID + 1, pid: Fake.firstPID,
                                      size: CGSize(width: 1100, height: 760), open: [], from: &pool)?.x == 100)
    }

    // MARK: PERSIST-32

    @Test("PERSIST-32 Take snapshot keeps the layout now, however recent the last, and only the newest three stay")
    func persist32a() throws {
        let a = Fake.window(id: Self.farID + 1, canvas: Self.rect(321, 40))
        let c = Self.synced([a])
        let oldest = Self.earlierLayouts(c, ago: [60, 20 * 60, 40 * 60])[2]
        Self.quietly(c) { c.takeSnapshot() }
        let s = LayoutStore.snapshots()
        #expect(s.count == 3)
        #expect(!FileManager.default.fileExists(atPath: oldest.path))
        let newest = try #require(s.first)
        #expect(abs(newest.date.timeIntervalSinceNow) < 5)
        #expect(LayoutStore.load(newest)?.windows.first?.x == 321)
    }

    @Test("PERSIST-32 Take snapshot keeps the panel open, and waits for Expanse to have started")
    func persist32b() throws {
        #expect(!MenuPanel.Action.takeSnapshot.closesPanel)
        #expect(MenuPanel.Action.takeSnapshot.needsCanvas)
        // Paused: none.
        let c = Self.synced([Fake.window(id: Self.farID + 1, canvas: Self.rect(0, 40))])
        Self.quietly(c) { c.pause() }
        let before = LayoutStore.snapshots().map(\.url)
        Self.quietly(c) { c.takeSnapshot() }
        #expect(LayoutStore.snapshots().map(\.url) == before)
    }

    // MARK: PERSIST-33

    @Test("PERSIST-33 A closed window isn't saved; one out of view is, marked away")
    func persist33a() throws {
        try #require(NSRunningApplication(processIdentifier: getpid()) != nil)
        let c = Self.synced([Fake.window(id: Self.farID + 9, canvas: Self.rect(0, 40))])
        Self.departed(c, id: Self.farID + 1, bundleID: "com.apple.TextEdit", canvas: Self.rect(900, 40), closed: true)
        Self.departed(c, id: Self.farID + 2, bundleID: "com.apple.TextEdit", canvas: Self.rect(1600, 40))
        c.save()
        let windows = try #require(LayoutStore.load()?.windows)
        #expect(!windows.contains { $0.id == Self.farID + 1 })
        #expect(windows.first { $0.id == Self.farID + 2 }?.away == true)
        #expect(windows.filter { $0.bundleID == "com.apple.TextEdit" }.count == 1)
    }

    @Test("PERSIST-33 A closed window's spot is kept 10 seconds (for a tab taking over), one out of view a week")
    func persist33b() {
        let w = Fake.window(id: Self.farID + 9, canvas: Self.rect(0, 40))
        let c = TestCanvas.make(windows: [w])
        let now = Date()
        Self.departed(c, id: Self.farID + 1, canvas: Self.rect(900, 40), at: now - 11, closed: true)
        Self.departed(c, id: Self.farID + 2, canvas: Self.rect(900, 40), at: now - 5, closed: true)
        Self.departed(c, id: Self.farID + 3, canvas: Self.rect(900, 40), at: now - 11)
        Self.departed(c, id: Self.farID + 4, canvas: Self.rect(900, 40), at: now - 8 * 24 * 3600)
        Self.quietly(c) { c.remove(w) }
        #expect(Set(c.recentlyRemoved.keys) == [Self.farID + 2, Self.farID + 3, Self.farID + 9])
    }

    @Test("PERSIST-33 When an app quits, windows it closed more than moments before don't keep their spots")
    func persist33c() {
        let me = NSRunningApplication.current, pid = me.processIdentifier
        let c = Self.synced()
        let now = Date()
        Self.departed(c, id: Self.farID + 1, pid: pid, canvas: Self.rect(900, 40), at: now - 6, closed: true)
        Self.departed(c, id: Self.farID + 2, pid: pid, canvas: Self.rect(900, 40), at: now - 2, closed: true)
        Self.departed(c, id: Self.farID + 3, pid: pid, canvas: Self.rect(900, 40), at: now - 60)
        Self.quietly(c) { c.appQuit(me) }
        #expect(Set(c.justQuit.flatMap { $0.spots.compactMap(\.id) }) == [Self.farID + 2, Self.farID + 3])
        #expect(c.recentlyRemoved.isEmpty)
    }

    // MARK: PERSIST-34

    @Test("PERSIST-34 After the 3 minutes, saved spots of windows that haven't come back are let go; still-open ones stay")
    func persist34a() throws {
        let c = Self.synced()
        let open = CGWindowID(c.overlay.windowNumber)
        try #require(LayoutStore.isOpen(Self.spot(x: 0, y: 0, id: open, pid: getpid())))
        c.savedPool = [Self.spot("com.apple.calculator", title: "Calculator", x: 0, y: 0),
                       Self.spot(title: "Gone", x: 100, y: 0, id: Self.farID + 1, pid: Fake.firstPID),
                       Self.spot(title: "Hidden", x: 200, y: 0, id: open, pid: getpid())]
        c.restartSpotsUntil = Date().addingTimeInterval(-1)
        Self.quietly(c) { c.letGoOfSavedSpots() }
        #expect(c.savedPool.map(\.x) == [200])
        // The next layout.json no longer lists them.
        c.save()
        let windows = try #require(LayoutStore.load()?.windows)
        #expect(windows.map(\.x) == [200])
        #expect(!windows.contains { $0.bundleID == "com.apple.calculator" })
    }

    @Test("PERSIST-34 Before the 3 minutes are up (or after resuming), nothing is let go")
    func persist34b() {
        let c = Self.synced()
        c.savedPool = [Self.spot("com.apple.calculator", title: "Calculator", x: 0, y: 0)]
        c.restartSpotsUntil = Date().addingTimeInterval(60)
        Self.quietly(c) { c.letGoOfSavedSpots() }
        #expect(c.savedPool.count == 1)
    }

    // MARK: PERSIST-35

    @Test("PERSIST-35 A window back after the 3 minutes still takes its own saved spot (same ID, pid and app)")
    func persist35a() throws {
        let pid = Fake.firstPID
        Fake.regularApp(pid)
        let c = TestCanvas.make(layout: .with([
            Self.spot("com.apple.Safari", title: "Start", x: 2200, y: 400, w: 900, h: 700, id: Self.farID + 1, pid: pid)]))
        c.firstSync = false
        c.hasSynced = true
        c.restartSpotsUntil = Date().addingTimeInterval(-1)
        let sc = Fake.scWindow(id: Self.farID + 1, pid: pid, bundleID: "com.apple.Safari", appName: "Safari", title: "Start",
                               frame: Self.rect(300, 200, 900, 700))
        let restored = Self.quietly(c) { c.add(sc, live: false, frame: sc.frame) }
        #expect(restored)
        #expect(c.windows.first?.canvasFrame.origin == CGPoint(x: 2200, y: 400))
        #expect(c.savedPool.isEmpty)
    }

    @Test("PERSIST-35 After the 3 minutes, another window of the app doesn't take that spot")
    func persist35b() throws {
        let pid = Fake.firstPID
        Fake.regularApp(pid)
        let c = TestCanvas.make(layout: .with([
            Self.spot("com.apple.Safari", title: "Start", x: 2200, y: 400, w: 900, h: 700, id: Self.farID + 1, pid: pid)]))
        c.firstSync = false
        c.hasSynced = true
        c.restartSpotsUntil = Date().addingTimeInterval(-1)
        let sc = Fake.scWindow(id: Self.farID + 2, pid: pid, bundleID: "com.apple.Safari", appName: "Safari", title: "Start",
                               frame: Self.rect(300, 200, 900, 700))
        let restored = Self.quietly(c) { c.add(sc, live: false, frame: sc.frame) }
        #expect(!restored)
        #expect(c.windows.first?.canvasFrame.origin != CGPoint(x: 2200, y: 400))
        #expect(c.savedPool.count == 1)
    }

    // MARK: PERSIST-37

    @Test("PERSIST-37 An app that quit in the last 30 seconds keeps its windows' spots in layout.json, marked away")
    func persist37a() throws {
        let me = NSRunningApplication.current, pid = me.processIdentifier
        defer { Self.forgetApp(pid) }
        let calc = Fake.window(id: Self.farID + 1, pid: pid, bundleID: "com.apple.calculator", appName: "Calculator",
                               title: "Calculator", canvas: Self.rect(1800, 300, 230, 400))
        let other = Fake.window(id: Self.farID + 2, canvas: Self.rect(0, 40))
        let c = Self.synced([calc, other])
        Self.quietly(c) { c.appQuit(me) }
        #expect(c.windows.map(\.id) == [Self.farID + 2])
        c.save()
        let kept = try #require(LayoutStore.load()?.windows.first { $0.id == Self.farID + 1 })
        #expect(kept.away == true && kept.bundleID == "com.apple.calculator")
        #expect(kept.x == 1800 && kept.y == 300)
    }

    @Test("PERSIST-37 More than 30 seconds after an app quit, its windows' spots are gone")
    func persist37b() throws {
        let me = NSRunningApplication.current, pid = me.processIdentifier
        defer { Self.forgetApp(pid) }
        let calc = Fake.window(id: Self.farID + 1, pid: pid, bundleID: "com.apple.calculator", appName: "Calculator",
                               title: "Calculator", canvas: Self.rect(1800, 300, 230, 400))
        let c = Self.synced([calc, Fake.window(id: Self.farID + 2, canvas: Self.rect(0, 40))])
        Self.quietly(c) { c.appQuit(me) }
        c.justQuit = c.justQuit.map { (at: $0.at.addingTimeInterval(-31), spots: $0.spots) }
        c.save()
        #expect(LayoutStore.load()?.windows.contains { $0.bundleID == "com.apple.calculator" } == false)
        #expect(c.justQuit.isEmpty)
    }

    // MARK: PERSIST-40

    @Test("PERSIST-40 With nothing on the canvas, the layout is saved but no snapshot is taken")
    func persist40() throws {
        let c = Self.synced()
        let earlier = Self.earlierLayouts(c, ago: [16 * 60, 40 * 60, 70 * 60])
        c.save()
        #expect(FileManager.default.fileExists(atPath: Self.layoutFile.path))
        #expect(Set(LayoutStore.snapshots().map(\.url.lastPathComponent)) == Set(earlier.map(\.lastPathComponent)))
    }

    // MARK: PERSIST-41

    @Test("PERSIST-41 Take snapshot with nothing on the canvas takes none")
    func persist41() {
        let c = Self.synced()
        let earlier = Self.earlierLayouts(c, ago: [60, 20 * 60, 40 * 60])
        Self.quietly(c) { c.takeSnapshot() }
        #expect(Set(LayoutStore.snapshots().map(\.url.lastPathComponent)) == Set(earlier.map(\.lastPathComponent)))
    }

    // MARK: PERSIST-42

    @Test("PERSIST-42 Windows with no saved spot at launch go to free spots beside the restored window most in view")
    func persist42() {
        let a = Fake.window(id: Self.farID + 1, canvas: Self.rect(100, 100))       // in view
        let b = Fake.window(id: Self.farID + 2, canvas: Self.rect(2000, 100))      // out of view
        let s1 = Fake.window(id: Self.farID + 3, canvas: Self.rect(150, 150, 500, 300))
        let s2 = Fake.window(id: Self.farID + 4, canvas: Self.rect(200, 200, 500, 300))
        s1.home = CGPoint(x: 150, y: 150)
        let c = TestCanvas.make(windows: [a, b, s1, s2])
        Self.quietly(c) { c.placeUnrecognised([s1, s2]) }
        let frames = c.windows.map(\.canvasFrame)
        for i in frames.indices {
            for j in frames.indices where j > i { #expect(!frames[i].intersects(frames[j]), "\(i) and \(j) overlap") }
        }
        // Beside the anchor: one edge the standard gap from one of its edges, overlapping it the other way.
        func beside(_ r: CGRect, _ a: CGRect) -> Bool {
            let gap = CanvasController.gap
            let side = (r.minX == a.maxX + gap || r.maxX == a.minX - gap) && r.minY < a.maxY && r.maxY > a.minY
            let stacked = (r.minY == a.maxY + gap || r.maxY == a.minY - gap) && r.minX < a.maxX && r.maxX > a.minX
            return side || stacked
        }
        #expect(beside(s1.canvasFrame, a.canvasFrame))
        #expect(beside(s2.canvasFrame, a.canvasFrame))
        #expect(c.visibleCanvas.contains(s1.canvasFrame) && c.visibleCanvas.contains(s2.canvasFrame))
        #expect(s1.home == nil && s2.home == nil)
        #expect(a.canvasFrame == Self.rect(100, 100) && b.canvasFrame == Self.rect(2000, 100))
    }

    // MARK: PERSIST-43

    @Test("PERSIST-43 The layout is saved a second after a change, even while changes keep coming")
    func persist43() async throws {
        let w = Fake.window(id: 4301, canvas: Self.rect(100, 100))
        let c = Self.synced([w])
        defer { c.saveWork?.cancel(); c.isPaused = true }
        // A size you chose, then a change every 0.4s after it (a window scan every second or two,
        // while an app's window isn't takeable yet, calls for a save each time).
        w.preferredSize = CGSize(width: 1512, height: 949)
        for _ in 0..<4 {
            c.scheduleSave()
            try await Task.sleep(for: .milliseconds(400))
        }
        // 1.6s in, with changes still coming: saved, with the size you chose.
        let saved = LayoutStore.load()?.windows.first { $0.id == 4301 }
        #expect(saved?.pw == 1512 && saved?.ph == 949)
    }
}
