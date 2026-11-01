import CoreGraphics

/// A part of a screen you build on the canvas: a half or a quarter (or all of it). Its frame comes
/// from a screen-sized rectangle on the canvas (see Screens.frame); canvas space, y grows down.
enum Slot: String, CaseIterable {
    case left, right, topLeft, topRight, bottomLeft, bottomRight, full

    /// For the log: "top-left".
    var name: String {
        switch self {
        case .left: "left"
        case .right: "right"
        case .topLeft: "top-left"
        case .topRight: "top-right"
        case .bottomLeft: "bottom-left"
        case .bottomRight: "bottom-right"
        case .full: "full"
        }
    }

    var isLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
    var isQuarter: Bool { self == .topLeft || self == .topRight || self == .bottomLeft || self == .bottomRight }

    /// The half a quarter is part of.
    var half: Slot { isQuarter ? (isLeft ? .left : .right) : self }

    /// The half across from this slot's side: a window dropped here sends the one it was dropped
    /// on to the other side.
    var otherHalf: Slot { isLeft ? .right : .left }

    /// The quarters of a half, top first.
    var quarters: [Slot] {
        switch self {
        case .left: [.topLeft, .bottomLeft]
        case .right: [.topRight, .bottomRight]
        default: []
        }
    }

    /// Whether the two slots cover any of the same part of the screen.
    func overlaps(_ other: Slot) -> Bool {
        if self == other || self == .full || other == .full { return true }
        guard half == other.half else { return false }
        // The same side: a half covers its quarters; two quarters don't meet.
        return !(isQuarter && other.isQuarter)
    }
}

/// The edges of a window you're dragging to resize it (a corner is two).
struct WindowEdges: OptionSet {
    let rawValue: Int
    static let left = WindowEdges(rawValue: 1)
    static let right = WindowEdges(rawValue: 2)
    static let top = WindowEdges(rawValue: 4)
    static let bottom = WindowEdges(rawValue: 8)

    /// `start` with these edges moved by `d`, no smaller than `minimum` (the other edges stay).
    func move(_ start: CGRect, by d: CGVector, minimum: CGSize) -> CGRect {
        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        if contains(.left) { minX = min(start.minX + d.dx, maxX - minimum.width) }
        if contains(.right) { maxX = max(start.maxX + d.dx, minX + minimum.width) }
        if contains(.top) { minY = min(start.minY + d.dy, maxY - minimum.height) }
        if contains(.bottom) { maxY = max(start.maxY + d.dy, minY + minimum.height) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Which slots a screen of two, three or four windows has.
struct ScreenLayout: Equatable {
    let slots: [Slot]

    static let halves = ScreenLayout(slots: [.left, .right])
    static let leftAndQuarters = ScreenLayout(slots: [.left, .topRight, .bottomRight])
    static let quartersAndRight = ScreenLayout(slots: [.topLeft, .bottomLeft, .right])
    static let quarters = ScreenLayout(slots: [.topLeft, .topRight, .bottomLeft, .bottomRight])

    /// The layouts for `count` windows, the one to offer first first.
    static func layouts(for count: Int) -> [ScreenLayout] {
        switch count {
        case 2: [.halves]
        case 3: [.leftAndQuarters, .quartersAndRight]
        case 4: [.quarters]
        default: []
        }
    }
}

/// The geometry of screens you build: the gap goes between slots and round the edge, so a built
/// screen is windows a gap apart whose outline fits the screen, which is what a screen group is
/// (see CanvasController.screenGroups).
enum Screens {
    /// `slot`'s frame in a screen-sized rectangle on the canvas, in whole points.
    static func frame(of slot: Slot, in screen: CGRect, gap: CGFloat) -> CGRect {
        let inner = screen.insetBy(dx: gap, dy: gap)
        let leftWidth = ((inner.width - gap) / 2).rounded(.down), topHeight = ((inner.height - gap) / 2).rounded(.down)
        let rightX = inner.minX + leftWidth + gap, bottomY = inner.minY + topHeight + gap
        let left = CGRect(x: inner.minX, y: inner.minY, width: leftWidth, height: inner.height)
        let right = CGRect(x: rightX, y: inner.minY, width: inner.maxX - rightX, height: inner.height)
        switch slot {
        case .full: return inner
        case .left: return left
        case .right: return right
        case .topLeft: return CGRect(x: left.minX, y: inner.minY, width: left.width, height: topHeight)
        case .topRight: return CGRect(x: right.minX, y: inner.minY, width: right.width, height: topHeight)
        case .bottomLeft: return CGRect(x: left.minX, y: bottomY, width: left.width, height: inner.maxY - bottomY)
        case .bottomRight: return CGRect(x: right.minX, y: bottomY, width: right.width, height: inner.maxY - bottomY)
        }
    }

    /// Where a screen goes so a window with `frame` stays where it is once it's in `slot`.
    static func screenOrigin(keeping frame: CGRect, in slot: Slot, size: CGSize, gap: CGFloat) -> CGPoint {
        let offset = Self.frame(of: slot, in: CGRect(origin: .zero, size: size), gap: gap).origin
        return CGPoint(x: frame.minX - offset.x, y: frame.minY - offset.y)
    }

    /// The screen a group of windows was built as, and the slot each window is in: nil if it isn't
    /// one. Each window's top-left is on its slot's (within 4pt), and it's no bigger than the slot
    /// and at most `slack` smaller (apps round sizes: Terminal to character cells).
    static func layout(of frames: [CGRect], size: CGSize, gap: CGFloat, slack: CGFloat = 32) -> (screen: CGRect, slots: [Slot])? {
        guard frames.count > 1, let first = frames.first else { return nil }
        let outline = frames.dropFirst().reduce(first) { $0.union($1) }
        // The screen's top-left lines up with the outline's top or left unless the top row or left
        // column is empty: try each corner of the outline.
        let xs = [outline.minX - gap, outline.maxX + gap - size.width]
        let ys = [outline.minY - gap, outline.maxY + gap - size.height]
        for x in xs {
            for y in ys {
                let screen = CGRect(x: x, y: y, width: size.width, height: size.height)
                var slots: [Slot] = []
                for f in frames {
                    guard let slot = Slot.allCases.first(where: { s in
                        s != .full && !slots.contains(where: { $0.overlaps(s) }) && fits(f, frame(of: s, in: screen, gap: gap), slack: slack)
                    }) else { break }
                    slots.append(slot)
                }
                if slots.count == frames.count { return (screen, slots) }
            }
        }
        return nil
    }

    /// The slot a window with `frame` is in, in the screen at `screen` (as layout(of:) judges it):
    /// nil if it's in none.
    static func slot(of frame: CGRect, in screen: CGRect, gap: CGFloat, slack: CGFloat = 32) -> Slot? {
        Slot.allCases.first { $0 != .full && fits(frame, Self.frame(of: $0, in: screen, gap: gap), slack: slack) }
    }

    /// The screen tool's slot under `p`: a quarter near the top or bottom of a half, else the half.
    static func toolSlot(at p: CGPoint, in screen: CGRect) -> Slot? {
        guard screen.contains(p) else { return nil }
        let left = p.x < screen.midX, y = (p.y - screen.minY) / screen.height
        if y < 0.3 { return left ? .topLeft : .topRight }
        if y > 0.7 { return left ? .bottomLeft : .bottomRight }
        return left ? .left : .right
    }

    /// Putting a window in `slot` of a screen whose windows are in `taken`: where each of those
    /// goes. One in the half a quarter is part of moves to its other quarter; one already in the
    /// slot, or in a half you put a window in whole, leaves the screen (nil). The rest stay.
    static func makeWay(for slot: Slot, among taken: [Slot]) -> [Slot?] {
        taken.map { s in
            guard s.overlaps(slot) else { return s }
            if slot.isQuarter, s == slot.half { return slot.half.quarters.first { $0 != slot } }
            return nil
        }
    }

    private static func fits(_ f: CGRect, _ slot: CGRect, slack: CGFloat) -> Bool {
        abs(f.minX - slot.minX) <= 4 && abs(f.minY - slot.minY) <= 4
            && f.width <= slot.width + 2 && f.height <= slot.height + 2
            && f.width >= slot.width - slack && f.height >= slot.height - slack
    }

    /// Which slot each window goes in, by where they are now (their centres): the assignment that
    /// keeps them most where they are relative to each other.
    static func assign(_ centres: [CGPoint], to layout: ScreenLayout) -> [Slot] {
        guard centres.count == layout.slots.count, let first = centres.first else { return layout.slots }
        // Both sides in 0...1: the windows' spread, and the slots' places in a screen.
        var lo = first, hi = first
        for c in centres { lo = CGPoint(x: min(lo.x, c.x), y: min(lo.y, c.y)); hi = CGPoint(x: max(hi.x, c.x), y: max(hi.y, c.y)) }
        let spread = CGSize(width: max(hi.x - lo.x, 1), height: max(hi.y - lo.y, 1))
        let points = centres.map { CGPoint(x: ($0.x - lo.x) / spread.width, y: ($0.y - lo.y) / spread.height) }
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let targets = layout.slots.map { s -> CGPoint in
            let f = frame(of: s, in: unit, gap: 0)
            return CGPoint(x: f.midX, y: f.midY)
        }
        var best = layout.slots, bestCost = CGFloat.infinity
        for order in permutations(Array(layout.slots.indices)) {
            let cost = zip(points, order).reduce(CGFloat(0)) { sum, pair in
                let t = targets[pair.1]
                return sum + (pair.0.x - t.x) * (pair.0.x - t.x) + (pair.0.y - t.y) * (pair.0.y - t.y)
            }
            if cost < bestCost - 0.0001 { bestCost = cost; best = order.map { layout.slots[$0] } }
        }
        return best
    }

    private static func permutations(_ a: [Int]) -> [[Int]] {
        guard a.count > 1 else { return [a] }
        return a.indices.flatMap { i -> [[Int]] in
            var rest = a
            let x = rest.remove(at: i)
            return permutations(rest).map { [x] + $0 }
        }
    }

    /// The drop zone at `p` over a window at `target`: a quarter in a corner (the outer 30% both
    /// ways), a half at a side (the outer 35%), nothing in the middle (an ordinary move).
    static func dropZone(at p: CGPoint, in target: CGRect) -> Slot? {
        guard target.width > 0, target.height > 0, target.contains(p) else { return nil }
        let x = (p.x - target.minX) / target.width, y = (p.y - target.minY) / target.height
        let side: Bool? = x < 0.3 ? true : x > 0.7 ? false : nil
        let top: Bool? = y < 0.3 ? true : y > 0.7 ? false : nil
        if let side, let top {
            return side ? (top ? .topLeft : .bottomLeft) : (top ? .topRight : .bottomRight)
        }
        if x < 0.35 { return .left }
        if x > 0.65 { return .right }
        return nil
    }
}
