# Features

What we might build next. New requests go in as they come up, and finished work moves to Done.

## Not released yet

- A full-screen app's tile in the Spaces panel shows a picture of its Space instead of the app's
  icon (asked 6 Nov), split view's two windows side by side. It's taken as the canvas opens and
  kept, so nothing's captured at 100% and protected video doesn't blink. The icon shows until the
  first picture.
- A window too tall for the screen that can't shrink (a Tart VM's, on a laptop's screen) stays where
  you put it on the canvas, and no longer holds up every hop by a quarter of a second.

## Bugs

None open. The "to check" list from writing the regression tests is settled (3 Nov): four were
real and are fixed; the README and how-it-works now name the menu bar panel's items.

To check (4 Nov): with the screenshots' stock apps still open in the VM, EDIT-14 and EDIT-26 fail
with low motion on or off: Tidy Up moves a group's left end by 288pt, and the log says
`derived=true`. They pass with those apps closed. It may only be the scene asking Chess for a size
it won't take, which would make the layout look shrunk for a smaller screen.

To check (6 Nov): desktop icons cut off along the right edge of the canvas's picture, seen once on
the Mac with an empty desktop and Brave full screen. Icons stopped about 33pt in and labels about
20pt in, in their right places. Not reproduced there or in the VM. SPACES-28 may not be the whole
cause; if it comes back, see whether reopening the canvas clears it.

To check (6 Nov): TRACK-35 fails on 0.1.43 in the VM, three times out of three, untouched main
included: after a window closes, going to Finder and back to the app doesn't glide to its other
window. UI-34 fails on main too, and has a session of its own.

If a new window doesn't make it onto the canvas, the log says why (look for "not on the canvas"
in Copy Logs for a Bug Report).

## Next up

1. **Window size snapping** (asked 28 Oct). Resize so grids of windows come out neat. Today
   Expanse only moves windows; resizing is whatever you do to the real window at 100%.
   - While you resize, edges snap to neighbouring edges and to the standard 20pt gap.
   - Sizes snap to match: the same width as the column, the same height as the row.
   - Maybe: resize handles on the canvas while zoomed out, and a way to even up a row or
     column in one go.
   - Released in 0.1.35 for zoomed out: edge and corner handles that snap to
     neighbours, the gap and screen halves; a right-click size menu; evening up a selection.
     Still to do: the same snapping when you resize a real window at 100%.
2. **Demo videos for the README.** Recorded in a clean macOS VM, so nothing personal is filmed.
   In progress. Screenshots of each feature went in first (asked 4 Nov): the README's See it work
   section, which `scripts/screenshots.sh` retakes.
3. **Minimap and Spaces polish**, left over from the UI hill climb:
   - the viewport keeps one accent ring at every zoom level, instead of turning into a grey box;
   - windows in view are drawn stronger than off-screen ones;
   - a press state on Space tiles, with the switch happening on mouse-up;
   - an open-hand cursor over the minimap, and at 100% a click goes to that spot.
4. **Multiple monitor support** (asked again 28 Oct). Today Expanse uses the main display only.
5. **Regression tests** (asked 29 Oct). Built: every case in [regression/](regression/README.md)
   has a test. 576 unit tests (`scripts/test.sh`, about a minute and a half, all passing), and 244
   end-to-end cases that drive the real app in the expanse-demo VM (`scripts/vm-integration.sh`;
   `--all` adds the 85 that need you). A new fix adds its case and its test.
   - End-to-end, 2 Nov: a complete run of 0.1.36 in the VM passed all 145 automatic cases, in one
     go (`--timeout 800`). Four skip by design: three need a Developer ID release, and NAV-50's
     Dock step needs a Dock that stays shown. macOS's screen-recording prompt still comes back now
     and then (it needs an Allow by hand); finish a run it interrupted with `--only`.
   - End-to-end, 3 Nov (0.1.37 and the fixes since): every automatic case passed across a complete
     run and its reruns, apart from SPACES-25, UI-23 and UI-24, which a notification stuck on the
     VM's screen kept from running. SIZE-11's failures were a real bug (PERSIST-43); NAV-34's was
     the Mac sleeping mid-case. The screen-recording prompt that came back right after TRACK-11
     (four times out of four) was Expanse quitting with a picture still with replayd (CAPTURE-40);
     SPACES-25, UI-23 and UI-24 couldn't run because of an invisible Notification Center window
     (UI-41). Both fixed; those three pass.
   - The 54 guided and 31 look cases haven't been run yet.

## In progress elsewhere

- **Windows version.** Released: 0.1.0 on 29 Oct 2026, at
  [github.com/invig/expanse-windows](https://github.com/invig/expanse-windows). It does what the Mac
  app does, apart from the gaps noted in that repo's
  [docs/spikes.md](https://github.com/invig/expanse-windows/blob/main/docs/spikes.md). The plan
  was [windows-port.md](windows-port.md).
- **Omarchy / Hyprland plugin** (`~/Code/ACTIVE/expanse-hypr`): catching up with the Mac
  features, plus a deep dive on jank.

## Ideas

- Tidy Up lines up bottom and right edges too (today: tops and lefts).
- Demo clips that show the pointer: resting in a corner, clicking a window.

## Open questions

Not decided yet.

- **Should Expanse keep windows from hiding under other windows** (mostly), as a tiling window
  manager does? Asked 1 Nov. Today overlaps are allowed: new windows, Tidy Up, screens you build
  and sizes picked zoomed out keep clear of other windows, but a window you drag (on the canvas or
  at 100%) or resize at 100% can sit over another.

## Won't do

- **Typing into windows while zoomed out.** That needs SIP turned off.
- **Hiding macOS's purple capture badge.** macOS draws it on captured windows; Expanse
  captures as little as it can instead.

## Done

- 0.1.43: The canvas over a full-screen app keeps the desktop picture instead of turning black, runs
  right up to the top of the screen so the app's tabs don't show above it, and takes no picture
  there, so protected video in that app isn't made to blink. The desktop picture waits for a Space
  change to finish and is only taken of a desktop at rest.
- 0.1.42: Tidy Up leaves zones alone: windows count as one group only when they're less than 80pt
  apart, down from 240pt, so zones you keep apart stay apart.
- 0.1.41: Settings is now a page of the menu bar panel, opened with the gear, instead of a window
  of its own: it opens over the canvas too, and Esc or the back arrow takes you back.
- 0.1.40: Low motion: glides, zooms and centring can jump straight to where they end (Settings ›
  Moving around). Expanse does this by itself when macOS's Reduce Motion is on, and the
  walkthrough's picture holds still too.
- 0.1.39: Quitting Expanse no longer makes macOS ask you to allow it again ("bypass the
  system private window picker"); after a notification, zooming out no longer opens the canvas
  under an invisible window.
- 0.1.38: Fill (the green button, Window › Fill, fn ⌃ F) grows a window right and down from
  its top-left on the canvas, so the windows above and to its left aren't covered, and Return to
  Previous Size puts everything back; the layout is saved even while windows keep changing, so
  a size you've just chosen isn't lost; Restore all windows works zoomed out; the Expanse tile
  stays on your desktop when a window is full screen; less CPU while macOS's capture service is
  stuck; `expanse://fit` and `zoom` do nothing at 100%.
- 0.1.37: A tab dragged out of Chrome or Brave is left alone while you hold the button, then
  goes beside its window; scrolling and pinching on the bare desktop at 100% open the canvas
  again, and a mouse wheel's slow notches no longer snap back; unplugging a display with the lid
  shut keeps your layout; the minimap and Spaces panel stay put after a full-screen app's Space.
- 0.1.36: A window grown back to its size after a smaller screen (unplugging a display, say)
  keeps that size, instead of sometimes slipping back to the smaller one; a notice that fades
  while the screen is locked goes away.
- 0.1.35: Build a screen zoomed out: drop a window on another's side or corner to tile them
  into halves and quarters of your screen, or select a few and press S, or press S with nothing
  selected for the screen tool; drag the gap between them to move the screen. Resize windows
  zoomed out by their edges, or right-click one for Fill, Half or Quarter screen, Same size as…
  and more; ⌘Z undoes it, and Settings has the gap between windows (20pt, 10pt or none). Windows
  side by side that fit the screen are one place: a hop, a click or ⌃⌥C shows the whole group.
  Esc and ⌥` go back to the window you were in, and scrolling at 100% no longer pulls you back
  to the window you were leaving. Fixes found by the new regression tests: steadier when the
  window server is busy, pictures come back after macOS restarts its capture service, windows
  macOS moves as a full-screen app comes back go back to their spots, and a window you minimise
  right after switching to it stays minimised.
- 0.1.34: Streaming video (Prime Video, say) no longer blinks every few seconds. Expanse kept
  taking pictures of windows at the screen's edge, and macOS blinks protected video at every
  one; now it takes nothing while you're at 100%.
- 0.1.33: Security fixes. An `expanse://` link from a web page runs only once you allow it, and
  a malformed one can't crash Expanse. Window titles in the layout file are hashed with a secret
  key kept in your Keychain, so the file alone can't be used to check a guessed title. Layout
  files, window sizes an app reports, and updates are all checked against sensible limits.
- 0.1.32: For about 20s after unlocking or waking the Mac, ⌘-Tab (or the Dock) to an app whose
  window was off screen did nothing, and an app opened then landed in the middle of the view, over
  your windows. Now the view goes to the app you switch to, and a new window goes beside what
  you're working on.
- 0.1.31: The menu bar icon opens a glass panel instead of a menu (the canvas at a glance, the
  main actions and switches, earlier layouts to restore, and a Take snapshot button); Open at Login
  and updates moved to a new Settings window. Restarts keep the layout: windows go back where macOS
  had them before apps quit, and windows the layout has no spot for (an app that opens at login)
  go beside what's in view instead of on top of it. A closed window's spot goes, and an app you
  quit and open later opens beside what you're working on; saved spots are only for a restart and
  windows still out of view. Steam's window is taken on (a helper process draws it); a new window
  its app is slow to list is picked up in seconds (was up to 30s); a window peeking in at the
  screen's edge no longer covers the minimap or Spaces panels.
- 0.1.30: Locking the Mac or sleeping its displays no longer moves windows (on 29 Oct macOS piled
  every parked window at one spot while the Mac was locked, and Expanse kept the pile as your
  layout); Restore Layout puts windows exactly where the snapshot had them.
- 0.1.29: At 100% the real desktop shows through, with clickable icons, macOS's shade under the
  menu bar and its dimming behind a filled window; the canvas opens onto a fresh picture of that
  same desktop (no dimmed copy left behind); a scroll at 100% snaps so windows aren't left cut
  off; hiding an app, then ⌘-Tab to it, glides to its window; Expanse's own Space tile goes back
  to 100%.
- 0.1.28: Sizes set with macOS's Fill, Moom or a keyboard shortcut stick, and a window that fills
  the screen keeps filling it.
- 0.1.27: New Finder windows open beside you instead of at an old Finder window's spot, and closing
  one keeps the view where it is; refused window scans back off instead of asking every 5s.
- 0.1.26: A stuck capture service (replayd) isn't swamped any more: scans back off, and captures
  wait for it to answer (overnight on 29 Oct, requests piled up in it until the screen froze); an
  app's loading box doesn't take its main window's spot; new windows go upward only as a last
  resort; a window in a column stays lined up after a display change and back.
- 0.1.25: Recovers when macOS restarts its capture service (windows no longer drop off the canvas,
  and new ones are still taken on); an app that opens again gets its windows' spots back; VM
  windows keep their spot when the VM changes resolution; clicking a window you can see keeps a
  view you placed.
- 0.1.24: A window back from full screen keeps its spot, instead of staying where macOS set it
  down.
- 0.1.23: Troubleshooting menu (Detailed Logging, Copy Logs for a Bug Report, Report an Issue);
  the log says why a window drops off the canvas.
- 0.1.22: Display changes keep every window's spot (round trips come back exactly, columns stay
  lined up); window names hidden unless turned on; release builds open at login; the canvas
  never covers another app's dialog.
- 0.1.21: New windows open beside the window they came from; VM and remote-screen apps size their
  own windows; apps that size in steps don't make the layout count as shrunk.
- 0.1.20: Tidy Up lines up each group where it is, and leaves groups in place.
- 0.1.19: Window tabs (Finder, etc.) keep the window's spot.
- 0.1.18: Liquid Glass minimap and Spaces panels, Restore Layout snapshots, layouts fitted
  when a monitor comes or goes, hidden apps' windows remembered across restarts.
