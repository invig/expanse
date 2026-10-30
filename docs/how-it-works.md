# How Expanse works

Expanse runs on a stock Mac with System Integrity Protection on. Everything below follows from that.

- **Camera.** Every window has a frame in canvas space, and a camera (an origin and a scale) maps the
  canvas to the screen. The layout is saved to `~/Library/Application Support/Expanse/`, along
  with a few snapshots taken 15 or more minutes apart for Earlier layouts in the menu bar panel.
- **At 100%, windows are real.** They sit exactly where the camera says, moved with the
  Accessibility API. Windows outside the view are *parked* in the bottom-right corner of the
  screen, with one pixel showing (the trick [AeroSpace](https://github.com/nikitabobko/AeroSpace)
  uses). A full-screen backdrop sits beneath all windows. It draws the desktop picture, and the
  parked windows where they belong on the canvas.
- **Zoomed out, windows are pictures.** The backdrop rises above everything and draws each
  window from its own ScreenCaptureKit stream. Desktop-independent window capture keeps working
  for covered and parked windows, so the whole canvas stays live. Panning and zooming only touch
  one Core Animation transform, so nothing reflows and it stays at 120 fps. The minimap and
  Spaces panels are system Liquid Glass (macOS 26 and later).
- **Gliding** between windows at 100% uses the same approach for a moment. The backdrop rises,
  with pictures exactly over the real windows, and the camera animates. The real windows then
  move once, hidden, on a background thread.
- **Capture only what can be seen.** Every stream costs the window server work, and macOS marks
  every captured window with a purple badge. So Expanse streams only the windows in view while
  zoomed out or gliding, when the backdrop covers them anyway. Those streams stop before the
  backdrop drops. At 100% nothing streams: each sliver of a parked window showing at the screen's
  edge gets one snapshot as it comes into view, and isn't refreshed after that. Every capture
  makes video that macOS protects (streaming services' DRM) blink on screen, wherever it's
  playing, so at rest Expanse captures nothing at all. Pictures are captured at the size they're
  drawn.
- **Sixteen streams at most.** The system service behind every screen capture on the Mac runs
  out of file descriptors at a few dozen streams, other apps' included. After that, new streams
  silently get no frames. So the sixteen most visible windows stream, and every other window in
  view is refreshed with one-off snapshots in turn. New windows get their first picture the same
  way. `defaults write com.invignation.expanse streamBudget -int 8` lowers the limit (a VM's
  service gives out sooner); nothing raises it.
- **Full-screen apps** get a Space of their own from macOS, so they aren't on the canvas. Expanse
  leaves their windows alone, and lists the Spaces (as the window server reports them, the list
  Mission Control shows) beside the minimap.
  - **Switching is instant.** Expanse posts a synthetic trackpad swipe that's faster than the Dock
    animates (InstantSpaceSwitcher's trick), under the canvas, which is on every Space and stays
    put. Then it makes the window key through the window server and raises it, the way AltTab
    reaches windows on other Spaces. That route also works when the swipe can't be made, say with
    the pointer on another display.
  - **Opened over a full-screen app,** the canvas switches back to its desktop as you pick a window.
    Leaving without picking one goes back to the app.
- **Display changes.** While macOS reshuffles windows after a display change, Expanse ignores
  their moves. Then it restores sizes and fits the layout to the new screen from the *home*
  layout, the full-size layout. Windows restored from the saved layout, at launch or after the
  lock screen, are fitted the same way.
- **Focus** switches through the Accessibility API, which lands in milliseconds instead of
  waiting on macOS's cooperative app activation.
- **Nothing waits on other apps.** Every Accessibility call that has to wait for an app's reply
  (moving, focusing, asking where a window is) runs off the main thread. Each app's windows get
  a thread of their own, so one busy app can't stall the canvas. Window scans only ask apps about
  windows that aren't where Expanse expects them. It stays smooth with 50+ windows open.

## Developing

```bash
./scripts/build.sh && open build/Expanse.app
log stream --level info --predicate 'subsystem == "com.invignation.expanse"'
```

`build.sh` signs with your *Apple Development* certificate if you have one, so the permissions
survive rebuilds. Without one it signs ad hoc. That works, but macOS asks for the permissions
again after every rebuild.

To publish a release (signed, notarised, universal), run `scripts/release.sh`; the script's
header covers the one-time setup. It also points the Homebrew cask in
[invig/homebrew-tap](https://github.com/invig/homebrew-tap) at the new release. Installed copies
pick it up from GitHub within a day; development builds are signed differently and never update.

Don't run a copy with a different signature from your development build (a release, say) on the
same Mac. It shares the app ID, and macOS's Accessibility permission for Expanse can get confused:
Expanse still reports itself trusted but sees no windows. To fix it, turn Expanse off and on
again in System Settings › Privacy & Security › Accessibility.

The log shows every window Expanse moves, resizes or follows, glide timings, and anything slow.
Development builds have debugging URL commands, off by default; turn them on with
`defaults write com.invignation.expanse debugURLCommands -bool true`. (A release ignores that
setting: any app could change it, then move other apps' windows through Expanse.) Then
`open "expanse://dump"` writes the full layout to the log, and `screen?w=1512&h=982` pretends the
display is that size. The others are `place`, `prefer`, `focus?id=` with a window ID,
`appearance?mode=light|dark`, and `update?install=1` to update without asking.
