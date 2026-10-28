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
    var lastPlaced: CGPoint? {
        didSet { if let oldValue, oldValue != lastPlaced { placedBefore = oldValue } }
    }
    /// Where it was before that (see CanvasController.cameBack).
    private(set) var placedBefore: CGPoint?
    /// When we last placed it (CACurrentMediaTime), to recognise the echo of our own move.
    var lastPlacedAt: CFTimeInterval = 0
    /// When it last turned up back at `placedBefore` and was put back (see CanvasController.cameBack).
    var cameBackAt: CFTimeInterval = 0
    /// When Expanse started tracking it.
    let addedAt = CACurrentMediaTime()
    /// The size the user chose. On a small screen the real window may be shrunk to fit.
    var preferredSize: CGSize = .zero

    /// Apps whose window follows a display somewhere else (a VM, a remote Mac): they size it to
    /// match, and resizing it makes them change that display's resolution. Expanse leaves their
    /// size alone and takes whatever size they choose.
    private static let sizesOwnWindows: Set<String> = [
        "com.utmapp.UTM", "com.github.cirruslabs.tart", "com.parallels.desktop.console", "com.vmware.fusion",
        "org.virtualbox.app.VirtualBoxVM", "com.apple.ScreenSharing", "com.edovia.screens.5", "com.edovia.screens.mac",
        "com.moonlight-stream.Moonlight", "com.microsoft.rdc.macos", "com.microsoft.rdc.mac",
    ]
    var sizesItself: Bool { Self.sizesOwnWindows.contains(bundleID) }
    /// The size we last set, so our own resizes aren't mistaken for the user's.
    var lastSized: CGSize?
    /// Where macOS had the window before Expanse managed it (global CG). Restored on quit / pause.
    var originalFrame: CGRect = .zero
    /// Where the window sits in the home layout: the arrangement at full chosen sizes (the big
    /// screen). On a smaller screen the canvas layout is derived from this, so it comes back exactly.
    var home: CGPoint?
    /// How far the last fit pushed the window to clear an overlap (see fitLayoutToScreen).
    var fitPush: CGVector = .zero
    /// Captured once when first seen, even if it's then on screen and not captured any more.
    var needsFirstFrame = true
    /// The last one-off picture asked for (CACurrentMediaTime), and failures in a row since.
    var lastSnapshotAt: CFTimeInterval = 0
    var snapshotFailures = 0
    /// Width in pixels of the picture showing now (captured smaller when zoomed out).
    var pictureWidth = 0

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

    /// The element if it's been looked up already (no Accessibility call).
    var knownAX: AXUIElement? { axElement }

    /// An element found elsewhere (a window scan), saving a lookup.
    func adopt(ax element: AXUIElement) {
        if axElement == nil { axElement = element }
    }

    var ax: AXUIElement? {
        if let axElement { return axElement }
        axElement = AX.windows(pid: pid).first { AX.windowID($0) == id }
        return axElement
    }

    /// Real window moves made so far (main thread), so a window scan can tell its frames are out
    /// of date.
    static var moves = 0

    /// Moves the real window to `point` (global CG coords) and records where it landed.
    func place(at point: CGPoint) {
        guard let ax else { return }
        if let last = lastPlaced, last.distance(to: point) < 0.5 { return }
        Self.moves += 1
        let before = lastPlaced
        AX.setPosition(ax, point)
        lastPlaced = AX.position(ax) ?? point
        lastPlacedAt = CACurrentMediaTime()
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
    static let cornerRadius: CGFloat = 16
    /// Narrower than this on screen, a window shows no close button (it would cover too much).
    static let closeMinWidth: CGFloat = 220

    /// Clicks only count as "close" while the button is actually showing.
    var closeVisible: Bool { !closeButton.isHidden && !container.isHidden }

    private var placedFrame = CGRect.null
    private var styled: (scale: CGFloat, hovered: Bool, selected: Bool, showsClose: Bool)?

    init() {
        container.shadowColor = NSColor.black.cgColor
        container.shadowOpacity = 0.22
        container.shadowRadius = 14
        container.shadowOffset = CGSize(width: 0, height: -6)

        // No masksToBounds: captured windows already have transparent rounded corners, and
        // clipping costs an offscreen pass per window per frame. The corner radius only rounds
        // the placeholder background shown before the first frame arrives.
        content.contentsGravity = .resize
        content.cornerRadius = WindowNode.cornerRadius
        content.backgroundColor = NSColor(white: 0.97, alpha: 1).cgColor
        content.minificationFilter = .linear
        content.magnificationFilter = .linear
        container.addSublayer(content)

        highlight.borderColor = NSColor.controlAccentColor.cgColor
        highlight.borderWidth = 0
        highlight.cornerRadius = WindowNode.cornerRadius
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
        label.anchorPoint = .zero
    }

    func setContentsScale(_ s: CGFloat) {
        label.contentsScale = s
        closeGlyph.contentsScale = s
    }

    /// Close button rect in view coordinates (top-left origin) for a window drawn at `r`.
    static func closeRect(in r: CGRect) -> CGRect {
        CGRect(x: r.maxX - closeInset - closeSize, y: r.minY + closeInset, width: closeSize, height: closeSize)
    }

    /// Puts the node at its canvas frame. Nodes live in canvas space with y pointing up (the
    /// canvas view's camera transform maps that to the screen), so this only runs when the window
    /// moves or resizes, never per animation frame.
    func place(canvasFrame f: CGRect) {
        guard f != placedFrame else { return }
        placedFrame = f
        container.frame = CGRect(x: f.minX, y: -f.maxY, width: f.width, height: f.height)
        content.frame = container.bounds
        highlight.frame = container.bounds
        let r = WindowNode.cornerRadius
        container.shadowPath = CGPath(roundedRect: container.bounds, cornerWidth: r, cornerHeight: r, transform: nil)
        styled = nil
    }

    /// Details that stay the same size on screen at any zoom: border, close button, label.
    /// `screenRect` is the window on screen in layer coordinates (bottom-left origin).
    /// `showsClose`: hovered, or in a selection whose window is hovered (× closes them all).
    func style(scale s: CGFloat, hovered: Bool, selected: Bool, showsClose: Bool, visible: Bool, screenRect: CGRect) {
        container.isHidden = !visible
        label.isHidden = !visible || screenRect.width < 70
        guard visible else { return }
        // Text layers redraw when resized, so while zooming the width only changes in 32pt steps.
        let width = max((max(screenRect.width - 4, 60) / 32).rounded(.down) * 32, 60)
        if label.bounds.width != width { label.bounds = CGRect(x: 0, y: 0, width: width, height: 15) }
        label.position = CGPoint(x: screenRect.minX + 2, y: screenRect.maxY + 5)
        if let styled, styled.scale == s, styled.hovered == hovered, styled.selected == selected,
           styled.showsClose == showsClose { return }
        styled = (s, hovered, selected, showsClose)
        highlight.borderWidth = (selected ? 3 : hovered ? 2 : 0) / s
        closeButton.isHidden = !showsClose || screenRect.width < WindowNode.closeMinWidth
        closeButton.transform = CATransform3DMakeScale(1 / s, 1 / s, 1)
        let inset = (WindowNode.closeInset + WindowNode.closeSize / 2) / s
        closeButton.position = CGPoint(x: placedFrame.width - inset, y: placedFrame.height - inset)
    }
}
