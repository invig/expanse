import AppKit

/// The manual cases in docs/regression/spaces-and-full-screen.md. The full-screen app (Safari in the catalogue)
/// is a window of Expanse Tests, so whether it has the keyboard can be asked directly; the canvas's other windows
/// are a fixture's. The Spaces are read from the window server as Expanse reads them (SpacesNow). A tile is
/// clicked where SpacesBar draws it when the case is about the click; otherwise expanse://space does what the
/// tile does. Every case ends with nothing full screen, back on the canvas's desktop.
@MainActor enum SPACES {
    static let cases: [Case] = [
        Case("SPACES-05", "⌥` over a full-screen app opens the canvas there", .look) { t in
            try await spacesScene(t, "Spaces05", showing: true) { sc in
                t.link("toggle")   // what ⌥` does
                try await t.until("the canvas open, zoomed out", timeout: 6) { let s = try await t.settle(); return s.active && s.scale < 1 }
                try t.expect(SpacesNow().current == sc.fsSpace, "opening the canvas left the full-screen window's Space")
                try t.expect(spacesCanvasUp(t), "Expanse's canvas isn't on screen over the full-screen window")
                let s = try await t.state()
                for id in sc.ids { try t.expect(s.window(id) != nil, "the canvas is missing the fixture's window [\(id)]") }
                let name = SpacesNow().list.first { $0.id == sc.fsSpace }?.name ?? "Expanse Tests"
                try await t.look("Over the full-screen window: the canvas with its windows, the minimap, and the Spaces panel with the “\(name)” tile ringed as the current Space?")
            }
        },
        Case("SPACES-06", "Clicking a full-screen app's tile actually switches to it") { t in
            try t.needsInput()
            try await spacesScene(t, "Spaces06", showing: false) { sc in
                let field = spacesTypingField(sc.fs)
                t.link("enter")
                try await t.until("zoomed out", timeout: 6) { let s = try await t.settle(); return s.active && s.scale < 1 }
                let p = try await spacesTile(t, sc.fsSpace)
                if let other = spacesCovering(t, p) { throw Failure("\(other) is in front of the full-screen app's tile") }
                let mark = t.log.mark()
                Input.click(at: p)
                try await spacesArrived(t, sc, typing: field, since: mark)
            }
        },
        Case("SPACES-07", "The Spaces panel works at 100% too") { t in
            try t.needsInput()
            try await spacesScene(t, "Spaces07", showing: false) { sc in
                let field = spacesTypingField(sc.fs)
                var p = try await spacesTile(t, sc.fsSpace)
                if spacesCovering(t, p) != nil {
                    // Windows over the panel: an empty part of the canvas, which puts them all out of view.
                    try await spacesEmptyView(t)
                    p = try await spacesTile(t, sc.fsSpace)
                }
                if let other = spacesCovering(t, p) { throw Skip("\(other) covers the Spaces panel at 100% (hide the Dock automatically to run this)") }
                let mark = t.log.mark()
                Input.click(at: p)
                // DIAGNOSTIC: a first click that reaches nothing (seen after the DISPLAY cases), and
                // whether a second one gets there.
                var second = "not needed"
                if await t.log.wait(since: mark, timeout: 2, { $0.hasPrefix("click at 100%") || $0.hasPrefix("switching from") }) == nil {
                    Input.click(at: p)
                    second = await t.log.wait(since: mark, timeout: 2, { $0.hasPrefix("click at 100%") || $0.hasPrefix("switching from") }) == nil
                        ? "lost too" : "reached Expanse"
                }
                do {
                    try await spacesArrived(t, sc, typing: field, since: mark)
                    if second != "not needed" { throw Failure("the first click on the tile reached nothing; a second \(second)") }
                } catch {
                    // Twice in complete runs the click switched nothing and logged nothing: say what was there.
                    let s = try? await t.state()
                    throw Failure("\(error) (clicked \(NSStringFromPoint(p)); a second click: \(second); in front there now: \(spacesCovering(t, p) ?? "Expanse"); "
                                  + "the panel's tiles: \(s.map { $0.spacesTiles.mapValues(NSStringFromRect).description } ?? "?"); "
                                  + "Expanse's windows: \(spacesExpanseWindows(t)); at the point, Accessibility finds \(spacesAXAt(p)))")
                }
            }
        },
        Case("SPACES-08", "Switching to another desktop from the Spaces panel", .guided) { t in
            let start = SpacesNow()
            guard let home = start.current, start.currentSpace?.fullScreen == false else { throw Skip("needs to start on a desktop") }
            let mine = try await t.window("SPACES-08 Mine")
            let away = try await t.window("SPACES-08 Away")
            try await t.ask("Open Mission Control, add a desktop if there's only one, and drag the window “SPACES-08 Away” onto another desktop. Close Mission Control, staying on this desktop, then click Done.")
            let now = SpacesNow()
            guard now.current == home, let there = spacesOf(away.id).first, there != home,
                  let desktop = now.list.first(where: { $0.id == there && !$0.fullScreen }) else {
                throw Skip("“SPACES-08 Away” isn't on another desktop, or you're not back on this one")
            }
            do {
                t.link("enter")
                try await t.until("zoomed out", timeout: 6) { let s = try await t.settle(); return s.active && s.scale < 1 }
                let mark = t.log.mark()
                t.link("space", ["name": desktop.name])   // what its tile does
                try await t.spacesLine("switching from Space \(home) to \(desktop.name) (\(there))", since: mark, timeout: 5)
                try await t.until("macOS on \(desktop.name)", timeout: 5) { SpacesNow().current == there }
                try await t.until("a window there in front, with the keyboard", timeout: 4) {
                    guard let front = spacesFrontWindow() else { return false }
                    let app = NSWorkspace.shared.frontmostApplication?.processIdentifier
                    return front.pid == app && (front.id != away.id || (NSApp.isActive && away.window.isKeyWindow))
                }
                try await t.spacesLine("Space switch done: on \(there)", since: mark, timeout: 4)
                let s = try await t.settle()
                try t.expect(!s.active, "the canvas should be back at 100%")
            } catch {
                await spacesBackTo(t, home, by: { mine.focus() })
                throw error
            }
            await spacesBackTo(t, home, by: { mine.focus() })
        },
        Case("SPACES-09", "Space switches are instant", .look) { t in
            try await spacesScene(t, "Spaces09", showing: false) { sc in
                spacesPointerOnMain()
                try await t.ask("Watch the screen: when you click Done, Expanse switches from here to the full-screen window's Space.")
                var mark = t.log.mark()
                try spacesLink(t, to: sc.fsSpace)   // its tile in the Spaces panel, at 100%
                let line = try await t.spacesLine("switching from Space", "(\(sc.fsSpace))", since: mark, timeout: 5)
                try t.expect(line.contains(", instantly"), "the switch wasn't the instant kind: \(line)")
                try await t.until("on the full-screen window's Space", timeout: 4) { SpacesNow().current == sc.fsSpace }
                try await t.look("Did the full-screen window appear at once, with no sliding animation?")
                t.link("toggle")
                try await t.until("the canvas open over it", timeout: 6) { let s = try await t.settle(); return s.active && s.scale < 1 }
                spacesPointerOnMain()
                try await t.ask("Watch again: when you click Done, Expanse goes from the canvas to its own desktop (its tile in the Spaces panel).")
                mark = t.log.mark()
                t.link("space", ["name": "expanse"])
                try await t.spacesLine("back to the canvas's Space, staying on the canvas", since: mark, timeout: 5)
                try await t.until("on the canvas's desktop", timeout: 4) { SpacesNow().current == sc.desktop }
                try await t.look("Did the desktop change under the canvas, with the canvas staying put and nothing sliding?")
            }
        },
        Case("SPACES-12", "Picking a window from the canvas over a full-screen app") { t in
            try await spacesScene(t, "Spaces12", showing: true) { sc in
                spacesPointerOnMain()
                t.link("toggle")
                try await t.until("the canvas open over the full-screen window", timeout: 6) { let s = try await t.settle(); return s.active && s.scale < 1 }
                let pick = sc.ids[0]
                let mark = t.log.mark()
                t.link("focus", ["id": pick])   // what clicking it on the canvas does
                try await t.spacesLine("switched to the canvas's desktop under the canvas", since: mark, timeout: 4)
                try await t.until("on the canvas's desktop", timeout: 3) { SpacesNow().current == sc.desktop }
                try await t.until("the picked window in front, with the keyboard", timeout: 4) {
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == sc.f.pid && spacesFrontWindow()?.id == pick
                }
                try await t.spacesViewOn(pick, "the view at 100% on the picked window")
            }
        },
        Case("SPACES-13", "Leaving the canvas without picking goes back to the full-screen app") { t in
            try await spacesScene(t, "Spaces13", showing: true) { sc in
                t.link("toggle")
                try await t.until("the canvas open over the full-screen window", timeout: 6) { let s = try await t.settle(); return s.active && s.scale < 1 }
                let mark = t.log.mark()
                t.link("exit")   // what Esc does
                try await t.spacesLine("Space switch: window server focus", since: mark, timeout: 5)
                try await t.spacesLine("Space switch done: on \(sc.fsSpace)", since: mark, timeout: 5)
                try await t.until("on the full-screen window's Space", timeout: 3) { SpacesNow().current == sc.fsSpace }
                try await t.until("the full-screen window with the keyboard", timeout: 4) { NSApp.isActive && sc.fs.window.isKeyWindow }
                let s = try await t.settle()
                try t.expect(!s.active, "the canvas should be closed")
            }
        },
        Case("SPACES-14", "The Expanse tile, from over a full-screen app, keeps you on the canvas") { t in
            try t.needsInput()
            try await spacesScene(t, "Spaces14", showing: true) { sc in
                spacesPointerOnMain()
                t.link("toggle")
                try await t.until("the canvas open over the full-screen window", timeout: 6) { let s = try await t.settle(); return s.active && s.scale < 1 }
                // 1: the Expanse tile.
                let p = try await spacesTile(t, sc.desktop)
                let mark = t.log.mark()
                Input.click(at: p)
                try await t.spacesLine("back to the canvas's Space, staying on the canvas", since: mark, timeout: 4)
                try await t.until("on the canvas's desktop", timeout: 3) { SpacesNow().current == sc.desktop }
                try await t.until("the canvas with the keyboard", timeout: 3) {
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == t.expanse?.processIdentifier
                }
                try t.expect(spacesCanvasUp(t), "the canvas isn't on screen on the desktop")
                var s = try await t.settle()
                try t.expect(s.active && s.scale < 1, "the canvas should stay open, zoomed out")
                // 2: 0 fits everything (moved off it first, so the key has something to do).
                t.link("pan", ["dx": 900, "dy": 600])
                s = try await t.settle()
                Input.key(.zero)
                try await t.until("0 to fit everything", timeout: 4) {
                    let s = try await t.settle()
                    guard s.active, let first = s.windows.first else { return false }
                    let all = s.windows.reduce(first.canvas) { $0.union($1.canvas) }
                    let near = max(4, 2 / s.scale)
                    return abs(s.visibleCanvas.midX - all.midX) <= near && abs(s.visibleCanvas.midY - all.midY) <= near
                }
                // Then a click on a window zooms into it.
                let pick = sc.ids[0]
                s = try await t.state()
                guard var w = s.window(pick) else { throw Failure("the fixture's window isn't on the canvas") }
                if s.clickPoint(on: w.canvas) == nil {
                    // All under the panels in the corner: into the middle of the screen first.
                    let c = s.screenPoint(CGPoint(x: w.canvas.midX, y: w.canvas.midY))
                    t.link("pan", ["dx": Int(s.viewport.midX - c.x), "dy": Int(s.viewport.midY - c.y)])
                    s = try await t.settle()
                    guard let moved = s.window(pick) else { throw Failure("the fixture's window isn't on the canvas") }
                    w = moved
                }
                guard let p = s.clickPoint(on: w.canvas) else { throw Failure("no part of the fixture's window is clear to click: \(w.canvas)") }
                Input.click(at: p)
                try await t.spacesViewOn(pick, "the view at 100% on the window clicked")
            }
        },
        Case("SPACES-15", "The canvas comes along to the desktop and keeps the keyboard", .guided) { t in
            try t.needsInput()
            try await spacesScene(t, "Spaces15", showing: true) { sc in
                t.link("toggle")
                try await t.until("the canvas open over the full-screen window", timeout: 6) { let s = try await t.settle(); return s.active && s.scale < 1 }
                try await t.ask("Swipe between Spaces on the trackpad (three or four fingers, as Trackpad settings say) to the desktop with the canvas's windows. Not ⌃→: that's Expanse's. Then click Done.")
                try await t.until("on the canvas's desktop", timeout: 4) { SpacesNow().current == sc.desktop }
                try await t.pause(0.5)
                try t.expect(spacesCanvasUp(t), "the canvas isn't on screen on the desktop")
                try await t.until("the canvas with the keyboard", timeout: 3) {
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == t.expanse?.processIdentifier
                }
                let s = try await t.settle()
                try t.expect(s.active && s.scale < 1, "the canvas should still be open, zoomed out")
                // macOS can list the canvas as on screen without drawing it (the bug): only you can see that.
                try await t.look("Is the zoomed-out canvas showing here on the desktop (not the plain desktop)?")
                Input.key(.escape)
                try await t.until("Esc to close the canvas", timeout: 4) { try await !t.settle().active }
            }
        },
        Case("SPACES-22", "A window back from full screen gets the view") { t in
            let start = SpacesNow()
            guard let desktop = start.current, start.currentSpace?.fullScreen == false else { throw Skip("needs to start on a desktop") }
            let f = try await t.fixture("Spaces22")
            guard let other = f.windows.first else { throw Failure("the fixture has no window") }
            try await t.until("Expanse to take on the fixture's window") { try await t.state().window(other) != nil }
            let a = try await t.window("SPACES-22 A")
            try await t.spacesPlace([(a.id, spacesAt(0, 0)), (other, spacesAt(6000, 0))])
            let s0 = try await t.spacesShow(a.id)
            guard let spot = s0.window(a.id)?.canvas else { throw Failure("A isn't on the canvas") }
            do {
                // 1: A in full screen.
                let fsSpace = try await spacesFullScreen(t, a)
                // 2: back to the canvas's desktop (A leaves the canvas while it's full screen), and a hop away from its spot.
                try await spacesGo(t, to: desktop, "back on the canvas's desktop")
                try await t.until("A off the canvas while it's full screen", timeout: 12) { try await t.state().window(a.id) == nil }
                try await t.spacesShow(other)
                // 3: zoomed out, A's tile, then ⌃⌘F.
                spacesPointerOnMain()
                t.link("enter")
                try await t.until("zoomed out", timeout: 6) { let s = try await t.settle(); return s.active && s.scale < 1 }
                try spacesLink(t, to: fsSpace)
                try await t.until("on A's Space", timeout: 6) { SpacesNow().current == fsSpace }
                try await t.pause(0.8)
                let mark = t.log.mark()
                a.toggleFullScreen()
                try await t.until("A out of full screen, on the desktop", timeout: 12) {
                    !a.window.styleMask.contains(.fullScreen) && SpacesNow().current == desktop
                }
                try await t.spacesLine("[\(a.id)] back from full screen", since: mark, timeout: 8)
                try await t.spacesLine("glide to ", "[\(a.id)]", since: mark, timeout: 5)
                try await t.until("A with the keyboard", timeout: 4) { NSApp.isActive && a.window.isKeyWindow }
                let s = try await t.spacesViewOn(a.id, "the view gliding to A")
                try t.expectNear(s.window(a.id)?.canvas ?? .zero, spot, within: 2, "A on the canvas (its own spot, not where macOS set it down)")
            } catch {
                await spacesTidy(t, home: desktop, fullScreen: [a])
                throw error
            }
            await spacesTidy(t, home: desktop, fullScreen: [a])
        },
        Case("SPACES-23", "A window back from full screen keeps its spot") { t in
            let start = SpacesNow()
            guard let desktop = start.current, start.currentSpace?.fullScreen == false else { throw Skip("needs to start on a desktop") }
            // A (Calendar in the catalogue) with neighbours either side.
            let ws = try await t.row(["SPACES-23 Left", "SPACES-23 A", "SPACES-23 Right"], origin: spacesAt(0, 0))
            let a = ws[1]
            try await t.spacesShow(a.id)
            let before = try await t.settle()
            do {
                // 1: the green button; wait.
                _ = try await spacesFullScreen(t, a)
                try await t.pause(2)
                // 2: out of full screen.
                let mark = t.log.mark()
                a.toggleFullScreen()
                try await t.until("A out of full screen, on the desktop", timeout: 12) {
                    !a.window.styleMask.contains(.fullScreen) && SpacesNow().current == desktop
                }
                // 3: 10s, then zoom out.
                try await t.pause(10)
                t.link("enter")
                let s = try await t.settle()
                for w in ws {
                    guard let was = before.window(w.id)?.canvas, let now = s.window(w.id)?.canvas else { throw Failure("\(w.title) left the canvas") }
                    try t.expectNear(now, was, within: 1, "\(w.title) after A's full screen")
                }
                let followed = t.spacesLines("follow ", "[\(a.id)]", since: mark)
                try t.expect(followed.isEmpty, "A's spot was taken from where macOS set it down: \(followed.first ?? "")")
                t.link("exit")
                try await t.until("back at 100%") { try await !t.settle().active }
            } catch {
                await spacesTidy(t, home: desktop, fullScreen: [a])
                throw error
            }
            await spacesTidy(t, home: desktop, fullScreen: [a])
        },
        Case("SPACES-24", "Clicking Expanse's own Space tile goes back to 100%") { t in
            try t.needsInput()
            // The full-screen window gives the Spaces panel a second tile; you stay on the desktop.
            try await spacesScene(t, "Spaces24", showing: false) { sc in
                // Nothing over the panel at 100% (for step 3): an empty part of the canvas.
                try await spacesEmptyView(t)
                let home = try await t.settle()
                // 1–2: zoom out, the Expanse tile.
                t.link("enter")
                try await t.until("zoomed out", timeout: 6) { let s = try await t.settle(); return s.active && s.scale < 1 }
                var mark = t.log.mark()
                Input.click(at: try await spacesTile(t, sc.desktop))
                try await t.until("2: back at 100%", timeout: 4) { try await !t.settle().active }
                var s = try await t.settle()
                try t.expectNear(s.camera, home.camera, within: 2, "2: the view you left")
                try t.expect(t.spacesLines("switching from Space", since: mark).isEmpty, "2: the Expanse tile ran a Space switch")
                // 3: at 100%, the Expanse tile again: nothing happens.
                let p = try await spacesTile(t, sc.desktop)
                if let other = spacesCovering(t, p) { throw Skip("\(other) covers the Spaces panel at 100% (hide the Dock automatically to run this)") }
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                mark = t.log.mark()
                Input.click(at: p)
                try await t.pause(1.5)
                let nowFront = NSWorkspace.shared.frontmostApplication
                try t.expect(nowFront?.processIdentifier == front || nowFront?.processIdentifier == t.expanse?.processIdentifier,
                             "3: focus moved, to \(nowFront?.localizedName ?? "-")")
                let moved = t.spacesLines("switching from Space", since: mark) + t.spacesLines("glide to ", since: mark)
                try t.expect(moved.isEmpty, "3: the Expanse tile at 100% did something: \(moved.first ?? "")")
                s = try await t.settle()
                try t.expect(!s.active, "3: the canvas opened")
                try t.expectNear(s.camera, home.camera, within: 1, "3: the view")
                // 4: zoom out, then expanse://space?name=Expanse.
                t.link("enter")
                try await t.until("zoomed out", timeout: 6) { let s = try await t.settle(); return s.active && s.scale < 1 }
                t.link("space", ["name": "Expanse"])
                try await t.until("4: back at 100%", timeout: 4) { try await !t.settle().active }
                s = try await t.settle()
                try t.expectNear(s.camera, home.camera, within: 2, "4: the view you left")
            }
        },
    ]
}

// MARK: Spaces, as the window server lists them

@_silgen_name("CGSMainConnectionID") private func spacesConnection() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func spacesManagedDisplaySpaces(_ cid: Int32) -> CFArray?
@_silgen_name("CGSCopySpacesForWindows") private func spacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> CFArray?

/// The main display's Spaces as Expanse lists them (Spaces.list: desktops and full-screen apps, in Mission
/// Control's order, named the same way), read as it reads them, and the one showing. The Spaces panel has a tile
/// for each, in this order.
private struct SpacesNow {
    struct Space {
        let id: UInt64
        let fullScreen: Bool
        /// "Desktop", "Desktop 2", or the full-screen app's name.
        let name: String
        /// A full-screen Space's windows (two in split view).
        let windows: [CGWindowID]
    }
    var list: [Space] = []
    var current: UInt64?

    var currentSpace: Space? { list.first { $0.id == current } }

    init() {
        let displays = spacesManagedDisplaySpaces(spacesConnection()) as? [[String: Any]] ?? []
        let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID()).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        guard let display = displays.first(where: { ($0["Display Identifier"] as? String) == uuid })
                ?? displays.first(where: { ($0["Display Identifier"] as? String) == "Main" }) ?? displays.first else { return }
        func spaceID(_ s: [String: Any]) -> UInt64? {
            (s["id64"] as? NSNumber)?.uint64Value ?? (s["ManagedSpaceID"] as? NSNumber)?.uint64Value
        }
        let raw = display["Spaces"] as? [[String: Any]] ?? []
        let desktops = raw.filter { ($0["type"] as? Int) == 0 }.count
        var n = 0
        for s in raw {
            guard let id = spaceID(s) else { continue }
            switch s["type"] as? Int {
            case 0:
                n += 1
                list.append(Space(id: id, fullScreen: false, name: desktops > 1 ? "Desktop \(n)" : "Desktop", windows: []))
            case 4:
                let tiles = (s["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]] ?? []
                guard let pid = (s["pid"] as? NSNumber)?.int32Value ?? (tiles.first?["pid"] as? NSNumber)?.int32Value else { continue }
                var windows = tiles.compactMap { ($0["TileWindowID"] as? NSNumber)?.uint32Value }
                if let w = (s["fs_wid"] as? NSNumber)?.uint32Value, !windows.contains(w) { windows.append(w) }
                let names = tiles.compactMap { $0["appName"] as? String }
                let name = names.isEmpty ? NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Full Screen" : names.joined(separator: " & ")
                list.append(Space(id: id, fullScreen: true, name: name, windows: windows))
            default:
                continue
            }
        }
        current = (display["Current Space"] as? [String: Any]).flatMap(spaceID)
    }
}

/// The Spaces a window is on (usually one).
private func spacesOf(_ id: CGWindowID) -> [UInt64] {
    let ids = spacesForWindows(spacesConnection(), 0x7, [NSNumber(value: id)] as CFArray) as? [NSNumber]
    return (ids ?? []).map(\.uint64Value)
}

// MARK: The scene most cases start from

/// A fixture's windows on the canvas, and a window of Expanse Tests full screen on a Space of its own.
@MainActor private struct SpacesScene {
    let f: Fixture
    /// The fixture's windows, on the canvas.
    let ids: [CGWindowID]
    let fs: TestWindow
    /// The canvas's desktop, and the full-screen window's Space.
    let desktop: UInt64
    let fsSpace: UInt64
}

/// Sets up a SpacesScene, runs `body` in it, and puts things back: canvas closed, nothing full screen, on the
/// canvas's desktop. As in the catalogue's setups, the full-screen window went full screen a while ago: you've
/// been back on the desktop since (where a scan takes it off the canvas). `showing`: then on its Space again.
@MainActor private func spacesScene(_ t: Ctx, _ name: String, showing: Bool, _ body: (SpacesScene) async throws -> Void) async throws {
    let start = SpacesNow()
    guard let desktop = start.current, start.currentSpace?.fullScreen == false else {
        throw Skip("needs to start on a desktop, not a full-screen app's Space")
    }
    // Not straight after a display change (DISPLAY-18 runs just before these): while Expanse
    // settles, a click on its Spaces bar at 100% doesn't reach it in the VM (README, Questions).
    try await t.until("Expanse to settle after the last display change", timeout: 30) { try await !t.state().settling }
    let f = try await t.fixture(name, windows: 2)
    let ids = f.windows
    try await t.until("Expanse to take on \(name)'s windows", timeout: 10) {
        let s = try await t.state()
        return ids.count == 2 && ids.allSatisfy { s.window($0) != nil }
    }
    let fs = try await t.window("\(name) Full screen")
    try await t.settle()
    do {
        let fsSpace = try await spacesFullScreen(t, fs)
        // Back on the desktop (the way Expanse's Spaces panel takes you there).
        try await spacesGo(t, to: desktop, "back on the canvas's desktop")
        try await t.until("Expanse to leave the full-screen window off the canvas", timeout: 12) { try await t.state().window(fs.id) == nil }
        if showing { try await spacesGo(t, to: fsSpace, "on the full-screen window's Space", by: { fs.focus() }) }
        try await body(SpacesScene(f: f, ids: ids, fs: fs, desktop: desktop, fsSpace: fsSpace))
    } catch {
        await spacesTidy(t, home: desktop, fullScreen: [fs])
        throw error
    }
    await spacesTidy(t, home: desktop, fullScreen: [fs])
}

/// Puts `w` in full screen and waits until macOS shows it on a Space of its own. Returns that Space.
@MainActor private func spacesFullScreen(_ t: Ctx, _ w: TestWindow) async throws -> UInt64 {
    w.focus()
    w.toggleFullScreen()
    var space: UInt64 = 0
    try await t.until("“\(w.title)” full screen on a Space of its own", timeout: 12) {
        let now = SpacesNow()
        guard w.window.styleMask.contains(.fullScreen), let s = now.list.first(where: { $0.fullScreen && $0.windows.contains(w.id) }),
              now.current == s.id else { return false }
        space = s.id
        return true
    }
    // macOS animates the move to the new Space for about a second.
    try await t.pause(1.2)
    return space
}

/// Takes `w` out of full screen, if it is, and waits until it's back on its desktop.
@MainActor private func spacesLeaveFullScreen(_ t: Ctx, _ w: TestWindow) async throws {
    guard w.window.styleMask.contains(.fullScreen) else { return }
    // From its own Space, as a person would. Toggled from the desktop, once in the VM (1 Nov)
    // Expanse and the runner both stopped for 140s as it came back.
    if let space = SpacesNow().list.first(where: { $0.fullScreen && $0.windows.contains(w.id) })?.id {
        try? await spacesGo(t, to: space, "on “\(w.title)”'s Space", by: { w.focus() })
    }
    w.toggleFullScreen()
    try await t.until("“\(w.title)” out of full screen", timeout: 12) {
        !w.window.styleMask.contains(.fullScreen) && !SpacesNow().list.contains { $0.windows.contains(w.id) }
    }
    try await t.pause(1.2)
}

/// Gets macOS onto `space`: `action` first if given (focusing a window there, say), then, if that didn't, Expanse's
/// own expanse://space link. (Activating an app doesn't do it: macOS brings the app forward on the Space you're on.)
@MainActor private func spacesGo(_ t: Ctx, to space: UInt64, _ what: String, by action: (() -> Void)? = nil) async throws {
    if SpacesNow().current == space { return }
    var there = false
    if let action {
        action()
        there = (try? await t.until(what, timeout: 4) { SpacesNow().current == space }) != nil
    }
    if !there {
        try spacesLink(t, to: space)
        try await t.until(what, timeout: 6) { SpacesNow().current == space }
    }
    try await t.pause(0.8)
}

/// expanse://space?index=: what clicking the Space's tile does.
@MainActor private func spacesLink(_ t: Ctx, to space: UInt64) throws {
    guard let i = SpacesNow().list.firstIndex(where: { $0.id == space }) else { throw Failure("Space \(space) isn't in Mission Control any more") }
    t.link("space", ["index": i + 1])
}

/// Back to 100%, nothing full screen, on `home`. Never throws: it's tidying up after a case.
@MainActor private func spacesTidy(_ t: Ctx, home: UInt64, fullScreen: [TestWindow]) async {
    if (try? await t.state())?.active == true {
        t.link("exit")
        _ = try? await t.until("back at 100%", timeout: 5) { try await !t.state().active }
    }
    for w in fullScreen { try? await spacesLeaveFullScreen(t, w) }
    await spacesBackTo(t, home)
    _ = try? await t.settle()
}

/// Back on `home`, by `action`, Expanse's link, or (when a person is there) asking.
@MainActor private func spacesBackTo(_ t: Ctx, _ home: UInt64, by action: (() -> Void)? = nil) async {
    if (try? await spacesGo(t, to: home, "back on the desktop the case started on", by: action)) != nil { return }
    try? await t.ask("Go back to the desktop this case started on (the canvas's), then click Done.")
}

// MARK: Checks and other helpers

/// SPACES-06 and 07: a click on the full-screen app's tile switched to it at once, and its window has the keyboard.
@MainActor private func spacesArrived(_ t: Ctx, _ sc: SpacesScene, typing field: NSTextField, since mark: Int) async throws {
    let line = try await t.spacesLine("switching from Space \(sc.desktop) to ", "(\(sc.fsSpace))", since: mark, timeout: 5)
    try t.expect(line.contains(", instantly"), "the switch wasn't the instant kind (the pointer's on the main display): \(line)")
    try await t.spacesLine("Space switch: window server focus true, window found", since: mark, timeout: 5)
    try await t.until("macOS showing the full-screen window's Space", timeout: 4) { SpacesNow().current == sc.fsSpace }
    try await t.until("the full-screen window with the keyboard", timeout: 4) { NSApp.isActive && sc.fs.window.isKeyWindow }
    for k: Input.Key in [.a, .c, .a, .w] { Input.key(k) }
    try await t.until("the typing in the full-screen window", timeout: 3) { field.stringValue == "acaw" }
    try await t.spacesLine("Space switch done: on \(sc.fsSpace)", since: mark, timeout: 4)
    let s = try await t.settle()
    try t.expect(!s.active, "the canvas should be back at 100%")
}

/// Somewhere on the canvas with nothing on it, far from your windows and the cases'.
private func spacesAt(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: -70000 + dx, y: -45000 + dy) }

/// The middle of the Spaces panel's tile for `space`, as SpacesBar and CanvasView lay it out: tiles 100pt wide and
/// 14pt apart, 14pt in from the panel's edges, the panel 12pt left of the 208pt minimap, 16pt in from the screen's
/// bottom-right corner, the tiles' middles 83.5pt up from the bottom.
@MainActor private func spacesTile(_ t: Ctx, _ space: UInt64) async throws -> CGPoint {
    // Where Expanse has it (expanse://dump), once its panel has caught up with the Space.
    var tile: CGRect?
    var shown: [UInt64] = []
    do {
        try await t.until("Expanse's Spaces panel to show Space \(space)", timeout: 3) {
            let s = try await t.state()
            shown = s.spacesTiles.keys.sorted()
            tile = s.spacesTiles[space]
            return tile != nil
        }
    } catch {
        throw Failure("Expanse's Spaces panel has no tile for Space \(space) (it shows \(shown.isEmpty ? "none: hidden" : "\(shown)"))")
    }
    guard let tile else { throw Failure("no tile for Space \(space)") }
    return CGPoint(x: tile.midX, y: tile.midY)
}

/// What's in front at `p` (global), as the window server stacks windows: nil if it's Expanse's (the canvas, or its
/// panels on the desktop at 100%), else whose window it is. The pointer is the window server's own window, and
/// doesn't count: a click on a tile (SPACES-06) leaves it there.
@MainActor private func spacesCovering(_ t: Ctx, _ p: CGPoint) -> String? {
    let expanse = t.expanse?.processIdentifier
    let pointer = Int(CGWindowLevelForKey(.cursorWindow))
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in info {
        guard let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b), r.contains(p),
              (w[kCGWindowAlpha as String] as? Double ?? 1) > 0, (w[kCGWindowLayer as String] as? Int ?? 0) < pointer else { continue }
        if (w[kCGWindowOwnerPID as String] as? pid_t) == expanse { return nil }
        return w[kCGWindowOwnerName as String] as? String ?? "a window"
    }
    return "nothing of Expanse's"
}

/// Moves the view at 100% to an empty part of the canvas, which puts every window out of view: nothing then
/// covers the minimap or the Spaces panel on the desktop.
@MainActor private func spacesEmptyView(_ t: Ctx) async throws {
    t.link("enter", ["zoomOut": 0])
    try await t.until("the canvas open at 100%", timeout: 5) { try await t.settle().active }
    t.link("pan", ["dx": 60000, "dy": 60000])
    try await t.pause(0.3)
    t.link("exit")
    try await t.until("back at 100% with every window out of view", timeout: 8) {
        let s = try await t.settle()
        return !s.active && s.windows.allSatisfy(\.parked)
    }
}

/// Expanse's instant switch needs the pointer on the main display.
private func spacesPointerOnMain() {
    guard let main = NSScreen.screens.first?.frame, !main.contains(NSEvent.mouseLocation) else { return }
    CGWarpMouseCursorPosition(CGPoint(x: main.width / 2, y: main.height / 2))
}

/// The front-most ordinary window on screen and its owner, as the window server stacks them.
private func spacesFrontWindow() -> (id: CGWindowID, pid: pid_t)? {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
        guard let id = w[kCGWindowNumber as String] as? CGWindowID, let pid = w[kCGWindowOwnerPID as String] as? pid_t,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
              r.width >= 100, r.height >= 60, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
        return (id, pid)
    }
    return nil
}

/// Whether Expanse's canvas is up: its overlay on screen above app windows (at 100% it's under them).
@MainActor private func spacesCanvasUp(_ t: Ctx) -> Bool {
    guard let pid = t.expanse?.processIdentifier else { return false }
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.contains { w in
        guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid, (w[kCGWindowLayer as String] as? Int ?? 0) > 0,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) else { return false }
        return r.width >= t.screen.width - 1
    }
}

/// A text field filling `w`, ready for typing: what's typed while `w` has the keyboard lands in it.
@MainActor private func spacesTypingField(_ w: TestWindow) -> NSTextField {
    let field = NSTextField(string: "")
    field.isEditable = true
    field.font = .systemFont(ofSize: 18)
    if let content = w.window.contentView {
        field.frame = content.bounds.insetBy(dx: 16, dy: 16)
        field.autoresizingMask = [.width, .height]
        content.addSubview(field)
    }
    w.window.makeFirstResponder(field)
    return field
}

@MainActor fileprivate extension Ctx {
    /// The first log line since `mark` with every one of `parts` in it.
    @discardableResult
    func spacesLine(_ parts: String..., since mark: Int, timeout: TimeInterval = 8) async throws -> String {
        guard let line = await log.wait(since: mark, timeout: timeout, { l in parts.allSatisfy { l.contains($0) } }) else {
            throw Failure("no log line with “\(parts.joined(separator: "…"))”")
        }
        return line
    }

    /// Every log line since `mark` with every one of `parts` in it.
    func spacesLines(_ parts: String..., since mark: Int) -> [String] {
        log.lines(since: mark).filter { l in parts.allSatisfy { l.contains($0) } }
    }

    /// Puts windows at canvas spots (expanse://place, committed) and waits until they're there.
    func spacesPlace(_ spots: [(CGWindowID, CGPoint)]) async throws {
        for (id, p) in spots { link("place", ["id": id, "x": Int(p.x), "y": Int(p.y), "commit": 1]) }
        try await until("windows at their spots on the canvas", timeout: 10) {
            let s = try await settle()
            return spots.allSatisfy { spot in
                s.window(spot.0).map { hypot($0.canvas.minX - spot.1.x, $0.canvas.minY - spot.1.y) < 1.5 } ?? false
            }
        }
    }

    /// Glides the view onto a window (expanse://focus?id=), and waits until it's in the middle.
    @discardableResult
    func spacesShow(_ id: CGWindowID) async throws -> ExpanseState {
        link("focus", ["id": id])
        return try await spacesViewOn(id, "the view to glide to [\(id)]")
    }

    /// Waits until the view is at 100% with the window in the middle.
    @discardableResult
    func spacesViewOn(_ id: CGWindowID, _ what: String, timeout: TimeInterval = 8) async throws -> ExpanseState {
        var last = ExpanseState(lines: [])
        try await until(what, timeout: timeout) {
            last = try await settle()
            // As a glide leaves it: the window in the middle, or its screen group framed.
            return !last.active && last.isViewOn(id, within: 4)
        }
        return last
    }
}

/// Expanse's windows on screen, front first, as the window server has them: level and bounds.
@MainActor private func spacesExpanseWindows(_ t: Ctx) -> String {
    let pid = t.expanse?.processIdentifier
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }.map { w in
        let b = (w[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
        return "layer \(w[kCGWindowLayer as String] as? Int ?? 0) \(NSStringFromRect(b)) alpha \(w[kCGWindowAlpha as String] as? Double ?? 1)"
    }.joined(separator: ", ")
}

/// The Accessibility element at `p` (global): its app and role.
private func spacesAXAt(_ p: CGPoint) -> String {
    var element: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &element) == .success,
          let element else { return "nothing" }
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
    return "\(app) \(role as? String ?? "?")"
}
