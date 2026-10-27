import AppKit

/// Beside the minimap: one tile per Space on the main display. Full-screen apps live in Spaces of
/// their own, off the canvas; this is how you see them and get to them (and back). Only shown
/// when there's more than one Space. Drawn on glass (see GlassPanel), in the colours
/// applyAppearance gives it.
final class SpacesBar: CALayer {
    private static let tile = CGSize(width: 104, height: 65)   // the screen's shape, roughly
    private static let gap: CGFloat = 10

    private(set) var spaces: [Spaces.Space] = []
    private var active: UInt64?
    private var wallpaper: CGImage?
    private var tiles: [CALayer] = []
    private var labels: [CATextLayer] = []
    private let heading = CATextLayer()
    private var scale: CGFloat = 2
    private var appearance = NSAppearance(named: .darkAqua)!
    /// The tile under the pointer.
    var hovered: Int? {
        didSet { if hovered != oldValue { styleTiles() } }
    }

    override init() {
        super.init()
        heading.string = "Spaces"
        heading.fontSize = 11
        heading.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        addSublayer(heading)
        isHidden = true
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func setContentsScale(_ s: CGFloat) {
        scale = s
        contentsScale = s
        heading.contentsScale = s
        for tile in tiles { tile.sublayers?.forEach { $0.contentsScale = s } }
        for label in labels { label.contentsScale = s }
    }

    /// Dark text on light glass, light text on dark.
    func applyAppearance(_ appearance: NSAppearance) {
        self.appearance = appearance
        styleTiles()
    }

    /// Rebuilt only when something changed. Hidden with a single Space: nothing to switch to.
    func update(spaces: [Spaces.Space], active: UInt64?, wallpaper: CGImage?) {
        guard spaces != self.spaces || active != self.active || wallpaper !== self.wallpaper else { return }
        self.spaces = spaces
        self.active = active
        self.wallpaper = wallpaper
        isHidden = spaces.count < 2
        (tiles + labels).forEach { $0.removeFromSuperlayer() }
        tiles = spaces.enumerated().map { makeTile($1, at: $0) }
        labels = spaces.enumerated().map { makeLabel($1, under: tiles[$0]) }
        (tiles + labels).forEach(addSublayer)
        let width = Self.gap + CGFloat(spaces.count) * (Self.tile.width + Self.gap)
        bounds = CGRect(x: 0, y: 0, width: width, height: Minimap.size.height)
        heading.frame = CGRect(x: Self.gap, y: Minimap.size.height - 25, width: 120, height: 14)
        styleTiles()
    }

    /// The tile at `p` (this layer's coordinates).
    func tile(at p: CGPoint) -> Int? {
        guard !isHidden else { return nil }
        return tiles.firstIndex { $0.frame.insetBy(dx: -4, dy: -18).contains(p) }
    }

    private func makeTile(_ space: Spaces.Space, at i: Int) -> CALayer {
        let tile = CALayer()
        tile.frame = CGRect(x: Self.gap + CGFloat(i) * (Self.tile.width + Self.gap), y: 34,
                            width: Self.tile.width, height: Self.tile.height)
        // Concentric with the panel's corners.
        tile.cornerRadius = GlassPanel.radius - Self.gap
        tile.cornerCurve = .continuous
        tile.masksToBounds = true
        if space.isDesktop {
            // The desktop: its picture, as on the canvas.
            tile.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
            tile.contents = wallpaper
            tile.contentsGravity = .resizeAspectFill
        } else if let pid = space.pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            // A full-screen app: its icon (on a colour that suits the glass; see styleTiles).
            let image = CALayer()
            // At the size it's drawn, in pixels (the default is a small, blurry version).
            var rect = CGRect(x: 0, y: 0, width: 36 * scale, height: 36 * scale)
            image.contents = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            image.contentsGravity = .resizeAspect
            image.frame = CGRect(x: (Self.tile.width - 36) / 2, y: (Self.tile.height - 36) / 2, width: 36, height: 36)
            image.contentsScale = scale
            tile.addSublayer(image)
        }
        return tile
    }

    private func makeLabel(_ space: Spaces.Space, under tile: CALayer) -> CATextLayer {
        let label = CATextLayer()
        label.string = space.name
        label.fontSize = 11
        label.alignmentMode = .center
        label.truncationMode = .end
        label.contentsScale = scale
        label.frame = CGRect(x: tile.frame.minX - 2, y: 13, width: Self.tile.width + 4, height: 14)
        return label
    }

    /// The Space you're on is outlined in the accent colour and named in bold; the one under the
    /// pointer lights up.
    private func styleTiles() {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        appearance.performAsCurrentDrawingAppearance {
            // Text in a layer gets no vibrancy from the glass, so secondary text is darker than
            // secondaryLabelColor, or it would be too faint to read.
            heading.foregroundColor = NSColor.labelColor.withAlphaComponent(0.75).cgColor
            for (i, tile) in tiles.enumerated() {
                let current = spaces[i].id == active
                labels[i].foregroundColor = NSColor.labelColor.cgColor
                labels[i].font = NSFont.systemFont(ofSize: 11, weight: current ? .semibold : .regular)
                if !spaces[i].isDesktop {
                    // Black like the Space itself in dark; in light, black would outweigh the
                    // current Space, so a quiet grey.
                    tile.backgroundColor = dark ? NSColor(white: 0.06, alpha: 1).cgColor
                        : NSColor.labelColor.withAlphaComponent(0.1).cgColor
                }
                tile.borderWidth = current ? 2 : i == hovered ? 1 : 0.5
                tile.borderColor = (current ? NSColor.controlAccentColor
                    : NSColor.labelColor.withAlphaComponent(i == hovered ? 0.5 : 0.12)).cgColor
                tile.opacity = current || i == hovered ? 1 : 0.85
            }
        }
        CATransaction.commit()
    }
}
