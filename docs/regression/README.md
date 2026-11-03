# Regression tests

Every feature Expanse has, and every bug it has fixed, as a test case: 471 cases, from all 174
commits from 0.1.0 to 0.1.34 (26–30 Oct 2026) and the changes since. A bug fix's case says what
went wrong **before** the fix and what must happen **now**, so a later change can't quietly bring
it back. Every case has a test: unit tests for the logic, and end-to-end cases that drive the real
app (see Running them).

| Area | What it covers | Cases | Bug fixes |
|---|---|---|---|
| [NAV](navigation.md) | Canvas, zoom and navigation | 63 | 15 |
| [EDIT](arranging.md) | Arranging windows on the canvas, and screens you build | 34 | 3 |
| [PLACE](new-windows.md) | New windows and where they go | 18 | 12 |
| [TRACK](tracking.md) | Finding and following windows | 44 | 30 |
| [SIZE](sizes.md) | Window sizes | 20 | 9 |
| [PERSIST](layouts-and-restarts.md) | Layouts, restarts and snapshots | 43 | 22 |
| [DISPLAY](displays-lock-sleep.md) | Displays, lock and sleep | 29 | 22 |
| [SPACES](spaces-and-full-screen.md) | Full-screen apps and Spaces | 26 | 16 |
| [CAPTURE](capture-and-performance.md) | Capture and performance | 39 | 28 |
| [UI](panels-and-look.md) | Menu bar panel, minimap, Settings and the backdrop | 40 | 8 |
| [SETUP](first-launch.md) | First launch and permissions | 27 | 7 |
| [SUPPORT](troubleshooting.md) | Troubleshooting and logs | 11 | 0 |
| [UPDATE](updates-and-install.md) | Updates, release builds and install | 19 | 2 |
| [URL](url-scripting.md) | expanse:// scripting | 28 | 1 |
| [SEC](security.md) | Security hardening | 30 | 25 |
| | **Total** | **471** | **200** |

[Coverage](coverage.md) lists every commit with the cases that test it, or why none does (docs
only, a reverted experiment, an empty merge, a release commit).

## Running them

Every case has a test (`scripts/test-coverage.sh` checks it): a unit test for each case marked
**unit**, and an end-to-end case, a unit test of its logic, or both, for each case marked
**manual**. A test's name starts with its case's ID.

**Unit tests** (Tests/ExpanseTests, 503 of them, about a minute and a half). Run them before every commit:
```bash
scripts/test.sh
```
`scripts/test.sh --filter NAV` runs one area. They never touch real windows, your layout, logs
or the Keychain: windows are stand-ins, the display is pretend, and files go to temp folders.

**End-to-end cases** (Tests/Integration, 229). An app, Expanse Tests, drives a running
development build of Expanse with links, its own windows, other apps and real key and pointer
events, and reads back what Expanse did from its log. They move real windows, so run them in the
VM (expanse-demo), not on your desktop:
```bash
scripts/vm-integration.sh
```
That builds both apps, copies them into the VM, runs the 144 cases that need nobody, and copies
the report back to build/integration-vm/, with Expanse's log for each failed case beside it
(`NAV-17.log`: the VM keeps its detailed log only for minutes). `--all` adds the 54 guided cases
(it asks you to do something, such as lock the Mac or unplug a display, in a panel at the top of
the screen, then checks the result) and the 31 look cases (it sets something up and asks whether
it looks right). `--area NAV` or `--only NAV-03,URL-01` narrows it, `--repeat 3` runs the chosen
cases three times over (to tell a flaky case from a broken one), and `--keep-logs` keeps the log of
every case, passed ones too. A few long cases skip unless given time (`--timeout 800`); a few need
a Developer ID release (`--release /path/to/Expanse.app`).

The VM's window server stalls now and then (a frame, an event or a call held up for 100ms to
several seconds), so limits on smoothness and speed (`expectTiming`) don't fail a case there: a
miss is noted in the report beside the pass, and the rest of the case still has to pass. Judge
those on a Mac. Restart the VM before a full run (`tart stop expanse-demo`, then
`tart run expanse-demo`): after an hour or two of cases its window server is slower still. Keep
its window showing: macOS asks again whether Expanse may record the screen ("bypass the system
private window picker") every so often (in the VM, within the hour, even with the same build),
and until you click Allow its prompt sits in the middle of the screen and takes the cases'
clicks. While one is up, the runner skips each automatic case
with the reason ("macOS is asking something on screen"). On 1 Nov it came three complete runs
in a row just as TRACK-12 began, about 25 minutes in (twice after a VM restart, once without),
so something there may set it off. After Allow, `--only` with the skipped IDs finishes the pass.
The VM's disk is 60GB (`tart set expanse-demo --disk-size 60`, 1 Nov): at 41GB it filled up
partway through a run (macOS downloads several GB of assets by itself), and cases failed
saving files ("No space left on device"). `df -h /` in the VM shows what's left. A heavy app on this Mac (a game) slows
the VM too.

One-time VM setup: this Mac's SSH key in the VM (`ssh-copy-id admin@<VM address>`, the
image's password is admin); Expanse Tests switched on in the VM's System Settings › Privacy &
Security › Device Control and Data Access (Accessibility before macOS 27; `ExpanseTests.app
--args --ask-access` adds it to the list); and Expanse allowed to record the screen when macOS
asks. Builds signed with the same certificate keep these. In the VM, links opened over SSH don't
reach Expanse; the runner opens them from inside the VM's login session.

Watching the log while you test by hand (in zsh, plain `log` is a shell builtin):
```bash
/usr/bin/log stream --info --style compact --predicate 'subsystem == "com.invignation.expanse"'
```
Debug-only links (`dump`, `screen`, `place`, `prefer`, `snapshot`, `poweroff`, `focus?id=`,
`appearance`, `logging`, `copylogs`) need a development build with
`defaults write com.invignation.expanse debugURLCommands -bool true`; releases ignore them.
Expected results describe the code as of 0.1.34. A case's Note says when a later commit changed
the behaviour it was written for.

## Each case

```
## AREA-NN Title
- Type: Feature | Bug fix
- Area, Commits (with the version each shipped in)
- Before: bug fixes only, what went wrong
- Setup, Steps, Expected, Check in log (optional)
- Automate: unit (the function a test could call) | manual (why it needs a real Mac)
- Note (optional)
```

New cases go at the end of their area with the next number. Numbers are never reused or
renumbered, so a case ID in a commit message stays valid.

## How the tests work

- **Unit tests** reach Expanse's private code through `@_private(sourceFile:) @testable import
  Expanse`, which debug builds allow (Package.swift; release builds are unchanged). Windows are
  `ManagedWindow`s made from fake ScreenCaptureKit records (Tests/ExpanseTests/Support), so
  Accessibility finds nothing to move. A `TestCanvas` sits on a pretend display, layouts and logs
  go to temp folders, and nothing starts a scan, a capture or the overlay. Where a check couldn't
  be reached otherwise, the app has a small seam for tests (a parameter with today's value as its
  default, or code moved verbatim into a function), marked "Tests…" in its comment. A case's
  manual part, where it has logic that can be checked this way, has a test named "(logic)".
- **End-to-end cases** are `Case(id, title, kind) { t in … }` in Tests/Integration/Sources/
  ExpanseIntegration/Cases, one file per area. The harness (Harness.swift) gives each case links,
  Expanse's state from `expanse://dump`, waits on the log, test windows, fixture apps (more copies
  of Expanse Tests, as other apps), synthetic input, and the questions for guided and look cases.
  Between cases it closes everything it opened and puts Expanse back at 100%.
- A case's test failing means the behaviour changed. Where today's code already differs from a
  case's Expected, the test records a known issue (`withKnownIssue`) instead of failing; they're
  listed below.

## Known issues the tests record

The bugs the tests found when they were written (31 Oct) are fixed, and their cases now check the
fix: PERSIST-21 (an unchanged layout counted as changed), UI-11 (Welcome behind a window),
CAPTURE-21 (pictures frozen after replayd crashed), DISPLAY-01 (the end of a drag after a display
change), NAV-53 (the snap and a nearly screen-wide window) and SEC-01 (a pan link with a bad
number). SEC-22's wording was wrong, not the code. Mark a new one with `withKnownIssue` in a unit
test, or `known:` on an end-to-end case, until it's fixed.

None at the moment. SPACES-07's lost clicks (1–2 Nov: a click on a Spaces tile at 100% that
reached nothing) were a bug in Expanse, now fixed and checked by SPACES-25. Back on the desktop
from a full-screen app's Space, with another app in front, macOS can stop drawing the overlay at
100% while still listing it on screen, so the minimap and Spaces panel vanish and their clicks
fall through to the desktop picture. A glide shows the overlay again, which hid it most of the
time; there's no glide while Expanse settles after a display change (it doesn't follow focus
then), which is why it came straight after DISPLAY-18. An event tap on where the window server
sent each click, and a screenshot, found it.

NAV-49, which first ran in the VM on 31 Oct, looked like one (the keyboard in
the wrong window after a click) until its log showed the click landing on another window of the
case's, cut off at the same edge; the case now brings the window it clicks to the front.

- **SUPPORT-01** (catalogue wording): a glide's moves are logged as one `windows landed after
  …ms (apps)` line, not a `move …` line each (`commitAsync`); single moves still log `move`. The
  case checks for both.

### Writing end-to-end cases

What the first runs in the VM taught (Tests/Integration):

- A window of Expanse Tests' own can't be dragged by posted events: drag a fixture app's
  window (`t.fixture`).
- Since macOS 14 an app can't simply bring itself or another forward: use `bringForward(app)`,
  which goes through Accessibility and waits until the app is in front. A hidden app has to be
  shown first, as ⌘-Tab does.
- `expanse://dump` waits for a glide to finish (links run through `whenIdle`), so it can't look
  mid-glide: time a glide from its `glide timing` line instead.
- macOS can stop a dragged window a few points short of the pointer: compare against where the
  real window landed, not the pointer's path.
- Expanse only takes a resize as your chosen size more than 2s after a resize of its own (a
  glide's): wait that long before resizing. And a move in a window's first 5s on the canvas is
  taken for its app placing it late, and put back (`cameBack`): wait those out before moving or
  resizing a new window as you would (SIZE-04, SIZE-11).
- The VM has other apps' windows on its canvas: lay a case's windows out somewhere clear (a hop
  goes to the nearest window, whoever's it is), and don't count on which window gets focus when
  one closes or an app hides. Those windows wander on the canvas (by tens of thousands of points
  after a VM restart), so no fixed spot is clear for good: start from `clearSpot`, measured as
  the run starts. Not too far from them either: a restored layout zooms out to fit every window,
  and at the smallest zoom the screen spans only about 30,000pt.
- Expanse can place a new window on the canvas within 100ms of its opening, before the window
  server lists it: where macOS had it is `TestWindow.opened` (or `Fixture.opened`), not where
  the window server first shows it.
- The pointer is a window of the window server's own in its window list: leave it out when
  asking what's in front at a point (a click leaves it there).
- The window list says what's on screen, not what's drawn: a window macOS has stopped drawing
  is still listed (SPACES-25). For a click that goes nowhere, a listen-only event tap at
  `.cgAnnotatedSessionEventTap` reads the window and pid the window server sent it to
  (`.mouseEventWindowUnderMousePointer`, `.eventTargetUnixProcessID`), and a screenshot over
  ssh (`sudo launchctl asuser 501 sudo -u admin screencapture`) shows what was drawn.
- A wheel or pinch over the bare desktop, with no window under the pointer, goes to the front
  app with no window, not to the desktop: the same tap shows window 0 and that app's pid. When
  the front app is Expanse (after leaving the canvas at an empty part of it), only a local event
  monitor sees it; a global one sees other apps' events only (NAV-62).
- Zoomed out, a window's picture can lie under Expanse's panels in the bottom-right corner, which
  take the click: click it at `s.clickPoint(on: w.canvas)`, not its middle.
- After a relaunch (or a fit), the whole layout can come back shifted on the canvas: earlier
  display changes leave windows shown off their home spots, and a relaunch goes by home spots
  (DISPLAY-17 came back 120pt up). Check sizes and where windows are relative to each other.
- replayd ignores SIGTERM: `killall -KILL replayd` is a restart (launchd starts a new one).
- Two windows a gap apart that fit the screen together are a screen group (NAV-55): a hop
  between them only moves focus, and going to one frames both. Put windows more than 40pt apart
  when a case is about one window on its own.
- Check a timing with `expectTiming`, and on the typical run of several (the median) where it
  can, not every one: one stall in the VM shouldn't decide it, and waiting on an app slows every
  run.
- A case that goes round many times asks for longer than the default 90s: `Case(…, time: 180)`.
- Set `flags` on every mouse event you post (`[]` for none): left unset, it can pick up modifier
  flags from earlier keys, and a title-bar drag then doesn't move the window (TRACK-06, TRACK-21).
- macOS's "App Running in Background" notice puts a Notification Center window over the whole
  screen that takes clicks and drags; the runner closes it before the run and between cases.
- Expanse keeps the saved spots of windows that haven't come back and, for three minutes after it
  starts or resumes, gives them to windows of apps that have just launched, matched by app alone:
  every fixture is Expanse Tests. So the VM script clears Expanse Tests' closed windows from
  Expanse's layout before a run, and after a case that started or resumed Expanse the runner
  starts it again without them.
- After `expanse://pause`, wait with `untilPaused()`: pausing puts every window back through
  Accessibility on Expanse's main thread, and in the VM, just after windows moved, that has taken
  more than the 8s a dump is given.
- Expanse logs "capturing N of M" only when the number changes: mark the log before what
  changes it.
- A copy of an app that Expanse Tests opens counts as its request, so macOS hands the front back
  to Expanse Tests: opening from Finder, the Dock or Spotlight is a guided step.
- A press through Accessibility isn't your input, so macOS won't let Expanse come forward after
  it: click a button where Accessibility says it is.

## Questions found while writing them

Writing the cases and their tests against the code turned these up. They aren't confirmed bugs
yet:

- **The hot corner with a second display** to the right of the main one may fire at that
  display's top edge (Expanse uses the main display only, so this is untested).
- **A display change with many windows, on a slow window server:** each window macOS moves
  costs the main thread Accessibility reads (`AX.position`, `AX.isFullScreen`) and a window-server
  call for the Space (`Spaces.inFullScreenSpace`, in `realWindowChanged`). In the VM, with 67
  windows, that added up to freezes of 1 to 10s (DISPLAY-10). Asking for the Space once per batch
  of moves, not once per window, would cut most of it.
- **A 140s freeze as a window left full screen from another Space:** in SPACES-07 (VM, 1 Nov,
  once) the case's tidy-up took its window out of full screen while the desktop was showing
  (`toggleFullScreen` on a window whose Space isn't the one shown, which a person can't do).
  Expanse glided to it as it came back, and then neither Expanse's main thread nor the runner did
  anything for 140s. No sample was caught, so whether Expanse or the window server was stuck is
  open. The tidy-up now goes to the window's Space first; if it's seen on a Mac, `sample Expanse`
  during it would tell.
- **Seen once each on 1 Nov in the VM, passing since (in a complete run too):** in UI-11 Expanse
  quit itself (a normal quit, no crash report) between the walkthrough opening and the case
  pressing Quit; in CAPTURE-15 replayd was asked for 3 pictures during the minute at rest, after
  33 new windows. The logs don't say why; if one comes back, its saved log (`--keep-logs`) is
  where to start. Expanse now logs why it quits (`quitting: Quit in the menu bar panel`, `SIGTERM`, or `asked
  by <app> (pid …)` for a quit Apple event), so a repeat of UI-11's says who asked.
- **Pause and Quit hold Expanse up while apps are slow:** `restoreOriginals` moves every window
  back with Accessibility calls on the main thread, one after another, so with a busy app (or
  in a VM) Expanse answers nothing for seconds (URL-01 saw more than 8s). `commitAsync` already
  moves windows off the main thread; pausing could too, apart from quitting, which has to wait.
- **The window list on the main thread:** `canvasLevel` reads `CGWindowListCopyWindowInfo` to
  keep the canvas under any dialog: at the start of every glide, and every 0.5s while the overlay
  is up (`keepDialogsVisible`). On a Mac that's milliseconds; in the VM, with its window server
  busy, it took 20ms to over 1s a call (`slow: glide prep … level Nms`), and a sample during
  DISPLAY-10's 10s freeze found the main thread there 40% of the time. Reading the list on a
  background queue and keeping the level up to date would take it off the main thread.
- **Tidy Up before the layout is first fitted to a screen:** a window its app keeps a few points
  short of its chosen size (Terminal's rounding) makes its right-hand neighbour count as out of
  place, so Tidy moves the neighbour by the shortfall.
