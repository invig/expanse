# EDIT: Arranging windows on the canvas

[All areas](README.md)

## EDIT-01 Drag a window on the canvas to move it
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. Drag a window's picture to empty canvas and let go.
  2. Press Esc (or click the window).
- **Expected:** Step 1: the picture follows the pointer and stays where dropped; the real window doesn't move yet. Step 2: back at 100%, the real window sits at its new spot relative to the others (or is parked if that's out of view), and the layout file is updated about a second later.
- **Automate:** manual: drag on the overlay, then the commit.

## EDIT-02 A tiny drag still counts as a click
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. Press on a window, move under 3 screen points, let go.
- **Expected:** The window doesn't move on the canvas; Expanse dives into it as for a click (NAV-12).
- **Automate:** manual: mouse events.

## EDIT-03 Dragged windows snap into place with guides
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 0cdf466 (0.1.0), 9f92b18 (0.1.0), 29b2a32 (0.1.0)
- **Setup:** Zoomed out, two windows side by side with space between.
- **Steps:**
  1. Drag window B towards window A's right side, slowly, and watch it.
  2. Drag B so its top nears A's top; then its centre nears A's centre.
  3. Drag B near the middle of the screen.
  4. Drag a window above a row of two or more windows and move it to their middle.
- **Expected:** Within about 10 screen points B snaps: its left edge to 20pt from A's right edge (the standard gap) or flush with A's edges; tops and bottoms line up. Centres snap more gently (half the reach, and an edge wins a tie). Near the middle of the screen it snaps dead centre. Above a row it can centre on the whole row. While snapped, pink guide lines show the alignment, spanning the windows involved; they vanish when you let go.
- **Automate:** unit: `CanvasController.snap(_:excluding:)` (offsets, chosen guide lines).
- **Note:** First commit: 8pt reach and a 24pt gap, centres equal to edges; 9f92b18 made it 10pt firm/5pt soft with a 20pt gap; 29b2a32 added the screen-centre snap.

## EDIT-04 Hold ⌘ while dragging to skip snapping
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** As EDIT-03.
- **Steps:**
  1. Hold ⌘ and drag B along the same path as in EDIT-03.
  2. Let go of ⌘ mid-drag.
- **Expected:** With ⌘ held, B follows the pointer exactly, no snaps, no guide lines. Releasing ⌘ mid-drag brings snapping back from the next movement.
- **Automate:** manual: modifier flags on drag events.
- **Note:** Since 31 Oct (not released yet) letting go ends the drag where the pointer is, even if the last moves never arrived (a busy window server drops them; the VM did).

## EDIT-05 Clicking or dragging a window brings it to the front of the canvas
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out, two windows overlapping, A on top.
- **Steps:**
  1. Drag B (the one underneath) a little.
- **Expected:** B is drawn on top of A as soon as you press on it, and stays on top.
- **Automate:** unit: `CanvasController.bringToFront(_:)` reorders `windows`.

## EDIT-06 Hover × closes a window
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 0cdf466 (0.1.0)
- **Setup:** Zoomed out to at least 40% so the window is wide on screen; a Finder window open.
- **Steps:**
  1. Hover the Finder window: a round dark × appears near its top-right corner.
  2. Click the ×.
- **Expected:** Expanse presses the window's own close button, so the window closes as if you'd clicked its red button (an app with unsaved changes asks as usual). Its picture leaves the canvas within about half a second and the minimap drops it. Clicking anywhere else on the window doesn't close it.
- **Check in log:** `dropped Finder[<id>]: not in the window list`
- **Automate:** unit: `WindowNode.closeRect(in:)` hit area | manual: AX close.

## EDIT-07 No × on windows too small on screen
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 0cdf466 (0.1.0), 3144b09 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. Zoom out until a window is under 220 screen points wide; hover it.
  2. Click where the × would be.
- **Expected:** No × shows, and the click dives into the window instead of closing it.
- **Automate:** unit: `WindowNode.closeMinWidth` (220) in `WindowNode.style`.
- **Note:** The first commit hid × below 140pt; 3144b09 raised it to 220pt.

## EDIT-08 ⌘W closes the selection, otherwise the window under the pointer
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 0cdf466 (0.1.0), 01b601c (0.1.4)
- **Setup:** Zoomed out, with at least four expendable windows (TextEdit, no unsaved changes).
- **Steps:**
  1. Drag a box around two windows to select them.
  2. Hover over a third, unselected window. Check its × and the selected windows' ×.
  3. Press ⌘W.
  4. Press Esc to clear any selection, hover over a window and press ⌘W.
- **Expected:** At step 2, × shows only on the hovered window; clicking it would close just that window. At step 3 the two selected windows close and the hovered one stays, because the selection wins. At step 4 only the hovered window closes.
- **Automate:** unit: CanvasView keyDown(⌘W) and close(_:). The target is the selection if there is one, otherwise the hovered window.

## EDIT-09 Clicking a window in the selection dives into it
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 3de4347 (0.1.0)
- **Setup:** Zoomed out, three windows selected.
- **Steps:**
  1. Click (no drag) one of the selected windows.
- **Expected:** The selection clears and Expanse dives into that window (NAV-12).
- **Automate:** manual: mouse events.

## EDIT-10 Drag on empty canvas to select windows
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 3de4347 (0.1.0)
- **Setup:** Zoomed out with 5+ windows.
- **Steps:**
  1. Press on empty canvas and drag a box across three windows.
  2. Let go.
- **Expected:** While dragging, a lightly tinted accent-coloured box follows the pointer. Every window it touches gets a thick accent border. With more than one selected, a dashed rounded outline surrounds them all. The selection stays after you let go.
- **Automate:** manual: mouse input on CanvasView.

## EDIT-11 ⇧-click and ⇧-drag add to the selection
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 3de4347 (0.1.0)
- **Setup:** Zoomed out, two windows selected (EDIT-10).
- **Steps:**
  1. ⇧-click a third window.
  2. ⇧-click it again.
  3. ⇧-drag a box over two more windows.
  4. Drag a box on empty canvas without ⇧.
- **Expected:** 1: added. 2: removed. 3: both added to the existing selection. 4: the old selection is cleared and only the windows in the new box are selected.
- **Automate:** manual: mouse input on CanvasView.

## EDIT-12 ⌘A selects every window; Esc clears it, then leaves
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 3de4347 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. Press ⌘A.
  2. Press Esc.
  3. Press Esc again.
- **Expected:** 1: every window is selected. 2: the selection clears and the canvas stays zoomed out. 3: back to 100%.
- **Automate:** manual: key input on CanvasView.

## EDIT-13 Dragging a selected window moves the group, snapping as one block
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 3de4347 (0.1.0)
- **Setup:** Zoomed out, three windows selected, another window D unselected nearby.
- **Steps:**
  1. Drag one of the selected windows towards D until the group's outer edge nears D's edge.
  2. Repeat holding ⌘.
  3. Click (without dragging) one of the selected windows.
- **Expected:** 1: all three move together, keeping their positions relative to each other. The group's bounding box snaps to D's edges or 20pt from it, with pink guide lines. 2: no snapping. 3: the selection clears and the canvas dives into that window at 100%.
- **Automate:** unit: CanvasController.snap(_:excluding:) with the group's bounding box (needs windows and camera injected).

## EDIT-14 Tidy Up from 100% opens the canvas first
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 9f92b18 (0.1.0), a2d80de (0.1.31)
- **Setup:** At 100%, an untidy layout.
- **Steps:**
  1. Panel › Tidy up.
- **Expected:** The canvas opens, then the layout is tidied (as in EDIT-17) and the view zooms to fit everything.
- **Automate:** manual: needs the canvas and a real tidy.

## EDIT-15 Edges and the 20pt gap snap firmly; centres snap softly
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 9f92b18 (0.1.0)
- **Setup:** Zoomed out with windows A and B.
- **Steps:**
  1. Drag B so its left edge comes within about 10 screen points of 20pt right of A.
  2. Drag B so its top nearly lines up with A's top.
  3. Drag B so its centre nears A's centre line, with an edge equally near something.
  4. Repeat 1 holding ⌘.
- **Expected:** 1: B snaps to exactly 20pt beside A. 2: tops line up with a pink guide line. 3: centres pull only within half the distance of edges, and the edge wins a tie. 4: no snapping. The snap distance is the same on screen at any zoom.
- **Automate:** unit: CanvasController.snap(_:excluding:) (needs windows and camera injected).

## EDIT-16 A window can centre on a whole row above or below
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 9f92b18 (0.1.0)
- **Setup:** Zoomed out. A row of three windows side by side; a narrower window W below them.
- **Steps:**
  1. Drag W left and right below the row.
- **Expected:** W's centre snaps to the middle of the whole row (not only one window's centre), with a guide line spanning the row. The same works for a column to the left or right.
- **Automate:** unit: CanvasController.snap(_:excluding:) row and column centring.

## EDIT-17 Tidy Up tidies each group where it is
- **Type:** Bug fix
- **Area:** EDIT
- **Commits:** 9f92b18 (0.1.0), 29b2a32 (0.1.0), 49c6c06 (0.1.20)
- **Before:** Tidy pushed overlaps apart across the whole canvas, so one stacked window could shove its row into the next group, and groups that came within 240pt were pulled together.
- **Setup:** Group A: three windows in a row, the middle one overlapping its neighbour by about 100pt. Group B: two windows at least 400pt to the right of A.
- **Steps:**
  1. Zoom out and press T.
- **Expected:** Inside A the overlap is pushed apart and gaps become 20pt. Group B doesn't move. The two groups are not pulled together.
- **Check in log:** `tidy moved <App>[<id>] by <dx>, <dy>` for each moved window, none for B's.
- **Automate:** unit: CanvasController.tidyUp(_:) on frames for both groups.

## EDIT-18 The close button only closes when it's showing
- **Type:** Bug fix
- **Area:** EDIT
- **Commits:** 3144b09 (0.1.0)
- **Before:** A click where the × would be closed the window even when the button wasn't showing (not hovered, or too small on screen to show one).
- **Setup:** Zoomed out so one window is under 220pt wide on screen and another is wider.
- **Steps:**
  1. Hover the small window and click its top-right corner.
  2. Hover the larger window; when × appears, click it.
- **Expected:** 1: no × appears and the window isn't closed; the click dives into it. 2: the window closes.
- **Automate:** unit: WindowNode.style hides the button under WindowNode.closeMinWidth (220), and WindowNode.closeVisible.

## EDIT-19 Dragging on the canvas stays smooth with busy apps
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 3144b09 (0.1.0)
- **Setup:** 30+ windows, including a busy browser. Log stream running.
- **Steps:**
  1. Zoom out and drag windows around continuously for 10s.
- **Expected:** Windows follow the pointer with no hitches. Window scans wait until the drag ends.
- **Check in log:** no `slow: drag step took` or `slow: …ms between drag events` lines.
- **Automate:** manual: real performance.

## EDIT-20 Tidy Up on a smaller screen holds on the big screen
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 29b2a32 (0.1.0)
- **Setup:** On a smaller screen, a group with overlaps and uneven gaps.
- **Steps:**
  1. Press ⌥`, then T.
  2. Switch to the big screen. Press ⌥`.
- **Expected:** The group is tidy on both screens. On the big screen it's the tidied arrangement at full sizes with 20pt gaps, not the untidy layout from before.
- **Automate:** unit: CanvasController.tidyUp(_:) on home frames, then derive(home:sizes:).

## EDIT-21 Dragging near the middle of the screen snaps to dead centre
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 29b2a32 (0.1.0)
- **Setup:** Zoomed out.
- **Steps:**
  1. Drag a window so its centre comes near the centre of the screen.
- **Expected:** It snaps so its centre is exactly at the screen's centre, horizontally, vertically or both, with a guide line through the window.
- **Automate:** unit: CanvasController.snap(_:excluding:) screen-centre candidates.

## EDIT-22 One × closes every selected window
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 01b601c (0.1.4)
- **Setup:** Zoomed out (⌥`), with three TextEdit documents that have no unsaved changes, plus other windows.
- **Steps:**
  1. ⇧-click the three TextEdit windows to select them.
  2. Hover over any one of them.
  3. Click the × in its corner.
- **Expected:** At step 2, × appears on all three selected windows at once, not only the hovered one. At step 3 all three close and the selection is cleared. Other windows are untouched, and the canvas stays responsive while they close.
- **Check in log:** `closing 3 windows`
- **Automate:** unit: CanvasView.isInGroup and WindowNode.style(showsClose:). With a selection of two or more windows, hovering one shows close on every selected node.
- **Note:** × only shows on a window wide enough on screen (WindowNode.closeMinWidth). A selection of one counts as no group.

## EDIT-23 Closing from the canvas still asks about unsaved changes
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 01b601c (0.1.4)
- **Setup:** Zoomed out, with two TextEdit documents selected: one saved, one with unsaved edits.
- **Steps:**
  1. Hover over either one and click ×.
- **Expected:** The saved document closes. The unsaved one is not force-closed: TextEdit asks whether to save it, as when you click its own close button (go to the window to answer). Expanse doesn't stall while TextEdit waits.
- **Automate:** manual. Each close presses the window's real close button (AX.close) on the Accessibility queue.

## EDIT-24 Tidy Up lines up edges that nearly line up and closes gaps
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 49c6c06 (0.1.20)
- **Setup:** One group: window B to the right of A, 50pt gap, B's top 40pt lower than A's. Window C below A, left edge 30pt to the right of A's, 60pt gap. A separate pair where one top is 100pt below the other.
- **Steps:**
  1. Zoom out and press T.
- **Expected:** B's top lines up with A's and the gap closes to 20pt; C's left edge lines up with A's and the gap closes to 20pt. In the separate pair (100pt apart, more than 60pt), the tops are not lined up. A line-up is skipped if it would bring a window closer than 20pt to another.
- **Automate:** unit: CanvasController.align(_:reach:gap:) and gravity(_:gap:) (alignReach 60, gap 20).

## EDIT-25 A group moves as a whole only when another grows into its space
- **Type:** Feature
- **Area:** EDIT
- **Commits:** 49c6c06 (0.1.20)
- **Setup:** Group A: two windows side by side, the right one overlapping the left by about 150pt. Group B: two windows about 100pt to the right of A.
- **Steps:**
  1. Zoom out and press T.
- **Expected:** A is tidied; since it grew to within 80pt of B, B moves right (or down) as a whole, its windows keeping their arrangement, and the groups stay at least 80pt apart.
- **Automate:** unit: CanvasController.separateGroups(_:groups:reach:).

## EDIT-26 Tidy Up right after a drag keeps what you dragged
- **Type:** Bug fix
- **Area:** EDIT
- **Commits:** 49c6c06 (0.1.20)
- **Before:** Tidy started from each window's home spot, which only updated when the layout saved, and every window scan postponed the save. Tidy put back groups you'd just dragged.
- **Setup:** Zoomed out, a group of windows selected.
- **Steps:**
  1. Drag the group to a new place.
  2. Press T straight away.
- **Expected:** The group is tidied at its new place, not put back where it was before the drag.
- **Automate:** manual: depends on scans and save timing; noteUserMove(_:from:) setting home could be unit-tested.

## EDIT-27 Dropping a window on another's side or corner makes the two a screen
- **Type:** Feature
- **Area:** EDIT
- **Commits:** unreleased (1 Nov)
- **Setup:** Zoomed out, two windows apart: A (say Notes) and B (Safari), well away from others.
- **Steps:**
  1. Drag B over A's right side and hold it there.
  2. Let go.
  3. Do the same with another pair, but over A's top-left corner; then over A's middle.
- **Expected:** Step 1: the right half of a screen-sized frame lights up, with the frame outlined round A. Step 2: A takes the left half and B the right, both sized to fit a gap apart, A's top-left where it was; windows in the way move clear. ⌥` then ⌃+arrow in from elsewhere frames both. Step 3: the corner makes B the top-left quarter and A the right half; over the middle nothing lights up and B just moves there. ⌘ held while dragging: no zones.
- **Check in log:** `screen: Notes[<id>] left, Safari[<id>] right (drop)` (the window dropped on first).
- **Automate:** unit: drop zones, the screen made and where it goes (`Screens.dropZone`, `CanvasView.dropPlan`, `CanvasController.arrange`).

## EDIT-28 Dropping into a screen you built fills an empty slot or splits a half
- **Type:** Feature
- **Area:** EDIT
- **Commits:** unreleased (1 Nov)
- **Setup:** A screen built as in EDIT-27 (A left, B right) and two more windows, C and D.
- **Steps:**
  1. Drag C over the bottom of B and let go.
  2. Make a screen of A (left) and B (top-right) only, then drag D into its empty bottom-right corner.
- **Expected:** Step 1: B moves to the top-right quarter and C takes the bottom-right one. Step 2: D fills the bottom-right quarter; the screen's other windows don't move.
- **Check in log:** `screen: Safari[<id>] top-right, Terminal[<id>] bottom-right (drop)`.
- **Automate:** unit: `Screens.layout(of:)` and drops into a built screen.

## EDIT-29 Select windows, press S, pick a layout
- **Type:** Feature
- **Area:** EDIT
- **Commits:** unreleased (1 Nov)
- **Setup:** Zoomed out, three windows: one on the left, two further right one above the other.
- **Steps:**
  1. Select the three (⇧-click or drag a box), press S.
  2. Pick "One left, two right" (or press 1).
  3. Right-click one of three selected windows.
- **Expected:** Step 1: a menu with the layouts three windows can make, drawn small. Step 2: the left one takes the left half, staying where it was, the others the right quarters in the order they were. Step 3: the same layouts under Make a screen. With one or five windows selected, S does nothing.
- **Check in log:** `screen: … (layout)`.
- **Automate:** unit: `Screens.assign`, `CanvasView.layoutMenu`, `makeScreen`.

## EDIT-30 The screen tool: a slot and a window, in either order
- **Type:** Feature
- **Area:** EDIT
- **Commits:** unreleased (1 Nov)
- **Setup:** Zoomed out, nothing selected, three windows.
- **Steps:**
  1. Press S (or right-click empty canvas › New screen).
  2. Click the frame's right half, then a window.
  3. Click another window, then the frame's left half.
  4. Click a third window, then near the bottom of the right half.
  5. Press Return. Then repeat 1–3 and press Esc instead.
- **Expected:** Step 1: an empty screen frame with its quarters outlined in the middle of the view; hovering lights a half (or a quarter near the top or bottom). Steps 2–3: each window goes into its slot at that size; a click on a window doesn't zoom into it. Step 4: the third takes the bottom-right quarter and the one in the right half moves up to the top-right. Step 5: Return leaves the screen as built; Esc puts every window back. The empty frame can be dragged by its edge.
- **Check in log:** `screen tool: started`, `screen: … (tool)` per window, `screen tool: done (3 placed)` or `cancelled`.
- **Automate:** unit: the tool's clicks, quarters, Esc undoing all.

## EDIT-31 Dragging a screen's ring moves the whole screen
- **Type:** Feature
- **Area:** EDIT
- **Commits:** unreleased (1 Nov)
- **Setup:** A screen of two windows built zoomed out.
- **Steps:**
  1. Hover the gap between them, or just outside them.
  2. Drag from there.
  3. Drag one of the windows away on its own.
- **Expected:** Step 1: the ring round the screen shows and the pointer is an open hand. Step 2: both windows move together, as a selection does. Step 3: just that window moves; once it's far enough, the other is on its own again.
- **Automate:** unit: the ring hit and the group drag.

## EDIT-32 Gaps between windows: 20pt, 10pt or none
- **Type:** Feature
- **Area:** EDIT
- **Commits:** unreleased (1 Nov)
- **Setup:** Settings › Gaps between windows.
- **Steps:**
  1. Build a screen of two windows; look at the gap between them and round the edge at 100%.
  2. Set Gaps between windows to 10pt, build another; then None.
  3. Drag a window towards another's edge zoomed out; press T.
- **Expected:** Step 1: 20pt between the windows and from the screen's edges. Step 2: 10pt, then none (the windows meet each other and the screen's edges). Step 3: snapping and Tidy Up keep the gap chosen. Each is still a screen group.
- **Automate:** unit: slot frames at each gap, and the setting read by snapping.

## EDIT-33 An app that won't take a slot's size keeps its own
- **Type:** Feature
- **Area:** EDIT
- **Commits:** unreleased (1 Nov)
- **Setup:** A VM window (UTM, Screen Sharing) or an app with a minimum size (System Settings) and another window.
- **Steps:**
  1. Drop the other window on the VM window's right side.
- **Expected:** The VM window keeps its size, its top-left at the left slot's; the other takes the right half. A toast: "UTM can't be made that size".
- **Check in log:** `can't size UTM[<id>] to {…}: took {…}`.
- **Automate:** unit: a window that sizes itself in `arrange`.

## EDIT-34 ⌘Z undoes the last screen or size zoomed out
- **Type:** Feature
- **Area:** EDIT
- **Commits:** unreleased (1 Nov)
- **Setup:** Zoomed out, some windows.
- **Steps:**
  1. Build a screen (any way), then resize one window by its edge.
  2. ⌘Z, ⌘Z, ⌘Z.
- **Expected:** The first ⌘Z undoes the resize, real window too; the second puts the screen's windows back where and how big they were (the dropped one where you dragged it from), and windows moved out of the way too; the third beeps. Plain moves aren't undone.
- **Check in log:** `undo: resize`, `undo: screen of 2`.
- **Automate:** unit: undo steps.

## EDIT-35 Windows 80pt or more apart stay separate zones through Tidy Up
- **Type:** Bug fix
- **Area:** EDIT
- **Commits:** fc52b9e (0.1.42)
- **Before:** Windows within 240pt counted as one group, chaining through neighbours, so Tidy Up pulled zones you'd kept apart on purpose back together.
- **Setup:** Two zones, 100pt apart. Inside each: two windows with a 50pt gap, the second's top 30pt lower.
- **Steps:**
  1. Zoom out and press T.
- **Expected:** Each zone is tidied where it is: a 20pt gap and its tops lined up. The first window of each zone doesn't move. Windows 79pt apart count as one group; 80pt apart, as two. Being close along one axis only doesn't make a group. Dragging a window to centre it on a row or column keeps its own 240pt reach (EDIT-16).
- **Check in log:** `tidy moved <App>[<id>] by <dx>, <dy>` for each zone's second window only.
- **Automate:** unit: CanvasController.tidyUp(_:). End-to-end: EDIT-35.
