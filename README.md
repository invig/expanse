# Canvas

An infinite-canvas window manager for macOS. Your desktop becomes a pannable, zoomable
canvas; every window lives somewhere on it. Inspired by Sunlight
(https://x.com/deezel/status/2114386503312839087).

## Build and run

```bash
./scripts/build.sh && open build/Canvas.app
```

Needs Accessibility and Screen Recording (System Settings → Privacy & Security). The app is
signed with the local Apple Development identity so the grants survive rebuilds.

## Using it

| Input | Does |
|---|---|
| Scroll or pinch on empty canvas, ⌥`, ⌥ + pinch anywhere | Open the canvas |
| Two-finger scroll / drag background | Pan |
| Pinch, ⌘-scroll | Zoom at the cursor |
| Two-finger double-tap, `0`, `1`, `-`, `=` | Overview / fit all / 100% / zoom out / in |
| Drag a window | Move it (snaps to edges and centers; hold ⌘ to disable) |
| Click a window | Fly to it, centered at 100%, and use it |
| Hover × or ⌘W | Close the hovered window |
| Esc | Back to 100% where you are |
| ⌘-Tab / Dock to an off-screen window | The canvas jumps to it |
| Menu → Pause Canvas, or quit | Every window goes back to its original macOS spot and size |
| ⌥` while paused, or launch | The canvas comes back exactly as you left it |

Scripting: `open "canvas://toggle"` (also `enter`, `exit`, `fit`, `pause`, `resume`, `restore`, `dump`,
`screen?w=1512&h=982` to simulate a smaller display,
`zoom?scale=0.5`, `pan?dx=100&dy=0`, `focus?app=Safari`).

## How it works

- **Camera.** Each window has a frame in canvas space; a camera (origin + scale) maps canvas to
  screen. Layout is saved to `~/Library/Application Support/Canvas/layout.json`.
- **Live mode** (scale 1). Real windows sit where the camera says, moved with the Accessibility
  API. Windows outside the view are parked in the bottom-right screen corner (the AeroSpace
  trick). A full-screen overlay sits below all windows as the desktop backdrop.
- **Canvas mode.** The overlay rises above everything and draws each window from its own
  ScreenCaptureKit stream (`desktopIndependentWindow`, so covered and parked windows keep
  rendering). Pan/zoom only touches Core Animation layers: no window reflows. Capture resolution
  follows the zoom level.
- **Leaving canvas mode** animates to scale 1 and commits real window positions.
- **Switching in and out.** Each window's original macOS frame is recorded when Canvas first
  sees it. Quit (or SIGTERM) and pause put windows back there; launch and resume restore the
  canvas. The originals are saved too, so after a crash the next quit still returns windows to
  the right macOS spots.
- **Display changes.** Window tracking pauses while macOS reshuffles windows, then the canvas
  re-centers and re-places everything. Windows too big for the screen shrink to fit when focused
  and grow back on a bigger screen.
- AX observers follow windows you move by hand.

## Not yet

- Multi-display (main display only today; display size changes are handled).
- Interacting with windows while zoomed out. That would need real window transforms from
  inside Dock.app, which needs SIP disabled. Canvas deliberately stays no-SIP.
