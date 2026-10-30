# TRACK: Finding and following windows

[All areas](README.md)

## TRACK-01 Windows out of view are parked in the bottom-right corner
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 0cdf466 (0.1.0), 09aabdf (0.1.10)
- **Setup:** At 100%, with a window well out of view on the canvas (drag it away while zoomed out, then Esc).
- **Steps:**
  1. Look at the bottom-right corner of the screen.
  2. Zoom out.
- **Expected:** Step 1: the out-of-view window's real window sits in the parking corner, only a small corner of it showing at the bottom right of the usable screen (macOS may nudge it so a strip stays in view). Step 2: on the canvas it's at its own spot, not in the corner.
- **Check in log:** with a dump (debug): `parked=true` for that window.
- **Automate:** unit: `CanvasController.commitPlan()` / `goesOnScreen(_:in:panels:)` returns parked for frames outside the viewport.

## TRACK-02 A window partly in view stays on screen at its spot
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 0cdf466 (0.1.0), 4045597 (0.1.31)
- **Setup:** A window placed so about a third of it shows at the right edge of the screen, away from the minimap.
- **Steps:**
  1. Go to 100% with that view.
- **Expected:** The real window is put there, partly off the right edge, not parked: at least 48×48pt of it is on screen. A window showing less than 48pt either way is parked instead.
- **Automate:** unit: `CanvasController.goesOnScreen(_:in:panels:)` (48pt minimum).
- **Note:** Since 4045597 a sliver (under a third of the window, or 200pt) that would cover the minimap or Spaces panel is parked too, and the backdrop draws it under them.

## TRACK-03 A window cut off at the top stays parked and is drawn on the backdrop
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 0cdf466 (0.1.0), 42b415b (0.1.29)
- **Setup:** At 100%, a window just below the menu bar.
- **Steps:**
  1. `open "expanse://enter?zoomOut=0"`, then `open "expanse://pan?dx=0&dy=-150"`, then `open "expanse://exit"`.
- **Expected:** The window would now start above the screen's top, where macOS won't put a title bar (it would shove it down), so the real window is parked; its picture is drawn on the desktop where it belongs, cut off at the top edge.
- **Automate:** unit: `CanvasController.goesOnScreen` returns false when `r.minY < vp.minY - 1`.

## TRACK-04 ⌘-Tab or the Dock to an off-screen window glides to it
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 0cdf466 (0.1.0), 6cd5611 (0.1.29)
- **Setup:** At 100%, auto-centre on; a TextEdit window parked (out of view); another app in front.
- **Steps:**
  1. ⌘-Tab to TextEdit (or click its Dock icon).
- **Expected:** The view glides to centre TextEdit's focused window, which ends up in front with the keyboard.
- **Check in log:** `focus-settled glide to TextEdit[<id>]: parked in …`
- **Automate:** manual: app activation.
- **Note:** 6cd5611 made this also work for an app you'd hidden. With auto-centre off see NAV-24.

## TRACK-05 Clicking a partly visible window at 100% centres it, and typing goes to it
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 0cdf466 (0.1.0), e1165df (0.1.25)
- **Setup:** At 100% after a glide (not after panning at 100%), auto-centre on; a window partly off the right edge.
- **Steps:**
  1. Click inside that window and type straight away.
- **Expected:** The view glides to centre the window, which keeps the keyboard throughout (the canvas never takes focus during a glide): every typed character lands in it.
- **Automate:** manual: focus and glide.
- **Note:** e1165df: after you've panned at 100% yourself, a click on a window you can see focuses it where it is, without moving the view.

## TRACK-06 Moving a window yourself at 100% is followed
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** At 100%.
- **Steps:**
  1. Drag a window by its title bar to another place.
  2. Zoom out.
- **Expected:** The canvas shows the window at its new place, relative to the others; it isn't put back.
- **Check in log:** `follow <App>[<id>] moved to {x, y} (last placed …)`
- **Automate:** manual: AX move notifications.

## TRACK-07 A closed window leaves the canvas
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 0cdf466 (0.1.0), 2d65ed9 (0.1.31)
- **Setup:** At 100%, a Finder window on screen.
- **Steps:**
  1. Close it with its red button (or ⌘W in Finder).
  2. Zoom out.
- **Expected:** The window is gone from the canvas and the minimap within a moment of closing; nothing is left in its place.
- **Check in log:** `dropped Finder[<id>]: not in the window list`
- **Automate:** manual: window close.
- **Note:** Since 2d65ed9 a closed window's spot isn't kept.

## TRACK-08 The canvas stacks windows as macOS does
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** At 100%, windows A and B overlapping, A in front.
- **Steps:**
  1. Click B so it comes in front. Wait 5 seconds.
  2. Zoom out.
- **Expected:** On the canvas B is drawn over A, matching the screen.
- **Automate:** unit: `CanvasController.orderByWindowServer(_:)` given a rank map.

## TRACK-09 Restore all windows brings out-of-view windows on screen
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 0cdf466 (0.1.0), a2d80de (0.1.31)
- **Setup:** At 100%, several windows parked out of view; two on screen.
- **Steps:**
  1. Menu bar icon › "Restore all windows" (in Earlier layouts).
- **Expected:** The panel closes. Each parked window is moved on screen near the top middle: the first centred 40pt below the menu bar, each next one 28pt further right and down (wrapping after eight). The windows already on screen don't move. Zoomed out afterwards, the canvas shows them at those new spots.
- **Automate:** unit: the cascade offsets in `CanvasController.restoreAll()`.
- **Note:** README says "brings every window into view, stacked in the middle"; the code moves only windows that were out of view (parked), as the panel's tooltip says.

## TRACK-10 A minimised or hidden window comes back to its own spot
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 0cdf466 (0.1.0), 5dab7a1 (0.1.0), ac50e01 (0.1.0), c30b1b3 (0.1.3)
- **Setup:** At 100%. A TextEdit window at a spot you can recognise; zoom out once to see where it is on the canvas.
- **Steps:**
  1. Press ⌘M, then click the window in the Dock.
  2. Press ⌘H in TextEdit, then ⌘-Tab back to it.
  3. Press ⌥` to check its spot.
- **Expected:** Both times it returns to exactly the same canvas spot and size. It isn't placed again as a new window beside something else.
- **Automate:** manual: needs a real minimise and hide.
- **Note:** Since 6cd5611 and 29ffe6a, a window you bring back yourself that ends up in front gets the view, as a new window would.

## TRACK-11 A stranded window in the parking corner is brought into view
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 0cdf466 (0.1.0), 44a7f91 (0.1.1), 09aabdf (0.1.10)
- **Before:** Only on the first scan, and only within 8pt of the corner, was a stranded window brought out. One left in the corner later, with no record of where it belonged, stayed out of sight.
- **Setup:** Windows parked. Back up layout.json.
- **Steps:**
  1. `kill -9 $(pgrep -x Expanse)` (windows stay in the corner).
  2. Move `~/Library/Application Support/Expanse/layout.json` aside.
  3. Launch Expanse.
- **Expected:** Windows in the corner come out horizontally centred, 40pt below the top of the usable screen, where you can see them.
- **Automate:** manual: needs real windows left in the corner.

## TRACK-12 Opening a document centres its new window, not the old one
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 5dab7a1 (0.1.0)
- **Before:** Opening a document focuses the app's old window for a moment, then the new one. Canvas acted on the first change and glided to the old window.
- **Setup:** At 100%, auto-centre on. Preview has one document window. The screen is full, so a new window will go off-screen.
- **Steps:**
  1. In Finder, double-click a second PDF so Preview opens it in a new window.
- **Expected:** The view ends centred on the new document's window. It never glides to the old Preview window first.
- **Check in log:** a `glide to Preview[<new id>]` line and no glide to the old window's ID.
- **Automate:** manual: depends on real focus-change timing (Expanse waits about 0.12s for focus to settle).
- **Note:** The wait was 0.2s here and 0.12s from 3144b09.

## TRACK-13 A window that comes back by itself returns quietly to its spot
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 363d854 (0.1.0)
- **Before:** In 5dab7a1, a window back from hiding or minimising whose spot was off-screen always made the canvas glide to it, whatever brought it back.
- **Setup:** At 100%. A TextEdit window is parked off-screen (hop away from it). Finder is in front.
- **Steps:**
  1. Finder › Hide Others (⌥⌘H).
  2. Finder › Show All.
  3. Press ⌥` to check.
- **Expected:** The view doesn't move and Finder stays in front. TextEdit's window is back at its old canvas spot, still out of view.
- **Automate:** manual: real hide and show.
- **Note:** Since 6cd5611 and 29ffe6a, a window you bring back yourself (⌘-Tab or the Dock to a hidden app, the Dock to a minimised window) that ends up in front gets the view, like a new window.

## TRACK-14 Apple's system prompts stay above app windows
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 9f92b18 (0.1.0)
- **Setup:** At 100%, a large window from another app on screen.
- **Steps:**
  1. Bring up a macOS prompt from a background system process (a Screen Recording reminder, or a password or security prompt).
  2. Click the large window so it comes in front of where the prompt is.
  3. Hop with ⌃→.
- **Expected:** The prompt stays above app windows after the click and after the hop.
- **Check in log:** `raised system prompt [<id>]`
- **Automate:** manual: needs a real system prompt.
- **Note:** This covers prompts at normal window level, at least 150×80, from com.apple.* background processes. Prompts at dialog level are handled by 9428c25 (the canvas goes under any dialog).

## TRACK-15 A window back from hiding keeps its macOS spot and chosen size
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** ac50e01 (0.1.0)
- **Before:** A window back from hiding or minimising came back with only its canvas spot. Its record of where macOS had it and the size you chose were lost, so Quit put it in the wrong place and a display change left it at the wrong size.
- **Setup:** Note TextEdit's macOS position before Expanse. On the canvas, drag the window to 1000×700.
- **Steps:**
  1. Minimise the window and restore it from the Dock.
  2. Switch to a smaller resolution and back.
  3. Quit Expanse.
- **Expected:** 2: the window grows back to 1000×700. 3: it goes back to the position and size macOS had before Expanse.
- **Automate:** manual: real minimise and display changes.

## TRACK-16 Window scans held back during a drag don't pile up
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** ac50e01 (0.1.0)
- **Before:** Every scan that came due during a glide, drag or animation scheduled its own retry 0.4s later, so a long drag stacked up retries that all ran afterwards.
- **Setup:** Zoomed out with 30+ windows. Activity Monitor open.
- **Steps:**
  1. Drag a window in circles for 20s, then let go.
- **Expected:** Expanse stays responsive throughout. After you let go, a single scan runs, and Expanse's CPU settles within a couple of seconds.
- **Automate:** unit: CanvasController.sync keeps at most one retry outstanding (syncRetryScheduled).

## TRACK-17 A frozen app can't freeze Expanse
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** ac50e01 (0.1.0)
- **Before:** An Accessibility call to a hung app waited for macOS's default timeout (several seconds), freezing Expanse and its full-screen overlay with it.
- **Setup:** TextEdit with a window on the canvas, plus other apps' windows.
- **Steps:**
  1. `kill -STOP $(pgrep -x TextEdit)`
  2. Zoom out, hop, drag windows, click TextEdit's window, leave the canvas.
  3. `kill -CONT $(pgrep -x TextEdit)`
- **Expected:** Expanse keeps responding. At worst TextEdit's own window lags (each call to it gives up after 0.5s). The overlay never gets stuck and there's no beachball.
- **Automate:** manual: needs a hung app.

## TRACK-18 An app that quit doesn't leave its observer behind
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** ac50e01 (0.1.0)
- **Before:** Expanse kept a quit app's Accessibility observer. A later app given the same process ID was handed that dead observer, so its new windows and focus changes went unseen until the next scan.
- **Setup:** At 100%.
- **Steps:**
  1. Quit several apps, then launch other apps and open windows in them.
- **Expected:** Each new app's first window is taken on and placed beside your work within about a second, and focus changes in it are followed.
- **Automate:** unit: CanvasController drops observers[pid] on didTerminateApplication (process ID reuse can't be forced by hand).

## TRACK-19 Records of departed windows are pruned
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** ac50e01 (0.1.0)
- **Before:** Expanse kept a record of every window that ever left the canvas, closed ones included, for ever.
- **Setup:** Finder with five windows.
- **Steps:**
  1. Close all five, wait 10s.
  2. Open a new Finder window.
- **Expected:** The new window is placed as a new window beside your work, not in a closed window's spot.
- **Automate:** unit: CanvasController.remove(_:) pruning: closed records after 10s, others after a week, 300 at most.
- **Note:** This commit pruned after a week; 2d65ed9 drops closed windows' records after 10s (kept a moment for a tab taking over).

## TRACK-20 A window found in the parking corner never takes that spot
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 44a7f91 (0.1.1)
- **Before:** After sleep and wake, apps answer Accessibility slowly and a placement can fail to register. Parked windows then looked "moved" to the corner and all took the same canvas spot; the next re-layout spread the pile into a column.
- **Setup:** 10+ windows, several parked.
- **Steps:**
  1. Apple menu › Sleep. Wait 5 minutes, wake the Mac and unlock.
  2. Press ⌥`.
- **Expected:** Every window is at its own spot. None are piled at one place or lined up in a new column.
- **Check in log:** no `follow … moved to` lines with bottom-right corner coordinates.
- **Automate:** unit: CanvasController.inParkingCorner (private).
- **Note:** The corner is measured from the usable screen area since 09aabdf.

## TRACK-21 Dragging a real window at 100% is followed smoothly
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 61e6e55 (0.1.3)
- **Setup:** At 100%. Log stream running.
- **Steps:**
  1. Drag a window by its title bar around the screen for 5s, then drop it.
  2. Press ⌥`.
- **Expected:** The drag is smooth. On the canvas the window is where you dropped it. Each window is looked at no more than every 50ms during the drag, and the echoes of Expanse's own moves are ignored.
- **Check in log:** `follow <App>[<id>] moved to …` lines, not one per mouse event.
- **Automate:** manual: real AX notifications.

## TRACK-22 Parked windows aren't moved again on every hop
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 61e6e55 (0.1.3)
- **Before:** macOS nudges parked windows within the corner, so they never matched the park point exactly, and every commit (each hop and glide) moved every parked window again: dozens of Accessibility moves per hop with 50 windows.
- **Setup:** 30+ windows, most parked. Log stream running.
- **Steps:**
  1. Hop with ⌃→ five times.
- **Expected:** `move` lines appear only for windows coming on screen or going off it. Windows that stay parked aren't moved again.
- **Automate:** unit: CanvasController.alreadyAt(_:_:parked:) (private): parked anywhere in the corner counts.

## TRACK-23 Window scans don't ask apps about windows already in place
- **Type:** Feature
- **Area:** TRACK
- **Commits:** 61e6e55 (0.1.3)
- **Setup:** 50 windows at 100%. Log stream running.
- **Steps:**
  1. Leave the Mac idle for 2 minutes.
- **Expected:** Scans make no Accessibility calls for windows that are where they should be, and each window's kind is asked only once.
- **Check in log:** no `slow: window scan took` lines; any that do appear report few Accessibility calls.
- **Automate:** manual: real apps answering Accessibility.

## TRACK-24 A newly launched app's first window is taken on in about a second
- **Type:** Feature
- **Area:** TRACK
- **Commits:** c30b1b3 (0.1.3)
- **Setup:** At 100%. TextEdit not running.
- **Steps:**
  1. Launch TextEdit and open a new document.
- **Expected:** Within about a second the window is placed in a free spot beside what you're working on. Every regular app is watched, even ones with no window on the canvas.
- **Check in log:** `placed new window TextEdit at …`
- **Automate:** manual: real app launch.

## TRACK-25 A window restored from the Dock is back straight away
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** c30b1b3 (0.1.3)
- **Before:** Expanse didn't listen for windows being un-minimised, so a restored window came back on the canvas only at the next regular scan.
- **Setup:** At 100%.
- **Steps:**
  1. Minimise a window, click it in the Dock, and press ⌥` at once.
- **Expected:** It's on the canvas at its spot right away; restoring it triggers a scan.
- **Automate:** manual: real minimise and restore.

## TRACK-26 A scan during a glide doesn't drag windows back
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 14c9218 (0.1.3)
- **Before:** A window scan that ran while windows moved (a glide, leaving the canvas) or the camera changed was applied with out-of-date frames. Windows were "followed" back to where they'd been, and the wrong spot was saved.
- **Setup:** 30+ windows. Log stream running.
- **Steps:**
  1. For 30s, hop quickly with ⌃→ and ⌃←, zoom out and click windows to leave.
  2. Press ⌥`.
- **Expected:** Every window is at its canvas spot. No `follow … found at` lines for windows Expanse has just moved.
- **Automate:** unit: the staleness check in CanvasController.sync (scan input's move count and camera; needs a seam).
- **Note:** Since af8eff8 an out-of-date scan still takes on new windows, as well as dropping closed ones; another scan follows.

## TRACK-27 Switching apps quickly doesn't pull you back
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 14c9218 (0.1.3)
- **Before:** Expanse asks the app which window has focus in the background. An answer that came back after you'd switched to another app, or a hop had started, still acted, gliding back to the app you'd left.
- **Setup:** At 100%, auto-centre on. Apps A and B with windows off-screen.
- **Steps:**
  1. ⌘-Tab to A and straight away ⌘-Tab to B.
  2. ⌘-Tab to A and straight away press ⌃→.
- **Expected:** 1: the view ends on B. 2: the view ends on the hop's target. It never glides back to A.
- **Automate:** manual: real focus timing (focusQuery).

## TRACK-28 Ten windows opened at once all get a spot on the canvas
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** af8eff8 (0.1.3)
- **Before:** Opening ten windows in a burst left most of them where their app put them, over your other windows, for up to 10 seconds. A window its app hadn't finished setting up (not yet in the app's Accessibility window list, or no subrole yet) was written off as "not a document window" for 10 s.
- **Setup:** At 100%, a few windows on the canvas.
- **Steps:**
  1. Click Finder in the Dock and press ⌘N ten times as fast as you can.
  2. Wait two seconds, then press ⌥` to zoom out.
- **Expected:** Each new Finder window gets its own free spot on the canvas beside what you were working on, all within a couple of seconds. None is left stacked at Finder's default position or over your other windows.
- **Check in log:** one `placed new window Finder at …` line per window. There are no `not on the canvas: Finder[…]: its app doesn't list it as one of its windows (Accessibility) yet` lines, because that note only appears for a window still unlisted after 5 s.
- **Automate:** unit: CanvasController.axSnapshot(for:input:). A window the app doesn't list yet, or that has no subrole, becomes WindowKind.pending for its first 5 s. It is asked about again at every scan, and AXSnapshot.pending makes the next scan follow quickly.
- **Note:** Later commits ask again about a window still unlisted after 5 s: every 2 s for its first minute, then every 10 s (WindowKind.askAgainAfter). The log also says why it isn't on the canvas.

## TRACK-29 A window scan asked for during another scan isn't lost
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** af8eff8 (0.1.3)
- **Before:** A scan asked for while another was running was dropped. A window that opened mid-scan then waited for some later event to be noticed. Each new event also pushed the pending scan back, so a steady stream of new windows was only scanned once it stopped.
- **Setup:** At 100%.
- **Steps:**
  1. In Finder press ⌘N, then again about every quarter second, eight times.
- **Expected:** Each window is placed on the canvas within a moment of opening, while you are still opening more. None waits until you stop.
- **Check in log:** the `placed new window Finder …` lines are spread through the burst, not all bunched at the end.
- **Automate:** unit: CanvasController.sync and syncSoon. A sync call while `syncing` sets `syncAgain`, and the finished scan then calls syncSoon. A second syncSoon while one is due doesn't replace the scheduled work item.

## TRACK-30 A scan that overlapped a window move still adds new windows
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** af8eff8 (0.1.3)
- **Before:** A scan that ran while Expanse was moving windows was treated as out of date and added no new windows. In a burst every arrival moves windows, so most scans were out of date and new windows kept being skipped.
- **Setup:** At 100%, auto-centre on.
- **Steps:**
  1. Open ten Finder windows at once (⌘N ten times quickly).
  2. Zoom out.
- **Expected:** All ten are on the canvas in free spots. Windows that opened while their siblings were being moved are placed too; none waits for the burst to end. Existing windows are not "followed" to stale positions from those scans: their spots don't change.
- **Automate:** unit: CanvasController.apply(_:ax:stale:). With stale = true, an unknown window is still added (using the live flag), but known windows' frames are not taken.

## TRACK-31 Opening many windows at once doesn't freeze the canvas
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** af8eff8 (0.1.3)
- **Before:** Signing up for each new window's notifications (five per window) waited on the app, on the main thread. That took about half a second while Finder was busy opening ten windows, and hops and the canvas froze meanwhile.
- **Setup:** At 100%, at least three windows to hop between.
- **Steps:**
  1. Press ⌘N ten times quickly in Finder.
  2. Straight away press ⌃→ and ⌃← a few times, then ⌥` and pinch.
- **Expected:** Hops, zooming and panning respond at once during the burst. There is no visible half-second stall.
- **Automate:** manual: needs a real app slow to answer Accessibility. AppObserver.add now runs on a per-app queue, off the main thread.

## TRACK-32 An app's late move doesn't drag a window off its spot
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** af8eff8 (0.1.3)
- **Before:** A busy app (Finder opening ten windows) could carry out an old move after a newer one, or set a new window's position a moment after Expanse had placed it. Expanse followed the window there as if you had moved it.
- **Setup:** At 100%.
- **Steps:**
  1. Open ten Finder windows at once.
  2. Wait five seconds, then zoom out and compare each window with where the log says it was placed.
- **Expected:** Each window stays at the spot Expanse gave it. Expanse undoes a move by the app within 5 s of the window opening, or a move back to the window's previous spot within 10 s of Expanse placing it. It does this only once per window per 10 s, so an app that insists gets its way.
- **Check in log:** `Finder[<id>] moved to {x, y} by its app right after being placed; putting it back`
- **Automate:** unit: CanvasController.cameBack(_:to:). It returns true when the point is the window's placedBefore (or the window is under 5 s old), it was last placed under 10 s ago, and it wasn't put back in the last 10 s; otherwise false.

## TRACK-33 Dragging a just-opened window yourself is still followed
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** af8eff8 (0.1.3)
- **Before:** — (edge case of TRACK-32: your own drag must not be mistaken for the app's late move)
- **Setup:** At 100%.
- **Steps:**
  1. Press ⌘N in Finder.
  2. Within two seconds, drag the new window by its title bar to another spot.
- **Expected:** The window stays where you dropped it, and its canvas spot follows; it is not put back.
- **Check in log:** `follow Finder[<id>] moved to …`, with no `putting it back` line for it.
- **Automate:** unit: CanvasController.realWindowChanged. With userDragging true, cameBack isn't consulted.

## TRACK-34 Parked windows stay parked when the Dock is always shown
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 09aabdf (0.1.10)
- **Before:** macOS nudges a parked window back until a strip of it is inside the usable screen area. With the Dock always shown, that strip sits above the Dock, outside the old parking corner. Parked windows were taken for windows you had moved and followed to the screen's corner on the canvas, and every hop waited the full quarter second for them to land.
- **Setup:** System Settings › Desktop & Dock › "Automatically hide and show the Dock" off, with the Dock at the bottom; run again with it on the right. Several windows, some off screen (parked).
- **Steps:**
  1. Press ⌃→ and ⌃← several times.
  2. Zoom out.
- **Expected:** Hops land promptly. Parked windows keep their canvas spots: none jumps to the corner of the screen on the canvas.
- **Check in log:** no `follow <App>[<id>] moved to …` lines for parked windows, and no `gave up on windows landing after …` lines.
- **Automate:** unit: CanvasController.parkingCorner and inParkingCorner, given a screen frame and a visibleFrame with a bottom or right Dock.

## TRACK-35 Closing a window keeps the view where it is
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** ed61c70 (0.1.27)
- **Before:** After you closed a window, macOS gave focus to another of the app's windows, wherever it was on the canvas, and the view glided there, which looked like a window reopening.
- **Setup:** At 100%, two Finder windows: F1 in view, F2 far off screen. Auto-centre on (default).
- **Steps:**
  1. In F1, ⌘W (or click its red close button).
  2. Don't click or press anything for 2 s.
- **Expected:** F1 closes and the view stays where it was; Expanse doesn't glide to F2, though F2 now has focus. A click or key press of yours afterwards is followed as usual.
- **Check in log:** `Finder[<F2 id>] got focus after a window of its app closed; the view stays`.
- **Automate:** manual: needs macOS's focus change after a close (the rule: same app, within 1.5 s of the close, no click or key since, in `focusSettled`).

## TRACK-36 Hiding an app, then ⌘-Tab to it, glides to its window
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 6cd5611 (0.1.29)
- **Before:** An app back from hiding came back quietly: its window went back to its spot, but if that was off screen the view stayed put and ⌘-Tab seemed to do nothing.
- **Setup:** At 100%, a TextEdit window and other apps' windows on the canvas, far enough apart that the view can be on one without the other.
- **Steps:**
  1. Glide into the TextEdit window (click it on the canvas) and hide TextEdit (⌘H).
  2. ⌃+arrow to a window far enough away that TextEdit's spot is off screen.
  3. ⌘-Tab to TextEdit.
  4. Repeat steps 1–3, clicking TextEdit's Dock icon instead of ⌘-Tab in step 3.
- **Expected:** Each time, the view glides to TextEdit's window, as for an app opened again. If the window was already on screen, it just reappears and the view doesn't move.
- **Check in log:** `glide to TextEdit[<id>]` within 3 s of the unhide.
- **Automate:** manual: needs NSWorkspace's unhide notification and the window coming back in a scan (`shownAgainAt` in `arrive`).

## TRACK-37 A window brought back from the Dock glides into view
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 6cd5611 (0.1.29)
- **Before:** A minimised window restored from the Dock came back quietly to its spot off screen; the view didn't go to it.
- **Setup:** At 100%, a TextEdit window you can glide to, with its spot off the current view.
- **Steps:**
  1. Glide into the TextEdit window and minimise it (⌘M).
  2. ⌃+arrow to a window elsewhere so TextEdit's spot is off screen.
  3. Click the TextEdit window in the Dock.
- **Expected:** The window comes back at its own spot on the canvas, and the view glides to it.
- **Automate:** manual: needs Accessibility's deminiaturised notification (`restoredAt` in `arrive`).

## TRACK-38 Windows back after a Space switch come back quietly
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 6cd5611 (0.1.29)
- **Before:** Not a bug before; this guards the fix. Only an unhide or a restore from the Dock in the last 3 s counts as you asking for the window.
- **Setup:** At 100% on Desktop 1, with a second desktop Space in Mission Control; windows on the canvas, some off screen.
- **Steps:**
  1. Go to Desktop 2 with Mission Control, then back to Desktop 1.
  2. Separately: unplug and replug an external display.
- **Expected:** The canvas's windows come back to their spots and the view stays where it was; nothing glides to an off-screen window.
- **Automate:** manual: Space switches and display changes.

## TRACK-39 An app you quit and open again opens beside your work
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 2d65ed9 (0.1.31)
- **Before:** Quitting an app kept its windows' spots; opened again later, its window went back to its old spot (gliding the view there), even after you'd moved on.
- **Setup:** Expanse running more than 3 minutes. Calculator on the canvas well away from where you're working; you're in Safari at 100%.
- **Steps:**
  1. Quit Calculator (⌘Q).
  2. Wait a few seconds, then open Calculator from Spotlight.
- **Expected:** Calculator's window opens in a free spot beside the Safari window you're in, not at its old spot.
- **Check in log:** "Calculator quit" (no longer "keeping N window spots for when it opens again").
- **Automate:** manual: real app quit and relaunch.

## TRACK-40 Steam's window is taken onto the canvas
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 4045597 (0.1.31)
- **Before:** Steam's main window is drawn by Steam Helper, a background process with no Dock icon, so Expanse never took it on: it stayed where Steam put it and wasn't on the canvas.
- **Setup:** Steam installed and signed in; Expanse running; Window names when zoomed out on.
- **Steps:**
  1. Open Steam. Zoom out (⌥`).
  2. Click Steam's window.
  3. ⌘-Tab to another app and back to Steam.
  4. Hide Steam (⌘H), then show it again; then quit Steam.
- **Expected:** Steam's main window is on the canvas, named "Steam" (not "Steam Helper"). Clicking it glides to it and makes Steam the frontmost app. ⌘-Tab back to Steam follows to its window. Hidden, it leaves the canvas and comes back to its spot; quitting Steam removes it. Any window drawn by a helper process inside an app's bundle counts as that app's.
- **Check in log:** (dev build, debug commands on) `open "expanse://dump"` no longer lists Steam's window under "dump unmanaged … app=none".
- **Automate:** unit: CanvasController.appPID(owning:) with a helper process inside an app bundle; manual for Steam itself.

## TRACK-41 A window whose app gets its Dock icon late is picked up in seconds
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 08fca65 (0.1.31)
- **Before:** "Not an app" was remembered for 30s and the window was looked at again only every 10s: a window whose app got its Dock icon 7s after showing it was taken on 24s later.
- **Setup:** A test app that shows a titled window while it has no Dock icon (accessory) and becomes an ordinary app with a Dock icon 7s later. Expanse running at 100%.
- **Steps:**
  1. Launch the test app and time from its Dock icon appearing to its window being taken on (it moves beside your work; zoomed out it's on the canvas).
- **Expected:** Taken on within a few seconds of the Dock icon (measured 3.5s): it's asked about again every 2s for its first minute, with a scan to do it, and "not an app" is remembered for 3s.
- **Check in log:** once: "not on the canvas: <App>[<id>]: <App> isn't an app in the Dock (a menu-bar extra or background process)".
- **Automate:** unit: CanvasController.appPID(owning:) cache (3s for nil, 30s otherwise) and WindowKind.askAgainAfter.

## TRACK-42 A window its app is slow to list is picked up in under a second
- **Type:** Bug fix
- **Area:** TRACK
- **Commits:** 08fca65 (0.1.31)
- **Before:** After its first 5 seconds such a window was asked about only every 10s: one that became an ordinary window 7s in was taken on 11s later.
- **Setup:** A test app whose window shows at once but isn't in its Accessibility window list (or has no subrole) until 7s later. Expanse running.
- **Steps:**
  1. Launch the test app; time from the window becoming listed to its being taken on.
  2. Keep a second window unlisted for over a minute, then list it.
- **Expected:** Step 1: taken on within about 2s (measured under 1s). Step 2: after its first minute it's asked about every 10s, so it's taken on within 10s.
- **Check in log:** "not on the canvas: <App>[<id>]: its app doesn't list it as one of its windows (Accessibility) yet; asked again every 2s for a minute, then every 10s".
- **Automate:** unit: WindowKind.askAgainAfter (2s within 60s of unlistedSince, 10s after).
