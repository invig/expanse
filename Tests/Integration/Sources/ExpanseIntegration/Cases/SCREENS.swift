import AppKit

/// Screens you build zoomed out (docs/regression/arranging.md, EDIT-27 on) and sizes picked
/// zoomed out (docs/regression/sizes.md, SIZE-15 on), with posted mouse and key events and the
/// runner's own windows, which Expanse sizes for real as you build.
@MainActor enum SCREENS {
    static let cases: [Case] = [
        Case("EDIT-27", "Dropping a window on another's side or corner makes the two a screen") { t in
            try t.needsInput()
            let (ws, o) = try await t.editRow(["EDIT-27 A", "EDIT-27 B"], gap: 800)
            let (a, b) = (ws[0], ws[1])
            let s = try await t.editZoomOut(on: CGPoint(x: o.x + 800, y: o.y + 130), scale: 0.4)
            let fa = try s.editFrame(a), fb = try s.editFrame(b)
            let mark = t.log.mark()
            // B's middle onto A's right side.
            let drag = EditDrag(from: s.editCentre(fb))
            defer { drag.release() }
            await drag.move(to: s.screenPoint(CGPoint(x: fa.maxX - fa.width * 0.1, y: fa.midY)), steps: 20)
            try await t.pause(0.2)
            drag.release()
            let line = try await t.expectLog("screen: ", since: mark, timeout: 5)
            try t.expect(line.contains("[\(a.id)] left") && line.contains("[\(b.id)] right") && line.hasSuffix("(drop)"),
                         "the screen made: \(line)")
            let after = try await t.settle()
            let half = screensHalf(after.viewport.size)
            try t.expectNear(try after.editFrame(a).origin, fa.origin, within: 1, "A, dropped on, staying where it was")
            for w in [a, b] {
                let f = try after.editFrame(w)
                try t.expect(abs(f.width - half.width) <= 2 && abs(f.height - half.height) <= 2,
                             "\(w.title) on the canvas should be half the screen (\(half)), not \(f.size)")
                try await t.until("the real \(w.title) half the screen", timeout: 5) {
                    w.real.map { abs($0.width - half.width) <= 2 && abs($0.height - half.height) <= 2 } ?? false
                }
            }
            // EDIT-34: ⌘Z puts both back, real sizes too.
            try await t.editKeysToCanvas()
            let undoMark = t.log.mark()
            Input.key(.z, .maskCommand)
            try await t.expectLog("undo: screen of 2", since: undoMark, timeout: 5)
            let undone = try await t.settle()
            try t.expectNear(try undone.editFrame(b).origin, fb.origin, within: 1, "B back where it was dragged from")
            try await t.until("the real B back to its size", timeout: 5) {
                b.real.map { abs($0.width - fb.width) <= 2 && abs($0.height - fb.height) <= 2 } ?? false
            }
        },
        Case("EDIT-29", "Select windows, press S, pick a layout") { t in
            try t.needsInput()
            let (ws, o) = try await t.editRow(["EDIT-29 A", "EDIT-29 B"], gap: 800)
            let s = try await t.editZoomOut(on: CGPoint(x: o.x + 800, y: o.y + 130), scale: 0.4)
            for w in ws { Input.click(at: s.editCentre(try s.editFrame(w)), flags: .maskShift) }
            try await t.editKeysToCanvas()
            let mark = t.log.mark()
            Input.key(.s)
            try await t.pause(0.5)
            // The menu of layouts: the first (Side by side).
            Input.key(.down)
            Input.key(.returnKey)
            let line = try await t.expectLog("screen: ", since: mark, timeout: 5)
            try t.expect(line.contains("[\(ws[0].id)] left") && line.contains("[\(ws[1].id)] right") && line.hasSuffix("(layout)"),
                         "the screen made: \(line)")
        },
        Case("EDIT-30", "The screen tool: a slot, then a window") { t in
            try t.needsInput()
            let (ws, o) = try await t.editRow(["EDIT-30 A"])
            let a = ws[0]
            // The view's middle well right of A, so A's picture is clear of the tool's frame.
            let s = try await t.editZoomOut(on: CGPoint(x: o.x + 1800, y: o.y + 130), scale: 0.25)
            try await t.editKeysToCanvas()
            let mark = t.log.mark()
            Input.key(.s)
            try await t.expectLog("screen tool: started", since: mark, timeout: 3)
            // The frame is the screen, a quarter size, in the view's middle: its right half's middle.
            let v = s.viewport
            Input.click(at: CGPoint(x: v.midX + v.width * s.scale / 4, y: v.midY))
            try await t.pause(0.3)
            Input.click(at: s.editCentre(try s.editFrame(a)))
            let line = try await t.expectLog("screen: ", since: mark, timeout: 5)
            try t.expect(line.contains("[\(a.id)] right") && line.hasSuffix("(tool)"), "the window placed: \(line)")
            Input.key(.returnKey)
            try await t.expectLog("screen tool: done (1 placed)", since: mark, timeout: 3)
            let half = screensHalf(v.size)
            try await t.until("the real A half the screen", timeout: 5) {
                a.real.map { abs($0.width - half.width) <= 2 && abs($0.height - half.height) <= 2 } ?? false
            }
            try t.expect(try await t.state().active, "a click on a window with the tool on shouldn't zoom into it")
        },
        Case("SIZE-15", "Resizing a window by its edges zoomed out") { t in
            try t.needsInput()
            let (ws, o) = try await t.editRow(["SIZE-15 A"])
            let a = ws[0]
            let s = try await t.editZoomOut(on: CGPoint(x: o.x + 200, y: o.y + 130), scale: 0.5)
            let fa = try s.editFrame(a)
            let mark = t.log.mark()
            // Just inside its right edge, 100pt right on screen (200 on the canvas), ⌘ held so it doesn't snap.
            let edge = s.screenPoint(CGPoint(x: fa.maxX, y: fa.midY))
            let drag = EditDrag(from: CGPoint(x: edge.x - 3, y: edge.y), flags: .maskCommand)
            defer { drag.release() }
            await drag.move(to: CGPoint(x: edge.x + 97, y: edge.y), steps: 20)
            drag.release()
            let line = try await t.expectLog("resize ", since: mark, timeout: 5)
            try t.expect(line.contains("[\(a.id)]") && line.hasSuffix("(handle)"), "the resize: \(line)")
            let width = fa.width + 200
            try await t.until("the real A \(Int(width)) wide", timeout: 5) { a.real.map { abs($0.width - width) <= 2 } ?? false }
            try t.expectNear(try await t.settle().editFrame(a).origin, fa.origin, within: 1, "A's top-left, staying put")
        },
        Case("SIZE-17", "The right-click size menu zoomed out") { t in
            try t.needsInput()
            let (ws, o) = try await t.editRow(["SIZE-17 A"])
            let a = ws[0]
            let s = try await t.editZoomOut(on: CGPoint(x: o.x + 200, y: o.y + 130), scale: 0.4)
            let mark = t.log.mark()
            screensRightClick(at: s.editCentre(try s.editFrame(a)))
            try await t.pause(0.5)
            // Fill screen, then Half screen.
            Input.key(.down)
            Input.key(.down)
            Input.key(.returnKey)
            let line = try await t.expectLog("resize ", since: mark, timeout: 5)
            try t.expect(line.contains("[\(a.id)]") && line.hasSuffix("(menu)"), "the resize: \(line)")
            let half = screensHalf(s.viewport.size)
            try await t.until("the real A half the screen", timeout: 5) {
                a.real.map { abs($0.width - half.width) <= 2 && abs($0.height - half.height) <= 2 } ?? false
            }
        },
    ]
}

/// A screen's half (Screens.frame) at the 20pt gap, for a screen of `size`.
private func screensHalf(_ size: CGSize, gap: CGFloat = 20) -> CGSize {
    CGSize(width: ((size.width - 3 * gap) / 2).rounded(.down), height: size.height - 2 * gap)
}

private func screensRightClick(at p: CGPoint) {
    Input.move(to: p)
    for type in [CGEventType.rightMouseDown, .rightMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .right)?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}
