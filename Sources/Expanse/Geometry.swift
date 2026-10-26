import CoreGraphics

/// Maps canvas space to view space (top-left origin, y down, points).
/// `origin` is the canvas point shown at the viewport's top-left corner.
struct Camera: Equatable {
    var origin: CGPoint = .zero
    var scale: CGFloat = 1

    static let minScale: CGFloat = 0.03
    static let maxScale: CGFloat = 1.5

    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - origin.x) * scale, y: (p.y - origin.y) * scale)
    }

    func toView(_ r: CGRect) -> CGRect {
        CGRect(origin: toView(r.origin), size: CGSize(width: r.width * scale, height: r.height * scale))
    }

    func toCanvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / scale + origin.x, y: p.y / scale + origin.y)
    }

    func toCanvas(_ r: CGRect) -> CGRect {
        CGRect(origin: toCanvas(r.origin), size: CGSize(width: r.width / scale, height: r.height / scale))
    }

    /// Zooms so the canvas point under `anchor` (view coords) stays put.
    mutating func zoom(to newScale: CGFloat, anchor: CGPoint) {
        guard newScale.isFinite, anchor.x.isFinite, anchor.y.isFinite else { return }
        let s = min(max(newScale, Camera.minScale), Camera.maxScale)
        let c = toCanvas(anchor)
        scale = s
        origin = CGPoint(x: c.x - anchor.x / s, y: c.y - anchor.y / s)
    }

    /// Moves the content by `d` view points.
    mutating func pan(by d: CGVector) {
        guard d.dx.isFinite, d.dy.isFinite else { return }
        origin.x -= d.dx / scale
        origin.y -= d.dy / scale
    }

    func center(in size: CGSize) -> CGPoint {
        toCanvas(CGPoint(x: size.width / 2, y: size.height / 2))
    }

    static func centered(on c: CGPoint, scale: CGFloat, viewSize: CGSize) -> Camera {
        Camera(origin: CGPoint(x: c.x - viewSize.width / 2 / scale, y: c.y - viewSize.height / 2 / scale), scale: scale)
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

extension CGPoint {
    func distance(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
