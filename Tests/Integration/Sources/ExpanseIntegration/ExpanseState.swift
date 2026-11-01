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
    /// Each app's focused window as Expanse last heard it (focusedWindowByApp): where a hop starts.
    var focusedByApp: [pid_t: CGWindowID] = [:]
    /// Where the Spaces bar's tile for each Space is on screen (global): empty while it's hidden.
    var spacesTiles: [UInt64: CGRect] = [:]
    /// Back to front.
    var windows: [Window] = []
    var unmanaged: [Unmanaged] = []

    var idle: Bool { !gliding && !animating }

    func window(_ id: CGWindowID) -> Window? { windows.first { $0.id == id } }

    /// Where a canvas point is on screen (global CG coordinates) at the current camera.
    func screenPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - camera.x) * scale + viewport.minX, y: (p.y - camera.y) * scale + viewport.minY)
    }

    /// Where to click on the window at `canvas` (on screen): its middle, or else a part of it clear
    /// of Expanse's panels in the bottom-right corner (the Spaces bar and the minimap), which take
    /// clicks there. Zoomed out to fit everything, a window can lie under them (SPACES-14, 1 Nov).
    /// Nil if it's all under them, or off screen: pan it into the open first.
    func clickPoint(on canvas: CGRect) -> CGPoint? {
        let a = screenPoint(canvas.origin), b = screenPoint(CGPoint(x: canvas.maxX, y: canvas.maxY))
        let r = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        let left = (spacesTiles.values.map(\.minX).min() ?? viewport.maxX - 260) - 30
        let top = min((spacesTiles.values.map(\.minY).min() ?? viewport.maxY) - 30, viewport.maxY - 170)
        let panels = CGRect(x: left, y: top, width: viewport.maxX - left, height: viewport.maxY - top)
        let spots = [CGPoint(x: r.midX, y: r.midY)] + [0.15, 0.5, 0.85].flatMap { fy in
            [0.15, 0.5, 0.85].map { fx in CGPoint(x: r.minX + r.width * fx, y: r.minY + r.height * fy) }
        }
        return spots.first { !panels.contains($0) && viewport.contains($0) }
    }

    /// The screen group window `id` is in, as Expanse sees it (CanvasController.screenGroups):
    /// windows within 40pt of each other, directly or through a neighbour, whose outline fits the
    /// screen at 100%. Nil for a window on its own.
    func screenGroup(of id: CGWindowID) -> [Window]? {
        guard let i = windows.firstIndex(where: { $0.id == id }) else { return nil }
        var parent = Array(windows.indices)
        func root(_ k: Int) -> Int { parent[k] == k ? k : root(parent[k]) }
        for a in windows.indices {
            for b in windows.indices where b > a
                && windows[a].canvas.insetBy(dx: -20, dy: -20).intersects(windows[b].canvas.insetBy(dx: -20, dy: -20)) {
                parent[root(b)] = root(a)
            }
        }
        let members = windows.indices.filter { root($0) == root(i) }.map { windows[$0] }
        guard members.count > 1 else { return nil }
        let outline = members.dropFirst().reduce(members[0].canvas) { $0.union($1.canvas) }
        guard outline.width <= viewport.width + 1, outline.height <= viewport.height + 1 else { return nil }
        return members
    }

    /// Where going to window `id` puts the camera (CanvasController.viewCamera): its group framed,
    /// or the window centred (top-aligned if it's taller than the screen).
    func viewCameraOrigin(for id: CGWindowID) -> CGPoint? {
        guard let w = window(id) else { return nil }
        let v = viewport.size
        if let group = screenGroup(of: id) {
            let o = group.dropFirst().reduce(group[0].canvas) { $0.union($1.canvas) }
            return CGPoint(x: (o.midX - v.width / 2).rounded(), y: (o.midY - v.height / 2).rounded())
        }
        let f = w.canvas
        let y = f.height > v.height ? 0 : (v.height - f.height) / 2
        return CGPoint(x: (f.minX - (v.width - f.width) / 2).rounded(), y: (f.minY - y).rounded())
    }

    /// At 100% on window `id`, as a glide or a dive leaves it: centred, or its group framed.
    func isViewOn(_ id: CGWindowID, within d: CGFloat = 2) -> Bool {
        guard abs(scale - 1) < 0.001, let o = viewCameraOrigin(for: id) else { return false }
        return hypot(camera.x - o.x, camera.y - o.y) <= d
    }

    /// The part of the canvas the screen shows.
    var visibleCanvas: CGRect {
        CGRect(x: camera.x, y: camera.y, width: viewport.width / scale, height: viewport.height / scale)
    }

    init(lines: [String]) {
        for line in lines {
            if line.hasPrefix("dump spaces") {
                // "dump spaces 1={{1100, 893}, {100, 63}}; 40={{1214, 893}, {100, 63}}"
                for m in line.matches(of: #/(\d+)=(\{\{.*?\}\})/#) {
                    if let id = UInt64(m.1) { spacesTiles[id] = NSRectFromString(String(m.2)) }
                }
            } else if line.hasPrefix("dump viewport=") {
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
                // "focusedByApp=[512: 4021, 77: 310]"
                if let m = line.firstMatch(of: #/focusedByApp=\[([^\]]*)\]/#) {
                    for pair in m.1.split(separator: ",") {
                        let parts = pair.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                        if parts.count == 2, let pid = pid_t(parts[0]), let id = CGWindowID(parts[1]) { focusedByApp[pid] = id }
                    }
                }
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
