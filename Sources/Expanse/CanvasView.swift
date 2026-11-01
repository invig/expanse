import AppKit
import Carbon.HIToolbox

/// Draws the canvas and turns trackpad / mouse / keyboard input into camera and window moves.
/// Internally everything is top-left view coordinates; `flip` converts to layer coordinates.
final class CanvasView: NSView {
    weak var controller: CanvasController!

    private let wallpaper = CALayer()
    private let world = CALayer()
    private let labels = CALayer()

    /// App names (and the hovered window's title) above the windows. Off unless chosen in the menu bar panel.
    static var showsNames: Bool {
        get { UserDefaults.standard.bool(forKey: "showWindowNames") }
        set { UserDefaults.standard.set(newValue, forKey: "showWindowNames") }
    }
    /// Height of the menu bar strip the wallpaper extends under, so it lines up with the real desktop.
    var menuBarHeight: CGFloat = 0 { didSet { needsLayout = true } }
    private let guides = CAShapeLayer()
    private let marquee = CAShapeLayer()
    private let selectionBox = CAShapeLayer()
    /// Around the screen group of the window you're hovering, zoomed out: what a click goes to.
    /// Its ring (and the gaps between its windows) moves the whole screen when dragged.
    private let groupOutline = CAShapeLayer()
    /// The screen whose ring the pointer is over (see screenRing).
    private var ringGroup: [ManagedWindow]?
    /// Where a window dragged over another, or into a screen you built, would go (see dropPlan):
    /// its slot filled, the screen outlined.
    private let dropSlot = CAShapeLayer()
    private let dropScreen = CAShapeLayer()
    private struct Drop {
        let placements: [(ManagedWindow, Slot)]
        let screen: CGRect
        let slot: CGRect
        /// The screen's windows already there, which stay.
        var members: [ManagedWindow] = []
    }
    private var drop: Drop?
    /// The screen tool (S with nothing selected, or New screen): a screen frame you fill by
    /// clicking a slot then a window, or a window then a slot.
    private struct Tool {
        var screen: CGRect
        var slot: Slot?
        var window: ManagedWindow?
        var hover: Slot?
        /// Undo steps it has taken, so Esc can put everything back.
        var steps = 0
    }
    private var tool: Tool?
    /// The tool's quarters, outlined.
    private let toolSlots = CAShapeLayer()
    /// Windows picked with a selection box or ⇧-click; dragging one moves them all.
    private(set) var selected = Set<CGWindowID>()
    private var spaceHeld = false
    private let minimap = Minimap()
    private let spacesBar = SpacesBar()
    private lazy var minimapGlass = GlassPanel(content: minimap) { [weak self] in self?.minimap.applyAppearance($0) }
    private lazy var spacesGlass = GlassPanel(content: spacesBar) { [weak self] in self?.spacesBar.applyAppearance($0) }
    var hovered: ManagedWindow?

    private enum Drag {
        case none
        case pan(last: CGPoint)
        case window(ManagedWindow, startFrame: CGRect, startPoint: CGPoint)
        case group(clicked: ManagedWindow, starts: [(ManagedWindow, CGRect)], startPoint: CGPoint)
        case marquee(start: CGPoint, base: Set<CGWindowID>)
        case minimap
        /// The screen tool's empty frame, by its edge.
        case toolScreen(start: CGRect, startPoint: CGPoint)
        /// A window's edges or corner (see resizeHandle).
        case resize(ManagedWindow, edges: WindowEdges, startFrame: CGRect, startPoint: CGPoint)
    }
    /// A window's size as you drag its edges: "726 × 909".
    private let sizeLabel = CATextLayer()
    /// The smallest a window can be dragged to.
    static let minimumSize = CGSize(width: 200, height: 120)
    private var drag: Drag = .none
    var isDragging: Bool { if case .none = drag { return false } else { return true } }
    private var dragged = false
    private var lastDragEvent: CFTimeInterval = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let root = layer else { return }
        root.masksToBounds = true
        wallpaper.contentsGravity = .resizeAspectFill
        wallpaper.actions = ["contents": NSNull()]
        // Underneath everything, the minimap and Spaces too when they go under the windows (see render).
        wallpaper.zPosition = -2
        root.addSublayer(wallpaper)
        for l in [world, labels, guides] {
            l.actions = ["sublayers": NSNull()]
            root.addSublayer(l)
        }
        guides.fillColor = nil
        guides.strokeColor = NSColor.systemPink.cgColor
        guides.lineWidth = 1
        marquee.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        marquee.strokeColor = NSColor.controlAccentColor.cgColor
        marquee.lineWidth = 1
        selectionBox.fillColor = nil
        selectionBox.strokeColor = NSColor.controlAccentColor.cgColor
        selectionBox.lineWidth = 1
        selectionBox.lineDashPattern = [5, 4]
        groupOutline.fillColor = nil
        groupOutline.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
        groupOutline.lineWidth = 1.5
        dropSlot.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        dropSlot.strokeColor = NSColor.controlAccentColor.cgColor
        dropSlot.lineWidth = 2
        dropScreen.fillColor = nil
        dropScreen.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        dropScreen.lineWidth = 1.5
        dropScreen.lineDashPattern = [6, 4]
        toolSlots.fillColor = nil
        toolSlots.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        toolSlots.lineWidth = 1
        toolSlots.lineDashPattern = [4, 4]
        for l in [marquee, selectionBox, groupOutline, toolSlots, dropScreen, dropSlot] {
            l.actions = ["path": NSNull()]
            root.addSublayer(l)
        }
        sizeLabel.fontSize = 12
        sizeLabel.alignmentMode = .right
        sizeLabel.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
        sizeLabel.isHidden = true
        root.addSublayer(sizeLabel)
        addSubview(spacesGlass)
        addSubview(minimapGlass)
        applyAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        world.anchorPoint = .zero
        for l in [world, labels, guides, marquee, selectionBox, groupOutline, toolSlots, dropScreen, dropSlot] { l.frame = bounds }
        // Pinned exactly where the real desktop picture is: the top strip sits under the menu bar.
        wallpaper.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height + menuBarHeight)
        minimapGlass.frame = CGRect(origin: CGPoint(x: bounds.maxX - Minimap.size.width - 16, y: 16), size: Minimap.size)
        placeSpacesBar()
        CATransaction.commit()
        render()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = window?.backingScaleFactor ?? 2
        minimap.setContentsScale(s)
        spacesBar.setContentsScale(s)
        controller?.windows.forEach { $0.node.setContentsScale(s) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    /// The Spaces beside the minimap (see SpacesBar).
    func updateSpaces(_ spaces: [Spaces.Space], active: UInt64?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spacesBar.update(spaces: spaces, active: active, wallpaper: wallpaper.contents.map { $0 as! CGImage })
        placeSpacesBar()
        CATransaction.commit()
    }

    /// The minimap and the Spaces panel, in view coordinates from the top left (as the camera's):
    /// what a window peeking in at the screen's edge mustn't cover (see CanvasController.goesOnScreen).
    var panelsFrame: CGRect {
        let panels = spacesGlass.isHidden ? [minimapGlass] : [minimapGlass, spacesGlass]
        return panels.reduce(CGRect.null) { $0.union(flip($1.frame)) }
    }

    private func placeSpacesBar() {
        spacesGlass.isHidden = spacesBar.isHidden
        spacesGlass.frame = CGRect(x: minimapGlass.frame.minX - 12 - spacesBar.bounds.width, y: 16,
                                   width: spacesBar.bounds.width, height: spacesBar.bounds.height)
    }

    func setWallpaper(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallpaper.contents = image
        wallpaper.isHidden = image == nil
        CATransaction.commit()
        applyAppearance()
    }

    private var hasWallpaper: Bool { wallpaper.contents != nil }

    /// The canvas's own background, behind its copy of the desktop picture (or instead of it).
    private var canvasBackground = NSColor(white: 0.85, alpha: 1).cgColor

    private func applyAppearance() {
        canvasBackground = (isDark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.85, alpha: 1)).cgColor
        render()
        controller?.windows.forEach { styleLabel($0.node.label) }
        styleLabel(sizeLabel)
    }

    /// White with a shadow over a desktop picture; quiet grey over the plain background.
    private func styleLabel(_ label: CATextLayer) {
        if hasWallpaper {
            label.foregroundColor = NSColor(white: 1, alpha: 0.95).cgColor
            label.shadowColor = NSColor.black.cgColor
            label.shadowOpacity = 0.7
            label.shadowRadius = 2
            label.shadowOffset = CGSize(width: 0, height: -1)
        } else {
            label.foregroundColor = (isDark ? NSColor(white: 0.7, alpha: 1) : NSColor(white: 0.3, alpha: 1)).cgColor
            label.shadowOpacity = 0
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    // MARK: Nodes

    func addNode(_ n: WindowNode) {
        world.addSublayer(n.container)
        labels.addSublayer(n.label)
        styleLabel(n.label)
    }

    func removeNode(_ n: WindowNode) {
        n.container.removeFromSuperlayer()
        n.label.removeFromSuperlayer()
    }

    func bringToFront(_ n: WindowNode) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        world.addSublayer(n.container)
        CATransaction.commit()
    }

    /// Keyboard navigation on the canvas: the highlighted window is the one Return dives into.
    func highlight(_ w: ManagedWindow) {
        hovered?.node.label.string = hovered?.appName
        hovered = w
        w.node.label.string = w.title.isEmpty ? w.appName : "\(w.appName) — \(w.title)"
        render()
    }

    // MARK: Rendering

    func render() {
        guard let c = controller else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        labels.isHidden = !Self.showsNames
        // At 100% the real desktop shows through (see OverlayWindow.backdropLevel); the canvas, and
        // a glide across it, draw their own copy of it.
        wallpaper.isHidden = wallpaper.contents == nil || !c.isActive
        let background = c.isActive ? canvasBackground : NSColor.clear.cgColor
        if layer?.backgroundColor != background { layer?.backgroundColor = background }
        let viewRect = CGRect(origin: .zero, size: bounds.size)
        selected.formIntersection(c.windows.map(\.id))
        if !c.isActive { selected.removeAll() }
        // The camera is one transform on the world layer: window nodes sit in canvas space
        // (y up), so panning and zooming never touch them individually.
        let s = c.camera.scale
        world.sublayerTransform = CATransform3DMakeAffineTransform(
            CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: -s * c.camera.origin.x, ty: bounds.height + s * c.camera.origin.y))
        // Hovering a window in a selection shows × on every selected window: it closes them all.
        let groupHovered = hovered.map(isInGroup) ?? false
        for w in c.windows {
            w.node.place(canvasFrame: w.canvasFrame)
            let r = c.camera.toView(w.canvasFrame)
            // In live mode the real window covers its proxy; only parked windows are drawn.
            let visible = r.insetBy(dx: -30, dy: -30).intersects(viewRect) && (c.isActive || w.parked)
            let isSelected = selected.contains(w.id)
            w.node.style(scale: s, hovered: w === hovered, selected: isSelected,
                         showsClose: w === hovered || (groupHovered && isSelected),
                         visible: visible, screenRect: flip(r))
        }
        let picked = c.windows.filter { selected.contains($0.id) }.map { c.camera.toView($0.canvasFrame) }
        if picked.count > 1, let first = picked.first {
            let box = picked.reduce(first) { $0.union($1) }.insetBy(dx: -8, dy: -8)
            selectionBox.path = CGPath(roundedRect: flip(box), cornerWidth: 6, cornerHeight: 6, transform: nil)
        } else {
            selectionBox.path = nil
        }
        if c.isActive, picked.count < 2, drop == nil, tool == nil, let group = hovered.flatMap(c.screenGroup) ?? ringGroup {
            groupOutline.path = CGPath(roundedRect: flip(ringBox(group)), cornerWidth: 10, cornerHeight: 10, transform: nil)
        } else {
            groupOutline.path = nil
        }
        func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
            CGPath(roundedRect: flip(c.camera.toView(r)), cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        dropSlot.path = nil
        dropScreen.path = nil
        toolSlots.path = nil
        if c.isActive, let t = tool {
            let gap = CanvasController.gap
            dropScreen.path = rounded(t.screen, 10)
            let quarters = CGMutablePath()
            for s in [Slot.topLeft, .topRight, .bottomLeft, .bottomRight] { quarters.addPath(rounded(Screens.frame(of: s, in: t.screen, gap: gap), 6)) }
            toolSlots.path = quarters
            if let s = t.slot ?? t.hover { dropSlot.path = rounded(Screens.frame(of: s, in: t.screen, gap: gap), 6) }
        } else if c.isActive, let d = drop {
            dropSlot.path = rounded(d.slot, 6)
            dropScreen.path = rounded(d.screen, 10)
        }
        minimap.update(windows: c.windows.map(\.canvasFrame), viewport: c.camera.toCanvas(viewRect), scale: c.camera.scale)
        // Gliding at 100%, the overlay is over the real windows, showing their pictures for a
        // moment: the minimap and Spaces stay under the windows, as they are before and after,
        // rather than jumping in front of them. Zoomed out, they're on top to be clicked.
        minimapGlass.layer?.zPosition = c.gliding ? -1 : 0
        spacesGlass.layer?.zPosition = c.gliding ? -1 : 0
        CATransaction.commit()
    }

    /// The window edges at `p` (its outer 6pt; two at a corner) of the top window there: dragging
    /// them resizes it. Inside only, so the gaps between a screen's windows still move the whole
    /// screen (see screenRing). Not a window that sizes itself (a VM's), one too small to tell
    /// its edges apart, or its close button.
    private func resizeHandle(at p: CGPoint) -> (ManagedWindow, WindowEdges)? {
        guard let w = controller.window(atView: p) else { return nil }
        let r = controller.camera.toView(w.canvasFrame)
        guard !w.sizesItself, r.width > 40, r.height > 30,
              !(w.node.closeVisible && WindowNode.closeRect(in: r).contains(p)) else { return nil }
        var edges: WindowEdges = []
        if p.x - r.minX <= 6 { edges.insert(.left) } else if r.maxX - p.x <= 6 { edges.insert(.right) }
        if p.y - r.minY <= 6 { edges.insert(.top) } else if r.maxY - p.y <= 6 { edges.insert(.bottom) }
        return edges.isEmpty ? nil : (w, edges)
    }

    private static func resizeCursor(_ edges: WindowEdges) -> NSCursor {
        let position: NSCursor.FrameResizePosition = switch edges {
        case [.left, .top]: .topLeft
        case [.right, .top]: .topRight
        case [.left, .bottom]: .bottomLeft
        case [.right, .bottom]: .bottomRight
        case .left: .left
        case .right: .right
        case .top: .top
        default: .bottom
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }

    /// The pointer for what's under it, set only when that changes.
    private var cursorKind = ""
    private func showCursor(_ kind: String, _ cursor: @autoclosure () -> NSCursor) {
        guard kind != cursorKind else { return }
        cursorKind = kind
        cursor().set()
    }

    /// "726 × 909" by the bottom-right corner of `w` as you resize it.
    private func showSize(of w: ManagedWindow) {
        let r = flip(controller.camera.toView(w.canvasFrame))
        sizeLabel.string = "\(Int(w.canvasFrame.width)) × \(Int(w.canvasFrame.height))"
        sizeLabel.contentsScale = window?.backingScaleFactor ?? 2
        sizeLabel.frame = CGRect(x: r.maxX - 160, y: r.minY - 20, width: 160, height: 16)
        sizeLabel.isHidden = false
    }

    /// Around a screen group, in the view: the outline drawn, and the ring you grab to move it.
    private func ringBox(_ group: [ManagedWindow]) -> CGRect {
        controller.camera.toView(CanvasController.outline(of: group)).insetBy(dx: -12, dy: -12)
    }

    /// The screen group whose ring is at `p` (not on one of its windows: the outline round it, or
    /// a gap between them).
    private func screenRing(at p: CGPoint) -> [ManagedWindow]? {
        controller.allScreenGroups().first { ringBox($0).contains(p) }
    }

    /// The drop zone under the pointer while `w` is dragged: an empty slot of a screen you built,
    /// or the top or bottom of one of its halves (split into quarters); else a side or corner of
    /// a window on its own (see Screens.dropZone), which pairs the two. Nil over nothing, or the
    /// middle of a window: an ordinary move.
    private func dropPlan(for w: ManagedWindow, at p: CGPoint) -> Drop? {
        let c = controller.camera.toCanvas(p)
        let gap = CanvasController.gap
        for built in controller.builtScreens(excluding: w) where built.screen.contains(c) {
            if let (m, slot) = built.members.first(where: { $0.0.canvasFrame.contains(c) }) {
                guard slot == .left || slot == .right else { return nil }
                let q = slot.quarters, top = c.y < m.canvasFrame.midY
                let mine = top ? q[0] : q[1]
                return Drop(placements: [(m, top ? q[1] : q[0]), (w, mine)], screen: built.screen,
                            slot: Screens.frame(of: mine, in: built.screen, gap: gap), members: built.members.map(\.0))
            }
            let taken = built.members.map(\.1)
            guard let free = [Slot.left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight].first(where: { s in
                !taken.contains { $0.overlaps(s) } && Screens.frame(of: s, in: built.screen, gap: gap).contains(c)
            }) else { return nil }
            return Drop(placements: [(w, free)], screen: built.screen, slot: Screens.frame(of: free, in: built.screen, gap: gap),
                        members: built.members.map(\.0))
        }
        guard let target = controller.window(atView: p, excluding: w), let mine = Screens.dropZone(at: c, in: target.canvasFrame) else {
            return nil
        }
        let theirs = mine.otherHalf
        let origin = Screens.screenOrigin(keeping: target.canvasFrame, in: theirs, size: controller.screenRect(at: .zero).size, gap: gap)
        let screen = controller.screenRect(at: origin)
        return Drop(placements: [(target, theirs), (w, mine)], screen: screen, slot: Screens.frame(of: mine, in: screen, gap: gap))
    }

    /// Part of a selection of more than one window (which × and ⌘W close together).
    private func isInGroup(_ w: ManagedWindow) -> Bool {
        selected.count > 1 && selected.contains(w.id)
    }

    /// Close `w`, or the whole selection if `w` is part of it.
    private func close(_ w: ManagedWindow) {
        if isInGroup(w) {
            controller.close(controller.windows.filter { selected.contains($0.id) })
            selected.removeAll()
        } else {
            controller.close([w])
        }
    }

    private func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height)
    }

    private func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: bounds.height - p.y) }

    private func showGuides(_ lines: [(CGPoint, CGPoint)]) {
        let path = CGMutablePath()
        for (a, b) in lines {
            path.move(to: flip(controller.camera.toView(a)))
            path.addLine(to: flip(controller.camera.toView(b)))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guides.path = lines.isEmpty ? nil : path
        CATransaction.commit()
    }

    // MARK: Event helpers

    /// Event location in top-left view coordinates.
    private func point(_ e: NSEvent) -> CGPoint {
        flip(convert(e.locationInWindow, from: nil))
    }

    private func minimapPoint(_ e: NSEvent) -> CGPoint? {
        guard let root = layer else { return nil }
        let p = minimap.convert(convert(e.locationInWindow, from: nil), from: root)
        return minimap.bounds.contains(p) ? p : nil
    }

    /// Where each Space's tile in the Spaces bar is on screen (global, top-left origin), for
    /// expanse://dump. None while the bar is hidden.
    func spacesTileFrames() -> [(id: UInt64, frame: CGRect)] {
        guard let root = layer, let window, !spacesBar.isHidden else { return [] }
        let h = NSScreen.screens.first?.frame.height ?? 0
        return zip(spacesBar.spaces, spacesBar.tileFrames).map { space, f in
            let s = window.convertToScreen(convert(spacesBar.convert(f, to: root), to: nil))
            return (space.id, CGRect(x: s.minX, y: h - s.maxY, width: s.width, height: s.height))
        }
    }

    /// Over the Spaces bar: which tile, if any (`nil` tile over the bar's background).
    private func spacesBarHit(_ e: NSEvent) -> (over: Bool, tile: Int?) {
        guard let root = layer, !spacesBar.isHidden else { return (false, nil) }
        let p = spacesBar.convert(convert(e.locationInWindow, from: nil), from: root)
        return (spacesBar.bounds.contains(p), spacesBar.tile(at: p))
    }

    // MARK: Trackpad

    override func scrollWheel(with e: NSEvent) {
        guard !controller.gliding else { return }
        guard controller.isActive else { controller.enter(zoomOut: false); return }
        if e.modifierFlags.contains(.command) {
            let k: CGFloat = e.hasPreciseScrollingDeltas ? 0.006 : 0.06
            controller.zoom(by: exp(e.scrollingDeltaY * k), at: point(e))
        } else {
            let k: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 12
            controller.pan(by: CGVector(dx: e.scrollingDeltaX * k, dy: e.scrollingDeltaY * k), scrolling: true)
            scrollMayEnd(e)
        }
    }

    private var scrollEnd: DispatchWorkItem?

    /// Tells the controller when a scroll that moved the view is over (see scrollEnded): when its
    /// momentum ends, or the fingers lift with none to follow. A wheel's ticks have no phases,
    /// so there a pause is the end.
    private func scrollMayEnd(_ e: NSEvent) {
        scrollEnd?.cancel()
        let wait: TimeInterval
        if e.momentumPhase == .ended || e.momentumPhase == .cancelled { wait = 0 }
        // Momentum, if any, starts straight after.
        else if e.momentumPhase == [], e.phase == .ended || e.phase == .cancelled { wait = 0.08 }
        else if e.momentumPhase == [], e.phase == [] { wait = 0.25 }
        else { return }
        let work = DispatchWorkItem { [weak self] in self?.controller.scrollEnded() }
        scrollEnd = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    override func magnify(with e: NSEvent) {
        guard !controller.gliding else { return }
        guard controller.isActive else { controller.enter(zoomOut: false); return }
        controller.zoom(by: 1 + e.magnification, at: point(e))
    }

    override func smartMagnify(with e: NSEvent) {
        guard !controller.gliding else { return }
        guard controller.isActive else { controller.enter(zoomOut: true); return }
        controller.toggleOverview(at: point(e))
    }

    // MARK: Mouse

    override func mouseDown(with e: NSEvent) {
        guard !controller.gliding else {
            logger.info("click ignored: a glide is under way")
            return
        }
        guard controller.isActive else {
            // Live mode: a click on a parked window's picture on the backdrop goes to that window,
            // and the Spaces bar works here too; anywhere else Expanse draws (the minimap), it
            // zooms out. The bare desktop is see-through, so its clicks go to the desktop itself.
            drag = .none
            let bar = spacesBarHit(e)
            let at = point(e)
            logger.info("click at 100% at \(NSStringFromPoint(at), privacy: .public): \(bar.tile.map { "Spaces tile \($0 + 1)" } ?? (bar.over ? "the Spaces bar, between tiles" : "the backdrop"), privacy: .public)")
            if let i = bar.tile {
                spacesBar.hovered = nil
                controller.switchToSpace(spacesBar.spaces[i])
                return
            }
            if let w = controller.window(atView: point(e), parkedOnly: true) {
                controller.focus(w)
            } else if !bar.over {
                controller.enter(zoomOut: true)
            }
            return
        }
        controller.cancelAnimation()
        dragged = false
        if sizing != nil {
            drag = .none
            finishSizing(at: point(e))
            return
        }
        if tool != nil {
            toolClick(at: point(e))
            return
        }
        let bar = spacesBarHit(e)
        if bar.over {
            drag = .none
            if let i = bar.tile {
                // Hover only updates while zoomed out; don't leave the tile lit after leaving.
                spacesBar.hovered = nil
                controller.switchToSpace(spacesBar.spaces[i])
            }
            return
        }
        if let mp = minimapPoint(e) {
            drag = .minimap
            controller.center(on: minimap.canvasPoint(at: mp))
            return
        }
        let p = point(e)
        let shift = e.modifierFlags.contains(.shift)
        if spaceHeld {
            drag = .pan(last: p)
            NSCursor.closedHand.set()
        } else if !shift, let (w, edges) = resizeHandle(at: p) {
            selected.removeAll()
            controller.bringToFront(w)
            // Undistorted while the frame changes; the real window catches up when you let go.
            w.node.content.contentsGravity = .resizeAspect
            drag = .resize(w, edges: edges, startFrame: w.canvasFrame, startPoint: p)
        } else if let w = controller.window(atView: p) {
            if w.node.closeVisible, WindowNode.closeRect(in: controller.camera.toView(w.canvasFrame)).contains(p) {
                drag = .none
                close(w)
                render()
                return
            }
            if shift {
                // ⇧-click toggles the window in the selection.
                if selected.remove(w.id) == nil { selected.insert(w.id) }
                drag = .none
            } else if selected.contains(w.id) && selected.count > 1 {
                let group = controller.windows.filter { selected.contains($0.id) }
                group.forEach(controller.bringToFront)
                drag = .group(clicked: w, starts: group.map { ($0, $0.canvasFrame) }, startPoint: p)
            } else {
                selected.removeAll()
                controller.bringToFront(w)
                drag = .window(w, startFrame: w.canvasFrame, startPoint: p)
            }
        } else if !shift, let group = screenRing(at: p) {
            // A screen's ring: the whole screen moves (a click without moving goes to it).
            selected.removeAll()
            group.forEach(controller.bringToFront)
            drag = .group(clicked: group[0], starts: group.map { ($0, $0.canvasFrame) }, startPoint: p)
            NSCursor.closedHand.set()
        } else {
            drag = .marquee(start: p, base: shift ? selected : [])
            if !shift { selected.removeAll() }
        }
        render()
    }

    override func mouseDragged(with e: NSEvent) {
        guard !controller.gliding else { return }
        let started = CACurrentMediaTime()
        defer {
            let ms = Int((CACurrentMediaTime() - started) * 1000)
            if ms > 16 { logger.info("slow: drag step took \(ms)ms") }
            if lastDragEvent > 0, started - lastDragEvent > 0.1 {
                logger.info("slow: \(Int((started - self.lastDragEvent) * 1000))ms between drag events")
            }
            lastDragEvent = started
        }
        guard controller.isActive else { controller.enter(zoomOut: false); return }
        let p = point(e)
        let s = controller.camera.scale
        let snapEnabled = !e.modifierFlags.contains(.command)
        switch drag {
        case .none:
            break
        case .minimap:
            if let mp = minimapPoint(e) { controller.center(on: minimap.canvasPoint(at: mp)) }
        case .pan(let last):
            dragged = true
            controller.pan(by: CGVector(dx: p.x - last.x, dy: p.y - last.y))
            drag = .pan(last: p)
        case .window(let w, let startFrame, let startPoint):
            if !dragged && p.distance(to: startPoint) < 3 { return }
            dragged = true
            let proposed = startFrame.offsetBy(dx: (p.x - startPoint.x) / s, dy: (p.y - startPoint.y) / s)
            // Over a drop zone the window follows the pointer, unsnapped (⌘ turns both off).
            drop = snapEnabled ? dropPlan(for: w, at: p) : nil
            let (frame, lines) = snapEnabled && drop == nil ? controller.snap(proposed, excluding: [w.id]) : (proposed, [])
            w.canvasFrame = frame
            showGuides(lines)
            render()
        case .group(_, let starts, let startPoint):
            if !dragged && p.distance(to: startPoint) < 3 { return }
            dragged = true
            let d = CGVector(dx: (p.x - startPoint.x) / s, dy: (p.y - startPoint.y) / s)
            // Snap the group's bounding box as one block against everything else.
            let bounds = starts.map(\.1).reduce(starts[0].1) { $0.union($1) }
            let proposed = bounds.offsetBy(dx: d.dx, dy: d.dy)
            let (snapped, lines) = snapEnabled ? controller.snap(proposed, excluding: Set(starts.map(\.0.id))) : (proposed, [])
            let dx = d.dx + snapped.minX - proposed.minX, dy = d.dy + snapped.minY - proposed.minY
            for (w, start) in starts { w.canvasFrame = start.offsetBy(dx: dx, dy: dy) }
            showGuides(lines)
            render()
        case .resize(let w, let edges, let start, let startPoint):
            if !dragged && p.distance(to: startPoint) < 3 { return }
            dragged = true
            let moved = edges.move(start, by: CGVector(dx: (p.x - startPoint.x) / s, dy: (p.y - startPoint.y) / s), minimum: Self.minimumSize)
            let (frame, lines) = snapEnabled ? controller.snapEdges(moved, moving: edges, excluding: w.id) : (moved, [])
            w.canvasFrame = edges.move(frame, by: .zero, minimum: Self.minimumSize)
            showGuides(lines)
            showSize(of: w)
            render()
        case .toolScreen(let start, let startPoint):
            dragged = true
            tool?.screen = start.offsetBy(dx: ((p.x - startPoint.x) / s).rounded(), dy: ((p.y - startPoint.y) / s).rounded())
            render()
        case .marquee(let start, let base):
            dragged = true
            let box = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            marquee.path = CGPath(rect: flip(box), transform: nil)
            let hits = controller.windows.filter { controller.camera.toView($0.canvasFrame).intersects(box) }.map(\.id)
            selected = base.union(hits)
            render()
        }
    }

    override func mouseUp(with e: NSEvent) {
        // Where you let go is where a window drag ends, even if the last moves before it never
        // came: a busy window server drops them, and the window stopped short of the pointer.
        if dragged {
            switch drag {
            case .window, .group, .resize: mouseDragged(with: e)
            default: break
            }
        }
        lastDragEvent = 0
        showGuides([])
        marquee.path = nil
        let dropped = drop
        drop = nil
        switch drag {
        case .window(let w, let startFrame, _):
            if dragged, let d = dropped {
                // From where it started: ⌘Z puts it back there, not where you let go.
                w.canvasFrame = startFrame
                controller.arrange(d.placements, screen: d.screen.origin, members: d.members, how: "drop")
            } else if dragged {
                controller.noteUserMove(w, from: startFrame.origin)
                controller.scheduleSave()
            } else {
                selected.removeAll()
                controller.exit(focus: w)
            }
        case .group(let w, let starts, _):
            if dragged {
                for (moved, start) in starts { controller.noteUserMove(moved, from: start.origin) }
                controller.scheduleSave()
            } else {
                selected.removeAll()
                controller.exit(focus: w)
            }
        case .resize(let w, _, let start, _):
            w.node.content.contentsGravity = .resize
            sizeLabel.isHidden = true
            if dragged {
                // From where it started, so ⌘Z puts it back there.
                let target = w.canvasFrame
                w.canvasFrame = start
                controller.resize(w, to: target.size, at: target.origin, how: "handle")
            }
        case .pan:
            if spaceHeld { NSCursor.openHand.set() }
        default:
            break
        }
        // The next move sets the pointer for what's under it.
        cursorKind = ""
        drag = .none
        render()
    }

    override func mouseMoved(with e: NSEvent) {
        guard controller.isActive else { return }
        let bar = spacesBarHit(e)
        spacesBar.hovered = bar.tile
        let free = minimapPoint(e) == nil && !bar.over
        if var t = tool {
            let s = free ? Screens.toolSlot(at: controller.camera.toCanvas(point(e)), in: t.screen) : nil
            if s != t.hover {
                t.hover = s
                tool = t
                render()
            }
        }
        let w = free ? controller.window(atView: point(e)) : nil
        let ring = free && w == nil && tool == nil ? screenRing(at: point(e)) : nil
        let ringChanged = (ring == nil) != (ringGroup == nil) || ring?.first !== ringGroup?.first
        if ringChanged { ringGroup = ring }
        if sizing != nil {
            showCursor("pick", .crosshair)
        } else if !spaceHeld {
            if free, tool == nil, let (_, edges) = resizeHandle(at: point(e)) {
                showCursor("resize \(edges.rawValue)", Self.resizeCursor(edges))
            } else if ring != nil {
                showCursor("ring", .openHand)
            } else {
                showCursor("arrow", .arrow)
            }
        }
        if w !== hovered {
            hovered?.node.label.string = hovered?.appName
            hovered = w
            if let w { w.node.label.string = w.title.isEmpty ? w.appName : "\(w.appName) — \(w.title)" }
            render()
        } else if ringChanged {
            render()
        }
    }

    // MARK: Keyboard

    override func keyDown(with e: NSEvent) {
        guard !controller.gliding else { return }
        guard controller.isActive else { super.keyDown(with: e); return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        switch Int(e.keyCode) {
        case kVK_Escape:
            if sizing != nil {
                sizing = nil
                NSCursor.arrow.set()
            } else if tool != nil {
                finishTool(cancel: true)
            } else if selected.isEmpty { controller.exit() } else { selected.removeAll(); render() }
        case kVK_ANSI_Z where e.modifierFlags.contains(.command):
            if tool != nil { NSSound.beep() } else if controller.canUndo { controller.undo() } else { NSSound.beep() }
        case kVK_ANSI_S where e.modifierFlags.intersection([.command, .option, .control]).isEmpty:
            // 2–4 picked: the screens they can make. None: the screen tool, here.
            let picked = controller.windows.filter { selected.contains($0.id) }
            if tool != nil {
                break
            } else if picked.isEmpty {
                startTool(centredOn: controller.camera.toCanvas(center))
            } else if (2...4).contains(picked.count) {
                showLayouts(for: picked)
            } else {
                NSSound.beep()
            }
        case kVK_Return where tool != nil:
            finishTool()
        case kVK_LeftArrow: controller.navigate(.left)
        case kVK_RightArrow: controller.navigate(.right)
        case kVK_UpArrow: controller.navigate(.up)
        case kVK_DownArrow: controller.navigate(.down)
        case kVK_Space:
            if !e.isARepeat { spaceHeld = true; NSCursor.openHand.set() }
        case kVK_ANSI_A where e.modifierFlags.contains(.command):
            selected = Set(controller.windows.map(\.id))
            render()
        case kVK_Return:
            controller.exit(focus: hovered ?? controller.windows.last)
        case kVK_ANSI_0:
            controller.animate(to: controller.fitCamera())
        case kVK_ANSI_T:
            controller.tidy()
        case kVK_ANSI_1:
            controller.zoomAnimated(to: 1)
        case kVK_ANSI_Minus:
            var t = controller.camera
            t.zoom(to: t.scale / 1.5, anchor: center)
            controller.animate(to: t, duration: 0.22)
        case kVK_ANSI_Equal:
            var t = controller.camera
            t.zoom(to: t.scale * 1.5, anchor: center)
            controller.animate(to: t, duration: 0.22)
        case kVK_ANSI_W where e.modifierFlags.contains(.command):
            // The selection if there is one, otherwise the window under the pointer.
            if let w = controller.windows.first(where: { selected.contains($0.id) }) ?? hovered {
                close(w)
                render()
            }
        default:
            super.keyDown(with: e)
        }
    }

    override func keyUp(with e: NSEvent) {
        if Int(e.keyCode) == kVK_Space {
            spaceHeld = false
            NSCursor.arrow.set()
        } else {
            super.keyUp(with: e)
        }
    }

    // MARK: Right-click menu

    /// "Same size as…": the window that takes the size of the next one you click.
    private var sizing: ManagedWindow?

    /// Zoomed out: a window's sizes, or on empty canvas, what you can do with it all.
    override func menu(for e: NSEvent) -> NSMenu? {
        guard controller.isActive, !controller.gliding, tool == nil else { return nil }
        sizing = nil
        let p = point(e)
        guard let w = controller.window(atView: p) else { return canvasMenu(at: controller.camera.toCanvas(p)) }
        return windowMenu(w)
    }

    private func windowMenu(_ w: ManagedWindow) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let c = controller!
        let sizable = !w.sizesItself
        for (title, slot) in [("Fill screen", Slot.full), ("Half screen", .left), ("Quarter screen", .topLeft)] {
            menu.addItem(MenuAction(title, enabled: sizable) { c.resize(w, to: c.slotSize(slot), how: "menu") })
        }
        menu.addItem(MenuAction("Same size as…", enabled: sizable) { [weak self] in
            self?.sizing = w
            NSCursor.crosshair.set()
            Toast.show("Click the window whose size to take")
        })
        menu.addItem(MenuAction("Back to its own size", enabled: sizable && w.originalFrame.size != .zero) {
            c.resize(w, to: w.originalFrame.size, how: "its own size")
        })
        let picked = c.windows.filter { selected.contains($0.id) }
        if picked.contains(where: { $0 === w }), picked.count > 1 {
            // Evening up: the others take this one's width, height or both.
            menu.addItem(.separator())
            for (title, width, height) in [("Same width", true, false), ("Same height", false, true), ("Same size", true, true)] {
                menu.addItem(MenuAction(title) { c.evenUp(picked, like: w, width: width, height: height) })
            }
        }
        if picked.contains(where: { $0 === w }), (2...4).contains(picked.count) {
            let make = NSMenuItem(title: "Make a screen", action: nil, keyEquivalent: "")
            make.submenu = layoutMenu(for: picked)
            menu.addItem(make)
        }
        return menu
    }

    private func canvasMenu(at c: CGPoint) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let controller = controller!
        menu.addItem(MenuAction("New screen") { [weak self] in self?.startTool(centredOn: c) })
        menu.addItem(.separator())
        menu.addItem(MenuAction("Tidy up") { controller.tidy() })
        menu.addItem(MenuAction("Fit everything") { controller.animate(to: controller.fitCamera()) })
        return menu
    }

    // MARK: Making a screen

    /// The screens these 2–4 windows can make, drawn small: picking one (or pressing its number)
    /// puts them in, each in the slot nearest where it is.
    func layoutMenu(for ws: [ManagedWindow]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (i, layout) in ScreenLayout.layouts(for: ws.count).enumerated() {
            let item = MenuAction(Self.title(of: layout)) { [weak self] in self?.makeScreen(ws, layout) }
            item.image = Self.thumbnail(of: layout)
            item.keyEquivalent = "\(i + 1)"
            item.keyEquivalentModifierMask = []
            menu.addItem(item)
        }
        return menu
    }

    private func showLayouts(for ws: [ManagedWindow]) {
        let box = ws.dropFirst().reduce(controller.camera.toView(ws[0].canvasFrame)) { $0.union(controller.camera.toView($1.canvasFrame)) }
        layoutMenu(for: ws).popUp(positioning: nil, at: NSPoint(x: box.midX, y: bounds.height - box.midY), in: self)
    }

    /// The windows into `layout`, each in the slot nearest where it is (see Screens.assign); the
    /// one in its first slot (the left, or top-left) stays where it is.
    func makeScreen(_ ws: [ManagedWindow], _ layout: ScreenLayout) {
        let placements = Array(zip(ws, Screens.assign(ws.map(\.canvasFrame.center), to: layout)))
        guard let anchor = placements.first(where: { $0.1 == layout.slots[0] }) ?? placements.first else { return }
        let origin = Screens.screenOrigin(keeping: anchor.0.canvasFrame, in: anchor.1, size: controller.screenRect(at: .zero).size,
                                          gap: CanvasController.gap)
        selected.removeAll()
        controller.arrange(placements, screen: origin, how: "layout")
    }

    static func title(of layout: ScreenLayout) -> String {
        switch layout {
        case .halves: "Side by side"
        case .leftAndQuarters: "One left, two right"
        case .quartersAndRight: "Two left, one right"
        default: "Four quarters"
        }
    }

    /// A screen with `layout`'s slots filled, menu-sized.
    static func thumbnail(of layout: ScreenLayout) -> NSImage {
        let image = NSImage(size: NSSize(width: 30, height: 19), flipped: true) { r in
            NSColor.black.setFill()
            for slot in layout.slots {
                NSBezierPath(roundedRect: Screens.frame(of: slot, in: r, gap: 1.5), xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: The screen tool

    func startTool(centredOn c: CGPoint) {
        let size = controller.screenRect(at: .zero).size
        tool = Tool(screen: controller.screenRect(at: CGPoint(x: (c.x - size.width / 2).rounded(), y: (c.y - size.height / 2).rounded())))
        selected.removeAll()
        logger.info("screen tool: started")
        render()
    }

    /// A click with the tool on: a slot (puts the window you picked there, or picks the slot), a
    /// window (puts it in the slot you picked, or picks it), the frame's edge while it's empty
    /// (moves it), or empty canvas (done).
    private func toolClick(at p: CGPoint) {
        guard var t = tool else { return }
        drag = .none
        let edge = controller.camera.toView(t.screen)
        if edge.insetBy(dx: -12, dy: -12).contains(p), !edge.insetBy(dx: 12, dy: 12).contains(p),
           controller.screenMembers(in: t.screen).isEmpty {
            drag = .toolScreen(start: t.screen, startPoint: p)
            return
        }
        if let slot = Screens.toolSlot(at: controller.camera.toCanvas(p), in: t.screen) {
            if let w = t.window { toolPlace(w, in: slot) } else {
                t.slot = slot
                tool = t
                render()
            }
        } else if let w = controller.window(atView: p) {
            if let slot = t.slot { toolPlace(w, in: slot) } else {
                t.window = w
                tool = t
                selected = [w.id]
                render()
            }
        } else {
            finishTool()
        }
    }

    /// `w` into `slot` of the tool's screen: a window in the half a quarter is part of moves to
    /// its other quarter, one in its way leaves (see Screens.makeWay).
    private func toolPlace(_ w: ManagedWindow, in slot: Slot) {
        guard var t = tool else { return }
        let there = controller.screenMembers(in: t.screen).filter { $0.0 !== w }
        var placements = [(w, slot)], stay: [ManagedWindow] = []
        for ((m, was), now) in zip(there, Screens.makeWay(for: slot, among: there.map(\.1))) {
            if now == was { stay.append(m) } else if let now { placements.append((m, now)) }
        }
        controller.arrange(placements, screen: t.screen.origin, members: stay, how: "tool")
        t.steps += 1
        t.slot = nil
        t.window = nil
        tool = t
        selected.removeAll()
        render()
    }

    /// Return or a click on empty canvas: done. Esc: everything it did undone.
    private func finishTool(cancel: Bool = false) {
        guard let t = tool else { return }
        tool = nil
        if cancel { for _ in 0..<t.steps { controller.undo() } }
        selected.removeAll()
        logger.info("screen tool: \(cancel ? "cancelled" : "done", privacy: .public) (\(t.steps) placed)")
        render()
    }

    /// The click after "Same size as…": the window clicked gives its size; anywhere else, nothing.
    private func finishSizing(at p: CGPoint) {
        guard let w = sizing else { return }
        sizing = nil
        NSCursor.arrow.set()
        if let source = controller.window(atView: p), source !== w {
            controller.resize(w, to: source.canvasFrame.size, how: "same size as \(source.appName)[\(source.id)]")
        }
    }
}

/// A menu item that runs a closure.
private final class MenuAction: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, enabled: Bool = true, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { run() }
}
