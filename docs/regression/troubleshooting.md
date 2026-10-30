# SUPPORT: Troubleshooting and logs

[All areas](README.md)

## SUPPORT-01 The log records every move, resize and glide
- **Type:** Feature
- **Area:** SUPPORT
- **Commits:** 363d854 (0.1.0)
- **Setup:** In Terminal: `log stream --level info --predicate 'subsystem == "com.invignation.expanse"'`
- **Steps:**
  1. Hop with ⌃→ to a window that isn't fully on screen.
  2. At 100%, drag a real window by its title bar.
  3. Press ⌥`, then T, then Esc.
- **Expected:** Lines appear for each: `glide to <App>[<id>]`; `move <App>[<id>] {x, y} -> {x, y} (asked {x, y})`; `follow <App>[<id>] moved to {x, y} (last placed …)`; `resize` or `fit size` lines for size changes; `hotkey 11 pressed` for ⌃→. App names appear, but not window titles.
- **Automate:** manual: reads the system log.

## SUPPORT-02 The log says why a window dropped off the canvas
- **Type:** Feature
- **Area:** SUPPORT
- **Commits:** 0da6343 (0.1.23)
- **Setup:** Expanse running.
- **Steps:**
  1. Open a new TextEdit window; then close it.
  2. A few minutes later, run `log show --last 15m --predicate 'subsystem == "com.invignation.expanse"' | grep -E "tracking|dropped"` (no `--info`).
- **Expected:** Both lines are there, kept on disk at notice level: `tracking TextEdit [<id>] <private>` when it was taken on, `dropped TextEdit[<id>]: not in the window list` when it went. The other reasons are `Accessibility says it isn't a standard window` and `layer <n>, on screen <bool>, <w>x<h>`, with ` (out-of-date scan)` added when the scan was out of date.
- **Automate:** manual: reasons come from live scans.

## SUPPORT-03 expanse://dump lists app windows that aren't on the canvas
- **Type:** Feature
- **Area:** SUPPORT
- **Commits:** 0da6343 (0.1.23)
- **Setup:** Debug commands on (a development build with `defaults write com.invignation.expanse debugURLCommands -bool true`). An app window on screen that Expanse doesn't take on.
- **Steps:**
  1. `open "expanse://dump"`
- **Expected:** After the usual `dump <App>[<id>] …` lines, each ordinary window (layer 0, at least 100pt wide, on screen, not Expanse's) that isn't on the canvas gets a line saying what the last check found about it.
- **Check in log:** `dump unmanaged <Owner>[<id>] standard=… pending=… age=<n>s` (or `never asked`) ` scanned=… fullScreen=… app=… recentlyRemoved=…`
- **Automate:** manual: reads the live window list.
- **Note:** The `regular=` field became `app=` in 4045597.

## SUPPORT-04 Detailed Logging writes Expanse's log to a file
- **Type:** Feature
- **Area:** SUPPORT
- **Commits:** 00fbfc7 (0.1.23), a2d80de (0.1.31)
- **Setup:** No `~/Library/Logs/Expanse/` folder.
- **Steps:**
  1. Menu bar icon › Troubleshooting (stethoscope) › Detailed Logging.
  2. Zoom out and in, hop a few times.
  3. Turn Detailed Logging off, hop again.
  4. Restart Expanse with it on.
- **Expected:** Step 1: toast "Detailed logging on"; `~/Library/Logs/Expanse/Expanse.log` starts with `<date time> [notice] detailed logging on (Expanse <version>)`. Step 2 adds lines in the form `yyyy-MM-dd HH:mm:ss.SSS [info] …`. Step 3: toast "Detailed logging off", last line `[notice] detailed logging off`, nothing after. Step 4: the setting is remembered and the item shows a checkmark.
- **Automate:** unit: LogFile.isEnabled / write (folder needs injecting for a temp dir).
- **Note:** At 00fbfc7 Troubleshooting was a submenu of the menu bar menu; since a2d80de it's the stethoscope button in the panel.

## SUPPORT-05 Copy Logs for a Bug Report, with Detailed Logging on
- **Type:** Feature
- **Area:** SUPPORT
- **Commits:** 00fbfc7 (0.1.23)
- **Setup:** Detailed Logging on, some activity logged.
- **Steps:**
  1. Troubleshooting › Copy Logs for a Bug Report.
  2. Paste into a text editor.
- **Expected:** Toast "Collecting logs…", then "Logs copied: paste them into a GitHub issue". The paste starts `### Expanse`, then bullets: `Expanse <version> (<build>), release|development build`, `macOS …, <model>`, `Displays: <w>×<h> @<n>x (usable …)`, `Accessibility: …, Screen Recording: …`, `Canvas: <n> windows, running|paused, auto-centre on|off, hot corner …`, `Desktop picture background …, window names …, detailed logging on`. Then a folded `<details><summary>Detailed log</summary>` holding the end of the log file, at most 45,000 characters, starting at a whole line.
- **Automate:** unit: LogFile.recent(maxCharacters:) | manual: clipboard and system info.

## SUPPORT-06 Copy Logs with Detailed Logging off uses this run's system log
- **Type:** Feature
- **Area:** SUPPORT
- **Commits:** 00fbfc7 (0.1.23)
- **Setup:** Detailed Logging off, an old `Expanse.log` still on disk from earlier.
- **Steps:**
  1. Troubleshooting › Copy Logs for a Bug Report; paste.
- **Expected:** Toast "Copied. For more, turn on Detailed Logging and try again." The log section is headed "System log for this run (Detailed Logging is off: turn it on for more)" and holds Expanse's system log lines since it started, as `<time> [info|notice|error] …`. The old file is not used. With nothing logged it says `(nothing logged)`.
- **Automate:** manual: OSLogStore for the current process.

## SUPPORT-07 Window titles stay out of the log file and the report
- **Type:** Feature
- **Area:** SUPPORT
- **Commits:** 00fbfc7 (0.1.23)
- **Setup:** Detailed Logging on. A window with a distinctive title, e.g. a TextEdit document named "Secret-Plan".
- **Steps:**
  1. Open, move and close the window.
  2. `grep -c Secret-Plan ~/Library/Logs/Expanse/Expanse.log`; Copy Logs and search the paste.
- **Expected:** The title appears nowhere; lines like `tracking TextEdit [<id>] <private>` show `<private>` in its place. App names, IDs and numbers are shown.
- **Automate:** unit: LogMessage interpolation (privacy defaults: private unless public, numbers and Bools public).

## SUPPORT-08 Show Log File in Finder and Report an Issue on GitHub
- **Type:** Feature
- **Area:** SUPPORT
- **Commits:** 00fbfc7 (0.1.23)
- **Setup:** No log file yet.
- **Steps:**
  1. Open Troubleshooting.
  2. Turn on Detailed Logging, reopen Troubleshooting, choose Show Log File in Finder.
  3. Choose Report an Issue on GitHub….
- **Expected:** Step 1: Show Log File in Finder is greyed out. Step 2: Finder opens `~/Library/Logs/Expanse/` with `Expanse.log` selected. Step 3: the browser opens https://github.com/invig/expanse/issues/new.
- **Automate:** manual: Finder and browser.

## SUPPORT-09 The log file is capped at 5 MB
- **Type:** Feature
- **Area:** SUPPORT
- **Commits:** 00fbfc7 (0.1.23)
- **Setup:** Detailed Logging has been on (so `Expanse.log` exists), then turned off.
- **Steps:**
  1. `head -c 5100000 /dev/zero | tr '\0' 'x' >> ~/Library/Logs/Expanse/Expanse.log`
  2. Turn Detailed Logging on, hop once.
- **Expected:** The over-5 MB file becomes `Expanse.1.log` (any older one is replaced) and a new, small `Expanse.log` takes the next lines. Copy Logs reads the newest file, then the one before if it needs more.
- **Automate:** unit: LogFile.write / rotate (maxBytes 5,000,000) with an injected folder.

## SUPPORT-10 Troubleshooting from the panel's footer
- **Type:** Feature
- **Area:** SUPPORT
- **Commits:** a2d80de (0.1.31)
- **Setup:** Expanse running; Detailed Logging off and no file in `~/Library/Logs/Expanse/`.
- **Steps:**
  1. Open the panel and click the stethoscope button.
  2. Choose Detailed Logging.
  3. Open the menu again; choose Copy Logs for a Bug Report, then paste somewhere.
  4. Open it again: Show Log File in Finder, then Report an Issue on GitHub….
- **Expected:** A native menu opens under the pointer, without closing the panel: Detailed Logging (unticked), Copy Logs for a Bug Report, Show Log File in Finder (greyed while there's no log file), a separator, Report an Issue on GitHub…. Detailed Logging ticks, shows the toast "Detailed logging on", and leaves the panel open. Copy Logs closes the panel and puts the bug report on the clipboard (toast). Show Log File selects Expanse.log in Finder; Report an Issue opens GitHub's new-issue page.
- **Automate:** manual: native menu and clipboard.

## SUPPORT-11 A window left off the canvas logs why, once
- **Type:** Feature
- **Area:** SUPPORT
- **Commits:** 4045597 (0.1.31), 08fca65 (0.1.31)
- **Setup:** Expanse running, Detailed Logging off. A second display if you have one; a menu-bar-only app with a titled settings window; an app with a floating panel or dialog.
- **Steps:**
  1. Open a window on the second display.
  2. Open the menu-bar app's titled settings window.
  3. Open the floating panel or dialog.
  4. Troubleshooting › Copy Logs for a Bug Report, and paste.
- **Expected:** Each window that's on screen but not taken on gets one notice line, kept in the system log (so it's in Copy Logs with Detailed Logging off): "not on the canvas: <App>[<id>]: it's outside the main display, at {{x, y}, {w, h}}"; "…: <App> isn't an app in the Dock (a menu-bar extra or background process)"; "…: not an ordinary window (<subrole>): it stays where its app puts it". A window its app doesn't list yet logs "its app doesn't list it as one of its windows (Accessibility) yet; asked again every 2s for a minute, then every 10s". Each window is logged once, not on every scan. Untitled windows of non-Dock apps (popovers) aren't logged.
- **Check in log:** "not on the canvas:".
- **Automate:** unit: CanvasController.noteSkipped (once per window ID).
- **Note:** The "doesn't list it yet" wording is from 08fca65; 4045597 said "asked again every 10s".
