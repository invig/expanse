import AppKit

/// Bottom-right overview: every window as a block, the viewport as an outline, the zoom level.
/// Drawn on glass (see GlassPanel), in the colours applyAppearance gives it.
final class Minimap: CALayer {
    static let size = CGSize(width: 208, height: 136)

    private let windowsShape = CAShapeLayer()
    private let viewportShape = CAShapeLayer()
    private let zoomText = CATextLayer()
    private let mapArea: CGRect

    /// Canvas -> minimap (bottom-left layer coords) mapping from the last update.
    private var mapScale: CGFloat = 1
    private var mapCanvasOrigin: CGPoint = .zero
    private var mapOffset: CGPoint = .zero
    /// What the window blocks were last drawn for: redrawn only when this changes.
    private var drawn: (windows: [CGRect], bounds: CGRect)?

    override init() {
        mapArea = CGRect(x: 10, y: 26, width: Minimap.size.width - 20, height: Minimap.size.height - 36)
        super.init()
        bounds = CGRect(origin: .zero, size: Minimap.size)
        addSublayer(windowsShape)
        viewportShape.lineWidth = 1
        addSublayer(viewportShape)

        zoomText.fontSize = 10
        zoomText.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        zoomText.frame = CGRect(x: 10, y: 7, width: 80, height: 13)
        addSublayer(zoomText)
    }

    override init(layer: Any) {
        mapArea = (layer as? Minimap)?.mapArea ?? .zero
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setContentsScale(_ s: CGFloat) {
        contentsScale = s
        zoomText.contentsScale = s
    }

    /// Dark marks on light glass, light ones on dark.
    func applyAppearance(_ appearance: NSAppearance) {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        appearance.performAsCurrentDrawingAppearance {
            windowsShape.fillColor = NSColor.labelColor.withAlphaComponent(dark ? 0.5 : 0.35).cgColor
            viewportShape.fillColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            viewportShape.strokeColor = NSColor.labelColor.cgColor
            zoomText.foregroundColor = NSColor.secondaryLabelColor.cgColor
        }
        CATransaction.commit()
    }

    /// All rects are canvas space (top-left origin).
    func update(windows: [CGRect], viewport: CGRect, scale: CGFloat) {
        var bounds = windows.reduce(viewport) { $0.union($1) }
        bounds = bounds.insetBy(dx: -bounds.width * 0.04, dy: -bounds.height * 0.04)
        mapScale = min(mapArea.width / bounds.width, mapArea.height / bounds.height)
        mapCanvasOrigin = bounds.origin
        mapOffset = CGPoint(x: mapArea.minX + (mapArea.width - bounds.width * mapScale) / 2,
                            y: mapArea.minY + (mapArea.height - bounds.height * mapScale) / 2)

        if drawn?.windows != windows || drawn?.bounds != bounds {
            drawn = (windows, bounds)
            let path = CGMutablePath()
            for r in windows {
                path.addRoundedRect(in: toMap(r), cornerWidth: 1.5, cornerHeight: 1.5)
            }
            windowsShape.path = path
        }
        viewportShape.path = CGPath(roundedRect: toMap(viewport), cornerWidth: 2, cornerHeight: 2, transform: nil)
        let zoom = "\(Int((scale * 100).rounded()))%"
        if zoomText.string as? String != zoom { zoomText.string = zoom }
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
