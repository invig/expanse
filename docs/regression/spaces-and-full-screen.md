# SPACES: Full-screen apps and Spaces

[All areas](README.md)

## SPACES-01 A full-screen window is never taken onto the canvas
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** 05457cb (0.1.5)
- **Before:** On a full-screen app's Space, a window scan saw none of the canvas's windows and adopted the full-screen one. It was parked, resized and glided to, and the canvas's other windows could be dropped.
- **Setup:** At 100%, several windows on the canvas, including a Safari window.
- **Steps:**
  1. Put the Safari window in full screen (green button).
  2. Stay on its Space for 30 seconds.
  3. Press ⌥` to open the canvas over it, then press Esc.
- **Expected:** Safari stays full screen and untouched: not resized, parked, moved or glided to, and not taken on as a new window at a new spot. The canvas opened over it still has every other window in its usual place; none has been dropped. Safari's own spot is kept for when it comes back (SPACES-22).
- **Automate:** unit: CanvasController.sync. Windows in Spaces.fullScreenWindows() are filtered out of the scan, and a scan taken on a full-screen Space isn't applied (see also SPACES-18).

## SPACES-02 Zoomed out, a Spaces panel beside the minimap shows each Space
- **Type:** Feature
- **Area:** SPACES
- **Commits:** 05457cb (0.1.5), 340f826 (0.1.5), 19a09e4 (0.1.5), 24b54b1 (0.1.6), e9a6f65 (0.1.18), 058fc62 (0.1.29)
- **Setup:** Mission Control has two desktops and one full-screen app (Safari). You are on the canvas's desktop.
- **Steps:**
  1. Press ⌥` to zoom out.
  2. Hover over each tile.
- **Expected:** To the left of the minimap, a panel headed "Spaces" has one tile per Space on the main display, in Mission Control's order. The canvas's own desktop is labelled "Expanse". The other desktop is "Desktop 2", showing the desktop picture (a plain grey tile when the Desktop picture background switch is off). The full-screen app shows its icon and name ("Safari", or e.g. "Safari & Notes" for split view). The current Space is ringed in the accent colour and named in bold, and a hovered tile gets a quiet ring.
- **Automate:** unit: Spaces.list() parsing a CGSCopyManagedDisplaySpaces dictionary. Type 0 is a desktop, numbered when there's more than one; type 4 is named from TileSpaces' appName values joined by " & ".
- **Note:** The canvas's desktop tile was labelled "Desktop" here, "Canvas" from 24b54b1, and "Expanse" since e9a6f65.

## SPACES-03 No Spaces panel when there's only one Space
- **Type:** Feature
- **Area:** SPACES
- **Commits:** 05457cb (0.1.5)
- **Setup:** One desktop and no full-screen apps.
- **Steps:**
  1. Press ⌥`.
- **Expected:** Only the minimap shows; there is no Spaces panel.
- **Automate:** unit: SpacesBar.update(spaces:active:wallpaper:) sets isHidden when spaces.count < 2.

## SPACES-04 A desktop with nothing on it says so
- **Type:** Feature
- **Area:** SPACES
- **Commits:** 05457cb (0.1.5)
- **Setup:** Desktop 2 exists with no windows on it.
- **Steps:**
  1. Zoom out and click the Desktop 2 tile.
- **Expected:** A toast reads "Nothing open on Desktop 2 to switch to", and the canvas stays open.
- **Automate:** unit: Spaces.someWindow(on:) returns nil for an empty Space.

## SPACES-05 ⌥` over a full-screen app opens the canvas there
- **Type:** Feature
- **Area:** SPACES
- **Commits:** 05457cb (0.1.5)
- **Setup:** Safari in full screen, showing.
- **Steps:**
  1. Press ⌥` (or rest the pointer in Expanse's hot corner).
- **Expected:** The canvas opens zoomed out over the full-screen app, with the canvas's windows, the minimap and the Spaces panel; Safari's tile is ringed as current. SPACES-12 and SPACES-13 cover picking a window and leaving.
- **Automate:** manual: needs real Spaces.

## SPACES-06 Clicking a full-screen app's tile actually switches to it
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** 340f826 (0.1.5)
- **Before:** Clicking the tile brought the app forward but left you on your desktop. macOS only follows a window that becomes key, and Accessibility can't see windows on other Spaces.
- **Setup:** Safari in full screen on its own Space; you are on the canvas's desktop at 100%.
- **Steps:**
  1. Press ⌥` to zoom out.
  2. Click Safari's tile.
- **Expected:** The canvas returns to 100%, macOS shows Safari's full-screen Space, and Safari's window is key: typing goes into it.
- **Check in log:** `switching from Space <id> to Safari (<id>), instantly`, `Space switch: window server focus true, window found`, `Space switch done: on <id>`
- **Automate:** manual: needs the window server and real Spaces.

## SPACES-07 The Spaces panel works at 100% too
- **Type:** Feature
- **Area:** SPACES
- **Commits:** 340f826 (0.1.5)
- **Setup:** At 100% on the canvas's desktop, with no window covering the bottom-right of the screen, so the minimap and Spaces panel show on the desktop. Safari is full screen elsewhere.
- **Steps:**
  1. Click Safari's tile in the Spaces panel.
- **Expected:** macOS switches to Safari's Space with Safari key, as in SPACES-06.
- **Automate:** manual.

## SPACES-08 Switching to another desktop from the Spaces panel
- **Type:** Feature
- **Area:** SPACES
- **Commits:** 340f826 (0.1.5)
- **Setup:** Desktop 2 has a TextEdit window on it.
- **Steps:**
  1. Zoom out and click the Desktop 2 tile.
- **Expected:** The canvas returns to 100%, macOS switches to Desktop 2, and a window there (the front-most one) is in front with the keyboard.
- **Check in log:** `switching from Space … to Desktop 2 (…)` and `Space switch done`
- **Automate:** manual.

## SPACES-09 Space switches are instant
- **Type:** Feature
- **Area:** SPACES
- **Commits:** 19a09e4 (0.1.5)
- **Setup:** The pointer is on the main display, and Safari is full screen.
- **Steps:**
  1. At 100%, click Safari's tile in the Spaces panel.
  2. From Safari, press ⌥` and click the Expanse tile.
- **Expected:** macOS's sliding animation doesn't play: the new Space appears at once. From the canvas, the switch happens under the canvas, which stays put, so nothing slides.
- **Check in log:** `switching from Space … to Safari (…), instantly`
- **Automate:** manual: synthetic Dock swipe events.

## SPACES-10 With the pointer on another display, the switch still happens the slow way
- **Type:** Feature
- **Area:** SPACES
- **Commits:** 19a09e4 (0.1.5)
- **Setup:** A second display is connected and the pointer rests on it. Safari is full screen on the main display.
- **Steps:**
  1. From Terminal, `open "expanse://space?name=Safari"`.
- **Expected:** macOS still switches the main display to Safari's Space, with its usual slide.
- **Check in log:** `switching from Space … to Safari (…)` without `, instantly`, then `Space switch done`
- **Automate:** unit: SpaceSwipe.go(to:) returns false and posts nothing when the pointer is outside the main screen's frame.

## SPACES-11 Instant switching follows the Natural scrolling setting (macOS 27)
- **Type:** Feature
- **Area:** SPACES
- **Commits:** 19a09e4 (0.1.5)
- **Setup:** macOS 27, with three Spaces. Run once with System Settings › Trackpad › Natural scrolling on and once with it off.
- **Steps:**
  1. Zoom out and click a tile to the right of the current Space.
  2. Zoom out and click a tile to the left.
- **Expected:** Both runs land instantly on the Space you clicked, never one in the opposite direction.
- **Automate:** unit: the sign SpaceSwipe.modernEvents takes from com.apple.swipescrolldirection.

## SPACES-12 Picking a window from the canvas over a full-screen app
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** 19a09e4 (0.1.5), 24b54b1 (0.1.6)
- **Before:** Picking a window dropped you back into the full-screen app and then slid across to the desktop afterwards.
- **Setup:** Safari in full screen; open the canvas over it with ⌥`.
- **Steps:**
  1. Click a window on the canvas, for example a Notes window.
- **Expected:** The canvas's desktop is switched to under the canvas at once, with no slide out of Safari. The canvas then zooms into the picked window at 100%, and that window has the keyboard.
- **Check in log:** `switched to the canvas's desktop under the canvas`
- **Automate:** manual.
- **Note:** 24b54b1 restored the zoom-in, which had been lost because macOS stopped drawing the canvas after the switch.

## SPACES-13 Leaving the canvas without picking goes back to the full-screen app
- **Type:** Feature
- **Area:** SPACES
- **Commits:** 19a09e4 (0.1.5)
- **Setup:** Safari in full screen; open the canvas over it with ⌥`.
- **Steps:**
  1. Press Esc (or ⌥` again).
- **Expected:** The canvas closes and you are in Safari's full-screen Space with Safari key, not on the desktop.
- **Check in log:** `Space switch: window server focus …` then `Space switch done: on <Safari's Space>`
- **Automate:** manual.

## SPACES-14 The Expanse tile, from over a full-screen app, keeps you on the canvas
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** 24b54b1 (0.1.6)
- **Before:** From the canvas opened over a full-screen app, the canvas's own desktop tile left you on the plain desktop at 100% instead of on the canvas.
- **Setup:** Safari in full screen; open the canvas over it with ⌥`.
- **Steps:**
  1. Click the "Expanse" tile.
  2. Press 0, then click a window.
- **Expected:** At step 1 macOS switches to the canvas's desktop instantly and the canvas stays open, zoomed out, with the Expanse tile now ringed. At step 2 the keys work (0 fits everything) and clicking zooms into the window.
- **Check in log:** `back to the canvas's Space, staying on the canvas`
- **Automate:** manual.
- **Note:** The tile was labelled "Canvas" in this commit and "Expanse" since e9a6f65.

## SPACES-15 The canvas comes along to the desktop and keeps the keyboard
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** 24b54b1 (0.1.6)
- **Before:** After a switch away from a full-screen app's Space, macOS stopped drawing the canvas window (while still listing it as on screen) and gave the keyboard to an app on the new Space, so the plain desktop showed.
- **Setup:** Safari in full screen; open the canvas over it with ⌥`.
- **Steps:**
  1. Swipe between Spaces on the trackpad (three or four fingers, per Trackpad settings) to the canvas's desktop.
  2. Press Esc.
- **Expected:** At step 1 the canvas is drawn again on the desktop, still zoomed out, and has the keyboard. At step 2 Esc closes it.
- **Automate:** manual.

## SPACES-16 The window you picked keeps the keyboard after a Space switch
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** 2885069 (0.1.6)
- **Before:** Picking a window from the canvas over a full-screen app switched to the canvas's desktop. On arrival, macOS activated the app in front, and the app put its previous window back in focus a moment after Expanse focused the picked one. Expanse followed that and glided back to the other window.
- **Setup:** Two TextEdit windows, A and B, far apart on the canvas, with B the one used last. Safari in full screen; open the canvas over it.
- **Steps:**
  1. Click window A, then type a few letters.
- **Expected:** The view lands on A and A keeps focus; the letters go into A, and there is no glide back to B. This happens only once: if the app moves focus again, it wins. If you click or type within that first second, nothing is put back.
- **Check in log:** `TextEdit[<B>] took focus just after [<A>] was picked; giving it back`
- **Automate:** unit: CanvasController.focusSettled. It reasserts lastFocusRequest once when the new focus is another window of the same app, under 1 s later, with no click or key since (inputSince).

## SPACES-17 The tile for the Space you're on doesn't run a switch
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** f310f04 (0.1.8), 1e85357 (0.1.11)
- **Before:** Clicking the tile of the Space you were already on ran a full switch, moving focus to the last window. From the canvas over a full-screen app, its own tile ran a switch instead of just leaving.
- **Setup:** Safari full screen on its own Space, and the Spaces panel visible.
- **Steps:**
  1. At 100% on the canvas's desktop, click the Expanse tile.
  2. Zoom out and click the Expanse tile.
  3. Go to Safari, press ⌥`, and click Safari's tile.
- **Expected:** Step 1 does nothing: no switch, no glide, no focus change. Step 2 returns the canvas to 100%. Step 3 leaves the canvas, back to Safari full screen.
- **Automate:** unit: the start of CanvasController.switchToSpace. When space.id equals Spaces.list().active, it exits if active and otherwise returns.
- **Note:** f310f04 covered a desktop at 100%, and 1e85357 any current Space. Zoomed out on the canvas's own desktop, step 2 returning to 100% is from 058fc62.

## SPACES-18 No window scans while a full-screen app's Space is showing
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** f310f04 (0.1.8)
- **Before:** On a full-screen Space, Expanse still asked ScreenCaptureKit and the window server for every window at each scan, only to throw the answer away.
- **Setup:** Safari in full screen.
- **Steps:**
  1. Stay on Safari's Space for a minute, switching tabs and moving the pointer.
  2. Go back to the canvas's desktop.
- **Expected:** While on the full-screen Space, Expanse scans nothing; only the Spaces panel is refreshed. On return, the canvas is exactly as you left it, and scanning resumes there.
- **Check in log:** none of `slow: window scan took …`, `window scan got no answer …`, `not on the canvas: …` or `placed new window …` while on Safari's Space.
- **Automate:** unit: CanvasController.sync returns early when Spaces.inFullScreenSpace. It needs a seam for Spaces.

## SPACES-19 Instant switch with the pointer resting on the top edge
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** f310f04 (0.1.8)
- **Before:** With the pointer resting on the screen's top edge (as it does in a top hot corner), it counted as off the main display. The instant swipe wasn't made, and macOS slid across slowly.
- **Setup:** Expanse's corner is Top Right, and Safari is full screen.
- **Steps:**
  1. Flick the pointer into the top-right corner to open the canvas over Safari, and leave it there.
  2. Press Return to dive into the last window.
- **Expected:** The switch to the canvas's desktop happens instantly under the canvas, then the zoom-in.
- **Check in log:** `switched to the canvas's desktop under the canvas`
- **Automate:** unit: SpaceSwipe.go(to:). Its frame test includes the maxX and maxY edges.

## SPACES-20 The picked window keeps the keyboard when the Space change arrives late
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** f310f04 (0.1.8)
- **Before:** When you picked a window from the canvas over a full-screen app, the "Space changed" notice could arrive while the canvas was already leaving. canvasFollowsSpace (from 24b54b1) had no check for that, so it could bring the canvas back to the front and take the keyboard from the window you had picked.
- **Setup:** Safari in full screen; open the canvas over it.
- **Steps:**
  1. Click a TextEdit window, then type straight away.
- **Expected:** The canvas leaves, and the typing goes into the TextEdit window. The canvas isn't redrawn or brought back to the front.
- **Automate:** unit: CanvasController.canvasFollowsSpace guards on !gliding.

## SPACES-21 Other windows stay put when one goes full screen
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** 1e85357 (0.1.11), 8dcba7d (0.1.12)
- **Before:** As one window went full screen or came back, Chromium browsers fitted their other windows onto the screen. Expanse followed those moves, dragging the windows across the canvas, and could take on sizes the browser had shrunk.
- **Setup:** At 100%, with Brave or Chrome having three windows on the canvas, two of them off screen. Zoom out and note the layout.
- **Steps:**
  1. Put the on-screen browser window in full screen (⌃⌘F) and wait a few seconds.
  2. Leave full screen.
  3. Zoom out.
- **Expected:** The browser's other windows are at exactly their earlier canvas spots and sizes. Any it moved or shrank were put back about half a second after the moves stopped, while out of sight behind the full-screen window.
- **Check in log:** `Brave Browser[<id>] moved as a full-screen window came or went; putting it back`, then `putting back <n> windows moved as a full-screen window came or went`
- **Automate:** unit: CanvasController.movedByFullScreen and putBackAfterFullScreenSoon, given the window-settle times.
- **Note:** 8dcba7d made this ignore display changes (DISPLAY-15).

## SPACES-22 A window back from full screen gets the view
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** 1e85357 (0.1.11)
- **Before:** A window coming back from full screen returned to its canvas spot, which could be off screen, while having the keyboard. You were typing into a window you couldn't see.
- **Setup:** At 100%, window A (Safari) on the canvas.
- **Steps:**
  1. Put A in full screen.
  2. Swipe back to the canvas's desktop on the trackpad, and hop away with ⌃→ so A's spot is off screen.
  3. Zoom out, click A's tile in the Spaces panel, and leave full screen with ⌃⌘F.
  4. Repeat with a YouTube video's full-screen button in Safari or Chrome.
- **Expected:** After leaving full screen, A is at its own canvas spot (not where macOS set it down), the view glides to it, and it has the keyboard.
- **Check in log:** `Safari[<id>] back from full screen`
- **Automate:** manual.
- **Note:** f8407c7 later stopped a scan in that moment from taking where macOS set the window down as its new spot.

## SPACES-23 A window back from full screen keeps its spot
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** f8407c7 (0.1.24)
- **Before:** Leaving full screen, a window got its old spot back, but a scan just before Expanse moved it could find it where macOS set it down and keep that as its spot (seen with Calendar).
- **Setup:** A Calendar window at a known spot on the canvas, neighbours around it.
- **Steps:**
  1. Click Calendar's green button to go full screen; wait.
  2. Leave full screen (green button or ⌃⌘F).
  3. Wait 10s, zoom out.
- **Expected:** Calendar ends exactly at its old canvas spot and stays there; it's not left where macOS set it down.
- **Check in log:** `Calendar[<id>] moved as a full-screen window came or went; putting it back`
- **Automate:** manual: needs a real full-screen transition.
- **Note:** Since 1 Nov (not released yet) windows macOS sets down elsewhere as a full-screen window comes back (the one coming back too, and ones half off the screen) are put back even when only a scan seconds later finds them, and the put-back happens after a glide that was running (before, its commit had already been worked out, and the next scan followed them).


## SPACES-24 Clicking Expanse's own Space tile goes back to 100%
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** 058fc62 (0.1.29)
- **Before:** On the desktop's own Space, clicking the canvas's Space tile while zoomed out did nothing; it only went back from over a full-screen app.
- **Setup:** On the desktop Space (no full-screen app in front). The Spaces panel shows next to the minimap, with the current tile named "Expanse".
- **Steps:**
  1. Zoom out (⌥`).
  2. Click the "Expanse" tile.
  3. At 100%, click the "Expanse" tile again.
  4. Zoom out and run `open "expanse://space?name=Expanse"`.
- **Expected:** Steps 2 and 4: back to 100%, as leaving the canvas does (the view you left, unless you panned or zoomed). Step 3: nothing happens, and focus doesn't move.
- **Automate:** manual: needs the Spaces list (`switchToSpace` with the active Space).

## SPACES-25 The minimap and Spaces panel are back at 100% after a full-screen app's Space
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** 4df566d (0.1.37)
- **Before:** Back on the desktop from a full-screen app's Space, with another app in front, macOS could stop drawing Expanse's window at 100% while still listing it on screen: the minimap, the Spaces panel and parked windows' pictures vanished, and clicks there went to the desktop picture, until the canvas next opened. A glide to the window you came back to showed it again, so it was seen only without one: in the 20s after a display change (when Expanse doesn't follow focus), or with the view already on that window (SPACES-07 lost its click now and then).
- **Setup:** At 100% on the canvas's desktop, with the minimap and Spaces panel showing in the bottom-right. Safari is full screen on a Space of its own.
- **Steps:**
  1. Click a window of another app (TextEdit, say) on the desktop.
  2. Click Safari's tile in the Spaces panel.
  3. Come back to the desktop (its tile, or a swipe).
  4. Click between the tiles in the Spaces panel, then click Safari's tile again.
- **Expected:** At step 3 the minimap and Spaces panel are drawn on the desktop. At step 4 the clicks reach Expanse (`click at 100%` in the log), and the second one switches to Safari.
- **Automate:** manual: end-to-end in the VM (SPACES-25), the rule in a unit test.

## SPACES-26 The Expanse tile is the desktop's, with a window of the canvas full screen
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** unreleased (3 Nov)
- **Before:** The canvas's desktop was taken to be the Space of its front-most window. A window that goes full screen keeps its spot on the canvas, so with it front-most that was its full-screen Space: the Spaces panel called that Space "Expanse", `expanse://space?name=expanse` went there, and leaving the canvas opened over a full-screen app switched to it rather than the desktop (found writing the SPACES cases).
- **Setup:** At 100% on the desktop, with a window of the canvas in front.
- **Steps:**
  1. Make that window full screen (green button), then ⌥` from its Space.
  2. Look at the Spaces panel; then press Esc.
- **Expected:** Step 2: the "Expanse" tile is the desktop, and the full-screen window has a tile of its own with its app's name. Esc goes back to the full-screen app (SPACES-15).
- **Automate:** unit: `canvasDesktop(front:desktops:spacesOf:)` skips windows whose Space isn't a desktop.

## SPACES-27 Over a full-screen app the canvas keeps the desktop picture, and covers the app's top edge
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** 43d0748 (0.1.43)
- **Before:** Opening the canvas over a full-screen app took a fresh picture of "the desktop", but what macOS draws on that Space is a black backdrop. The canvas and the Expanse tile turned black. The canvas's window stops at the menu bar, which macOS hides there, so the app's top edge (Brave's tabs) stayed showing above the canvas and took clicks.
- **Setup:** Desktop picture background on. Brave or Safari in full screen, showing.
- **Steps:**
  1. Press ⌥`.
  2. Click along the top of the screen.
  3. Move the pointer to the top edge and wait.
  4. Press Esc.
- **Expected:** Step 1: the canvas shows the desktop picture, right up to the top of the screen, and so does the Expanse tile. The app's top edge doesn't show. Step 2: nothing happens. Step 3: macOS's menu bar comes down over the strip. Step 4: back in the full-screen app, with its top edge showing again.
- **Automate:** unit: `takeWallpaper` asks for no capture on that Space and keeps the picture; `menuBarStripFrame`; `MenuBarStrip`. End-to-end: the strip comes and goes with the canvas, opened twice (a window macOS has shown once can stay undrawn on that Space).

## SPACES-28 The desktop picture is only taken of a desktop at rest
- **Type:** Bug fix
- **Area:** SPACES
- **Commits:** 43d0748 (0.1.43)
- **Before:** The picture was asked for the moment the Space changed, while macOS was still sliding the desktop's windows across the screen (one Mac reported Finder's at x = −554, then −2034), and a window of the screen's size counted wherever it was. The canvas could show that picture until it next opened.
- **Setup:** Desktop picture background on. A full-screen app on another Space.
- **Steps:**
  1. Swipe from the full-screen app to the desktop, and press ⌥` straight away.
  2. Open the canvas over the full-screen app, click the desktop's tile, and look at the picture a second later.
- **Expected:** The canvas's desktop is where the real one is, icons whole, at both steps.
- **Automate:** unit: `Wallpaper.desktopState` with frames recorded from a real slide; `takeWallpaper` waits out `spaceSettleTime`, asks again while the desktop moves, gives up keeping the last picture, and drops older asks.
- **Note:** Icons cut off along the right edge of the canvas's picture were seen once on a Mac on 6 Nov, with the icons in their right place, which a mid-slide picture wouldn't explain on its own. Not reproduced, in a VM or on that Mac. This may not be the whole cause: if it comes back, note whether closing and reopening the canvas clears it.

