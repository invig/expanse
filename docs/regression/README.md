# Regression tests

Every feature Expanse has, and every bug it has fixed, as a test case: 439 cases from all 174
commits, 0.1.0 to 0.1.34 (26–30 Oct 2026). A bug fix's case says what went wrong **before** the
fix and what must happen **now**, so a later change can't quietly bring it back. Every case has a
test: unit tests for the logic, and end-to-end cases that drive the real app (see Running them).

| Area | What it covers | Cases | Bug fixes |
|---|---|---|---|
| [NAV](navigation.md) | Canvas, zoom and navigation | 54 | 12 |
| [EDIT](arranging.md) | Arranging windows on the canvas | 26 | 3 |
| [PLACE](new-windows.md) | New windows and where they go | 17 | 11 |
| [TRACK](tracking.md) | Finding and following windows | 42 | 28 |
| [SIZE](sizes.md) | Window sizes | 14 | 9 |
| [PERSIST](layouts-and-restarts.md) | Layouts, restarts and snapshots | 42 | 21 |
| [DISPLAY](displays-lock-sleep.md) | Displays, lock and sleep | 28 | 21 |
| [SPACES](spaces-and-full-screen.md) | Full-screen apps and Spaces | 24 | 14 |
| [CAPTURE](capture-and-performance.md) | Capture and performance | 38 | 27 |
| [UI](panels-and-look.md) | Menu bar panel, minimap, Settings and the backdrop | 40 | 8 |
| [SETUP](first-launch.md) | First launch and permissions | 27 | 7 |
| [SUPPORT](troubleshooting.md) | Troubleshooting and logs | 11 | 0 |
| [UPDATE](updates-and-install.md) | Updates, release builds and install | 19 | 2 |
| [URL](url-scripting.md) | expanse:// scripting | 27 | 0 |
| [SEC](security.md) | Security hardening | 30 | 25 |
| | **Total** | **439** | **188** |

[Coverage](coverage.md) lists every commit with the cases that test it, or why none does (docs
only, a reverted experiment, an empty merge, a release commit).

## Running them

Every case has a test (`scripts/test-coverage.sh` checks it): a unit test for each case marked
**unit**, and an end-to-end case, a unit test of its logic, or both, for each case marked
**manual**. A test's name starts with its case's ID.

**Unit tests** (Tests/ExpanseTests, 490 of them, about a minute). Run them before every commit:
```bash
scripts/test.sh
```
`scripts/test.sh --filter NAV` runs one area. They never touch real windows, your layout, logs
or the Keychain: windows are stand-ins, the display is pretend, and files go to temp folders.

**End-to-end cases** (Tests/Integration, 223). An app, Expanse Tests, drives a running
development build of Expanse with links, its own windows, other apps and real key and pointer
events, and reads back what Expanse did from its log. They move real windows, so run them in the
VM (expanse-demo), not on your desktop:
```bash
scripts/vm-integration.sh
```
That builds both apps, copies them into the VM, runs the 139 cases that need nobody, and copies
the report back to build/integration-vm/. `--all` adds the 54 guided cases (it asks you to do
something, such as lock the Mac or unplug a display, in a panel at the top of the screen, then
checks the result) and the 30 look cases (it sets something up and asks whether it looks right).
`--area NAV` or `--only NAV-03,URL-01` narrows it. A few long cases skip unless given time
(`--timeout 800`); a few need a Developer ID release (`--release /path/to/Expanse.app`).

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

- **PERSIST-21:** a layout that hasn't changed can still count as changed, so it's saved again
  and, once the newest snapshot is 15 minutes old, snapshotted, pushing out an older one.
  `CanvasController.save()` compares JSON made without `.sortedKeys`, and the key order varies
  between encodes (one value gave 6 different encodings in a run). Fix: `.sortedKeys`, as
  `LayoutStore.write` has.
- **NAV-53:** a window a little narrower than the screen isn't centred by the snap: it lands
  12–20pt from an edge, as the shorter of the moves that leave nothing cut off.
- **SEC-01:** `pan?dx=nan&dy=1` drops the nan but still pans by `dy`. The case expects the view
  left alone.
- **SEC-22:** a number that isn't finite can't be written in JSON; the nearest (`1e400`) makes
  the whole layout file unreadable, so it's ignored (as SEC-21), not just that entry. Safe; the
  case's wording needs changing.
- **UI-11** (end-to-end): zoomed out, the panel's Welcome opens the walkthrough at once, then
  leaving the canvas hands focus back to the window in view, which covers it.
  `AppDelegate.showWelcome` calls `controller.exit()` and `Onboarding.show` together; showing it
  from `exit(then:)` would wait. SETUP-07's zoomed-out half meets the same thing.
- **CAPTURE-21** (end-to-end): zoomed out, when replayd crashes the pictures stay frozen until
  the camera moves. A stopped stream only asks for a window scan, and `askAgain` →
  `updateStreamingSoon` returns while the canvas is up, so nothing starts the streams again. (Seen
  in the VM: six streams stopped, none restarted in 16s.)
- **DISPLAY-01** (end-to-end): in the 20s after a display change, only moves made while the
  mouse button is down count, and Expanse follows a drag at most every 100ms: the window's last
  stretch, after you let go, isn't taken, so its canvas spot ends a little short of the real window
  (26×15pt in the VM). Outside that time the final spot is caught (TRACK-21).
- **NAV-17** (end-to-end): leaving the canvas hands focus to the front window in view; when that
  one is cut off at the screen's edge, auto-centre takes Expanse's own hand-back for a focus change
  and glides to it, away from the middle you were looking at. (`viewPlaced` stops this after you
  move the view at 100%, not after moving it zoomed out.)
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
  glide's): wait that long before resizing.
- The VM has other apps' windows on its canvas: lay a case's windows out somewhere clear (a hop
  goes to the nearest window, whoever's it is), and don't count on which window gets focus when
  one closes or an app hides.
- replayd ignores SIGTERM: `killall -KILL replayd` is a restart (launchd starts a new one).
- Expanse logs "capturing N of M" only when the number changes: mark the log before what
  changes it.
- A copy of an app that Expanse Tests opens counts as its request, so macOS hands the front back
  to Expanse Tests: opening from Finder, the Dock or Spotlight is a guided step.
- A press through Accessibility isn't your input, so macOS won't let Expanse come forward after
  it: click a button where Accessibility says it is.

## Questions found while writing them

Writing the cases and their tests against the code turned these up. They aren't confirmed bugs
yet:

- **Restore all windows while zoomed out** moves the real windows, but their spots on the canvas
  stay where they were, so leaving the canvas may park them again (TRACK-09).
- **`expanse://fit` and `expanse://zoom?scale=` with the canvas closed** move the view at 100%
  without opening the canvas (URL-04, URL-05).
- **`expanse://update?install=1`** can't do anything in any build: releases ignore debug links,
  and development builds don't update (URL-19). docs/how-it-works.md still lists it.
- **The README's Questions section** still names "Restore Layout", "Restore All Windows" and
  "Welcome & Shortcuts", from before the menu bar panel. The panel says "Earlier layouts",
  "Restore all windows" and "Welcome". "Restore all windows" also only moves windows that are
  out of view.
- **The hot corner with a second display** to the right of the main one may fire at that
  display's top edge (Expanse uses the main display only, so this is untested).
- **Capture while replayd is stuck:** zoomed out with more than 10 windows to stream,
  `updateStreaming` seems to schedule another pass every 10ms for as long as the stall lasts,
  since starts held back never count as running (CAPTURE-31/32).
- **Pictures after replayd crashes, zoomed out:** `askAgain` → `updateStreamingSoon` returns
  early while the canvas is open, so streams a crash killed may stay down until the camera moves
  (CAPTURE-21 checks the catalogue's "pictures update again while staying zoomed out").
- **The Expanse tile right after a window goes full screen:** `canvasDesktop` is the Space of
  the front-most window on the canvas, which can briefly be the new full-screen window, so the
  tile (and `space?name=expanse`) would point at the full-screen Space.
- **Tidy Up before the layout is first fitted to a screen:** a window its app keeps a few points
  short of its chosen size (Terminal's rounding) makes its right-hand neighbour count as out of
  place, so Tidy moves the neighbour by the shortfall.
