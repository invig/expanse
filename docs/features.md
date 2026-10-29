# Features

What we might build next. New requests go in as they come up, and finished work moves to Done.

## Bugs

- **Windows peeking in at the screen's edges** cover the minimap and Spaces panels (29 Oct), which
  sit on the backdrop under every window. Park a window that only shows a sliver, or float the
  panels above windows?
- **New windows not always picked up** (29 Oct): a window that's just opened sometimes doesn't
  make it onto the canvas. Which apps, and does it turn up later on its own? Catch one with
  Detailed Logging on.
- **Steam's window isn't recognised** (29 Oct): Expanse doesn't take it onto the canvas.
- **Window spots lost after a restart** (29 Oct): after rebooting the Mac, windows don't go back
  to where they were, so the layout isn't carried across a restart.

## Next up

1. **Window size snapping** (asked 28 Oct). Resize so grids of windows come out neat. Today
   Expanse only moves windows; resizing is whatever you do to the real window at 100%.
   - While you resize, edges snap to neighbouring edges and to the standard 20pt gap.
   - Sizes snap to match: the same width as the column, the same height as the row.
   - Maybe: resize handles on the canvas while zoomed out, and a way to even up a row or
     column in one go.
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
6. **Menu bar panel** (asked 29 Oct). The menu bar icon opens a glass panel instead of a menu, built
   30 Oct to design A on the Expanse Menu Redesign canvas, plus a Take snapshot button. Updates
   and Open at Login moved into a new Settings window. Not released yet: click through it first, then release.
7. **Fewer kept window spots** (asked 30 Oct). Built, not released. A closed window's spot goes,
   and an app you quit and open later opens beside what you're working on, not at an old spot.
   Saved spots are only for a restart: windows coming back at launch, and apps reopened in its
   first 3 minutes. Windows still out of view (hidden, minimised, another Space) keep theirs.
8. **Regression tests** (asked 29 Oct). A unit test for each problem we fix, so a later change
   can't quietly bring it back. There are no tests yet: the layout maths would move into its own
   target that tests can reach. Start with the recent fixes (the lock pile-up, Restore Layout,
   display changes and back).

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
