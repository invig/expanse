import AppKit

/// Beside the minimap: one tile per Space on the main display. Full-screen apps live in Spaces of
/// their own, off the canvas; this is how you see them and get to them (and back). Only shown
/// when there's more than one Space. Drawn on glass (see GlassPanel), in the colours
/// applyAppearance gives it, with its text on the glass itself (textHost).
final class SpacesBar: CALayer {
    private static let tile = CGSize(width: 100, height: 63)   // the screen's shape, roughly
    /// Between tiles, as at the panel's edges, so the current Space's ring has the same air all round.
    private static let gap: CGFloat = 14
    /// From the panel's edges to the tiles and heading.
    private static let inset: CGFloat = 14

    private(set) var spaces: [Spaces.Space] = []
    private var active: UInt64?
    private var wallpaper: CGImage?
    private var tiles: [CALayer] = []
    /// Around each tile, shown for the current Space (and the one under the pointer).
    private var rings: [CALayer] = []
    private var labels: [NSTextField] = []
    private lazy var heading = GlassPanel.label("Spaces", font: .systemFont(ofSize: 11, weight: .semibold),
                                                color: GlassPanel.secondaryText)
    weak var textHost: NSView? {
        didSet { textHost?.addSubview(heading) }
    }
    private var scale: CGFloat = 2
    private var appearance = NSAppearance(named: .darkAqua)!
    /// The tile under the pointer.
    var hovered: Int? {
        didSet { if hovered != oldValue { styleTiles() } }
    }

    override init() {
        super.init()
        isHidden = true
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func setContentsScale(_ s: CGFloat) {
        scale = s
        contentsScale = s
        for tile in tiles { tile.sublayers?.forEach { $0.contentsScale = s } }
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
        (tiles + rings).forEach { $0.removeFromSuperlayer() }
        labels.forEach { $0.removeFromSuperview() }
        tiles = spaces.enumerated().map { makeTile($1, at: $0) }
        rings = tiles.map(makeRing)
        labels = spaces.enumerated().map { makeLabel($1, under: tiles[$0]) }
        (tiles + rings).forEach(addSublayer)
        labels.forEach { textHost?.addSubview($0) }
        let width = Self.inset * 2 + CGFloat(spaces.count) * (Self.tile.width + Self.gap) - Self.gap
        bounds = CGRect(x: 0, y: 0, width: width, height: Minimap.size.height)
        heading.frame = CGRect(x: Self.inset, y: Minimap.size.height - 25, width: 120, height: 14)
        styleTiles()
    }

    /// The tile at `p` (this layer's coordinates).
    func tile(at p: CGPoint) -> Int? {
        guard !isHidden else { return nil }
        return tiles.firstIndex { $0.frame.insetBy(dx: -4, dy: -18).contains(p) }
    }

    private func makeTile(_ space: Spaces.Space, at i: Int) -> CALayer {
        let tile = CALayer()
        tile.frame = CGRect(x: Self.inset + CGFloat(i) * (Self.tile.width + Self.gap), y: 36,
                            width: Self.tile.width, height: Self.tile.height)
        // Concentric with the panel's corners.
        tile.cornerRadius = GlassPanel.radius - Self.inset
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
            // Lifted off the well a little, like an icon in the Dock.
            image.shadowColor = NSColor.black.cgColor
            image.shadowOpacity = 0.25
            image.shadowRadius = 2
            image.shadowOffset = CGSize(width: 0, height: -1)
            tile.addSublayer(image)
        }
        return tile
    }

    /// A ring outside the tile with a gap, as macOS marks a chosen picture, so it doesn't cover
    /// the thumbnail's edge.
    private func makeRing(around tile: CALayer) -> CALayer {
        let ring = CALayer()
        ring.frame = tile.frame.insetBy(dx: -Self.ringOutset, dy: -Self.ringOutset)
        ring.cornerRadius = tile.cornerRadius + Self.ringOutset
        ring.cornerCurve = .continuous
        return ring
    }
    private static let ringOutset: CGFloat = 4.5

    private func makeLabel(_ space: Spaces.Space, under tile: CALayer) -> NSTextField {
        let label = GlassPanel.label(space.name, font: .systemFont(ofSize: 11), color: .labelColor, alignment: .center)
        label.frame = CGRect(x: tile.frame.minX - 2, y: 13, width: Self.tile.width + 4, height: 14)
        return label
    }

    /// The Space you're on is ringed in the accent colour and named in bold; the one under the
    /// pointer gets a quiet ring. (The others aren't dimmed: that would read as disabled.)
    private func styleTiles() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        appearance.performAsCurrentDrawingAppearance {
            for (i, tile) in tiles.enumerated() {
                let current = spaces[i].id == active
                labels[i].font = NSFont.systemFont(ofSize: 11, weight: current ? .semibold : .regular)
                if !spaces[i].isDesktop {
                    // A quiet well in the glass: black would outweigh the current Space.
                    tile.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
                }
                tile.borderWidth = current ? 0 : 0.5
                tile.borderColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
                rings[i].isHidden = !current && i != hovered
                rings[i].borderWidth = current ? 2.5 : 1.5
                rings[i].borderColor = (current ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.3)).cgColor
            }
        }
        CATransaction.commit()
    }
}
