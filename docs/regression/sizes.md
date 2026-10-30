# SIZE: Window sizes

[All areas](README.md)

## SIZE-01 Resizing a window yourself keeps the new size
- **Type:** Feature
- **Area:** SIZE
- **Commits:** 0cdf466 (0.1.0), 0209aa7 (0.1.0), 1a673fe (0.1.28)
- **Setup:** At 100%.
- **Steps:**
  1. Drag a window's edge to make it noticeably bigger.
  2. Zoom out, then Esc; quit and relaunch Expanse.
- **Expected:** The canvas picture takes the new size at once, and it's the window's chosen size from then on: it keeps it across zooming, display changes back to this screen, and relaunching (`pw`/`ph` in layout.json match).
- **Automate:** unit: `CanvasController.adoptSize(_:_:fromUser:)` sets `preferredSize` only for your resizes | manual otherwise.
- **Note:** Resizes by macOS, apps or Expanse itself don't change the chosen size (0209aa7); Fill, Moom or a keyboard shortcut do (1a673fe).

## SIZE-02 Windows shrink to fit a smaller screen and grow back
- **Type:** Feature
- **Area:** SIZE
- **Commits:** 0cdf466 (0.1.0), 29b2a32 (0.1.0), c6c639e (0.1.22)
- **Setup:** On a large screen, a window sized wider and taller than the smaller screen you'll switch to (e.g. 2000×1200 for a 1512×982 laptop). Development build with `defaults write com.invignation.expanse debugURLCommands -bool true` and Expanse restarted (or use a real resolution change instead).
- **Steps:**
  1. `open "expanse://screen?w=1512&h=982"` (or switch to the smaller resolution).
  2. Go to that window (click it zoomed out).
  3. `open "expanse://screen"` (back to the real size).
- **Expected:** Step 1–2: the window is resized to the screen less a 16pt margin all round (in each direction that doesn't fit; a direction that fits keeps its size), and the layout tightens around it. Step 3: it grows back to its chosen size and the layout returns exactly to what it was.
- **Check in log:** `fit size <App>[<id>] {2000, 1200} -> {…}`
- **Automate:** unit: `CanvasController.cap(_:to:)` (fits as is, else the screen less 32pt).
- **Note:** The first commit shrank a window only as you focused it; now fitting happens on every display change too.

## SIZE-03 Window sizes survive quitting and relaunching Expanse
- **Type:** Feature
- **Area:** SIZE
- **Commits:** fbdc277 (0.1.0)
- **Setup:** A TextEdit window about 600×400 when Expanse first took it on.
- **Steps:**
  1. At 100%, drag its corner to about 1100×800.
  2. Quit Expanse (panel › power button).
  3. Launch Expanse.
- **Expected:** 2: the window goes back to 600×400 at its macOS spot. 3: it's 1100×800 again, at its canvas spot.
- **Check in log:** `restore size TextEdit[<id>] {600, 400} -> {1100, 800}`
- **Automate:** unit: SavedLayout.Window w/h survive LayoutStore save and load (the real resize stays manual).

## SIZE-04 A window growing near the screen's edge isn't cut short
- **Type:** Bug fix
- **Area:** SIZE
- **Commits:** fbdc277 (0.1.0)
- **Before:** macOS won't grow a window past the screen edge from where it sits, so a window near the bottom right asked to grow came out smaller than asked.
- **Setup:** Expanse quit. A TextEdit window about 500×400 in the bottom-right corner of the screen.
- **Steps:**
  1. Launch Expanse. At 100%, drag the window's top-left corner to make it about 1200×800.
  2. Quit Expanse (it goes back to 500×400 in the bottom right).
  3. Launch Expanse.
- **Expected:** The window is fully 1200×800 at its canvas spot, not clipped at the screen edge. During a glide the overlay hides the moment it jumps to the top left to grow.
- **Check in log:** `restore size TextEdit[<id>] {500, 400} -> {1200, 800}` (the size after the arrow is what was asked).
- **Automate:** manual: depends on macOS's own clamping of AX resizes.

## SIZE-05 After a display change, windows get their chosen sizes back
- **Type:** Feature
- **Area:** SIZE
- **Commits:** 9f92b18 (0.1.0), 0209aa7 (0.1.0)
- **Setup:** Big display, several windows at sizes you chose, some parked off-screen.
- **Steps:**
  1. Switch to a smaller resolution (System Settings › Displays), or unplug the external display. Wait 3s.
  2. Switch back.
- **Expected:** After each change, every window (parked ones too) has the size you chose, capped at the screen with a 16pt margin where it doesn't fit, not the size macOS squeezed it to. After step 2 every window is exactly its chosen size. The overlay covers the reshuffle.
- **Check in log:** `display changed: {w, h} -> {w, h}` and `fit size …`
- **Automate:** unit: CanvasController.cap(_:to:).
- **Note:** For a development build, `open "expanse://screen?w=1512&h=982"` and `open "expanse://screen"` stand in for a display change (debug commands on).

## SIZE-06 Only a size you choose becomes a window's size
- **Type:** Bug fix
- **Area:** SIZE
- **Commits:** 0209aa7 (0.1.0)
- **Before:** Any resize Expanse didn't make became the window's chosen size: Chromium's stepped resizes, macOS squeezing windows for a smaller display, even Expanse's own fitting. Windows then didn't grow back to the size you'd picked.
- **Setup:** Big display. A Chrome window dragged to 1600×1000.
- **Steps:**
  1. Switch to a smaller resolution (the window shrinks to fit), then back.
  2. Drag its edge to 1400×900, then repeat step 1.
- **Expected:** 1: back at 1600×1000. 2: back at 1400×900 (your drag made the new chosen size).
- **Automate:** unit: CanvasController.adoptSize(_:_:fromUser:) (private).
- **Note:** 1a673fe also counts a resize right after your click or key press in that app (Fill, Moom, keyboard shortcuts).

## SIZE-07 VM and remote-screen windows keep the size their app picks
- **Type:** Feature
- **Area:** SIZE
- **Commits:** eb224e7 (0.1.21)
- **Setup:** A UTM (or Parallels, VMware, VirtualBox, Tart, Screen Sharing, Screens, Moonlight, Remote Desktop) window larger than the laptop screen, on the big display.
- **Steps:**
  1. Unplug the big display (or, with debug commands on, `open "expanse://screen?w=1280&h=800"`), then plug it back in (or `open "expanse://screen"`).
  2. Zoom out and press T.
  3. Change the VM's display resolution so its app resizes the window.
  4. Press T again.
- **Expected:** Expanse never resizes the VM window: it keeps its size on the small screen and through Tidy. After step 3, the new size is taken as its size, and step 4 doesn't change it.
- **Check in log:** No `fit size UTM[…]` or `resize UTM[…]` lines.
- **Automate:** unit: ManagedWindow.sizesItself for the listed bundle IDs.

## SIZE-08 Apps that size in steps don't make the layout count as shrunk
- **Type:** Bug fix
- **Area:** SIZE
- **Commits:** eb224e7 (0.1.21)
- **Before:** Terminal (character cells) or Chess (its board) never reach exactly the size asked for, so the layout counted as shrunk for a smaller screen even on the big one, and every Tidy asked for the size again.
- **Setup:** Big display. A Terminal window and a Chess window among others.
- **Steps:**
  1. Zoom out and press T.
  2. Press T again.
- **Expected:** Step 1 may resize Terminal once. Step 2 doesn't ask again: within 32pt of the size asked for counts as the chosen size.
- **Check in log:** Step 2: no `fit size Terminal[…]` line; `layout fitted: … derived=false`.
- **Automate:** unit: isDerived with CanvasController.appRounding (32) on fake windows.

## SIZE-09 A window fitted after a display change doesn't shrink when you focus it
- **Type:** Bug fix
- **Area:** SIZE
- **Commits:** c6c639e (0.1.22)
- **Before:** A display change fitted windows to the screen with no margin, but focusing a window fitted it with a 16pt margin, so it shrank and shifted the first time you focused it.
- **Setup:** Big display, a window larger than the laptop screen.
- **Steps:**
  1. Unplug the display; wait 3s.
  2. Click into that window (or hop to it).
- **Expected:** After step 1 it fills the screen less 16pt on each side. Step 2 doesn't resize or move it.
- **Check in log:** No `resize <App>[<id>] …` line on focus.
- **Automate:** unit: CanvasController.screenMargin used by fittedSize / fitToScreen.

## SIZE-10 A VM window keeps its spot when the VM changes resolution
- **Type:** Bug fix
- **Area:** SIZE
- **Commits:** 1b1cc23 (0.1.25)
- **Before:** When a VM's resolution changed, its app resized the window and moved it to keep it centred. Expanse followed that move as if you'd made it, so the window left its lined-up spot.
- **Setup:** A UTM window lined up in a row with other windows (tops level).
- **Steps:**
  1. In the guest, change the display resolution (bigger, then smaller).
  2. Then drag the UTM window by hand to a new spot.
- **Expected:** Step 1: the window keeps its top-left where it was, growing or shrinking from there; its top stays level with the row. Step 2: a drag with the mouse is followed as usual.
- **Check in log:** `UTM[<id>] resized itself <w>x<h> -> <w>x<h>; keeping its spot`
- **Automate:** manual: CanvasController.resizedItself (moves within 2s of a self-resize are put back) depends on live events.

## SIZE-11 A size set with macOS's Fill sticks
- **Type:** Bug fix
- **Area:** SIZE
- **Commits:** 1a673fe (0.1.28)
- **Before:** Only a resize made with the mouse button down counted as the size you chose, so macOS's Fill (the green button's menu or Window › Fill) was undone the next time Expanse fitted the window: a glide to it, Tidy Up or a display change shrank it back.
- **Setup:** At 100%, a TextEdit window smaller than the screen, and another window beside it.
- **Steps:**
  1. Hover the green button › Fill (or Window › Fill).
  2. ⌃→ to hop to the other window, then ⌃← back.
  3. Zoom out, press T (Tidy Up), then click the TextEdit window.
- **Expected:** The TextEdit window keeps the Fill size through the hops and Tidy Up, filling the screen; it isn't shrunk back to its earlier size.
- **Check in log:** No `resize TextEdit[<id>] … -> …` line on the hop back.
- **Automate:** manual: needs a real resize right after a click in the window's app (`realWindowChanged`: input in the last 1.5 s, window's app frontmost, Expanse hasn't resized it in the last 2 s).

## SIZE-12 A size set with Moom or a keyboard shortcut sticks
- **Type:** Bug fix
- **Area:** SIZE
- **Commits:** 1a673fe (0.1.28)
- **Before:** Resizes from Moom or keyboard shortcuts weren't counted as yours and were undone at the next fit.
- **Setup:** As SIZE-11; Moom installed, or use macOS's Fill shortcut (fn ⌃ F).
- **Steps:**
  1. In the TextEdit window, resize it with Moom (its shortcut or its grid) or with fn ⌃ F.
  2. ⌃→ then ⌃← to hop away and back.
- **Expected:** The window keeps the size you gave it.
- **Automate:** manual: needs a key press in the window's app followed by a resize from outside Expanse.

## SIZE-13 A window sized to fill the screen keeps filling it
- **Type:** Bug fix
- **Area:** SIZE
- **Commits:** 1a673fe (0.1.28)
- **Before:** Fitting capped every window at the screen less a 16 pt margin all round, so a window you'd sized to fill the screen was pulled 16 pt in from every edge.
- **Setup:** A laptop with an external display. On the external display, one window filled with Fill (SIZE-11) and one larger than the laptop's screen.
- **Steps:**
  1. Glide to the filled window (⌃+arrows) and back.
  2. Unplug the external display; wait for it to settle; glide to each window.
- **Expected:** Step 1: the filled window still fills the screen, flush with its edges. Step 2: a window bigger than the laptop's screen is shrunk to the screen less 16 pt on each side, so it doesn't touch the edges; a window that fits is left at its size.
- **Automate:** unit: `CanvasController.cap(_:to:)`: a size equal to (or under) the view's comes back unchanged; a bigger one becomes the view less 32 pt in that dimension.

## SIZE-14 A resize you didn't make doesn't change the size you chose
- **Type:** Bug fix
- **Area:** SIZE
- **Commits:** 1a673fe (0.1.28)
- **Before:** Not a bug before; this guards the fix from going too far. A resize the app or a script makes without your click or key in that app, or an app catching up with Expanse's own resize (Chromium resizes in steps), must not become your size.
- **Setup:** At 100%, a TextEdit window you sized yourself (note its size), Terminal open.
- **Steps:**
  1. In Terminal: `osascript -e 'tell application "TextEdit" to set bounds of front window to {100, 100, 700, 500}'`.
  2. ⌃+arrow to the TextEdit window (or click it on the canvas).
- **Expected:** The script's resize happens, but it isn't taken as your size (TextEdit wasn't the app in front): gliding to the window puts it back to the size you chose.
- **Check in log:** On the glide, `resize TextEdit[<id>] {600, 400} -> {<your size>}`.
- **Automate:** manual: the rule sits in `realWindowChanged` and reads live input timing.
