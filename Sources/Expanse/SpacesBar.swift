import AppKit

/// Beside the minimap: one tile per Space on the main display. Full-screen apps live in Spaces of
/// their own, off the canvas; this is how you see them and get to them (and back). Only shown
/// when there's more than one Space.
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
    /// The tile under the pointer.
    var hovered: Int? {
        didSet { if hovered != oldValue { styleTiles() } }
    }

    override init() {
        super.init()
        backgroundColor = NSColor(white: 0.12, alpha: 0.88).cgColor
        cornerRadius = 12
        borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        borderWidth = 1
        heading.string = "Spaces"
        heading.fontSize = 10
        heading.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        heading.foregroundColor = NSColor(white: 1, alpha: 0.55).cgColor
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
        heading.frame = CGRect(x: 12, y: Minimap.size.height - 22, width: 120, height: 13)
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
        tile.cornerRadius = 6
        tile.masksToBounds = true
        if space.isDesktop {
            // The desktop: its picture, as on the canvas.
            tile.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
            tile.contents = wallpaper
            tile.contentsGravity = .resizeAspectFill
        } else if let pid = space.pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            // A full-screen app: its icon on black, like the Space itself.
            tile.backgroundColor = NSColor(white: 0.05, alpha: 1).cgColor
            let image = CALayer()
            image.contents = icon.cgImage(forProposedRect: nil, context: nil, hints: nil)
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
        label.fontSize = 10
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.foregroundColor = NSColor(white: 1, alpha: 0.8).cgColor
        label.alignmentMode = .center
        label.truncationMode = .end
        label.contentsScale = scale
        label.frame = CGRect(x: tile.frame.minX - 2, y: 14, width: Self.tile.width + 4, height: 13)
        return label
    }

    /// The Space you're on is outlined in the accent colour; the one under the pointer lights up.
    private func styleTiles() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, tile) in tiles.enumerated() {
            let current = spaces[i].id == active
            tile.borderWidth = current ? 2 : 1
            tile.borderColor = current ? NSColor.controlAccentColor.cgColor
                : NSColor(white: 1, alpha: i == hovered ? 0.7 : 0.15).cgColor
            tile.opacity = current || i == hovered ? 1 : 0.85
        }
        CATransaction.commit()
    }
}
