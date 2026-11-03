import AppKit
import ApplicationServices
import Security

/// The manual cases in docs/regression/panels-and-look.md, and UI-19's glass (its colours are a
/// unit case). The menu bar panel, the walkthrough and Settings are read and pressed through
/// Accessibility (Expanse Tests needs it, as it does for input); what only shows on screen is
/// asked about.
@MainActor enum UI {
    static let cases: [Case] = [
        Case("UI-01", "The minimap shows every window, the view and the zoom", .look) { t in
            _ = try await t.row(["UI-01 A", "UI-01 B", "UI-01 C"])
            t.link("enter")
            let out = try await t.settle()
            try t.expect(out.active && out.scale < 1, "enter should zoom out (scale \(out.scale))")
            try await t.look("Bottom right, 16pt in from the screen's corner: a \(uiGlass) panel shows every window as a block, the part of "
                             + "the canvas on screen as an accent-coloured outline, and the zoom (\(Int((out.scale * 100).rounded()))%)?")
            try await t.uiLook("Watch the minimap while Expanse pans and zooms for a few seconds: the blocks, the outline and the "
                               + "percentage follow live?", every: 1.5, [
                { t.link("zoom", ["scale": 0.25]) }, { t.link("pan", ["dx": 500, "dy": 0]) }, { t.link("zoom", ["scale": 0.5]) },
                { t.link("pan", ["dx": -500, "dy": 300]) }, { t.link("fit") },
            ])
            t.link("exit")
            let back = try await t.settle()
            try t.expect(!back.active, "exit should go back to 100%")
            // A window over the minimap's corner: at 100% the minimap is on the desktop, under it.
            let cover = try await t.window("UI-01 Cover", CGRect(x: 300, y: 300, width: 480, height: 360))
            t.place(cover, at: CGPoint(x: back.camera.x + back.viewport.width - 500, y: back.camera.y + back.viewport.height - 380))
            let s = try await t.settle()
            guard let backdrop = t.uiOverlay(s) else { throw Failure("can't find Expanse's backdrop window") }
            try t.expect(backdrop.layer == uiBackdropLevel,
                         "at 100% the minimap's backdrop should be under every app window (level \(uiBackdropLevel); it's at \(backdrop.layer))")
            try await t.look("Back at 100%: the minimap is on the desktop, under your windows (“UI-01 Cover” hides part of it)?")
        },
        Case("UI-02", "The hovered window is outlined", .look) { t in
            try t.needsInput()
            let ws = try await t.row(["UI-02 A", "UI-02 B", "UI-02 C"])
            t.link("enter")
            var s = try await t.settle()
            @MainActor func centre(_ w: TestWindow) throws -> CGPoint {
                guard let f = s.window(w.id)?.canvas else { throw Failure("“\(w.title)” isn't on the canvas") }
                return s.screenPoint(CGPoint(x: f.midX, y: f.midY))
            }
            Input.glide(to: try centre(ws[0]))
            try await t.pause(0.5)
            try await t.look("Before you move the mouse: “UI-02 A”, under the pointer, has a thin (2pt) accent-colour border, and no other window has one?")
            Input.glide(to: try centre(ws[1]))
            try await t.pause(0.5)
            try await t.look("Before you move the mouse: the border moved to “UI-02 B”, now under the pointer?")
            t.link("zoom", ["scale": 0.2])
            s = try await t.settle()
            Input.glide(to: try centre(ws[1]))
            try await t.pause(0.5)
            try await t.look("Zoomed further out (\(Int((s.scale * 100).rounded()))%): B's border is just as thick on screen as before?")
            Input.click(at: try centre(ws[2]), flags: .maskShift)
            try await t.pause(0.5)
            try await t.look("“UI-02 C”, now selected (⇧-click) and under the pointer, has a thicker (3pt) border?")
            Input.glide(to: CGPoint(x: s.viewport.maxX - 16 - uiMinimapSize.width / 2, y: s.viewport.maxY - 16 - uiMinimapSize.height / 2))
            try await t.pause(0.5)
            try await t.look("With the pointer over the minimap, no window is outlined?")
        },
        Case("UI-03", "Plain canvas background follows light and dark mode", .look) { t in
            let old = expanseDefault("background")
            defer { setExpanseDefault("background", old) }
            setExpanseDefault("background", "plain")
            try await t.window("UI-03 A")
            // The canvas takes a fresh desktop picture as it opens only if the last is over 2s old.
            try await t.pause(2.5)
            t.link("appearance", ["mode": "light"])
            defer { t.link("appearance") }
            t.link("enter")
            try await t.settle()
            try await t.look("Zoomed out, in light mode: the canvas behind the windows is a plain light grey, no desktop picture?")
            try await t.uiLook("Expanse now switches between dark and light every two seconds: the background is dark grey in dark and "
                               + "light grey in light, changing straight away?", every: 2, [
                { t.link("appearance", ["mode": "dark"]) }, { t.link("appearance", ["mode": "light"]) },
                { t.link("appearance", ["mode": "dark"]) }, { t.link("appearance", ["mode": "light"]) },
                { t.link("appearance", ["mode": "dark"]) }, { t.link("appearance", ["mode": "light"]) },
            ])
        },
        Case("UI-04", "Zoomed out, the canvas covers the Dock but not the menu bar", .look) { t in
            let dialogs = t.uiDialogsOnScreen()
            guard dialogs.isEmpty else { throw Skip("a dialog is on screen (\(dialogs.joined(separator: ", "))): the canvas goes under it") }
            try await t.window("UI-04 A")
            t.link("enter")
            let s = try await t.settle()
            try await t.pause(1)   // it checks for dialogs twice a second
            guard let canvas = t.uiOverlay(s) else { throw Failure("can't find Expanse's canvas window") }
            try t.expect(canvas.layer == uiCanvasLevel, "zoomed out, the canvas should be at level \(uiCanvasLevel), just under the menu bar (it's at \(canvas.layer))")
            try t.expect(canvas.layer > uiDockLevel && canvas.layer < uiMenuBarLevel,
                         "the canvas (level \(canvas.layer)) should be above the Dock (\(uiDockLevel)) and under the menu bar (\(uiMenuBarLevel))")
            // The Dock's own windows (not the desktop-level ones it keeps under everything).
            for dock in t.uiWindows(owner: "Dock") where (0..<uiMenuBarLevel).contains(dock.layer) {
                try t.expect(dock.layer < canvas.layer, "the Dock's window at level \(dock.layer) is above the canvas")
            }
            try t.expectNear(canvas.frame, s.viewport, "the canvas should cover the whole screen below the menu bar")
            if Input.allowed {
                Input.click(at: CGPoint(x: 18, y: max(4, s.viewport.minY / 2)))
                try await t.pause(0.8)
                try await t.look("The Apple menu opened above the canvas, which still covers the Dock and every window?")
                Input.key(.escape)
            } else {
                try await t.look("Click the Apple menu: it opens above the canvas, which covers the Dock and every window? (Esc closes it.)")
            }
        },
        Case("UI-07", "The canvas shows the real desktop picture", .look) { t in
            let old = expanseDefault("background")
            defer { setExpanseDefault("background", old) }
            setExpanseDefault("background", "wallpaper")
            try await t.window("UI-07 A")
            try await t.pause(2.5)
            t.link("enter")
            try await t.settle()
            try await t.pause(1)   // the picture's taken as the canvas opens
            try await t.look("Zoomed out: behind the windows is the desktop exactly as macOS draws it now (a dynamic or Photos picture "
                             + "included, with its icons), lined up with the real desktop, the strip under the menu bar too? "
                             + "(It needs Screen Recording for Expanse.)")
            t.link("exit")
            try await t.settle()
            setExpanseDefault("background", "plain")
            try await t.pause(2.5)
            t.link("appearance", ["mode": "light"])
            defer { t.link("appearance") }
            t.link("enter")
            try await t.settle()
            try await t.look("With Desktop picture background off: a plain light-grey background (light mode)?")
            t.link("appearance", ["mode": "dark"])
            try await t.look("And in dark mode, plain dark grey?")
            t.link("appearance")
            t.link("exit")
            try await t.settle()
            setExpanseDefault("background", "wallpaper")
            try await t.pause(2.5)
            t.link("enter")
            try await t.settle()
            try await t.pause(1)
            try await t.look("Turned back on: the desktop picture is behind the windows again?")
        },
        Case("UI-08", "Another Space's desktop picture shows on the canvas there", .guided) { t in
            let old = expanseDefault("background")
            defer { setExpanseDefault("background", old) }
            setExpanseDefault("background", "wallpaper")
            try await t.ask("Set up two desktop Spaces with different desktop pictures (Mission Control › +), and go to Desktop 1.")
            for (step, desktop) in [("", "Desktop 1"), ("Switch to Desktop 2 with Mission Control.", "Desktop 2"),
                                    ("Switch back to Desktop 1.", "Desktop 1")] {
                if !step.isEmpty { try await t.ask(step) }
                try await t.pause(2.5)
                t.link("enter")
                try await t.settle()
                try await t.pause(1)
                try await t.look("Zoomed out on \(desktop): the canvas shows \(desktop)'s desktop picture?")
                t.link("exit")
                try await t.settle()
            }
        },
        Case("UI-10", "Picking the hot corner in the panel") { t in
            try await t.uiClosingUp {
                try t.needsInput()
                let macOS = uiMacCornersInUse()
                guard macOS.isEmpty else {
                    throw Skip("macOS uses the \(macOS.joined(separator: ", ")) hot corner (System Settings › Desktop & Dock › Hot Corners): set them to –")
                }
                let old = expanseDefault("hotCorner") as? String
                do {
                    try await t.uiPickCorner("Top right corner", "topRight")
                    try await t.uiCheckCorners(opening: [.topRight])
                    try await t.uiPickCorner("Off", "off")
                    try await t.uiCheckCorners(opening: [])
                    // The pick is kept after relaunching.
                    try await t.relaunchExpanse()
                    try t.expect(expanseDefault("hotCorner") as? String == "off", "the pick (Off) should be kept after relaunching")
                    try await t.uiCheckCorners(opening: [])
                    try await t.uiPickCorner("All corners", "all")
                    try await t.uiCheckCorners(opening: Set(UICorner.allCases))
                } catch {
                    await t.uiRestoreCorner(old)
                    throw error
                }
                await t.uiRestoreCorner(old)
            }
        },
        Case("UI-11", "Welcome and Quit from the panel's footer") { t in
            try await t.uiClosingUp {
                try t.needsInput()
                let ws = try await t.row(["UI-11 A", "UI-11 B"])
                // Clear of wherever the view is (an earlier case can leave it anywhere).
                let vis = try await t.state().visibleCanvas
                t.place(ws[1], at: CGPoint(x: (vis.maxX + 3000).rounded(), y: vis.minY.rounded()))
                try await t.until("B out of view") { try await t.state().window(ws[1].id)?.parked == true }
                t.link("enter")
                try await t.until("zoomed out") { try await t.settle().active }
                // ? (Welcome & Shortcuts) leaves the canvas first, then opens the walkthrough in front.
                try t.uiPress("Welcome & Shortcuts", in: try await t.uiOpenPanelTree())
                // It opens once the canvas has handed back to the real windows (the zoom in, the
                // windows' moves, focus), which in a VM can take seconds.
                try await t.until("the walkthrough to open", timeout: 20) { t.uiWelcome() != nil }
                let s = try await t.settle()
                try t.expect(!s.active, "? should leave the canvas first (back to 100%)")
                try t.expect(t.uiPanel() == nil, "? should close the panel")
                if let w = t.uiWelcome() { try t.uiExpectInFront(w, "the walkthrough") }
                try await t.uiCloseWelcome()
                // The power button quits Expanse: every window back where macOS had it, the icon gone.
                guard let pid = t.uiPID else { throw Failure("Expanse isn't running") }
                try t.uiPress("Quit Expanse", in: try await t.uiOpenPanelTree())
                try await t.until("Expanse to quit", timeout: 15) { t.expanse == nil }
                for w in ws {
                    try t.expect(w.real.map { t.screen.insetBy(dx: 20, dy: 20).intersects($0) } ?? false,
                                 "“\(w.title)” should be back on screen once Expanse quits (it's at \(w.real.map { NSStringFromRect($0) } ?? "nowhere"))")
                }
                try t.expect(t.uiWindows(pid: pid).isEmpty, "Expanse's windows (its menu bar icon among them) should go with it")
                try await t.launchExpanse()
            }
        },
        Case("UI-12", "Expanse has its own app icon", .look) { t in
            try await t.uiClosingUp {
                try t.needsInput()
                let bundle = Bundle(url: t.expanseURL)
                let name = bundle?.infoDictionary?["CFBundleIconFile"] as? String ?? ""
                try t.expect(!name.isEmpty, "Expanse's Info.plist names no icon (CFBundleIconFile)")
                try t.expect(bundle?.url(forResource: (name as NSString).deletingPathExtension, withExtension: "icns") != nil,
                             "Expanse.app has no \(name).icns in its Resources")
                _ = try await t.uiOpenPanel()
                try await t.look("The menu bar panel's header shows Expanse's ring-gate icon (a portal onto a grid of windows)?")
                try await t.uiClosePanel()
                t.link("welcome")
                try await t.until("the walkthrough to open") { t.uiWelcome() != nil }
                try await t.look("The walkthrough's welcome page shows the same icon?")
                try await t.uiCloseWelcome()
                NSWorkspace.shared.activateFileViewerSelecting([t.expanseURL])
                try await t.look("Finder shows Expanse (\(t.expanseURL.path)) with that icon, and Get Info (⌘I) does too? (Close the Finder windows afterwards.)")
            }
        },
        Case("UI-13", "The walkthrough's canvas illustration", .look) { t in
            try await t.uiClosingUp {
                try t.uiNeedsAX()
                let oldPage = expanseDefault("onboardingPage")
                defer { setExpanseDefault("onboardingPage", oldPage) }
                t.link("welcome")
                try await t.until("the walkthrough to open") { t.uiWelcome() != nil }
                try await t.look("On the left: a deep-blue starry canvas in the icon's colours, with groups of small named windows (Calendar, "
                                 + "Slack, TV and others), gently zooming out to show more windows past the edges and back in, with a zoom "
                                 + "percentage under the “Expanse” name?")
                try await t.uiWalkthrough(to: "STEP 3 OF 4")
                let corner = ["topLeft": "top-left", "bottomLeft": "bottom-left", "bottomRight": "bottom-right"][expanseDefault("hotCorner") as? String ?? ""] ?? "top-right"
                try await t.look("On Step 3, a pointer flicks to the \(corner) corner as the illustration zooms out?")
                try await t.uiWalkthrough(to: "STEP 4 OF 4")
                try await t.look("On Step 4, it glides from window to window (right, down, left, up), with the focused window outlined in amber?")
                try await t.uiCloseWelcome()
            }
        },
        Case("UI-14", "A banner in the panel when an update is ready", .guided) { t in
            throw Skip(uiNeedsRelease(t, "an update ready to install (a release build older than the latest on GitHub)"))
        },
        Case("UI-16", "Full-screen apps' icons in the Spaces panel are sharp", .look) { t in
            guard (NSScreen.screens.first?.backingScaleFactor ?? 1) >= 2 else { throw Skip("needs a Retina display") }
            try await t.uiFullScreenFixture("UI-16 Full")
            t.link("enter")
            try await t.settle()
            try await t.look("In the Spaces panel beside the minimap, the full-screen app's tile shows its icon (36pt) crisp, not blurry, at this display's pixel density?")
        },
        Case("UI-17", "The walkthrough's animation is capped at 60 fps", .look) { t in
            try await t.uiClosingUp {
                let fastest = NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60
                guard fastest > 60 else { throw Skip("needs a display faster than 60 Hz (this one runs at \(fastest) Hz)") }
                try t.uiNeedsAX()
                let idle = try await t.uiCPU(over: 5)
                t.link("welcome")
                try await t.until("the walkthrough to open") { t.uiWelcome() != nil }
                try await t.pause(2)
                let open = try await t.uiCPU(over: 10)
                try await t.look("With the walkthrough open on page 1, Expanse used \(uiPercent(open)) of a core (\(uiPercent(idle)) without it). "
                                 + "The illustration looks smooth, and that's modest, as for redrawing at most 60 times a second (not \(fastest))?")
                try await t.uiCloseWelcome()
            }
        },
        Case("UI-19", "Minimap and Spaces panels are glass that follows light and dark", .look) { t in
            try t.needsInput()
            _ = try await t.row(["UI-19 A", "UI-19 B"])
            try await t.uiFullScreenFixture("UI-19 Full")
            t.link("appearance", ["mode": "light"])
            defer { t.link("appearance") }
            t.link("enter")
            var s = try await t.settle()
            try await t.look("The minimap (bottom right) and the Spaces panel to its left are rounded \(uiGlass) panels (22pt corners), "
                             + "with dark window blocks and text on the light glass?")
            t.link("appearance", ["mode": "dark"])
            try await t.look("Now dark: the glass turned dark, and the blocks and text turned light at once?")
            t.link("appearance")
            // Clicks reach the panels through the glass: the minimap centres the view on the spot clicked.
            for fraction in [0.25, 0.75] {
                let local = CGPoint(x: 14 + 180 * fraction, y: 58)   // in the map, bottom-left origin
                let target = uiMinimapCanvasPoint(s, local)
                Input.click(at: CGPoint(x: s.viewport.maxX - 16 - uiMinimapSize.width + local.x, y: s.viewport.maxY - 16 - local.y))
                try await t.pause(0.3)
                s = try await t.settle()
                let centre = CGPoint(x: s.visibleCanvas.midX, y: s.visibleCanvas.midY)
                try t.expectNear(centre, target.point, within: max(20, 5 / target.scale), "a click on the minimap should centre the view on that spot")
            }
            // A Space tile switches to that Space. The rightmost tile is never the canvas's: the
            // full-screen app's Space opened just after it.
            let mark = t.log.mark()
            Input.click(at: CGPoint(x: s.viewport.maxX - 300, y: s.viewport.maxY - 83))
            try await t.expectLog("switching from Space", since: mark)
            try await t.pause(1.5)
            t.link("space", ["name": "expanse"])
            try await t.pause(1.5)
        },
        Case("UI-23", "A dialog that opens while zoomed out shows above the canvas") { t in
            let already = t.uiDialogsOnScreen()
            guard already.isEmpty else { throw Skip("a dialog is already on screen (\(already.joined(separator: ", "))): close it first") }
            try await t.window("UI-23 A")
            t.link("enter")
            let s = try await t.settle()
            try await t.until("the canvas at level \(uiCanvasLevel)") { t.uiOverlay(s)?.layer == uiCanvasLevel }
            // An alert (an app's window at modal-panel level) opens while zoomed out.
            var mark = t.log.mark()
            let alert = UIDialog()
            defer { alert.close() }
            let opened = Date()
            while (t.uiOverlay(s)?.layer ?? uiCanvasLevel) >= alert.level, Date().timeIntervalSince(opened) < 3 { try await t.pause(0.05) }
            let took = Date().timeIntervalSince(opened)
            try t.expectTiming(took < 1, "the canvas should go under the dialog within about half a second (it took \(String(format: "%.1f", took))s)")
            try await t.expectLog("canvas level \(uiCanvasLevel) -> \(alert.level - 1) (under a dialog)", since: mark)
            // It can be clicked.
            if Input.allowed, let ok = alert.buttonCentre {
                Input.click(at: ok)
                try await t.until("the dialog's button to get the click", timeout: 3) { alert.clicked }
            }
            // Once it closes, the canvas goes back to its usual level.
            mark = t.log.mark()
            alert.close()
            try await t.expectLog("canvas level \(alert.level - 1) -> \(uiCanvasLevel)", since: mark)
            try await t.until("the canvas back at level \(uiCanvasLevel)", timeout: 3) { t.uiOverlay(s)?.layer == uiCanvasLevel }
            // Zooming out with the alert already showing opens the canvas under it.
            t.link("exit")
            try await t.until("back at 100%") { try await !t.settle().active }
            let again = UIDialog()
            defer { again.close() }
            try await t.pause(0.3)
            t.link("enter")
            let s2 = try await t.settle()
            let level = t.uiOverlay(s2)?.layer ?? Int.max
            try t.expect(level < again.level, "zooming out with a dialog showing should open the canvas under it (canvas level \(level), dialog \(again.level))")
            again.close()
            try await t.until("the canvas back at level \(uiCanvasLevel)", timeout: 3) { t.uiOverlay(s2)?.layer == uiCanvasLevel }
        },
        Case("UI-24", "The Dock doesn't count as a dialog") { t in
            let already = t.uiDialogsOnScreen()
            guard already.isEmpty else { throw Skip("a dialog is on screen (\(already.joined(separator: ", "))): close it first") }
            try await t.window("UI-24 A")
            t.link("enter")
            let s = try await t.settle()
            try await t.noLog("(under a dialog)", within: 3)
            let level = t.uiOverlay(s)?.layer ?? Int.min
            try t.expect(level == uiCanvasLevel, "zoomed out, the canvas should cover the Dock at level \(uiCanvasLevel) (it's at \(level))")
            // The Dock's own windows (not the desktop-level ones it keeps under everything).
            for dock in t.uiWindows(owner: "Dock") where (0..<uiMenuBarLevel).contains(dock.layer) {
                try t.expect(dock.layer < level, "the Dock's window at level \(dock.layer) is above the canvas")
            }
            // A window at dialog level under 100×50pt, or fully transparent, doesn't count either.
            let mark = t.log.mark()
            let small = UIDialog(size: CGSize(width: 80, height: 40), titled: false)
            let clear = UIDialog(alpha: 0)
            defer { small.close(); clear.close() }
            try await t.noLog("(under a dialog)", since: mark, within: 2.5)
            try t.expect(t.uiOverlay(s)?.layer == uiCanvasLevel, "a small or transparent window at dialog level moved the canvas under it")
        },
        Case("UI-25", "At 100% the real desktop shows through the backdrop", .guided) { t in
            try await t.window("UI-25 A")
            let s = try await t.settle()
            guard let backdrop = t.uiOverlay(s) else { throw Failure("can't find Expanse's backdrop window") }
            try t.expect(backdrop.layer == uiBackdropLevel,
                         "at 100% the backdrop should be under every app window (level \(uiBackdropLevel); it's at \(backdrop.layer))")
            try await t.ask("Have Finder show items on the desktop, with a light desktop picture. Look closely at the desktop: the shade under the menu bar, the icons.")
            t.link("pause")
            try await t.untilPaused("paused")
            try await t.look("Expanse is paused now. The desktop looks exactly as it did with Expanse running (the menu bar's shade fades the same way, the icons are the same)?")
            t.link("resume")
            try await t.until("resumed") { try await !t.state().paused }
            try await t.ask("Fill a window: hold ⌥ over its green button and choose Fill (or Window › Fill).")
            try await t.look("Around the filled window, macOS dims the desktop as it does without Expanse, and only Expanse's own drawing "
                             + "(slivers of windows out of view, the minimap) is on top? (Put the window back afterwards.)")
        },
        Case("UI-26", "The canvas and a glide still draw their own copy of the desktop", .look) { t in
            let old = expanseDefault("background")
            defer { setExpanseDefault("background", old) }
            setExpanseDefault("background", "wallpaper")
            let ws = try await t.row(["UI-26 A", "UI-26 B"])
            t.place(ws[1], at: CGPoint(x: 6000, y: 0))
            try await t.until("B out of view") { try await t.state().window(ws[1].id)?.parked == true }
            try await t.pause(2.5)
            t.link("enter")
            try await t.settle()
            try await t.pause(1)
            try await t.look("Zoomed out: the backdrop is opaque and shows Expanse's copy of the desktop picture behind the windows?")
            t.link("exit")
            try await t.settle()
            t.link("focus", ["id": ws[0].id])
            try await t.settle()
            try await t.uiLook("In a moment Expanse glides to “UI-26 B” (off screen) and back, twice. During each glide the background is "
                               + "Expanse's opaque copy of the desktop, never flashing through to the real desktop?", every: 2.5, [
                { t.link("focus", ["id": ws[1].id]) }, { t.link("focus", ["id": ws[0].id]) },
                { t.link("focus", ["id": ws[1].id]) }, { t.link("focus", ["id": ws[0].id]) },
            ])
            try await t.settle()
            setExpanseDefault("background", "plain")
            try await t.pause(2.5)
            t.link("appearance", ["mode": "light"])
            defer { t.link("appearance") }
            t.link("enter")
            try await t.settle()
            try await t.look("With Desktop picture background off: the canvas is plain light grey (light mode)?")
            t.link("appearance", ["mode": "dark"])
            try await t.look("And plain dark grey in dark mode?")
            t.link("appearance")
            t.link("exit")
            let back = try await t.settle()
            let level = t.uiOverlay(back)?.layer ?? Int.min
            try t.expect(level == uiBackdropLevel, "back at 100% the backdrop should be see-through again, under the windows (level \(level))")
        },
        Case("UI-27", "Desktop icons can be clicked at 100%", .guided) { t in
            try t.needsInput()
            let s = try await t.settle()
            let level = t.uiOverlay(s)?.layer ?? Int.min
            try t.expect(level == uiBackdropLevel, "at 100% the backdrop should be under every window (level \(uiBackdropLevel); it's at \(level))")
            // A right-click on the bare desktop is Finder's: its desktop menu, and the canvas stays shut.
            guard let p = t.uiBareDesktopPoint(s) else { throw Skip("no bare desktop showing to click: move some windows aside") }
            uiRightClick(at: p)
            try await t.until("Finder's desktop menu", timeout: 3) { t.uiMenuShowing(owner: "Finder") }
            Input.key(.escape)
            try await t.pause(0.5)
            var active = try await t.state().active
            try t.expect(!active, "a right-click on the bare desktop opened the canvas")
            try await t.ask("With Finder showing items on the desktop: click an icon, double-click it, then drag an icon to another place on the desktop.")
            active = try await t.state().active
            try t.expect(!active, "clicking the desktop's icons opened the canvas")
            try await t.look("Each did what it does without Expanse: the icon was selected, then opened, then moved?")
        },
        Case("UI-28", "The canvas opens onto a fresh picture of the real desktop", .guided) { t in
            try t.needsInput()
            let old = expanseDefault("background")
            defer { setExpanseDefault("background", old) }
            setExpanseDefault("background", "wallpaper")
            try await t.window("UI-28 A")
            var s = try await t.settle()
            guard let p = t.uiBareDesktopPoint(s) else { throw Skip("no bare desktop showing to scroll on: move some windows aside") }
            try await t.pause(2.5)
            // A scroll on the bare desktop opens the canvas at 100% (NAV-18).
            Input.move(to: p)
            Input.scroll(dy: -3)
            try await t.until("the canvas to open", timeout: 3) { try await t.state().active }
            s = try await t.settle()
            try t.expect(abs(s.scale - 1) < 0.01, "a scroll on the desktop should open the canvas at 100% (scale \(s.scale))")
            try await t.pause(1)
            try await t.look("The canvas just opened at 100%: nothing changed under the windows (the picture, Finder's icons and the shade under the menu bar are as they were)?")
            t.link("exit")
            try await t.settle()
            try await t.ask("Move an icon on the desktop to another place (or add one).")
            try await t.pause(3)
            t.link("enter")
            try await t.settle()
            try await t.pause(1)
            try await t.look("Zoomed out, the canvas's desktop shows the icon where it is now?")
        },
        Case("UI-29", "No dimmed desktop is left on the canvas after Fill", .guided) { t in
            let old = expanseDefault("background")
            defer { setExpanseDefault("background", old) }
            setExpanseDefault("background", "wallpaper")
            try await t.ask("Fill a window: hold ⌥ over its green button and choose Fill (or Window › Fill). macOS dims the desktop around it.")
            try await t.pause(2.5)
            t.link("enter")
            try await t.settle()
            try await t.pause(1)
            try await t.look("Zoomed out, the canvas's desktop is dimmed, as the real one is?")
            t.link("exit")
            try await t.settle()
            try await t.ask("Make that window smaller (drag a corner) so macOS no longer dims the desktop.")
            try await t.pause(3)
            t.link("enter")
            try await t.settle()
            try await t.pause(1)
            try await t.look("The canvas's desktop is bright again: no dimmed copy left behind?")
        },
        Case("UI-30", "The panel's status line", .look) { t in
            try await t.uiClosingUp {
                try t.needsInput()
                let ws = try await t.row(["UI-30 A", "UI-30 B", "UI-30 C"])
                let n = try await t.settle().windows.count
                _ = try await t.uiOpenPanel()
                try await t.uiExpectStatus(uiOn(n))
                // Closing a window with the panel open: the count follows within about half a second.
                ws[2].close()
                let closed = Date()
                try await t.uiExpectStatus(uiOn(n - 1), timeout: 4)
                let took = Date().timeIntervalSince(closed)
                try t.expect(took < 2, "the count took \(String(format: "%.1f", took))s to follow a window closing (expected about half a second)")
                try await t.uiClosePanel()
                // Before the walkthrough is done: reset for the moment, and put back.
                try await t.uiBeforeWalkthrough {
                    try await t.uiClickIcon()
                    let tree = try await t.uiPanelTree()
                    let status = t.uiStatus(tree)
                    try t.expect(status == "Starts once the walkthrough is done", "the status should read “Starts once the walkthrough is done” (it reads “\(status ?? "nothing")”)")
                    let parts: [(String, UINode?)] = [
                        ("the header switch", tree.first("Expanse", role: kAXCheckBoxRole)), ("the minimap card", tree.button("Open Expanse")),
                        ("Centre window", tree.button("Centre window")), ("Tidy up", tree.button("Tidy up")),
                        ("Take snapshot", tree.button("Take snapshot")), ("Restore all windows", tree.button("Restore all windows")),
                    ] + tree.flat.filter { $0.role == kAXButtonRole && $0.help.hasPrefix("Put the windows back") }.map { ("a layout thumbnail", $0) }
                    for (name, node) in parts {
                        guard let node else { throw Failure("no \(name) in the panel") }
                        try t.expect(!node.enabled, "\(name) should be greyed out and inactive before the walkthrough is done")
                    }
                    try await t.look("In the panel, the app icon is grey, and the switch, the minimap card, the tiles, the snapshot links and any thumbnails are greyed out?")
                }
            }
        },
        Case("UI-31", "The menu bar icon opens a glass panel", .look) { t in
            try await t.uiClosingUp {
                try t.needsInput()
                let ws = try await t.row(["UI-31 A", "UI-31 B", "UI-31 C"])
                t.link("focus", ["id": ws[0].id])
                let n = try await t.settle().windows.count
                ws[0].focus()
                try await t.pause(0.5)
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                guard let icon = t.uiStatusItem() else { throw Failure("can't find Expanse's menu bar icon") }
                let iconCentre = CGPoint(x: icon.midX, y: icon.midY)
                // It opens on the press, just under the icon, kept on screen, without taking the app you're in.
                Input.click(at: iconCentre)
                try await t.until("the panel to open", timeout: 2) { t.uiPanel() != nil }
                try await t.pause(0.3)
                guard let panel = t.uiPanel() else { throw Failure("the panel closed again by itself") }
                let glass = panel.frame.insetBy(dx: 24, dy: 24)
                try t.expect(t.screen.contains(glass), "the panel should be kept on screen (it's at \(glass))")
                try t.expect(glass.minY >= icon.maxY - 1 && glass.minY <= icon.maxY + 14, "the panel should open just under the icon (icon \(icon), panel \(glass))")
                try t.expect(abs(glass.midX - icon.midX) < 2 || glass.maxX >= t.screen.maxX - 12 || glass.minX <= 12,
                             "the panel should be centred under the icon unless that would take it off screen (icon \(icon), panel \(glass))")
                try t.expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == front,
                             "the app you were in should stay frontmost (it's \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") now)")
                // What's in it, top to bottom.
                let tree = try await t.uiPanelTree()
                if tree.has("Permission needed") { throw Skip("Expanse is missing a permission (the panel says Permission needed)") }
                let parts = ["Expanse", uiOn(n), "Open Expanse", "Centre window", "Tidy up", "Auto-centre focused window",
                             "Desktop picture background", "Window names when zoomed out", "Hot corner", "Earlier layouts", "Take snapshot",
                             "Restore all windows", "Permissions OK", "Welcome & Shortcuts", "Troubleshooting", "Settings…", "Quit Expanse"]
                let missing = parts.filter { !tree.has($0) }
                try t.expect(missing.isEmpty, "the panel is missing: \(missing.joined(separator: "; "))")
                try t.expect(tree.first("Expanse", role: kAXCheckBoxRole) != nil, "no on/off switch in the panel's header")
                let order = ["Open Expanse", "Centre window", "Auto-centre focused window", "Hot corner", "Earlier layouts", "Permissions OK"]
                let tops = order.compactMap { name in tree.flat.first { $0.says(name) }?.frame?.minY }
                try t.expect(tops.count == order.count && tops == tops.sorted(), "top to bottom the panel should have: \(order.joined(separator: ", "))")
                try await t.look("A rounded \(uiGlass) panel opened just under Expanse's icon: icon, status and switch; the minimap card with "
                                 + "⌥`; Centre window and Tidy up; three switches; Hot corner; Earlier layouts; a green dot with four round "
                                 + "buttons at the foot? (Answering closes it.)")
                try await t.uiClosePanel()
                // The icon again closes it, and that click doesn't open it again.
                try await t.pause(0.5)
                Input.click(at: iconCentre)
                try await t.until("the panel to open", timeout: 2) { t.uiPanel() != nil }
                try await t.pause(0.4)
                Input.click(at: iconCentre)
                try await t.until("the icon to close the panel", timeout: 2) { t.uiPanel() == nil }
                try await t.pause(0.6)
                try t.expect(t.uiPanel() == nil, "the click on the icon that closed the panel opened it again")
                // Esc closes it.
                Input.click(at: iconCentre)
                try await t.until("the panel to open", timeout: 2) { t.uiPanel() != nil }
                try await t.pause(0.3)
                Input.key(.escape)
                try await t.until("Esc to close the panel", timeout: 2) { t.uiPanel() == nil }
                // So does a click outside it.
                try await t.pause(0.5)
                Input.click(at: iconCentre)
                try await t.until("the panel to open", timeout: 2) { t.uiPanel() != nil }
                try await t.pause(0.3)
                guard let a = ws[0].real else { throw Failure("“UI-31 A” isn't on screen") }
                Input.click(at: CGPoint(x: a.midX, y: a.midY))
                try await t.until("a click outside to close the panel", timeout: 2) { t.uiPanel() == nil }
            }
        },
        Case("UI-32", "The panel's minimap opens the canvas and stays live", .look) { t in
            try await t.uiClosingUp {
                try t.needsInput()
                let ws = try await t.row(["UI-32 A", "UI-32 B"])
                t.link("focus", ["id": ws[1].id])
                try await t.settle()
                let b = ws[1].real ?? CGRect(x: 300, y: 300, width: 600, height: 400)
                _ = try await t.uiOpenPanel()
                try await t.uiLook("Watch the panel's minimap card while “UI-32 B” moves about: it draws every window as a block and the part "
                                   + "of the canvas on screen as an accent-coloured outline, and B's block follows within about half a second?", every: 1.2, [
                    { ws[1].setFrame(b.offsetBy(dx: 200, dy: 0)) }, { ws[1].setFrame(b.offsetBy(dx: 200, dy: 150)) },
                    { ws[1].setFrame(b.offsetBy(dx: -150, dy: 150)) }, { ws[1].setFrame(b) },
                ])
                try await t.uiClosePanel()
                // A click on the card closes the panel and zooms out, as ⌥` does.
                try t.uiPress("Open Expanse", in: try await t.uiOpenPanelTree())
                try await t.until("the panel to close", timeout: 2) { t.uiPanel() == nil }
                try await t.until("zoomed out") { let s = try await t.settle(); return s.active && s.scale < 1 }
                // Zoomed out, it reads Back to 100%, and goes back.
                try t.uiPress("Back to 100%", in: try await t.uiOpenPanelTree())
                try await t.until("back at 100%") { try await !t.settle().active }
                // Paused: Resume Expanse without ⌥`, dimmed with no outline; a click resumes and the panel stays.
                t.link("pause")
                try await t.untilPaused("paused")
                let tree = try await t.uiOpenPanelTree()
                guard let card = tree.button("Resume Expanse") else { throw Failure("paused, the minimap card should read “Resume Expanse”") }
                try t.expect(!card.flat.contains { $0.says("`") }, "paused, the card shouldn't show the ⌥` keys")
                try await t.look("Paused: the panel's minimap card is dimmed, with no outline? (Answering closes the panel.)")
                try t.uiPress("Resume Expanse", in: try await t.uiOpenPanelTree())
                try await t.until("resumed") { try await !t.state().paused }
                try await t.pause(0.5)
                try t.expect(t.uiPanel() != nil, "resuming from the card should leave the panel open")
                try await t.uiClosePanel()
            }
        },
        Case("UI-33", "The panel's switch pauses and resumes Expanse", .look) { t in
            try await t.uiClosingUp {
                try t.needsInput()
                let ws = try await t.row(["UI-33 A", "UI-33 B"])
                t.place(ws[1], at: CGPoint(x: 8000, y: 6000))
                try await t.until("B out of view") { try await t.state().window(ws[1].id)?.parked == true }
                var tree = try await t.uiOpenPanelTree()
                guard let on = tree.first("Expanse", role: kAXCheckBoxRole) else { throw Failure("no on/off switch in the panel's header") }
                try t.expect(on.on == true, "the header switch should be on")
                try t.expect(tree.flat.contains { $0.help == "Pause Expanse: windows go back to the macOS layout" },
                             "the switch's tooltip should read “Pause Expanse: windows go back to the macOS layout” while Expanse is on")
                // Off: windows back in the macOS layout, the panel still open, the canvas's commands greyed.
                var mark = t.log.mark()
                on.press()
                try await t.uiExpectLine("paused", since: mark)
                try await t.until("B back on screen") { ws[1].real.map { t.screen.insetBy(dx: 40, dy: 40).intersects($0) } ?? false }
                try t.expect(t.uiPanel() != nil, "pausing should leave the panel open")
                try await t.uiExpectStatus("Paused · windows back in the macOS layout")
                tree = try await t.uiPanelTree()
                guard let off = tree.first("Expanse", role: kAXCheckBoxRole) else { throw Failure("no on/off switch in the panel's header") }
                try t.expect(off.on == false, "the header switch should be off while paused")
                try t.expect(tree.flat.contains { $0.help == "Resume Expanse" }, "paused, the switch's tooltip should read “Resume Expanse”")
                let greyed: [(String, UINode?)] = [
                    ("Centre window", tree.button("Centre window")), ("Tidy up", tree.button("Tidy up")),
                    ("Take snapshot", tree.button("Take snapshot")), ("Restore all windows", tree.button("Restore all windows")),
                ] + tree.flat.filter { $0.role == kAXButtonRole && $0.help.hasPrefix("Put the windows back") }.map { ("a layout thumbnail", $0) }
                for (name, node) in greyed {
                    guard let node else { throw Failure("no \(name) in the panel") }
                    try t.expect(!node.enabled, "paused, \(name) should be disabled")
                }
                try await t.look("Paused: the panel's app icon is grey and its minimap dimmed? (Answering closes the panel.)")
                // On again: the canvas comes back from the saved layout.
                tree = try await t.uiOpenPanelTree()
                mark = t.log.mark()
                guard let again = tree.first("Expanse", role: kAXCheckBoxRole) else { throw Failure("no on/off switch in the panel's header") }
                again.press()
                try await t.uiExpectLine("resumed", since: mark)
                try await t.until("B out of view again", timeout: 15) { try await t.state().window(ws[1].id)?.parked == true }
                try await t.uiExpectStatus(uiOn(try await t.settle().windows.count), timeout: 4)
                try await t.uiClosePanel()
            }
        },
        Case("UI-34", "Centre window and Tidy up from the panel") { t in
            try await t.uiClosingUp {
                try t.needsInput()
                let ws = try await t.row(["UI-34 A", "UI-34 B", "UI-34 C"], gap: 45, origin: CGPoint(x: 30000, y: 0))
                // A on screen and off-centre: the window you're in.
                var s = try await t.settle()
                t.place(ws[0], at: CGPoint(x: s.camera.x + 60, y: s.camera.y + 60))
                s = try await t.settle()
                // Clicked, as you would: focus an app moves by itself within a second of Expanse
                // picking another of its windows looks like a steal, and is given back (1 Nov).
                guard let a = ws[0].real else { throw Failure("“UI-34 A” isn't on screen") }
                Input.click(at: CGPoint(x: a.midX, y: a.minY + 10))
                // Until Expanse has heard: Centre window goes to the window it last heard had focus,
                // and in a VM the notification can come well after.
                try await t.until("Expanse to hear “UI-34 A” has focus", timeout: 5) { try await t.state().focusedByApp[getpid()] == ws[0].id }
                var mark = t.log.mark()
                try t.uiPress("Centre window", in: try await t.uiOpenPanelTree())
                try await t.until("the panel to close", timeout: 2) { t.uiPanel() == nil }
                let id = ws[0].id
                guard await t.log.wait(since: mark, timeout: 5, { $0.hasPrefix("centre ") && $0.contains("[\(id)]") }) != nil else {
                    throw Failure("Centre window didn't centre “UI-34 A”, the window you were in (no “centre …[\(id)]” line)")
                }
                try await t.until("A in the middle of the screen", timeout: 5) {
                    guard let r = ws[0].real else { return false }
                    return hypot(r.midX - s.viewport.midX, r.midY - s.viewport.midY) < 10
                }
                // Tidy up: each group lined up and evenly spaced where it is, shown zoomed out.
                mark = t.log.mark()
                try t.uiPress("Tidy up", in: try await t.uiOpenPanelTree())
                try await t.until("the panel to close", timeout: 2) { t.uiPanel() == nil }
                try await t.expectLog("layout fitted:", since: mark, timeout: 10)
                s = try await t.settle()
                try t.expect(s.active, "Tidy up should show the result zoomed out")
                guard let fb = s.window(ws[1].id)?.canvas, let fc = s.window(ws[2].id)?.canvas else { throw Failure("B or C left the canvas") }
                try t.expect(abs(fc.minX - fb.maxX - 20) <= 1 && abs(fc.minY - fb.minY) <= 1, "Tidy up should line B and C up 20pt apart (B \(fb), C \(fc))")
                t.link("exit")
                try await t.until("back at 100%") { try await !t.settle().active }
                // Paused, both tiles are greyed and do nothing.
                t.link("pause")
                try await t.untilPaused("paused")
                let tree = try await t.uiOpenPanelTree()
                for title in ["Centre window", "Tidy up"] {
                    guard let tile = tree.button(title) else { throw Failure("no “\(title)” tile in the panel") }
                    try t.expect(!tile.enabled, "paused, “\(title)” should be greyed out")
                    mark = t.log.mark()
                    tile.press()
                    try await t.pause(1)
                    try t.expect(!t.log.lines(since: mark).contains { $0.hasPrefix("centre ") || $0.hasPrefix("layout fitted") },
                                 "paused, “\(title)” should do nothing")
                }
                try await t.uiClosePanel()
                t.link("resume")
                try await t.until("resumed") { try await !t.state().paused }
            }
        },
        Case("UI-35", "The panel's switches change settings and leave the panel open", .look) { t in
            try await t.uiClosingUp {
                try t.needsInput()
                let keys = ["autoCentre", "background", "showWindowNames"]
                let olds = keys.map { expanseDefault($0) }
                defer { for (k, v) in zip(keys, olds) { setExpanseDefault(k, v) } }
                _ = try await t.row(["UI-35 A", "UI-35 B"])
                let switches: [(title: String, read: () -> Bool)] = [
                    ("Auto-centre focused window", { (expanseDefault("autoCentre") as? Bool) ?? true }),
                    ("Desktop picture background", { (expanseDefault("background") as? String) != "plain" }),
                    ("Window names when zoomed out", { (expanseDefault("showWindowNames") as? Bool) ?? false }),
                ]
                let original = switches.map { $0.read() }
                var tree = try await t.uiOpenPanelTree()
                try t.expect(tree.has("⇧"), "the panel should show ⌥⇧` beside Auto-centre")
                // Each flips at once, and the panel stays open.
                for sw in switches {
                    let before = sw.read()
                    guard let node = tree.first(sw.title, role: kAXCheckBoxRole) else { throw Failure("no “\(sw.title)” switch in the panel") }
                    try t.expect(node.on == before, "“\(sw.title)” should show the current setting (\(before ? "on" : "off"))")
                    node.press()
                    try await t.until("“\(sw.title)” to flip", timeout: 3) { sw.read() != before }
                    try await t.pause(0.3)
                    try t.expect(t.uiPanel() != nil, "flipping “\(sw.title)” should leave the panel open")
                    tree = try await t.uiPanelTree()
                }
                try await t.uiClosePanel()
                // Auto-centre is the same setting as ⌥⇧`.
                let autoCentre = switches[0].read()
                Input.key(.grave, [.maskAlternate, .maskShift])
                try await t.until("⌥⇧` to flip Auto-centre", timeout: 3) { switches[0].read() != autoCentre }
                // Each time the panel opens, its switches show the settings as they are.
                tree = try await t.uiOpenPanelTree()
                for sw in switches {
                    try t.expect(tree.first(sw.title, role: kAXCheckBoxRole)?.on == sw.read(), "reopened, “\(sw.title)” should show the current setting")
                }
                // The desktop picture and the names, zoomed out.
                for sw in switches.dropFirst() where !sw.read() {
                    tree.first(sw.title, role: kAXCheckBoxRole)?.press()
                    try await t.until("“\(sw.title)” on", timeout: 3) { sw.read() }
                }
                try await t.uiClosePanel()
                try await t.pause(2.5)
                t.link("enter")
                try await t.settle()
                try await t.pause(1)
                try await t.look("Zoomed out: the desktop picture shows behind the windows, and each window has its app's name above it?")
                t.link("exit")
                try await t.settle()
                // Back as they were, from the panel.
                tree = try await t.uiOpenPanelTree()
                for (sw, was) in zip(switches, original) where sw.read() != was {
                    tree.first(sw.title, role: kAXCheckBoxRole)?.press()
                    try await t.until("“\(sw.title)” back", timeout: 3) { sw.read() == was }
                }
                try await t.uiClosePanel()
            }
        },
        Case("UI-37", "A banner in the panel when a permission is missing", .guided) { t in
            try await t.uiClosingUp {
                try t.needsInput()
                let settingsRan = uiSystemSettingsRunning()
                defer { if !settingsRan { uiQuitSystemSettings() } }
                var failure: Error?
                do {
                    try await t.ask("In System Settings › Privacy & Security › Screen Recording, switch Expanse off, leaving Accessibility on. (If macOS offers to quit Expanse, choose Later.)")
                    var tree = try await t.uiOpenPanelTree()
                    for text in ["Screen Recording is off", "Zoomed out, windows show as outlines without it. Once it's on, reopen Expanse.", "Permission needed"] {
                        try t.expect(tree.has(text), "the panel should say “\(text)”")
                    }
                    try await t.uiPressBanner(tree)
                    try await t.look("macOS asked for Screen Recording for Expanse (its prompt, or System Settings at Screen Recording)?")
                    try await t.ask("Switch Screen Recording back on for Expanse, and switch Accessibility off for it.")
                    tree = try await t.uiOpenPanelTree()
                    for text in ["Accessibility is off", "Expanse can't move windows without it.", "Permission needed"] {
                        try t.expect(tree.has(text), "the panel should say “\(text)”")
                    }
                    try await t.uiPressBanner(tree)
                    try await t.look("macOS asked for Accessibility for Expanse (its prompt, or System Settings at Accessibility)?")
                    try await t.ask("Switch Screen Recording off for Expanse too (Accessibility stays off).")
                    tree = try await t.uiOpenPanelTree()
                    try t.expect(tree.has("Accessibility and Screen Recording are off"), "the panel should say “Accessibility and Screen Recording are off”")
                    try await t.uiClosePanel()
                } catch {
                    failure = error
                }
                // Both back, and Expanse reopened so Screen Recording takes effect.
                try? await t.uiClosePanel()
                do {
                    try await t.ask("Put both back: switch Accessibility and Screen Recording on for Expanse. Expanse reopens when you press Done.")
                    try await t.relaunchExpanse()
                } catch {
                    failure = failure ?? error
                }
                if let failure { throw failure }
            }
        },
        Case("UI-38", "The Settings window", .guided) { t in
            try await t.uiClosingUp {
                try t.needsInput()
                let settingsRan = uiSystemSettingsRunning()
                defer { if !settingsRan { uiQuitSystemSettings() } }
                let oldSetUp = expanseDefault("loginItemSetUp")
                defer { setExpanseDefault("loginItemSetUp", oldSetUp) }
                try await t.window("UI-38 A")
                t.link("enter")
                try await t.until("zoomed out") { try await t.settle().active }
                // The canvas closes first, then a small Expanse Settings window opens in front.
                let first = try await t.uiOpenSettings()
                let s = try await t.settle()
                try t.expect(!s.active, "the gear should close the canvas first (back to 100%)")
                try t.uiExpectInFront(first.win, "Expanse Settings")
                let tree = first.tree
                let version = Bundle(url: t.expanseURL)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                guard let login = tree.first("Open Expanse at login", role: kAXCheckBoxRole) else { throw Failure("no “Open Expanse at login” switch") }
                guard let automatic = tree.first("Check for updates automatically", role: kAXCheckBoxRole) else {
                    throw Failure("no “Check for updates automatically” switch")
                }
                guard let checkNow = tree.button("Check Now") else { throw Failure("no Check Now button") }
                try t.expect(tree.has("Updates"), "no Updates section")
                try t.expect(tree.has("Expanse \(version)"), "no “Expanse \(version)” beside Check Now")
                if uiIsRelease(t.expanseURL) {
                    try t.expect(automatic.enabled && checkNow.enabled, "in a release the Updates section should be usable")
                } else {
                    try t.expect(!automatic.enabled && !checkNow.enabled, "in a development build the Updates section should be greyed out")
                    try t.expect(tree.has(uiDevNote), "no development-build footnote (“\(uiDevNote)”)")
                }
                // The login switch adds or removes Expanse in Login Items.
                let wasOn = login.on ?? false
                try await t.uiSetLogin(!wasOn)
                NSWorkspace.shared.open(uiLoginItemsPane)
                try await t.look("System Settings › General › Login Items: Expanse is \(wasOn ? "no longer" : "now") listed under Open at Login?")
                // A change made in System Settings shows when the window is key again.
                try await t.uiSetLogin(true)
                try await t.ask("In System Settings › Login Items, select Expanse under Open at Login and click −. Then click the Expanse Settings window.")
                try await t.until("the switch to show the change", timeout: 5) { t.uiLoginSwitch() == false }
                if wasOn { try await t.uiSetLogin(true) }
                // The gear again brings back the same window.
                if let w = t.uiSettings() { _ = uiPressClose(w.tree) }
                try await t.until("Settings to close", timeout: 3) { t.uiSettings() == nil }
                let second = try await t.uiOpenSettings()
                try t.expect(second.win.id == first.win.id, "the gear should bring back the same Settings window (it was \(first.win.id), now \(second.win.id))")
                _ = uiPressClose(second.tree)
            }
        },
    ]
}

// MARK: - Levels and sizes

/// Zoomed out, the canvas sits just under the menu bar (OverlayWindow.canvasLevel)…
private let uiCanvasLevel = Int(CGWindowLevelForKey(.mainMenuWindow)) - 1
/// …and at 100% under every app window (OverlayWindow.backdropLevel).
private let uiBackdropLevel = Int(CGWindowLevelForKey(.backstopMenu))
private let uiMenuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
private let uiDockLevel = Int(CGWindowLevelForKey(.dockWindow))
/// The menu bar panel (MenuPanel): pop-up menu level, 360pt of glass with 24pt round it for its shadow.
private let uiPanelLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
private let uiPanelWidth: CGFloat = 360 + 2 * 24
private let uiMinimapSize = CGSize(width: 208, height: 136)
private let uiWelcomeSize = CGSize(width: 960, height: 620)
private let uiDevNote = "This is a development build: it has no updates, and opening at login opens this copy."
private let uiLoginItemsPane = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

private var uiGlass: String {
    ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
        ? "Liquid Glass" : "frosted (HUD material)"
}

private func uiOn(_ n: Int) -> String { "On · \(n) window\(n == 1 ? "" : "s") on the canvas" }

private func uiPercent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

private func uiSame(_ a: CGRect, _ b: CGRect, within d: CGFloat = 2) -> Bool {
    max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height)) <= d
}

// MARK: - Expanse's windows, as the window server has them

/// One of Expanse's windows (or another app's): where, at what level, and whether it shows.
private struct UIWin {
    let id: CGWindowID
    let frame: CGRect
    let layer: Int
    let alpha: Double
}

/// On-screen windows front to back, any level, that pass `include`.
private func uiScreenWindows(_ include: ([String: Any]) -> Bool) -> [UIWin] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.filter(include).compactMap { w in
        guard let id = w[kCGWindowNumber as String] as? CGWindowID,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) else { return nil }
        return UIWin(id: id, frame: r, layer: w[kCGWindowLayer as String] as? Int ?? 0, alpha: w[kCGWindowAlpha as String] as? Double ?? 1)
    }
}

fileprivate extension Ctx {
    var uiPID: pid_t? { expanse?.processIdentifier }

    func uiWindows(pid: pid_t? = nil) -> [UIWin] {
        guard let pid = pid ?? uiPID else { return [] }
        return uiScreenWindows { ($0[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid }
    }

    func uiWindows(owner: String) -> [UIWin] {
        uiScreenWindows { $0[kCGWindowOwnerName as String] as? String == owner }
    }

    /// The canvas's own window (OverlayWindow): the screen below the menu bar.
    func uiOverlay(_ s: ExpanseState) -> UIWin? {
        uiWindows().first { uiSame($0.frame, s.viewport) && $0.layer <= uiCanvasLevel }
    }

    /// The menu bar panel, while it's open.
    func uiPanel() -> UIWin? {
        uiWindows().first { $0.layer == uiPanelLevel && abs($0.frame.width - uiPanelWidth) < 2 && $0.alpha > 0.01 }
    }

    /// The walkthrough (or Welcome & Shortcuts) window.
    func uiWelcome() -> UIWin? {
        uiWindows().first { $0.layer == 0 && abs($0.frame.width - uiWelcomeSize.width) < 2 && abs($0.frame.height - uiWelcomeSize.height) < 2 }
    }

    /// What CanvasController.lowestDialogLevel would count as a dialog: another app's window above
    /// app windows and under the canvas, at least 100×50pt, not see-through, not the Dock's.
    func uiDialogsOnScreen() -> [String] {
        let modal = Int(CGWindowLevelForKey(.modalPanelWindow)), pid = uiPID
        let screen = CGDisplayBounds(CGMainDisplayID()).size
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { w in
            guard let layer = w[kCGWindowLayer as String] as? Int, layer >= modal, layer < uiCanvasLevel,
                  let owner = w[kCGWindowOwnerPID as String] as? Int, pid_t(owner) != pid,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
                  r.width >= 100, r.height >= 50,
                  // Not a window over the whole screen, as Expanse counts them (UI-41).
                  r.width < screen.width || r.height < screen.height,
                  NSRunningApplication(processIdentifier: pid_t(owner))?.bundleIdentifier != "com.apple.dock" else { return nil }
            return w[kCGWindowOwnerName as String] as? String ?? "?"
        }
    }

    /// A menu of `owner`'s on screen (a context menu, say).
    func uiMenuShowing(owner: String) -> Bool {
        uiWindows(owner: owner).contains { $0.layer >= uiPanelLevel }
    }

    /// A spot of bare desktop, where a click or scroll reaches the desktop itself: no window over
    /// it, and away from the minimap and Spaces panels and the slivers at the screen's edges.
    func uiBareDesktopPoint(_ s: ExpanseState) -> CGPoint? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let covered: [CGRect] = info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int ?? 0) >= 0, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: b)
        }
        let panels = CGRect(x: s.viewport.maxX - 800, y: s.viewport.maxY - 180, width: 800, height: 180)
        let area = s.viewport.insetBy(dx: 160, dy: 120)
        guard !area.isEmpty else { return nil }
        for y in stride(from: area.minY, to: area.maxY, by: 40) {
            for x in stride(from: area.minX, to: area.maxX, by: 40) {
                let p = CGPoint(x: x, y: y)
                if !panels.contains(p), !covered.contains(where: { $0.insetBy(dx: -20, dy: -20).contains(p) }) { return p }
            }
        }
        return nil
    }

    /// Expanse is the active app and `w` the front ordinary window.
    func uiExpectInFront(_ w: UIWin, _ what: String) throws {
        let front = NSWorkspace.shared.frontmostApplication
        try expect(front?.processIdentifier == uiPID, "\(what) should come to the front (the frontmost app is \(front?.localizedName ?? "none"))")
        let ordinary = uiScreenWindows { w in
            (w[kCGWindowLayer as String] as? Int) == 0 && (w[kCGWindowAlpha as String] as? Double ?? 1) > 0
        }.first { $0.frame.width >= 100 && $0.frame.height >= 100 }
        try expect(ordinary?.id == w.id, "\(what) should be in front of every other window")
    }

    /// Expanse's CPU use over `seconds`, as a share of one core.
    func uiCPU(over seconds: TimeInterval) async throws -> Double {
        guard let pid = uiPID, let a = uiCPUTime(pid) else { throw Failure("can't read Expanse's CPU time") }
        try await pause(seconds)
        guard let b = uiCPUTime(pid) else { throw Failure("can't read Expanse's CPU time") }
        return (b - a) / seconds
    }

    /// Asks `question` while `steps` run, one every `every` seconds, so you can watch them happen.
    func uiLook(_ question: String, every: TimeInterval, _ steps: [@MainActor () -> Void]) async throws {
        let motion = Task { @MainActor in
            for step in steps {
                try await Task.sleep(nanoseconds: UInt64(every * 1e9))
                step()
            }
        }
        defer { motion.cancel() }
        try await look(question)
    }

    /// The exact log line `line`, since `mark` (dump's lines say paused= too).
    func uiExpectLine(_ line: String, since mark: Int, timeout: TimeInterval = 8) async throws {
        guard await log.wait(since: mark, timeout: timeout, { $0 == line }) != nil else { throw Failure("no log line “\(line)”") }
    }

    /// A fixture app's window full screen in a Space of its own, and the view back on the canvas's
    /// desktop, so the Spaces panel shows.
    func uiFullScreenFixture(_ name: String) async throws {
        let f = try await fixture(name, windows: 1)
        try await f.send("fullscreen", ["index": "0"])
        try await pause(3)
        link("space", ["name": "expanse"])
        try await pause(2)
    }
}

/// Expanse's CPU time so far, in seconds (`ps`: [[hh:]mm:]ss.cc).
private func uiCPUTime(_ pid: pid_t) -> Double? {
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

/// macOS's own hot corners that fire with no key held, e.g. "top-right".
private func uiMacCornersInUse() -> [String] {
    let dock = "com.apple.dock" as CFString
    CFPreferencesAppSynchronize(dock)
    return [("tl", "top-left"), ("tr", "top-right"), ("bl", "bottom-left"), ("br", "bottom-right")].compactMap { key, name in
        let action = CFPreferencesCopyAppValue("wvous-\(key)-corner" as CFString, dock) as? Int ?? 1
        let modifier = CFPreferencesCopyAppValue("wvous-\(key)-modifier" as CFString, dock) as? Int ?? 0
        return action > 1 && modifier == 0 ? name : nil
    }
}

private func uiRightClick(at p: CGPoint) {
    Input.move(to: p)
    for type in [CGEventType.rightMouseDown, .rightMouseUp] {
        let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .right)
        e?.flags = []
        e?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}

/// Signed with a Developer ID, as Updater.isRelease checks: a release, which updates and opens at login by itself.
private func uiIsRelease(_ app: URL) -> Bool {
    var code: SecStaticCode?, requirement: SecRequirement?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
          SecRequirementCreateWithString("anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]" as CFString,
                                         [], &requirement) == errSecSuccess, let requirement else { return false }
    return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
}

/// Why a case that needs a release can't run here.
@MainActor private func uiNeedsRelease(_ t: Ctx, _ what: String) -> String {
    uiIsRelease(t.expanseURL)
        ? "needs \(what); the runner drives development builds (a release ignores the debug links it uses)"
        : "needs \(what), signed with a Developer ID; this is a development build, which never updates"
}

private func uiSystemSettingsRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").isEmpty
}

private func uiQuitSystemSettings() {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").forEach { $0.terminate() }
}

private func uiSystemSettingsInFront() -> Bool {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
}

/// One of macOS's permission prompts on screen (see Permissions.prompts in Onboarding.swift).
private func uiPermissionPrompt() -> UIWin? {
    uiScreenWindows { $0[kCGWindowOwnerName as String] as? String == "universalAccessAuthWarn" }.first
}

// MARK: - The minimap

/// The canvas point under `p` in the minimap (its layer's coordinates, bottom-left origin), worked
/// out as Minimap.update and canvasPoint(at:) do, and the map's scale.
private func uiMinimapCanvasPoint(_ s: ExpanseState, _ p: CGPoint) -> (point: CGPoint, scale: CGFloat) {
    let mapArea = CGRect(x: 14, y: 12, width: uiMinimapSize.width - 28, height: uiMinimapSize.height - 44)
    var bounds = s.windows.map(\.canvas).reduce(s.visibleCanvas) { $0.union($1) }
    bounds = bounds.insetBy(dx: -bounds.width * 0.04, dy: -bounds.height * 0.04)
    let fit = mapArea.insetBy(dx: 4, dy: 4)
    let scale = min(fit.width / bounds.width, fit.height / bounds.height)
    let offset = CGPoint(x: fit.minX + (fit.width - bounds.width * scale) / 2, y: fit.minY + (fit.height - bounds.height * scale) / 2)
    let top = mapArea.maxY - (offset.y - mapArea.minY)
    return (CGPoint(x: (p.x - offset.x) / scale + bounds.minX, y: (top - p.y) / scale + bounds.minY), scale)
}

// MARK: - Hot corners

private enum UICorner: String, CaseIterable {
    case topLeft = "top-left", topRight = "top-right", bottomLeft = "bottom-left", bottomRight = "bottom-right"
}

fileprivate extension Ctx {
    /// Picks a corner in the panel's Hot corner card (a dot of the little screen, or a pill).
    func uiPickCorner(_ control: String, _ value: String) async throws {
        try uiPress(control, in: try await uiOpenPanelTree())
        try await until("the hot corner to be \(value)", timeout: 3) { expanseDefault("hotCorner") as? String == value }
        try await pause(0.4)
        try expect(uiPanel() != nil, "the panel should stay open as you pick a corner")
        try await uiClosePanel()
    }

    /// Rests the pointer in each corner of the screen: those in `opening` open the canvas, the rest don't.
    func uiCheckCorners(opening: Set<UICorner>) async throws {
        let middle = CGPoint(x: screen.midX, y: screen.midY)
        for c in UICorner.allCases {
            Input.move(to: middle)
            try await pause(0.3)
            let p: CGPoint
            switch c {
            case .topLeft: p = CGPoint(x: 0, y: 0)
            case .topRight: p = CGPoint(x: screen.maxX - 1, y: 0)
            case .bottomLeft: p = CGPoint(x: 0, y: screen.maxY - 1)
            case .bottomRight: p = CGPoint(x: screen.maxX - 1, y: screen.maxY - 1)
            }
            Input.move(to: p)
            if opening.contains(c) {
                try await until("the \(c.rawValue) corner to open the canvas", timeout: 3) { try await self.state().active }
                Input.move(to: middle)
                link("exit")
                try await until("back at 100%") { try await !self.settle().active }
            } else {
                try await pause(1)
                let opened = try await state().active
                Input.move(to: middle)
                if opened {
                    link("exit")
                    _ = try? await settle()
                }
                try expect(!opened, "the \(c.rawValue) corner opened the canvas, but it isn't Expanse's corner now")
            }
        }
        Input.move(to: middle)
    }

    /// Puts Expanse's hot corner back as it was, from the panel (or, failing that, by relaunching).
    func uiRestoreCorner(_ old: String?) async {
        let controls = ["all": "All corners", "off": "Off", "topLeft": "Top left corner", "topRight": "Top right corner",
                        "bottomLeft": "Bottom left corner", "bottomRight": "Bottom right corner"]
        let value = old ?? "all"
        if expanseDefault("hotCorner") as? String != value, (try? await uiPickCorner(controls[value] ?? "All corners", value)) == nil {
            try? await uiClosePanel()
            setExpanseDefault("hotCorner", old)
            try? await relaunchExpanse()
        }
        if old == nil { setExpanseDefault("hotCorner", nil) }
    }
}

// MARK: - Accessibility: the panel, the walkthrough, Settings

/// Part of Expanse's interface as Accessibility has it, read in one go per element.
private final class UINode {
    let el: AXUIElement
    let role: String, title: String, label: String, help: String
    let value: AnyObject?
    let enabled: Bool
    let frame: CGRect?
    let children: [UINode]
    lazy var flat: [UINode] = [self] + children.flatMap { $0.flat }

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
        var kids: [UINode] = []
        if depth < 40, let list = at(8) as? [AnyObject] {
            for k in list where budget > 0 && CFGetTypeID(k) == AXUIElementGetTypeID() {
                kids.append(UINode(unsafeBitCast(k, to: AXUIElement.self), budget: &budget, depth: depth + 1))
            }
        }
        children = kids
    }

    var string: String { value as? String ?? "" }
    /// A switch's state.
    var on: Bool? { (value as? NSNumber)?.boolValue }
    var words: [String] { [title, label, string, help].filter { !$0.isEmpty } }
    func says(_ s: String) -> Bool { words.contains { $0.caseInsensitiveCompare(s) == .orderedSame } }
    func has(_ s: String) -> Bool { flat.contains { $0.says(s) } }
    func first(_ s: String, role: String? = nil) -> UINode? { flat.first { (role == nil || $0.role == role) && $0.says(s) } }

    /// A button that says `s`, or holds a text that does, or failing those mentions it.
    func button(_ s: String) -> UINode? {
        let buttons = flat.filter { $0.role == kAXButtonRole }
        return buttons.first { $0.says(s) } ?? buttons.first { $0.flat.dropFirst().contains { $0.says(s) } }
            ?? buttons.first { $0.words.contains { $0.contains(s) } }
    }

    @discardableResult func press() -> Bool { AXUIElementPerformAction(el, kAXPressAction as CFString) == .success }
}

/// A window's close button, pressed.
private func uiPressClose(_ window: UINode) -> Bool {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window.el, kAXCloseButtonAttribute as CFString, &v) == .success, let v,
          CFGetTypeID(v) == AXUIElementGetTypeID() else { return false }
    return AXUIElementPerformAction(unsafeBitCast(v, to: AXUIElement.self), kAXPressAction as CFString) == .success
}

fileprivate extension Ctx {
    /// Runs `body`, then closes whatever of Expanse's it left open (the menu bar panel, the
    /// walkthrough, Settings), passing or failing, so the next case starts clear.
    func uiClosingUp(_ body: () async throws -> Void) async throws {
        var failure: Error?
        do { try await body() } catch { failure = error }
        if uiPanel() != nil, Input.allowed { Input.key(.escape) }
        if let w = uiWelcome(), let tree = uiTree(at: w.frame) { _ = uiPressClose(tree) }
        if let settings = uiSettings() { _ = uiPressClose(settings.tree) }
        if let failure { throw failure }
    }

    /// Reading Expanse's panels needs Accessibility for Expanse Tests, as input does.
    func uiNeedsAX() throws {
        if !AXIsProcessTrusted() { throw Skip("needs Accessibility for Expanse Tests, to read and press Expanse's panels") }
    }

    /// Expanse's windows as Accessibility lists them (its panels too, which some lists leave out).
    func uiAXWindows() -> [AXUIElement] {
        guard let pid = uiPID else { return [] }
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
    func uiTree(at frame: CGRect) -> UINode? {
        for el in uiAXWindows() {
            var one = 1
            guard let f = UINode(el, budget: &one).frame, uiSame(f, frame) else { continue }
            var budget = 3000
            return UINode(el, budget: &budget)
        }
        return nil
    }

    /// The menu bar panel's contents (it must be open).
    func uiPanelTree() async throws -> UINode {
        var tree: UINode?
        try await until("the menu bar panel's contents (through Accessibility)", timeout: 4) {
            guard let p = self.uiPanel() else { return false }
            tree = self.uiTree(at: p.frame)
            return tree?.has("Quit Expanse") == true
        }
        return tree!
    }

    @discardableResult
    func uiOpenPanel() async throws -> UIWin {
        if let p = uiPanel() { return p }
        link("menu")
        var panel: UIWin?
        try await until("the menu bar panel to open") {
            panel = self.uiPanel()
            return panel != nil
        }
        try await pause(0.25)   // its fade
        return panel!
    }

    func uiOpenPanelTree() async throws -> UINode {
        try await uiOpenPanel()
        return try await uiPanelTree()
    }

    /// Esc (the panel takes key focus without activating Expanse).
    func uiClosePanel() async throws {
        guard uiPanel() != nil else { return }
        if Input.allowed { Input.key(.escape) } else { try await ask("Press Esc to close Expanse's menu bar panel.") }
        try await until("the menu bar panel to close", timeout: 3) { self.uiPanel() == nil }
    }

    /// Expanse's menu bar icon, in screen coordinates.
    func uiStatusItem() -> CGRect? {
        guard let pid = uiPID else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var bar: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar,
           CFGetTypeID(bar) == AXUIElementGetTypeID() {
            var budget = 20
            if let f = UINode(unsafeBitCast(bar, to: AXUIElement.self), budget: &budget).children.first?.frame, f.width > 0 { return f }
        }
        return uiWindows().first { $0.layer == Int(CGWindowLevelForKey(.statusWindow)) && $0.frame.width < 80 && $0.frame.minY < 60 }?.frame
    }

    /// Opens the panel with a click on the menu bar icon (expanse:// links wait for the walkthrough).
    func uiClickIcon() async throws {
        guard let icon = uiStatusItem() else { throw Failure("can't find Expanse's menu bar icon") }
        Input.click(at: CGPoint(x: icon.midX, y: icon.midY))
        try await until("the panel to open", timeout: 3) { self.uiPanel() != nil }
        try await pause(0.25)
    }

    /// A click on it, as you'd click it: a real click where Accessibility says it is (a press
    /// through Accessibility isn't your input, and macOS then won't let Expanse come forward).
    func uiPress(_ label: String, in tree: UINode) throws {
        guard let node = tree.button(label) ?? tree.first(label) else { throw Failure("no “\(label)” in Expanse's panel (through Accessibility)") }
        if Input.allowed, let f = node.frame, f.width > 0, f.height > 0 {
            Input.click(at: CGPoint(x: f.midX, y: f.midY))
        } else {
            try expect(node.press(), "couldn't press “\(label)”")
        }
    }

    /// The panel's status line (On · …, Paused · …, Starts once…).
    func uiStatus(_ tree: UINode) -> String? {
        tree.flat.first { n in ["On · ", "Paused · ", "Starts once"].contains { n.string.hasPrefix($0) } }?.string
    }

    func uiExpectStatus(_ status: String, timeout: TimeInterval = 3) async throws {
        var last: String?
        do {
            try await until("the panel's status to read “\(status)”", timeout: timeout) {
                last = self.uiStatus(try await self.uiPanelTree())
                return last == status
            }
        } catch {
            throw Failure("the panel's status reads “\(last ?? "nothing")”, not “\(status)”")
        }
    }

    /// The permission banner's Open System Settings: macOS's prompt, or System Settings, comes up.
    func uiPressBanner(_ tree: UINode) async throws {
        try uiPress("Open System Settings", in: tree)
        try await until("the panel to close", timeout: 2) { self.uiPanel() == nil }
        try await until("macOS's prompt or System Settings", timeout: 6) { uiPermissionPrompt() != nil || uiSystemSettingsInFront() }
    }

    /// The walkthrough: its main button (Get started, Continue, Skip for now) until the page's
    /// heading reads `heading` (as shown: “STEP 3 OF 4”).
    func uiWalkthrough(to heading: String) async throws {
        for _ in 0..<6 {
            guard let w = uiWelcome(), let tree = uiTree(at: w.frame) else { throw Failure("the walkthrough isn't open") }
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
    func uiCloseWelcome() async throws {
        guard let w = uiWelcome() else { return }
        guard let tree = uiTree(at: w.frame), uiPressClose(tree) else { throw Failure("couldn't press the walkthrough's close button") }
        try await until("the walkthrough to close", timeout: 3) { self.uiWelcome() == nil }
    }

    /// Runs `body` with the walkthrough reset and showing (Expanse not started yet), then marks it
    /// done again, as it was, with Expanse running.
    func uiBeforeWalkthrough(_ body: () async throws -> Void) async throws {
        let done = expanseDefault("onboardingDone"), page = expanseDefault("onboardingPage")
        var failure: Error?
        do {
            try await quitExpanse()
            setExpanseDefault("onboardingDone", nil)
            setExpanseDefault("onboardingPage", nil)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: expanseURL, configuration: config)
            try await until("the walkthrough to open", timeout: 20) { self.uiWelcome() != nil }
            try await body()
        } catch {
            failure = error
        }
        try? await uiClosePanel()
        try? await quitExpanse()
        setExpanseDefault("onboardingDone", done)
        setExpanseDefault("onboardingPage", page)
        do { try await launchExpanse() } catch { failure = failure ?? error }
        if let failure { throw failure }
    }

    /// The Expanse Settings window and its contents, if it's open.
    func uiSettings() -> (win: UIWin, tree: UINode)? {
        for el in uiAXWindows() {
            var one = 1
            let shallow = UINode(el, budget: &one)
            guard shallow.title == "Expanse Settings", let f = shallow.frame,
                  let win = uiWindows().first(where: { $0.layer == 0 && uiSame($0.frame, f) }) else { continue }
            var budget = 2000
            return (win, UINode(el, budget: &budget))
        }
        return nil
    }

    /// Settings, from the panel's gear.
    func uiOpenSettings() async throws -> (win: UIWin, tree: UINode) {
        try uiPress("Settings…", in: try await uiOpenPanelTree())
        var found: (win: UIWin, tree: UINode)?
        try await until("the Expanse Settings window", timeout: 5) {
            found = self.uiSettings()
            return found != nil
        }
        return found!
    }

    func uiLoginSwitch() -> Bool? { uiSettings()?.tree.first("Open Expanse at login", role: kAXCheckBoxRole)?.on }

    /// Settings' “Open Expanse at login”, flipped to `on` if it isn't. Switched off in System
    /// Settings, macOS may want your OK there first.
    func uiSetLogin(_ on: Bool) async throws {
        guard let sw = uiSettings()?.tree.first("Open Expanse at login", role: kAXCheckBoxRole) else { throw Failure("Expanse Settings isn't open") }
        if sw.on == on { return }
        sw.press()
        do {
            try await until("“Open Expanse at login” to turn \(on ? "on" : "off")", timeout: 3) { self.uiLoginSwitch() == on }
        } catch where on {
            try await ask("macOS wants your OK: in System Settings › Login Items, switch Expanse on. Then click the Expanse Settings window.")
            try await until("“Open Expanse at login” to show on", timeout: 5) { self.uiLoginSwitch() == true }
        }
    }
}

// MARK: - A dialog of our own

/// A window of Expanse Tests at modal-panel level, as an alert or a password prompt is: what the
/// canvas must stay under while it's up.
@MainActor private final class UIDialog: NSObject {
    let panel: NSPanel
    private(set) var clicked = false
    private var button: NSButton?

    init(size: CGSize = CGSize(width: 420, height: 160), alpha: CGFloat = 1, titled: Bool = true) {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: titled ? [.titled, .nonactivatingPanel] : [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = "Expanse Tests"
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .windowBackgroundColor
        if titled {
            let b = UIFirstClickButton(title: "OK", target: self, action: #selector(press))
            b.frame = NSRect(x: size.width - 100, y: 16, width: 80, height: 32)
            panel.contentView?.addSubview(b)
            button = b
        }
        panel.alphaValue = alpha
        panel.center()
        panel.orderFrontRegardless()
    }

    var level: Int { panel.level.rawValue }

    /// Its OK button, in screen coordinates.
    var buttonCentre: CGPoint? {
        guard let b = button else { return nil }
        let r = panel.convertToScreen(b.convert(b.bounds, to: nil))
        return CGPoint(x: r.midX, y: (NSScreen.screens.first?.frame.height ?? 0) - r.midY)
    }

    @objc private func press() { clicked = true }

    func close() { panel.orderOut(nil) }
}

/// Takes the first click, as an alert's button does.
private final class UIFirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
