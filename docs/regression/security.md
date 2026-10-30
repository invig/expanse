# SEC: Security hardening

[All areas](README.md)

## SEC-01 A link with nan or inf can't crash Expanse
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** ac50e01 (0.1.0)
- **Before:** `open "expanse://zoom?scale=nan"` crashed Expanse.
- **Setup:** Zoomed out.
- **Steps:**
  1. `open "expanse://zoom?scale=nan"`, then `scale=inf` and `scale=-inf`.
  2. `open "expanse://pan?dx=nan&dy=1"`, then `dx=1e400`.
  3. `open "expanse://zoom?scale=0.5"`
- **Expected:** 1 and 2: Expanse keeps running and the view doesn't change. 3: zooms to 50%.
- **Check in log:** `url command zoom`
- **Automate:** unit: Camera.zoom(to:anchor:) and Camera.pan(by:) ignore non-finite input; the URL number() parser rejects them.
- **Note:** 47ed782 hardened malformed links further.

## SEC-02 Unexpected Accessibility answers can't crash Expanse
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** ac50e01 (0.1.0)
- **Before:** Expanse force-cast whatever an app returned for its focused window or close button to an Accessibility element. An app returning something else would crash Expanse.
- **Setup:** A day of normal use with many kinds of apps (Electron, Java, Qt, games).
- **Steps:**
  1. Switch between them, hop, close windows with × on the canvas.
- **Expected:** No crash.
- **Automate:** unit: AX.focusedWindow(pid:) and AX.close(_:) check CFGetTypeID before casting (needs a stubbed AX value).

## SEC-03 Window titles are hashed in the layout file and hidden in the log
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** ac50e01 (0.1.0), 47ed782 (0.1.33)
- **Before:** layout.json stored every window title in plain text (document names, mail subjects), and the log printed titles.
- **Setup:** A TextEdit document saved as "Secret Plan.txt", open on the canvas.
- **Steps:**
  1. Panel › Take snapshot (or wait for a save).
  2. `grep -rc "Secret Plan" ~/Library/Application\ Support/Expanse/`
  3. `log show --last 10m --predicate 'subsystem == "com.invignation.expanse"' | grep "Secret Plan"`
  4. Quit and relaunch Expanse.
- **Expected:** 2 and 3: no matches. Titles in the files look like `hmac:…` (release) or `sha256:…` (development build). `tracking` log lines show `<private>` for the title. 4: windows are still recognised and go back to their spots.
- **Automate:** unit: LayoutStore.titleKey(_:), and LayoutStore.read hashes plain titles from old files.
- **Note:** Releases key the hash with a secret in the Keychain since 47ed782.

## SEC-04 Debug link commands are ignored by release builds
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** ac50e01 (0.1.0), 47ed782 (0.1.33)
- **Before:** Any app could set `debugURLCommands` and then, through Expanse's links, move other apps' windows in a release.
- **Setup:** A release build (Developer ID signed). `defaults write com.invignation.expanse debugURLCommands -bool true`.
- **Steps:**
  1. `open "expanse://dump"`; `open "expanse://place?id=<a window id>&x=0&y=0"`; `open "expanse://snapshot"`.
  2. `open "expanse://focus?id=<a window id>"`, then `open "expanse://focus?app=Safari"`.
  3. `defaults delete com.invignation.expanse debugURLCommands`.
- **Expected:** Step 1: each is ignored. Step 2: `focus?id=` does nothing; `focus?app=Safari` still goes to Safari's front window. The debug commands are place, prefer, dump, screen, update, appearance, logging, copylogs, snapshot, poweroff.
- **Check in log:** "ignored debug URL command dump (debugURLCommands is off)".
- **Automate:** manual: needs a Developer ID–signed build (Updater.isRelease).

## SEC-05 Bad numbers in expanse:// links don't crash Expanse
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** f310f04 (0.1.8)
- **Before:** Converting a number that isn't a valid window ID or index trapped and crashed Expanse: `space?index=` with a huge value, or `place`/`prefer` with a negative or huge `id`. Any app or web page can open these links.
- **Setup:** Any build. For steps 4 and 5, a development build with debugURLCommands on.
- **Steps:**
  1. `open "expanse://space?index=99999999999999999999"`
  2. `open "expanse://space?index=2.5"`
  3. `open "expanse://space?index=-4"`
  4. `open "expanse://place?id=-1&x=0&y=0"`
  5. `open "expanse://prefer?id=1e12&w=800&h=600"`
- **Expected:** Expanse keeps running (the menu bar icon stays) and nothing switches, moves or resizes. Each link logs `url command <name>` and does nothing more.
- **Automate:** unit: the windowID(_:) and index(_:) helpers in AppDelegate.runURLCommand. They return nil for anything that isn't an exact whole number in range.
- **Note:** 47ed782 also rejects nan and inf, and limits index to 0–10000.

## SEC-06 expanse://focus?id= is ignored without debug commands
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** f310f04 (0.1.8)
- **Before:** Any app or web page could focus any particular window by its ID.
- **Setup:** A release build, with a TextEdit window's ID known (from an earlier dump on a development build, or from `CGWindowList` tooling).
- **Steps:**
  1. `open "expanse://focus?id=<id>"`
  2. `open "expanse://focus?app=TextEdit"`
- **Expected:** Step 1 does nothing: no glide and no focus change. Step 2 glides to TextEdit's front window and focuses it.
- **Automate:** unit: the "focus" branch of AppDelegate.runURLCommand. id is nil unless debugURLCommands is on.
- **Note:** Since 47ed782, debugURLCommands is honoured only in development builds.

## SEC-07 expanse://appearance is a debug-only command
- **Type:** Feature
- **Area:** SEC
- **Commits:** bf5aace (0.1.19)
- **Setup:** `defaults delete com.invignation.expanse debugURLCommands` (or a release build).
- **Steps:**
  1. `open "expanse://appearance?mode=dark"`
- **Expected:** Nothing changes.
- **Check in log:** `ignored debug URL command appearance (debugURLCommands is off)`
- **Automate:** unit: AppDelegate's debug command set and debugURLCommands (release builds always false since 47ed782).
- **Note:** bf5aace is otherwise the first-time-user README, docs/how-it-works.md, and the README hero's Space tile renamed Expanse.

## SEC-08 A link with a name given twice doesn't crash Expanse
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** A parameter name given twice made Expanse crash (building the parameter list trapped), and any web page can open these links.
- **Setup:** Expanse running at 100% with windows to the left and right.
- **Steps:**
  1. `open "expanse://nav?dir=left&dir=right"`.
  2. `open "expanse://zoom?scale=0.5&scale=2"`.
- **Expected:** No crash. The first value counts: step 1 hops left; step 2 zooms to 50%.
- **Automate:** unit: the query parsing in AppDelegate.application(_:open:) (Dictionary uniquingKeysWith, first wins).

## SEC-09 A huge number in a link doesn't crash Expanse
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** `expanse://layout?snapshot=1e300` crashed Expanse (converting the number to a whole number trapped).
- **Setup:** Expanse running with earlier layouts.
- **Steps:**
  1. `open "expanse://layout?snapshot=1e300"`.
  2. `open "expanse://space?index=1e300"`.
- **Expected:** No crash, and nothing happens: an index is a whole number from 0 to 10,000 or it's ignored.
- **Automate:** unit: index(_:) in AppDelegate.runURLCommand (range 0…10_000).

## SEC-10 The minimum integer in a link doesn't crash Expanse
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** `expanse://space?index=-9223372036854775808` crashed Expanse (subtracting one from the minimum integer overflowed).
- **Setup:** Expanse running; at least one full-screen app Space.
- **Steps:**
  1. `open "expanse://space?index=-9223372036854775808"`.
  2. `open "expanse://space?index=2"`.
- **Expected:** Step 1: no crash, no Space switch. Step 2 still switches to the second Space in Mission Control's order.
- **Automate:** unit: index(_:) in AppDelegate.runURLCommand.
- **Note:** The same commit stopped an empty `name=` matching a Space by name; Space names are never empty, so that has no visible effect.

## SEC-11 An invalid snapshot number does nothing
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** `layout?snapshot=abc` restored the newest layout, and `snapshot=1.5` the second newest.
- **Setup:** Expanse running with three earlier layouts; windows moved since the newest.
- **Steps:**
  1. `open "expanse://layout?snapshot=abc"`, then `snapshot=1.5`, then `snapshot=-1`.
  2. `open "expanse://layout"`, then `open "expanse://layout?snapshot=2"`.
- **Expected:** Step 1: nothing happens. Step 2: with no number the newest layout is restored; `snapshot=2` restores the oldest of the three.
- **Automate:** unit: the layout case in AppDelegate.runURLCommand.

## SEC-12 A link's hop delay is capped at 10 seconds
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** `nav?…&delay=` took any number of seconds, so a link could schedule a hop for any time ahead.
- **Setup:** Expanse running at 100% with a window to the right.
- **Steps:**
  1. `open "expanse://nav?dir=right&delay=99"` and time it.
  2. `open "expanse://nav?dir=right&delay=-5"`.
- **Expected:** Step 1 hops after 10 seconds. Step 2 hops straight away.
- **Automate:** unit: the nav case's clamp in AppDelegate.runURLCommand.

## SEC-13 Unknown link commands are ignored without logging their name
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** Any name after `expanse://` was logged as given, and would have gone into the question a web page's link gets.
- **Setup:** Expanse running.
- **Steps:**
  1. `open "expanse://bogus?x=1"`.
  2. From a web page in Safari, open `expanse://<made-up name>`.
- **Expected:** Nothing happens and no question is asked. Only known commands run: toggle, centre/center, enter, exit, fit, restore, tidy, layout, welcome, menu, nav, pause, resume, zoom, pan, space, focus, and the debug ones.
- **Check in log:** "ignored unknown URL command" (the name isn't in the line).
- **Automate:** unit: AppDelegate.commands allow-list.

## SEC-14 A link from a web page asks before it runs
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** A web page's expanse:// link ran straight away once the browser let it through, so a page could rearrange windows or switch apps while you typed.
- **Setup:** Expanse running at 100%. A local HTML page with `<a href="expanse://tidy">Tidy</a>` open in Safari.
- **Steps:**
  1. Click the link; allow Safari to open Expanse.
  2. In Expanse's question, click Don't Allow.
  3. Click the link again; this time click Allow.
- **Expected:** Expanse comes forward with "A web page in Safari wants Expanse to run “tidy”" and "Links from web pages can move your windows and switch apps. Allow it only if you clicked the link yourself, expecting this.", buttons Don't Allow (default) and Allow. Don't Allow: nothing happens. Allow: Tidy Up runs. It asks every time. Any browser counts (an app that opens https links, by bundle ID, its helper processes included).
- **Check in log:** "url command tidy from Safari"; after Don't Allow, "URL command tidy from a web page in Safari: not allowed".
- **Automate:** manual: needs a real browser sending the Apple event.

## SEC-15 A web page's link while zoomed out is refused without asking
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** A web page's link ran whatever you were doing, zoomed out included.
- **Setup:** Chrome, with a local page whose script opens `expanse://tidy` 5 seconds after load; Chrome set to always allow the page to open Expanse links.
- **Steps:**
  1. Load the page and zoom out (⌥`) within 5 seconds.
- **Expected:** No question appears (the canvas would cover it) and nothing runs.
- **Check in log:** "URL command tidy from a web page in Google Chrome: not allowed".
- **Automate:** manual: needs a browser and the canvas up.

## SEC-16 welcome and menu links from a web page run without asking
- **Type:** Feature
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Setup:** Expanse running; a local page in Safari with links to `expanse://menu` and `expanse://welcome`.
- **Steps:**
  1. Click the menu link (allow Safari's prompt).
  2. Click the welcome link.
- **Expected:** No question from Expanse: the menu bar panel opens, then the walkthrough opens.
- **Check in log:** "url command menu from Safari".
- **Automate:** manual: needs a real browser.

## SEC-17 Links from scripts and other apps run without asking
- **Type:** Feature
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Setup:** Expanse running at 100%.
- **Steps:**
  1. In Terminal: `open "expanse://tidy"`.
  2. Run the same link from Shortcuts or Raycast.
- **Expected:** Tidy Up runs straight away each time; no question.
- **Check in log:** "url command tidy" with no "from …".
- **Automate:** manual: Apple event sender detection.

## SEC-18 Debug link commands work in a development build when turned on
- **Type:** Feature
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Setup:** A development build.
- **Steps:**
  1. `open "expanse://dump"` with the setting off.
  2. `defaults write com.invignation.expanse debugURLCommands -bool true`; `open "expanse://dump"`; `open "expanse://focus?id=<an id from dump>"`.
- **Expected:** Step 1 is ignored. Step 2: dump writes the layout to the log, and focus?id= goes to that window.
- **Check in log:** "dump viewport=…".
- **Automate:** manual: URL dispatch in the running app.

## SEC-19 Absurd window sizes and positions from an app are ignored
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** A position or size an app reported through Accessibility was taken as given: NaN, infinity or huge values wrecked the layout, and converting them to whole pixels crashed Expanse.
- **Setup:** A test app whose window reports an Accessibility position or size of NaN, infinity, or beyond ±1,000,000.
- **Steps:**
  1. Open the test app's window with Expanse running; zoom out and back; hop to it.
- **Expected:** No crash; the value is treated as unknown (no position or size), and the rest of the layout is unaffected.
- **Automate:** unit: AX.position and AX.size via AX.plausible (finite, |v| ≤ 1,000,000).

## SEC-20 Capture sizes are capped
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** A capture was configured at whatever pixel size the window implied; NaN, infinity or a huge number crashed Expanse.
- **Setup:** A test window whose size works out to more than 16,384 pixels, or NaN.
- **Steps:**
  1. Zoom out so the window streams, and back.
- **Expected:** No crash; each side of a capture is between 2 and 16,384 pixels, and a non-finite size becomes 2.
- **Automate:** unit: WindowCapture.configuration(pixelSize:fps:).

## SEC-21 A layout file with an absurd view position is ignored
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** Whatever layout.json said was used: an absurd camera position put the view millions of points away.
- **Setup:** Quit Expanse; back up `~/Library/Application Support/Expanse/layout.json`.
- **Steps:**
  1. Set `"cameraX"` to `5000000` and save.
  2. Launch Expanse.
- **Expected:** The file is ignored as if there were no saved layout: no crash, windows are taken on where macOS has them, and the next save replaces the file. The same check applies to snapshot files restored from the panel.
- **Automate:** unit: LayoutStore.load(_:) on a snapshot fixture (returns nil).

## SEC-22 Out-of-range numbers in a layout file are dropped
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** Every number in layout.json was taken as given, and the windows it moved were other apps'.
- **Setup:** Quit Expanse; back up layout.json; two apps with windows in it, both still open.
- **Steps:**
  1. Set window A's `"x"` to `5000000`. Set window B's `"w"` to `-100`. Set `"centerX"` to `1e9`.
  2. Launch Expanse.
- **Expected:** A's entry is left out: A is placed as a window the layout has no spot for (beside what's in view, PERSIST-42). B goes back to its spot but keeps its current size. The view comes from cameraX/cameraY (the centre is dropped). Any position or size beyond ±1,000,000 or not finite, and any size ≤ 0, counts as out of range; a bad home, preferred size, original frame or fitted size is dropped the same way, keeping the rest of the entry.
- **Automate:** unit: LayoutStore.load(_:) on a fixture with bad fields.

## SEC-23 Old plaintext titles in a layout file are hashed
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** A title stored as plain text by an older version stayed in layout.json through later saves while its window didn't come back.
- **Setup:** Quit Expanse; back up layout.json. Add to it (or edit) an entry for an app that isn't running, with `"title" : "Secret plan.txt"`.
- **Steps:**
  1. Launch Expanse and move a window, so the layout is saved.
  2. Within 3 minutes, `grep -c "Secret plan" ~/Library/Application\ Support/Expanse/layout.json`.
- **Expected:** 0: the entry is still there but its title is a hash (`hmac:` in a release, `sha256:` in a development build). Titles already starting `hmac:` or `sha256:` are left alone. A window whose real title matches a plaintext entry still finds its spot.
- **Automate:** unit: LayoutStore.load(_:) (titles hashed with titleKey).

## SEC-24 The stream limit can only be lowered
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** `streamBudget` took any positive number, so any app could raise it and starve every other app's screen captures.
- **Setup:** A development build with `debugURLCommands` on; 25+ windows that fit in view when zoomed out.
- **Steps:**
  1. `defaults write com.invignation.expanse streamBudget -int 64`; relaunch; zoom out; `open "expanse://dump"`; count `capturing=true`.
  2. Repeat with `-int 8`, then `-int 0`.
  3. `defaults delete com.invignation.expanse streamBudget`.
- **Expected:** 64: at most 16 windows stream. 8: at most 8. 0 (or anything outside 1–16): 16.
- **Automate:** unit: the streamBudget rule in CanvasController ((1...16) or 16).
- **Note:** Read once at launch.

## SEC-25 An update GitHub lists as too big isn't downloaded
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** The release's zip was downloaded whatever its size.
- **Setup:** A release build and a stand-in for GitHub's latest-release answer whose `Expanse-<version>.zip` asset has `size` over 64 MB (or no size).
- **Steps:**
  1. Settings › Check Now.
- **Expected:** Nothing is downloaded; "Couldn't check for updates" with "GitHub didn't say which release is the latest."
- **Check in log:** "update check failed: no release found".
- **Automate:** unit: Updater.release(from:) on JSON fixtures (size ≤ 64 MB accepted; bigger or missing → nil).

## SEC-26 A download that grows past the limit is stopped
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** The download ran to the end however many bytes came.
- **Setup:** As SEC-25, but the asset is listed small and the server sends more than 64 MB (or a Content-Length above it).
- **Steps:**
  1. Settings › Check Now.
- **Expected:** The download is cancelled as soon as more than 64 MB has arrived (or is announced); "Couldn't download Expanse <version>". Nothing is unpacked.
- **Check in log:** "update download stopped at N bytes (expected M): more than a release".
- **Automate:** unit: LimitedDownload.start against a local test server.

## SEC-27 A zip that would unpack too big isn't unpacked
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** Any downloaded zip was unpacked with ditto before its signature could be checked.
- **Setup:** As SEC-25, with a zip under 64 MB whose directory (`zipinfo -t`) says over 256 MB uncompressed or over 10,000 files; and one zipinfo can't read.
- **Steps:**
  1. Settings › Check Now with each zip.
- **Expected:** Not unpacked; the temporary folder is removed; "Couldn't download Expanse <version>".
- **Check in log:** "update <version> not unpacked: N bytes, unpacked B bytes in F files" (or "unpacked unknown").
- **Automate:** unit: Updater.unpackedSize on fixture zips.

## SEC-28 Unpacking an update stops after a minute
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** Unpacking had no time limit: a zip claiming one size and unpacking to far more could run on.
- **Setup:** As SEC-25, with a zip that takes ditto more than 60 seconds to unpack.
- **Steps:**
  1. Settings › Check Now and wait.
- **Expected:** ditto is stopped after 60 seconds; the update isn't offered or installed and the temporary folder is removed; "Couldn't download Expanse <version>".
- **Automate:** manual: needs a slow zip and the real ditto.

## SEC-29 Release builds key title hashes with a secret in the Keychain
- **Type:** Bug fix
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Before:** Titles were stored as a plain SHA-256 hash, so the layout file alone (a copy, a backup) could confirm a guessed title.
- **Setup:** A release build, with no "Expanse window title key" in Keychain Access.
- **Steps:**
  1. Launch Expanse; move a window so the layout is saved.
  2. Look at the titles in layout.json; search Keychain Access for "Expanse window title key".
  3. Relaunch Expanse.
  4. Repeat steps 1–2 with a development build.
- **Expected:** Release: titles look like `hmac:` and 24 hex digits; Keychain Access has a password item "Expanse window title key" (service com.invignation.expanse, account window-title-key); no Keychain prompt at any launch; windows come back to their spots after relaunch. Development build: titles are `sha256:…` and no Keychain item is made. If the Keychain can't be read or written, titles are hashed without the key.
- **Check in log:** only on failure: "window title key not available (<status>): titles hashed without it" or "window title key not saved (<status>): titles hashed without it".
- **Automate:** unit: LayoutStore.titleKey (prefix and length); manual for the Keychain.
- **Note:** README: the key stays in the Keychain after uninstalling until you delete it in Keychain Access.

## SEC-30 Unkeyed title hashes still match in a release
- **Type:** Feature
- **Area:** SEC
- **Commits:** 47ed782 (0.1.33)
- **Setup:** A layout.json saved by a development build or 0.1.32 (`sha256:` titles), with two TextEdit documents of the same size at different spots.
- **Steps:**
  1. Quit Expanse and TextEdit. Start the 0.1.33+ release build.
  2. Within 3 minutes, open TextEdit so it reopens both documents.
- **Expected:** Each document goes back to its own spot (matched by title, not swapped). After the next save their entries carry `hmac:` titles.
- **Automate:** unit: LayoutStore.takeMatch with sha256 and hmac entries (titleKeys).
- **Note:** A guard for the keyed hashes in SEC-29: without both forms matching, a layout saved by 0.1.32 or a development build would lose its title matches after updating.
