import AppKit

/// What Expanse says about itself in answer to expanse://dump (CanvasController.dump): the view,
/// the camera, and every window on the canvas.
struct ExpanseState {
    struct Window {
        let app: String
        let id: CGWindowID
        /// ScreenCaptureKit's last frame for it, and where Accessibility says the real window is.
        let sc: CGRect
        let ax: CGPoint?
        /// Its spot on the canvas.
        let canvas: CGRect
        let parked: Bool
        let capturing: Bool
        let lastPlaced: CGPoint?
    }
    struct Unmanaged {
        let owner: String
        let id: CGWindowID
        let line: String
    }

    var viewport = CGRect.zero
    var camera = CGPoint.zero
    var scale: CGFloat = 1
    var active = false
    var gliding = false
    var animating = false
    var paused = false
    var frontmost = ""
    /// Back to front.
    var windows: [Window] = []
    var unmanaged: [Unmanaged] = []

    var idle: Bool { !gliding && !animating }

    func window(_ id: CGWindowID) -> Window? { windows.first { $0.id == id } }

    /// Where a canvas point is on screen (global CG coordinates) at the current camera.
    func screenPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - camera.x) * scale + viewport.minX, y: (p.y - camera.y) * scale + viewport.minY)
    }

    /// The part of the canvas the screen shows.
    var visibleCanvas: CGRect {
        CGRect(x: camera.x, y: camera.y, width: viewport.width / scale, height: viewport.height / scale)
    }

    init(lines: [String]) {
        for line in lines {
            if line.hasPrefix("dump viewport=") {
                viewport = rect(after: "viewport=", in: line) ?? .zero
                if let m = line.firstMatch(of: #/camera=\{([^}]*)\}@([0-9.eE+-]+)/#) {
                    camera = NSPointFromString("{\(m.1)}")
                    scale = CGFloat(Double(m.2) ?? 1)
                }
                active = flag("active", in: line)
                gliding = flag("gliding", in: line)
                animating = flag("animating", in: line)
                paused = flag("paused", in: line)
                if let m = line.firstMatch(of: #/frontmost=(.*?) focusedByApp=/#) { frontmost = String(m.1) }
            } else if let m = line.firstMatch(of: #/^dump unmanaged (.*)\[(\d+)\]/#) {
                unmanaged.append(Unmanaged(owner: String(m.1), id: CGWindowID(m.2) ?? 0, line: line))
            } else if let m = line.firstMatch(of: #/^dump (.*)\[(\d+)\] sc=(\{\{.*?\}\}) ax=(\{[^}]*\}|nil) canvas=(\{\{.*?\}\}) .* parked=(true|false) capturing=(true|false) .* lastPlaced=(\{[^}]*\}|nil)/#) {
                windows.append(Window(app: String(m.1), id: CGWindowID(m.2) ?? 0, sc: NSRectFromString(String(m.3)),
                                      ax: m.4 == "nil" ? nil : NSPointFromString(String(m.4)),
                                      canvas: NSRectFromString(String(m.5)), parked: m.6 == "true", capturing: m.7 == "true",
                                      lastPlaced: m.8 == "nil" ? nil : NSPointFromString(String(m.8))))
            }
        }
    }

    private func rect(after key: String, in line: String) -> CGRect? {
        guard let r = line.range(of: key) else { return nil }
        let rest = line[r.upperBound...]
        guard let end = rest.range(of: "}}") else { return nil }
        return NSRectFromString(String(rest[..<end.upperBound]))
    }

    private func flag(_ key: String, in line: String) -> Bool { line.contains("\(key)=true") }
}
