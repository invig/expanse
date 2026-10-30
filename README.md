<p align="center">
  <img src="docs/hero.svg" alt="Expanse: windows arranged on an infinite canvas" width="900">
</p>

<p align="center">
  <strong>Every window gets its own place on one endless desktop.</strong><br>
  Zoom out to see them all. Click one to glide straight to it.
</p>

<p align="center">
  <a href="https://github.com/invig/expanse/releases/latest"><strong>Download</strong></a> ·
  <a href="#install">Install</a> ·
  <a href="#the-basics">How to use it</a> ·
  <a href="#questions">Questions</a>
</p>

<p align="center">
  On a Windows PC? There's <a href="https://github.com/invig/expanse-windows">Expanse for Windows</a>
  too (<a href="https://github.com/invig/expanse-windows/releases/latest">download</a>).
</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple">
  <img alt="Free and open source, MIT" src="https://img.shields.io/badge/free-MIT-blue">
</p>

---

Expanse treats your screen as a view onto a much bigger canvas. Your windows stay where you put
them on it; you move the view instead of the windows. Rest the pointer in a corner of the screen
to see everything at once, then click a window to fly to it, ready to use.

- **See everything at once.** Every window, live, laid out the way you arranged it.
- **Move around by direction.** <kbd>⌃</kbd> + arrow keys hop to the next window to the left,
  right, above or below.
- **Arrange like a design tool.** Drag windows around; they snap into neat, even gaps.
- **At home on a laptop or a big display.** On a smaller screen the layout tightens up, and plugging
  back in puts it back exactly.
- **Easy to leave.** Pause or quit and every window goes straight back to where macOS had it.

## Install

```bash
brew install --cask invig/tap/expanse
```

Or [download the latest version](https://github.com/invig/expanse/releases/latest), unzip it,
and drag **Expanse** to Applications. It runs on macOS 15 or later, on any Mac, and keeps
itself up to date.

## First launch

A short walkthrough gets you set up in about a minute:

1. **Accessibility**, so Expanse can move and focus your windows.
2. **Screen Recording**, so it can show live pictures of your windows when you zoom out.
   Nothing is recorded or saved.
3. **A free screen corner and the <kbd>⌃</kbd> + arrow keys.** macOS uses these too, and the
   walkthrough shows you which of its settings to switch off.

## The basics

| Do this | To |
|---|---|
| Rest the pointer in a screen corner, or press <kbd>⌥</kbd> <kbd>`</kbd> | Zoom out to every window (do it again to go back) |
| Click a window | Glide to it and start using it |
| <kbd>⌃</kbd> + <kbd>←</kbd> <kbd>→</kbd> <kbd>↑</kbd> <kbd>↓</kbd> | Hop to the next window in that direction |
| Pinch, or scroll with two fingers | Zoom and move around the canvas |
| Drag a window while zoomed out | Move it; it snaps into place |
| <kbd>T</kbd> | Tidy up: each group of windows lined up and evenly spaced, where it is |
| <kbd>Esc</kbd> | Back to 100% |

<details>
<summary><strong>All shortcuts</strong></summary>

| Do this | To |
|---|---|
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>C</kbd> | Centre the window you're in |
| <kbd>⌘</kbd> + scroll | Zoom around the pointer |
| <kbd>Space</kbd> + drag | Move around the canvas |
| Click the minimap | Zoom out to every window |
| Scroll or pinch on empty desktop | Start moving around the canvas from 100% |
| Drag on empty canvas, <kbd>⇧</kbd>-click, or <kbd>⌘</kbd> <kbd>A</kbd> | Select windows, then drag any of them to move the group |
| Hold <kbd>⌘</kbd> while dragging | Move without snapping |
| <kbd>0</kbd> · <kbd>1</kbd> · <kbd>-</kbd> · <kbd>=</kbd> | Fit everything · 100% · zoom out · zoom in |
| <kbd>Return</kbd> | Dive into the highlighted window |
| Hover <kbd>×</kbd>, or <kbd>⌘</kbd> <kbd>W</kbd> | Close the window, or every selected window |
| <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>`</kbd> | Turn auto-centring on or off (off suits side-by-side work) |

</details>

**Full-screen apps** keep their own Spaces, as usual. Jump to them, and back, from the
**Spaces** panel next to the minimap at the bottom of the screen.

**The menu bar icon** opens a panel with the rest: a live minimap that opens the canvas, Pause,
Centre and Tidy Up, which corner to use, earlier layouts to go back to, the walkthrough again,
Troubleshooting (logs for a bug report), and Settings (updates, opening at login).

## Questions

<details>
<summary><strong>The corner or <kbd>⌃</kbd> + arrows do nothing</strong></summary>

macOS got there first. Run the walkthrough again (menu bar icon › Welcome & Shortcuts), or change
the settings yourself:

- **Corners:** System Settings › Desktop & Dock › Hot Corners. Set the corners you want for Expanse
  to “–”, or pick a different corner from Expanse's menu bar icon.
- **<kbd>⌃</kbd> + arrows:** System Settings › Keyboard › Keyboard Shortcuts › Mission Control.
  Turn off *Mission Control*, *Application windows* and *Move left/right a space*.

</details>

<details>
<summary><strong>My windows ended up somewhere odd</strong></summary>

Menu bar icon › **Restore Layout** puts them back the way they were earlier. Expanse keeps your
last three layouts, saved at least 15 minutes apart, and a restore can be undone too. **Tidy Up**
neatens things where they are. As a last resort, **Restore All Windows** brings every window
into view, stacked in the middle of the screen.

</details>

<details>
<summary><strong>Expanse doesn't see any of my windows</strong></summary>

Open System Settings › Privacy & Security › Accessibility, then turn Expanse off and on again.

</details>

<details>
<summary><strong>Something went wrong. How do I report it?</strong></summary>

1. Menu bar icon › Troubleshooting › turn on **Detailed Logging**.
2. Make it happen again.
3. Troubleshooting › **Copy Logs for a Bug Report**, then **Report an Issue on GitHub…** and paste
   them in, with a line about what you did and what you expected.

The copy says which Mac, macOS and Expanse version, your displays and settings, then the log.
Window titles are left out. Turn Detailed Logging off again once it's reported.

</details>

<details>
<summary><strong>Why is there a purple dot in the menu bar?</strong></summary>

macOS shows it whenever an app captures the screen. Expanse captures window pictures only while
you're zoomed out or gliding between windows, and only in memory.

</details>

<details>
<summary><strong>What does it keep, and what does it send?</strong></summary>

Window pictures exist only in memory, to draw the canvas. Nothing is recorded or sent anywhere.
The one network request is a daily update check to GitHub, which you can turn off in Settings.
When there's a newer release, Expanse downloads its zip from GitHub, unpacks it in a temporary
folder, and installs it only if it's signed by the same developer and notarised by Apple.

Expanse keeps its layouts in `~/Library/Application Support/Expanse/`: window positions and
sizes, app names, and a scrambled fingerprint (a hash) of each window's title, which recognises
the window without storing the title. Expanse makes the fingerprint with a secret key kept in
your Keychain, so the layout file on its own (a copy, a backup) can't even be used to check a
guessed title. Its settings are where
macOS keeps every app's (`~/Library/Preferences/com.invignation.expanse.plist`), and what it does
goes to the macOS log, without window titles. If you turn on **Detailed Logging** (menu bar
icon › Troubleshooting), it also keeps a log in `~/Library/Logs/Expanse/`: what it did with which
app's windows, never their titles. It stays on your Mac unless you copy it into a bug report
yourself.

</details>

<details>
<summary><strong>What can't it do?</strong></summary>

- **One display.** Expanse uses your main display for now.
- **No typing while zoomed out.** That would need changes to macOS that turn off its system
  protection (SIP), and Expanse deliberately doesn't go there.
- **A few apps fight being moved.** Please [open an issue](https://github.com/invig/expanse/issues)
  if you find one.

</details>

<details>
<summary><strong>How do I uninstall it?</strong></summary>

Quit Expanse first. Your windows go back where macOS had them. Then:

```bash
brew uninstall --zap --cask expanse
```

Or drag Expanse from Applications to the Bin, and delete `~/Library/Application Support/Expanse`.
Its window title key stays in your Keychain until you delete "Expanse window title key" in
Keychain Access.

</details>

## For tinkerers

<details>
<summary><strong>Scripting with <code>expanse://</code> links</strong></summary>

```bash
open "expanse://toggle"             # zoom out / back
open "expanse://tidy"
open "expanse://nav?dir=left"       # left | right | up | down
open "expanse://centre"             # the window you're in, to the middle
open "expanse://focus?app=Safari"
open "expanse://space?name=Safari"  # a full-screen app's Space, "Desktop", or "Expanse"
open "expanse://layout?snapshot=0"  # back to the newest saved layout (1, 2: older ones)
open "expanse://pause"              # windows back to the macOS layout
open "expanse://resume"
```

Also `enter`, `exit`, `fit`, `zoom?scale=0.5`, `pan?dx=100&dy=0` and `restore`.

Any app on your Mac can open these links. They only do what you can do yourself with the canvas,
the menu bar icon and the shortcuts. A web page can open them too, once you allow it in the
browser's prompt, so a link that comes from a browser runs only after Expanse asks you as well.

</details>

<details>
<summary><strong>Building from source</strong></summary>

You'll need the Swift 6 toolchain (Xcode 16 or later, or the Command Line Tools).

```bash
git clone https://github.com/invig/expanse.git
cd expanse
./scripts/build.sh
open build/Expanse.app
```

</details>

Curious how it works without turning off System Integrity Protection? See
[How Expanse works](docs/how-it-works.md).

## Thanks

- [Sunlight](https://x.com/deezel/status/2114386503312839087) by Darin Dimitroff, which inspired
  Expanse. Sunlight goes further with SIP disabled; Expanse explores how far a stock Mac can go.
- [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) and
  [Space Rabbit](https://github.com/Tahul/space-rabbit) for instant Space switching, and
  [AltTab](https://github.com/lwouis/alt-tab-macos) for reaching windows on other Spaces.
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) for the corner-parking idea, and
  [Rectangle](https://github.com/rxhanson/Rectangle) and [yabai](https://github.com/koekeishiya/yabai)
  for years of public knowledge about macOS window management.

## Licence

[MIT](LICENSE)
