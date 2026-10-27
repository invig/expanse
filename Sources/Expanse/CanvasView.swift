import AppKit
import Carbon.HIToolbox

/// Draws the canvas and turns trackpad / mouse / keyboard input into camera and window moves.
/// Internally everything is top-left view coordinates; `flip` converts to layer coordinates.
final class CanvasView: NSView {
    weak var controller: CanvasController!

    private let wallpaper = CALayer()
    private let world = CALayer()
    private let labels = CALayer()
    /// Height of the menu bar strip the wallpaper extends under, so it lines up with the real desktop.
    var menuBarHeight: CGFloat = 0 { didSet { needsLayout = true } }
    private let guides = CAShapeLayer()
    private let marquee = CAShapeLayer()
    private let selectionBox = CAShapeLayer()
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
    }
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
        for l in [marquee, selectionBox] {
            l.actions = ["path": NSNull()]
            root.addSublayer(l)
        }
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
        for l in [world, labels, guides, marquee, selectionBox] { l.frame = bounds }
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

    private var hasWallpaper: Bool { wallpaper.contents != nil && !wallpaper.isHidden }

    private func applyAppearance() {
        let background = (isDark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.85, alpha: 1)).cgColor
        layer?.backgroundColor = background
        controller?.windows.forEach { styleLabel($0.node.label) }
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
        minimap.update(windows: c.windows.map(\.canvasFrame), viewport: c.camera.toCanvas(viewRect), scale: c.camera.scale)
        // Gliding at 100%, the overlay is over the real windows, showing their pictures for a
        // moment: the minimap and Spaces stay under the windows, as they are before and after,
        // rather than jumping in front of them. Zoomed out, they're on top to be clicked.
        minimapGlass.layer?.zPosition = c.gliding ? -1 : 0
        spacesGlass.layer?.zPosition = c.gliding ? -1 : 0
        CATransaction.commit()
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
            controller.pan(by: CGVector(dx: e.scrollingDeltaX * k, dy: e.scrollingDeltaY * k))
        }
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
        guard !controller.gliding else { return }
        guard controller.isActive else {
            // Live mode: a click on a parked window's picture on the backdrop goes to that window,
            // and the Spaces bar works here too. Anywhere else on the backdrop (the desktop, as
            // far as you can tell), it zooms out.
            drag = .none
            let bar = spacesBarHit(e)
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
        let bar = spacesBarHit(e)
        if bar.over {
            drag = .none
            if let i = bar.tile {
                // Switching Space takes the pointer away; don't leave the tile lit.
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
            let (frame, lines) = snapEnabled ? controller.snap(proposed, excluding: [w.id]) : (proposed, [])
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
            let (snapped, lines) = snapEnabled ? controller.snap(proposed, excluding: selected) : (proposed, [])
            let dx = d.dx + snapped.minX - proposed.minX, dy = d.dy + snapped.minY - proposed.minY
            for (w, start) in starts { w.canvasFrame = start.offsetBy(dx: dx, dy: dy) }
            showGuides(lines)
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
        lastDragEvent = 0
        showGuides([])
        marquee.path = nil
        switch drag {
        case .window(let w, let startFrame, _):
            if dragged {
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
        case .pan:
            if spaceHeld { NSCursor.openHand.set() }
        default:
            break
        }
        drag = .none
        render()
    }

    override func mouseMoved(with e: NSEvent) {
        // A Space tile switches Space at 100% too, so it lights up under the pointer there as well.
        let bar = spacesBarHit(e)
        spacesBar.hovered = bar.tile
        guard controller.isActive else { return }
        let w = minimapPoint(e) == nil && !bar.over ? controller.window(atView: point(e)) : nil
        if w !== hovered {
            hovered?.node.label.string = hovered?.appName
            hovered = w
            if let w { w.node.label.string = w.title.isEmpty ? w.appName : "\(w.appName) — \(w.title)" }
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
            if selected.isEmpty { controller.exit() } else { selected.removeAll(); render() }
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
            controller.cameraMovedByUser()
            controller.animate(to: controller.fitCamera())
        case kVK_ANSI_T:
            controller.tidy()
        case kVK_ANSI_1:
            controller.zoomAnimated(to: 1)
        case kVK_ANSI_Minus:
            var t = controller.camera
            t.zoom(to: t.scale / 1.5, anchor: center)
            controller.cameraMovedByUser()
            controller.animate(to: t, duration: 0.22)
        case kVK_ANSI_Equal:
            var t = controller.camera
            t.zoom(to: t.scale * 1.5, anchor: center)
            controller.cameraMovedByUser()
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
}
