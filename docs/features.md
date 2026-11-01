# Features

What we might build next. New requests go in as they come up, and finished work moves to Done.

## Not released yet

Fixed or built since 0.1.34, for the next release's notes:

- **Groups of windows as places** (Next up 7).
- **Screens you build, and resizing zoomed out** (Next up 1 and 8): drop a window on another's
  side or corner to make a screen of halves and quarters, or select 2–4 and press S, or use the
  screen tool (S with nothing selected); drag a screen's ring to move it whole. Drag a window's
  edges to resize it, or right-click for Fill / Half / Quarter screen, Same size as…, Back to its
  own size and, with several selected, Same width / height / size. ⌘Z undoes each. Settings ›
  Gaps between windows: 20pt, 10pt or none (EDIT-27 to EDIT-34, SIZE-15 to SIZE-19).
- **Scrolling at 100% is easier to steer**: the snap when a scroll ends carries on your way or
  tidies by at most 40pt, and no longer pulls you back to the window you were leaving (NAV-61).
- **Esc and ⌥` go back to the window you were in**, however much you moved around zoomed out
  (NAV-17).
- **Fixes the regression tests found** (31 Oct): an unchanged layout no longer counts as changed
  and pushes out an older snapshot (PERSIST-21); Welcome from the panel while zoomed out no longer
  opens behind a window (UI-11); pictures come back after replayd crashes while you're zoomed out,
  without moving the view (CAPTURE-21); the end of a drag in the 20s after a display change is
  followed (DISPLAY-01); a window nearly the screen's width is centred by the snap after a scroll
  (NAV-53); an `expanse://pan` link with a bad number is ignored, not half followed (SEC-01).
- **Steadier with a busy window server** (31 Oct, found running the regression tests in the VM):
  while the canvas is up, the check for dialogs reads the window list off the main thread (in the
  VM each read took up to a second, every half second, and Expanse froze for up to 10s); and
  zoomed out, only streams that stopped are restarted after a scan, not every start that timed
  out (which piled requests onto macOS's capture service). A display change while zoomed out
  keeps the sizes it fitted windows to (a slow scan from before the fit put the old ones back).
  A slow hop's start is now logged in parts (`slow: glide prep`), and opening the canvas logs
  `canvas up`. A window dragged on the canvas ends where you let go, even if the last moves were
  dropped; a window a scan catches on its way into the Dock comes back to its own spot; and windows
  macOS sets down elsewhere as a full-screen window comes back (or the Space changes) are put back,
  even when only a later scan notices, and even mid-glide (SPACES-23). Minimising a window just
  after Expanse brought it forward no longer brings it straight back out (PLACE-17). Pictures
  come back after macOS restarts its capture service just as streams are starting (requests it
  never answered held every capture back until Expanse restarted; CAPTURE-27), and an answer to
  a window scan already given up on is dropped even when it comes before the next scan begins
  (CAPTURE-30). Expanse logs why it quits (`quitting: …`). Centre window
  from the panel acts on the window you were in (UI-34), and a toast shown while the last one
  fades stays up (SUPPORT-06).

## Bugs

1. **To check** (found writing the regression tests, 30–31 Oct; not confirmed): Restore all
   windows while zoomed out doesn't update the windows' spots on the canvas; `expanse://fit` and
   `zoom` move the view at 100% without opening the canvas; capture may spin every 10ms while
   replayd is stuck; the Expanse tile may point at a full-screen Space just after a window goes
   full screen; the README's Questions section and how-it-works still name old menu items and
   `update?install=1`. Details in [regression/README.md](regression/README.md).

If a new window doesn't make it onto the canvas, the log says why (look for "not on the canvas"
in Copy Logs for a Bug Report).

## Next up

1. **Window size snapping** (asked 28 Oct). Resize so grids of windows come out neat. Today
   Expanse only moves windows; resizing is whatever you do to the real window at 100%.
   - While you resize, edges snap to neighbouring edges and to the standard 20pt gap.
   - Sizes snap to match: the same width as the column, the same height as the row.
   - Maybe: resize handles on the canvas while zoomed out, and a way to even up a row or
     column in one go.
   - Built 1 Nov (Not released yet, above) for zoomed out: edge and corner handles that snap to
     neighbours, the gap and screen halves; a right-click size menu; evening up a selection.
     Still to do: the same snapping when you resize a real window at 100%.
2. **Demo videos for the README.** Recorded in a clean macOS VM, so nothing personal is filmed.
   In progress.
3. **Minimap and Spaces polish**, left over from the UI hill climb:
   - the viewport keeps one accent ring at every zoom level, instead of turning into a grey box;
   - windows in view are drawn stronger than off-screen ones;
   - a press state on Space tiles, with the switch happening on mouse-up;
   - an open-hand cursor over the minimap, and at 100% a click goes to that spot.
4. **Multiple monitor support** (asked again 28 Oct). Today Expanse uses the main display only.
5. **Low-motion mode** (asked 28 Oct): animated screen moves turned off, so glides, zooms and
   centring jump straight to where they end. Probably on by default when macOS's Reduce Motion
   is on (Accessibility › Display), which Expanse doesn't follow yet.
6. **Regression tests** (asked 29 Oct). Built: every case in [regression/](regression/README.md)
   has a test. 503 unit tests (`scripts/test.sh`, about a minute and a half, all passing), and 229
   end-to-end cases that drive the real app in the expanse-demo VM (`scripts/vm-integration.sh`;
   `--all` adds the 85 that need you). A new fix adds its case and its test.
   - End-to-end, 1 Nov: in the last full run 128 of the 144 automatic cases passed and 12 skipped
     (a Developer ID release, a longer `--timeout`, a Dock that hides, or something covering the
     screen). Since then the rest are fixed and pass on repeat runs: TRACK-21, UI-23/24 (macOS's
     screen-recording prompt had been left up in the VM: it needs an Allow by hand), UI-34, NAV-49
     (the case clicked under another of its windows) and SPACES-23 (fixed in Expanse). Timing
     limits are noted rather than failed in a VM, and the runner keeps windows from earlier cases,
     and notices over the screen, out of the way.
   - The 54 guided and 31 look cases haven't been run yet.

7. **Groups of windows as places** (asked 31 Oct). Built 31 Oct (Not released yet, above):
   windows a gap or so apart that fit the screen together are one place. A hop to one frames the
   group, hops inside a group on screen only move focus, a click zoomed out or ⌃⌥C frames it, and
   hovering it zoomed out outlines it (NAV-55 to NAV-60).
8. **Build screens zoomed out** (asked 1 Nov). Built 1 Nov (Not released yet, above): put two to
   four windows into halves and quarters of a screen, three ways (drop zones, select and S, the
   screen tool), and resize windows zoomed out. A built screen is a group, so it gets all of 7.

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

## Won't do

- **Typing into windows while zoomed out.** That needs SIP turned off.
- **Hiding macOS's purple capture badge.** macOS draws it on captured windows; Expanse
  captures as little as it can instead.

## Done

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
