# NAV: Canvas, zoom and navigation

[All areas](README.md)

## NAV-01 ⌥` zooms out to every window, and back
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0), 2b994e0 (0.1.0)
- **Setup:** Expanse running (walkthrough done, Accessibility and Screen Recording granted, auto-centre on, hot corner All corners: the defaults, assumed by every case unless it says otherwise). At 100%, five or more windows spread over the canvas, some out of view.
- **Steps:**
  1. Press ⌥`.
  2. Press ⌥` again.
- **Expected:** Step 1: the canvas rises over everything and animates out until every window is in view with a margin; every window shows as a live picture. Step 2: the view animates back to exactly the 100% view you had before step 1, the real windows are where the canvas showed them, and the front-most window on screen has the keyboard.
- **Automate:** unit: `CanvasController.overviewCamera()` / `fitCamera(maxScale:)` for the target camera | manual: the toggle itself needs the overlay and real windows.
- **Note:** Before 2b994e0 leaving went to 100% wherever the view was; now it returns to the view you left unless you panned or zoomed (see NAV-17).

## NAV-02 Zooming out never goes past 60%
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** At 100%, only two small windows open, close together (they'd fit at 100%).
- **Steps:**
  1. Press ⌥`.
  2. Read the zoom figure in the minimap.
- **Expected:** The view zooms out to show both windows centred, but stops at 60% (the minimap reads 60%), not 100%. With many windows it goes as far out as needed to fit them all, 80pt of canvas margin around them, down to 3% at most.
- **Automate:** unit: `CanvasController.fitCamera(maxScale: 0.6)` with a few small frames returns scale 0.6.

## NAV-03 Pinch zooms around the pointer
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. Put the pointer over a window's corner and pinch out, then in.
- **Expected:** The canvas zooms in and out smoothly, and the canvas point under the pointer stays under the pointer. The minimap's zoom figure follows. Pictures sharpen as you zoom in (see CAPTURE-02).
- **Automate:** unit: `Camera.zoom(to:anchor:)` keeps `toCanvas(anchor)` fixed.

## NAV-04 ⌘ + scroll zooms around the pointer
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. Hold ⌘ and scroll up and down (trackpad, then a mouse wheel).
- **Expected:** Scrolling zooms instead of panning, anchored on the pointer as with a pinch; a mouse wheel zooms in bigger steps than the trackpad. No panning happens while ⌘ is held.
- **Automate:** manual: needs scroll events with modifier flags.

## NAV-05 Zoom stops at 3% and 150%
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. Pinch (or press -) all the way out.
  2. Pinch (or press =) all the way in.
- **Expected:** The minimap's figure stops at 3% going out and 150% going in; further input does nothing.
- **Automate:** unit: `Camera.zoom(to:anchor:)` clamps to `Camera.minScale` 0.03 and `Camera.maxScale` 1.5.

## NAV-06 Two-finger double-tap swaps between the overview and 100%
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out, trackpad with smart zoom (double-tap with two fingers) on.
- **Steps:**
  1. Double-tap with two fingers over a window.
  2. Double-tap with two fingers again.
- **Expected:** Step 1: below 95% zoom, the canvas animates to 100% around the pointer, staying on the canvas (no window is entered). Step 2: at 100% it animates back out to the overview (NAV-01's view).
- **Automate:** unit: `CanvasController.toggleOverview(at:)` target camera | manual: smart-magnify gesture.

## NAV-07 ⌥ + pinch anywhere opens the canvas
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** At 100%, pointer over an app window (not the desktop).
- **Steps:**
  1. Hold ⌥ and pinch in.
  2. Pinch in without ⌥ over the same window.
- **Expected:** Step 1: once the pinch passes a small threshold, the canvas opens zoomed out to every window, as ⌥` does. Step 2: nothing happens in Expanse (the pinch goes to the app).
- **Automate:** manual: global gesture monitor.

## NAV-08 0 fits every window
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out, panned and zoomed so some windows are out of view.
- **Steps:**
  1. Press 0.
- **Expected:** The view animates to fit every window with a margin, at up to 100% (so a few small windows fit at 100%, unlike the 60% cap of NAV-02).
- **Automate:** unit: `CanvasController.fitCamera()`.

## NAV-09 1 goes to 100% on the canvas
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. Press 1.
- **Expected:** The canvas animates to 100% around the middle of the screen and stays as the canvas (windows are still pictures; the minimap reads 100%). Esc or a click on a window then hands back to the real windows.
- **Automate:** unit: `CanvasController.zoomAnimated(to:)` target camera.

## NAV-10 - and = zoom out and in by steps
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out to about 40%.
- **Steps:**
  1. Press - twice.
  2. Press = twice.
- **Expected:** Each press animates the zoom by a factor of 1.5 around the middle of the screen (- divides, = multiplies), within 3%–150%; two of each return to the starting zoom.
- **Automate:** unit: `Camera.zoom(to:anchor:)` with scale / 1.5 and × 1.5.

## NAV-11 Esc goes back to the 100% view you left
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0), 2b994e0 (0.1.0)
- **Setup:** At 100% with Safari in front; note what's on screen. No windows selected.
- **Steps:**
  1. Press ⌥` to zoom out. Don't pan or zoom.
  2. Press Esc.
- **Expected:** The view animates back to exactly the earlier 100% view; real windows are where they were; the front-most window on screen gets the keyboard.
- **Automate:** manual: overlay hand-back.
- **Note:** With a selection, the first Esc clears it instead (EDIT-12).

## NAV-12 Click a window on the canvas to glide to it and use it
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. Click (without dragging) a TextEdit window far from the middle.
  2. Start typing straight away.
- **Expected:** The canvas animates to 100% with that window centred on screen (in about a fifth of a second), hands back to the real windows, and the window is raised and focused: the typing goes into it.
- **Automate:** unit: `CanvasController.focusCamera(for:)` centres the frame | manual: focus and hand-back.
- **Note:** A window too big for the screen is shrunk to fit first (SIZE-02). A window that can't shrink and is taller than the screen lands top-aligned (`focusCamera`).

## NAV-13 The minimap moves the zoomed-out view
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out to about 20%, so some windows are off screen.
- **Steps:**
  1. Click a spot in the minimap (bottom right).
  2. Drag across the minimap.
- **Expected:** The view centres on the canvas point you clicked, at the same zoom, and follows the pointer while you drag. The click doesn't select or move any window.
- **Automate:** unit: `Minimap.canvasPoint(at:)` maps back to canvas space.

## NAV-14 Click a parked window's picture at 100% to go to it
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** As at the end of TRACK-03.
- **Steps:**
  1. Click the window's picture at the top of the screen.
- **Expected:** The view glides (about 0.3s) to centre that window at 100%; the real window comes back from the corner, in focus.
- **Check in log:** `glide to <App>[<id>]`
- **Automate:** manual: backdrop click, glide.

## NAV-15 Pan with two-finger scroll or Space + drag
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0), 3de4347 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. Scroll with two fingers in each direction.
  2. Hold Space, then press and drag anywhere (over a window too). Let go of the button, then of Space.
  3. Hold ⌘ and scroll.
- **Expected:** 1: the canvas pans. 2: an open hand cursor while Space is held, a closed hand while dragging; the canvas pans and no window moves; the arrow cursor comes back when Space is released. 3: zooms around the pointer instead of panning.
- **Automate:** manual: trackpad and key input.

## NAV-16 On the canvas, arrow keys move a highlight and Return dives in
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0), 9f92b18 (0.1.0)
- **Setup:** Zoomed out, names on (panel › Window names when zoomed out).
- **Steps:**
  1. Press →, ↓, ←, ↑ (no ⌃).
  2. Press Return.
- **Expected:** Each arrow highlights the nearest window that way (accent border, label "App — Title") and the view pans to centre it without changing zoom. Return glides into the highlighted window at 100%, with focus. With nothing highlighted, Return dives into the front window.
- **Automate:** unit: CanvasController.nearest(_:from:in:) (the key handling stays manual).

## NAV-17 After moving around zoomed out, leaving goes back to the window you were in
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0), 2b994e0 (0.1.0), unreleased (31 Oct)
- **Setup:** At 100%, in a window.
- **Steps:**
  1. Press ⌥`, then pan with two fingers (or pinch, ⌘-scroll, press 0, 1, - or =, or click the minimap).
  2. Press Esc (or ⌥` again).
  3. Again, but drag the window you were in somewhere else on the canvas before pressing Esc.
- **Expected:** Step 2: back at 100% on the window you were in, exactly as you left it, and it has the keyboard: you didn't pick anywhere else. Step 3: that window, centred where it is now. Picking a window (a click, Return) still goes to it.
- **Automate:** manual: needs the canvas. The camera it goes back to is unit-tested (NAV-17 tests).
- **Note:** Until 31 Oct (2b994e0 on), leaving after moving around went to the middle of the view you were looking at, and could then glide on to a window cut off at the screen's edge. Changed at your request: leaving without picking is going back.

## NAV-18 Scrolling or pinching on the bare desktop opens the canvas
- **Type:** Feature
- **Area:** NAV
- **Commits:** 0cdf466 (0.1.0), f70bf12 (0.1.29), d33eab0 (0.1.29)
- **Setup:** At 100%, bare desktop under the pointer (no window there).
- **Steps:**
  1. Scroll with two fingers on the bare desktop.
  2. Back to 100% (Esc), then pinch on the bare desktop.
  3. Back to 100%, then turn a mouse's scroll wheel on the bare desktop.
- **Expected:** Each opens the canvas at 100%, and the rest of the gesture moves (scroll, wheel) or zooms (pinch) the view.
- **Automate:** manual: global event monitors (`handleDesktopGesture`).

## NAV-19 The hot corner fires once per visit, never mid-drag
- **Type:** Feature
- **Area:** NAV
- **Commits:** 06a9a13 (0.1.0)
- **Setup:** At 100%, hot corner All corners.
- **Steps:**
  1. Rest the pointer in a corner and keep it there for several seconds.
  2. Drag a window (mouse button held) into a corner.
- **Expected:** Step 1 opens the canvas once; staying there doesn't toggle it back (leaving the corner re-arms it). Step 2 doesn't fire while the button is held.
- **Automate:** unit: `HotCorner` arming logic, given injected pointer positions (needs a seam).

## NAV-20 Resting the pointer in a corner opens the canvas
- **Type:** Feature
- **Area:** NAV
- **Commits:** 06a9a13 (0.1.0), 2b994e0 (0.1.0)
- **Setup:** Expanse running at 100% with 3+ windows. Menu bar icon › panel › Hot corner: All corners (the default). macOS's own hot corners set to "–" (System Settings › Desktop & Dock › Hot Corners).
- **Steps:**
  1. Move the pointer into the top-left corner of the main display and hold it still for 2 seconds.
  2. Move it out of the corner, then back in.
  3. Repeat steps 1–2 for the other three corners.
- **Expected:** About a tenth of a second after the pointer reaches the corner, the canvas zooms out to show every window. Holding it there longer does nothing more (one toggle per visit). Leaving and coming back toggles again, back to 100%. All four corners work.
- **Automate:** manual: HotCorner polls the real pointer 30 times a second; a unit test needs the in-corner test pulled out of HotCorner.poll.
- **Note:** The wait was 0.15s and became 0.06s in 2b994e0.

## NAV-21 Hot corners do nothing while Expanse is paused
- **Type:** Feature
- **Area:** NAV
- **Commits:** 06a9a13 (0.1.0)
- **Setup:** Menu bar icon › panel › turn the Expanse switch off (Pause). Windows are back in the macOS layout.
- **Steps:**
  1. Rest the pointer in each corner.
- **Expected:** Nothing happens: no canvas, no window moves. Expanse stays paused.
- **Automate:** manual: needs the real pointer (guard in CanvasController.start's hotCorner.onTrigger).

## NAV-22 ⌥⇧` turns auto-centre on and off
- **Type:** Feature
- **Area:** NAV
- **Commits:** 3de4347 (0.1.0), 363d854 (0.1.0)
- **Setup:** At 100%, auto-centre on.
- **Steps:**
  1. Press ⌥⇧`.
  2. Open the panel.
  3. Press ⌥⇧` again; quit and relaunch Expanse; open the panel.
- **Expected:** 1: a toast near the bottom of the screen: "Auto-centre off: windows stay put". 2: the Auto-centre focused window switch is off. 3: toast "Auto-centre on"; after the relaunch the switch is still on. Flipping the switch in the panel does the same, without a toast.
- **Automate:** unit: CanvasController.autoCentre (UserDefaults "autoCentre", default true).

## NAV-23 With auto-centre on, clicking a part-hidden window centres it
- **Type:** Feature
- **Area:** NAV
- **Commits:** 3de4347 (0.1.0)
- **Setup:** At 100%, auto-centre on. Window A runs off the right edge of the screen. The view got there by a hop or glide, not by your own scrolling.
- **Steps:**
  1. Click the visible part of A.
- **Expected:** The view glides so A is centred at 100%, and A has focus.
- **Check in log:** `focus-settled glide to <App>[<id>]: on screen at …`
- **Automate:** manual: real focus changes.
- **Note:** Since e1165df, in a view you placed yourself (scrolling at 100%), a partly visible window you click stays where it is.

## NAV-24 With auto-centre off, focus never moves the view
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** 3de4347 (0.1.0), 363d854 (0.1.0)
- **Before:** With auto-centre off (3de4347), a fully hidden window that got focus still glided into view. macOS often focuses a hidden window by itself after a close or minimise, so the canvas jumped away from what you were doing.
- **Setup:** At 100%, auto-centre off. App A's window on screen; app B's only window parked off-screen.
- **Steps:**
  1. ⌘-Tab to B.
  2. ⌘-Tab to A, then to B again.
  3. In A, close a window so macOS focuses another of A's windows that's off-screen.
- **Expected:** The view never moves. Step 1 shows the toast "B is off-screen · ⌥` to find it". It isn't shown again for the same window in step 2. A window that's partly on screen just takes focus, with no toast.
- **Automate:** manual: real app switching.

## NAV-25 ⌃ + arrow with auto-centre off only moves focus to a window in view
- **Type:** Feature
- **Area:** NAV
- **Commits:** 9f92b18 (0.1.0), d776526 (0.1.2)
- **Setup:** At 100%, auto-centre off; two windows fully on screen side by side, a third parked to the right.
- **Steps:**
  1. From the left window press ⌃→.
  2. Press ⌃→ again.
- **Expected:** Step 1: the right window is raised and focused; the view stays put. Step 2: the parked window isn't fully on screen, so the view glides to it.
- **Automate:** manual: focus and glide.

## NAV-26 ⌃ + arrow keys hop to the next window that way
- **Type:** Feature
- **Area:** NAV
- **Commits:** 9f92b18 (0.1.0), b14448d (0.1.0), d776526 (0.1.2)
- **Setup:** At 100%, auto-centre on. A row of windows A, B, C left to right 20pt apart, and D below B. macOS's ⌃-arrow shortcuts off.
- **Steps:**
  1. Click A, then press ⌃→, ⌃→, ⌃←, ⌃↓.
- **Expected:** Each press glides the view to centre the next window that way: B, C, B, then D. Each has focus when it lands, so typing goes to it.
- **Check in log:** `navigate to <App>[<id>]`
- **Automate:** unit: CanvasController.nearest(_:from:in:).
- **Note:** With auto-centre off, a hop to a window that's fully on screen only gives it focus and the view stays put (d776526).

## NAV-27 Arrow hops prefer windows in the same row or column
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** 9f92b18 (0.1.0), b14448d (0.1.0)
- **Before:** A weighted score could pick a window well above or below as the next one to the right, ahead of one level with you further along.
- **Setup:** At 100%. Window A; B level with A, 800pt to its right; C 60pt to the right of A but mostly above it (overlapping less than a third of A's height).
- **Steps:**
  1. Click A, press ⌃→.
  2. Close B, click A, press ⌃→ again.
- **Expected:** 1: goes to B (it shares A's row). 2: goes to the nearest window within about 35° of straight right; a window mostly above or below never counts as right, so C is picked only if it's within that angle.
- **Automate:** unit: CanvasController.nearest(_:from:in:).

## NAV-28 A hop pressed during a glide carries on from where it was heading
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** b14448d (0.1.0), 3144b09 (0.1.0)
- **Before:** ⌃+arrow during a glide moved the view while the real windows stayed put, so the screen and the real windows disagreed.
- **Setup:** At 100%, a row A, B, C, D of windows wider than the screen.
- **Steps:**
  1. Click A and press ⌃→ three times quickly.
- **Expected:** Each press re-aims the glide at once, hopping on from the window it was heading to: B, C, then D. It lands on D with every real window in place and D in focus. Only the last hop hands back.
- **Check in log:** `navigate (chained) to <App>[<id>]`
- **Automate:** manual: timing of real glides.
- **Note:** b14448d queued the press until the glide landed; 3144b09 made it chain straight away.

## NAV-29 Scrolls, clicks and the canvas toggle can't cut a glide short
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** b14448d (0.1.0)
- **Before:** A scroll, click, key or hot corner during a glide cancelled it halfway, leaving the overlay and the real windows out of step.
- **Setup:** At 100%, a window far to the right.
- **Steps:**
  1. Press ⌃→ and, during the glide, scroll, click, press ⌥` and rest the pointer in the hot corner.
- **Expected:** The glide finishes and lands normally with the target focused. None of those inputs does anything mid-glide; the corner has to be rested in again afterwards.
- **Automate:** manual: real input during a glide.

## NAV-30 Glides and hops are quick, and their timing is logged
- **Type:** Feature
- **Area:** NAV
- **Commits:** 3144b09 (0.1.0)
- **Setup:** At 100% with 10+ windows, log stream running.
- **Steps:**
  1. Hop with ⌃+arrows ten times.
- **Expected:** Each glide starts straight away and lasts about 0.3s. Focus lands within a few tens of milliseconds, without waiting for the app's own activation.
- **Check in log:** `glide timing: prep Xms, first frame after Yms, N frames, max gap Zms, commit Wms` and `activation took Nms`; `slow: animation` lines are rare.
- **Automate:** manual: real timing.

## NAV-31 Chrome-based browsers move as quickly as other apps
- **Type:** Feature
- **Area:** NAV
- **Commits:** 3144b09 (0.1.0)
- **Setup:** Chrome, Brave or Edge with three windows on the canvas, plus other apps' windows.
- **Steps:**
  1. Hop between the browser windows and the others; zoom out and click a browser window.
- **Expected:** Glides land without stalls and browser windows end exactly in place. Chromium's slow animated moves are switched off while Expanse moves its windows, then back on.
- **Automate:** manual: depends on Chromium's Accessibility behaviour.

## NAV-32 Zooming out and straight back returns to the same view
- **Type:** Feature
- **Area:** NAV
- **Commits:** 2b994e0 (0.1.0)
- **Setup:** At 100%, some windows partly on screen. Note exactly what's in view.
- **Steps:**
  1. Press ⌥`.
  2. Without scrolling, zooming or clicking a window, press ⌥` again (or Esc).
- **Expected:** Back at 100% with exactly the same view: the same windows in the same places. The zoom out takes about 0.22s and the zoom back about 0.18s.
- **Automate:** manual: needs the canvas (CanvasController.returnCamera).

## NAV-33 Menu, link and Tidy actions wait for a glide to land
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** ac50e01 (0.1.0)
- **Before:** A URL command, menu action, Tidy Up or Pause during a glide cut it short and could leave the overlay stuck over the screen.
- **Setup:** At 100%, windows far to the right.
- **Steps:**
  1. `open "expanse://nav?dir=right"; open "expanse://tidy"` as one Terminal line.
  2. Press ⌃→ and straight away use the panel's Tidy up, the Expanse switch (Pause), or Restore all windows.
- **Expected:** The hop lands first, then the action runs. The screen is never left covered by the overlay.
- **Automate:** unit: CanvasController.whenIdle(attempts:_:).

## NAV-34 Every hop centres its window when auto-centre is on
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** d776526 (0.1.2)
- **Before:** A hop to a window already fully on screen only moved focus, so it looked like nothing happened and the next press skipped on to another group.
- **Setup:** At 100%, auto-centre on. Two windows side by side, both fully on screen.
- **Steps:**
  1. Click the left one, press ⌃→.
- **Expected:** The view glides to centre the right-hand window, which has focus.
- **Automate:** manual: real glides.
- **Note:** With auto-centre off, it only takes focus and the view stays.

## NAV-35 Equal gaps: the hop goes to the better-aligned window
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** d776526 (0.1.2)
- **Before:** With two windows snapped 20pt below one (equal gaps), ⌃↓ picked whichever came first in the list, often the one further off to the side.
- **Setup:** Window A; B and C side by side, both 20pt below A, with B's centre nearer A's centre.
- **Steps:**
  1. Click A, press ⌃↓.
- **Expected:** Goes to B.
- **Automate:** unit: CanvasController.nearest(.down, from:in:).

## NAV-36 ⌥` zooms out without waiting for a window scan
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** 61e6e55 (0.1.3)
- **Before:** Zooming out waited for a fresh window scan, which can take a second when ScreenCaptureKit is busy.
- **Setup:** 50 windows.
- **Steps:**
  1. Press ⌥` and Esc ten times over a minute.
  2. Open a new window, then press ⌥` straight away.
- **Expected:** 1: the zoom starts at once every time. 2: a scan runs right after zooming out, so the new window appears on the canvas moments later.
- **Automate:** manual: real ScreenCaptureKit timing.

## NAV-37 One busy app doesn't hold up other apps' windows
- **Type:** Feature
- **Area:** NAV
- **Commits:** 61e6e55 (0.1.3)
- **Setup:** A browser with 15 windows, made busy (heavy pages loading) or paused with `kill -STOP`. Other apps' windows too.
- **Steps:**
  1. Hop between the other apps' windows.
- **Expected:** Their windows move into place promptly; each app's windows move on a thread of their own, with the glide's target first.
- **Check in log:** `slow: moving N windows took Xms (<Browser>: Yms)` names the slow app when moves take over 150ms.
- **Automate:** manual: needs a real slow app.

## NAV-38 Leaving the canvas doesn't freeze, even with 50 windows
- **Type:** Feature
- **Area:** NAV
- **Commits:** 61e6e55 (0.1.3)
- **Setup:** 50 windows.
- **Steps:**
  1. Zoom out and click a window.
- **Expected:** The zoom-in is smooth (about 0.18s). Real windows move in the background; clicks and keys wait until they're in place, then work. No beachball.
- **Automate:** manual: real performance.

## NAV-39 Hops start without waiting for the app
- **Type:** Feature
- **Area:** NAV
- **Commits:** 61e6e55 (0.1.3)
- **Setup:** A busy app in front (a browser loading pages). Log stream running.
- **Steps:**
  1. Press ⌃→.
- **Expected:** The glide starts at once. Expanse already knows the app's focused window from its notifications, so it doesn't ask the app first.
- **Check in log:** `glide timing: prep Xms` stays small.
- **Automate:** manual: real timing.

## NAV-40 A hop lands without flashing the old layout
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** f310f04 (0.1.8)
- **Before:** The canvas handed the screen back about 30 ms after the moves. Apps take an Accessibility move at once, but some (Chromium browsers especially) show it a frame or more later, so the old layout flashed as the hop landed.
- **Setup:** At 100%, three or more Brave or Chrome windows side by side on the canvas, some off screen.
- **Steps:**
  1. Press ⌃→ several times, then ⌃← back.
- **Expected:** Each hop ends with the windows already in their new places. The old layout never flashes, and another app's windows don't blink on top. The hand-back never takes longer than a quarter of a second.
- **Check in log:** `windows landed after <n>ms (Brave Browser)`. If the hand-back waited over 60 ms: `hand-back waited <n>ms: Brave Browser focused after …ms, windows landed after …ms, …`
- **Automate:** manual: needs real window-server timing. CanvasController.whenOnScreen and notOnScreenYet could be unit-tested with a stubbed window list.
- **Note:** a23c303 (next release) also waits for streams to stop before handing back, so the log line has a `streams …` part too.

## NAV-41 Leaving the canvas onto a window doesn't flash either
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** f310f04 (0.1.8)
- **Before:** Leaving the canvas waited a fixed 80 ms before dropping it under the real windows, so windows not yet moved could show the old layout, or the new app's windows could jump forward over it.
- **Setup:** Zoomed out, with several Chromium windows.
- **Steps:**
  1. Click a window far from the current view.
- **Expected:** The canvas zooms in. When it drops away, every window is already in place and the clicked window has focus, with no blink. This takes at most a quarter of a second after the zoom.
- **Check in log:** as NAV-40.
- **Automate:** manual.

## NAV-42 Clicking the minimap zooms out; clicking the bare desktop doesn't
- **Type:** Feature
- **Area:** NAV
- **Commits:** 535247b (0.1.14), f70bf12 (0.1.29)
- **Setup:** At 100%, the minimap showing at the bottom-right of the screen, bare desktop showing.
- **Steps:**
  1. Click the bare desktop.
  2. Click the minimap.
- **Expected:** Step 1: Finder becomes active as normal; the canvas doesn't open. Step 2: the canvas zooms out to every window.
- **Automate:** manual: hit-testing on the backdrop window (`CanvasView.mouseDown` live-mode branch).
- **Note:** README's shortcut table changed "Click empty desktop" to "Click the minimap" in this commit.

## NAV-43 ⌃⌥C centres the window you're in
- **Type:** Feature
- **Area:** NAV
- **Commits:** 8c2b732 (0.1.15)
- **Setup:** At 100%, with the focused window partly off the edge of the screen.
- **Steps:**
  1. Press ⌃⌥C.
- **Expected:** The view glides, like a hop, until the window is in the middle of the screen. It keeps the keyboard.
- **Check in log:** `centre <App>[<id>]`
- **Automate:** unit: CanvasController.centreCurrentWindow uses currentWindow(): the front app's focused window, otherwise the front-most window on screen.

## NAV-44 ⌃⌥C while zoomed out goes back to 100% on your window
- **Type:** Feature
- **Area:** NAV
- **Commits:** 8c2b732 (0.1.15)
- **Setup:** Working in window X, then zoomed out with ⌥` and panned away.
- **Steps:**
  1. Press ⌃⌥C.
- **Expected:** The canvas zooms back to 100%, centred on X, with X focused.
- **Automate:** manual.

## NAV-45 Centring does nothing while Expanse is paused or not started
- **Type:** Feature
- **Area:** NAV
- **Commits:** 8c2b732 (0.1.15)
- **Setup:** Menu bar panel › Expanse switch off (paused). For the second run, the walkthrough is up on first launch.
- **Steps:**
  1. Press ⌃⌥C and look at the panel's Centre window tile.
- **Expected:** No window moves. While paused, the tile is disabled. Before the walkthrough is done, the ⌃⌥C shortcut isn't registered and the tile is disabled.
- **Automate:** unit: centreCurrentWindow returns when isPaused; MenuPanel disables the tile when !isOn or isPaused.

## NAV-46 animationSlowdown makes camera moves slower
- **Type:** Feature
- **Area:** NAV
- **Commits:** eb224e7 (0.1.21)
- **Setup:** `defaults write com.invignation.expanse animationSlowdown -float 3`, then restart Expanse (it's read at launch).
- **Steps:**
  1. Press ⌥`, then ⌃→.
  2. `defaults delete com.invignation.expanse animationSlowdown`, restart, repeat.
- **Expected:** With the setting, zooms and glides take about three times as long. Without it (or with a value under 1), normal speed.
- **Automate:** manual: timing on screen.

## NAV-47 After you pan at 100%, clicking a window you can see doesn't recentre
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** e1165df (0.1.25)
- **Before:** After you'd placed the view yourself, clicking a window that was only partly on screen glided to centre it, losing your view.
- **Setup:** Auto-centre on. At 100%, windows side by side.
- **Steps:**
  1. Scroll on the empty desktop to start moving the canvas at 100%.
  2. Hold Space and drag so a window is about a third on screen.
  3. Press Esc.
  4. Click the partly visible window.
- **Expected:** The window gets focus and the view stays where you put it; nothing glides.
- **Check in log:** `view placed by you: <App>[<id>] focused where it is`
- **Automate:** manual: focus events from the real app.

## NAV-48 Diving into a window you can see keeps the view you placed
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** e1165df (0.1.25)
- **Before:** Clicking a partly visible window on the canvas at 100% centred it, moving the view you'd placed.
- **Setup:** As NAV-47, steps 1–2 (canvas open at 100%, view placed with Space+drag).
- **Steps:**
  1. Click the partly visible window on the canvas.
- **Expected:** The canvas drops in place and the window gets focus where it is: the view doesn't move. A window too little on screen (under 48pt showing, or its top cut off) is centred as usual.
- **Check in log:** `view placed by you: diving into <App>[<id>] where it is`
- **Automate:** unit: CanvasController.goesOnScreen(_:in:) | manual: the dive.

## NAV-49 The next glide, zoom or display change ends the placed view
- **Type:** Feature
- **Area:** NAV
- **Commits:** e1165df (0.1.25)
- **Setup:** View placed as in NAV-47.
- **Steps:**
  1. Press ⌃→ to hop.
  2. Click a window that's partly on screen.
  3. Place the view again, then pinch or ⌘-scroll to zoom (or change the display, or ⌃⌥C), and repeat step 2.
- **Expected:** After a glide, zoom or display change, clicking a partly visible window recentres it again.
- **Check in log:** `focus-settled glide to <App>[<id>]: on screen at {…} in {…}, real window at {…}`
- **Automate:** manual: event-driven state (viewPlaced).

## NAV-50 Scrolling over a window doesn't open the canvas
- **Type:** Feature
- **Area:** NAV
- **Commits:** f70bf12 (0.1.29)
- **Setup:** At 100%, a Safari window with a long page, the Dock visible.
- **Steps:**
  1. Scroll with two fingers over the Safari page.
  2. Scroll over the Dock, the menu bar and an open dialog or panel of another app.
  3. Pinch over the Safari window without ⌥.
- **Expected:** The window under the pointer gets the gesture as usual; the canvas doesn't open. (⌥ + pinch still zooms out from anywhere.)
- **Automate:** manual: the window-server check in `handleDesktopGesture`.

## NAV-51 A trackpad scroll at 100% snaps when it stops
- **Type:** Feature
- **Area:** NAV
- **Commits:** d33eab0 (0.1.29)
- **Setup:** At 100%, a row of windows the standard gap apart, wider together than the screen.
- **Steps:**
  1. Scroll sideways with two fingers (on the bare desktop, which opens the canvas at 100%, then onward) and lift your fingers with a window cut off by the screen's left or right edge.
- **Expected:** When the momentum ends, the view moves on a little (a 0.25 s animation) by the least that leaves the fewest windows cut off and at least one whole: a window's edge lines up 20 pt in from the screen's edge, which puts the next window just out of sight. It never moves more than half a screen.
- **Check in log:** `scroll ended: view snapped by <dx>, <dy>`.
- **Automate:** unit: `CanvasController.snappedCamera()` (private, pure maths over window frames and the view size; needs a test seam).

## NAV-52 A mouse-wheel scroll snaps after a short pause
- **Type:** Feature
- **Area:** NAV
- **Commits:** d33eab0 (0.1.29)
- **Setup:** As NAV-51, with a mouse that has a scroll wheel.
- **Steps:**
  1. Open the canvas at 100% and turn the wheel (⇧ + wheel for sideways) until a window is cut off and the next one's edge is a notch or two short of 20pt in from the screen's; stop.
- **Expected:** About a quarter of a second after the last tick, the view snaps as in NAV-51, but only on the way you turned the wheel and by 40pt or less (NAV-63).
- **Check in log:** `scroll ended: view snapped by …`.
- **Automate:** manual: event phases (`CanvasView.scrollMayEnd`).

## NAV-53 A window that nearly fills the screen is centred by the snap
- **Type:** Feature
- **Area:** NAV
- **Commits:** d33eab0 (0.1.29)
- **Setup:** At 100%, a window filled with Fill (less than 40 pt to spare along its width), with other windows beside it.
- **Steps:**
  1. Scroll so the filled window is partly off screen, and let go.
- **Expected:** The view snaps so the filled window is whole, centred on screen (flush with the screen's edges if it's exactly the screen's size).
- **Automate:** unit: `CanvasController.snappedCamera()` offers `spare / 2 - from` for a window with under two gaps to spare.

## NAV-54 No snap when nothing is cut off, or when zoomed
- **Type:** Feature
- **Area:** NAV
- **Commits:** d33eab0 (0.1.29)
- **Setup:** As NAV-51.
- **Steps:**
  1. At 100%, scroll so that every window is either whole on screen or out of sight, and let go.
  2. Zoom out a little (- or ⌘-scroll), then scroll and let go.
- **Expected:** Neither moves the view after the scroll; ⌘-scroll zooming doesn't snap either.
- **Check in log:** No `scroll ended: view snapped` line.
- **Automate:** unit: `snappedCamera()` returns the camera unchanged when no shown window is cut off; `scrollEnded` only runs at scale 1.

## NAV-55 Windows arranged to fit the screen together are a group
- **Type:** Feature
- **Area:** NAV
- **Commits:** unreleased (31 Oct)
- **Setup:** At 100%. Two or three windows side by side (or one above another), snapped a gap apart, together no wider or taller than the screen. Another window on its own elsewhere.
- **Steps:**
  1. ⌥`, and hover each window.
  2. Move one of the group a little more than 40pt away from its neighbour; hover again.
- **Expected:** Step 1: the arranged windows count as one group (see NAV-60); the window on its own doesn't. Step 2: they're no longer a group. Windows 40pt apart or less (directly or through a neighbour) whose outline fits the screen are a group; a cluster too big for the screen isn't one at all.
- **Automate:** unit: `CanvasController.screenGroups(_:fitting:)`, `screenGroup(of:)` and `viewCamera(for:)`.

## NAV-56 A hop to a window in a group frames the whole group
- **Type:** Feature
- **Area:** NAV
- **Commits:** unreleased (31 Oct)
- **Setup:** As NAV-55, in the window on its own, the group out of view to its right.
- **Steps:**
  1. ⌃→.
- **Expected:** The view glides to the group, centred on it as a whole, every window of it in view; the window the hop reached (the nearest that way) has the keyboard.
- **Check in log:** `glide to <App>[<id>] (group of 2)`.
- **Automate:** manual: a real glide. The camera is unit-tested (NAV-56 tests).

## NAV-57 Hops between the windows of a group on screen only move focus
- **Type:** Feature
- **Area:** NAV
- **Commits:** unreleased (31 Oct)
- **Setup:** As NAV-55, the group framed, in its left window. Auto-centre on.
- **Steps:**
  1. ⌃→, then ⌃←.
  2. ⌃→ from the group's right-hand window, towards a window beyond the group.
- **Expected:** Step 1: focus moves between the group's windows and the view doesn't move. Step 2: the hop leaves the group, gliding to the next window (framing its group, if it's in one).
- **Automate:** manual: real focus. The rule is unit-tested (`hopStaysInGroup`).

## NAV-58 Clicking a window in a group zoomed out zooms to the group
- **Type:** Feature
- **Area:** NAV
- **Commits:** unreleased (31 Oct)
- **Setup:** As NAV-55, zoomed out.
- **Steps:**
  1. Click a window of the group (or hover it and press Return).
  2. ⌥`, then click the window on its own.
- **Expected:** Step 1: back at 100% with the whole group framed, the window clicked in front with the keyboard. Step 2: that window centred, as before.
- **Automate:** manual: real clicks on the canvas. The camera is unit-tested (NAV-58 test).

## NAV-59 ⌃⌥C frames the group of the window you're in
- **Type:** Feature
- **Area:** NAV
- **Commits:** unreleased (31 Oct)
- **Setup:** As NAV-55, in a window of the group; pan at 100% so the group is half off screen.
- **Steps:**
  1. ⌃⌥C.
  2. ⌥`, pan, and ⌃⌥C again.
- **Expected:** Both times: the group framed at 100%, your window still with the keyboard. A window on its own is centred, as before (NAV-43, NAV-44).
- **Automate:** manual: real focus and glides. The camera is unit-tested (NAV-59 test).

## NAV-60 Zoomed out, hovering a window in a group outlines the group
- **Type:** Feature
- **Area:** NAV
- **Commits:** unreleased (31 Oct)
- **Setup:** As NAV-55, zoomed out.
- **Steps:**
  1. Hover a window of the group, then the window on its own.
  2. Select two windows (⇧-click), and hover one.
- **Expected:** Step 1: a soft accent outline around the whole group (12pt outside it, rounded), alongside the hovered window's own outline; none for the window on its own. Step 2: only the selection's dashed box. At 100% nothing is drawn.
- **Automate:** unit: `CanvasView.render` sets `groupOutline`'s path (NAV-60 test); manual for how it looks.

## NAV-61 The snap after a scroll never pulls you back the way you came
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** unreleased (1 Nov)
- **Before:** When a scroll at 100% ended, the snap (NAV-51) moved the view up to half a screen any way that left fewer windows cut off: scrolling away from a window across the canvas, each time you lifted your fingers it pulled you back towards it, so it was hard to get away.
- **Setup:** At 100%, a few windows in a row, more canvas beyond them.
- **Steps:**
  1. Scroll away from the window you're in, a little at a time, lifting your fingers between scrolls.
  2. Scroll up or down past a row of windows.
- **Expected:** Step 1: each time a scroll ends the view stays, or carries on your way to line a window up, or moves back no more than 40pt; it never takes you back to the window. Step 2: no sideways snap of more than 40pt.
- **Check in log:** `scroll ended: view snapped by …`, with the move your way (or 40pt or less).
- **Automate:** unit: `snappedCamera(going:)` and the travel kept by `pan(by:scrolling:)`.

## NAV-62 Scrolling or pinching on the bare desktop works under an invisible window, and with Expanse in front
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** unreleased (2 Nov)
- **Before:** Expanse took a scroll or pinch on the desktop (NAV-18) only where the window server listed no window over it, and some apps keep invisible windows that let everything through: Notification Center one over the whole screen (macOS 27), a dictation app (Wispr Flow) one over the bottom middle. Under those, a mouse wheel, a two-finger scroll or a pinch on the desktop did nothing. It did nothing anywhere, too, while Expanse was still the front app (after leaving the canvas at an empty part of it, with nothing to focus): the gesture then went to Expanse itself, with no window, and Expanse only watched other apps' gestures (found by NAV-62 in the VM, 3 Nov).
- **Setup:** At 100%, bare desktop under the pointer. Notification Center's window up (it is after a notification), or Wispr Flow running. Then again just after leaving the canvas at an empty part of it (Expanse still in front).
- **Steps:**
  1. Turn a mouse's scroll wheel on the bare desktop, then a notch at a time with pauses.
  2. Back to 100% (Esc), then scroll with two fingers, and then pinch, on the bare desktop.
  3. Scroll over an app's window, the menu bar and the Dock.
- **Expected:** Steps 1 and 2: the canvas opens at 100%, and the rest of the gesture moves or zooms the view (each notch moves it on). Step 3: the window gets the scroll; the canvas doesn't open (NAV-50).
- **Automate:** manual: end-to-end in the VM (NAV-62), where Notification Center's window is up after a notification.

## NAV-63 A mouse wheel turned a notch at a time isn't pulled back
- **Type:** Bug fix
- **Area:** NAV
- **Commits:** unreleased (2 Nov)
- **Before:** A wheel's ticks have no phases, so a pause ends the scroll (NAV-52) and the snap follows. A notch moves the view 12pt, and the snap may go back the way you came up to 40pt (NAV-61): it put the view back after every notch, or leapt on to line up the next window.
- **Setup:** At 100% on the canvas, a row of windows lined up with the screen's edge, a mouse with a scroll wheel.
- **Steps:**
  1. Turn the wheel sideways (⇧ + wheel) one notch at a time, pausing between notches.
- **Expected:** Each notch moves the view 12pt on and it stays there; after a wheel the snap only finishes a move your way of 40pt or less (a window's edge lining up 20pt in), never back.
- **Check in log:** no `scroll ended: view snapped by` against the way you turned the wheel.
- **Automate:** unit: `snappedCamera(going:wheel:)`, and notches through `CanvasView.scrollWheel`.
