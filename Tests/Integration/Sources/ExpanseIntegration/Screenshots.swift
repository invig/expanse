import AppKit

/// The screenshots in the README (docs/screenshots), taken in the VM: stock apps laid out on the
/// canvas, each feature driven with real input as the cases drive it, and a picture of the screen
/// at the moment that shows it. `--shots` takes them all, `--shots overview,tidy` only those.
/// scripts/screenshots.sh runs it and puts the pictures in place.
@MainActor final class Shots {
    private struct Spot {
        let app: String
        /// What `open` is given to bring it up.
        let open: [String]
        let frame: CGRect
    }

    private static let documents = NSHomeDirectory() + "/Documents"
    private static let scene = [
        Spot(app: "Safari", open: ["-a", "Safari", "https://en.wikipedia.org/wiki/Lisbon"], frame: CGRect(x: 0, y: 0, width: 900, height: 800)),
        Spot(app: "Maps", open: ["-a", "Maps", "maps://?q=Lisbon"], frame: CGRect(x: 920, y: 0, width: 660, height: 800)),
        Spot(app: "Calendar", open: ["-a", "Calendar"], frame: CGRect(x: 1780, y: 0, width: 900, height: 640)),
        Spot(app: "Weather", open: ["-a", "Weather"], frame: CGRect(x: 2880, y: 0, width: 760, height: 580)),
        Spot(app: "Notes", open: ["-a", "Notes"], frame: CGRect(x: 0, y: 960, width: 760, height: 540)),
        Spot(app: "TextEdit", open: ["-a", "TextEdit", documents + "/Demo/Trip plan.txt"], frame: CGRect(x: 780, y: 960, width: 520, height: 540)),
        Spot(app: "Clock", open: ["-a", "Clock"], frame: CGRect(x: 1500, y: 860, width: 760, height: 640)),
        Spot(app: "Chess", open: ["-a", "Chess"], frame: CGRect(x: 2460, y: 720, width: 700, height: 620)),
        Spot(app: "Font Book", open: ["-a", "Font Book"], frame: CGRect(x: 1500, y: 1560, width: 860, height: 560)),
        Spot(app: "Finder", open: [documents], frame: CGRect(x: 2560, y: 1500, width: 700, height: 460)),
    ]

    private let t: Ctx
    private let out: URL
    private let say: (String) -> Void
    private var ids: [String: CGWindowID] = [:]

    init(t: Ctx, out: URL, say: @escaping (String) -> Void) {
        self.t = t
        self.out = out
        self.say = say
    }

    /// Takes the shots; true if they all worked. A report beside them says which didn't.
    func run(only: Set<String>?) async -> Bool {
        var report = "# Screenshots\n\n| Shot | Result |\n|---|---|\n"
        do {
            // Slowed, so a picture can catch a glide halfway.
            setExpanseDefault("animationSlowdown", 6.0)
            try await t.relaunchExpanse()
            try await setUp()
        } catch {
            say("couldn't set up: \(error)")
            try? (report + "| set-up | FAILED |\n").write(to: out.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
            return false
        }
        var allWorked = true
        for (name, take) in shots where only?.contains(name) ?? true {
            do {
                // Screen Recording asking again, say: it takes the clicks and spoils the picture.
                if let prompt = macOSPromptOnScreen() { say("waiting for an answer to: \(prompt)") }
                try await t.until("macOS's prompt answered", timeout: 900) { macOSPromptOnScreen() == nil }
                try await reset()
                try await take()
                say("ok   \(name)")
                report += "| \(name) | ok |\n"
            } catch {
                allWorked = false
                say("FAIL \(name) — \(error)")
                report += "| \(name) | FAILED |\n"
            }
        }
        try? await reset()
        setExpanseDefault("animationSlowdown", nil)
        try? report.write(to: out.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        return allWorked
    }

    private var shots: [(String, () async throws -> Void)] {
        [("overview", overview), ("group", group), ("glide", glide), ("hop", hop), ("zoom", zoom), ("snap", snap),
         ("tile", tile), ("select", select), ("resize", resize), ("sizes", sizes), ("tidy", tidy), ("spaces", spaces),
         ("menu", menu), ("paused", paused), ("welcome", welcome)]
    }

    // MARK: The shots

    private func overview() async throws {
        let s = try await zoomOut()
        Input.glide(to: CGPoint(x: s.viewport.minX + 60, y: s.viewport.maxY - 60))
        try await picture("overview")
    }

    /// Hovering a group outlines it; a click on it frames it at 100%.
    private func group() async throws {
        let s = try await zoomOut()
        let p = s.editCentre(try s.editFrame(id("Safari")))
        Input.glide(to: p)
        try await t.pause(0.8)
        try await picture("group-hover")
        Input.click(at: p)
        try await t.until("back at 100%", timeout: 15) { !(try await self.t.settle(timeout: 15).active) }
        try await t.pause(1)
        try await picture("group-screen")
    }

    private func glide() async throws {
        let s = try await zoomOut()
        let p = s.editCentre(try s.editFrame(id("Calendar")))
        Input.glide(to: p)
        Input.click(at: p)
        try await t.pause(0.2)
        try await picture("glide")
    }

    /// From Safari: Maps first, on screen in its group, so only the focus moves; then the glide to Calendar.
    private func hop() async throws {
        try await bringForward("Safari")
        t.link("nav", ["dir": "right"])
        try await t.pause(1)
        _ = try await t.settle(timeout: 15)
        t.link("nav", ["dir": "right"])
        try await picture("hop")
    }

    private func zoom() async throws {
        let s = try await t.editZoomOut(on: CGPoint(x: 1500, y: 620), scale: 0.6)
        Input.glide(to: s.screenPoint(CGPoint(x: 1400, y: 880)))
        try await t.pause(1)
        try await picture("zoom")
    }

    /// Chess, dragged to just off a neat gap beside Clock, its top nearly level: it snaps there.
    private func snap() async throws {
        let s = try await zoomOut()
        let chess = try s.editFrame(id("Chess")), clock = try s.editFrame(id("Clock"))
        let from = s.editCentre(chess)
        let to = s.screenPoint(CGPoint(x: clock.maxX + 26 + chess.width / 2, y: clock.minY + 8 + chess.height / 2))
        let drag = EditDrag(from: from)
        defer { drag.release() }
        await drag.move(to: to, steps: 40)
        try await t.pause(0.5)
        try await picture("snap")
    }

    /// Notes, dropped on Calendar's right side: the two become a screen.
    private func tile() async throws {
        let s = try await zoomOut()
        let calendar = try s.editFrame(id("Calendar"))
        let drag = EditDrag(from: s.editCentre(try s.editFrame(id("Notes"))))
        defer { drag.release() }
        await drag.move(to: s.screenPoint(CGPoint(x: calendar.maxX - calendar.width * 0.1, y: calendar.midY)), steps: 40)
        try await t.pause(0.5)
        try await picture("tile-drop")
        drag.release()
        let after = try await t.settle(timeout: 15)
        try await t.pause(1)
        Input.click(at: after.editCentre(try after.editFrame(id("Calendar"))))
        try await t.until("back at 100%", timeout: 15) { !(try await self.t.settle(timeout: 15).active) }
        try await t.pause(1)
        try await picture("tile-screen")
    }

    /// A box dragged from empty canvas across Notes, TextEdit and Clock, then S for a layout.
    private func select() async throws {
        let s = try await zoomOut()
        let drag = EditDrag(from: s.screenPoint(CGPoint(x: 40, y: 1540)))
        defer { drag.release() }
        await drag.move(to: s.screenPoint(CGPoint(x: 1900, y: 1150)), steps: 60)
        try await t.pause(0.5)
        try await picture("select-box")
        drag.release()
        try await t.pause(0.5)
        Input.glide(to: s.screenPoint(CGPoint(x: 400, y: 1800)))
        try await t.editKeysToCanvas()
        Input.key(.s)
        try await t.pause(0.8)
        try await picture("select-layouts")
        Input.key(.escape)
        try await t.pause(0.3)
        Input.key(.escape)
    }

    private func resize() async throws {
        let s = try await zoomOut()
        let f = try s.editFrame(id("Calendar"))
        let edge = s.screenPoint(CGPoint(x: f.maxX, y: f.midY))
        Input.glide(to: CGPoint(x: edge.x - 3, y: edge.y))
        let drag = EditDrag(from: CGPoint(x: edge.x - 3, y: edge.y))
        defer { drag.release() }
        await drag.move(to: CGPoint(x: edge.x + 50, y: edge.y), steps: 30)
        try await t.pause(0.5)
        try await picture("resize")
    }

    private func sizes() async throws {
        let s = try await zoomOut()
        let p = s.editCentre(try s.editFrame(id("Clock")))
        Input.glide(to: p)
        for type in [CGEventType.rightMouseDown, .rightMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .right)?.post(tap: .cghidEventTap)
            usleep(30_000)
        }
        try await t.pause(0.8)
        try await picture("sizes")
        Input.key(.escape)
    }

    /// Windows in pairs, unevenly spaced and out of line (close enough to count as groups), then T.
    private func tidy() async throws {
        let knocked: [String: CGPoint] = ["Maps": CGPoint(x: 934, y: 28), "TextEdit": CGPoint(x: 792, y: 934), "Weather": CGPoint(x: 2716, y: 34),
                                          "Chess": CGPoint(x: 2290, y: 844), "Finder": CGPoint(x: 2388, y: 1590)]
        for (app, p) in knocked { t.link("place", ["id": try id(app), "x": Int(p.x), "y": Int(p.y), "commit": 1]) }
        try await t.pause(1)
        let s = try await zoomOut()
        Input.glide(to: CGPoint(x: s.viewport.minX + 60, y: s.viewport.maxY - 60))
        try await picture("tidy-before")
        try await t.editKeysToCanvas()
        Input.key(.t)
        try await t.pause(1)
        _ = try await t.settle(timeout: 15)
        try await t.pause(1)
        try await picture("tidy-after")
    }

    /// TextEdit in a full-screen Space of its own, shown in the Spaces panel.
    private func spaces() async throws {
        try await bringForward("TextEdit")
        Input.key(.f, [.maskControl, .maskCommand])
        try await t.pause(4)
        t.link("space", ["name": "Expanse"])
        try await t.pause(4)
        let s = try await zoomOut()
        Input.glide(to: CGPoint(x: s.viewport.minX + 60, y: s.viewport.maxY - 60))
        try await t.pause(0.5)
        try await picture("spaces")
        t.link("exit")
        _ = try await t.settle(timeout: 15)
        t.link("space", ["name": "TextEdit"])
        try await untilInFront("TextEdit")
        try await t.pause(2)
        Input.key(.f, [.maskControl, .maskCommand])
        try await t.pause(4)
    }

    private func menu() async throws {
        t.link("menu")
        try await t.pause(1.5)
        try await picture("menu")
        Input.key(.escape)
    }

    private func paused() async throws {
        t.link("pause")
        try await t.untilPaused()
        try await t.pause(1.5)
        try await picture("paused")
        t.link("resume")
        try await t.until("resumed", timeout: 30) { !(try await self.t.state().paused) }
        _ = try await t.settle(timeout: 15)
    }

    private func welcome() async throws {
        t.link("welcome")
        try await t.pause(2)
        try await picture("welcome")
        if let e = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.invignation.expanse" })?.localizedName {
            for w in axWindows(e) { close(w) }
        }
    }

    // MARK: The scene

    private static let tripPlan = """
    Lisbon, three days

    Day 1
    - Alfama in the morning, tram 28 up to the castle
    - Lunch by the Sé
    - Sunset at Miradouro da Graça

    Day 2
    - Belém: the tower, the monastery, pastéis de nata
    - Back along the river to Cais do Sodré
    - Fado in the evening

    Day 3
    - Day trip to Sintra: Pena Palace, then the Moorish Castle
    - Back for dinner in Bairro Alto

    To book
    - Pena Palace tickets
    - Dinner on the last night
    - Airport transfer
    """

    private func setUp() async throws {
        // Every app quit first, these too, and started fresh (see launch): TextEdit would keep
        // showing what it had open, and a window left full screen would stay off the canvas.
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard app.localizedName != "Finder", app.processIdentifier != getpid(),
                  app.bundleIdentifier != "com.invignation.expanse" else { continue }
            app.forceTerminate()
        }
        try await t.pause(1)
        try Self.tripPlan.write(toFile: Self.documents + "/Demo/Trip plan.txt", atomically: true, encoding: .utf8)
        for spot in Self.scene { try launch(spot.open) }
        try await t.until("every app's window on the canvas", timeout: 60) {
            let s = try await self.t.state()
            return Self.scene.allSatisfy { spot in s.windows.contains { $0.app == spot.app } }
        }
        // One window each: an app may have brought back others from before.
        let opened = try await t.state()
        for spot in Self.scene where opened.windows.filter({ $0.app == spot.app }).count > 1 {
            for w in axWindows(spot.app).dropFirst() { close(w) }
        }
        try await t.until("one window each", timeout: 30) {
            let s = try await self.t.state()
            return Self.scene.allSatisfy { spot in s.windows.filter { $0.app == spot.app }.count == 1 }
        }
        let s = try await t.state()
        for spot in Self.scene { ids[spot.app] = s.windows.first { $0.app == spot.app }?.id }
        // Notes can open on an empty note: the packing list says more.
        try await reset()
        try await bringForward("Notes")
        let front = try await t.state()
        let notes = front.screenPoint(try front.editFrame(id("Notes")).origin)
        Input.click(at: CGPoint(x: notes.x + 320, y: notes.y + 187))
        try await t.pause(0.5)
    }

    /// Back to 100%, with every window at its spot and size.
    private func reset() async throws {
        let s = try await t.state()
        if s.active { t.link("exit") }
        try await t.until("back at 100%", timeout: 15) { !(try await self.t.settle(timeout: 15).active) }
        for spot in Self.scene {
            let id = try id(spot.app)
            t.link("prefer", ["id": id, "w": Int(spot.frame.width), "h": Int(spot.frame.height)])
            if let w = axWindows(spot.app).first {
                var size = spot.frame.size
                if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, v) }
            }
            t.link("place", ["id": id, "x": Int(spot.frame.minX), "y": Int(spot.frame.minY), "commit": 1])
        }
        try await t.pause(1.5)
        _ = try await t.settle(timeout: 15)
    }

    private func zoomOut() async throws -> ExpanseState {
        t.link("enter")
        try await t.until("zoomed out", timeout: 15) { try await self.t.settle(timeout: 15).active }
        // The windows' pictures catch up.
        try await t.pause(1.5)
        return try await t.settle(timeout: 15)
    }

    /// The app's window in front, the glide to it over. A key or a hop sent sooner goes to the app before it.
    private func bringForward(_ app: String) async throws {
        t.link("focus", ["id": try id(app)])
        try await untilInFront(app)
        _ = try await t.settle(timeout: 15)
        try await t.pause(1)
    }

    private func untilInFront(_ app: String) async throws {
        try await t.until("\(app) in front", timeout: 15) { NSWorkspace.shared.frontmostApplication?.localizedName == app }
    }

    private func id(_ app: String) throws -> CGWindowID {
        guard let id = ids[app] else { throw Failure("no window of \(app)") }
        return id
    }

    private func launch(_ arguments: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // -F: without bringing back the windows it had.
        p.arguments = ["-F"] + arguments
        try p.run()
        p.waitUntilExit()
    }

    private func axWindows(_ app: String) -> [AXUIElement] {
        guard let pid = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == app })?.processIdentifier else { return [] }
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value)
        return value as? [AXUIElement] ?? []
    }

    private func close(_ window: AXUIElement) {
        var button: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button)
        if let button { AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) }
    }

    /// A picture of the screen, with the pointer in it. Taken over SSH by scripts/screenshots.sh,
    /// which watches for this request: SSH can record the VM's screen, and this way Expanse Tests
    /// needs no Screen Recording of its own.
    private func picture(_ name: String) async throws {
        let request = "/tmp/expanse-shot"
        try out.appendingPathComponent("\(name).png").path.write(toFile: request, atomically: true, encoding: .utf8)
        try await t.until("the picture \(name)", timeout: 15) { !FileManager.default.fileExists(atPath: request) }
    }
}
