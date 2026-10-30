# Regression tests

Every feature Expanse has, and every bug it has fixed, as a test case: 439 cases from all 174
commits, 0.1.0 to 0.1.34 (26–30 Oct 2026). A bug fix's case says what went wrong **before** the
fix and what must happen **now**, so a later change can't quietly bring it back.

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

- **Before a release:** every case in the areas the change touches. **Now and then, or before a
  big change:** all of them.
- Watch the log while you test; many cases name a line to look for:
  ```bash
  /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.invignation.expanse"'
  ```
  (In zsh, plain `log` is a shell builtin.)
- Debug-only links (`dump`, `screen`, `place`, `prefer`, `snapshot`, `poweroff`, `focus?id=`,
  `appearance`) need a development build with
  `defaults write com.invignation.expanse debugURLCommands -bool true`; releases ignore them.
- Expected results describe the code as of 0.1.34. A case's Note says when a later commit
  changed the behaviour it was written for.

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

## Automating them

218 cases are marked **unit**: their logic (layout maths, matching saved windows, link parsing,
layout-file checks, updater limits, title hashes) can be tested without real windows. There's no
test target yet. The first step is a library target the tests can reach, then those cases, most
recent fixes first (docs/features.md, Next up). The other 221 need a real Mac: displays,
Spaces, lock and sleep, other apps' windows, ScreenCaptureKit.

## Questions found while writing them

Writing the cases against the code turned these up. They aren't confirmed bugs yet:

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
