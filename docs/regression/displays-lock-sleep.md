# DISPLAY: Displays, lock and sleep

[All areas](README.md)

## DISPLAY-01 For 20s after a display change, only your drags count as moves
- **Type:** Feature
- **Area:** DISPLAY
- **Commits:** 0cdf466 (0.1.0), 9f92b18 (0.1.0)
- **Setup:** At 100%, log stream running (SUPPORT-01).
- **Steps:**
  1. Change the display resolution.
  2. Within 20s, drag a window by its title bar to a new place.
  3. Wait 20s.
- **Expected:** Moves macOS makes while it settles are put back where the canvas says. Your drag (mouse button down) is followed and kept. After about 20s the display change counts as settled.
- **Check in log:** `re-placing windows moved by macOS during a display change`, then `display change settled`
- **Automate:** manual: needs a real display change.

## DISPLAY-02 After the screen changes size, the window you were in is centred
- **Type:** Feature
- **Area:** DISPLAY
- **Commits:** 0cdf466 (0.1.0), 8dcba7d (0.1.12), c6c639e (0.1.22)
- **Setup:** At 100% on the big display, with window X focused and not in the middle of the screen.
- **Steps:**
  1. Unplug the display.
  2. Plug it back in, focus X again (off-centre), lock the Mac (⌃⌘Q), unplug the display, then unlock.
- **Expected:** Once the layout has fitted the laptop screen, X is in the middle of the screen at 100%, not whatever window ends up at the old middle. In the locked run, X was noted as the change began and is still the one centred after unlocking.
- **Check in log:** `display change: centred on <App>[<id>]`
- **Automate:** unit: CanvasController.restoreSizesAndPlace with screenResized and centreAfterResize (from displaysWillChange).

## DISPLAY-03 Closing the lid with no other display doesn't crash Expanse
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 0209aa7 (0.1.0), ac50e01 (0.1.0)
- **Before:** With the lid shut and nothing plugged in there can briefly be no screen at all. Expanse crashed on its force-unwrapped screen.
- **Setup:** A MacBook on power with an external display.
- **Steps:**
  1. Close the lid (the external display becomes the only screen), wait 10s, open the lid.
  2. With the lid closed, unplug the external display, wait 10s, open the lid.
- **Expected:** Expanse is still running after both. When a display appears, windows are re-placed on it.
- **Check in log:** `no display yet; waiting` may appear.
- **Automate:** manual: needs real display hardware.

## DISPLAY-04 After unlocking, windows are back where the canvas has them
- **Type:** Feature
- **Area:** DISPLAY
- **Commits:** 0209aa7 (0.1.0)
- **Setup:** At 100% with 10+ windows, several parked.
- **Steps:**
  1. Lock the Mac (⌃⌘Q), wait a minute, unlock it.
  2. Press ⌥`.
- **Expected:** Every window is at its canvas spot. Nothing is piled up or moved by what macOS did at the lock screen.
- **Check in log:** `locked: window moves not followed until unlocked`, then `unlocked: re-placing windows`
- **Automate:** manual: needs the real lock screen.
- **Note:** 9183b47 (0.1.30) also stopped following macOS's moves while locked.

## DISPLAY-05 Windows past the edge of a shrinking screen stay on the canvas
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** b6f69cf (0.1.0)
- **Before:** When the screen got smaller, windows beyond its edge (every parked window included) failed the on-screen check and were dropped. They came back as new windows stacked in the middle, and Tidy then spread them into a column.
- **Setup:** Big display, 10+ windows, several parked off to the right and below.
- **Steps:**
  1. Switch to a laptop-sized resolution (or, in a development build, `open "expanse://screen?w=1512&h=982"`). Press ⌥`.
  2. Switch back (`open "expanse://screen"`). Press ⌥`.
- **Expected:** 1: every window is still on the canvas at its place in the tightened layout; none are stacked in the middle. 2: the layout is exactly as before.
- **Check in log:** no `dropped <App>[<id>]` lines for these windows.
- **Automate:** unit: CanvasController.isManageable(_:tracked:regular:) keeps a tracked window anywhere.
- **Note:** A window that goes missing and comes back takes its old spot (TRACK-10).

## DISPLAY-06 A smaller screen tightens the layout, and the big screen gets it back exactly
- **Type:** Feature
- **Area:** DISPLAY
- **Commits:** 29b2a32 (0.1.0)
- **Setup:** Big display. Groups of windows snapped 20pt apart, some bigger than a laptop screen.
- **Steps:**
  1. Switch to a laptop-sized resolution. Press ⌥`.
  2. Switch back. Press ⌥`.
- **Expected:** 1: big windows shrink to fit and the layout tightens. Each window keeps its gap to its neighbour on the left and above: snapped 20pt gaps stay 20pt and columns stay lined up. 2: every window is exactly where and as big as it was.
- **Check in log:** `layout fitted: … derived=true`, then `derived=false`
- **Automate:** unit: CanvasController.derive(home:sizes:) returns the home positions exactly for home sizes.
- **Note:** Refined in c6c639e, 8dcba7d and c047399 (round trips, columns).

## DISPLAY-07 A move made on the smaller screen survives going back
- **Type:** Feature
- **Area:** DISPLAY
- **Commits:** 29b2a32 (0.1.0)
- **Setup:** As DISPLAY-06, on the smaller screen.
- **Steps:**
  1. Drag window X 200pt to the right into free space.
  2. Switch back to the big screen. Press ⌥`.
- **Expected:** X keeps its new place relative to its neighbours on the big screen; it doesn't jump back to its old spot. The other windows are unaffected.
- **Automate:** unit: CanvasController.noteUserMove / homeSpot (private).

## DISPLAY-08 Display changes while paused leave windows alone
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** ac50e01 (0.1.0)
- **Before:** With Expanse paused, a display change still ran its re-layout, moving windows that should stay in the macOS layout.
- **Setup:** Expanse paused (panel switch off). Log stream running.
- **Steps:**
  1. Change the resolution, or unplug a display. Wait 25s.
  2. Resume Expanse.
- **Expected:** 1: Expanse moves no window; no `display changed` or `move` lines. 2: the layout comes back, fitted to the current screen.
- **Automate:** manual: needs a real display change.

## DISPLAY-09 Overlaps after a display change are pushed 20pt apart; close placements stay
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 44a7f91 (0.1.1)
- **Before:** Windows a display change made overlap were pushed apart only until they touched (0pt gap), not to the standard 20pt.
- **Setup:** Windows A and B placed 8pt apart (drag with ⌘ held). Elsewhere, windows that a smaller screen will make overlap.
- **Steps:**
  1. Switch to a smaller resolution. Press ⌥`.
- **Expected:** Windows that overlap because of the smaller screen are pushed apart to exactly 20pt. A and B are still 8pt apart.
- **Automate:** unit: CanvasController.separate(_:gap:onlyOverlaps:keep:).
- **Note:** 60b2a87 also leaves overlaps you chose in the home layout (DISPLAY-11).

## DISPLAY-10 A display change with 50 windows doesn't freeze Expanse
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 60b2a87 (0.1.3)
- **Before:** Re-placing every window after a display change, and re-asserting the positions macOS shoves while it settles, ran on the main thread and froze Expanse for a second or more with 50 windows.
- **Setup:** 50 windows.
- **Steps:**
  1. Change the resolution, then straight away move the pointer and press ⌥`.
- **Expected:** The overlay covers the reshuffle and Expanse stays responsive. Input waits only until the windows are in place.
- **Automate:** manual: real display change and performance.

## DISPLAY-11 Overlapping windows you chose stay overlapping across screens
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 60b2a87 (0.1.3)
- **Before:** Fitting the layout to a smaller screen pushed apart windows that overlapped in the home layout (cascaded Finder windows). Everything below them was shoved down, and the shift stuck back on the big screen: a round trip moved 22 of 53 windows.
- **Setup:** Big display. Four cascaded Finder windows (each offset, overlapping) with other windows below them.
- **Steps:**
  1. Switch to a smaller resolution, then back. Press ⌥`.
- **Expected:** The Finder windows stay cascaded on both screens and the windows below aren't pushed down. After the round trip every window is exactly where it was.
- **Automate:** unit: CanvasController.overlappingPairs(_:) and separate(_:gap:onlyOverlaps:keep:).

## DISPLAY-12 A display change waits for windows still moving
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 14c9218 (0.1.3)
- **Before:** A display change that came while windows were still moving in the background (a glide, the last re-layout pass) went ahead under them, and windows landed where the previous screen wanted them.
- **Setup:** At 100%, windows far to the right.
- **Steps:**
  1. Press ⌃→ and change the resolution at the same moment.
  2. Press ⌥`.
- **Expected:** Once the glide is done, the re-layout runs. Every window is placed for the new screen at its chosen size.
- **Automate:** manual: real timing.

## DISPLAY-13 The big-screen layout survives a trip to the laptop screen and back
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 8dcba7d (0.1.12)
- **Before:** Coming back to the big screen, macOS gave windows their big sizes back before Expanse moved them, so for a moment nothing looked shrunk, and the tightened laptop layout was saved as home. The gaps never unwound, and windows with wider gaps came back overlapping.
- **Setup:** A laptop with an external display as main. A layout where some windows have gaps wider than 20pt between them. Zoom out and take a screenshot.
- **Steps:**
  1. Unplug the display; the layout tightens to fit the laptop.
  2. Wait ten seconds, then plug it back in and wait until windows settle.
  3. Zoom out and compare with the screenshot.
- **Expected:** Every window is back at exactly its big-screen spot and size. The wider gaps are back, and nothing overlaps that didn't before.
- **Check in log:** `display changed: <old size> -> <new size>` both ways
- **Automate:** unit: CanvasController.homeFromCanvas doesn't change home while suspendTracking. manual for real displays. On a development build, `expanse://screen?w=1512&h=982` then `expanse://screen` stands in for unplugging.

## DISPLAY-14 Zoomed out during a screen change: no centring
- **Type:** Feature
- **Area:** DISPLAY
- **Commits:** 8dcba7d (0.1.12)
- **Setup:** Zoomed out (⌥`) on the big display.
- **Steps:**
  1. Unplug the display while zoomed out.
  2. Press Esc after things settle.
- **Expected:** At step 1 the canvas stays zoomed out, with no glide to centre a window. At step 2 it returns to 100% as usual, and no window is centred later because of the old screen change.
- **Automate:** unit: CanvasController.displaysChanged clears screenResized and centreAfterResize when isActive and final.

## DISPLAY-15 A display change isn't mistaken for full-screen shuffling
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 8dcba7d (0.1.12)
- **Before:** A display change also changes the Space. Since 1e85357, window moves in the next 1.5 s were treated as caused by a full-screen window and "put back" to their old places, fighting the display-change fit.
- **Setup:** Laptop with an external display, several windows.
- **Steps:**
  1. Unplug the display, then plug it back in.
- **Expected:** Windows end up where the fitted layout says on each screen.
- **Check in log:** no `moved as a full-screen window came or went; putting it back` lines during the change.
- **Automate:** unit: CanvasController.movedByFullScreen returns false while suspendTracking.

## DISPLAY-16 Apps that round their size don't make the layout creep
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 8dcba7d (0.1.12)
- **Before:** A window a point or two off its home size (an app rounding, like Terminal sizing to whole character cells) counted as shrunk. The windows beyond it moved by a point at every screen change.
- **Setup:** A Terminal window on the canvas with windows to its right and below it. Note their positions (`expanse://dump` on a development build, or a zoomed-out screenshot).
- **Steps:**
  1. Unplug and replug the display three times.
  2. Compare positions.
- **Expected:** The windows to the right of and below Terminal are at the same canvas positions after every round trip, with no drift.
- **Automate:** unit: CanvasController.fitLayoutToScreen and derive(home:sizes:). A size within tolerance of home counts as home.
- **Note:** The tolerance was 2pt here. eb224e7 widened it to CanvasController.appRounding (32pt), applied only when the home size fits the screen.

## DISPLAY-17 Relaunching on a bigger screen fits the saved layout to it
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 3c4c247 (0.1.18), a225c63 (0.1.18)
- **Before:** The saved layout holds sizes and spots from the screen it was saved on. Starting Expanse on a bigger screen left windows at the laptop's sizes in the tightened layout, all slightly out of place.
- **Setup:** A laptop and a bigger external display. Windows arranged on the big display at their chosen sizes.
- **Steps:**
  1. Unplug the display so the layout tightens on the laptop screen.
  2. Quit Expanse.
  3. Plug the big display back in (as the main display).
  4. Open Expanse.
- **Expected:** Windows go back to the sizes you chose and the home layout of the big display, as they would after a display change: none left at the laptop's sizes.
- **Check in log:** `layout fitted: <n> of <m> windows moved, derived=false`
- **Automate:** manual: needs two screen sizes and a relaunch.
- **Note:** At HEAD, windows move only by however much the screen differs from the one the layout was fitted to (c6c639e, PERSIST-27).

## DISPLAY-18 A display change while zoomed out fits the layout
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 3c4c247 (0.1.18), a225c63 (0.1.18)
- **Before:** A display change while zoomed out left the canvas layout as it was (the old screen's sizes) until you left the canvas.
- **Setup:** Big display, windows at their chosen sizes, some larger than the laptop screen.
- **Steps:**
  1. Press ⌥` to zoom out.
  2. Unplug the big display (or, with debug commands on, `open "expanse://screen?w=1280&h=800"`).
  3. Wait about 3s, still zoomed out.
  4. Zoom back in.
- **Expected:** While still zoomed out, the canvas shows the layout fitted to the new screen: no window bigger than the screen less 16pt each side, gaps kept. Zooming in, the real windows follow. The view isn't recentred on any window while zoomed out.
- **Check in log:** `display changed: … -> …`, then `layout fitted: …`
- **Automate:** manual: needs a display change.

## DISPLAY-19 A round trip between two screens puts every window back exactly
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** c6c639e (0.1.22)
- **Before:** Positions were re-derived from home spots on every display change, so whatever the layout had picked up since (windows opening, closing, moving) was undone, every window jumped, and a round trip didn't come back exactly.
- **Setup:** Big display, 6+ windows in rows and columns. For positions, debug commands on (a development build with `defaults write com.invignation.expanse debugURLCommands -bool true`).
- **Steps:**
  1. `open "expanse://dump"` and note each window's `canvas=`.
  2. Unplug the big display (or `open "expanse://screen?w=1280&h=800"`); wait 3s.
  3. Plug it back in (or `open "expanse://screen"`); wait 3s.
  4. Dump again.
- **Expected:** Every window's `canvas=` frame equals its value from step 1. On the smaller screen each window only moved as far as the change moved it in the tightened layout.
- **Automate:** unit: CanvasController.derive(home:sizes:) for both sizes (moves are after − before).

## DISPLAY-20 A window opened on the smaller screen moves with its neighbours
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** c6c639e (0.1.22)
- **Before:** A window opened or moved on a smaller screen had no home spot, or one that didn't explain where it sat. Back on the big screen it moved by the wrong amount, or stayed put while its neighbours grew over it.
- **Setup:** On the laptop screen only, the layout tightened.
- **Steps:**
  1. Open a new window; it's placed beside a window A, 20pt away.
  2. Drag another window B to sit 20pt below A.
  3. Plug in the big display.
- **Expected:** The new window and B keep their 20pt gaps to A as A grows back: no overlaps, nothing left behind.
- **Check in log:** `re-homed <n> windows: <App>[<id>], …`
- **Automate:** unit: CanvasController.anchors(_:in:) and derive; rehomeStrays needs extracting.

## DISPLAY-21 A window in a column stays lined up after a display change and back
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** c6c639e (0.1.22)
- **Before:** Each window kept its distance to the nearest window on its left, even across groups, so a window under another in a column could drift out of line after a display change.
- **Setup:** Big display. Window A with window B under it, left edges lined up; a wide group to their left.
- **Steps:**
  1. Unplug the big display; look at A and B.
  2. Plug it back in.
- **Expected:** On both screens B's left edge stays lined up with A's.
- **Automate:** unit: CanvasController.derive(home:sizes:) (edge anchor keeps the column).
- **Note:** c047399 fixed the case where capping to a smaller screen gives windows the same width (the tie now counts as unchanged).

## DISPLAY-22 A window in a column stays lined up after a smaller screen and back
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** c047399 (0.1.26)
- **Before:** On the smaller screen, the windows left of a column were capped to the same width, which put the lower window of the column exactly the standard gap (20 pt) from its left-hand neighbour. That tie went to the gap, so its anchor no longer matched the home layout's; Expanse gave it a new home spot off its column, and back on the big screen it no longer lined up under the window above.
- **Setup:** A laptop with an external display bigger than its own screen, Expanse running on the external display. On the canvas: two windows stacked on the left (L1 above L2, the standard gap apart), L1 wider than L2 and both wider than the laptop's screen; on their right a column of two windows, A above B, left edges lined up, the standard gap apart, A the standard gap right of L1.
- **Steps:**
  1. Unplug the external display (lid open) so Expanse fits the layout to the laptop's screen; wait for the display change to settle (about 20 s).
  2. Zoom out (⌥`) and look at the column.
  3. Plug the external display back in; wait for it to settle; zoom out again.
- **Expected:** On the laptop, L1 and L2 are both capped to the screen less 16 pt each side, and B stays under A. Back on the big display every window is where it was before: B directly under A, left edges lined up, nothing shifted.
- **Check in log:** No `re-homed … windows: …` line naming B during either display change.
- **Automate:** unit: `CanvasController.isNearest(_:_:in:)` with frames where B's gap to L2 ties its edge offset under A (gap anchor wins `anchor`, but `isNearest(.edge(A))` must be true); then `rehomeStrays` leaves B's home alone.

## DISPLAY-23 Locking the Mac doesn't move windows
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 9183b47 (0.1.30)
- **Before:** On 29 Oct, at the lock screen, macOS pulled every parked window onto a smaller screen at one spot, and Expanse followed that as if you'd moved them: the pile was kept as your layout.
- **Setup:** Expanse with many windows, most parked off screen; ideally a laptop with an external display, as on 29 Oct. Note the arrangement (zoom out) and keep a copy of `~/Library/Application Support/Expanse/layout.json`.
- **Steps:**
  1. Lock the Mac (⌃⌘Q) and leave it locked for several minutes (long enough for the displays to sleep).
  2. Unlock.
  3. Zoom out.
- **Expected:** Every window is where it was before locking; parked windows are still parked; nothing is piled at one spot, and the saved layout's positions are unchanged.
- **Check in log:** `locked: window moves not followed until unlocked`, then `unlocked: re-placing windows`.
- **Automate:** manual: needs the lock screen (unit tests for the lock pile-up are planned once the layout maths has its own target).
- **Note:** 804e187 later made a ⌘-Tab of yours in the 20 s after unlocking be followed once windows are back, and a new window then go beside your work.

## DISPLAY-24 Sleeping the displays doesn't move windows
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 9183b47 (0.1.30)
- **Before:** Window moves macOS made while the displays slept were followed as yours.
- **Setup:** As DISPLAY-23, with "require password after sleep" off so this doesn't also lock.
- **Steps:**
  1. In Terminal: `pmset displaysleepnow`.
  2. Wait a minute, then wake the displays with a key or the mouse.
  3. Zoom out.
- **Expected:** Every window is back where it was; none moved by macOS while asleep is kept.
- **Check in log:** `displays asleep: window moves not followed until they wake`, then `displays awake: re-placing windows`.
- **Automate:** manual: needs real display sleep.

## DISPLAY-25 A display change while locked isn't followed before you unlock
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 9183b47 (0.1.30)
- **Before:** The display change's 20 s settle period could end while the Mac was still at the lock screen, and moves macOS made there were then followed.
- **Setup:** A laptop with an external display, windows on the canvas.
- **Steps:**
  1. Lock the Mac (⌃⌘Q).
  2. Unplug the external display; wait more than 20 s.
  3. Unlock; wait for things to settle.
  4. Plug the display back in; wait; zoom out.
- **Expected:** After unlocking, the layout is fitted to the laptop's screen from its home layout, as for any display change; nothing macOS did at the lock screen is kept. Back on the external display every window is exactly where it was.
- **Check in log:** No `display change settled` while locked; after `unlocked: re-placing windows`, `display change settled` about 20 s later.
- **Automate:** manual: lock screen plus a display change.

## DISPLAY-26 After unlocking, ⌘-Tab follows to the app's window
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 804e187 (0.1.32)
- **Before:** For about 20s after unlocking or waking, Expanse ignored every focus change: ⌘-Tab (or the Dock) to an app whose window was off screen did nothing.
- **Setup:** Outlook (or any app) with its window parked off screen; you're in another window at 100%.
- **Steps:**
  1. Lock the Mac (⌃⌘Q) and unlock it.
  2. Within 20 seconds, ⌘-Tab to Outlook (or click it in the Dock).
- **Expected:** Once windows are back in place after the unlock, the view glides to Outlook's window. A switch made before they're back is retried every half second for up to 5 seconds.
- **Automate:** manual: lock and unlock, real focus changes.

## DISPLAY-27 After unlocking, focus changes macOS makes itself aren't followed
- **Type:** Feature
- **Area:** DISPLAY
- **Commits:** 804e187 (0.1.32)
- **Setup:** Several apps with windows on the canvas, at 100%.
- **Steps:**
  1. Lock the Mac and unlock it. Don't touch the keyboard or mouse for 20 seconds.
- **Expected:** The view stays put even if macOS moves focus about while the displays settle; only a switch you made (a click, a key, or letting go of ⌘ after ⌘-Tab, in the last 1.5s) is followed. Nothing is followed while the screen is still locked.
- **Check in log:** "<App>[<id>] focused while displays settle, not by you: not followed".
- **Automate:** manual: lock screen and system input timing.

## DISPLAY-28 A window opened just after unlocking goes beside your work
- **Type:** Bug fix
- **Area:** DISPLAY
- **Commits:** 804e187 (0.1.32)
- **Before:** For about 20s after an unlock or wake no new window was placed: an app opened then (Outlook) was left in the middle of the view, over your windows.
- **Setup:** Expanse running at 100%; Calculator not running.
- **Steps:**
  1. Lock the Mac and unlock it.
  2. Within 20 seconds open Calculator.
- **Expected:** Calculator's window goes in a free spot beside the window you're working on, like any new window. One that opens before the layout is back in place gets its spot on the canvas and goes there with the rest.
- **Automate:** manual: lock and unlock.
