# Coverage: every commit

[All areas](README.md)

Every commit, oldest first, with the cases that test it or why none does. Release commits
(a version number, or "Features: …") only change docs/features.md or Info.plist.

| Commit | Subject | Cases |
|---|---|---|
| 0cdf466 | Canvas: infinite-canvas window manager for macOS | CAPTURE-01, CAPTURE-02, DISPLAY-01, DISPLAY-02, EDIT-01, EDIT-02, EDIT-03, EDIT-04, EDIT-05, EDIT-06, EDIT-07, EDIT-08, NAV-01, NAV-02, NAV-03, NAV-04, NAV-05, NAV-06, NAV-07, NAV-08, NAV-09, NAV-10, NAV-11, NAV-12, NAV-13, NAV-14, NAV-15, NAV-16, NAV-17, NAV-18, PERSIST-01, PERSIST-02, PERSIST-03, PERSIST-04, PERSIST-05, PERSIST-06, PERSIST-07, PERSIST-08, PERSIST-09, PLACE-01, PLACE-02, PLACE-03, SIZE-01, SIZE-02, TRACK-01, TRACK-02, TRACK-03, TRACK-04, TRACK-05, TRACK-06, TRACK-07, TRACK-08, TRACK-09, TRACK-10, TRACK-11, UI-01, UI-02, UI-03, UI-04, UI-05, UI-06, UPDATE-01, URL-01, URL-02, URL-03, URL-04, URL-05, URL-06, URL-07, URL-08, URL-09, URL-10, URL-11 |
| 06a9a13 | Add hot corners and desktop picture background | NAV-19, NAV-20, NAV-21, PERSIST-08, UI-03, UI-07, UI-08, UI-09, UI-10 |
| 5dab7a1 | Open new windows in free canvas space | PLACE-03, PLACE-04, PLACE-05, TRACK-10, TRACK-12 |
| 3de4347 | Add group selection and an auto-centre toggle | EDIT-09, EDIT-10, EDIT-11, EDIT-12, EDIT-13, NAV-15, NAV-22, NAV-23, NAV-24 |
| 363d854 | Make auto-centre off mean off; log window moves | NAV-22, NAV-24, PLACE-06, SUPPORT-01, TRACK-13 |
| fbdc277 | Keep window sizes across restarts; grow windows without clipping | PERSIST-02, SIZE-03, SIZE-04 |
| 9f92b18 | Add arrow navigation, layout-keeping Tidy Up and steadier display changes | DISPLAY-01, EDIT-03, EDIT-14, EDIT-15, EDIT-16, EDIT-17, NAV-16, NAV-25, NAV-26, NAV-27, PERSIST-08, PLACE-03, SIZE-05, TRACK-14 |
| b14448d | Fix arrow navigation during glides and its direction picking | NAV-26, NAV-27, NAV-28, NAV-29 |
| 3144b09 | Make glides, hops and zoomed-out dragging fast | CAPTURE-02, EDIT-07, EDIT-18, EDIT-19, NAV-28, NAV-30, NAV-31, URL-12 |
| 2b994e0 | Faster zooms; zooming out and back returns to the same view | NAV-01, NAV-11, NAV-17, NAV-20, NAV-32 |
| d41ce2a | Capture at full resolution before zooming into a window | CAPTURE-03 |
| 0209aa7 | Survive lid-close display switches; keep chosen sizes honest | DISPLAY-03, DISPLAY-04, SIZE-01, SIZE-05, SIZE-06, URL-13 |
| b6f69cf | Don't forget windows beyond the edge of a shrinking screen | DISPLAY-05, PLACE-01, URL-14 |
| 29b2a32 | Home layout across screens, centre snap, capture only when needed | CAPTURE-04, DISPLAY-06, DISPLAY-07, EDIT-03, EDIT-17, EDIT-20, EDIT-21, SIZE-02 |
| c7cba50 | Rename to Expanse; first-launch walkthrough, README, MIT licence | PERSIST-01, SETUP-01, SETUP-02, SETUP-03, SETUP-04, UI-11, UPDATE-01, URL-01, URL-15 |
| ac50e01 | Fix issues from a pre-release bug and security review | DISPLAY-03, DISPLAY-08, NAV-33, PERSIST-03, PERSIST-10, PERSIST-11, PERSIST-12, PERSIST-13, PERSIST-14, SEC-01, SEC-02, SEC-03, SEC-04, SETUP-03, SETUP-05, SETUP-06, TRACK-10, TRACK-15, TRACK-16, TRACK-17, TRACK-18, TRACK-19, URL-10, URL-11, URL-13 |
| 7ee9f9d | Add the app icon | UI-12 |
| 0578497 | Add release script: universal build, Developer ID signing, notarisation, GitHub release | UPDATE-02 |
| 8899f27 | README: download the signed release | no case: docs only |
| faa7e36 | Only manage ordinary document windows | PLACE-02, PLACE-07 |
| b229427 | Run one copy at a time | SETUP-07, SETUP-08 |
| 44a7f91 | Never adopt the parking corner as a window's position; 20pt gaps when pushing apart | DISPLAY-09, TRACK-11, TRACK-20 |
| 24e646f | Version 0.1.1 | no case: release commit |
| d776526 | Keyboard hops centre their window when auto-centre is on | NAV-25, NAV-26, NAV-34, NAV-35 |
| 3542479 | Version 0.1.2 | no case: release commit |
| 61e6e55 | Performance at scale (50+ windows) | CAPTURE-05, CAPTURE-06, CAPTURE-07, CAPTURE-08, NAV-36, NAV-37, NAV-38, NAV-39, TRACK-21, TRACK-22, TRACK-23 |
| 6146145 | Capture within replayd's limits: 20 streams, snapshots for the rest | CAPTURE-01, CAPTURE-07, CAPTURE-09, CAPTURE-10, CAPTURE-11, CAPTURE-12, CAPTURE-13 |
| 60b2a87 | Display changes: move windows off the main thread; keep your overlaps | DISPLAY-10, DISPLAY-11 |
| 0229cb2 | Picture memory: full size only near the view | CAPTURE-11, CAPTURE-14 |
| c30b1b3 | Idle cost: watch every app, scan less | CAPTURE-15, TRACK-10, TRACK-24, TRACK-25 |
| 77be218 | Stream budget 16: leave replayd room for other apps | CAPTURE-01, CAPTURE-09, CAPTURE-16 |
| 37a8848 | Relaunch puts every window back exactly, even same-titled ones | PERSIST-02, PERSIST-15, PERSIST-16 |
| 14c9218 | Fix races found in review | CAPTURE-17, CAPTURE-18, DISPLAY-12, TRACK-26, TRACK-27 |
| 3a1f218 | Nothing streams at 100%; smaller stream buffer pools | CAPTURE-04, CAPTURE-07, CAPTURE-15, CAPTURE-19, CAPTURE-20 |
| 90eef27 | 0.1.3 | no case: release commit (version bump to 0.1.3) |
| af8eff8 | Catch every window when many open at once | PLACE-08, TRACK-28, TRACK-29, TRACK-30, TRACK-31, TRACK-32, TRACK-33 |
| 01b601c | Close a whole selection with one click | EDIT-08, EDIT-22, EDIT-23 |
| 3995854 | 0.1.4 | no case: release commit |
| bf8e9a6 | Walkthrough: four clear steps, live ticks, on-brand canvas | SETUP-09, SETUP-10, SETUP-11, SETUP-12, SETUP-13, SETUP-14, SETUP-15, UI-13 |
| 05457cb | Spaces beside the minimap; leave full-screen apps alone | SPACES-01, SPACES-02, SPACES-03, SPACES-04, SPACES-05 |
| 340f826 | Spaces bar: actually switch Spaces | SPACES-02, SPACES-06, SPACES-07, SPACES-08, URL-16 |
| 19a09e4 | Instant Space switching; no bounce out of full-screen apps | SPACES-02, SPACES-09, SPACES-10, SPACES-11, SPACES-12, SPACES-13 |
| 93804d5 | 0.1.5 | no case: release commit |
| 24b54b1 | Back to the canvas from a full-screen app keeps the canvas | SPACES-02, SPACES-12, SPACES-14, SPACES-15, URL-17 |
| 2885069 | Keep focus on the window you picked after a Space switch | SPACES-16, URL-18 |
| abdfdd5 | 0.1.6 | no case: release commit |
| 0cd0016 | Update from GitHub releases | UI-14, UPDATE-03, UPDATE-04, UPDATE-05, UPDATE-06, UPDATE-07, UPDATE-08, UPDATE-09, UPDATE-10, UPDATE-11, UPDATE-12, UPDATE-13, UPDATE-14, URL-19 |
| ed8baa0 | 0.1.7 | no case: release commit |
| 47eb117 | README hero in the icon's style | no case: docs only (docs/hero.svg) |
| f310f04 | No flash when a hop lands; review fixes | NAV-40, NAV-41, SEC-05, SEC-06, SPACES-17, SPACES-18, SPACES-19, SPACES-20, UI-15, UI-16, UI-17, UPDATE-15, UPDATE-16, URL-18 |
| 0bfd211 | 0.1.8 | no case: release commit |
| df75a6e | Install with Homebrew | UPDATE-17, UPDATE-18, UPDATE-19 |
| d7da75d | Setup: Expanse waits for the walkthrough; Screen Recording prompt in front | PERSIST-17, SETUP-16, SETUP-17, SETUP-18 |
| c9336a3 | 0.1.9 | no case: release commit |
| 09aabdf | Parking corner measured from the usable screen area | TRACK-01, TRACK-11, TRACK-34 |
| 401569b | 0.1.10 | no case: release commit |
| 1e85357 | Full-screen windows: neighbours stay put, and you land back on them | SPACES-17, SPACES-21, SPACES-22 |
| 288c7a5 | 0.1.11 | no case: release commit |
| 8dcba7d | Screen changes: the big-screen layout survives, and you stay centred | DISPLAY-02, DISPLAY-13, DISPLAY-14, DISPLAY-15, DISPLAY-16, SPACES-21 |
| be668bf | 0.1.12 | no case: release commit |
| c4d8ec4 | Minimap and Spaces stay under the windows during a glide | UI-18 |
| 9c1e040 | 0.1.13 | no case: release commit |
| 552ac0e | Capture recovers when replayd crashes | CAPTURE-21, CAPTURE-22 |
| 535247b | Click the desktop at 100% to zoom out | NAV-42 |
| f4e632a | Walkthrough: macOS's prompts and System Settings in front | SETUP-17, SETUP-19, SETUP-20, SETUP-21, SETUP-22, SETUP-23 |
| 959452c | 0.1.14 | no case: release commit |
| 4a4941f | README: click empty desktop to zoom out | no case: docs only (row removed in f70bf12; see NAV-42) |
| 8c2b732 | ⌃⌥C centres the window you're in | NAV-43, NAV-44, NAV-45, SETUP-15, URL-20 |
| 058b6ce | 0.1.15 | no case: release commit |
| 9ccd030 | Phone and FaceTime windows are left where their app puts them | PLACE-02, PLACE-09 |
| 2ae46bb | 0.1.16 | no case: release commit |
| a23c303 | Windows in view stop streaming before the overlay drops | CAPTURE-23, CAPTURE-24, CAPTURE-25 |
| 2ce42ea | 0.1.17 | no case: release commit |
| 021cb8b | expanse://appearance forces light or dark, to check Expanse's look in both | URL-21 |
| ccd4656 | ui-hill-climb round 1: Liquid Glass panels, appearance colours, concentric radii | UI-01, UI-19, UI-20 |
| 8e8f301 | ui-hill-climb round 2: AA secondary text, accent viewport, 11pt scale, appearance-aware full-screen tile, shared header row | UI-19, UI-20, UI-21, UI-22 |
| 37a41d9 | Hidden and minimised windows keep their spots across a restart | PERSIST-18, PERSIST-19 |
| ab759ab | Hidden and minimised windows keep their spots across a restart | PERSIST-18, PERSIST-19 |
| a727041 | Layout snapshots to go back to, from the menu bar | PERSIST-20, PERSIST-21, PERSIST-22, PERSIST-23, PERSIST-24, PERSIST-25, URL-22 |
| 03451fb | ui-hill-climb round 3: one glass well for full-screen Spaces, Canvas title with zoom value, distinct window blocks, concentric viewport, tint under the blocks | UI-19, UI-20, UI-21, UI-22 |
| e36baa4 | ui-hill-climb round 4: viewport ring off the blocks, 14pt insets, outer ring for the current Space, AA headers in dark, seams on light blocks | UI-19, UI-20, UI-21, UI-22 |
| 394c6e8 | ui-hill-climb round 5: quiet outline when the viewport frames everything, lighter seams in light, even air round the ring, no dimmed Spaces, full-strength headers in dark | UI-19, UI-20, UI-22 |
| beaf5b0 | ui-hill-climb round 6: text as AppKit labels on the glass (secondary headings, primary names), viewport reads as an area | no case: reverted by b8c8656 |
| b8c8656 | Revert "ui-hill-climb round 6: text as AppKit labels on the glass (secondary headings, primary names), viewport reads as an area" | no case: revert of beaf5b0 |
| 9475567 | ui-hill-climb round 7: crisp minimap windows, AA secondary text in both themes, hand cursor and hover ring on the map, soft lift under the glass | no case: reverted by a3c4a5a |
| a3c4a5a | Revert "ui-hill-climb round 7: crisp minimap windows, AA secondary text in both themes, hand cursor and hover ring on the map, soft lift under the glass" | no case: revert of 9475567 |
| a2be2f2 | ui-hill-climb round 8: Control Center module titles with the zoom as their value, crisp and firmer minimap windows, Space tiles light up at 100% too | no case: reverted by 578940c |
| 578940c | Revert "ui-hill-climb round 8: Control Center module titles with the zoom as their value, crisp and firmer minimap windows, Space tiles light up at 100% too" | no case: revert of a2be2f2 |
| e9a6f65 | The canvas's Space and the minimap are called Expanse, not Canvas | SPACES-02, UI-20, UI-21, URL-17 |
| 3c4c247 | Windows restored from the saved layout fit this screen, and so does the canvas when the display changes zoomed out | DISPLAY-17, DISPLAY-18 |
| a225c63 | Windows restored from the saved layout fit this screen, and so does the canvas when the display changes zoomed out | DISPLAY-17, DISPLAY-18 |
| def9c8d | Merge the Liquid Glass overlays (ui-hill-climb) | no case: merge commit. Its tree is identical to a225c63: it brought rounds 1–5 (6–8 reverted), 021cb8b, 37a41d9, e9a6f65 and a225c63 to main, with no changes of its own |
| 89a12f1 | Merge fix/display-fit (with fix/hidden-windows) | no case: merge commit with no changes (3c4c247 and ab759ab were already on main as a225c63 and 37a41d9) |
| 89acbd3 | Merge feature/layout-snapshots | no case: merge commit, brings exactly a727041 to main (see a727041) |
| 54c2f3d | Restored layouts are fitted to this screen; README covers Restore Layout | PERSIST-22, PERSIST-26, URL-22 |
| 4946342 | 0.1.18 | no case: release commit |
| bf5aace | A README for first-time users | SEC-07 |
| 74dac43 | Tabs keep their window's spot | PLACE-10, PLACE-11 |
| 1fa738d | 0.1.19 | no case: release commit |
| 49c6c06 | Tidy Up lines up each group where it is | EDIT-17, EDIT-24, EDIT-25, EDIT-26 |
| 3414eca | 0.1.20 | no case: release commit |
| eb224e7 | New windows open beside their source; VM windows keep their own size | CAPTURE-26, NAV-46, PLACE-03, PLACE-12, PLACE-13, SIZE-07, SIZE-08, URL-23 |
| cf31c1d | 0.1.21 | no case: release commit |
| c6c639e | Display changes keep every window's spot | DISPLAY-02, DISPLAY-19, DISPLAY-20, DISPLAY-21, PERSIST-27, SIZE-02, SIZE-09 |
| dc044f9 | Window names are hidden unless turned on | UI-06 |
| b3843a3 | Release builds open at login | SETUP-24, SETUP-25, SETUP-26 |
| 9428c25 | The canvas never covers another app's dialog | UI-04, UI-23, UI-24 |
| 8f04ed3 | 0.1.22 | no case: release commit |
| 0da6343 | Log why windows drop off the canvas | SUPPORT-02, SUPPORT-03 |
| 00fbfc7 | Troubleshooting menu: detailed logging and logs for a bug report | SUPPORT-04, SUPPORT-05, SUPPORT-06, SUPPORT-07, SUPPORT-08, SUPPORT-09, URL-24 |
| aae79ea | 0.1.23 | no case: release commit |
| ef9dad0 | Add the features list and the Windows port research | no case: docs only (docs/features.md, docs/windows-port.md) |
| f8407c7 | A window back from full screen keeps its spot | SPACES-23 |
| f9c8215 | Features: the full-screen fix, not yet released | no case: release commit (features.md only) |
| f3f1fa3 | Features: 0.1.24 | no case: release commit (features.md only) |
| b9dec84 | 0.1.24 | no case: release commit |
| 86fbd72 | Recover when macOS restarts its capture service | CAPTURE-27, CAPTURE-28 |
| 29ffe6a | An app that opens again gets its windows' spots back | PERSIST-28 |
| 1b1cc23 | VM windows keep their spot when they resize themselves | SIZE-10 |
| e1165df | Clicking a window you can see keeps a view you placed | NAV-47, NAV-48, NAV-49, TRACK-05 |
| 2cf27f2 | Features: today's fixes, not yet released | no case: release commit (features.md only) |
| d9f6203 | Features: 0.1.25 | no case: release commit (features.md only) |
| 43325f0 | 0.1.25 | no case: release commit |
| c047399 | A window in a column stays lined up when a smaller screen evens out widths | DISPLAY-22 |
| d5f1c91 | Features: the column fix, not yet released | no case: release commit (docs/features.md only) |
| e249814 | Window scans back off while macOS's capture service is stuck | CAPTURE-29, CAPTURE-30 |
| f615454 | Don't pile capture requests up in a stuck replayd | CAPTURE-31, CAPTURE-32, CAPTURE-33 |
| 5209c7d | An app's loading box doesn't take its main window's spot | PERSIST-29, PLACE-14 |
| 0305c39 | New windows go above the window they came from only as a last resort | PLACE-03, PLACE-15 |
| af693a2 | Features: 0.1.26 | no case: release commit (docs/features.md only) |
| 8f72c4d | 0.1.26 | no case: release commit (Info.plist version) |
| ed61c70 | New Finder windows open beside you, and closing one keeps the view | PLACE-16, PLACE-17, TRACK-35 |
| 50844aa | Back off when macOS refuses window scans | CAPTURE-34 |
| 96699d3 | Features: 0.1.27 | no case: release commit (docs/features.md only) |
| 92179bc | 0.1.27 | no case: release commit (Info.plist version) |
| 1a673fe | Sizes set with macOS's Fill, Moom or a shortcut stick | SIZE-01, SIZE-11, SIZE-12, SIZE-13, SIZE-14 |
| 64dadd9 | Features: 0.1.28; the dark background, not reproduced | no case: release commit (docs/features.md only; the dark background bug it logs is covered by UI-29) |
| 94612d0 | 0.1.28 | no case: release commit (Info.plist version) |
| 18c6751 | Point at the Windows version, released as 0.1.0 | no case: docs only (README link to Expanse for Windows, features.md) |
| 7c1a6f5 | Merge pull request #1 from invig/claude/nice-mcnulty-c7af27 | no case: merge commit; brings in only 18c6751 (README and docs/features.md, no code) |
| 42b415b | At 100% the real desktop shows through the backdrop | TRACK-03, UI-07, UI-25, UI-26 |
| a0709c7 | Features: the see-through backdrop, not yet released; the canvas's dimmed copy and the panels under peeking windows | no case: docs only (features.md) |
| 6cd5611 | Hiding an app, then ⌘-Tab to it, glides to its window | TRACK-04, TRACK-36, TRACK-37, TRACK-38 |
| 058fc62 | Clicking Expanse's own Space tile goes back to 100% | SPACES-02, SPACES-24 |
| f70bf12 | Desktop icons can be clicked at 100% | NAV-18, NAV-42, NAV-50, UI-27 |
| 077d3dd | The canvas's desktop is a fresh picture of the real one | CAPTURE-35, UI-07, UI-28, UI-29 |
| d33eab0 | A scroll at 100% snaps when it stops | NAV-18, NAV-51, NAV-52, NAV-53, NAV-54 |
| 20b2dd2 | Features: fresh desktop picture, clickable icons, scroll snapping, ⌘-Tab and Space tile fixes | no case: docs only (features.md) |
| 418fd73 | Features: 0.1.29 | no case: release commit (docs/features.md only) |
| 3662a94 | 0.1.29 | no case: release commit (Info.plist version) |
| 9183b47 | Locking the Mac or sleeping its displays no longer moves windows | DISPLAY-23, DISPLAY-24, DISPLAY-25 |
| 154ee21 | Restore Layout puts windows exactly where the snapshot had them | PERSIST-22, PERSIST-30, PERSIST-31 |
| 9c7d1c9 | Features: 0.1.30 | no case: release commit (docs/features.md only) |
| 32e339a | 0.1.30 | no case: release commit (Info.plist version) |
| 682e270 | Features: new windows not always picked up; regression tests | no case: docs only (backlog entries in features.md; the bug was later fixed by 4045597 and 08fca65, outside this range) |
| a2d80de | Menu bar panel in place of the menu, with Settings and Take snapshot | EDIT-14, PERSIST-03, PERSIST-07, PERSIST-20, PERSIST-22, PERSIST-32, SETUP-25, SUPPORT-04, SUPPORT-10, TRACK-09, UI-06, UI-07, UI-10, UI-11, UI-14, UI-30, UI-31, UI-32, UI-33, UI-34, UI-35, UI-36, UI-37, UI-38, UI-39, UPDATE-03, URL-25, URL-26 |
| 2d65ed9 | Closed windows and quit apps no longer keep window spots | PERSIST-28, PERSIST-33, PERSIST-34, PERSIST-35, TRACK-07, TRACK-39 |
| cb8f726 | Features: menu bar panel, fewer kept spots, Steam and restart bugs | no case: release commit (docs/features.md only) |
| 4045597 | Steam's window is taken on, slivers stay off the panels, restarts keep the layout | PERSIST-36, PERSIST-37, PERSIST-38, PERSIST-39, PLACE-02, SETUP-27, SUPPORT-11, TRACK-02, TRACK-40, UI-38, UI-40, URL-27 |
| 652d6ef | Features: the four bugs from 29 Oct fixed | no case: release commit (docs/features.md only) |
| 08fca65 | New windows that aren't takeable at first are picked up in seconds | SUPPORT-11, TRACK-41, TRACK-42 |
| ed54a07 | No layout snapshot with nothing on the canvas; poweroff link posts the real notification | PERSIST-21, PERSIST-32, PERSIST-40, PERSIST-41, URL-27 |
| 13a79d4 | Windows with no saved spot at launch go beside what's in view | PERSIST-02, PERSIST-39, PERSIST-42 |
| 271a303 | Features: 0.1.31 | no case: release commit (docs/features.md only) |
| 1be8dfd | 0.1.31 | no case: release commit (Info.plist version only) |
| 804e187 | After unlocking, ⌘-Tab follows and new windows go beside your work | DISPLAY-26, DISPLAY-27, DISPLAY-28 |
| 37186fd | Features: 0.1.32 | no case: release commit (docs/features.md only) |
| 746c008 | 0.1.32 | no case: release commit (Info.plist version only) |
| 47ed782 | Fix the issues from the security review | SEC-03, SEC-04, SEC-08, SEC-09, SEC-10, SEC-11, SEC-12, SEC-13, SEC-14, SEC-15, SEC-16, SEC-17, SEC-18, SEC-19, SEC-20, SEC-21, SEC-22, SEC-23, SEC-24, SEC-25, SEC-26, SEC-27, SEC-28, SEC-29, SEC-30, URL-10 |
| dc697d9 | Features: 0.1.33 | no case: release commit (docs/features.md only) |
| 5a1ca88 | 0.1.33 | no case: release commit (Info.plist version only) |
| 2f6c592 | Stop video blinking: no captures while you're at 100% | CAPTURE-04, CAPTURE-36, CAPTURE-37, CAPTURE-38 |
| 2ae6fdd | Features: 0.1.34 | no case: release commit (docs/features.md only) |
| 54a3cca | 0.1.34 | no case: release commit (Info.plist version only) |
