# Expanse on Windows: research (2026-10-28)

## Verdict

Doable, and in places easier than macOS:
- **No permission prompts.** Moving windows needs no Accessibility grant.
- **Free live pictures.** DWM thumbnails cost nothing and show no capture indicator.
- **Full off-screen parking.** Windows can sit entirely off-screen.

Three areas are harder:
- **Our UI over live pictures.** Drawing anything on top of live window pictures is fiddly. The smooth route is an undocumented API.
- **Stale pictures.** Some parked windows stop painting.
- **Focus and admin windows.** Windows restricts focus changes, and admin (elevated) windows can't be moved at all.

Spaces don't carry over. Windows virtual desktops can only be switched through undocumented APIs, and full-screen apps don't get a desktop of their own.

**Recommended route:**
- **Stack:** C# / .NET 10, written fresh. Only the layout maths (~600 of 7,000 lines) is worth porting.
- **Dev machine:** a free UTM 5 Windows 11 on Arm VM on this Mac, driven over SSH the way the Omarchy port drives its VM.
- **Later:** a cheap physical x64 laptop for the things a VM can't test.

## a) What to set up here

This Mac is an M5 with 32 GB of RAM and 180 GB free. No hypervisor is installed yet; the Omarchy VM runs inside Try Omarchy.app's QEMU.

**Hypervisor: UTM 5** (free, open source, October 2026), on its QEMU backend, the same engine as Try Omarchy.
- Graphics: a new DirectX 11/12 driver, still experimental. That's the main risk.
- `utmctl exec` and `utmctl file push/pull` (with the guest agent) run commands and copy files; `utmctl` also does snapshots.
- No screenshot command: take them inside Windows over SSH, from a scheduled task in the logged-in session (apps started over plain SSH don't show on the desktop).

Fallback: VMware Fusion Pro (also free; `vmrun` has screenshots, but it's in maintenance mode and macOS 27 support is unconfirmed).

**Guest:**
- **Windows:** Windows 11 Pro on Arm, 26H2, from the [official ARM64 ISO page](https://www.microsoft.com/software-download/windows11arm64).
- **Resources:** 6 vCPUs, 16 GB of RAM, a 256 GB disk, and the "More Space" display mode so DPI isn't forced to 200%.
- **Licence:** each VM needs its own Windows 11 Pro licence (about $199). Unactivated Windows works, with a watermark and some settings locked, so it's fine for dev at first.
- **Tools:** Visual Studio 2026 (ARM64, with C++/x64 tools and the Windows SDK), .NET 10, Git, OpenSSH Server, and the [Virtual Display Driver](https://github.com/VirtualDrivers/Virtual-Display-Driver) for extra virtual monitors and mixed-DPI tests. Rust and Swift only if we pick them.
- **Arm vs x64:** build ARM64 for the VM. x64 builds run under emulation (Prism), so they're only a smoke test. Avoid DLL-injection hooks, because injected DLLs must match each target process's architecture. Out-of-process WinEvent hooks and low-level hooks are fine.

**Agent workflow**, the same shape as `expanse-hypr/scripts/vm.sh`:
- SSH in to build (`dotnet` or `msbuild`).
- A scheduled task in the logged-in session to launch the app and take screenshots.
- `utmctl` snapshots to reset.
- `scp` or a shared folder for files.

**Things the VM can't test:**
- Real GPU/DWM performance: frame timing is not representative.
- Precision-touchpad gestures, since the Mac trackpad doesn't arrive as one.
- Physical monitor hot-plug, sleep/resume, and high refresh rates.
- Hot corners: in a window, the pointer leaves the VM at the edges.
- Native x64.

Plan on a used x64 business laptop with a precision touchpad, plus one external monitor at a different DPI, once the core works.

**Untested and worth checking in week one:** whether DWM thumbnails and Windows.Graphics.Capture work inside UTM at all, and whether Ctrl+arrows reach the guest. macOS's own Ctrl+arrow shortcuts may need turning off.

### Setup steps (YOU = needs you)
1. **YOU:** install UTM 5 (`brew install --cask utm`, or from getutm.app). It may ask for your Mac password.
2. **Me:** download the ARM64 ISO and create the VM with the settings above.
4. **YOU:** finish Windows setup. It may insist on a Microsoft account. Use a dedicated one, not your personal account.
5. **YOU:** buy and enter a Windows 11 Pro licence, or skip this for now.
6. **Me:** install the tools with winget. **YOU:** approve the admin (UAC) prompts.
7. **Me:** set up OpenSSH with a key from this Mac (**YOU:** one admin prompt), install the UTM guest agent, and take a "clean" snapshot.
8. **Me:** write the build, launch, screenshot and reset scripts. First experiment: window pictures inside the VM.
9. **Later, YOU:** the x64 laptop and an external monitor. I repeat the SSH setup on it.

## b) Feature for feature

**Difficulty scale:** 1 means it's straightforward on Windows; 5 means it's hard, undocumented or unreliable there.

| Expanse feature | On Windows | Diff |
|---|---|---|
| Zoom out / dive in, hot corner, ⌥` | Full-screen overlay window (no-activate, topmost) drawn with DirectComposition. Poll `GetCursorPos` for hot corners. Hotkey via `RegisterHotKey`, but ⌥`'s natural equivalent, Alt+`, is the Japanese IME toggle, so default to **Ctrl+Alt+`** and make it rebindable. | 3 |
| Live window pictures | **DWM thumbnails** (`DwmRegisterThumbnail`): no copying, cheap for 50 windows, and no capture indicator (no purple badges). Catch: DWM draws them *over* our window, so our UI has to live in a second window above. Smooth camera moves need the **undocumented** `DwmpCreateSharedThumbnailVisual`, which hands back thumbnails we can animate in our own visual tree. Fallback: Windows.Graphics.Capture, which gives real textures we can blur but shows a yellow border unless the user consents, and costs about 0.5–0.8 GB of video memory for 30–50 windows. **Spike both in week one.** | 5 |
| 120 fps glides, then hand-back | Same design as macOS: animate the pictures, then move the real windows (`SetWindowPos` async / `DeferWindowPos`; there's no cross-process atomic move), then drop the overlay. Hand back on foreground plus the window's actual position, as we do now. | 3 |
| Parking off-screen | Allowed fully off-screen, unlike macOS's 1 px sliver. But Chromium and Electron apps stop painting when off-screen, so their pictures go stale. Other projects park in a 2 px strip, or "cloak" windows through undocumented calls. Parked windows still show in the taskbar and Alt-Tab, and picking one should glide to it, which also covers our auto-centre. `SetWindowPlacement` pulls off-screen windows back, so use `SetWindowPos`. | 4 |
| Ctrl+arrow hops | Ctrl+arrows is word-jump in every app, and Win+arrows is taken by Snap. Use **Ctrl+Alt+arrows**, rebindable. (Some old Intel drivers use it to rotate the screen.) | 2 |
| Focus a window when you click its picture | `SetForegroundWindow` only works for the foreground process or the one that last got input. A hotkey or a click on our overlay grants that, so start every glide from an input. Fallback: `AttachThreadInput` or a dummy keypress. | 3 |
| Window tracking (new, closed, moved, minimised, focus) | `SetWinEventHook` out-of-process, which is cheaper and fuller than macOS's Accessibility notifications. Which windows count: Raymond Chen's Alt-Tab rule, minus cloaked windows; UWP apps sit inside ApplicationFrameHost. **No persistent window ID**: handles get reused, so match saved layouts on app ID, exe path, window class and title, as we do with bundle ID and title hash. | 3 |
| Admin (elevated) windows | A normal process can't move, focus or close them. Either run Expanse elevated, use `uiAccess` (needs a signed exe in Program Files), or leave them alone. **Your call.** | 4 |
| Drag, snap, box-select, close, Tidy Up, auto-placing new windows, follow between screens, Restore Layout, minimap | Logic we already have. Port the maths (camera, nearest-window, derive/separate/gravity/clusters, snapping, layout matching, about 600 lines) to C#. Closing a window is `WM_CLOSE`. | 2 |
| Display changes / home layout | `WM_DISPLAYCHANGE`, `WM_DPICHANGED`, Per-Monitor V2 DPI awareness; work area from `GetMonitorInfo`. Windows 11's "remember window locations" setting moves windows on plug/unplug, so debounce and re-park, much like our settle period today. Mixed DPI means a canvas-to-screen mapping per monitor. Assume Windows also pulls parked windows back on display change (unconfirmed). | 3 |
| Spaces strip | Virtual desktops: the public API can only *read* (which desktop a window is on). Switching needs `IVirtualDesktopManagerInternal`, which is undocumented and changes between Windows builds. Full-screen apps have no desktop of their own; F11 is just a window the size of the monitor. Suggest a read-only first version: one canvas per desktop, and the strip shows desktops. | 3 read-only, 5 for full parity |
| Full-screen video (Brave, Chrome, Safari) | Simpler: a full-screen window is just a window covering the monitor. Detect it by comparing rects, and poll `SHQueryUserNotificationState` for D3D games. Never park it. | 2 |
| Pause / quit restores the original layout, crash recovery | `GetWindowPlacement` to record originals, plus a state file, as now. | 2 |
| Hidden apps keep their spots | Minimised windows: we get minimise/restore events and keep the spot. Windows has no "hide app". | 2 |
| Desktop picture as the canvas | `IDesktopWallpaper` for the image, or a DWM thumbnail of the desktop for a live one. | 2 |
| Glass panels | Mica or Desktop Acrylic via `DWMWA_SYSTEMBACKDROP_TYPE`, or WinUI 3's AcrylicBrush. There's no Liquid Glass equivalent, so it'll look Fluent rather than Apple. A custom refraction shader is possible on top of capture textures. | 2 (4 for a true glass look) |
| Pinch / ⌘-scroll zoom, two-finger pan | Inside our overlay: fine (DirectManipulation / pointer input). Global pinch (⌥ + pinch anywhere to zoom out) has no Windows API: only raw touchpad input plus our own recogniser, and the app underneath still sees the pinch. Suggest dropping global pinch and pointing users to Settings, which can map 3- and 4-finger gestures to our hotkey. | 2 in-overlay, 4 global |
| Leave Phone / FaceTime alone | An exclusion list (Phone Link, call windows). | 1 |
| Typing into a window while zoomed out | Same limit as macOS (no real window scaling). | n/a |
| Menu bar icon and menu | Tray icon (`Shell_NotifyIcon`; re-add it when Explorer restarts). | 1 |
| `expanse://` scripting | Register a URL protocol under `HKCU\Software\Classes\expanse`, with a single-instance mutex and pipe to forward commands. | 2 |
| Onboarding | Much smaller: no Accessibility or Screen Recording grants. Only the admin-windows choice, and capture consent if we use Windows.Graphics.Capture. | 1 |
| Auto-update, signing, Homebrew cask | **Velopack** for install and update (signs with signtool), **winget** in place of the Homebrew cask. Signing: Microsoft's Artifact Signing (~$10/month) takes individuals only in the US and Canada, and organisations only in the US, Canada, EU and UK with 3+ years of history. Otherwise buy an OV certificate. SmartScreen warnings fade as reputation builds over weeks; EV no longer skips that. **Check eligibility.** | 3 |

## Stack

**Recommended: C# / .NET 10**, in three layers:
1. **Engine:** a thread with its own message loop for hooks, hotkeys and moves, calling Win32 through CsWin32.
2. **Overlay:** a raw window with DirectComposition and D3D11, behind one "window picture" interface so DWM thumbnails or capture textures can slot in.
3. **Panels and settings:** WinUI 3, unpackaged, shipped with Velopack. This gets us Mica/Acrylic, proper text input and accessibility for free.

Similar C# projects already exist: The Infinity (WPF), Whim (WinUI 3) and PowerToys.

- **Runner-up: Rust + windows-rs.** Proven by komorebi and GlazeWM, but every bit of UI is hand-drawn.
- **Not Swift.** The toolchain works on Windows ARM64, but the WinUI bindings are stale (Windows App SDK 1.5-preview, March 2025), and the code we could share is small.

**Prior art to read first:**
- [Spatial Canvas](https://github.com/13auth/spatial-canvas): C++. Capture per window, 2 px parking strip, and parked state saved to a file for crash recovery.
- [win-infinite-desktop](https://github.com/RandomNam3/win-infinite-desktop): C++/Qt. Taskbar and Alt-Tab picks move the camera.
- [The Infinity](https://github.com/lokeswara-s/the-infinity): C#/WPF, DWM thumbnails.
- [robmikh/Win32CaptureSample](https://github.com/robmikh/Win32CaptureSample): the reference Windows.Graphics.Capture sample.
- [ADeltaX on shared thumbnail visuals](https://blog.adeltax.com/dwm-thumbnails-but-with-idcompositionvisual/).

## Biggest risks
1. **Our UI over live pictures:** the smooth route is undocumented, and the documented one brings a border and memory cost.
2. **Stale pictures:** parked Chromium/Electron windows stop painting, minimised windows give no frames, and Windows pulls parked windows back.
3. **Focus and admin windows:** foreground refusals, and elevated windows we can't move.
4. **Input:** no global pinch, our macOS shortcuts are taken, and low-level hooks are fragile.
5. **Spaces:** undocumented desktop switching that breaks between builds, or settle for read-only.

## Decisions for tomorrow
1. Hypervisor: UTM 5 (chosen, free); VMware Fusion as fallback.
2. Windows licence now, or run unactivated for dev.
3. Stack: C# / .NET 10 (recommended) or Rust.
4. Admin windows: leave alone, run elevated, or uiAccess.
5. Spaces: read-only first (recommended), or chase full parity.
6. Code signing route, which depends on eligibility.
7. When to buy the x64 laptop and monitor.

## First week, once the VM is up
1. **Spikes, in the VM:** DWM thumbnails vs shared thumbnail visuals vs Windows.Graphics.Capture. Check frame rate with 30 windows, and draw our UI on top.
2. **Spikes, in the VM:** park Chrome, VS Code and Explorer off-screen and see who keeps painting. Test `SetForegroundWindow` from a hotkey and from an overlay click.
3. Engine skeleton: enumerate and track windows, park and unpark, and a saved layout keyed on app ID, exe, class and title.
4. Port the layout maths with its tests.
5. Overlay with a camera and glides, then hand-back.

The key sources are linked inline; anything I couldn't confirm for 2026 is marked as unconfirmed.
