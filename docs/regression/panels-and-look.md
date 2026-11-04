# UI: Menu bar panel, minimap, Settings and the backdrop

[All areas](README.md)

## UI-01 The minimap shows every window, the view and the zoom
- **Type:** Feature
- **Area:** UI
- **Commits:** 0cdf466 (0.1.0), ccd4656 (0.1.18)
- **Setup:** Several windows open.
- **Steps:**
  1. Zoom out and look at the bottom-right corner; pan and zoom.
  2. Go back to 100% and look at the bottom-right corner of the desktop.
- **Expected:** A panel 16pt in from the bottom-right corner shows every window as a block, the part of the canvas on screen as an accent outline, and the zoom as a percentage; all three follow pans and zooms live. At 100% it's on the desktop, under your windows. On macOS 26 it's a Liquid Glass panel.
- **Automate:** manual: rendering.

## UI-02 The hovered window is outlined
- **Type:** Feature
- **Area:** UI
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. Move the pointer across several windows, at a few zoom levels.
- **Expected:** The window under the pointer gets an accent-colour border, the same thickness on screen at any zoom (2pt; 3pt for selected windows); it moves to whichever window is under the pointer. Over the minimap nothing is highlighted.
- **Automate:** manual: rendering.

## UI-03 Plain canvas background follows light and dark mode
- **Type:** Feature
- **Area:** UI
- **Commits:** 0cdf466 (0.1.0), 06a9a13 (0.1.0)
- **Setup:** Menu bar icon › "Desktop picture background" off.
- **Steps:**
  1. Zoom out in light mode.
  2. Switch macOS to dark mode while zoomed out.
- **Expected:** The canvas behind the windows is a light grey in light mode and a dark grey in dark mode, switching straight away.
- **Automate:** manual: appearance (a development build can force it with `expanse://appearance?mode=dark`, debug-only).

## UI-04 Zoomed out, the canvas covers the Dock but not the menu bar
- **Type:** Feature
- **Area:** UI
- **Commits:** 0cdf466 (0.1.0), 9428c25 (0.1.22)
- **Setup:** Dock always shown.
- **Steps:**
  1. Zoom out. Click the menu bar (e.g. the Apple menu).
- **Expected:** The canvas covers every window and the Dock; the menu bar stays above it and works.
- **Automate:** manual: window levels.
- **Note:** Since 9428c25 another app's dialog (alert, password prompt) stays above the canvas too.

## UI-05 Expanse lives in the menu bar, not the Dock
- **Type:** Feature
- **Area:** UI
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Expanse running.
- **Steps:**
  1. Look at the Dock and press ⌘-Tab.
  2. Look at the menu bar.
- **Expected:** No Expanse icon in the Dock or the ⌘-Tab switcher; an Expanse icon (three grouped rectangles) in the menu bar.
- **Automate:** unit: Info.plist `LSUIElement` true.

## UI-06 Window names are hidden unless turned on
- **Type:** Feature
- **Area:** UI
- **Commits:** 0cdf466 (0.1.0), dc044f9 (0.1.22), a2d80de (0.1.31)
- **Setup:** `defaults delete com.invignation.expanse showWindowNames`, restart Expanse.
- **Steps:**
  1. Zoom out.
  2. In the menu bar panel turn on "Window names when zoomed out".
  3. Zoom out, hover a window.
  4. Restart Expanse and zoom out.
- **Expected:** Step 1: no app names above the windows. Step 3: each window has its app's name above it, and the hovered one shows its title. Step 4: names still on. Copy Logs reports "window names shown" or "hidden".
- **Automate:** unit: CanvasView.showsNames (UserDefaults showWindowNames).
- **Note:** At dc044f9 this was the menu item "Show Window Names"; it became the panel switch in a2d80de.

## UI-07 The canvas shows the real desktop picture
- **Type:** Feature
- **Area:** UI
- **Commits:** 06a9a13 (0.1.0), 42b415b (0.1.29), 077d3dd (0.1.29), a2d80de (0.1.31)
- **Setup:** Screen Recording granted. A dynamic or Photos wallpaper set. Panel › Desktop picture background on (the default).
- **Steps:**
  1. Press ⌥` to zoom out and compare the picture behind the windows with the real desktop.
  2. Back at 100%, turn Desktop picture background off, then zoom out again.
  3. Turn it back on and zoom out.
- **Expected:** Step 1: the canvas background is the desktop as macOS is drawing it right now (dynamic and Photos wallpapers included), lined up with the real desktop including the strip under the menu bar. Step 2: a plain background, light grey in Light mode, dark grey in Dark mode. Step 3: the picture is back.
- **Automate:** manual: needs ScreenCaptureKit and a real desktop.
- **Note:** Since 077d3dd it's a fresh picture of the whole desktop (icons and dimming included), taken as the canvas opens if the last is over 2s old. The 5-minute refresh timer from this commit was removed in 2f6c592 (every capture made protected video blink). With no Screen Recording, no picture is captured (ac50e01). If no wallpaper window is found, the image file is used instead.

## UI-08 Another Space's desktop picture shows on the canvas there
- **Type:** Feature
- **Area:** UI
- **Commits:** 06a9a13 (0.1.0)
- **Setup:** Two desktop Spaces with different desktop pictures. Desktop picture background on.
- **Steps:**
  1. On Desktop 1, press ⌥`, note the picture, press ⌥` again.
  2. Switch to Desktop 2 with Mission Control and press ⌥`.
  3. Switch back to Desktop 1 and press ⌥`.
- **Expected:** The canvas background always matches the Space you're on: Desktop 2's picture in step 2, Desktop 1's again in step 3. The picture is re-taken on every Space switch.
- **Automate:** manual: needs real Spaces.

## UI-09 Window names over the desktop picture are white with a shadow
- **Type:** Feature
- **Area:** UI
- **Commits:** 06a9a13 (0.1.0)
- **Setup:** Panel › Window names when zoomed out on. Desktop picture background on.
- **Steps:**
  1. Press ⌥` and look at the app names above the windows.
  2. Turn Desktop picture background off and press ⌥` again, in Light mode and then in Dark mode.
- **Expected:** Step 1: names are white with a soft dark shadow, readable on any wallpaper. Step 2: names are plain grey without a shadow (dark grey in Light mode, light grey in Dark mode).
- **Automate:** unit: CanvasView.styleLabel (private; needs exposing).
- **Note:** Names are hidden unless turned on since dc044f9.

## UI-10 Picking the hot corner in the panel
- **Type:** Feature
- **Area:** UI
- **Commits:** 06a9a13 (0.1.0), a2d80de (0.1.31)
- **Setup:** Expanse running, at 100%. macOS's own hot corners set to "–".
- **Steps:**
  1. Open the panel; in the Hot corner card click the top-right dot of the little screen.
  2. Rest the pointer in the top-right corner, then in the bottom-left corner.
  3. In the card click "Off", and rest the pointer in each corner.
  4. Click "All corners".
- **Expected:** The panel stays open as you pick. With top-right picked only that dot is lit; the top-right corner opens the canvas and the others don't. "Off" lights no dot and no corner opens it. "All corners" lights all four and any corner opens it. The pick is kept after relaunching.
- **Automate:** manual: hot corners need the real pointer.

## UI-11 Welcome and Quit from the panel's footer
- **Type:** Feature
- **Area:** UI
- **Commits:** c7cba50 (0.1.0), a2d80de (0.1.31)
- **Setup:** Expanse running, zoomed out, windows arranged.
- **Steps:**
  1. Open the panel and click the ? button (tooltip "Welcome & Shortcuts").
  2. Close the walkthrough. Open the panel and click the power button (tooltip "Quit Expanse").
- **Expected:** ? leaves the canvas first (back to 100%), then opens the walkthrough window in front. Power quits Expanse: every window goes back to where macOS had it, and the menu bar icon goes away.
- **Automate:** manual: walkthrough window and quitting.

## UI-12 Expanse has its own app icon
- **Type:** Feature
- **Area:** UI
- **Commits:** 7ee9f9d (0.1.0)
- **Setup:** Expanse installed in Applications.
- **Steps:**
  1. Look at Expanse in Finder › Applications and in Get Info.
  2. Open Welcome & Shortcuts, and the menu bar panel.
- **Expected:** The ring-gate icon (a portal onto a grid of windows) shows in Finder and Get Info, on the walkthrough's welcome page and in the panel's header.
- **Automate:** manual: visual.

## UI-13 The walkthrough's canvas illustration
- **Type:** Feature
- **Area:** UI
- **Commits:** bf8e9a6 (0.1.5)
- **Setup:** The walkthrough is open.
- **Steps:**
  1. Watch the left panel on page 1, then on Step 3, then on Step 4.
- **Expected:** A deep-blue starry canvas in the icon's colours, with groups of small named windows (Calendar, Slack, TV and others). It gently zooms out to reveal more windows past the edges and back in, showing a zoom percentage under the "Expanse" name. On Step 3 a pointer flicks to Expanse's chosen corner as it zooms out. On Step 4 it glides window to window (right, down, left, up), with the focused window outlined in amber.
- **Automate:** manual: visual.

## UI-14 A banner in the panel when an update is ready
- **Type:** Feature
- **Area:** UI
- **Commits:** 0cd0016 (0.1.7), a2d80de (0.1.31)
- **Setup:** A release build older than the latest GitHub release.
- **Steps:**
  1. Settings › Check Now; when "Expanse x.y.z is ready to install" appears, choose Later.
  2. Open the panel and click "Install and Relaunch".
- **Expected:** The panel shows a banner "Expanse x.y.z is ready" with "It relaunches, and your windows stay where they are." and an "Install and Relaunch" button; clicking it closes the panel and installs the update, which relaunches Expanse.
- **Automate:** manual: needs a real downloaded release.

## UI-15 A clicked Spaces tile doesn't stay lit
- **Type:** Bug fix
- **Area:** UI
- **Commits:** f310f04 (0.1.8)
- **Before:** Hover only updates while zoomed out, so the tile you clicked kept its hover ring after the canvas closed and showed it when you next looked.
- **Setup:** Safari full screen.
- **Steps:**
  1. Zoom out and click Safari's tile.
  2. Come back to the canvas's desktop and zoom out again without moving over the panel.
- **Expected:** Only the current Space's accent ring shows; there is no leftover quiet ring on Safari's tile. The same applies to clicking a tile at 100%.
- **Automate:** unit: CanvasView.mouseDown sets spacesBar.hovered to nil before switchToSpace.

## UI-16 Full-screen apps' icons in the Spaces panel are sharp
- **Type:** Bug fix
- **Area:** UI
- **Commits:** f310f04 (0.1.8)
- **Before:** The app icon on a full-screen app's tile used a small default image and looked blurry.
- **Setup:** A Retina display, and a full-screen app.
- **Steps:**
  1. Zoom out and look closely at the app's tile.
- **Expected:** The 36pt icon is crisp at the screen's pixel density.
- **Automate:** manual: visual.

## UI-17 The walkthrough's animation is capped at 60 fps
- **Type:** Bug fix
- **Area:** UI
- **Commits:** f310f04 (0.1.8)
- **Before:** The illustration redrew at the display's full rate (120 Hz on ProMotion), costing CPU for nothing.
- **Setup:** A 120 Hz display, with Activity Monitor open.
- **Steps:**
  1. Open the walkthrough and leave it on page 1 for a minute.
- **Expected:** The animation looks smooth, and Expanse's CPU use stays modest, consistent with redrawing at most 60 times a second.
- **Automate:** manual. TimelineView(.animation(minimumInterval: 1/60)).

## UI-18 The minimap and Spaces panel stay under the windows during a glide
- **Type:** Bug fix
- **Area:** UI
- **Commits:** c4d8ec4 (0.1.13)
- **Before:** Mid-glide the canvas sits over the real windows showing their pictures, and the minimap and Spaces panel were drawn on top of those. They jumped in front of the windows for the length of the hop, then went back under.
- **Setup:** At 100%, with a window covering the bottom-right of the screen where the minimap and Spaces panel sit, and full-screen apps open so the Spaces panel shows.
- **Steps:**
  1. Press ⌃→ and ⌃← to hop.
  2. Press ⌥` to zoom out.
- **Expected:** During the hops the minimap and Spaces panel never appear over the windows. Zoomed out, they are on top of the window pictures and clickable.
- **Automate:** unit: CanvasView.render sets the minimap and Spaces glass layers' zPosition to -1 while gliding and 0 otherwise.

## UI-19 Minimap and Spaces panels are glass that follows light and dark
- **Type:** Feature
- **Area:** UI
- **Commits:** ccd4656 (0.1.18), 8e8f301 (0.1.18), 03451fb (0.1.18), e36baa4 (0.1.18), 394c6e8 (0.1.18)
- **Setup:** At least one full-screen app open (so the Spaces panel shows). Zoomed out.
- **Steps:**
  1. Look at the minimap (bottom right) and the Spaces panel to its left.
  2. Switch the Mac between Light and Dark (System Settings › Appearance, or URL-21).
  3. Click a spot on the minimap; click a Space tile.
- **Expected:** Both panels are rounded glass (22pt corners): Liquid Glass on macOS 26, the HUD material on macOS 15. On light glass the window blocks and text are dark; on dark glass they're light, and they update as soon as the appearance changes. Clicks reach the panels through the glass: a click on the minimap centres the view on that spot, and a Space tile switches to that Space.
- **Automate:** unit: Minimap.applyAppearance(_:) and SpacesBar.applyAppearance(_:) colours for .aqua and .darkAqua | manual: the glass itself.
- **Note:** Rounds 6, 7 and 8 were reverted; the hand cursor, hover ring on the map and Space tile press state are still on the features list.

## UI-20 The Spaces panel marks the current Space with a ring
- **Type:** Feature
- **Area:** UI
- **Commits:** ccd4656 (0.1.18), 8e8f301 (0.1.18), 03451fb (0.1.18), e36baa4 (0.1.18), 394c6e8 (0.1.18), e9a6f65 (0.1.18)
- **Setup:** Two full-screen apps open. Zoomed out.
- **Steps:**
  1. Look at the Spaces panel.
  2. Hover over a full-screen app's tile.
  3. Close the full-screen apps until only the desktop's Space is left.
- **Expected:** The canvas's own Space is called "Expanse"; its tile has an accent-coloured ring set a little outside it and its name is bold. The hovered tile gets a thin grey ring. Other tiles aren't dimmed. A full-screen app's tile shows its icon, slightly lifted, on a quiet grey well; tile corners follow the panel's. With a single Space the panel is hidden.
- **Automate:** unit: SpacesBar.update(spaces:active:wallpaper:) and the hovered property (ring visibility, label weight).
- **Note:** The tile was called "Canvas" until e9a6f65.

## UI-21 Minimap header shows the name and the zoom on one row
- **Type:** Feature
- **Area:** UI
- **Commits:** 8e8f301 (0.1.18), 03451fb (0.1.18), e36baa4 (0.1.18), e9a6f65 (0.1.18)
- **Setup:** Zoomed out, a full-screen app open so the Spaces panel shows.
- **Steps:**
  1. Look at the top row of the minimap.
  2. Press = and - to zoom.
- **Expected:** The minimap's top row reads "Expanse" on the left (semibold, 11pt) and the zoom on the right (for example "35%"), level with the Spaces panel's "Spaces" heading. The percentage updates as you zoom. The map sits below that row, 14pt in from the panel's edges.
- **Automate:** unit: Minimap.update(windows:viewport:scale:) sets the zoom text.
- **Note:** The title read "Canvas" until e9a6f65.

## UI-22 Minimap viewport: an accent ring, or a quiet outline when it frames everything
- **Type:** Feature
- **Area:** UI
- **Commits:** 8e8f301 (0.1.18), 03451fb (0.1.18), e36baa4 (0.1.18), 394c6e8 (0.1.18)
- **Setup:** About 10 windows spread over the canvas. Zoomed out.
- **Steps:**
  1. Press 0 to fit everything.
  2. Press 1 (100%) and pan to one window.
  3. With many windows on the canvas, zoom in until the view covers a tiny part of the map.
- **Expected:** Step 1: the viewport covers more than half the map, so it's a thin (1pt) grey outline with no tint. Step 2: a 2pt ring in the accent colour, standing 3pt off the window blocks inside it, over a light accent tint under the blocks. Step 3: the ring never gets smaller than about 20×13pt, so it can still be found. Window blocks have rounded corners and a thin seam so overlapping windows stay apart.
- **Automate:** unit: Minimap.update(windows:viewport:scale:) (viewport tint hidden and line width 1 when it covers over half the map area).

## UI-23 A dialog that opens while zoomed out shows above the canvas
- **Type:** Bug fix
- **Area:** UI
- **Commits:** 9428c25 (0.1.22)
- **Before:** The canvas sat above every app window, including alerts, password and permission prompts and run-modal panels. A dialog that opened while zoomed out (or during a glide) waited unseen until you left the canvas.
- **Setup:** Terminal open.
- **Steps:**
  1. Run `sleep 5; osascript -e 'tell application "Finder" to display alert "Expanse test"'`.
  2. Within 5s press ⌥` to zoom out and stay zoomed out.
  3. Click OK on the alert.
  4. Zoom out again with the alert already showing (repeat step 1 first).
- **Expected:** Within about half a second of appearing, the alert shows above the canvas and can be clicked. Once it closes the canvas goes back to its usual level. Step 4: the canvas opens under the alert.
- **Check in log:** `canvas level <n> -> <m> (under a dialog)`, then `canvas level <m> -> <n>`
- **Automate:** manual: CanvasController.lowestDialogLevel reads the real window list.
- **Note:** Since 31 Oct (not released yet) the half-second check reads the window list on a background queue, then sets the level on the main thread; zooming out and starting a glide still read it first, so the canvas never opens over a dialog already showing.

## UI-24 The Dock doesn't count as a dialog
- **Type:** Feature
- **Area:** UI
- **Commits:** 9428c25 (0.1.22)
- **Setup:** No dialogs open. Dock visible.
- **Steps:**
  1. Zoom out and wait a few seconds.
- **Expected:** The canvas covers the Dock as usual. The log has no `(under a dialog)` line. Expanse's own windows, and windows under 100×50pt or fully transparent, don't count either.
- **Automate:** manual: lowestDialogLevel filters the live window list.

## UI-25 At 100% the real desktop shows through the backdrop
- **Type:** Bug fix
- **Area:** UI
- **Commits:** 42b415b (0.1.29)
- **Before:** At 100% the backdrop drew its own copy of the desktop picture over the real one, so it missed what macOS does to the desktop: the shade under the menu bar stopped dead at the menu bar's edge, there was no dimming behind a window that fills the screen, and desktop icons didn't show.
- **Setup:** At 100%, Finder showing items on the desktop, a light desktop picture.
- **Steps:**
  1. Compare the desktop with Expanse running and with it paused (menu bar icon › Pause, then resume).
  2. Fill a window (Window › Fill) and look at the desktop around it.
- **Expected:** With Expanse running, the desktop looks exactly as macOS draws it: the shade under the menu bar fades as without Expanse, desktop icons show, and macOS's dimming behind a filled window shows. Only what Expanse draws there (slivers of parked windows, the minimap and Spaces panels) is on top.
- **Automate:** manual: visual, depends on the window server's compositing.
- **Note:** The icons' clicks were Expanse's in this commit; f70bf12 made them clickable (UI-27).

## UI-26 The canvas and a glide still draw their own copy of the desktop
- **Type:** Feature
- **Area:** UI
- **Commits:** 42b415b (0.1.29)
- **Setup:** "Desktop picture background" on (menu bar icon › panel). Windows on the canvas, one off screen.
- **Steps:**
  1. Zoom out (⌥`).
  2. Go back to 100%, then ⌃+arrow to the off-screen window and watch the background during the glide.
  3. Turn "Desktop picture background" off and zoom out again; switch macOS between Light and Dark.
- **Expected:** Zoomed out and during the glide, the backdrop is opaque and shows Expanse's copy of the desktop behind the windows' pictures; it doesn't flash through to the real desktop. With the setting off, the canvas is plain grey: light in Light mode, dark in Dark mode. At 100% the backdrop is see-through again (UI-25).
- **Automate:** manual: visual (`CanvasView.render`: wallpaper hidden and background clear unless `isActive`).

## UI-27 Desktop icons can be clicked at 100%
- **Type:** Feature
- **Area:** UI
- **Commits:** f70bf12 (0.1.29)
- **Setup:** At 100%, Finder showing items on the desktop, with bare desktop showing between windows.
- **Steps:**
  1. Click a desktop icon; double-click it.
  2. Right-click the bare desktop.
  3. Drag an icon to another place on the desktop.
- **Expected:** The desktop behaves as without Expanse: the icon is selected, then opens; Finder's desktop menu appears; the icon moves. The canvas doesn't open.
- **Automate:** manual: needs the window server passing clicks through the see-through backdrop.

## UI-28 The canvas opens onto a fresh picture of the real desktop
- **Type:** Feature
- **Area:** UI
- **Commits:** 077d3dd (0.1.29)
- **Setup:** "Desktop picture background" on. At 100%, desktop icons showing; a window placed so the menu bar's shade is visible.
- **Steps:**
  1. Scroll on the bare desktop to open the canvas at 100% (NAV-18), and watch the background.
  2. Esc, move or add a desktop icon, wait 3 s, then zoom out (⌥`).
- **Expected:** Opening the canvas changes nothing under the windows: its desktop shows the wallpaper, Finder's icons and the shade under the menu bar as they are at that moment. Step 2: the moved or new icon shows on the canvas.
- **Automate:** manual: screen capture of the windows below the backdrop (`Wallpaper.capture`).

## UI-29 No dimmed desktop is left on the canvas after Fill
- **Type:** Bug fix
- **Area:** UI
- **Commits:** 077d3dd (0.1.29)
- **Before:** On another Mac (29 Oct) the canvas's background went dark after using Fill: macOS dims the desktop behind a window that fills the screen, the canvas's copy of the desktop picture was taken then, and it was kept (refreshed at most every 30 s).
- **Setup:** "Desktop picture background" on; a window you can Fill.
- **Steps:**
  1. Fill the window (Window › Fill); zoom out (⌥`), then back.
  2. Resize the window smaller so macOS no longer dims the desktop; wait 3 s.
  3. Zoom out again.
- **Expected:** Step 1: the canvas's desktop is dimmed, as the real one is. Step 3: it's bright again; no dimmed copy is left behind.
- **Automate:** manual: depends on macOS's dimming and a screen capture.

## UI-30 The panel's status line
- **Type:** Feature
- **Area:** UI
- **Commits:** a2d80de (0.1.31)
- **Setup:** Three windows on the canvas.
- **Steps:**
  1. Open the panel.
  2. Close one window with the panel open.
  3. Reset the walkthrough (`defaults delete com.invignation.expanse onboardingDone`), relaunch, and open the panel before finishing the walkthrough.
- **Expected:** Step 1: "On · 3 windows on the canvas" ("1 window" when singular). Step 2: the count and the minimap update within about half a second. Step 3: "Starts once the walkthrough is done", the app icon grey, and the switch, minimap card, tiles, snapshot links and thumbnails all greyed out and inactive.
- **Automate:** manual: SwiftUI panel.

## UI-31 The menu bar icon opens a glass panel
- **Type:** Feature
- **Area:** UI
- **Commits:** a2d80de (0.1.31)
- **Setup:** Expanse running (walkthrough done), a few windows on the canvas, at 100% in an ordinary app (say Safari).
- **Steps:**
  1. Click the Expanse icon in the menu bar.
  2. Look over the panel, then click the icon again.
  3. Open it again and press Esc.
  4. Open it again and click anywhere outside it (the desktop, another app's window).
- **Expected:** A rounded glass panel (Liquid Glass on macOS 26, a popover material before) opens on the mouse press, just under the icon, kept on screen. Top to bottom: the Expanse icon with "Expanse" and "On · N windows on the canvas" and an on/off switch; a minimap card with "Open Expanse" and ⌥`; "Centre window" (⌃⌥C) and "Tidy up" tiles; three switches; the Hot corner card; "Earlier layouts" with Take snapshot · Restore all windows; a footer with a green dot "Permissions OK" and four round buttons (?, stethoscope, gear, power). Safari stays the frontmost app while it's open. Clicking the icon again, Esc, or a click outside closes it (fading out); the click on the icon that closed it doesn't reopen it.
- **Automate:** manual: a status-item panel, focus and click monitors need a real menu bar.
- **Note:** The old NSMenu is gone. README's Questions still say "Restore Layout", "Restore All Windows" and "Welcome & Shortcuts": in the panel these are the Earlier layouts thumbnails, the "Restore all windows" link and the ? button.

## UI-32 The panel's minimap opens the canvas and stays live
- **Type:** Feature
- **Area:** UI
- **Commits:** a2d80de (0.1.31)
- **Setup:** Expanse running, several windows on the canvas, at 100%.
- **Steps:**
  1. Open the panel and watch the minimap card while another app moves or opens a window.
  2. Click the minimap card.
  3. While zoomed out, open the panel again.
  4. Pause Expanse (header switch), then look at the card and click it.
- **Expected:** The card draws every window as a block and the part of the canvas the screen shows as an accent-coloured outline, updating about twice a second while the panel is open. Clicking it closes the panel and zooms out (as ⌥`). Zoomed out, the card's label reads "Back to 100%" and clicking it goes back. Paused, the map is dimmed with no outline, the label reads "Resume Expanse" without the ⌥` keys, and clicking it resumes Expanse (the panel stays open).
- **Automate:** manual: needs the live panel and canvas.

## UI-33 The panel's switch pauses and resumes Expanse
- **Type:** Feature
- **Area:** UI
- **Commits:** a2d80de (0.1.31)
- **Setup:** Expanse running with windows arranged on the canvas, some parked off screen.
- **Steps:**
  1. Open the panel and turn the header switch off.
  2. Look at the panel, then turn the switch back on.
- **Expected:** Off: every window goes back to where macOS had it; the panel stays open; the status reads "Paused · windows back in the macOS layout", the app icon turns grey, the minimap dims, and the Centre/Tidy tiles, Take snapshot, Restore all windows and the thumbnails are disabled. The switch's tooltip says "Resume Expanse" while paused and "Pause Expanse: windows go back to the macOS layout" while on. On again: the canvas comes back from the saved layout and the status returns to "On · N windows on the canvas".
- **Check in log:** "paused", then "resumed".
- **Automate:** manual: pausing moves real windows.

## UI-34 Centre window and Tidy up from the panel
- **Type:** Feature
- **Area:** UI
- **Commits:** a2d80de (0.1.31)
- **Setup:** Expanse running, at 100% in a window that is off-centre; a few windows with uneven gaps.
- **Steps:**
  1. Open the panel and click "Centre window".
  2. Open the panel and click "Tidy up".
  3. Pause Expanse and open the panel.
- **Expected:** Centre window closes the panel and moves the window you were in (the app that was frontmost before you opened the panel) to the middle of the screen, as ⌃⌥C does. Tidy up closes the panel and tidies as T does: each group lined up and evenly spaced where it is, shown zoomed out. While paused (or before the walkthrough is done) both tiles are greyed and do nothing.
- **Automate:** manual: real window moves through the panel.

## UI-35 The panel's switches change settings and leave the panel open
- **Type:** Feature
- **Area:** UI
- **Commits:** a2d80de (0.1.31)
- **Setup:** Expanse running.
- **Steps:**
  1. Open the panel; flip "Auto-centre focused window", "Desktop picture background" and "Window names when zoomed out" in turn.
  2. Zoom out (⌥`) and look; then flip them back.
- **Expected:** Each switch flips at once and the panel stays open. Auto-centre matches ⌥⇧` (same setting; the panel shows ⌥⇧` next to it). With Desktop picture background on, the zoomed-out backdrop shows the desktop picture; with Window names on, app names show above windows when zoomed out. The switches reflect the current settings each time the panel opens.
- **Automate:** manual: needs the panel and the canvas to look at.

## UI-36 A thumbnail leaves out windows that were out of view
- **Type:** Feature
- **Area:** UI
- **Commits:** a2d80de (0.1.31)
- **Setup:** Expanse running; one app's window (say Notes) sits apart from the others on the canvas.
- **Steps:**
  1. Hide Notes (⌘H).
  2. Open the panel and click Take snapshot.
  3. Open the newest file in `~/Library/Application Support/Expanse/Snapshots/`.
- **Expected:** The new thumbnail draws only the windows that were on the canvas: no block where the hidden Notes window is. In the file, Notes' entry is still there (its spot is kept for when it's back) with `"away" : true`; the windows on the canvas have no `away` key. Layouts saved before 0.1.31 have no `away` key and draw every entry.
- **Automate:** unit: CanvasController.save (entries for recentlyRemoved and savedPool marked away) and the MenuPanel layouts filter.

## UI-37 A banner in the panel when a permission is missing
- **Type:** Feature
- **Area:** UI
- **Commits:** a2d80de (0.1.31)
- **Setup:** Expanse running. In System Settings › Privacy & Security, turn Screen Recording off for Expanse (leave Accessibility on).
- **Steps:**
  1. Open the panel.
  2. Click the banner's "Open System Settings".
  3. Turn Screen Recording back on, turn Accessibility off, and open the panel again.
- **Expected:** An orange banner "Screen Recording is off" with "Zoomed out, windows show as outlines without it. Once it's on, reopen Expanse."; the footer shows an orange dot and "Permission needed". The button asks macOS for Screen Recording (its prompt, or the Screen Recording list in System Settings). With Accessibility off the banner reads "Accessibility is off", "Expanse can't move windows without it.", and the button goes to Accessibility; with both off, "Accessibility and Screen Recording are off". Permissions are read as the panel opens.
- **Automate:** manual: needs real privacy settings.

## UI-38 The Settings page
- **Type:** Feature
- **Area:** UI
- **Commits:** a2d80de (0.1.31), 4045597 (0.1.31), unreleased (4 Nov)
- **Setup:** A release build.
- **Steps:**
  1. Open the panel and click the gear button.
  2. Flip "Open Expanse at login"; check System Settings › General › Login Items.
  3. Turn "Check for updates automatically" off and on; click Check Now.
  4. Change the login item in System Settings, then open the page again.
- **Expected:** The panel shows its Settings page (UI-42): an "Open Expanse at login" switch, Gaps between windows, Glides and zooms, and an Updates section with "Check for updates automatically" and "Expanse <version>" with Check Now. Step 2: Expanse is added to or removed from Login Items; if macOS wants your OK, System Settings opens at Login Items, leaving the canvas first if zoomed out, and the switch shows on only once it's really on. Step 3: Check Now closes the panel, leaves the canvas first if zoomed out, and answers in an alert. Step 4: the switch shows the change.
- **Automate:** manual: SMAppService and the updater need a signed release.
- **Note:** In a development build the Updates section is greyed out and a footnote reads "This is a development build: it has no updates, and opening at login opens this copy." The login switch works there since 4045597 (see SETUP-27). This was a window of its own until 0.1.41 (it closed the canvas first, and came back as the same window), and its Gaps and Glides pickers were pop-up menus.

## UI-39 Before the walkthrough is done the panel says so
- **Type:** Feature
- **Area:** UI
- **Commits:** a2d80de (0.1.31)
- **Setup:** Quit Expanse; `defaults delete com.invignation.expanse onboardingDone`; launch Expanse so the walkthrough shows. Don't finish it.
- **Steps:**
  1. Click the menu bar icon.
  2. Try the minimap card, the header switch, Centre window, Tidy up, Take snapshot, Restore all windows.
  3. Try the switches, the hot corner, Settings and Troubleshooting.
- **Expected:** The status reads "Starts once the walkthrough is done" and the app icon is grey. The minimap card, header switch, both tiles, Take snapshot, Restore all windows and thumbnails are greyed and do nothing. Switches, the hot corner, Settings, Troubleshooting, ? and Quit work.
- **Automate:** unit: MenuPanel.Action.needsCanvas (and the run guard on State.isOn).

## UI-40 A sliver at the screen's edge doesn't cover the minimap or Spaces panel
- **Type:** Bug fix
- **Area:** UI
- **Commits:** 4045597 (0.1.31)
- **Before:** A window peeking in at the screen's edge with only a sliver showing was put on screen, covering the minimap and Spaces panels that sit on the backdrop.
- **Setup:** Expanse running; a window about 900pt wide.
- **Steps:**
  1. Zoomed out, place the window so that, back at 100%, only about 120pt of it shows at the right edge of the screen, level with the minimap (bottom right). Go back to 100%.
  2. Repeat with about 300pt showing.
  3. Repeat with a 120pt sliver at the right edge near the top, clear of the panels.
- **Expected:** Step 1: the real window stays parked; the backdrop draws what shows of it, under the minimap. Step 2: the window is put on screen. Step 3: the window is put on screen. A sliver is less than 200pt (or a third of the window) showing in either direction; only one that would overlap the minimap or a visible Spaces panel stays parked.
- **Automate:** unit: CanvasController.goesOnScreen(_:in:panels:) (120pt over the panels → false; 300pt → true; 120pt elsewhere → true).
- **Note:** Since 2f6c592 the backdrop's picture of a sliver is taken once, as it comes into view.

## UI-41 An invisible window over the whole screen isn't taken for a dialog
- **Type:** Bug fix
- **Area:** UI
- **Commits:** unreleased (3 Nov)
- **Before:** After a notification, macOS 27 keeps an invisible Notification Center window over the whole screen, at a dialog's level. Expanse took it for a dialog (UI-23), so every zoom-out opened the canvas under it (`canvas level 23 -> 20 (under a dialog)` in the log), and the end-to-end UI-23 and UI-24 could never run (found 3 Nov in the VM).
- **Setup:** At 100%. `osascript -e 'display notification "Expanse test"'`, then wait for the banner to go.
- **Steps:**
  1. Zoom out (⌥`).
- **Expected:** No `canvas level … (under a dialog)` line; a real dialog still puts the canvas under it (UI-23).
- **Automate:** unit: `lowestDialogLevel(in:screen:ownPID:isDock:)` leaves out a window the size of the screen and keeps a real one; end-to-end: UI-23 and UI-24 count dialogs the same way.

## UI-42 Settings is a page of the panel, not a window of its own
- **Type:** Feature
- **Area:** UI
- **Commits:** unreleased (4 Nov)
- **Setup:** Zoomed out, with a window or two.
- **Steps:**
  1. Open the panel and click the gear button.
  2. Under Gaps between windows pick 10pt, None, then 20pt. Under Glides and zooms pick Jump, Animate, then Match macOS.
  3. Press Esc.
  4. Click the gear, then the back arrow.
  5. Click the gear, press Esc twice, and open the panel again.
- **Expected:** Step 1: Settings takes the place of the panel's first page, in the same panel with its top where it was. The canvas stays zoomed out, and no window opens. Step 2: each pick takes at once, and the panel stays on the page. Step 3: back to the first page, still open, the panel grown to fit it with its top where it was. Step 4: the same. Step 5: the second Esc closes the panel, and it opens again on its first page.
- **Automate:** unit: `escape()`, `Action.closesPanel`, `SettingsPage` and the picks through `AppDelegate.perform`; end-to-end.
