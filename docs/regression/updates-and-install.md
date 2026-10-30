# UPDATE: Updates, release builds and install

[All areas](README.md)

## UPDATE-01 Building from source without a signing certificate
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cdf466 (0.1.0), c7cba50 (0.1.0)
- **Setup:** A Mac with the Swift 6 toolchain and no Apple Development certificate in the keychain.
- **Steps:**
  1. `./scripts/build.sh`
  2. `codesign -dv build/Expanse.app`, then `open build/Expanse.app`.
- **Expected:** The build succeeds and prints "signed with: -". codesign shows an ad hoc signature, and the app runs (macOS asks for the permissions again after each rebuild). With an Apple Development certificate it's signed with that.
- **Automate:** unit: a CI job running build.sh and checking codesign output.

## UPDATE-02 Release builds are universal, signed and notarised
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0578497 (0.1.0)
- **Setup:** The latest zip from the GitHub releases page, unzipped.
- **Steps:**
  1. `lipo -archs Expanse.app/Contents/MacOS/Expanse`
  2. `codesign -dv --verbose=2 Expanse.app`
  3. `spctl -a -vv Expanse.app` and `xcrun stapler validate Expanse.app`
  4. Open it.
- **Expected:** 1: `x86_64 arm64`. 2: Authority "Developer ID Application", hardened runtime flag. 3: "accepted", source "Notarized Developer ID"; the stapler validates. 4: opens with no Gatekeeper warning.
- **Automate:** unit: a release-check script running these commands.

## UPDATE-03 Settings: updates
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cd0016 (0.1.7), a2d80de (0.1.31)
- **Setup:** A release build, up to date; then a development build.
- **Steps:**
  1. Settings › "Check Now".
  2. Turn off "Check for updates automatically".
  3. Open Settings in a development build.
- **Expected:** Step 1: an alert "You're up to date" / "Expanse <version> is the latest version." (or "Couldn't check for updates" offline). Step 2: no daily check from then on (the default is on: a check a minute after launch and once a day). Step 3: the Updates section is greyed, with "This is a development build: it has no updates, and opening at login opens this copy."
- **Automate:** manual: network.

## UPDATE-04 A release finds a newer version a minute after launch and asks
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cd0016 (0.1.7)
- **Setup:** An older release build (any version from 0.1.7 on, older than the latest GitHub release) in /Applications. Settings › Check for updates automatically is on, and the Mac is online.
- **Steps:**
  1. Launch it and stay at 100% for about 70 seconds.
- **Expected:** An alert reads "Expanse <latest> is ready to install" / "Expanse relaunches, and your windows stay where they are. You can also install it later from the menu bar icon.", with Install and Relaunch, Later and What's New buttons. The menu bar panel shows a banner, "Expanse <latest> is ready", with Install and Relaunch.
- **Check in log:** `update available: <latest>`, then `update <latest> checks: signature 0, notarisation 0, version <latest>`
- **Automate:** manual: GitHub release, network and signed builds.
- **Note:** The update items were in the menu at first (Install Expanse x.y.z…, Check for Updates…, Check for Updates Automatically). Since a2d80de they are a panel banner plus the Settings window.

## UPDATE-05 Install and Relaunch replaces Expanse in place
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cd0016 (0.1.7)
- **Setup:** An update is ready (UPDATE-04), with windows arranged on the canvas.
- **Steps:**
  1. Click Install and Relaunch, in the alert or the panel banner.
- **Expected:** Expanse quits, putting windows back, and reopens as the new version in the same place (/Applications/Expanse.app). It asks for no Accessibility or Screen Recording permission and shows no walkthrough, because the signature matches. Your layout is as before, and Settings shows the new version.
- **Check in log:** `installed <version>; relaunching`
- **Automate:** manual.

## UPDATE-06 What's New and Later
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cd0016 (0.1.7)
- **Setup:** An update is ready, with the alert showing.
- **Steps:**
  1. Click What's New.
  2. When it's offered again (Settings › Check Now), click Later.
- **Expected:** At step 1 the GitHub release page opens in the browser and nothing installs. At step 2 the alert closes and nothing installs, but the panel banner still offers Install and Relaunch.
- **Automate:** manual.

## UPDATE-07 Asked once per version; Check Now asks again
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cd0016 (0.1.7)
- **Setup:** Click Later on the alert for version X.
- **Steps:**
  1. Quit and reopen Expanse, then wait 70 seconds.
  2. Open the menu bar icon › Settings › Check Now.
- **Expected:** At step 1 no alert appears for X again (it's remembered in `updatePromptedFor`), though the panel banner still offers X once it's downloaded. At step 2 the alert appears again.
- **Automate:** unit: AppDelegate.updateReady with askedToCheck and the updatePromptedFor default.

## UPDATE-08 The update question never appears over the canvas
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cd0016 (0.1.7)
- **Setup:** An older release build, just launched.
- **Steps:**
  1. Within the first minute, press ⌥` and stay zoomed out until well past the minute.
  2. Press Esc.
- **Expected:** No alert appears while zoomed out. Within 30 seconds of returning to 100%, "Expanse <latest> is ready to install" appears.
- **Automate:** manual. updateReady retries every 30 s while controller.isActive.

## UPDATE-09 Check Now says when you're up to date, or when it couldn't check
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cd0016 (0.1.7)
- **Setup:** The latest release build.
- **Steps:**
  1. Open Settings › Check Now.
  2. Turn Wi-Fi off and click Check Now again.
- **Expected:** At step 1: "You're up to date" / "Expanse <version> is the latest version." At step 2: "Couldn't check for updates", with the network error.
- **Check in log:** `up to date (<v>; latest <v>)`; `update check failed: …`
- **Automate:** manual. Updater.check(interactive: true).

## UPDATE-10 Development builds never update
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cd0016 (0.1.7)
- **Setup:** A development build (`./scripts/build.sh`).
- **Steps:**
  1. Launch it and wait 70 seconds.
  2. Open Settings.
- **Expected:** At step 1 there is no update check: no `update available`, `up to date` or `update check failed` lines. At step 2 the Updates section is greyed out, with "This is a development build: it has no updates, and opening at login opens this copy."
- **Automate:** unit: Updater.isRelease is false for a non-Developer-ID signature, and Updater.start/check return without a request.
- **Note:** The note and greyed section come from the Settings window, added in a2d80de.

## UPDATE-11 When it can't replace itself, the update opens the release page
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cd0016 (0.1.7)
- **Setup:** An older release build run from somewhere it can't replace itself: straight from the unzipped download, so macOS translocates it, or a folder you can't write to.
- **Steps:**
  1. Wait for the update alert and click Install and Relaunch.
- **Expected:** The GitHub release page opens in the browser, and Expanse keeps running unchanged.
- **Automate:** unit: Updater.install's guard on /AppTranslocation/ in the path, or a folder that isn't writable.

## UPDATE-12 Only a copy signed like this one, notarised and at the right version, is installed
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cd0016 (0.1.7)
- **Setup:** A release-signed test host, plus three copies of a release: the genuine one; one re-signed ad hoc (`codesign --force --deep -s - Expanse.app`); and the genuine one checked against the wrong version string.
- **Steps:**
  1. Call Updater.verify(app, version:) on each.
- **Expected:** The genuine copy at its own version returns true. The ad-hoc copy and the wrong-version check return false.
- **Check in log:** `update <v> checks: signature 0, notarisation 0, version <v>` for the genuine copy; a non-zero signature or notarisation status, or a different version, for the others.
- **Automate:** unit: Updater.verify(_:version:). It must run from a release-signed host, because it compares against the running copy's designated requirement.

## UPDATE-13 Version comparison and reading GitHub's answer
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cd0016 (0.1.7)
- **Setup:** None (unit level).
- **Steps:**
  1. Compare versions with Updater.isNewer.
  2. Parse sample GitHub "latest release" JSON.
- **Expected:**
  - isNewer("0.1.10", than: "0.1.9") is true, and the reverse is false.
  - Equal versions are not newer, and "1.0" vs "1.0.0" is not newer.
  - Tag "v0.1.34" reads as version 0.1.34.
  - A tag with letters (for example "0.1.34-beta") gives no release.
  - The zip must be the asset named "Expanse-<version>.zip"; otherwise there's no release.
- **Automate:** unit: Updater.isNewer(_:than:) and Updater.release(from:). The latter is private, so a test needs access.
- **Note:** 47ed782 later also refused assets larger than the download limit.

## UPDATE-14 Turning off automatic checks stops them
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** 0cd0016 (0.1.7)
- **Setup:** A release build.
- **Steps:**
  1. Settings › switch off "Check for updates automatically".
  2. Quit, reopen and wait 70 seconds.
  3. Click Check Now.
- **Expected:** At step 2 there is no check: no `update available` or `up to date` line. At step 3 the manual check still runs.
- **Automate:** unit: Updater.automatic (defaults key `checkForUpdates`, default true) and schedule().

## UPDATE-15 A failed update install cleans up and is offered again
- **Type:** Bug fix
- **Area:** UPDATE
- **Commits:** f310f04 (0.1.8)
- **Before:** After a failed install, the staged copy and the download could be left behind, and Expanse kept offering a downloaded copy that had already been moved away.
- **Setup:** An update is ready (UPDATE-04). Make the swap fail, for example `chflags uchg /Applications/Expanse.app`, and undo it afterwards with `chflags nouchg`.
- **Steps:**
  1. Click Install and Relaunch.
  2. Run `ls -a /Applications | grep Expanse-update`.
  3. Undo the flag, then Settings › Check Now.
- **Expected:** At step 1 an alert reads "Couldn't install Expanse <v>" with the error, the release page opens, and Expanse keeps running. The panel's "ready" banner is gone. Step 2 prints nothing (no `.Expanse-update.app` left). At step 3 the update downloads again and is offered.
- **Check in log:** `update install failed: …`
- **Automate:** unit: the catch path of Updater.install, which removes the staged copy and the download folder and sets ready to nil.

## UPDATE-16 A download that fails its checks is deleted
- **Type:** Bug fix
- **Area:** UPDATE
- **Commits:** f310f04 (0.1.8)
- **Before:** A downloaded and unpacked release that failed verification was left in the temporary folder.
- **Setup:** A test release whose app fails Updater.verify (for example an ad-hoc-signed one), served in place of GitHub's latest.
- **Steps:**
  1. Settings › Check Now.
  2. Look in `$TMPDIR` for `Expanse-update-*` folders.
- **Expected:** "Couldn't download Expanse <v>" / "Try again later, or download it from GitHub." appears, and no `Expanse-update-*` folder remains.
- **Automate:** unit: Updater.download removes the unpack folder whenever app is nil.

## UPDATE-17 Install with Homebrew
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** df75a6e (0.1.9)
- **Setup:** Homebrew installed, and no Expanse in /Applications.
- **Steps:**
  1. `brew install --cask invig/tap/expanse`
  2. Open Expanse.
- **Expected:** Expanse.app at the latest release version is installed in /Applications, and it opens with the walkthrough.
- **Automate:** manual: network and Homebrew.

## UPDATE-18 Releasing points the Homebrew cask at the new version
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** df75a6e (0.1.9)
- **Setup:** A maintainer machine set up for `scripts/release.sh`, with `gh` signed in and write access to invig/homebrew-tap.
- **Steps:**
  1. Run `scripts/release.sh` for a new version.
  2. Look at Casks/expanse.rb in invig/homebrew-tap.
  3. On another Mac, run `brew upgrade --cask expanse`.
- **Expected:** After "==> Updating the Homebrew cask (invig/homebrew-tap)" the script prints the tap commit's URL, then "==> Done". The cask's `version` is the new version and its `sha256` matches `shasum -a 256` of the release zip, in a commit titled "Expanse <version>". Step 3 installs the new version.
- **Automate:** manual: publishes to GitHub. Use `CASK_BRANCH=test` to try it without touching main.

## UPDATE-19 update-cask.sh: already up to date, or a cask it can't edit
- **Type:** Feature
- **Area:** UPDATE
- **Commits:** df75a6e (0.1.9)
- **Setup:** A test branch of the tap, used via `CASK_BRANCH=test`.
- **Steps:**
  1. Run `CASK_BRANCH=test scripts/update-cask.sh <version already in the cask> <its zip>`.
  2. On a branch whose cask has no `  version "…"` line, run it again.
  3. Run `scripts/release.sh` (against the test branch) with the cask in step 2's state, so its update-cask step fails.
- **Expected:** Step 1 prints "The cask is already at <version>." and exits 0 with no commit. Step 2 prints "Couldn't find the version and sha256 lines in invig/homebrew-tap/Casks/expanse.rb." and exits 1. At step 3 release.sh prints "The release is out, but the cask isn't updated: run scripts/update-cask.sh <version> <zip>" and still finishes with "==> Done".
- **Automate:** unit: a shell test of scripts/update-cask.sh with `gh` stubbed.
