# CAPTURE: Capture and performance

[All areas](README.md)

## CAPTURE-01 Zoomed out, windows are live pictures and never move
- **Type:** Feature
- **Area:** CAPTURE
- **Commits:** 0cdf466 (0.1.0), 6146145 (0.1.3), 77be218 (0.1.3)
- **Setup:** A video playing in a browser window; 3+ other windows.
- **Steps:**
  1. Zoom out, then pan and pinch around for a while.
- **Expected:** The video keeps playing in its picture on the canvas; other windows update as they change. No real window moves or reflows while you pan and zoom (they stay behind the canvas until you leave). With many windows in view, at most 16 are streamed; the rest refresh by one-off pictures about every 1.5s.
- **Check in log:** `capturing N of M windows, K more by snapshot`
- **Automate:** manual: ScreenCaptureKit.
- **Note:** The first commit streamed every window; 6146145/77be218 capped it (now 16, lowered with `defaults write com.invignation.expanse streamBudget -int 8`).

## CAPTURE-02 Pictures are captured at the size they're drawn
- **Type:** Feature
- **Area:** CAPTURE
- **Commits:** 0cdf466 (0.1.0), 3144b09 (0.1.0)
- **Setup:** Development build with debug URL commands on (`defaults write com.invignation.expanse debugURLCommands -bool true`, then restart Expanse).
- **Steps:**
  1. Zoom out to about 50%, wait a second, `open "expanse://dump"`.
  2. Zoom to about 10%, wait a second, dump again.
- **Expected:** Each window's `pic=` width roughly halves with each halving of the zoom: full pixel size near 100%, then 1/2, 1/4 … down to 1/16 of the window's pixel width, changing in those steps rather than continuously. Pictures look sharp at every zoom.
- **Automate:** unit: `CanvasController.pixelSize(for:)` steps (scale < factor × 0.7 halves the factor, to 1/16).

## CAPTURE-03 Diving into a window shows it sharp on arrival
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** d41ce2a (0.1.0)
- **Before:** Zoomed-out pictures are captured small. Diving into a window enlarged that low-resolution picture, so it arrived blurry until the real window took over.
- **Setup:** A window with small text.
- **Steps:**
  1. Zoom far out (press - a few times).
  2. Click that window.
- **Expected:** The text is sharp during the end of the zoom-in and on arrival. There's no blurry frame before the real window shows.
- **Automate:** unit: CanvasController.pixelSize(for:) with an animation heading to scale 1 gives full size.
- **Note:** 61e6e55 replaced this commit's mechanism: capture size follows where the camera is heading (viewScale), so windows being zoomed into start sharp.

## CAPTURE-04 At 100%, windows on screen carry no purple capture badge
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 29b2a32 (0.1.0), 3a1f218 (0.1.3), 2f6c592 (0.1.34)
- **Before:** Every window was captured all the time, so macOS's purple per-window capture badge sat over the traffic lights of on-screen windows at 100%.
- **Setup:** At 100% with several windows.
- **Steps:**
  1. Hop between windows with ⌃+arrows; zoom out and back.
  2. After each, look at the traffic lights of the windows on screen.
- **Expected:** Once the view has settled, no on-screen window has a purple badge.
- **Automate:** manual: the badge is drawn by macOS.
- **Note:** a23c303 stops streams before the overlay drops; since 3a1f218 nothing streams at 100% (CAPTURE-19).

## CAPTURE-05 With 50+ windows, zooming, panning and dragging stay smooth
- **Type:** Feature
- **Area:** CAPTURE
- **Commits:** 61e6e55 (0.1.3)
- **Setup:** 50+ windows. Names on. Log stream running.
- **Steps:**
  1. Pinch in and out, pan, and drag windows for a minute.
- **Expected:** Motion is smooth. Frames reach the screen in batches; window names only re-layout in 32pt steps while zooming; the minimap redraws windows only when they change.
- **Check in log:** few or no `slow: animation` and `slow: updating captures` lines.
- **Automate:** manual: real performance.

## CAPTURE-06 Zoomed out, only windows in view are captured
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 61e6e55 (0.1.3)
- **Before:** Every parked window was captured all the time, at full size: about 48 streams kept the window server at 110% CPU when idle.
- **Setup:** 50 windows. Log stream running.
- **Steps:**
  1. Zoom to show about 10 of them.
  2. Pan to another area.
- **Expected:** Only the windows in view (plus a small margin) are captured, nearest first. Pictures for windows coming into view arrive within a fraction of a second.
- **Check in log:** `capturing N of 50 windows, K more by snapshot`, with N + K about the windows in view
- **Automate:** unit: CanvasController.wantsCapture(_:in:) (private).

## CAPTURE-07 Going straight back to the canvas reuses its pictures
- **Type:** Feature
- **Area:** CAPTURE
- **Commits:** 61e6e55 (0.1.3), 6146145 (0.1.3), 3a1f218 (0.1.3)
- **Setup:** 20+ windows. Log stream running.
- **Steps:**
  1. Zoom out, press Esc, and zoom out again within 5s.
  2. Press Esc, wait 10s at 100%, then zoom out.
- **Expected:** 1: the second zoom-out shows live pictures at once (streams kept going for 5s). 2: about 5s after leaving, the streams stop and the menu bar's purple screen-capture dot goes away; zooming out later starts them again, showing the last pictures meanwhile.
- **Check in log:** `capturing 0 of N windows` about 5s after leaving the canvas.
- **Automate:** manual: needs ScreenCaptureKit streams.

## CAPTURE-08 Pictures are captured smaller the further out you zoom
- **Type:** Feature
- **Area:** CAPTURE
- **Commits:** 61e6e55 (0.1.3)
- **Setup:** 20+ windows. Activity Monitor › Memory.
- **Steps:**
  1. Zoom out step by step to the smallest zoom, then back in.
- **Expected:** Pictures look crisp at every zoom. Captures halve in size in steps down to 1/16, so memory falls when zoomed far out. Zooming back in, pictures are re-captured sharp once the camera has been still for about 0.3s.
- **Automate:** unit: CanvasController.pixelSize(for:) power-of-two steps down to 1/16.

## CAPTURE-09 Zoomed out over 50+ windows, no picture is frozen
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 6146145 (0.1.3), 77be218 (0.1.3)
- **Before:** replayd (which runs every ScreenCaptureKit stream on the Mac) runs out of file descriptors at around 50 streams; streams started after that succeed but never deliver a frame. Zoomed out over 53 windows, half the pictures were frozen.
- **Setup:** 55 windows with changing content (clocks, Terminal running `top`, videos). Log stream running.
- **Steps:**
  1. Zoom out to fit all and watch for 30s.
- **Expected:** Every picture updates. At most 16 windows stream (the glide's target first, then those most on screen); every other window in view is refreshed by snapshot, each about every 1.5s, about ten a second in all.
- **Check in log:** `capturing 16 of 55 windows, 39 more by snapshot`
- **Automate:** unit: CanvasController.streamBudget parsing (the ranking in updateStreaming is private).
- **Note:** The limit was 20 here and 16 from 77be218. `defaults write com.invignation.expanse streamBudget -int 8` lowers it (eb224e7); values above 16 are ignored (47ed782).

## CAPTURE-10 A new window's first picture appears straight away
- **Type:** Feature
- **Area:** CAPTURE
- **Commits:** 6146145 (0.1.3)
- **Setup:** Zoomed out over 30 windows.
- **Steps:**
  1. In Terminal: `osascript -e 'tell application "TextEdit" to make new document'`
- **Expected:** The new window appears on the canvas with its picture within about a second. Its first picture is a snapshot; it doesn't wait for a stream.
- **Automate:** manual: needs ScreenCaptureKit.

## CAPTURE-11 Hopping to a nearby window after using the canvas shows it sharp
- **Type:** Feature
- **Area:** CAPTURE
- **Commits:** 6146145 (0.1.3), 0229cb2 (0.1.3)
- **Setup:** 20+ windows.
- **Steps:**
  1. Zoom far out, press Esc, wait 5s.
  2. Press ⌃→ to a parked window next to the view.
- **Expected:** During the glide the window coming in is sharp, not an enlarged canvas thumbnail. At 100%, parked windows near the view are re-captured at full size in the background, nearest first.
- **Automate:** unit: CanvasController.pictureNeedsResizing(_:) and livePictureSize(for:) (private).
- **Note:** Since 0229cb2 only windows within half a screen of the view get full-size pictures (CAPTURE-14).

## CAPTURE-12 Glides only stream what's on screen at the start and the end
- **Type:** Feature
- **Area:** CAPTURE
- **Commits:** 6146145 (0.1.3)
- **Setup:** A window far away, with others in between. Log stream running.
- **Steps:**
  1. Hop to the far window.
- **Expected:** Only windows on screen where the glide starts and where it lands are streamed. Windows passed on the way show the pictures they already have.
- **Check in log:** `capturing N of M windows` stays small during the glide.
- **Automate:** manual: needs real streams.

## CAPTURE-13 Pictures keep moving after a zoom
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 6146145 (0.1.3)
- **Before:** Running streams were reconfigured for new sizes and frame rates. A stream asked to change size sends nothing until the change is through (seconds under load), so pictures froze for seconds after zooming.
- **Setup:** Zoomed out over 20 windows with changing content.
- **Steps:**
  1. Press - and = a few times, then stop.
- **Expected:** Pictures keep updating. About 0.3s after the camera stops, streams restart at their new sizes; no picture freezes for seconds.
- **Automate:** unit: WindowCapture.update(pixelSize:fps:) restarts the stream rather than reconfiguring it.

## CAPTURE-14 Window pictures take far less memory
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 0229cb2 (0.1.3)
- **Before:** Every window kept its last picture at full size for the backdrop and the canvas: with 53 windows, 750MB of frame buffers.
- **Setup:** 50+ windows. Activity Monitor › Memory.
- **Steps:**
  1. Zoom out and back a few times, then stay at 100% for 30s.
- **Expected:** Expanse uses roughly 160–200MB, not about 750MB. Windows within half a screen of the view keep full-size pictures; ones further away are kept at a quarter size. A snapshot keeps only its own buffer.
- **Automate:** unit: CanvasController.livePictureSize(for:) (private).

## CAPTURE-15 Expanse uses almost no CPU at rest
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** c30b1b3 (0.1.3), 3a1f218 (0.1.3)
- **Before:** A window scan costs ScreenCaptureKit about 70ms of LaunchServices lookups, and it ran every 2.5s: most of Expanse's 3.5% idle CPU.
- **Setup:** 30+ windows at 100%. Activity Monitor › CPU.
- **Steps:**
  1. Don't touch the Mac for 2 minutes.
- **Expected:** Expanse sits around 0.5–1% CPU and replayd under about 1%. No purple capture dot in the menu bar. The regular scan is only a safety net, every 5s.
- **Automate:** manual: real CPU measurement.
- **Note:** This commit's 2 fps refresh of parked windows' slivers was replaced by snapshots in 3a1f218, and by one picture per sliver in 2f6c592.

## CAPTURE-16 Other apps can still capture the screen while you're zoomed out
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 77be218 (0.1.3)
- **Before:** With 20 streams replayd peaked at 204 of its 256 file descriptors, leaving little room for screen sharing and the like.
- **Setup:** 50 windows.
- **Steps:**
  1. Zoom out over all of them.
  2. Start a QuickTime screen recording (or a screen share) and keep the canvas open for 30s.
- **Expected:** The other app's capture works, and Expanse's pictures keep updating.
- **Automate:** manual: needs another capturing app.

## CAPTURE-17 Interrupting a zoom stops capturing the path it would have taken
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 14c9218 (0.1.3)
- **Before:** Interrupting a canvas animation (a click or scroll during a zoom) left its capture region in place, so windows along the abandoned path kept streaming.
- **Setup:** Zoomed in on one area of a large canvas. Log stream running.
- **Steps:**
  1. Press 0 (fit everything) and scroll straight away to interrupt it.
- **Expected:** After the interruption, captures settle to the windows in view.
- **Check in log:** `capturing N of M windows` drops back to about the windows in view.
- **Automate:** unit: CanvasController.cancelAnimation clears pathRegion when not gliding.

## CAPTURE-18 Streams drop to the resting frame rate after a glide
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 14c9218 (0.1.3)
- **Before:** Streams restarted only for a new size. A big frame-rate change (a glide's 30 fps back to 2 at rest) took seconds to apply, if it did at all, so streams kept the glide's rate.
- **Setup:** Activity Monitor › CPU, replayd visible.
- **Steps:**
  1. Hop between windows, then stay at 100% for 5s.
- **Expected:** Lingering streams fall to 2 fps right after the glide, and replayd's CPU drops within a second or two. A stream restarts when its rate at least doubles or halves.
- **Automate:** unit: WindowCapture.restartIfResized rate rule (fps ≥ 2× or ≤ ½ the configured rate).

## CAPTURE-19 Nothing streams at 100%
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 3a1f218 (0.1.3)
- **Before:** At 100% the slivers of parked windows at the screen's edges were streamed, and each stream kept a pool of full-size buffers: 200MB for two big windows.
- **Setup:** Two big windows parked with slivers showing at the screen's edge. Activity Monitor › Memory. Log stream running.
- **Steps:**
  1. Leave the canvas and wait 10s.
- **Expected:** After the 5s linger no stream runs and the menu bar's purple dot goes away. Each sliver shows a picture taken as it came into view. Expanse's memory doesn't grow by hundreds of MB.
- **Check in log:** `capturing 0 of N windows`
- **Automate:** unit: CanvasController.updateStreaming gives a budget of 0 when not active (private).
- **Note:** This commit refreshed slivers with a snapshot every 3s. 2f6c592 (0.1.34) takes one picture as each comes into view and none after, so protected video stops blinking.

## CAPTURE-20 Streaming windows hold fewer picture buffers
- **Type:** Feature
- **Area:** CAPTURE
- **Commits:** 3a1f218 (0.1.3)
- **Setup:** 16+ big windows. Activity Monitor › Memory.
- **Steps:**
  1. Zoom out so 16 windows stream, and watch Expanse's memory.
- **Expected:** Each stream uses a pool of 4 buffers (was 5) and holds 2 (was 3), so memory while zoomed out is lower than before for the same windows.
- **Automate:** unit: WindowCapture.configuration queueDepth is 4; deliver keeps at most 2 samples.

## CAPTURE-21 Live pictures recover after replayd crashes
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 552ac0e (0.1.14)
- **Before:** replayd, which runs every screen capture on the Mac, crashes now and then. Requests it held never got an answer, so streams stayed "starting" for good and windows on the canvas stayed blurry or blank until Expanse was restarted.
- **Setup:** Zoomed out with several windows showing live (play a video in one).
- **Steps:**
  1. In Activity Monitor, find `replayd` and Force Quit it (macOS restarts it).
  2. Stay zoomed out for 15 seconds; zoom back to 100%, then out again.
- **Expected:** Within a few seconds of replayd coming back, the pictures update again. No window stays blank or frozen, and zooming out later shows live pictures. A stream that answers after Expanse gave up on it is stopped, not used.
- **Check in log:** `stream start for <id> timed out` for any start replayd never answered
- **Automate:** manual: needs replayd. WindowCapture.start's 5 s timeout and startToken could be unit-tested with a stubbed SCStream.
- **Note:** Later commits added holding back requests while three or more are overdue or scans get no answer (WindowCapture.overdue and replaydStuck, 0.1.26), and recovery from macOS restarting the service (0.1.25). Since 31 Oct (not released yet), zoomed out, streams that stopped by themselves start again after the next scan that's answered, without the camera moving; a start that only timed out isn't retried on every scan (in a VM that piled requests onto replayd and stalled the window server).

## CAPTURE-22 One-off pictures recover after replayd crashes
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 552ac0e (0.1.14)
- **Before:** A snapshot request replayd never answered held one of the few snapshot places for good, so windows refreshed by snapshots (beyond the 16 that stream, and new windows' first pictures) stopped updating.
- **Setup:** More than 16 windows in view when zoomed out, so some are refreshed by snapshots.
- **Steps:**
  1. Zoom out and Force Quit `replayd` in Activity Monitor.
  2. Wait 15 seconds, then pan across the canvas.
- **Expected:** The snapshot-refreshed windows update again. None stays blank or blurry for good.
- **Check in log:** `snapshot of <id> timed out`
- **Automate:** unit: WindowCapture.snapshot calls completion(false) once after replaydTimeout (5 s), and never twice.

## CAPTURE-23 No purple badge on a window after a hop
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** a23c303 (0.1.17)
- **Before:** After a ⌃+arrow hop, macOS's purple capture badge stayed on the traffic lights of the window the hop landed on (and others in view) for up to a second, because their streams were still running when the overlay dropped.
- **Setup:** Screen Recording granted. At 100%, three or more windows in a row on the canvas, auto-centre on.
- **Steps:**
  1. Click into the left-hand window.
  2. Press ⌃→ and watch the traffic lights of the window it lands on.
  3. Press ⌃→ several more times in quick succession, then ⌃← back.
- **Expected:** Each hop glides and lands with no purple badge over the traffic lights of any window on screen, not even briefly. Streams of the windows the hop lands on stop during the glide's last third, and the hand-back waits for them (never longer than a quarter of a second).
- **Check in log:** When the hand-back had to wait over 60ms: `hand-back waited <n>ms: <App> focused after <n>ms, windows landed after <n>ms, streams stopped after <n>ms`
- **Automate:** manual: the badge is drawn by macOS inside the app's window; WindowCapture.pause(stopped:) callbacks could be unit-tested with a fake stream.

## CAPTURE-24 No purple badge after zooming back in from the canvas
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** a23c303 (0.1.17)
- **Before:** Zooming back in restarted the streams of the windows in view at full size, so their purple badges showed for up to a second after the canvas dropped.
- **Setup:** Screen Recording granted, several windows on the canvas.
- **Steps:**
  1. Press ⌥` to zoom out (window pictures are live).
  2. Press ⌥` again (or Esc) to zoom back in.
  3. Zoom out again and click a window to glide into it.
- **Expected:** Both times the windows land at 100% with no purple badge on any window in view. During the zoom in, windows in the area being zoomed into stop streaming rather than restarting.
- **Check in log:** As CAPTURE-23 (`hand-back waited …` only when over 60ms).
- **Automate:** manual: needs ScreenCaptureKit and the macOS badge.

## CAPTURE-25 No purple badge after a display change puts windows back
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** a23c303 (0.1.17)
- **Before:** After a display change at 100%, the canvas dropped while the windows on screen were still being streamed, showing their purple badges.
- **Setup:** At 100%, windows on screen. A second display to plug or unplug, or debug commands on (a development build with `defaults write com.invignation.expanse debugURLCommands -bool true`).
- **Steps:**
  1. Change the display (unplug or plug in a monitor, or `open "expanse://screen?w=1440&h=900"`).
  2. Wait about 3s for Expanse to re-place the windows.
- **Expected:** Windows come back in place with no purple badge on any window on screen.
- **Check in log:** `display changed: …`
- **Automate:** manual: needs a display change and the macOS badge.

## CAPTURE-26 streamBudget lowers the number of live window streams
- **Type:** Feature
- **Area:** CAPTURE
- **Commits:** eb224e7 (0.1.21)
- **Setup:** Debug commands on (a development build with `defaults write com.invignation.expanse debugURLCommands -bool true`). `defaults write com.invignation.expanse streamBudget -int 4`, restart Expanse. Ten or more windows.
- **Steps:**
  1. Press 0 while zoomed out so every window is in view.
  2. `open "expanse://dump"`.
  3. Set `streamBudget` to 0, then 50, restart each time and repeat.
- **Expected:** With 4: at most four `dump …` lines show `capturing=true`; the others still update, as one-off pictures in turn. With 0 or 50: the default of 16 applies.
- **Automate:** manual: needs ScreenCaptureKit streams.
- **Note:** Values outside 1–16 are ignored since 47ed782; at eb224e7 any positive value was used.

## CAPTURE-27 Windows stay on the canvas when macOS restarts its capture service
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 86fbd72 (0.1.25)
- **Before:** When replayd restarted, every capture stream stopped and Expanse dropped every window it was streaming. They stayed off the canvas until Expanse restarted.
- **Setup:** Several windows on the canvas, zoomed out so they're streaming.
- **Steps:**
  1. In Terminal: `killall replayd` (it may need `sudo`).
  2. Wait 15s, zoom in and out.
  3. Close one window while zoomed out.
- **Expected:** Steps 1–2: every open window stays on the canvas and its picture comes back. Step 3: the closed window still drops off, once a scan confirms it.
- **Check in log:** `<App>[<id>]: its capture stopped; checking it's still open` for each; for step 3, `dropped <App>[<id>]: not in the window list`.
- **Automate:** manual: needs replayd restarted.
- **Note:** Since 1 Nov (not released yet), found by the end-to-end case in the VM: stream starts asked for just as replayd restarted never get an answer, and three of them held every capture back (CAPTURE-31) until Expanse restarted, so the pictures never came back. An overdue request now stops counting after as long as replayd had gone without answering, 10s at least, so pictures come back about 15s after a restart.

## CAPTURE-28 A scan with no answer is given up, so new windows are still taken on
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 86fbd72 (0.1.25)
- **Before:** A window scan waiting on ScreenCaptureKit when replayd restarted never got an answer, and no scan ran again. New windows (a VM's) were never taken on.
- **Setup:** As CAPTURE-27.
- **Steps:**
  1. `killall replayd` while Expanse is scanning (zoom out and in to trigger scans).
  2. Open a new window (a UTM VM, say) within a minute.
- **Expected:** The new window is taken on and placed beside its source within seconds.
- **Check in log:** If a scan hung: `window scan got no answer in 10s (macOS's capture service stuck or restarting?); the next waits 20s`, then `tracking <App> [<id>] …`
- **Automate:** manual: needs a hanging ScreenCaptureKit request.
- **Note:** The wait doubles after each unanswered scan since e249814 (at 86fbd72 it was always 10s).

## CAPTURE-29 Window scans back off while macOS's capture service is stuck
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** e249814 (0.1.26)
- **Before:** Overnight on 29 Oct replayd stopped answering window scans, and Expanse gave up after 10 s and asked again, every 10 s for three and a half hours.
- **Setup:** Expanse running with windows on the canvas; a log stream open: `log stream --level info --predicate 'subsystem == "com.invignation.expanse"'`.
- **Steps:**
  1. Make replayd stop answering: `killall -STOP replayd`.
  2. Leave it for at least 6 minutes, watching the log.
  3. `killall -CONT replayd`.
- **Expected:** Each unanswered scan doubles the wait before the next is given up on: 10 s, 20 s, 40 s, 80 s, 160 s, then about 320 s (about five minutes) and no longer. Once replayd answers, scans go back to normal and the next wait starts at 10 s again; windows opened meanwhile turn up.
- **Check in log:** `window scan got no answer in 10s (macOS's capture service stuck or restarting?); the next waits 20s`, then `…in 20s…; the next waits 40s`, and so on up to `…in 320s…; the next waits 320s`.
- **Automate:** manual: needs a real replayd that doesn't answer (the wait, `scanTimeout × 2^min(n, 5)`, could be pulled out of `CanvasController.sync` for a unit test).
- **Note:** `killall -STOP replayd` (replayd runs as you, no sudo) stops every app's screen capture until `killall -CONT replayd`; resume it promptly.

## CAPTURE-30 A late answer to a scan already given up on is dropped
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** e249814 (0.1.26)
- **Before:** When a stuck replayd answered at last, it could answer a backlog of scans at once; each answer to a scan Expanse had given up on still made it ask every app about its windows before being thrown away.
- **Setup:** As CAPTURE-29, with several apps and windows open.
- **Steps:**
  1. `killall -STOP replayd` and wait until at least three `window scan got no answer` lines have been logged.
  2. `killall -CONT replayd`.
  3. Straight away, toggle the canvas (⌥`) and hop with ⌃+arrows.
- **Expected:** Only the newest scan's answer is applied; answers to earlier scans stop before any app is asked about its windows. Expanse stays responsive while replayd catches up, and the canvas shows the windows as they are now.
- **Check in log:** Answers to given-up scans log nothing; after the resume, scans log one at a time, with no run of `slow: window scan took …` lines for the backlog. (A slow line counts from when its scan was asked for, so an applied answer to a given-up scan shows 10,000ms or more; new scans just after the resume can show a few hundred.)
- **Note:** Since 1 Nov (not released yet), found by the end-to-end case in the VM: an answer that came after its scan was given up but before the next scan began was still applied (the check only compared it with the newest scan, which it still was). Giving a scan up now drops its answer, whenever it comes.
- **Automate:** manual: needs replayd answering requests late, on its own thread (the check is `latestScan` in `CanvasController.sync`).

## CAPTURE-31 No more than three capture requests are left hanging in replayd
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** f615454 (0.1.26)
- **Before:** Expanse gave up waiting for a picture or a stream start after 5 s and asked again, but replayd kept every request: about 1,960 piled up overnight until it flushed them at once and froze the screen (it had crashed 17 times in the days before).
- **Setup:** Expanse running with a dozen or more windows; log stream open as in CAPTURE-29.
- **Steps:**
  1. `killall -STOP replayd`.
  2. Zoom out (⌥`) and pan around so Expanse wants pictures and streams of many windows; keep going for a minute.
  3. `killall -CONT replayd`.
- **Expected:** After a few requests time out (5 s each), no new picture or stream start is asked for: the timeout lines stop at a handful instead of growing every few seconds. When replayd answers one of the overdue requests, what was held back starts: streams come up and pictures refresh, with no freeze.
- **Check in log:** A few `stream start for <id> timed out` / `snapshot of <id> timed out` lines, then none until replayd is resumed.
- **Automate:** unit: `WindowCapture.canAsk` (false once `overdue` reaches 3, true again when an overdue answer arrives, and `askAgain` is called then).
- **Note:** Since 1 Nov (not released yet) an overdue request stops counting after a while (`WindowCapture.expiry`, CAPTURE-27): as long as replayd had gone without answering when it went overdue, 10s at least and 10 minutes at most. A stuck replayd gets three requests at a time at ever longer intervals, a hundred or so overnight; in step 2 the timeout lines come in threes, further and further apart.

## CAPTURE-32 Captures wait while window scans get no answer, and start when one does
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** f615454 (0.1.26)
- **Before:** While window scans went unanswered, pictures and stream starts kept being asked for, adding to replayd's backlog.
- **Setup:** As CAPTURE-31.
- **Steps:**
  1. `killall -STOP replayd` and wait for the first `window scan got no answer` line.
  2. Zoom out and pan to windows that weren't in view before.
  3. `killall -CONT replayd` and wait for the next scan to be answered.
- **Expected:** From the first unanswered scan until a scan is answered, Expanse asks for no pictures and starts no streams (windows newly in view keep their last picture). As soon as a scan is answered, the held-back streams and pictures start without any further action.
- **Automate:** unit: `WindowCapture.replaydStuck` true makes `canAsk` false; setting it back to false calls `askAgain` (which runs `updateStreamingSoon` and `pumpSnapshotsSoon`).

## CAPTURE-33 Window capture never asks for audio
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** f615454 (0.1.26)
- **Before:** The capture settings didn't switch audio off explicitly; each audio-capturing request also sets up an audio clock in replayd.
- **Setup:** Expanse running, Screen Recording allowed.
- **Steps:**
  1. Zoom out (⌥`) so windows stream; glide between windows with ⌃+arrows.
  2. Look at the menu bar's privacy indicators and Control Centre.
- **Expected:** Only screen capture is in use: the purple indicator, never the orange microphone one, and nothing of Expanse's captures audio.
- **Automate:** unit: `WindowCapture.configuration(pixelSize:fps:)` returns `capturesAudio == false` and `captureMicrophone == false` (the desktop picture's config in `Wallpaper.capture` has `capturesAudio == false` too).

## CAPTURE-34 Refused window scans back off
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 50844aa (0.1.27)
- **Before:** A refused scan (Screen Recording not allowed, or its approval waiting for you) was asked again every 5 s.
- **Setup:** Expanse running with Screen Recording in effect; log stream open as in CAPTURE-29.
- **Steps:**
  1. Make macOS refuse window scans: turn Expanse off under System Settings › Privacy & Security › Screen & System Audio Recording while it runs, or leave macOS's Screen Recording approval prompt for Expanse unanswered.
  2. Watch the log for at least 6 minutes.
  3. Allow Screen Recording again (relaunching Expanse if macOS asks).
- **Expected:** Each refusal makes the next scan wait longer: about 10 s, 20 s, 40 s, 80 s, 160 s, then about every 320 s (about five minutes), not every 5 s. No pictures or streams are asked for meanwhile. Once a scan succeeds, the wait resets and captures resume.
- **Check in log:** `SCShareableContent failed: <reason>` lines at those growing intervals.
- **Automate:** manual: needs macOS refusing ScreenCaptureKit (`scanRetryAt` in `CanvasController.sync`).
- **Note:** If macOS reports no Screen Recording access at all, `sync` doesn't scan in the first place (the `CGPreflightScreenCaptureAccess` guard from ac50e01), and no `SCShareableContent failed` lines appear: also correct.

## CAPTURE-35 The desktop picture isn't re-taken within 2 s, or while capture is stuck
- **Type:** Feature
- **Area:** CAPTURE
- **Commits:** 077d3dd (0.1.29)
- **Setup:** "Desktop picture background" on; log stream open as in CAPTURE-29.
- **Steps:**
  1. Toggle the canvas (⌥` twice) quickly, several times within 2 s.
  2. `killall -STOP replayd`, wait for a `window scan got no answer` line, then zoom out; then `killall -CONT replayd`.
- **Expected:** Step 1: the desktop is captured at most once every 2 s; the last picture shows meanwhile. Step 2: no desktop capture is asked for while scans go unanswered; the canvas shows the last picture.
- **Automate:** manual: timing against replayd (`enter`: `lastWallpaperRefresh > 2` and `WindowCapture.canAsk`).
- **Note:** 2f6c592 later removed the 5-minute timer refresh: the desktop is captured as the canvas opens, at launch, on a Space change and after a display change, never at rest.

## CAPTURE-36 Protected video doesn't blink while you're at 100%
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 2f6c592 (0.1.34)
- **Before:** Every capture makes macOS blink protected video. At 100% Expanse re-captured the slivers of parked windows at the screen's edge every 3 seconds (about 80 captures a minute), so Prime Video blinked every few seconds, in a window or full screen.
- **Setup:** Prime Video (or other DRM video) playing in Safari, in a window and then full screen; several parked windows with slivers showing at the screen's edges.
- **Steps:**
  1. Stay at 100% without touching anything for at least 80 seconds.
  2. Pause Expanse and watch another 80 seconds.
- **Expected:** No blinks; at rest Expanse captures nothing, so no purple screen-capture dot shows in the menu bar.
- **Automate:** manual: DRM video and the system's capture indicator.

## CAPTURE-37 A sliver gets one picture as it comes into view
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 2f6c592 (0.1.34)
- **Before:** At 100% the stand-in of a parked window at the screen's edge was re-captured every 3 seconds.
- **Setup:** A window whose content keeps changing (a clock, a playing video) next to the one you're in.
- **Steps:**
  1. Hop (⌃-arrow) so the changing window ends up as a sliver at the screen's edge.
  2. Watch the sliver for a minute; then zoom out.
- **Expected:** The sliver shows a picture taken as it came into view and doesn't change after that. Zoomed out, the window is live again.
- **Automate:** unit: CanvasController.updateStreaming and pumpSnapshots (pictureStale set once when a window joins the queue at 100%).

## CAPTURE-38 The desktop picture is captured as the canvas opens, not on a timer
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** 2f6c592 (0.1.34)
- **Before:** With Desktop picture background on, the desktop was captured every 5 minutes, even while paused, blinking protected video each time.
- **Setup:** Desktop picture background on; protected video playing.
- **Steps:**
  1. Stay at 100% for over 5 minutes.
  2. Change the desktop picture in System Settings, then zoom out (⌥`).
  3. Pause Expanse and switch Spaces.
- **Expected:** Step 1: no capture and no blink at the 5-minute mark. Step 2: the backdrop shows the new desktop picture as the canvas opens. Step 3: no capture while paused. A Space change while running, a display change, and turning the switch on still take a fresh picture.
- **Automate:** manual: desktop capture and DRM video.

## CAPTURE-39 Zoomed out, starts held back while replayd is stuck don't spin
- **Type:** Bug fix
- **Area:** CAPTURE
- **Commits:** unreleased (3 Nov)
- **Before:** Zoomed out with more than ten windows to stream, each capture pass starts ten and books the next pass 10ms later. While replayd wasn't answering, starts were held back and never counted as running, so a pass followed every 10ms for as long as the stall lasted (found writing CAPTURE-31 and CAPTURE-32).
- **Setup:** As CAPTURE-31, with 20 or more windows.
- **Steps:**
  1. `killall -STOP replayd`, wait for `window scan got no answer`, then zoom out (⌥`) and leave it for a minute; watch Expanse in Activity Monitor.
  2. `killall -CONT replayd`.
- **Expected:** Step 1: Expanse's CPU stays near idle. Step 2: streams start, ten a pass, as CAPTURE-32.
- **Automate:** unit: `updateStreaming` with replayd stuck queues no further pass (`moreStartsQueued`), and `askAgain` is what resumes.
