# PERSIST: Layouts, restarts and snapshots

[All areas](README.md)

## PERSIST-01 The layout is saved to layout.json
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 0cdf466 (0.1.0), c7cba50 (0.1.0)
- **Setup:** Expanse running.
- **Steps:**
  1. Drag a window to a new spot on the canvas, go back to 100%, wait 2 seconds.
  2. Open `~/Library/Application Support/Expanse/layout.json`.
- **Expected:** The file was rewritten about a second after the change. It has the camera (`cameraX/Y`, `centerX/Y`), `cleanExit` (false while running), and one entry per window with app (`bundleID`, `appName`), hashed `title`, canvas spot and size (`x`, `y`, `w`, `h`), home spot, chosen size (`pw`, `ph`) and its macOS frame (`ox`, `oy`, `ow`, `oh`).
- **Automate:** unit: `LayoutStore.save`/`load` round trip.
- **Note:** The folder was `Canvas` until c7cba50.

## PERSIST-02 Relaunching puts windows back where they were on the canvas
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 0cdf466 (0.1.0), fbdc277 (0.1.0), 37a8848 (0.1.3), 13a79d4 (0.1.31)
- **Setup:** A layout arranged on the canvas that differs from where macOS had the windows; note the 100% view.
- **Steps:**
  1. Quit Expanse (menu bar icon › power button). Windows go back to the macOS layout.
  2. Open Expanse again.
- **Expected:** Every window goes back to its canvas spot and size (sizes that quitting put back are restored), and the view is centred on the same canvas point as before. Several windows with the same title (Finder on one folder) each get their own spot back. A window the saved layout has no spot for goes beside what's in view.
- **Check in log:** `first sync: …`, `restore size <App>[<id>] …`
- **Automate:** unit: `LayoutStore.takeMatch(...)` (ID+pid, then title, then app) | manual: relaunch.

## PERSIST-03 Quitting puts every window back where macOS had it
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 0cdf466 (0.1.0), ac50e01 (0.1.0), a2d80de (0.1.31)
- **Setup:** Before starting Expanse, note where each window is and its size. Start Expanse, rearrange on the canvas so some windows are parked, minimise one and hide one app (⌘H).
- **Steps:**
  1. Menu bar icon › power button (Quit Expanse).
- **Expected:** Every window, parked, minimised or hidden ones included, goes back to the position and size it had in macOS before Expanse took it on. None is left in the bottom-right corner. The backdrop and minimap disappear.
- **Automate:** manual: real windows.
- **Note:** If Expanse never finished the walkthrough, quitting moves nothing and doesn't overwrite the saved layout.

## PERSIST-04 Quitting brings a window whose old spot is gone into view
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** A window's macOS spot was on a bigger screen (or far right of a larger resolution); now on a smaller one (switch resolution, or a laptop without its display).
- **Steps:**
  1. Quit Expanse.
- **Expected:** That window comes back at the top of the screen, centred horizontally, 40pt below the menu bar, at its original size; others go to their original spots.
- **Automate:** unit: the off-screen test in `CanvasController.restore(_:to:currentSize:)` (original inset by 40pt not intersecting the viewport).

## PERSIST-05 kill or Ctrl-C puts windows back too
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Expanse running with some windows parked.
- **Steps:**
  1. `kill $(pgrep -x Expanse)` (or Ctrl-C if running it from a terminal).
- **Expected:** Same as quitting (PERSIST-03): every window back in the macOS layout, then Expanse exits.
- **Automate:** manual: signals.

## PERSIST-06 After a crash, quitting still returns the pre-Expanse layout
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Note the macOS layout. Start Expanse, park some windows.
- **Steps:**
  1. `kill -9 $(pgrep -x Expanse)`. Parked windows stay in the corner. (`cleanExit` in layout.json is false.)
  2. Open Expanse: windows go back to their canvas spots.
  3. Quit Expanse normally.
- **Expected:** Step 3 puts every window back where it was in the macOS layout before step 1's run started, not in the corner and not where step 2 found them.
- **Automate:** unit: `add()` takes `ox/oy/ow/oh` from the saved entry when `cleanExit != true` | manual: crash.

## PERSIST-07 Pause puts windows back and stops managing them
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 0cdf466 (0.1.0), a2d80de (0.1.31)
- **Setup:** Note the macOS layout before Expanse took on the windows; canvas rearranged, some windows parked.
- **Steps:**
  1. Menu bar icon › turn off the switch at the top right of the panel.
  2. Drag a window somewhere else.
- **Expected:** Step 1: every window goes back to where macOS had it (PERSIST-03); the backdrop and minimap go; the panel's status reads "Paused · windows back in the macOS layout" and the app icon in it turns grey; the panel stays open. Step 2: Expanse ignores the move.
- **Check in log:** `paused`
- **Automate:** manual: real windows.

## PERSIST-08 While paused, only ⌥` and the switch bring Expanse back
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 0cdf466 (0.1.0), 06a9a13 (0.1.0), 9f92b18 (0.1.0)
- **Setup:** Paused (PERSIST-07).
- **Steps:**
  1. Rest the pointer in a screen corner; press ⌃→; press ⌃⌥C.
  2. Press ⌥`.
- **Expected:** Step 1: nothing happens; no window moves. Step 2: Expanse resumes, as PERSIST-09 (it doesn't also zoom out).
- **Automate:** manual: hotkeys.

## PERSIST-09 Resume brings the canvas back as you left it
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Paused after arranging a layout.
- **Steps:**
  1. Menu bar icon › turn the switch back on (or ⌥`, or `open "expanse://resume"`).
- **Expected:** Like a fresh launch from the layout saved at pause: every window goes back to its canvas spot, parked ones to the corner, and the view is where it was. The status reads "On · N windows on the canvas".
- **Check in log:** `resumed`, then `first sync: …`
- **Automate:** manual: real windows.

## PERSIST-10 Hidden and minimised windows also go back on Quit and Pause
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** ac50e01 (0.1.0)
- **Before:** A window out of tracking at quit or pause (app hidden, window minimised, on another Space) had been forgotten. It wasn't put back in the macOS layout and stayed wherever the canvas had it, often parked in the corner.
- **Setup:** Before launching Expanse, note a TextEdit window's macOS position and size. Launch Expanse and hop away so the TextEdit window is parked off-screen.
- **Steps:**
  1. Hide TextEdit from its Dock menu (right-click › Hide).
  2. Pause Expanse (panel switch off).
  3. Show TextEdit (click its Dock icon).
  4. Repeat with a minimised window, and with Quit instead of Pause.
- **Expected:** The window is back at its macOS position and size each time, not in the bottom-right corner.
- **Automate:** manual: real hide, minimise and restore.

## PERSIST-11 A failed first scan never wipes the saved layout
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** ac50e01 (0.1.0)
- **Before:** Before the first successful window scan (Screen Recording not yet in effect, say) Expanse had no windows, and saving wrote an empty layout over layout.json, losing every spot and the crash-recovery originals.
- **Setup:** Expanse has a saved layout. Copy `~/Library/Application Support/Expanse/layout.json` aside.
- **Steps:**
  1. Quit Expanse. Turn off Screen Recording for Expanse in System Settings.
  2. Launch Expanse, close the walkthrough, wait a minute.
  3. Compare layout.json with the copy.
  4. Turn Screen Recording back on and relaunch.
- **Expected:** 3: layout.json is unchanged. 4: windows go back to their saved spots.
- **Automate:** unit: CanvasController.save() returns early until hasSynced (needs a test seam).

## PERSIST-12 Saved spots of windows that aren't open yet are kept
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** ac50e01 (0.1.0)
- **Before:** After the first scan, saved spots for windows that weren't open were dropped, and the next save erased them from layout.json. A window that opened moments later (an app still starting at login) lost its spot.
- **Setup:** Notes open with its window at a recognisable canvas spot.
- **Steps:**
  1. Quit Expanse, then quit Notes.
  2. Launch Expanse, wait 30s, then open Notes.
- **Expected:** Notes' window goes back to its saved canvas spot. Until it does, layout.json keeps its entry (marked `"away": true`).
- **Automate:** unit: LayoutStore.takeMatch(...) and the save of kept entries.
- **Note:** Since 2d65ed9 saved spots are only for windows back within 3 minutes of launch (from an app launched within the last minute) or still out of view; an app opened later goes beside what you're working on. At most 60 kept entries are saved.

## PERSIST-13 Quit or Pause during a hop leaves nothing parked
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** ac50e01 (0.1.0)
- **Before:** Window moves still running in the background (a hop's last step), or a hand-back still due, could land after Quit or Pause had put the windows back, leaving a window parked in the corner.
- **Setup:** Note the macOS layout before Expanse. 10+ windows.
- **Steps:**
  1. Press ⌃→ and straight away run `osascript -e 'quit app "Expanse"'`.
  2. Relaunch. Press ⌃→ and straight away run `open "expanse://pause"`.
- **Expected:** Both times every window ends in its macOS position. None is left in the bottom-right corner. Pause waits for the hop to land first.
- **Automate:** manual: timing against real moves (CanvasController.settleBackgroundMoves).
- **Note:** SIGTERM (`pkill -TERM Expanse`) is handled as Quit.

## PERSIST-14 Windows put back on Quit come back at full size
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** ac50e01 (0.1.0)
- **Before:** Restoring a window resized it first, then moved it. From the parking corner, macOS wouldn't grow it past the screen edge, so it came back smaller than it had been.
- **Setup:** Before Expanse: a TextEdit window at 1200×800. In Expanse: resize it to 600×400 at 100%, then hop away so it's parked.
- **Steps:**
  1. Quit Expanse.
- **Expected:** The window is back at its macOS position at 1200×800.
- **Automate:** manual: depends on macOS's clamping of AX resizes.

## PERSIST-15 Restarting Expanse puts same-titled windows back exactly
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 37a8848 (0.1.3)
- **Before:** The saved layout recognised windows by app and title only, so windows with the same title (a dozen Brave windows on the same page, Finder windows on the same folder) swapped places when Expanse restarted: 42 of 53 moved.
- **Setup:** Six Finder windows on the same folder at different spots.
- **Steps:**
  1. Quit Expanse (Finder keeps running) and launch it again.
  2. Press ⌥`.
- **Expected:** Every Finder window is back at exactly its own spot. layout.json entries carry `id` and `pid`. Launch isn't held up while positions are restored.
- **Automate:** unit: LayoutStore.takeMatch matches window ID and pid first.

## PERSIST-16 A window never takes an open window's saved spot
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 37a8848 (0.1.3)
- **Setup:** As PERSIST-15.
- **Steps:**
  1. Quit Expanse. Close one Finder window, then open a new one on the same folder.
  2. Launch Expanse.
- **Expected:** The five old windows keep their exact spots. The new window takes the closed window's spot (the only free entry with its title), not another open window's.
- **Automate:** unit: LayoutStore.takeMatch(bundleID:title:id:pid:size:open:from:) with `open` keys.

## PERSIST-17 Quitting during the walkthrough leaves the saved layout alone
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** d7da75d (0.1.9)
- **Setup:** A saved layout. Note `stat -f %m ~/Library/Application\ Support/Expanse/layout.json`. Delete `onboardingDone` and reopen Expanse.
- **Steps:**
  1. With the walkthrough still up, quit Expanse (menu bar panel › Quit).
  2. Check layout.json's modification time again.
- **Expected:** The modification time is unchanged, and no window moved at any point.
- **Automate:** unit: AppDelegate.applicationWillTerminate returns before controller.shutdown() when !isOn.
- **Note:** This edge case comes with SETUP-16. Expanse never started, so there is nothing to put back, and a shutdown would overwrite the layout.

## PERSIST-18 A hidden app's windows keep their spots across an Expanse restart
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 37a41d9 (0.1.18), ab759ab (0.1.18)
- **Before:** Spots of windows whose app was hidden (or minimised, or on another Space) were only kept in memory. Restarting Expanse lost them, and when the windows came back they were all brought out at one place and pushed into a column.
- **Setup:** Safari with two windows at distinct, well-separated spots on the canvas.
- **Steps:**
  1. Hide Safari (⌘H).
  2. Quit Expanse (menu bar icon › power button) and open it again.
  3. ⌘-Tab to Safari.
- **Expected:** Both Safari windows come back to their own earlier spots, at their sizes. They are not stacked in one place or in a column.
- **Check in log:** `layout.json` (in `~/Library/Application Support/Expanse/`) lists the hidden windows with `"away": true` while Safari is hidden.
- **Automate:** manual: needs a real hidden app; CanvasController.save (the away list) could be unit-tested once separated.

## PERSIST-19 A minimised window's saved spot isn't given to another window of its app
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 37a41d9 (0.1.18), ab759ab (0.1.18)
- **Before:** At launch, a window of the same app with no saved spot of its own could take the spot saved for a window that was minimised or hidden, so that window had nowhere to come back to.
- **Setup:** TextEdit with window A at a known spot, then A minimised.
- **Steps:**
  1. Quit Expanse.
  2. In TextEdit, open a new document window C (different title).
  3. Open Expanse.
  4. Un-minimise A from the Dock.
- **Expected:** At launch C does not take A's spot (it goes beside what's in view). A comes back to its own earlier spot.
- **Automate:** unit: LayoutStore.takeMatch(… open:from:) skips entries whose window still exists (needs a real window ID for exists()).
- **Note:** Where C goes at launch is from 13a79d4 (windows with no saved spot go beside what's in view).

## PERSIST-20 Earlier layouts: thumbnails and the empty state
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** a727041 (0.1.18), a2d80de (0.1.31)
- **Setup:** First with no snapshots (`~/Library/Application Support/Expanse/Snapshots/` empty), then with some.
- **Steps:**
  1. Open the panel and read Earlier layouts.
  2. Take a snapshot, wait two minutes, reopen the panel.
- **Expected:** Step 1: "Expanse keeps your last few layouts, 15 minutes apart, to go back to. Take a snapshot to keep this one." Step 2: a thumbnail drawn like the minimap (windows that were out of view aren't drawn), labelled "Just now" for its first minute, then "2 minutes ago", with the time below ("9:29 am", or "Yesterday, 9:29 am"); newest on the left, at most three.
- **Automate:** unit: `LayoutStore.snapshots()` (named by Unix time, newest first).

## PERSIST-21 Layout snapshots are taken by themselves, at least 15 minutes apart, newest three kept
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** a727041 (0.1.18), ed54a07 (0.1.31)
- **Setup:** Expanse running with windows on the canvas. `~/Library/Application Support/Expanse/Snapshots/` open in Finder.
- **Steps:**
  1. Move a window; wait a few seconds for the layout to save.
  2. Move another window straight away.
  3. Wait 15 minutes, move a window again.
  4. Repeat until four or more snapshots would have been taken.
- **Expected:** A snapshot file (named for the time, seconds since 1970, `.json`) appears when the layout has changed and the newest snapshot is at least 15 minutes old; step 2 adds none. Only the newest three files are kept. The menu bar panel's Earlier layouts shows them newest first, each with "N minutes ago" (or "Just now") and the time.
- **Automate:** unit: LayoutStore.saveSnapshot / snapshots() (snapshotsKept = 3, snapshotSpacing = 15 min), with the folder pointed at a temp directory.
- **Note:** At HEAD no snapshot is taken with nothing on the canvas (ed54a07), and Take snapshot in the panel takes one at once (a2d80de). The menu item Restore Layout became the panel's Earlier layouts in a2d80de.

## PERSIST-22 Restore Layout puts windows back where a snapshot had them
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** a727041 (0.1.18), 54c2f3d (0.1.18), 154ee21 (0.1.30), a2d80de (0.1.31)
- **Setup:** At least one snapshot (panel › Take snapshot). Then several windows moved and one resized.
- **Steps:**
  1. At 100%, open the menu bar panel.
  2. Under Earlier layouts, click the snapshot.
- **Expected:** The canvas opens zoomed out (fit to everything), and every window the snapshot knows moves back to its spot there, at its chosen size from then.
- **Check in log:** `restored a layout: <n> of <m> windows`
- **Automate:** manual: CanvasController.restoreLayout moves real windows.
- **Note:** At HEAD, a snapshot from this screen size puts windows exactly where it had them (154ee21); one from another screen is fitted (PERSIST-26).

## PERSIST-23 Windows a snapshot doesn't know stay where they are
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** a727041 (0.1.18)
- **Setup:** Take a snapshot. Then open a window of an app that had no windows when the snapshot was taken (it's placed beside your work), and move an older window.
- **Steps:**
  1. Restore the snapshot from the menu bar panel.
- **Expected:** The older window goes back to its snapshot spot. The new window stays where it was; the log counts it out (`restored a layout: <n> of <m> windows` with n < m).
- **Automate:** unit: LayoutStore.takeMatch returns nil for a window with no entry.

## PERSIST-24 A restore can be undone
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** a727041 (0.1.18)
- **Setup:** A snapshot S that differs from the current layout L.
- **Steps:**
  1. Restore S from the menu bar panel.
  2. Reopen the panel.
  3. Click the newest snapshot ("Just now").
- **Expected:** Step 2 shows a new newest snapshot taken just before the restore: layout L. Step 3 puts the windows back as in L.
- **Automate:** manual: depends on real window moves; the snapshot-before-restore order could be unit-tested with restoreLayout separated.

## PERSIST-25 Restore Layout does nothing while Expanse is paused
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** a727041 (0.1.18)
- **Setup:** At least one snapshot. Expanse paused (panel switch off).
- **Steps:**
  1. Open the menu bar panel and try to click a snapshot under Earlier layouts.
  2. `open "expanse://layout?snapshot=0"`
- **Expected:** The thumbnails are greyed out and do nothing; the link changes nothing. Windows stay in the macOS layout.
- **Automate:** manual: guard in CanvasController.restoreLayout (isPaused).

## PERSIST-26 Restoring a snapshot taken on another screen fits it to this one
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 54c2f3d (0.1.18)
- **Setup:** A snapshot taken on the big display. Now on the laptop screen only (or, with debug commands on, `open "expanse://screen?w=1280&h=800"`).
- **Steps:**
  1. Restore that snapshot from the menu bar panel.
- **Expected:** Windows take the snapshot's arrangement fitted to this screen: sizes capped at the screen less 16pt each side, the layout tightened with its gaps kept, nothing overlapping. No window is left at the big display's sizes or spots.
- **Automate:** manual: restoreLayout with fitLayoutToScreen; CanvasController.derive(home:sizes:) can be unit-tested for the fitting.
- **Note:** A snapshot taken on this same screen size puts windows exactly where it had them (154ee21).

## PERSIST-27 Relaunching Expanse on the same screen moves nothing
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** c6c639e (0.1.22)
- **Before:** At launch the layout was re-derived from home spots, so windows could shift even though the screen hadn't changed.
- **Setup:** A layout you've arranged by hand, including windows opened since the last display change.
- **Steps:**
  1. Quit Expanse and open it again on the same display.
- **Expected:** Every window comes back exactly where it was. `layout.json` has `fittedWidth` and `fittedHeight` for the screen it was fitted to.
- **Check in log:** `layout fitted: 0 of <n> windows moved, …`
- **Automate:** manual: relaunch; fitLayoutToScreen with rederiving [] needs extracting.

## PERSIST-28 Apps opened just after Expanse starts take their saved spots
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 29ffe6a (0.1.25), 2d65ed9 (0.1.31)
- **Setup:** Calculator on the canvas at a spot you'll recognise, well away from other windows.
- **Steps:**
  1. Quit Expanse (panel › power button). Then quit Calculator.
  2. Launch Expanse.
  3. Within 3 minutes, open Calculator.
- **Expected:** Windows open at launch go back to their saved spots. Calculator's window, from an app started in Expanse's first 3 minutes (as macOS reopening apps at login would), goes to its saved spot, matched by its title.
- **Automate:** unit: LayoutStore.takeMatch; manual for the timing (restartSpotsUntil).

## PERSIST-29 Restore Layout doesn't give a small window a big window's spot
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 5209c7d (0.1.26)
- **Before:** Restoring a layout matched any window of the same app to the snapshot's entry, so a small dialog or loading box could be given the spot of the app's main window.
- **Setup:** A snapshot (menu bar icon › panel › Take snapshot) that has an app's large main window. Then close that main window and open a small window of the same app (e.g. its Settings window, under a quarter of the main window's size), and note where it is.
- **Steps:**
  1. Menu bar icon › panel › Earlier layouts › click that snapshot (or `open "expanse://layout?snapshot=0"`).
- **Expected:** The small window stays where it was; it isn't moved or resized to the main window's spot. Other windows go back where the snapshot had them.
- **Check in log:** `restored a layout: N of M windows`, with the small window not counted in N.
- **Automate:** unit: `LayoutStore.takeMatch(bundleID:title:id:pid:size:open:from:)` returns nil for a size under a quarter of the only entry's `pw × ph` (or `w × h`).

## PERSIST-30 Restore Layout puts windows exactly where the snapshot had them
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 154ee21 (0.1.30)
- **Before:** Re-homing ran after the restore and reworked the snapshot's home spots from where windows were, shifting some by hundreds of points.
- **Setup:** Several windows on one screen. Menu bar icon › panel › Take snapshot. Then drag several windows to new places on the canvas.
- **Steps:**
  1. Menu bar icon › panel › Earlier layouts › click the snapshot you took (or `open "expanse://layout?snapshot=0"`, the newest).
  2. Compare positions with the snapshot file in `~/Library/Application Support/Expanse/Snapshots/`.
- **Expected:** Every window in the snapshot is back exactly where it was then (the snapshot's x, y), none off by tens or hundreds of points; the view zooms out to show them. The layout it replaced is a snapshot itself, so the restore can be undone.
- **Check in log:** `restored a layout: N of M windows`, and no `re-homed …` line straight after.
- **Automate:** manual: needs real windows (a unit test is planned for when the layout maths moves into its own target; `restoreLayout` skips `rehomeStrays` with `rehoming: false`).

## PERSIST-31 Restore Layout on another screen keeps the snapshot's home spots
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 154ee21 (0.1.30)
- **Before:** On a different screen the restore's home spots were reworked from where windows were, so going back to the snapshot's screen didn't reproduce the snapshot.
- **Setup:** A laptop with an external display. On the external display, take a snapshot; then move several windows.
- **Steps:**
  1. Unplug the external display; wait for it to settle.
  2. Restore that snapshot from Earlier layouts.
  3. Plug the external display back in; wait; zoom out.
- **Expected:** Step 2: the windows are laid out from the snapshot's home spots, tightened to fit the laptop's screen. Step 3: every window is exactly where the snapshot had it on the external display.
- **Check in log:** `restored a layout: N of M windows`.
- **Automate:** manual: needs two screen sizes.
- **Note:** Since 1 Nov (not released yet), found by the end-to-end case after a long run in the VM: back on the big screen, a slow window scan that started just after Expanse grew the big window again still had it at the small screen's size, and that size was taken back. A scan that started within half a second of Expanse resizing a window no longer takes a different size for it; the next scan says how it ended up.

## PERSIST-32 Take snapshot keeps the layout now
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** a2d80de (0.1.31), ed54a07 (0.1.31)
- **Setup:** Expanse running with windows on the canvas; the newest earlier layout is only a minute or two old.
- **Steps:**
  1. Open the panel and click "Take snapshot".
  2. Do it again a few times, a minute apart (move a window in between).
- **Expected:** The panel stays open and a new "Just now" thumbnail appears first, however recent the last one was (the 15-minute spacing doesn't apply). Only the newest three are kept: the oldest goes. A new file appears in `~/Library/Application Support/Expanse/Snapshots/` named for the time. Disabled while paused or before the walkthrough is done.
- **Automate:** unit: CanvasController.takeSnapshot with LayoutStore.saveSnapshot/snapshots (three kept).
- **Note:** Since ed54a07 it does nothing when the canvas has no windows (see PERSIST-41).

## PERSIST-33 A closed window's spot isn't kept
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 2d65ed9 (0.1.31)
- **Before:** A closed window's spot stayed in layout.json (as a window out of view) and in memory for a week; when its app quit, its closed windows' spots went to the app's next windows, so a window opened after reopening the app landed where an old, closed window had been.
- **Setup:** Expanse running more than 3 minutes. Two TextEdit document windows on the canvas, apart from each other.
- **Steps:**
  1. `grep -c com.apple.TextEdit ~/Library/Application\ Support/Expanse/layout.json` (2).
  2. Close one TextEdit window with ⌘W (TextEdit keeps running). Wait a few seconds and run the grep again.
  3. Hop to another app's window. Quit TextEdit, open it again, and press ⌘N.
  4. Edge: in Terminal with two tabs (native tabs, one window each), close the front tab.
- **Expected:** After step 2 the grep says 1: the closed window isn't saved. In step 3 the new window goes in a free spot beside the window you're working on, not at the closed window's old spot. In step 4 the remaining tab stays exactly where the tab group was (a closed window's spot is kept for 10 seconds, only for a tab taking over).
- **Automate:** unit: CanvasController.save filtering out Departed.closed; the 10s prune of recentlyRemoved.

## PERSIST-34 Saved spots are let go 3 minutes after launch
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 2d65ed9 (0.1.31)
- **Before:** Spots from the saved layout stayed for the whole run: an app opened hours after Expanse started still took its old windows' spots instead of opening beside your work.
- **Setup:** As PERSIST-28.
- **Steps:**
  1. Quit Expanse, quit Calculator, launch Expanse.
  2. Wait more than 3 minutes. Then open Calculator.
- **Expected:** About 3 minutes after launch Expanse lets go of saved spots for windows that haven't come back (keeping those whose windows are still open out of view). Calculator then opens beside the window you're in, not at its old spot. The next layout.json no longer lists Calculator.
- **Check in log:** "let go of N saved window spots; M still out of view".
- **Automate:** unit: CanvasController.letGoOfSavedSpots with LayoutStore.isOpen.
- **Note:** Pause and resume starts the 3 minutes again.

## PERSIST-35 A window out of view during a restart of Expanse gets its own spot back, however late
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 2d65ed9 (0.1.31)
- **Before:** Since 0.1.27 a window that was hidden or minimised while Expanse restarted got its saved spot back only within the first minute; shown later, it was placed as a new window.
- **Setup:** Safari window on the canvas at a spot you'll recognise.
- **Steps:**
  1. Hide Safari (⌘H).
  2. Quit Expanse and launch it again.
  3. Wait more than 3 minutes. Click Safari in the Dock.
- **Expected:** Safari's window comes back at its own spot (matched by its window ID in the same Safari process), and the view goes to it. Its spot survives the 3-minute let-go because the window is still open.
- **Automate:** unit: the mayTakeSavedSpot rule in CanvasController.add (savedPool entry with the same id, pid, bundle ID).

## PERSIST-36 Logging out puts windows back in the macOS layout first
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 4045597 (0.1.31)
- **Before:** On logout or restart apps quit with their windows still parked in the bottom-right corner, so they reopened there, and the layout wasn't carried across the restart.
- **Setup:** Expanse running with windows arranged, some parked off screen. For the quick check: a development build with `debugURLCommands` on.
- **Steps:**
  1. `open "expanse://poweroff"` (or log out for real: Apple menu › Log Out).
  2. Look at the windows and open the panel; note layout.json's modification time.
- **Expected:** Expanse pauses at once: every window goes back to where macOS had it (none left in the corner), the panel says "Paused · windows back in the macOS layout", and the layout is saved as it was (no further saves while paused). Already paused, nothing happens.
- **Check in log:** notice "logging out or restarting: windows back to the macOS layout, layout kept for next time", then "paused".
- **Automate:** manual: needs NSWorkspace.willPowerOffNotification and real windows.

## PERSIST-37 Apps that quit during a logout keep their spots
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 4045597 (0.1.31)
- **Before:** A restart quits many apps before Expanse; their spots went as each quit (2d65ed9, same release), so after the restart those windows didn't go back to their spots.
- **Setup:** Development build with `debugURLCommands` on. Calculator on the canvas at a spot you'll recognise.
- **Steps:**
  1. Quit Calculator. Within 30 seconds, `open "expanse://poweroff"`.
  2. Quit Expanse. Look for Calculator in layout.json.
  3. Launch Expanse, and within 3 minutes open Calculator.
  4. Repeat, waiting more than 30 seconds between quitting Calculator and the poweroff link.
- **Expected:** Step 2: layout.json still has Calculator's window, marked `"away" : true`. Step 3: Calculator's window goes back to its spot. Step 4: Calculator isn't in layout.json and opens beside what you're working on.
- **Automate:** unit: CanvasController.appQuit with save (justQuit kept 30s).
- **Note:** Quitting Expanse normally within 30s of an app quitting keeps that app's spots too.

## PERSIST-38 A cancelled logout resumes Expanse after 3 minutes
- **Type:** Feature
- **Area:** PERSIST
- **Commits:** 4045597 (0.1.31)
- **Setup:** Development build with `debugURLCommands` on; Expanse running.
- **Steps:**
  1. `open "expanse://poweroff"`.
  2. Wait 3 minutes without touching Expanse.
  3. Repeat; this time resume yourself after a minute, pause again, and wait past the 3 minutes.
- **Expected:** Step 2: 3 minutes after the logout began, still running, Expanse resumes by itself and windows go back onto the canvas. Step 3: once you've resumed yourself, the timer does nothing, and the pause you made stays.
- **Check in log:** notice "still running: the logout was cancelled, so resuming", then "resumed".
- **Automate:** manual: a 3-minute timer on the running app.

## PERSIST-39 A real restart brings the layout back
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 4045597 (0.1.31), 13a79d4 (0.1.31)
- **Before:** After rebooting the Mac windows didn't go back to where they were: apps quit parked in the corner and the layout wasn't carried across the restart.
- **Setup:** A release build set to open at login; several apps with windows arranged on the canvas, some off screen; "Reopen windows when logging back in" ticked.
- **Steps:**
  1. Apple menu › Restart….
  2. Log in and wait for Expanse and the reopened apps.
- **Expected:** Windows go back to their canvas spots, including those of apps that quit before Expanse and those macOS reopens in the first 3 minutes. Windows the layout has no spot for go beside what's in view (PERSIST-42).
- **Automate:** manual: a real restart.

## PERSIST-40 No layout snapshot of an empty canvas
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** ed54a07 (0.1.31)
- **Before:** At the lock screen no window can be taken on; a snapshot taken then was an empty picture that pushed out an earlier layout worth going back to.
- **Setup:** Three earlier layouts in the panel, the newest at least 15 minutes old.
- **Steps:**
  1. Lock the Mac (⌃⌘Q), wait a minute at the lock screen, unlock. (Or empty the canvas: hide every app.)
  2. Open the panel.
- **Expected:** No new empty thumbnail; the same three earlier layouts are there. layout.json is still saved; only the snapshot is skipped while the canvas has no windows.
- **Automate:** unit: CanvasController.save (no snapshot when windows is empty).

## PERSIST-41 Take snapshot does nothing with nothing on the canvas
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** ed54a07 (0.1.31)
- **Before:** Take snapshot with an empty canvas made an empty thumbnail and pushed out the oldest layout.
- **Setup:** Expanse running; every app hidden so the canvas has no windows; three earlier layouts.
- **Steps:**
  1. Open the panel and click Take snapshot.
- **Expected:** No new thumbnail; the three earlier layouts stay.
- **Automate:** unit: CanvasController.takeSnapshot.

## PERSIST-42 Windows with no saved spot at launch go beside what's in view
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** 13a79d4 (0.1.31)
- **Before:** After a restart the layout came back, but windows it had no spot for (apps opening at login with a window closed before the restart) stayed where macOS put them, on top of the restored layout.
- **Setup:** Expanse running with windows arranged.
- **Steps:**
  1. Quit Expanse.
  2. Open two apps that weren't open when Expanse quit (say Calculator and Chess), their windows in the middle of the screen.
  3. Launch Expanse.
- **Expected:** Saved windows go back to their spots. Each new window moves to a free spot beside the restored window most in view; neither overlaps any window or each other.
- **Check in log:** "placed Calculator[<id>] at {x, y} beside <App>[<id>]: the saved layout has no spot for it".
- **Automate:** unit: CanvasController.placeUnrecognised (free spots beside the anchor, no overlaps).
- **Note:** Only when the saved layout restores at least one window; with no layout (first launch) windows stay where macOS has them.

## PERSIST-43 The layout is saved a second after a change, even while changes keep coming
- **Type:** Bug fix
- **Area:** PERSIST
- **Commits:** unreleased (3 Nov)
- **Before:** Each change put the save off another second. While changes kept coming (a window scan every second or two, as when an app has a window Expanse can't take on yet, which TextEdit has after a Fill), the layout wasn't saved at all, so a size you'd just chosen or a window you'd just moved was lost if Expanse quit then (found by SIZE-11 failing now and then in the VM).
- **Setup:** At 100%, a TextEdit window smaller than the screen.
- **Steps:**
  1. Green button › Fill.
  2. Within a few seconds, quit Expanse from the menu bar panel and open it again.
- **Expected:** The window keeps the Fill size as its chosen size (SIZE-11): `pw`/`ph` in `~/Library/Application Support/Expanse/layout.json` are the filled size a second or so after step 1.
- **Automate:** unit: `scheduleSave` called every 0.4s still saves within a second of the first call; end-to-end: SIZE-11 reads the layout file.
