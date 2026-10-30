# PLACE: New windows and where they go

[All areas](README.md)

## PLACE-01 Windows on another display aren't taken on
- **Type:** Feature
- **Area:** PLACE
- **Commits:** 0cdf466 (0.1.0), b6f69cf (0.1.0)
- **Setup:** An external display connected besides the main one.
- **Steps:**
  1. Open a new TextEdit window on the second display.
  2. Zoom out.
- **Expected:** It isn't on the canvas and Expanse never moves it; the canvas uses the main display (with the menu bar) only.
- **Check in log:** `not on the canvas: TextEdit[<id>]: it's outside the main display, at …`
- **Automate:** unit: `isManageable` (`tracked || screenRectCG.intersects(frame)`).
- **Note:** A window already on the canvas stays tracked wherever it goes (b6f69cf).

## PLACE-02 Only ordinary app windows on the main display are managed
- **Type:** Feature
- **Area:** PLACE
- **Commits:** 0cdf466 (0.1.0), faa7e36 (0.1.1), 9ccd030 (0.1.16), 4045597 (0.1.31)
- **Setup:** Open a TextEdit document, a Save sheet or alert in some app, a menu-bar extra's popover window, a tiny window under 100×60 if you have one, and a Phone/FaceTime call window if possible.
- **Steps:**
  1. Zoom out.
- **Expected:** Only the ordinary document windows of apps with a Dock icon are on the canvas. Sheets, dialogs and panels, menu-bar extras' windows, windows under 100×60pt, Expanse's own windows, and Phone/FaceTime windows aren't, and stay where their app puts them.
- **Check in log:** `not on the canvas: <App>[<id>]: <why>` (notice), once per window.
- **Automate:** unit: `CanvasController.isManageable(_:tracked:regular:)` rules | manual: real windows.
- **Note:** Helper processes drawing an app's windows (Steam) count as that app (4045597).

## PLACE-03 A new window opens in free space beside the window it came from
- **Type:** Feature
- **Area:** PLACE
- **Commits:** 0cdf466 (0.1.0), 5dab7a1 (0.1.0), 9f92b18 (0.1.0), eb224e7 (0.1.21), 0305c39 (0.1.26)
- **Setup:** At 100%, auto-centre on. A TextEdit window in the middle of the screen with free space to its right.
- **Steps:**
  1. Click the TextEdit window and press ⌘N.
  2. Make the space to the right too small for a window, then press ⌘N again.
- **Expected:** Step 1: the new window sits to the right of the first, exactly 20pt away, top edges lined up, overlapping nothing; it's on screen, so the view doesn't move. Step 2: it goes below, then to the left; above only as a last resort. Spots already on screen are preferred over ones off-screen.
- **Check in log:** `placed new window TextEdit at {x, y} beside TextEdit[<id>] at …`
- **Automate:** unit: CanvasController.freeSpot(for:near:onScreenOnly:) once it takes plain frames.
- **Note:** The gap was 24pt here and 20pt from 9f92b18. The anchor became the window it came from (its app's front window in view) in eb224e7; before, it was the last on-screen window. Above became a last resort in 0305c39.

## PLACE-04 With no free spot in view, the view glides to the new window
- **Type:** Feature
- **Area:** PLACE
- **Commits:** 5dab7a1 (0.1.0)
- **Setup:** At 100%, auto-centre on. The screen is filled with windows so no new window fits anywhere on it.
- **Steps:**
  1. Click a TextEdit window and press ⌘N.
- **Expected:** The new window gets a free spot beside the source window, off-screen. The canvas glides to it, centres it at 100% and it has focus. Nothing overlaps.
- **Automate:** manual: needs real windows and a glide.

## PLACE-05 A glide asked for while another runs still happens
- **Type:** Bug fix
- **Area:** PLACE
- **Commits:** 5dab7a1 (0.1.0)
- **Before:** Opening a window usually activates its app, which may already be gliding somewhere. The new window's glide was dropped, leaving it off-screen.
- **Setup:** At 100%, auto-centre on. TextEdit's only window is off-screen (parked). The screen is full, so a new window will go off-screen too.
- **Steps:**
  1. In Finder, double-click a .txt file so TextEdit opens it in a new window.
- **Expected:** However the first moments go, the view ends centred on the new document window, which has focus. If a glide was running, the new window's glide waits for it to finish (up to 2s) and then runs.
- **Automate:** manual: depends on real app activation and glides (CanvasController.glideWhenIdle).

## PLACE-06 With auto-centre off, new windows only take free spots on screen
- **Type:** Feature
- **Area:** PLACE
- **Commits:** 363d854 (0.1.0)
- **Setup:** At 100%, auto-centre off.
- **Steps:**
  1. With free space on screen beside a TextEdit window, press ⌘N in it.
  2. Fill the screen so nothing fits, then press ⌘N again.
- **Expected:** 1: the new window goes in a free on-screen spot beside its source and the view stays put. 2: there's no free spot on screen, so the new window stays where TextEdit put it and the view doesn't move (no glide).
- **Check in log:** `placed new window` for step 1 only.
- **Automate:** unit: CanvasController.freeSpot(for:near:onScreenOnly: true) returns nil when nothing fits in view.

## PLACE-07 Sheets, dialogs and floating panels stay with their app
- **Type:** Bug fix
- **Area:** PLACE
- **Commits:** faa7e36 (0.1.1)
- **Before:** Sheets (like Xcode's Manage Certificates), dialogs and floating panels were tracked as windows of their own. Hops and zooming moved or parked them away from their parent window, or hid them in the corner.
- **Setup:** At 100%, a new TextEdit document.
- **Steps:**
  1. Press ⌘S so the Save sheet opens. Hop away with ⌃→ and back with ⌃←.
  2. Cancel. Press ⌘T for the Fonts panel. Hop away and back, then zoom out.
- **Expected:** The sheet stays attached to its document window. The Fonts panel stays where TextEdit put it: it isn't parked, and it isn't drawn as a window of its own on the canvas. Only document windows are on the canvas.
- **Check in log:** `dropped <App>[<id>]: Accessibility says it isn't a standard window` for a tracked window that turns out not to be a standard one.
- **Automate:** unit: the AXStandardWindow filter in CanvasController.apply (needs a seam for ax.known and ax.standard).

## PLACE-08 Several new windows from one scan: one glide, to the one in front
- **Type:** Feature
- **Area:** PLACE
- **Commits:** af8eff8 (0.1.3)
- **Setup:** At 100%, auto-centre on, with the screen around the current window full, so new windows have to go off screen.
- **Steps:**
  1. Press ⌘N four times quickly in Finder.
- **Expected:** The new windows are moved into their spots together. The view makes one glide, to the Finder window that is in front (focused), not one glide per window and not a series of jumps.
- **Check in log:** a `placed new window Finder …` line for each window, followed by a single glide.
- **Automate:** unit: CanvasController.apply. arrivals.glide takes the window matching focusedWindowByApp, otherwise the one with the highest window ID, and calls glideWhenIdle once.

## PLACE-09 Phone and FaceTime call windows are left where their app puts them
- **Type:** Bug fix
- **Area:** PLACE
- **Commits:** 9ccd030 (0.1.16)
- **Before:** A call's window was taken on as a new window and put in the nearest empty spot on the canvas. The view glided off to it while Phone kept moving it back.
- **Setup:** At 100%, with FaceTime set up, or an iPhone set up for calls on this Mac.
- **Steps:**
  1. Start a FaceTime call, or answer a phone call on the Mac.
  2. Zoom out with ⌥`, then Esc.
  3. End the call.
- **Expected:** The call window stays where FaceTime or Phone puts it, in front of you; the view doesn't move. Zoomed out, the call window isn't one of the canvas's windows. Afterwards the canvas layout is unchanged.
- **Automate:** unit: CanvasController.isManageable is false for bundle IDs com.apple.mobilephone and com.apple.FaceTime (leftAlone).

## PLACE-10 A new tab keeps its window's spot
- **Type:** Bug fix
- **Area:** PLACE
- **Commits:** 74dac43 (0.1.19)
- **Before:** macOS shows each tab as a window of its own. A new tab looked like a new window, so Expanse placed it in an empty spot, moving the tab group.
- **Setup:** A Finder window at a known spot on the canvas, with windows on either side.
- **Steps:**
  1. At 100%, click into the Finder window and press ⌘T.
  2. Zoom out and look.
- **Expected:** The window, now with two tabs, stays exactly where it was; nothing else moves.
- **Check in log:** `tab Finder[<new id>] takes over from [<old id>]`
- **Automate:** unit: CanvasController.tabTakingOver (private; same app, same size within 2pt, same spot within 2pt).

## PLACE-11 Switching tabs keeps the window's spot
- **Type:** Bug fix
- **Area:** PLACE
- **Commits:** 74dac43 (0.1.19)
- **Before:** Bringing another tab to the front looked like a window closing and a new one opening, so the group was placed somewhere new.
- **Setup:** A Finder window with three tabs on the canvas, other windows around it.
- **Steps:**
  1. At 100%, switch between the tabs (⌃Tab, or click them).
  2. Turn auto-centre off (⌥⇧`), hop away so the Finder window is off screen (parked), click Finder in the Dock and press ⌃Tab, then zoom out.
- **Expected:** In both cases the tab group stays at its spot on the canvas; nothing else moves. In step 2 the view stays put (auto-centre is off) and the parked group keeps its spot.
- **Check in log:** `tab Finder[…] takes over from […]` for each switch.
- **Automate:** unit: tabTakingOver (the parked case: parked tab and the new window in the parking corner).

## PLACE-12 A new window opens beside its own app's window
- **Type:** Bug fix
- **Area:** PLACE
- **Commits:** eb224e7 (0.1.21)
- **Before:** A new window anchored on whatever window was in front, so a window opened by an app in the background could land beside an unrelated app's window, well away from its source.
- **Setup:** At 100%, a TextEdit window on screen on the left, a Terminal window in front on the right, free space around both.
- **Steps:**
  1. In Terminal: `open -g -a TextEdit ~/Desktop/new.txt` (create the file first; -g keeps Terminal in front).
- **Expected:** The new TextEdit window opens beside the TextEdit window, not beside Terminal. If none of TextEdit's windows is on screen, it opens beside the window in front.
- **Check in log:** `placed new window TextEdit at (x, y) beside TextEdit[<id>] at …`
- **Automate:** manual: anchor choice reads the window order; freeSpot could be unit-tested once extracted.

## PLACE-13 A new window tries every spot along its source's edges first
- **Type:** Bug fix
- **Area:** PLACE
- **Commits:** eb224e7 (0.1.21)
- **Before:** Only four corner-aligned spots around the nearest windows were tried, so a new window could land well away from the window it came from.
- **Setup:** Auto-centre on. Safari window A in the middle of free canvas.
- **Steps:**
  1. In Safari press ⌘N. Note where it goes.
  2. Close the new window, wait a few seconds, put another app's window right of A (same height, 20pt gap) and press ⌘N in A again.
  3. Close the new window, also block the space below A, and press ⌘N.
  4. Close the new window, also block the space left of A, and press ⌘N.
- **Expected:** Step 1: right of A, tops lined up, 20pt gap. Step 2: below A, left edges lined up. Step 3: left of A, tops lined up. Step 4: above A, the last resort. On each side the order is lined up with A's top (or left) edge, then its bottom (or right), then centred. Only when every edge is taken does it go beside the windows nearest A. A spot on screen wins over one off screen.
- **Automate:** unit: CanvasController.freeSpot(for:near:onScreenOnly:) once extracted (private now).
- **Note:** Spots above the source get an extra penalty since 0305c39 (above only as a last resort).

## PLACE-14 An app's loading box doesn't take its main window's spot
- **Type:** Bug fix
- **Area:** PLACE
- **Commits:** 5209c7d (0.1.26)
- **Before:** Discord shows a small update box before its window. The box took the saved spot (same app, any window), so Discord's window opened somewhere else.
- **Setup:** Discord with its window on the canvas, somewhere you'll recognise. Quit Expanse first (so its saved layout still has Discord's window), then quit Discord.
- **Steps:**
  1. Open Expanse.
  2. Within 3 minutes, open Discord; it shows its small update box, then its main window.
- **Expected:** The update box (under a quarter of the window's saved size) goes in the middle of where Discord's window was, and the view goes there if it's off screen. A moment later Discord's main window takes its saved spot and size; the view doesn't go anywhere else in between.
- **Check in log:** `Discord[<id>] is a small window of an app opening again: centred on its window's spot`.
- **Automate:** unit: `LayoutStore.takeMatch(…, size:…)` doesn't hand an entry to a window under a quarter of its area, and `LayoutStore.largerSpot` returns that entry (use entries without id/pid, so no window-server lookup).
- **Note:** Changed by ed61c70 (saved spots only for an app launched in the last minute) and 2d65ed9 (and only in the first 3 minutes after Expanse starts, macOS reopening apps at login). An app you quit and open later mid-session is new: its box and window go beside your work, not to an old spot.

## PLACE-15 A new window goes above its window only as a last resort
- **Type:** Bug fix
- **Area:** PLACE
- **Commits:** 0305c39 (0.1.26)
- **Before:** When every edge of the window you were in was taken, spots beside the nearest windows went by distance alone, so a gap in the row above often won.
- **Setup:** Zoomed out, arrange a TextEdit window A (the only TextEdit window) with another app's window touching every side of it (right, below, left and above, each the standard gap away, leaving no room for another A-sized window along any edge). Above the row over A, leave a gap big enough for a new window; to the right of A's right-hand neighbour and below the row under A, leave open space. Glide into A (click it) so you're working in it.
- **Steps:**
  1. In TextEdit, ⌘N.
- **Expected:** The new window goes in a free spot beside or below the windows near A (right, then down, by nearness), not in the gap in the row above A. A spot above A wins only when there's none beside or below within a few thousand points.
- **Check in log:** `placed new window TextEdit at {x, y} beside TextEdit[<A's id>] at {{x, y}, {w, h}}`.
- **Automate:** unit: `CanvasController.freeSpot(for:near:onScreenOnly:)` (private, needs a test seam): with all four edges of the anchor blocked, a spot ending above the anchor's top scores 3000 more than one beside or below.
- **Note:** The `beside …` part of the log line was added by this commit.

## PLACE-16 A new Finder window opens beside you
- **Type:** Bug fix
- **Area:** PLACE
- **Commits:** ed61c70 (0.1.27)
- **Before:** A window an app opened long after it started took one of the app's old saved spots (any window of the same app), often off screen: new Finder windows landed all over the canvas.
- **Setup:** Expanse running for more than 3 minutes, its saved layout having had several Finder windows in different places (some since closed). At 100%, working in a Finder window in view.
- **Steps:**
  1. In Finder, ⌘N.
  2. Repeat a few times.
- **Expected:** Each new Finder window goes in a free spot beside the Finder window you're in (right, then below, left, above), and the view glides to it only if it isn't on screen. None goes to an old Finder window's spot elsewhere on the canvas.
- **Check in log:** `placed new window Finder at {x, y} beside Finder[<id>] at {{…}}`.
- **Automate:** manual: depends on a running app's launch date and the saved pool (`mayTakeSavedSpot` in `CanvasController.add`).
- **Note:** Changed by 2d65ed9: saved spots are now only used in the first 3 minutes after Expanse starts (for apps launched in the last minute, or the very same window), not for any app launched in the last minute at any time.

## PLACE-17 A new window that reuses a closed window's ID isn't sent to its spot
- **Type:** Bug fix
- **Area:** PLACE
- **Commits:** ed61c70 (0.1.27)
- **Before:** Finder reuses window IDs. A new window with the ID of one closed earlier was taken for that window coming back and sent to its old spot.
- **Setup:** At 100%, two Finder windows: F1 in view (the one you work in), F2 somewhere else on the canvas, off screen.
- **Steps:**
  1. Minimise F1 (⌘M) and click it in the Dock: it comes back to its own spot (control).
  2. Bring F2 into view (⌃+arrows), close it (⌘W), hop back to F1.
  3. Wait a few seconds, then ⌘N in Finder.
- **Expected:** Step 1: the minimised window comes back where it was. Step 3: the new window goes in a free spot beside F1, even if Finder gave it F2's old ID; it isn't sent to F2's spot.
- **Check in log:** Compare the new window's `tracking Finder [<id>]` line with F2's ID; when they match, it must still be logged as `placed new window Finder at … beside Finder[<F1 id>] …`.
- **Automate:** manual: needs Finder reusing a window ID and Accessibility's element-destroyed notification (`closedWindows`, `Departed.closed`).
- **Note:** Wait more than 2 s after the close: a window of the same size at the same spot within 2 s of a close counts as a tab taking over (`tabTakingOver`). Since 2d65ed9 a closed window's record is kept only 10 s, for a tab taking over.
