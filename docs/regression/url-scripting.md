# URL: expanse:// scripting

[All areas](README.md)

## URL-01 expanse://toggle
- **Type:** Feature
- **Area:** URL
- **Commits:** 0cdf466 (0.1.0), c7cba50 (0.1.0)
- **Setup:** At 100%.
- **Steps:**
  1. `open "expanse://toggle"`; then again.
  2. Pause, then `open "expanse://toggle"`.
- **Expected:** As ⌥` (NAV-01): zooms out, then back. While paused it resumes.
- **Check in log:** `url command toggle`
- **Automate:** manual: URL handling.
- **Note:** The scheme was `canvas://` until c7cba50. URL commands do nothing until the walkthrough is done, and one from a web browser runs only after Expanse asks you (47ed782).

## URL-02 expanse://enter
- **Type:** Feature
- **Area:** URL
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** At 100%.
- **Steps:**
  1. `open "expanse://enter"`.
  2. Esc; `open "expanse://enter?zoomOut=0"`.
- **Expected:** Step 1 opens the canvas zoomed out to every window (NAV-01's view); sent again while zoomed out, it re-fits that view. Step 2 opens the canvas at 100%, nothing moved.
- **Automate:** manual: URL handling.

## URL-03 expanse://exit
- **Type:** Feature
- **Area:** URL
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. `open "expanse://exit"`.
- **Expected:** As Esc (NAV-11/NAV-17). At 100% it does nothing.
- **Automate:** manual: URL handling.

## URL-04 expanse://fit
- **Type:** Feature
- **Area:** URL
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out, panned away.
- **Steps:**
  1. `open "expanse://fit"`.
- **Expected:** As the 0 key (NAV-08): every window in view, at up to 100%.
- **Automate:** unit: `fitCamera()`.

## URL-05 expanse://zoom?scale=
- **Type:** Feature
- **Area:** URL
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. `open "expanse://zoom?scale=0.5"`.
  2. `open "expanse://zoom?scale=9"`; `open "expanse://zoom?scale=abc"`.
- **Expected:** Step 1 animates to 50% around the middle of the screen (minimap reads 50%). Step 2: 9 is clamped to 150%; a non-number is ignored.
- **Automate:** unit: `Camera.zoom(to:anchor:)` clamp.

## URL-06 expanse://pan?dx=&dy=
- **Type:** Feature
- **Area:** URL
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Canvas open (zoomed out or `enter?zoomOut=0`).
- **Steps:**
  1. `open "expanse://pan?dx=100&dy=0"`.
  2. Go to 100% with Esc, then `open "expanse://pan?dx=100&dy=0"`.
- **Expected:** Step 1: the canvas content moves 100 screen points right (instantly). Step 2: with the canvas closed it does nothing.
- **Automate:** unit: `Camera.pan(by:)`.

## URL-07 expanse://focus?app=
- **Type:** Feature
- **Area:** URL
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** At 100%, Safari's windows out of view.
- **Steps:**
  1. `open "expanse://focus?app=safari"`.
  2. Zoom out; `open "expanse://focus?app=Safari"`.
  3. `open "expanse://focus?app=NoSuchApp"`.
- **Expected:** Steps 1–2: the front-most Safari window on the canvas is glided to (at 100%) or dived into (zoomed out), centred and focused; the name matches regardless of case. Step 3 does nothing.
- **Automate:** manual: URL handling.
- **Note:** `focus?id=<window ID>` is debug-only.

## URL-08 expanse://restore
- **Type:** Feature
- **Area:** URL
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** As TRACK-09.
- **Steps:**
  1. `open "expanse://restore"`.
- **Expected:** As Restore all windows (TRACK-09).
- **Automate:** manual: URL handling.

## URL-09 expanse://pause and expanse://resume
- **Type:** Feature
- **Area:** URL
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Expanse running.
- **Steps:**
  1. `open "expanse://pause"`; `open "expanse://pause"` again.
  2. `open "expanse://resume"`.
- **Expected:** Step 1 pauses as PERSIST-07; the second pause does nothing. Step 2 resumes as PERSIST-09.
- **Check in log:** `paused`, `resumed`
- **Automate:** manual: URL handling.

## URL-10 expanse://dump writes the layout to the log (debug only)
- **Type:** Feature
- **Area:** URL
- **Commits:** 0cdf466 (0.1.0), ac50e01 (0.1.0), 47ed782 (0.1.33)
- **Setup:** Development build. First with debugURLCommands off, then on (restart Expanse after setting it).
- **Steps:**
  1. `open "expanse://dump"` with the setting off.
  2. Turn it on, restart Expanse, `open "expanse://dump"`.
- **Expected:** Step 1: nothing but `ignored debug URL command dump (debugURLCommands is off)`. Step 2: a `dump viewport=… camera=…@<scale> active=…` line, one `dump <App>[<id>] sc=… ax=… canvas=… parked=… capturing=… pic=…` line per window, `dump unmanaged …` lines for app windows not on the canvas, and last `dump end: <N> windows` (since 31 Oct, so a reader knows it has the lot). A release build ignores the setting.
- **Automate:** manual: URL handling.

## URL-11 expanse://screen pretends the display is another size (debug only)
- **Type:** Feature
- **Area:** URL
- **Commits:** 0cdf466 (0.1.0), ac50e01 (0.1.0)
- **Setup:** Development build with debugURLCommands on.
- **Steps:**
  1. `open "expanse://screen?w=1512&h=982"`.
  2. `open "expanse://screen"`.
- **Expected:** Step 1 behaves as a display change to 1512×982 (DISPLAY-02, SIZE-02), logged as `display changed: {…} -> {1512, <982 less the menu bar>}`. Step 2 goes back to the real display size, the layout returning exactly.
- **Automate:** manual: drives the display-change path without hardware.

## URL-12 expanse://nav hops by direction
- **Type:** Feature
- **Area:** URL
- **Commits:** 3144b09 (0.1.0)
- **Setup:** At 100%, windows in every direction. Run the links from Terminal.
- **Steps:**
  1. `open "expanse://nav?dir=right"`, then `dir=left`, `dir=up`, `dir=down`.
  2. `open "expanse://nav?dir=sideways"`
  3. `open "expanse://nav?dir=right&delay=2"`, then `delay=99`.
- **Expected:** 1: each hops like ⌃+arrow. 2: nothing. 3: the hop happens after 2s; with 99 it waits 10s at most.
- **Automate:** unit: AppDelegate.runURLCommand query parsing (the hop stays manual).
- **Note:** The delay was capped at 0–10s in 47ed782. From a web page, Expanse asks first (47ed782).

## URL-13 expanse://prefer sets a window's chosen size (development builds)
- **Type:** Feature
- **Area:** URL
- **Commits:** 0209aa7 (0.1.0), ac50e01 (0.1.0)
- **Setup:** A development build (`./scripts/build.sh`) with `defaults write com.invignation.expanse debugURLCommands -bool true`. A window ID from `open "expanse://dump"` (in the log).
- **Steps:**
  1. `open "expanse://prefer?id=<id>&w=900&h=700"`
  2. Press ⌥`, then T.
- **Expected:** 1: logged. 2: Tidy Up resizes that window to 900×700.
- **Check in log:** `preferred size <App>[<id>] = {900, 700}`
- **Automate:** unit: CanvasController.setPreferredSize(_:_:).
- **Note:** Ignored in a release, and in a development build with the setting off (SEC-04).

## URL-14 expanse://place moves a window on the canvas (development builds)
- **Type:** Feature
- **Area:** URL
- **Commits:** b6f69cf (0.1.0)
- **Setup:** As URL-13: development build, debug commands on, a window ID.
- **Steps:**
  1. `open "expanse://place?id=<id>&x=0&y=0"`, then press ⌥`.
  2. Back at 100%: `open "expanse://place?id=<id>&x=200&y=100&commit=1"`
- **Expected:** 1: the window's canvas spot is now (0, 0); the real window moves at the next commit. 2: the real windows are re-placed straight away.
- **Automate:** unit: CanvasController.setCanvasOrigin(_:_:commit:).
- **Note:** Ignored in a release and with the setting off (SEC-04).

## URL-15 The app is Expanse and answers expanse:// links
- **Type:** Feature
- **Area:** URL
- **Commits:** c7cba50 (0.1.0)
- **Setup:** Expanse installed and running.
- **Steps:**
  1. `osascript -e 'id of app "Expanse"'`
  2. `open "expanse://toggle"` twice.
- **Expected:** 1: `com.invignation.expanse`. 2: the canvas zooms out, then back.
- **Check in log:** `url command toggle` (subsystem com.invignation.expanse)
- **Automate:** manual: needs Launch Services.

## URL-16 expanse://space switches by name or by position
- **Type:** Feature
- **Area:** URL
- **Commits:** 340f826 (0.1.5)
- **Setup:** Safari full screen, two desktops. Commands are run from Terminal.
- **Steps:**
  1. `open "expanse://space?name=safari"`
  2. `open "expanse://space?name=Desktop%202"`
  3. `open "expanse://space?index=1"`
  4. `open "expanse://space?name=nonesuch"`
- **Expected:** Step 1 switches to Safari's Space (the name is case-insensitive). Step 2 switches to Desktop 2. Step 3 switches to the first Space in Mission Control's order. Step 4 does nothing. Each switch works from 100% or from the canvas, like clicking the tile.
- **Automate:** unit: AppDelegate.runURLCommand("space"), with name matching before index.
- **Note:** Since f310f04, index must be a whole number (see SEC-05); 47ed782 limits it to 0–10000.

## URL-17 expanse://space?name=expanse (or canvas) goes to the canvas's Space
- **Type:** Feature
- **Area:** URL
- **Commits:** 24b54b1 (0.1.6), e9a6f65 (0.1.18)
- **Setup:** Safari in full screen.
- **Steps:**
  1. At 100% in Safari, run `open "expanse://space?name=expanse"` from a launcher hotkey (Raycast, Shortcuts) so you stay on Safari's Space. Terminal would take you to its own Space.
  2. Go back to Safari, press ⌥`, and trigger `expanse://space?name=canvas` the same way.
- **Expected:** At step 1 you switch to the canvas's desktop, back on the window you were last in. At step 2 the switch happens under the canvas and the canvas stays open, as in SPACES-14.
- **Automate:** unit: the "space" branch of AppDelegate.runURLCommand, where "expanse" or "canvas" resolves to controller.canvasDesktop.
- **Note:** `name=canvas` dates from 24b54b1; `name=expanse` was added in e9a6f65.

## URL-18 expanse://focus?id= focuses one particular window (debug)
- **Type:** Feature
- **Area:** URL
- **Commits:** 2885069 (0.1.6), f310f04 (0.1.8)
- **Setup:** A development build with debugURLCommands on. Run `open "expanse://dump"` and read a window ID from a `dump <App>[<id>]` log line.
- **Steps:**
  1. `open "expanse://focus?id=<id>"`
- **Expected:** The view glides to that window (or zooms in to it if the canvas is open) and focuses it.
- **Automate:** unit: the "focus" branch of AppDelegate.runURLCommand.
- **Note:** f310f04 made `id=` need debug commands (see SEC-06). Since 47ed782, debug commands work only in development builds.

## URL-19 expanse://update?install=1 doesn't install anything
- **Type:** Feature
- **Area:** URL
- **Commits:** 0cd0016 (0.1.7)
- **Setup:** Two runs: a release build, then a development build with debugURLCommands on.
- **Steps:**
  1. `open "expanse://update?install=1"`
- **Expected:** In the release build it is ignored: `ignored debug URL command update (debugURLCommands is off)`. In the development build it is accepted (`url command update`) but nothing is checked or installed, because development builds have no updates.
- **Automate:** unit: AppDelegate.debugURLCommands (false for releases) with Updater.check (returns early when !isRelease).
- **Note:** At first (0cd0016) this installed a newer release without asking when debug commands were on. Since 47ed782, debug commands only work in development builds and development builds never update, so the command can't do anything in any build. docs/how-it-works.md says so (3 Nov).

## URL-20 Centre from the menu bar panel and expanse://centre
- **Type:** Feature
- **Area:** URL
- **Commits:** 8c2b732 (0.1.15)
- **Setup:** At 100%, with the focused window off-centre.
- **Steps:**
  1. Open the menu bar panel and click "Centre window" (it shows ⌃ ⌥ C).
  2. Move the window off-centre again and run `open "expanse://centre"`.
  3. Repeat with `open "expanse://center"`.
- **Expected:** Each one centres the window, as in NAV-43.
- **Automate:** unit: AppDelegate.runURLCommand maps "centre" and "center" to centreCurrentWindow.
- **Note:** The menu item "Centre Current Window" became the panel's "Centre window" tile in a2d80de.

## URL-21 expanse://appearance switches Expanse between light and dark
- **Type:** Feature
- **Area:** URL
- **Commits:** 021cb8b (0.1.18)
- **Setup:** Debug commands on (a development build with `defaults write com.invignation.expanse debugURLCommands -bool true`). Mac in Light appearance. Zoomed out so the minimap and Spaces panels show.
- **Steps:**
  1. `open "expanse://appearance?mode=dark"`
  2. `open "expanse://appearance?mode=light"`
  3. `open "expanse://appearance"` (no mode, or any other value)
- **Expected:** Step 1: Expanse's own panels (minimap, Spaces, menu bar panel) turn dark while the Mac stays light. Step 2: they turn light. Step 3: they follow the Mac's appearance again. Other apps never change.
- **Check in log:** `url command appearance`
- **Automate:** manual: appearance is applied by AppKit (NSApp.appearance).
- **Note:** Made debug-only in bf5aace (see SEC-07).

## URL-22 expanse://layout?snapshot=N restores a snapshot from a script
- **Type:** Feature
- **Area:** URL
- **Commits:** a727041 (0.1.18), 54c2f3d (0.1.18)
- **Setup:** Three snapshots.
- **Steps:**
  1. `open "expanse://layout?snapshot=2"`
  2. `open "expanse://layout"`
  3. `open "expanse://layout?snapshot=7"` and `open "expanse://layout?snapshot=abc"`
- **Expected:** Step 1 restores the oldest snapshot, as PERSIST-22. Step 2 restores the newest (no number means 0). Step 3 does nothing.
- **Check in log:** `url command layout`, then `restored a layout: …` for steps 1 and 2 only.
- **Automate:** manual: AppDelegate.runURLCommand; the index parsing (whole number 0…10000) could be unit-tested.
- **Note:** Non-numbers and out-of-range numbers are rejected by the index check from 47ed782.

## URL-23 expanse://place moves a window's home spot with it
- **Type:** Feature
- **Area:** URL
- **Commits:** eb224e7 (0.1.21)
- **Setup:** Debug commands on (a development build with `defaults write com.invignation.expanse debugURLCommands -bool true`). A window ID from `open "expanse://dump"` (`dump <App>[<id>] …`). On a smaller screen (`open "expanse://screen?w=1280&h=800"`).
- **Steps:**
  1. `open "expanse://place?id=<id>&x=<x>&y=<y>&commit=1"` to an empty spot beside another window.
  2. `open "expanse://screen"` (back to the real screen size).
- **Expected:** The window keeps its new place relative to its neighbours on the bigger screen, as if you'd dragged it there. It doesn't jump back to its old spot.
- **Automate:** manual: setCanvasOrigin calls noteUserMove; homeSpot needs extracting for a unit test.

## URL-24 expanse://logging and expanse://copylogs
- **Type:** Feature
- **Area:** URL
- **Commits:** 00fbfc7 (0.1.23)
- **Setup:** Debug commands on (a development build with `defaults write com.invignation.expanse debugURLCommands -bool true`).
- **Steps:**
  1. `open "expanse://logging?on=1"`
  2. `open "expanse://copylogs"`
  3. `open "expanse://logging?on=0"`
- **Expected:** Step 1 turns Detailed Logging on (as SUPPORT-04, without the toast). Step 2 copies the report as SUPPORT-05. Step 3 turns it off. With debug commands off all three are ignored (`ignored debug URL command …`).
- **Automate:** manual: AppDelegate.runURLCommand.

## URL-25 expanse://menu opens the panel
- **Type:** Feature
- **Area:** URL
- **Commits:** a2d80de (0.1.31)
- **Setup:** Expanse running (walkthrough done).
- **Steps:**
  1. In Terminal: `open "expanse://menu"`.
- **Expected:** The menu bar panel opens under the icon, as if you'd clicked it. Before the walkthrough is done the link is ignored.
- **Check in log:** "url command menu".
- **Automate:** manual: needs the status item.
- **Note:** Since 47ed782 a web page's `menu` link runs without Expanse asking (see SEC-16).

## URL-26 expanse://snapshot takes a snapshot (development builds)
- **Type:** Feature
- **Area:** URL
- **Commits:** a2d80de (0.1.31)
- **Setup:** A development build; `defaults write com.invignation.expanse debugURLCommands -bool true`; windows on the canvas.
- **Steps:**
  1. `open "expanse://snapshot"`, then open the panel.
- **Expected:** Same as Take snapshot: a new "Just now" thumbnail first, at most three kept. Without the setting, or in a release build, it's ignored.
- **Check in log:** "url command snapshot"; when off, "ignored debug URL command snapshot (debugURLCommands is off)".
- **Automate:** manual: URL dispatch in the running app.
- **Note:** Release builds ignore debug commands since 47ed782 (see SEC-04); with nothing on the canvas it does nothing since ed54a07.

## URL-27 expanse://poweroff runs the logout handling (development builds)
- **Type:** Feature
- **Area:** URL
- **Commits:** 4045597 (0.1.31), ed54a07 (0.1.31)
- **Setup:** Development build with `debugURLCommands` on.
- **Steps:**
  1. `open "expanse://poweroff"`.
  2. Turn the setting off and try again.
- **Expected:** Step 1 posts macOS's own will-power-off notification, so it goes through the same path a real logout does: paused, windows back in the macOS layout, layout kept, and resumed 3 minutes later (PERSIST-36, PERSIST-38). Step 2: ignored.
- **Check in log:** "url command poweroff", then "logging out or restarting: …"; when off, "ignored debug URL command poweroff (debugURLCommands is off)".
- **Automate:** manual: URL dispatch and the workspace notification.
- **Note:** In 4045597 the link called the handler directly; ed54a07 made it post the real notification. Release builds ignore it since 47ed782.

## URL-28 expanse://fit and expanse://zoom at 100% leave the view alone
- **Type:** Bug fix
- **Area:** URL
- **Commits:** unreleased (3 Nov)
- **Before:** With the canvas closed, `fit` and `zoom?scale=` moved the view anyway, out from under your windows. The canvas opens where the view was left (scale aside), so the next time it opened it didn't line up with them, and leaving it moved your windows (found writing URL-04 and URL-05).
- **Setup:** At 100%, the canvas closed.
- **Steps:**
  1. `open "expanse://fit"`, then `open "expanse://zoom?scale=0.5"`.
  2. ⌥`, then Esc.
- **Expected:** Step 1: nothing happens, as `pan` at 100%. Step 2: every window is where it was.
- **Automate:** unit: `runURLCommand` for `fit` and `zoom` with the canvas closed starts no animation and leaves the camera.
