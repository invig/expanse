import AppKit

/// A Liquid Glass panel for an overlay drawn in layers (the minimap, the Spaces strip), over
/// whatever the canvas shows behind it: system glass from macOS 26, the HUD material before.
/// Clicks go through to the canvas, which hit-tests the layers itself.
final class GlassPanel: NSView {
    static let radius: CGFloat = 22

    private let host = Host()
    /// A soft shadow round the panel, so it lifts off light window pictures as the Dock does.
    /// Masked to outside the panel, so the glass never samples it.
    private let lift = NSView()

    /// `appearanceChanged` gets the appearance the glass gives its content (light or dark text),
    /// at once and whenever it changes.
    init(content: CALayer, appearanceChanged: @escaping (NSAppearance) -> Void) {
        super.init(frame: .zero)
        host.wantsLayer = true
        host.layer?.addSublayer(content)
        host.content = content
        host.appearanceChanged = appearanceChanged
        let effect: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.radius
            glass.contentView = host
            effect = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .hudWindow
            material.blendingMode = .withinWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = Self.radius
            material.layer?.cornerCurve = .continuous
            material.layer?.masksToBounds = true
            host.autoresizingMask = [.width, .height]
            material.addSubview(host)
            effect = material
        }
        effect.autoresizingMask = [.width, .height]
        lift.wantsLayer = true
        lift.layer?.shadowColor = NSColor.black.cgColor
        lift.layer?.shadowRadius = 14
        lift.layer?.shadowOffset = CGSize(width: 0, height: -5)
        addSubview(lift)
        addSubview(effect)
    }

    override func layout() {
        super.layout()
        lift.frame = bounds
        let panel = CGPath(roundedRect: bounds, cornerWidth: Self.radius, cornerHeight: Self.radius, transform: nil)
        lift.layer?.shadowPath = panel
        let outside = CGMutablePath()
        outside.addRect(bounds.insetBy(dx: -40, dy: -40))
        outside.addPath(panel)
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = outside
        mask.fillRule = .evenOdd
        lift.layer?.mask = mask
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        lift.layer?.shadowOpacity = dark ? 0.32 : 0.14
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private final class Host: NSView {
        var content: CALayer?
        var appearanceChanged: ((NSAppearance) -> Void)?

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            content?.frame = bounds
            CATransaction.commit()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            appearanceChanged?(effectiveAppearance)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            appearanceChanged?(effectiveAppearance)
        }
    }
}
