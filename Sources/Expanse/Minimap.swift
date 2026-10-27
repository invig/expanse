import AppKit

/// Bottom-right overview of the canvas: every window as a block, the viewport as an outline,
/// the zoom level. Drawn on glass (see GlassPanel), in the colours applyAppearance gives it.
final class Minimap: CALayer {
    static let size = CGSize(width: 208, height: 136)

    private let windowsShape = CAShapeLayer()
    /// The viewport's tint, under the windows (its outline, viewportShape, is over them).
    private let viewportFill = CAShapeLayer()
    private let viewportShape = CAShapeLayer()
    private let title = CATextLayer()
    /// The viewport's outline: the accent marks where you are; when it frames the whole map there's
    /// nothing to single out, so it's a quiet line instead.
    private var accentRing: CGColor?
    private var quietRing: CGColor?
    private let zoomText = CATextLayer()
    private let mapArea: CGRect

    /// Canvas -> minimap (bottom-left layer coords) mapping from the last update.
    private var mapScale: CGFloat = 1
    private var mapCanvasOrigin: CGPoint = .zero
    private var mapOffset: CGPoint = .zero
    /// What the window blocks were last drawn for: redrawn only when this changes.
    private var drawn: (windows: [CGRect], bounds: CGRect)?

    override init() {
        // Below a header row level with the Spaces strip's: the title, and the zoom as its value.
        mapArea = CGRect(x: 14, y: 12, width: Minimap.size.width - 28, height: Minimap.size.height - 44)
        super.init()
        bounds = CGRect(origin: .zero, size: Minimap.size)
        addSublayer(viewportFill)
        windowsShape.lineJoin = .round
        addSublayer(windowsShape)
        viewportShape.fillColor = nil
        addSublayer(viewportShape)

        title.string = "Canvas"
        title.fontSize = 11
        title.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        title.frame = CGRect(x: 14, y: Minimap.size.height - 25, width: 120, height: 14)
        addSublayer(title)
        zoomText.fontSize = 11
        zoomText.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomText.alignmentMode = .right
        zoomText.frame = CGRect(x: Minimap.size.width - 74, y: Minimap.size.height - 25, width: 60, height: 14)
        addSublayer(zoomText)
    }

    override init(layer: Any) {
        mapArea = (layer as? Minimap)?.mapArea ?? .zero
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setContentsScale(_ s: CGFloat) {
        contentsScale = s
        title.contentsScale = s
        zoomText.contentsScale = s
    }

    /// Dark marks on light glass, light ones on dark.
    func applyAppearance(_ appearance: NSAppearance) {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        appearance.performAsCurrentDrawingAppearance {
            // Quieter than the viewport, each with an edge so overlapping windows stay apart: a
            // dark seam on light glass (a light one would outline them like stickers), light on dark.
            windowsShape.fillColor = NSColor.labelColor.withAlphaComponent(dark ? 0.38 : 0.2).cgColor
            windowsShape.strokeColor = (dark ? NSColor.windowBackgroundColor.withAlphaComponent(0.5)
                : NSColor.labelColor.withAlphaComponent(0.24)).cgColor
            windowsShape.lineWidth = dark ? 0.75 : 0.5
            // Where you are, in the accent colour, as the current Space is beside it.
            viewportFill.fillColor = NSColor.controlAccentColor.withAlphaComponent(dark ? 0.14 : 0.1).cgColor
            accentRing = NSColor.controlAccentColor.cgColor
            quietRing = NSColor.labelColor.withAlphaComponent(dark ? 0.35 : 0.28).cgColor
            viewportShape.strokeColor = viewportFill.isHidden ? quietRing : accentRing
            // (Darker than secondaryLabelColor: text in a layer gets no vibrancy from the glass.)
            let secondary = dark ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.75)
            title.foregroundColor = secondary.cgColor
            zoomText.foregroundColor = secondary.cgColor
        }
        CATransaction.commit()
    }

    /// All rects are canvas space (top-left origin).
    func update(windows: [CGRect], viewport: CGRect, scale: CGFloat) {
        var bounds = windows.reduce(viewport) { $0.union($1) }
        bounds = bounds.insetBy(dx: -bounds.width * 0.04, dy: -bounds.height * 0.04)
        // Room all round for the viewport's ring, drawn outside it (below).
        let fit = mapArea.insetBy(dx: Self.ringOutset + 1, dy: Self.ringOutset + 1)
        mapScale = min(fit.width / bounds.width, fit.height / bounds.height)
        mapCanvasOrigin = bounds.origin
        mapOffset = CGPoint(x: fit.minX + (fit.width - bounds.width * mapScale) / 2,
                            y: fit.minY + (fit.height - bounds.height * mapScale) / 2)

        if drawn?.windows != windows || drawn?.bounds != bounds {
            drawn = (windows, bounds)
            let path = CGMutablePath()
            for r in windows {
                let m = toMap(r)
                let radius = Self.radius(for: m, min: 2, max: 3, share: 0.18)
                path.addRoundedRect(in: m, cornerWidth: radius, cornerHeight: radius)
            }
            windowsShape.path = path
        }
        // Never so small it can't be found (zoomed in, among a lot of windows).
        let v = toMap(viewport)
        let shown = v.insetBy(dx: min(0, (v.width - 20) / 2), dy: min(0, (v.height - 13) / 2))
        // Concentric with the panel when it fills the map (22pt corners).
        let radius = Self.radius(for: shown, min: 3, max: GlassPanel.radius - mapArea.minX, share: 0.14)
        viewportFill.path = CGPath(roundedRect: shown, cornerWidth: radius, cornerHeight: radius, transform: nil)
        // The ring stands off the windows inside, so it reads as a frame around what you see,
        // not as one more (selected) window.
        let ring = radius + Self.ringOutset
        viewportShape.path = CGPath(roundedRect: shown.insetBy(dx: -Self.ringOutset, dy: -Self.ringOutset),
                                    cornerWidth: ring, cornerHeight: ring, transform: nil)
        // Seeing everything, the outline says so (lighter); a tint over the whole map would only cloud it.
        let framesAll = shown.width * shown.height > 0.5 * mapArea.width * mapArea.height
        viewportFill.isHidden = framesAll
        viewportShape.lineWidth = framesAll ? 1 : 2
        viewportShape.strokeColor = framesAll ? quietRing : accentRing
        let zoom = "\(Int((scale * 100).rounded()))%"
        if zoomText.string as? String != zoom { zoomText.string = zoom }
    }

    private static let ringOutset: CGFloat = 3

    /// A corner radius in proportion to `r`, within `min`...`max` (and never more than it fits).
    private static func radius(for r: CGRect, min lo: CGFloat, max hi: CGFloat, share: CGFloat) -> CGFloat {
        Swift.min(Swift.min(hi, Swift.max(lo, Swift.min(r.width, r.height) * share)), Swift.min(r.width, r.height) / 2)
    }

    /// Minimap point (this layer's coords) -> canvas point.
    func canvasPoint(at p: CGPoint) -> CGPoint {
        let top = mapArea.maxY - (mapOffset.y - mapArea.minY)
        return CGPoint(x: (p.x - mapOffset.x) / mapScale + mapCanvasOrigin.x,
                       y: (top - p.y) / mapScale + mapCanvasOrigin.y)
    }

    /// Canvas rect (top-left origin) -> minimap layer rect (bottom-left origin).
    private func toMap(_ r: CGRect) -> CGRect {
        let top = mapArea.maxY - (mapOffset.y - mapArea.minY)
        let x = mapOffset.x + (r.minX - mapCanvasOrigin.x) * mapScale
        let yTop = top - (r.minY - mapCanvasOrigin.y) * mapScale
        let h = r.height * mapScale
        return CGRect(x: x, y: yTop - h, width: max(r.width * mapScale, 1), height: max(h, 1))
    }
}
