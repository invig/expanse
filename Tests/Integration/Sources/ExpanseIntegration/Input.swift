import AppKit

/// Keyboard, pointer and scroll events, posted as if from the hardware. Posting needs
/// Accessibility for Expanse Tests (System Settings › Privacy & Security › Accessibility).
/// Points are global CG coordinates (top-left of the main display, y down).
enum Input {
    static var allowed: Bool { AXIsProcessTrusted() }

    enum Key: CGKeyCode {
        case a = 0, c = 8, w = 13, t = 17, one = 18, equal = 24, minus = 27, zero = 29, q = 12, tab = 48, space = 49
        case grave = 50, escape = 53, returnKey = 36, left = 123, right = 124, down = 125, up = 126
    }

    static func key(_ key: Key, _ flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key.rawValue, keyDown: down)
            // Arrow keys carry these flags from a real keyboard.
            let arrows: [Key] = [.left, .right, .up, .down]
            e?.flags = flags.union(arrows.contains(key) ? [.maskNumericPad, .maskSecondaryFn] : [])
            e?.post(tap: .cghidEventTap)
            usleep(20_000)
        }
    }

    /// Holds modifier keys down (for a drag with ⌘, say) while `body` runs.
    static func holding(_ flags: CGEventFlags, _ body: () -> Void) {
        let src = CGEventSource(stateID: .hidSystemState)
        let keys: [(CGEventFlags, CGKeyCode)] = [(.maskCommand, 55), (.maskShift, 56), (.maskAlternate, 58), (.maskControl, 59)]
        for (f, code) in keys where flags.contains(f) {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
        body()
        for (f, code) in keys where flags.contains(f) {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
            e?.post(tap: .cghidEventTap)
        }
    }

    static var pointer: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    static func move(to p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(10_000)
    }

    /// Glides the pointer there in steps, as a hand would.
    static func glide(to p: CGPoint, steps: Int = 20) {
        let from = pointer
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            move(to: CGPoint(x: from.x + (p.x - from.x) * t, y: from.y + (p.y - from.y) * t))
            usleep(8_000)
        }
    }

    static func click(at p: CGPoint, flags: CGEventFlags = [], count: Int = 1) {
        move(to: p)
        for n in 1...count {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
                e?.flags = flags
                e?.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                e?.post(tap: .cghidEventTap)
                usleep(30_000)
            }
        }
    }

    static func drag(from a: CGPoint, to b: CGPoint, flags: CGEventFlags = [], steps: Int = 30) {
        move(to: a)
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: a, mouseButton: .left)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        usleep(50_000)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
            usleep(12_000)
        }
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: b, mouseButton: .left)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
        usleep(50_000)
    }

    /// The same drag, waiting between events without blocking the main thread: needed to drag
    /// one of Expanse Tests' own windows, which must answer as it's dragged.
    @MainActor static func dragAsync(from a: CGPoint, to b: CGPoint, flags: CGEventFlags = [], steps: Int = 30) async {
        move(to: a)
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: a, mouseButton: .left)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 80_000_000)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: b, mouseButton: .left)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    enum ScrollPhase: Int64 { case none = 0, began = 1, changed = 2, ended = 4 }

    /// A scroll of `dy`, `dx` points at the pointer. Trackpad scrolls come in phases; a mouse
    /// wheel's have none.
    static func scroll(dx: Int32 = 0, dy: Int32, flags: CGEventFlags = [], phase: ScrollPhase = .none) {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        e?.flags = flags
        if phase != .none {
            e?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            e?.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
        }
        e?.post(tap: .cghidEventTap)
        usleep(16_000)
    }

    /// A two-finger trackpad scroll: began, `steps` changes, ended.
    static func trackpadScroll(dx: Int32 = 0, dy: Int32, steps: Int = 10, flags: CGEventFlags = []) {
        scroll(dx: 0, dy: 0, flags: flags, phase: .began)
        for _ in 0..<steps { scroll(dx: dx / Int32(steps), dy: dy / Int32(steps), flags: flags, phase: .changed) }
        scroll(dx: 0, dy: 0, flags: flags, phase: .ended)
    }
}
