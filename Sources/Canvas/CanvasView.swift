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
    private let minimap = Minimap()
    var hovered: ManagedWindow?

    private enum Drag {
        case none
        case pan(last: CGPoint)
        case window(ManagedWindow, startFrame: CGRect, startPoint: CGPoint)
        case minimap
    }
    private var drag: Drag = .none
    private var dragged = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let root = layer else { return }
        root.masksToBounds = true
        wallpaper.contentsGravity = .resizeAspectFill
        wallpaper.actions = ["contents": NSNull()]
        root.addSublayer(wallpaper)
        for l in [world, labels, guides] {
            l.actions = ["sublayers": NSNull()]
            root.addSublayer(l)
        }
        guides.fillColor = nil
        guides.strokeColor = NSColor.systemPink.cgColor
        guides.lineWidth = 1
        root.addSublayer(minimap)
        applyAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [world, labels, guides] { l.frame = bounds }
        // Pinned exactly where the real desktop picture is: the top strip sits under the menu bar.
        wallpaper.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height + menuBarHeight)
        minimap.frame.origin = CGPoint(x: bounds.maxX - Minimap.size.width - 16, y: 16)
        CATransaction.commit()
        render()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = window?.backingScaleFactor ?? 2
        minimap.setContentsScale(s)
        controller?.windows.forEach { $0.node.setContentsScale(s) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

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

    // MARK: Rendering

    func render() {
        guard let c = controller else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let viewRect = CGRect(origin: .zero, size: bounds.size)
        for w in c.windows {
            let r = c.camera.toView(w.canvasFrame)
            // In live mode the real window covers its proxy; only parked windows are drawn.
            let visible = r.insetBy(dx: -30, dy: -30).intersects(viewRect) && (c.isActive || w.parked)
            w.node.layout(rect: flip(r), scale: c.camera.scale, hovered: w === hovered, visible: visible)
        }
        minimap.update(windows: c.windows.map(\.canvasFrame), viewport: c.camera.toCanvas(viewRect), scale: c.camera.scale)
        CATransaction.commit()
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

    // MARK: Trackpad

    override func scrollWheel(with e: NSEvent) {
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
        guard controller.isActive else { controller.enter(zoomOut: false); return }
        controller.zoom(by: 1 + e.magnification, at: point(e))
    }

    override func smartMagnify(with e: NSEvent) {
        guard controller.isActive else { controller.enter(zoomOut: true); return }
        controller.toggleOverview(at: point(e))
    }

    // MARK: Mouse

    override func mouseDown(with e: NSEvent) {
        guard controller.isActive else {
            // Live mode: a click on a parked window's picture on the backdrop goes to that window.
            drag = .none
            if let w = controller.window(atView: point(e), parkedOnly: true) { controller.focus(w) }
            return
        }
        controller.cancelAnimation()
        dragged = false
        if let mp = minimapPoint(e) {
            drag = .minimap
            controller.center(on: minimap.canvasPoint(at: mp))
            return
        }
        let p = point(e)
        if let w = controller.window(atView: p) {
            if w === hovered, WindowNode.closeRect(in: controller.camera.toView(w.canvasFrame)).contains(p) {
                drag = .none
                controller.close(w)
                return
            }
            controller.bringToFront(w)
            drag = .window(w, startFrame: w.canvasFrame, startPoint: p)
        } else {
            drag = .pan(last: p)
        }
        render()
    }

    override func mouseDragged(with e: NSEvent) {
        guard controller.isActive else { controller.enter(zoomOut: false); return }
        let p = point(e)
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
            let s = controller.camera.scale
            let proposed = startFrame.offsetBy(dx: (p.x - startPoint.x) / s, dy: (p.y - startPoint.y) / s)
            let snapEnabled = !e.modifierFlags.contains(.command)
            let (frame, lines) = snapEnabled ? controller.snap(proposed, for: w) : (proposed, [])
            w.canvasFrame = frame
            showGuides(lines)
            render()
        }
    }

    override func mouseUp(with e: NSEvent) {
        showGuides([])
        if case .window(let w, _, _) = drag {
            if dragged { controller.scheduleSave() } else { controller.exit(focus: w) }
        }
        drag = .none
    }

    override func mouseMoved(with e: NSEvent) {
        guard controller.isActive else { return }
        let w = minimapPoint(e) == nil ? controller.window(atView: point(e)) : nil
        if w !== hovered {
            hovered?.node.label.string = hovered?.appName
            hovered = w
            if let w { w.node.label.string = w.title.isEmpty ? w.appName : "\(w.appName) — \(w.title)" }
            render()
        }
    }

    // MARK: Keyboard

    override func keyDown(with e: NSEvent) {
        guard controller.isActive else { super.keyDown(with: e); return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        switch Int(e.keyCode) {
        case kVK_Escape:
            controller.exit()
        case kVK_Return:
            controller.exit(focus: hovered ?? controller.windows.last)
        case kVK_ANSI_0:
            controller.animate(to: controller.fitCamera())
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
            if let w = hovered { controller.close(w) }
        default:
            super.keyDown(with: e)
        }
    }
}
