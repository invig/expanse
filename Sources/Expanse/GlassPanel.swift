import AppKit

/// A Liquid Glass panel for an overlay drawn in layers (the minimap, the Spaces strip), over
/// whatever the canvas shows behind it: system glass from macOS 26, the HUD material before.
/// Clicks go through to the canvas, which hit-tests the layers itself.
final class GlassPanel: NSView {
    static let radius: CGFloat = 22

    private let host = Host()

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
        addSubview(effect)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Where the overlay puts its text, as AppKit labels on the glass (in the content layer's
    /// coordinates), so it's drawn as AppKit draws text and takes the glass's appearance by itself.
    var textHost: NSView { host }

    /// Headings and values: the glass gives AppKit labels no extra contrast, so secondaryLabelColor
    /// is too faint on it; 70% of the label colour still reads as secondary.
    static let secondaryText = NSColor.labelColor.withAlphaComponent(0.7)

    static func label(_ text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        return label
    }

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
