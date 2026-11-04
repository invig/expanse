<p align="center">
  <img src="docs/hero.svg" alt="Expanse: windows on one big canvas, with a lit frame showing the part your screen sees, gliding from window to window while the windows stay put" width="900">
</p>

<p align="center">
  <strong>Every window gets its own place on one endless desktop.</strong><br>
  Zoom out to see them all. Click one to glide straight to it.
</p>

<p align="center">
  <a href="https://github.com/invig/expanse/releases/latest"><strong>Download</strong></a> ·
  <a href="#install">Install</a> ·
  <a href="#the-basics">How to use it</a> ·
  <a href="#see-it-work">See it work</a> ·
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
- **Groups of windows stay together.** Arrange a few side by side so they fit the screen, and
  Expanse treats them as one place: hops, clicks and centring show the whole group.
- **Build a screen in a moment.** Zoomed out, drop a window on another's side or corner to tile
  them into halves and quarters of your screen, or select a few and press S. Resize windows
  right there by their edges, or right-click for Fill, Half or Quarter screen.
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
| Click a window | Glide to it (and the windows grouped with it) and start using it |
| <kbd>⌃</kbd> + <kbd>←</kbd> <kbd>→</kbd> <kbd>↑</kbd> <kbd>↓</kbd> | Hop to the next window in that direction |
| Pinch, or scroll with two fingers | Zoom and move around the canvas |
| Drag a window while zoomed out | Move it; it snaps into place |
| <kbd>T</kbd> | Tidy up: each group of windows lined up and evenly spaced, where it is |
| <kbd>Esc</kbd> | Back to 100%, to the window you were in |

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
Troubleshooting (logs for a bug report), and Settings (updates, opening at login, the gap between
windows).

**Prefer less movement?** Settings › Glides and zooms can make the view jump straight to where
it's going. If macOS's Reduce Motion is on, Expanse does this by itself.

## See it work

<img src="docs/screenshots/overview.jpg" alt="Expanse zoomed out: ten windows arranged on one canvas over the desktop picture, with a minimap in the corner">

**Zoom out to see everything.** Every window, live, laid out the way you arranged it. Rest the
pointer in a screen corner, or press <kbd>⌥</kbd> <kbd>`</kbd>.

<table>
<tr>
<td width="50%" valign="top"><img src="docs/screenshots/glide.jpg" alt="The view partway through zooming in on the Calendar window, its neighbours sliding off the edges of the screen"><br><strong>Click a window</strong> and the view glides to it, ready to use.</td>
<td width="50%" valign="top"><img src="docs/screenshots/hop.jpg" alt="The view at 100% partway through moving from Maps to Calendar"><br><strong><kbd>⌃</kbd> + arrow keys</strong> hop to the next window in that direction. The view moves; the windows stay where they are.</td>
</tr>
<tr>
<td width="50%" valign="top"><img src="docs/screenshots/zoom.jpg" alt="The canvas at 60%, with windows running off the edges and the minimap outlining the part in view"><br><strong>Pinch, or scroll with two fingers,</strong> to zoom and move around. The minimap shows where you are.</td>
<td width="50%" valign="top"><img src="docs/screenshots/snap.jpg" alt="Chess being dragged next to Clock on the zoomed-out canvas, its top snapped level with Clock's"><br><strong>Drag a window while zoomed out</strong> and it snaps into neat, even gaps. Hold <kbd>⌘</kbd> to move it freely.</td>
</tr>
<tr>
<td width="50%" valign="top"><img src="docs/screenshots/group-hover.jpg" alt="The pointer over Safari, with an outline around both Safari and Maps beside it"><br><strong>Windows side by side that fit the screen are one place.</strong> Hover one and the group is outlined.</td>
<td width="50%" valign="top"><img src="docs/screenshots/group-screen.jpg" alt="Safari and Maps side by side, filling the screen at 100%"><br><strong>Hops, clicks and centring show the whole group</strong> at 100%.</td>
</tr>
<tr>
<td width="50%" valign="top"><img src="docs/screenshots/tile-drop.jpg" alt="Notes being dragged onto the right side of Calendar, with the right half of a screen highlighted"><br><strong>Drop a window on another's side or corner</strong> to tile them. The highlight shows where it will go.</td>
<td width="50%" valign="top"><img src="docs/screenshots/tile-screen.jpg" alt="Calendar and Notes as two halves filling the screen at 100%"><br><strong>They become a screen:</strong> halves or quarters of your display, ready to use.</td>
</tr>
<tr>
<td width="50%" valign="top"><img src="docs/screenshots/select-box.jpg" alt="A selection box dragged across Notes, TextEdit and Clock, all three outlined"><br><strong>Drag on empty canvas to select windows,</strong> then drag any of them to move them together.</td>
<td width="50%" valign="top"><img src="docs/screenshots/select-layouts.jpg" alt="Three selected windows with a menu offering One left, two right and Two left, one right"><br><strong>Press <kbd>S</kbd> with a few selected</strong> to choose how they fill a screen.</td>
</tr>
<tr>
<td width="50%" valign="top"><img src="docs/screenshots/resize.jpg" alt="Calendar being widened by its right edge on the canvas, with its size in points showing below"><br><strong>Resize a window by its edges,</strong> right there on the canvas. Its size shows as you drag.</td>
<td width="50%" valign="top"><img src="docs/screenshots/sizes.jpg" alt="A right-click menu on Clock: Fill screen, Half screen, Quarter screen, Same size as, Back to its own size"><br><strong>Right-click a window</strong> for Fill, Half or Quarter screen, the size of another window, or its own size again.</td>
</tr>
<tr>
<td width="50%" valign="top"><img src="docs/screenshots/tidy-before.jpg" alt="The canvas with pairs of windows out of line and unevenly spaced"><br><strong>Before Tidy Up:</strong> windows out of line, with uneven gaps.</td>
<td width="50%" valign="top"><img src="docs/screenshots/tidy-after.jpg" alt="The same windows lined up and evenly spaced"><br><strong>After pressing <kbd>T</kbd>:</strong> each group lined up and evenly spaced.</td>
</tr>
<tr>
<td width="50%" valign="top"><img src="docs/screenshots/spaces.jpg" alt="The zoomed-out canvas with a Spaces panel beside the minimap, showing Expanse and a full-screen TextEdit"><br><strong>Full-screen apps keep their own Spaces.</strong> Jump to them, and back, from the Spaces panel next to the minimap.</td>
<td width="50%" valign="top"><img src="docs/screenshots/menu.jpg" alt="The menu bar panel: a live minimap, Centre window, Tidy up, the hot corner, and earlier layouts"><br><strong>The menu bar icon</strong> opens the rest: a live minimap, Pause, Centre and Tidy Up, which corner to use, and earlier layouts.</td>
</tr>
<tr>
<td width="50%" valign="top"><img src="docs/screenshots/paused.jpg" alt="Windows piled up in the middle of the screen, as macOS had them, with Expanse paused"><br><strong>Pause or quit</strong> and every window goes straight back to where macOS had it.</td>
<td width="50%" valign="top"><img src="docs/screenshots/welcome.jpg" alt="The Expanse welcome window: Your Mac, on an infinite canvas, with four quick steps"><br><strong>A short walkthrough</strong> gets you set up in about a minute.</td>
</tr>
</table>

## Questions

<details>
<summary><strong>The corner or <kbd>⌃</kbd> + arrows do nothing</strong></summary>

macOS got there first. Run the walkthrough again (menu bar icon › the **?** button), or change
the settings yourself:

- **Corners:** System Settings › Desktop & Dock › Hot Corners. Set the corners you want for Expanse
  to “–”, or pick a different corner from Expanse's menu bar icon.
- **<kbd>⌃</kbd> + arrows:** System Settings › Keyboard › Keyboard Shortcuts › Mission Control.
  Turn off *Mission Control*, *Application windows* and *Move left/right a space*.

</details>

<details>
<summary><strong>My windows ended up somewhere odd</strong></summary>

Menu bar icon › **Earlier layouts**: click one to put your windows back the way they were then.
Expanse keeps your last three, taken 15 minutes apart as you work (or when you press **Take
snapshot**), and a restore can be undone too: the layout you had becomes the newest earlier one.
**Tidy Up** neatens things where they are: windows 80pt or more apart count as separate groups, so
zones you keep apart stay apart. As a last resort, **Restore all windows** (beside Take snapshot)
brings every window that's out of view back on screen, cascaded from the top middle.

</details>

<details>
<summary><strong>Expanse doesn't see any of my windows</strong></summary>

Open System Settings › Privacy & Security › Accessibility (Device Control and Data Access on macOS
27), then turn Expanse off and on again.

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
