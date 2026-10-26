import AppKit
import ScreenCaptureKit

/// A real window that lives somewhere on the canvas.
final class ManagedWindow {
    let id: CGWindowID
    let pid: pid_t
    let bundleID: String
    var appName: String
    var title: String
    var scWindow: SCWindow

    /// Position and size in canvas space. Size always equals the real window's size.
    var canvasFrame: CGRect
    /// True while the real window is hidden in the screen corner.
    var parked = false
    /// Where the real window actually ended up the last time we placed it (global CG coords).
    /// If the window is later found somewhere else, the user (or the app) moved it.
    var lastPlaced: CGPoint?
    /// The size the user chose. On a small screen the real window may be shrunk to fit.
    var preferredSize: CGSize = .zero
    /// The size we last set, so our own resizes aren't mistaken for the user's.
    var lastSized: CGSize?
    /// Where macOS had the window before Canvas managed it (global CG). Restored on quit / pause.
    var originalFrame: CGRect = .zero

    let node = WindowNode()
    let capture = WindowCapture()
    private var axElement: AXUIElement?

    init(scWindow: SCWindow, canvasFrame: CGRect) {
        self.id = scWindow.windowID
        self.pid = scWindow.owningApplication?.processID ?? 0
        self.bundleID = scWindow.owningApplication?.bundleIdentifier ?? ""
        self.appName = scWindow.owningApplication?.applicationName ?? "Window"
        self.title = scWindow.title ?? ""
        self.scWindow = scWindow
        self.canvasFrame = canvasFrame
        node.label.string = appName
    }

    var ax: AXUIElement? {
        if let axElement { return axElement }
        axElement = AX.windows(pid: pid).first { AX.windowID($0) == id }
        return axElement
    }

    /// Moves the real window to `point` (global CG coords) and records where it landed.
    func place(at point: CGPoint) {
        guard let ax else { return }
        if let last = lastPlaced, last.distance(to: point) < 0.5 { return }
        let before = AX.position(ax)
        AX.setPosition(ax, point)
        lastPlaced = AX.position(ax) ?? point
        if let before, before.distance(to: lastPlaced!) >= 1 {
            logger.info("move \(self.appName, privacy: .public)[\(self.id)] \(NSStringFromPoint(before), privacy: .public) -> \(NSStringFromPoint(self.lastPlaced!), privacy: .public) (asked \(NSStringFromPoint(point), privacy: .public))")
        }
    }
}

/// Core Animation layers for one window: shadowed container, live content, name label.
final class WindowNode {
    let container = CALayer()
    let content = CALayer()
    let highlight = CALayer()
    let label = CATextLayer()
    let closeButton = CALayer()
    private let closeGlyph = CAShapeLayer()
    static let closeSize: CGFloat = 26
    static let closeInset: CGFloat = 10

    init() {
        container.shadowColor = NSColor.black.cgColor
        container.shadowOpacity = 0.22
        container.shadowRadius = 14
        container.shadowOffset = CGSize(width: 0, height: -6)

        content.contentsGravity = .resize
        content.masksToBounds = true
        content.backgroundColor = NSColor(white: 0.97, alpha: 1).cgColor
        content.minificationFilter = .linear
        content.magnificationFilter = .linear
        container.addSublayer(content)

        highlight.borderColor = NSColor.controlAccentColor.cgColor
        highlight.borderWidth = 0
        container.addSublayer(highlight)

        closeButton.backgroundColor = NSColor(white: 0.1, alpha: 0.75).cgColor
        closeButton.cornerRadius = WindowNode.closeSize / 2
        closeButton.bounds = CGRect(x: 0, y: 0, width: WindowNode.closeSize, height: WindowNode.closeSize)
        closeButton.isHidden = true
        let glyph = CGMutablePath()
        let a: CGFloat = 9, b = WindowNode.closeSize - 9
        glyph.move(to: CGPoint(x: a, y: a)); glyph.addLine(to: CGPoint(x: b, y: b))
        glyph.move(to: CGPoint(x: a, y: b)); glyph.addLine(to: CGPoint(x: b, y: a))
        closeGlyph.path = glyph
        closeGlyph.strokeColor = NSColor.white.cgColor
        closeGlyph.lineWidth = 2
        closeGlyph.lineCap = .round
        closeGlyph.frame = closeButton.bounds
        closeButton.addSublayer(closeGlyph)
        container.addSublayer(closeButton)

        label.fontSize = 11
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.foregroundColor = NSColor(white: 0.32, alpha: 1).cgColor
        label.alignmentMode = .left
        label.truncationMode = .end
        label.isWrapped = false
    }

    func setContentsScale(_ s: CGFloat) {
        label.contentsScale = s
        closeGlyph.contentsScale = s
    }

    /// Close button rect in view coordinates (top-left origin) for a window drawn at `r`.
    static func closeRect(in r: CGRect) -> CGRect {
        CGRect(x: r.maxX - closeInset - closeSize, y: r.minY + closeInset, width: closeSize, height: closeSize)
    }

    /// `rect` is in layer coordinates (bottom-left origin).
    func layout(rect: CGRect, scale: CGFloat, hovered: Bool, selected: Bool = false, visible: Bool) {
        container.isHidden = !visible
        label.isHidden = !visible || rect.width < 70
        guard visible else { return }
        container.frame = rect
        content.frame = container.bounds
        highlight.frame = container.bounds
        let radius = max(2, 16 * scale)
        content.cornerRadius = radius
        highlight.cornerRadius = radius
        highlight.borderWidth = selected ? 3 : hovered ? 2 : 0
        closeButton.isHidden = !hovered || rect.width < 140
        closeButton.position = CGPoint(x: rect.width - WindowNode.closeInset - WindowNode.closeSize / 2,
                                       y: rect.height - WindowNode.closeInset - WindowNode.closeSize / 2)
        container.shadowPath = CGPath(roundedRect: container.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        container.shadowRadius = max(3, 14 * min(scale, 1))
        label.frame = CGRect(x: rect.minX + 2, y: rect.maxY + 5, width: max(rect.width - 4, 60), height: 15)
    }
}
