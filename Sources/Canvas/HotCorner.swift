import AppKit

/// Rest the pointer in a screen corner to fire `onTrigger`. Polls the pointer (cheap, and it
/// works whichever app is in front, including ours); re-arms once the pointer leaves the corner.
final class HotCorner {
    enum Corner: String, CaseIterable {
        case off, all, topLeft, topRight, bottomLeft, bottomRight

        var title: String {
            switch self {
            case .off: "Off"
            case .all: "All Corners"
            case .topLeft: "Top Left"
            case .topRight: "Top Right"
            case .bottomLeft: "Bottom Left"
            case .bottomRight: "Bottom Right"
            }
        }
    }

    static let defaultsKey = "hotCorner"
    var corner: Corner {
        didSet { UserDefaults.standard.set(corner.rawValue, forKey: Self.defaultsKey) }
    }
    var onTrigger: () -> Void = {}

    private var timer: Timer?
    private var enteredAt: CFTimeInterval?
    private var armed = true
    private static let dwell: CFTimeInterval = 0.15
    private static let tolerance: CGFloat = 3

    init() {
        corner = Corner(rawValue: UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "") ?? .all
    }

    func start() {
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard corner != .off, let f = NSScreen.screens.first?.frame else { return }
        let p = NSEvent.mouseLocation
        let t = Self.tolerance
        let left = p.x <= f.minX + t, right = p.x >= f.maxX - t
        let top = p.y >= f.maxY - t, bottom = p.y <= f.minY + t
        let inCorner = switch corner {
        case .off: false
        case .all: (top || bottom) && (left || right)
        case .topLeft: top && left
        case .topRight: top && right
        case .bottomLeft: bottom && left
        case .bottomRight: bottom && right
        }
        guard inCorner, NSEvent.pressedMouseButtons == 0 else {
            enteredAt = nil
            armed = true
            return
        }
        guard armed else { return }
        let now = CACurrentMediaTime()
        if let enteredAt {
            if now - enteredAt >= Self.dwell {
                armed = false
                self.enteredAt = nil
                onTrigger()
            }
        } else {
            enteredAt = now
        }
    }
}
