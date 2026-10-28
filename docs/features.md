# Features

What we might build next. New requests go in as they come up, and finished work moves to Done.

## Bugs

None open. Fixed, not yet released:
- Windows dropping off the canvas (seen twice on 28 Oct): when macOS restarted its capture
  service, Expanse dropped every window it was capturing and stopped scanning, so they never came
  back and new windows (a VM's) weren't taken on. It now recovers.
- An app that opens again (UTM, say) gets its windows' spots back, and the view goes to them.
- VM windows keep their spot when the VM changes resolution, instead of drifting off their line.
- Clicking a window you can see, after panning the view yourself, no longer recentres it.

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

## In progress elsewhere

- **Windows version.** The plan is in [windows-port.md](windows-port.md), built in its own session
  on a UTM VM.
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
