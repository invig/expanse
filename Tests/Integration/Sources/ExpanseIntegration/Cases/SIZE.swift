import AppKit

/// The manual cases in docs/regression/sizes.md.
///
/// What Expanse takes as the size you chose (`preferredSize`) isn't in expanse://dump: it's read
/// from the layout file's `pw`/`ph` (see sizeSaved), and from the `resize` and `fit size` lines a
/// glide or Tidy Up logs when it puts a window back to it. "Yours" means a drag of an edge, or a
/// resize just after your click or key press in the window's app (CanvasController.realWindowChanged):
/// the cases make one with a real click or key, then a resize from the app or from outside.
@MainActor enum SIZE {
    static let cases: [Case] = [
        Case("SIZE-04", "A window growing near the screen's edge isn't cut short") { t in
            try t.needsInput()
            let vp = try await t.state().viewport
            let vf = sizeVisibleFrame()
            // About 500×400 in the bottom-right corner of the screen when Expanse first takes it on:
            // where quitting puts it back.
            let w = try await t.window("SIZE-04 W", CGRect(x: vf.maxX - 510, y: vf.maxY - 410, width: 500, height: 400), managed: false)
            try await t.until("the window on screen", timeout: 3) { w.real != nil }
            let original = w.opened
            try await t.until("Expanse to take on the window", timeout: 10) { try await t.state().window(w.id) != nil }
            let takenOn = Date()
            let app = try await t.state().window(w.id)?.app ?? "Expanse Tests"
            // Your size for it, much bigger than fits from that corner, made at 100%.
            t.link("focus", ["id": w.id])
            try await t.sizeInView(w.id)
            let chosen = CGSize(width: min(1200, vp.width - 120).rounded(), height: min(800, vp.height - 120).rounded())
            // (Expanse takes a window's own move or resize within 0.6s of placing it for the echo of
            // that, and a move in a new window's first 5s for its app placing it late: cameBack.)
            try await t.pause(max(0.8, 5.5 - Date().timeIntervalSince(takenOn)))
            guard let r = w.real else { throw Failure("the window isn't on screen") }
            Input.click(at: CGPoint(x: r.minX + 100, y: r.minY + 10))
            w.setFrame(CGRect(origin: CGPoint(x: vp.minX + 40, y: vp.minY + 40), size: chosen))
            try await t.sizeChosen(w.id, chosen)
            try await t.quitExpanse()
            try await t.until("the window back at 500×400 in the bottom right, where macOS had it", timeout: 10) {
                w.real.map { sizeNear($0.origin, original.origin) && sizeNear($0.size, original.size) } ?? false
            }
            let mark = t.log.mark()
            try await t.launchExpanse()
            let line = try await t.expectLog("restore size \(app)[\(w.id)]", since: mark, timeout: 20)
            guard let restored = sizeLast(line) else { throw Failure("couldn't read “\(line)”") }
            try t.expect(sizeNear(restored, chosen), "the window should come back at the whole \(Int(chosen.width))×\(Int(chosen.height)), not cut short at the screen's edge: \(line)")
            try await t.until("the real window at its full size", timeout: 10) { w.real.map { sizeNear($0.size, chosen) } ?? false }
            let s = try await t.settle(timeout: 15)
            guard let cw = s.window(w.id) else { throw Failure("the window isn't on the canvas after the relaunch") }
            try t.expect(sizeNear(cw.canvas.size, chosen), "the window's size on the canvas after the relaunch (\(cw.canvas.size))")
            if !cw.parked {
                let spot = s.screenPoint(cw.canvas.origin)
                try await t.until("the window at its canvas spot", timeout: 8) { w.real.map { sizeNear($0.origin, spot, 3) } ?? false }
            }
        },

        Case("SIZE-10", "A VM window keeps its spot when the VM changes resolution", .guided) { t in
            var vm = try await sizeVMWindow(t)
            if vm == nil {
                try await t.ask("Open a VM or remote-screen window (UTM, Parallels, VMware Fusion, VirtualBox, Tart, Screen Sharing, Screens, Moonlight or Remote Desktop) whose guest display resolution you can change, and leave it on this display. Then click Done.")
                try await t.until("Expanse to take on the VM window", timeout: 15) {
                    vm = try await sizeVMWindow(t)
                    return vm != nil
                }
            }
            guard let vm else { throw Skip("no VM window on the canvas") }
            let home = vm.canvas.origin
            defer { t.link("place", ["id": vm.id, "x": Int(home.x), "y": Int(home.y), "commit": 1]) }
            // In a row with one of ours, tops level, at 100% on it.
            let spot = sizeClearSpot(try await t.state())
            let row = try await t.window("SIZE-10 Row", CGRect(x: 160, y: 160, width: 400, height: 260))
            t.place(row, at: spot)
            let rowWidth = try await t.canvasFrame(row).width
            t.link("place", ["id": vm.id, "x": Int(spot.x + rowWidth + 20), "y": Int(spot.y), "commit": 1])
            try await t.settle()
            t.link("focus", ["id": vm.id])
            try await t.sizeInView(vm.id)
            let start = try await t.state().sizeFrame(vm.id)
            var before = start
            for bigger in [true, false] {
                let mark = t.log.mark()
                try await t.ask("In the VM, change the guest's display resolution to a \(bigger ? "bigger" : "smaller") one. Once the window has finished resizing, click Done.")
                try await t.expectLog("\(vm.app)[\(vm.id)] resized itself", since: mark, timeout: 3)
                let s = try await t.settle()
                let now = try s.sizeFrame(vm.id)
                try t.expect(!sizeNear(now.size, before.size), "the VM window should have changed size (still \(now.size))")
                try t.expectNear(now.origin, start.origin, within: 2, "the VM window's top-left on the canvas (it should keep its spot, \(bigger ? "growing" : "shrinking") from there)")
                try t.expect(abs(now.minY - (try s.sizeFrame(row.id)).minY) <= 2, "the VM window's top should stay level with the row's")
                if s.window(vm.id)?.parked == false, let real = realFrame(vm.id) {
                    try t.expectNear(real.origin, s.screenPoint(now.origin), within: 3, "the real VM window (it should stay at its spot)")
                }
                before = now
            }
            // Moving it by hand is followed as usual.
            let mark = t.log.mark()
            try await t.ask("Now drag the VM window by its title bar to a new spot a few hundred points away, then click Done.")
            try await t.expectLog("follow \(vm.app)[\(vm.id)]", since: mark, timeout: 3)
            let s = try await t.settle()
            let moved = try s.sizeFrame(vm.id)
            try t.expect(hypot(moved.minX - start.minX, moved.minY - start.minY) > 40, "the VM window's spot on the canvas should follow your drag (it's still at \(moved.origin))")
            if s.window(vm.id)?.parked == false, let real = realFrame(vm.id) {
                try t.expectNear(real.origin, s.screenPoint(moved.origin), within: 3, "the real VM window after your drag")
            }
        },

        Case("SIZE-11", "A size set with macOS's Fill sticks") { t in
            try t.needsInput()
            let bundle = "com.apple.TextEdit"
            let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Expanse Tests SIZE-11", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("SIZE-11 Fill.txt")
            try "Expanse Tests: a document to Fill.\n".write(to: file, atomically: true, encoding: .utf8)
            var opened: [AXUIElement] = []
            defer {
                opened.forEach(sizeAXClose)
                if !wasRunning { NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.terminate() }
                try? FileManager.default.removeItem(at: folder)
            }
            let doc = try await t.sizeNewTextEditWindow(titled: "SIZE-11 Fill") { try t.open(file.path, in: "TextEdit") }
            let takenOn = Date()
            opened.append(doc.ax)
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier else {
                throw Failure("TextEdit isn't running")
            }
            let s0 = try await t.state()
            let vf = sizeVisibleFrame()
            let size = try s0.sizeFrame(doc.id).size
            guard size.width < vf.width - 100 || size.height < vf.height - 100 else {
                throw Skip("TextEdit's window already about fills the screen, so Fill wouldn't change it")
            }
            // The document, and another window beside it.
            let spot = sizeClearSpot(s0)
            let beside = try await t.window("SIZE-11 Beside", CGRect(x: 160, y: 160, width: 400, height: 260))
            t.link("place", ["id": doc.id, "x": Int(spot.x), "y": Int(spot.y), "commit": 0])
            // Far enough right to stay clear of the document once it fills the screen.
            t.place(beside, at: CGPoint(x: spot.x + vf.width + 400, y: spot.y))
            try await t.settle()
            t.link("focus", ["id": doc.id])
            try await t.sizeInView(doc.id)
            try await t.until("TextEdit in front", timeout: 5) { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle }
            guard let fill = sizeAXMenuItem(pid, ["Window", "Fill"]) else { throw Skip("TextEdit's Window menu has no Fill (macOS 15 or later)") }
            // Past the 2s after any resize of Expanse's own (the glide's), which isn't you choosing a
            // size, and the window's first 5s, in which a move is taken for its app placing it late
            // and put back (cameBack): Fill moves it as well.
            try await t.pause(max(2.5, 5.5 - Date().timeIntervalSince(takenOn)))
            guard let r = realFrame(doc.id) else { throw Failure("the document isn't on screen") }
            // Window › Fill, as you'd choose it: a click, then the menu item.
            Input.click(at: CGPoint(x: r.minX + 100, y: r.minY + 10))
            AXUIElementPerformAction(fill, kAXPressAction as CFString)
            try await t.until("the document to fill the screen", timeout: 5) {
                realFrame(doc.id).map { $0.width > r.width + 40 || $0.height > r.height + 40 } ?? false
            }
            try await t.pause(1)
            guard let filled = realFrame(doc.id)?.size else { throw Failure("the document closed") }
            try t.expect(filled.width >= vf.width - 60 && filled.height >= vf.height - 60, "Fill should make the document fill the screen (\(filled) on a \(vf.size) screen)")
            try await t.sizeChosen(doc.id, filled)
            // Hop away and back.
            let mark = t.log.mark()
            t.link("focus", ["id": beside.id])
            try await t.sizeInView(beside.id)
            t.link("focus", ["id": doc.id])
            try await t.sizeInView(doc.id)
            try await t.noLog("resize TextEdit[\(doc.id)]", since: mark, within: 0.5)
            try t.expect(realFrame(doc.id).map { sizeNear($0.size, filled) } ?? false, "after hopping away and back, the document should still fill the screen (\(String(describing: realFrame(doc.id)?.size)), Fill made it \(filled))")
            // Zoomed out, Tidy Up, then back into the document.
            t.link("enter")
            try await t.until("the canvas to open", timeout: 10) { try await t.state().active }
            try await t.settle()
            try await t.sizeKeysToCanvas()
            let tidyMark = t.log.mark()
            Input.key(.t)
            try await t.expectLog("layout fitted:", since: tidyMark, timeout: 8)
            let s = try await t.settle()
            let d = try s.sizeFrame(doc.id)
            Input.click(at: s.screenPoint(CGPoint(x: d.midX, y: d.midY)))
            try await t.until("back at 100% in the document", timeout: 8) { let s = try await t.state(); return !s.active && s.idle }
            try await t.until("the document still filling the screen", timeout: 5) { realFrame(doc.id).map { sizeNear($0.size, filled) } ?? false }
            try await t.noLog("resize TextEdit[\(doc.id)]", since: mark, within: 0.5)
            try await t.noLog("fit size TextEdit[\(doc.id)]", since: mark, within: 0.1)
        },

        Case("SIZE-12", "A size set with Moom or a keyboard shortcut sticks") { t in
            try t.needsInput()
            let (f, id, beside) = try await t.sizeFixtureBeside("SIZE-12")
            let vp = try await t.state().viewport
            let app = try await t.state().window(id)?.app ?? "Expanse Tests"
            guard let r = realFrame(id) else { throw Failure("the fixture's window isn't on screen") }
            let size = CGSize(width: min(r.width + 260, vp.width - 100).rounded(), height: min(r.height + 160, vp.height - 100).rounded())
            // As Moom does on its shortcut: a key press in the window's app, then a resize from
            // outside it, straight after.
            Input.key(.escape)
            try await f.send("frame", ["frame": NSStringFromRect(CGRect(origin: CGPoint(x: vp.minX + 60, y: vp.minY + 40), size: size))])
            try await t.sizeChosen(id, size)
            // Hop away and back.
            let mark = t.log.mark()
            t.link("focus", ["id": beside.id])
            try await t.sizeInView(beside.id)
            t.link("focus", ["id": id])
            try await t.sizeInView(id)
            try await t.noLog("resize \(app)[\(id)]", since: mark, within: 0.5)
            try await t.until("the window at the size it was given", timeout: 5) { realFrame(id).map { sizeNear($0.size, size) } ?? false }
        },

        Case("SIZE-14", "A resize you didn't make doesn't change the size you chose") { t in
            try t.needsInput()
            let (f, id, beside) = try await t.sizeFixtureBeside("SIZE-14")
            let vp = try await t.state().viewport
            let app = try await t.state().window(id)?.app ?? "Expanse Tests"
            guard let r = realFrame(id) else { throw Failure("the fixture's window isn't on screen") }
            // The size you chose: a click in the window, then a resize straight after.
            let chosen = CGSize(width: min(r.width + 260, vp.width - 100).rounded(), height: min(r.height + 160, vp.height - 100).rounded())
            Input.click(at: CGPoint(x: r.minX + 100, y: r.minY + 10))
            try await f.send("frame", ["frame": NSStringFromRect(CGRect(origin: CGPoint(x: vp.minX + 60, y: vp.minY + 40), size: chosen))])
            try await t.sizeChosen(id, chosen)
            // Another app in front, and nothing pressed for a while: then the app resizes the
            // window itself, as a script telling it to would.
            t.link("focus", ["id": beside.id])
            try await t.sizeInView(beside.id)
            try await t.until("Expanse Tests in front", timeout: 5) {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            }
            try await t.pause(2)
            let scripted = CGSize(width: 600, height: 400)
            try await f.send("frame", ["frame": NSStringFromRect(CGRect(origin: CGPoint(x: 100, y: 100), size: scripted))])
            try await t.until("the script's resize to happen", timeout: 5) { realFrame(id).map { sizeNear($0.size, scripted) } ?? false }
            try await t.until("Expanse to see it", timeout: 5) { (try await t.state().window(id)?.canvas.size).map { sizeNear($0, scripted) } ?? false }
            try await t.pause(1.5)
            let kept = sizeSaved(id)?.chosen
            try t.expect(kept.map { sizeNear($0, chosen) } ?? false,
                         "a resize the app made while another app was in front shouldn't become the chosen size (layout file has \(kept.map { "\($0)" } ?? "nothing"), not \(chosen))")
            // Going to it puts it back to the size you chose.
            let mark = t.log.mark()
            t.link("focus", ["id": id])
            let line = try await t.expectLog("resize \(app)[\(id)]", since: mark, timeout: 8)
            try t.expect(sizeLast(line).map { sizeNear($0, chosen) } ?? false, "the glide should resize it back to \(Int(chosen.width))×\(Int(chosen.height)): \(line)")
            try await t.until("the window back at the size you chose", timeout: 8) { realFrame(id).map { sizeNear($0.size, chosen) } ?? false }
        },
    ]
}

// MARK: Helpers

private func sizeNear(_ a: CGSize, _ b: CGSize, _ d: CGFloat = 2) -> Bool { abs(a.width - b.width) <= d && abs(a.height - b.height) <= d }
private func sizeNear(_ a: CGPoint, _ b: CGPoint, _ d: CGFloat = 2) -> Bool { abs(a.x - b.x) <= d && abs(a.y - b.y) <= d }

/// The last `{w, h}` in a log line (the size after the arrow in `resize` and `restore size`).
private func sizeLast(_ line: String) -> CGSize? {
    guard let m = line.matches(of: #/\{(-?[0-9.]+), (-?[0-9.]+)\}/#).last,
          let w = Double(m.1), let h = Double(m.2) else { return nil }
    return CGSize(width: w, height: h)
}

/// A spot on the canvas clear of every window on it: right of and above them all.
private func sizeClearSpot(_ s: ExpanseState) -> CGPoint {
    let all = s.windows.map(\.canvas).reduce(CGRect.null) { $0.union($1) }
    guard !all.isNull else { return .zero }
    return CGPoint(x: (all.maxX + 3000).rounded(), y: (all.minY - 3000).rounded())
}

/// The main display's area for windows (less the menu bar and the Dock), in global CG coordinates.
@MainActor private func sizeVisibleFrame() -> CGRect {
    guard let screen = NSScreen.screens.first else { return .zero }
    let f = screen.visibleFrame
    return CGRect(x: f.minX, y: screen.frame.height - f.maxY, width: f.width, height: f.height)
}

/// What Expanse's layout file has for window `id`: its size on the canvas, and the size you chose.
private func sizeSaved(_ id: CGWindowID) -> (size: CGSize, chosen: CGSize)? {
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Expanse/layout.json")
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let windows = json["windows"] as? [[String: Any]],
          let e = windows.first(where: { ($0["id"] as? NSNumber)?.uint32Value == id }) else { return nil }
    func n(_ k: String) -> CGFloat { CGFloat((e[k] as? NSNumber)?.doubleValue ?? 0) }
    return (CGSize(width: n("w"), height: n("h")), CGSize(width: n("pw"), height: n("ph")))
}

/// VM and remote-screen apps, whose windows keep the size their app picks (ManagedWindow.sizesItself).
private let sizeSelfSizing: Set<String> = [
    "com.utmapp.UTM", "com.github.cirruslabs.tart", "com.parallels.desktop.console", "com.vmware.fusion",
    "org.virtualbox.app.VirtualBoxVM", "com.apple.ScreenSharing", "com.edovia.screens.5", "com.edovia.screens.mac",
    "com.moonlight-stream.Moonlight", "com.microsoft.rdc.macos", "com.microsoft.rdc.mac",
]

/// A window of a VM or remote-screen app on the canvas, if there is one.
@MainActor private func sizeVMWindow(_ t: Ctx) async throws -> ExpanseState.Window? {
    let names = Set(NSWorkspace.shared.runningApplications.filter { sizeSelfSizing.contains($0.bundleIdentifier ?? "") }.compactMap(\.localizedName))
    guard !names.isEmpty else { return nil }
    return try await t.state().windows.last { names.contains($0.app) }
}

extension ExpanseState {
    fileprivate func sizeFrame(_ id: CGWindowID) throws -> CGRect {
        guard let f = window(id)?.canvas else { throw Failure("window \(id) isn't on the canvas") }
        return f
    }
}

fileprivate extension Ctx {
    /// Glided to and on screen at 100% (after expanse://focus).
    func sizeInView(_ id: CGWindowID) async throws {
        try await until("window \(id) in view at 100%", timeout: 10) {
            let s = try await self.settle()
            return !s.active && s.window(id)?.parked == false
        }
    }

    /// Expanse has `size` as the window's size and, in its layout file, as the size you chose.
    func sizeChosen(_ id: CGWindowID, _ size: CGSize) async throws {
        try await until("Expanse to take the new size \(Int(size.width))×\(Int(size.height))", timeout: 5) {
            (try await self.state().window(id)?.canvas.size).map { sizeNear($0, size) } ?? false
        }
        do {
            try await until("the layout file to keep it as the size you chose", timeout: 5) { sizeSaved(id).map { sizeNear($0.chosen, size) } ?? false }
        } catch {
            throw Failure("a resize just after your click or key press in the window's app should become its chosen size: the layout file has \(sizeSaved(id).map { "\($0.chosen)" } ?? "nothing") for it, not \(size)")
        }
    }

    func sizeKeysToCanvas() async throws {
        try await until("Expanse in front, so the canvas gets the keys", timeout: 4) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.invignation.expanse"
        }
    }

    /// A fixture's window (another app's) with one of ours beside it at a clear spot, and you in
    /// the fixture's window at 100%, its app in front.
    func sizeFixtureBeside(_ name: String) async throws -> (Fixture, CGWindowID, TestWindow) {
        let spot = sizeClearSpot(try await state())
        let f = try await fixture(name, windows: 1, size: CGSize(width: 500, height: 340))
        guard let id = f.windows.first else { throw Failure("the fixture has no window") }
        try await until("Expanse to take on the fixture's window", timeout: 10) { try await self.state().window(id) != nil }
        let beside = try await window("\(name) Beside", CGRect(x: 160, y: 160, width: 400, height: 260))
        // Far enough right that the fixture's window can grow without reaching it.
        link("place", ["id": id, "x": Int(spot.x), "y": Int(spot.y), "commit": 0])
        place(beside, at: CGPoint(x: spot.x + 1600, y: spot.y))
        try await settle()
        link("focus", ["id": id])
        try await sizeInView(id)
        try? await until("the glide to bring the fixture's app forward", timeout: 2) {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == f.pid
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != f.pid, let r = realFrame(id) {
            // A click on its window does; then a pause, so that click isn't what makes the next resize yours.
            Input.click(at: CGPoint(x: r.minX + 100, y: r.minY + 10))
            try await pause(2)
        }
        try await until("the fixture's app in front", timeout: 5) { NSWorkspace.shared.frontmostApplication?.processIdentifier == f.pid }
        // Expanse takes a window's own move or resize within 0.6s of placing it for the echo of that.
        try await pause(0.8)
        return (f, id, beside)
    }

    /// A TextEdit window that `open` brings, titled starting `titled`, once Expanse has it: its
    /// window ID and its element, paired by where they are.
    func sizeNewTextEditWindow(titled: String, _ open: () throws -> Void) async throws -> (id: CGWindowID, ax: AXUIElement) {
        let bundle = "com.apple.TextEdit"
        let ids = Set(windowsOf(owner: "TextEdit").map(\.id))
        try open()
        var found: (CGWindowID, AXUIElement)?
        try await until("the TextEdit document on the canvas", timeout: 15) {
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier,
                  let el = sizeAXChildren(AXUIElementCreateApplication(pid), kAXWindowsAttribute)
                    .first(where: { (sizeAXString($0, kAXTitleAttribute) ?? "").hasPrefix(titled) }),
                  let at = sizeAXFrame(el),
                  let id = self.windowsOf(owner: "TextEdit").first(where: { w in
                      !ids.contains(w.id) && sizeNear(w.frame.origin, at.origin) && sizeNear(w.frame.size, at.size)
                  })?.id,
                  try await self.state().window(id) != nil else { return false }
            found = (id, el)
            return true
        }
        guard let found else { throw Failure("no TextEdit window for “\(titled)”") }
        return found
    }
}

// MARK: Accessibility (TextEdit's menu and window)

private func sizeAXValue(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}

private func sizeAXString(_ e: AXUIElement, _ name: String) -> String? { sizeAXValue(e, name) as? String }

private func sizeAXElement(_ e: AXUIElement, _ name: String) -> AXUIElement? {
    guard let v = sizeAXValue(e, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

private func sizeAXChildren(_ e: AXUIElement, _ name: String = kAXChildrenAttribute) -> [AXUIElement] {
    (sizeAXValue(e, name) as? [AXUIElement]) ?? []
}

private func sizeAXFrame(_ e: AXUIElement) -> CGRect? {
    guard let p = sizeAXValue(e, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
          let z = sizeAXValue(e, kAXSizeAttribute), CFGetTypeID(z) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(z as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: origin, size: size)
}

/// An app's menu item by its titles from the menu bar down, e.g. ["Window", "Fill"].
private func sizeAXMenuItem(_ pid: pid_t, _ path: [String]) -> AXUIElement? {
    guard var here = sizeAXElement(AXUIElementCreateApplication(pid), kAXMenuBarAttribute) else { return nil }
    for (i, title) in path.enumerated() {
        // A menu bar's children are its items; an item's child is its menu, whose children are items.
        let items = i == 0 ? sizeAXChildren(here) : sizeAXChildren(here).flatMap { sizeAXChildren($0) }
        guard let next = items.first(where: { sizeAXString($0, kAXTitleAttribute) == title }) else { return nil }
        here = next
    }
    return here
}

/// Presses the window's close button (nothing happens if it's gone already).
private func sizeAXClose(_ window: AXUIElement) {
    guard let button = sizeAXElement(window, kAXCloseButtonAttribute) else { return }
    AXUIElementPerformAction(button, kAXPressAction as CFString)
}
