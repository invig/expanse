# SETUP: First launch and permissions

[All areas](README.md)

## SETUP-01 First launch: the walkthrough comes before any macOS prompt
- **Type:** Feature
- **Area:** SETUP
- **Commits:** c7cba50 (0.1.0)
- **Setup:** A first launch: `tccutil reset Accessibility com.invignation.expanse`, `tccutil reset ScreenCapture com.invignation.expanse` and `defaults delete com.invignation.expanse`.
- **Steps:**
  1. Launch Expanse.
  2. Before pressing anything in the walkthrough, press ⌥` and ⌃→, and run `open "expanse://toggle"`.
- **Expected:** 1: the welcome window ("Welcome to Expanse", "Your Mac, on an infinite canvas.") with a four-step checklist. No macOS permission prompt appears until you press a button. 2: nothing happens and no window moves.
- **Check in log:** `ignored URL command toggle: Expanse starts once the walkthrough is done`
- **Automate:** manual: needs a fresh permission state.
- **Note:** Four steps since bf8e9a6; Expanse waits for the walkthrough before starting since d7da75d.

## SETUP-02 Permission steps show live status and open the right Settings pane
- **Type:** Feature
- **Area:** SETUP
- **Commits:** c7cba50 (0.1.0)
- **Setup:** As SETUP-01, on the walkthrough's Accessibility step.
- **Steps:**
  1. Press the step's button.
  2. Turn Expanse on in System Settings › Privacy & Security › Accessibility and watch the walkthrough.
  3. On the Screen Recording step, press its button.
- **Expected:** 1: macOS's prompt comes up in front (or the Accessibility pane opens). 2: the card shows a tick within about a second, without a relaunch. 3: the Screen Recording prompt or pane opens.
- **Automate:** manual: real permission prompts.

## SETUP-03 Screen Recording: Expanse reopens itself to apply it
- **Type:** Feature
- **Area:** SETUP
- **Commits:** c7cba50 (0.1.0), ac50e01 (0.1.0)
- **Setup:** Walkthrough on the Screen Recording step, Accessibility granted.
- **Steps:**
  1. Press Allow and turn Expanse on in the Screen Recording pane.
  2. Press the step's button, which now reads Reopen Expanse (or finish the walkthrough).
- **Expected:** Expanse quits and opens again. The walkthrough comes back on the page you were on, with Screen Recording ticked.
- **Automate:** manual: real relaunch and permissions.

## SETUP-04 The corner and ⌃-arrow steps show what macOS has in the way
- **Type:** Feature
- **Area:** SETUP
- **Commits:** c7cba50 (0.1.0)
- **Setup:** A macOS hot corner set (top left: Mission Control). macOS's ⌃-arrow Mission Control shortcuts on.
- **Steps:**
  1. Go to the walkthrough's hot corner step; press its button and set that macOS corner to "–".
  2. Go to the ⌃ + arrow keys step; press its button and turn off Mission Control's ⌃-arrow shortcuts.
- **Expected:** Each step names the macOS settings in the way. Its button opens Desktop & Dock or Keyboard Shortcuts. The tick appears within about a second of switching them off. Picking a corner in the walkthrough also changes Expanse's hot corner.
- **Automate:** unit: SystemShortcuts.hotCorners(in:) and controlArrows() read macOS's preferences.

## SETUP-05 Closing the walkthrough releases it
- **Type:** Bug fix
- **Area:** SETUP
- **Commits:** ac50e01 (0.1.0)
- **Before:** Closing the walkthrough with its title-bar button left the window, its view and its once-a-second permission check running.
- **Setup:** Walkthrough done. Activity Monitor open.
- **Steps:**
  1. Panel › Welcome & Shortcuts, then close it with the red button.
  2. Reopen it and close it again.
- **Expected:** It reopens fresh each time. Once closed, Expanse's idle CPU is back to normal and its shortcuts work.
- **Automate:** manual: window lifecycle.
- **Note:** Since d7da75d closing it also starts Expanse, as finishing does.

## SETUP-06 No repeated Screen Recording prompts before the relaunch
- **Type:** Bug fix
- **Area:** SETUP
- **Commits:** ac50e01 (0.1.0)
- **Before:** After you allowed Screen Recording, but before Expanse relaunched, every window scan (every 1.5s) and desktop picture capture made macOS show its prompt again.
- **Setup:** `tccutil reset ScreenCapture com.invignation.expanse`; Accessibility granted.
- **Steps:**
  1. Launch Expanse. On the Screen Recording step press Allow and turn it on in System Settings.
  2. Close the walkthrough without reopening Expanse and wait 30s.
- **Expected:** macOS's Screen Recording prompt doesn't keep coming back. The canvas has no desktop picture and takes on no windows until Expanse is reopened.
- **Automate:** manual: needs real permission state.

## SETUP-07 A second copy quits and shows the running one's welcome window
- **Type:** Feature
- **Area:** SETUP
- **Commits:** b229427 (0.1.1)
- **Setup:** Expanse running. A second copy of the app (a development build, say) with the same bundle ID.
- **Steps:**
  1. Open the second copy (or `open -n /Applications/Expanse.app`).
  2. Repeat while zoomed out.
- **Expected:** The second copy exits at once without moving any window. The running copy shows its welcome window in front, leaving the canvas first in step 2.
- **Automate:** manual: needs two app processes.

## SETUP-08 Reopening Expanse waits for the old copy to quit
- **Type:** Bug fix
- **Area:** SETUP
- **Commits:** b229427 (0.1.1)
- **Before:** The walkthrough's Reopen Expanse opened the new copy after a fixed second. With only one copy allowed, a new copy that started before the old one had finished quitting (putting windows back takes a moment) quit at once, and Expanse didn't come back.
- **Setup:** 30+ windows, so quitting takes a while. Walkthrough on the Screen Recording step after allowing it.
- **Steps:**
  1. Press Reopen Expanse.
- **Expected:** Expanse quits (windows back in the macOS layout), then opens again and carries on. It never stays closed.
- **Automate:** manual: process lifecycle.
- **Note:** Installing an update uses the same relaunch (Updater.relaunch).

## SETUP-09 The welcome page lists the four steps with live ticks
- **Type:** Feature
- **Area:** SETUP
- **Commits:** bf8e9a6 (0.1.5)
- **Setup:** Run `defaults delete com.invignation.expanse onboardingDone`, then quit and reopen Expanse. The walkthrough opens on its first page.
- **Steps:**
  1. Read the first page.
  2. With it open, change one of the four things in System Settings, for example set a macOS hot corner that Expanse uses to "–".
- **Expected:** A 960×620 window: an animated canvas on the left, and on the right "Welcome to Expanse" / "Your Mac, on an infinite canvas." Under "Four quick steps" it lists Let Expanse move your windows, Let Expanse show your windows, Free up a screen corner, and Free up ⌃ + arrow keys. Each row shows a green tick when that step is already done, otherwise its number. Below: "No hacks or SIP changes. Quit any time and every window goes back where it was." The footer has page dots and a "Get started" button. At step 2 the matching row ticks within about a second.
- **Automate:** unit: SetupModel's done flags (accessibility, screenRecording, cornersDone, arrowsDone). manual for the 1 s polling against System Settings.

## SETUP-10 The hot corner step names the macOS corner in the way and ticks off once it's freed
- **Type:** Feature
- **Area:** SETUP
- **Commits:** bf8e9a6 (0.1.5)
- **Setup:** Expanse's corner is All Corners. In System Settings › Desktop & Dock › Hot Corners, the bottom-right corner is set to Quick Note.
- **Steps:**
  1. Open the walkthrough and go to "Step 3 of 4", "Flick to a corner to see everything."
  2. Click Open Settings.
  3. Click Hot Corners… and set the bottom-right corner to "–".
- **Expected:** At step 1 the card says "macOS uses the bottom‑right corner for Quick Note" (several corners are joined with "and the"), and the footer button reads "Skip for now". At step 2 System Settings opens at Desktop & Dock. At step 3, within a second, the card turns to "Free for Expanse" with a tick and the button becomes "Continue".
- **Automate:** unit: SystemShortcuts.hotCorners(in:) from wvous-<corner>-corner and -modifier values. It needs a seam for the com.apple.dock preferences domain.

## SETUP-11 A macOS hot corner that needs a modifier key doesn't count as in the way
- **Type:** Feature
- **Area:** SETUP
- **Commits:** bf8e9a6 (0.1.5)
- **Setup:** In Hot Corners, hold ⌘ while setting the bottom-left corner to Mission Control, so it only fires with ⌘ held. Expanse's corner is All Corners, and no other macOS corners are set.
- **Steps:**
  1. Open the walkthrough at Step 3.
- **Expected:** The bottom-left corner isn't listed; the card reads "Free for Expanse". A corner set to "–" is never listed either.
- **Automate:** unit: SystemShortcuts.hotCorners(in:). A modifier other than 0 is not listed, and actions 0 and 1 are not listed.

## SETUP-12 Picking Expanse's own corner on the hot corner step
- **Type:** Feature
- **Area:** SETUP
- **Commits:** bf8e9a6 (0.1.5)
- **Setup:** The macOS bottom-right corner is set to Quick Note, and Expanse's corner is All Corners.
- **Steps:**
  1. At Step 3, set the "Expanse uses" pop-up to Bottom Left.
  2. Set it to Off.
  3. Continue to the last page.
- **Expected:** At step 1 only the bottom-left macOS corner is checked now, so the bottom-right Quick Note no longer blocks and the card ticks ("Free for Expanse"). Expanse's own hot corner setting becomes Bottom Left (the menu bar panel shows it later), and the illustration's pointer flicks to the bottom-left corner instead of the top right. At step 2 the card reads "Expanse’s hot corner is off" with a tick. At step 3 the page says "Press ⌥` to zoom out, then click any window to dive back in."
- **Automate:** unit: SetupModel.corner didSet, which updates Onboarding.hotCorner.corner, and HotCorner.Corner.corners.

## SETUP-13 The ⌃ + arrows step lists the macOS shortcuts still on
- **Type:** Feature
- **Area:** SETUP
- **Commits:** bf8e9a6 (0.1.5)
- **Setup:** A Mac whose Mission Control shortcuts have never been changed.
- **Steps:**
  1. Open the walkthrough at "Step 4 of 4".
  2. Click Open Settings, then Keyboard Shortcuts…, then Mission Control. Switch off Mission Control, Application windows, Move left a space and Move right a space, one at a time.
- **Expected:** At first the card reads "Still on: Application windows (⌃↓), Mission Control (⌃↑), Move left a space (⌃←), Move right a space (⌃→)", sorted. Each entry disappears within a second of being switched off. With all four off it reads "Free for Expanse" with a tick, and the button says Continue. A shortcut that uses ⌃ plus ⇧, ⌥ or ⌘ with an arrow isn't listed. Any other enabled macOS shortcut that is ⌃ plus an arrow on its own shows as "A macOS shortcut (⌃→)".
- **Automate:** unit: SystemShortcuts.controlArrows() given an AppleSymbolicHotKeys dictionary. Built-ins 32, 33, 79 and 81 count as on when missing, and parameters[2] must have ⌃ and no other modifier.

## SETUP-14 Footer buttons: Skip for now until a step is done, then Continue
- **Type:** Feature
- **Area:** SETUP
- **Commits:** bf8e9a6 (0.1.5)
- **Setup:** The walkthrough is open, with at least one step not done (for example the ⌃ + arrows still on).
- **Steps:**
  1. Go through the pages with Return, and back with ←.
- **Expected:** Page 1 shows "Get started". A step page shows "Skip for now" (plain style) while its step isn't done, and "Continue" (prominent) once it is. The last page shows "Start using Expanse". Back appears on every page after the first and ← triggers it; Return presses the main button. Skipping moves on without changing anything.
- **Automate:** unit: OnboardingView.stepDone for each page.

## SETUP-15 The last page is a cheat sheet
- **Type:** Feature
- **Area:** SETUP
- **Commits:** bf8e9a6 (0.1.5), 8c2b732 (0.1.15)
- **Setup:** The walkthrough is open.
- **Steps:**
  1. Go to the last page.
  2. Click Start using Expanse.
- **Expected:** "All set" / "Try it now." with keycaps and descriptions: ⌥ ` zoom out to every window and back; Click to dive into a window; ⌃ ← → ↑ ↓ to hop; ⌃ ⌥ C to centre the window you're in (added by 8c2b732); Pinch / Scroll to zoom and pan; Space + Drag to move around; Drag to move windows; ⇧ Click to select several, then drag or close them together; T to tidy up. Underneath: "Find this again under the menu bar icon › Welcome & Shortcuts." At step 2 the walkthrough closes and Expanse is running.
- **Automate:** manual: SwiftUI page content.

## SETUP-16 Expanse does nothing until the walkthrough is finished, skipped or closed
- **Type:** Feature
- **Area:** SETUP
- **Commits:** d7da75d (0.1.9)
- **Setup:** A saved layout, with windows not where the canvas would put them. Run `defaults delete com.invignation.expanse onboardingDone`, then quit and reopen Expanse.
- **Steps:**
  1. With the walkthrough up, press ⌥`, ⌃→ and ⌃⌥C, and rest the pointer in a screen corner.
  2. Open the menu bar icon's panel.
  3. `open "expanse://toggle"`
  4. Close the walkthrough with its red close button.
- **Expected:**
  1. Nothing from Expanse: no windows move, there's no canvas, and macOS keeps its own shortcuts and corners.
  2. The status reads "Starts once the walkthrough is done", and the canvas actions (Expanse switch, Centre window, Tidy up and the like) are disabled.
  3. The link is ignored.
  4. Expanse starts: the status changes to "On · N windows on the canvas" and the shortcuts work.
- **Check in log:** `ignored URL command toggle: Expanse starts once the walkthrough is done`
- **Automate:** unit: AppDelegate.turnOn, which runs once from Onboarding's onFinish (called on windowWillClose), and the isOn gate in application(_:open:).
- **Note:** `expanse://welcome` and `expanse://update` are let through before then. Disabling the canvas actions moved from menu items to MenuPanel.Action.needsCanvas in a2d80de.

## SETUP-17 macOS's Screen Recording prompt comes to the front
- **Type:** Bug fix
- **Area:** SETUP
- **Commits:** d7da75d (0.1.9), f4e632a (0.1.14)
- **Before:** Expanse opened System Settings at the same moment as macOS's prompt, which hid the prompt and showed a Screen Recording list without Expanse in it (macOS only lists an app once its prompt is answered).
- **Setup:** Expanse never asked for Screen Recording on this Mac (for example after `tccutil reset ScreenCapture com.invignation.expanse`). Walkthrough at Step 2.
- **Steps:**
  1. Click Open Settings.
  2. In macOS's prompt, click Open System Settings.
- **Expected:** At step 1 macOS's prompt appears in front of everything, the walkthrough included, and System Settings doesn't open by itself. At step 2 System Settings opens at Screen Recording with Expanse listed. The card then reads "Switched it on? Reopen Expanse to finish.", its button becomes "Reopen Expanse", and the step counts as done (Continue). If macOS shows no prompt (asked before), System Settings opens at Screen Recording after about a second and a half.
- **Check in log:** `permission prompt up [<id>]`
- **Automate:** manual: macOS's TCC prompt (Permissions.ask).

## SETUP-18 Finishing with Screen Recording pending relaunches, and Expanse starts then
- **Type:** Feature
- **Area:** SETUP
- **Commits:** d7da75d (0.1.9)
- **Setup:** Screen Recording was just switched on in this run of the walkthrough (SETUP-17), and you skipped "Reopen Expanse".
- **Steps:**
  1. Go to the last page and click Start using Expanse.
- **Expected:** Expanse quits without having started and opens again by itself. After reopening, the walkthrough doesn't show (both permissions are now in effect) and Expanse starts, with the canvas, shortcuts and windows in their saved spots.
- **Automate:** unit: OnboardingView's last-page action calls markDone() then relaunch() instead of finish().

## SETUP-19 System Settings opens in front of the walkthrough
- **Type:** Bug fix
- **Area:** SETUP
- **Commits:** f4e632a (0.1.14)
- **Before:** The walkthrough floated above other windows (at the level it needed to clear the canvas), so System Settings opened behind it.
- **Setup:** The walkthrough is open.
- **Steps:**
  1. At Step 3, click Open Settings.
  2. At Step 4, click Open Settings.
- **Expected:** Each time, System Settings (Desktop & Dock, then Keyboard) opens in front of the walkthrough, which behaves like an ordinary window.
- **Automate:** manual: window layering.

## SETUP-20 macOS's Accessibility prompt comes to the front
- **Type:** Bug fix
- **Area:** SETUP
- **Commits:** f4e632a (0.1.14)
- **Before:** Open Settings asked for Accessibility and opened System Settings at the same time, which covered macOS's prompt.
- **Setup:** Expanse not yet trusted for Accessibility and never asked before (for example after `tccutil reset Accessibility com.invignation.expanse`). Walkthrough at Step 1.
- **Steps:**
  1. Click Open Settings.
  2. In the prompt, click Open System Settings and switch Expanse on.
- **Expected:** At step 1 macOS's prompt is in front of everything, and System Settings doesn't open over it. At step 2 the Accessibility list opens; once Expanse is switched on, the card reads "On" with a tick within a second. If there's no prompt (already asked), System Settings opens at Accessibility after about a second and a half.
- **Check in log:** `permission prompt up [<id>]`
- **Automate:** manual: macOS's TCC prompt (Permissions.requestAccessibility).
- **Note:** At HEAD, the menu bar panel's grant-Accessibility action goes through the same path.

## SETUP-21 After reopening for Screen Recording, the walkthrough picks up where you were
- **Type:** Feature
- **Area:** SETUP
- **Commits:** f4e632a (0.1.14)
- **Setup:** First run of the walkthrough, with Screen Recording just switched on in System Settings (SETUP-17).
- **Steps:**
  1. At Step 2, click Reopen Expanse.
- **Expected:** Expanse quits and reopens, and the walkthrough opens on Step 2, now showing "On" with a tick, not on the Welcome page. Once finished, it starts from page 1 next time (for example from Welcome & Shortcuts).
- **Automate:** unit: Onboarding.show's start page comes from the `onboardingPage` default unless onboardingDone; markDone() removes it.

## SETUP-22 The walkthrough window is exactly the page's size
- **Type:** Bug fix
- **Area:** SETUP
- **Commits:** f4e632a (0.1.14)
- **Before:** The hosting view added the title bar's height, which showed as an empty strip along the bottom of the window.
- **Setup:** None.
- **Steps:**
  1. Open the walkthrough and look at its bottom edge.
- **Expected:** The window is 960×620. The page and illustration run right to the edges and up under the see-through title bar, with no strip at the bottom.
- **Automate:** manual: visual.

## SETUP-23 Opening the walkthrough while zoomed out leaves the canvas first
- **Type:** Feature
- **Area:** SETUP
- **Commits:** f4e632a (0.1.14)
- **Setup:** Zoomed out (⌥`).
- **Steps:**
  1. Trigger `open "expanse://welcome"` from a launcher, or open Expanse again from /Applications while it's running.
  2. Zoom out again, open the menu bar panel and click the ? (Welcome & Shortcuts) button.
- **Expected:** Each time, the canvas returns to 100% and the walkthrough appears in front, starting at page 1. A second launch doesn't start a second copy.
- **Automate:** unit: AppDelegate.showWelcome calls controller.exit() when active and not gliding.
- **Note:** The walkthrough became an ordinary window in this commit (SETUP-19); without leaving the canvas first, it would open underneath it.

## SETUP-24 A release build opens at login after its first start
- **Type:** Feature
- **Area:** SETUP
- **Commits:** b3843a3 (0.1.22)
- **Setup:** A Developer ID signed release build. `defaults delete com.invignation.expanse loginItemSetUp`; Expanse not in System Settings › General › Login Items.
- **Steps:**
  1. Open Expanse and finish the walkthrough.
  2. Look in System Settings › General › Login Items, and Expanse's Settings (panel › gear).
  3. Log out and back in.
- **Expected:** Expanse is listed under Open at Login and "Open Expanse at login" is on. After logging in, Expanse starts by itself. It's registered once, after the walkthrough, not during it.
- **Check in log:** `login item registered` (or `login item registration failed: …`, retried at the next start)
- **Automate:** manual: SMAppService needs a signed app.

## SETUP-25 Open at Login stays as you set it; development builds don't register
- **Type:** Feature
- **Area:** SETUP
- **Commits:** b3843a3 (0.1.22), a2d80de (0.1.31)
- **Setup:** Release build already registered (SETUP-24). A development build to compare.
- **Steps:**
  1. In Expanse's Settings, turn "Open Expanse at login" off.
  2. Quit and reopen Expanse.
  3. Start a fresh development build with `loginItemSetUp` deleted.
- **Expected:** Step 2: it stays off; Expanse doesn't register itself again. Step 3: the development build never registers by itself, and Settings says "This is a development build: it has no updates, and opening at login opens this copy."
- **Automate:** manual: SMAppService.
- **Note:** The switch moved from the menu to the Settings window, and development builds can turn it on by hand there, since a2d80de. Settings has been a page of the menu bar panel since 0.1.41 (UI-42).

## SETUP-26 Turning Open at Login back on after switching it off in System Settings
- **Type:** Feature
- **Area:** SETUP
- **Commits:** b3843a3 (0.1.22)
- **Setup:** Release build. Expanse turned off in System Settings › General › Login Items.
- **Steps:**
  1. In Expanse's Settings, turn "Open Expanse at login" on.
- **Expected:** If macOS needs your approval, System Settings opens at Login Items so you can approve it; the switch shows on only once it's really on.
- **Automate:** manual: SMAppService status requiresApproval.

## SETUP-27 A development build can open at login
- **Type:** Feature
- **Area:** SETUP
- **Commits:** 4045597 (0.1.31)
- **Setup:** A development build (`./scripts/build.sh`, `open build/Expanse.app`).
- **Steps:**
  1. Panel › gear. Turn on "Open Expanse at login".
  2. Check System Settings › General › Login Items; log out and in.
- **Expected:** The switch works: this copy is added to Login Items and opens at login. The footnote reads "This is a development build: it has no updates, and opening at login opens this copy." A development build never turns it on by itself; a release turns it on once, at its first start.
- **Automate:** manual: SMAppService login items.
- **Note:** In a2d80de the switch was greyed out in development builds.
