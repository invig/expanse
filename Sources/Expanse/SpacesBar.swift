import AppKit
import ScreenCaptureKit

/// Beside the minimap: one tile per Space on the main display. Full-screen apps live in Spaces of
/// their own, off the canvas; this is how you see them and get to them (and back). Only shown
/// when there's more than one Space. Drawn on glass (see GlassPanel), in the colours
/// applyAppearance gives it.
final class SpacesBar: CALayer {
    fileprivate static let tile = CGSize(width: 100, height: 63)   // the screen's shape, roughly
    /// Between tiles, as at the panel's edges, so the current Space's ring has the same air all round.
    private static let gap: CGFloat = 14
    /// From the panel's edges to the tiles and heading.
    private static let inset: CGFloat = 14

    private(set) var spaces: [Spaces.Space] = []
    private var active: UInt64?
    private var wallpaper: CGImage?
    /// What's on each full-screen app's Space, as far as Expanse has seen (see SpacePicture).
    private var pictures: [UInt64: CGImage] = [:]
    private var tiles: [CALayer] = []
    /// Around each tile, shown for the current Space (and the one under the pointer).
    private var rings: [CALayer] = []
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
    func update(spaces: [Spaces.Space], active: UInt64?, wallpaper: CGImage?, pictures: [UInt64: CGImage] = [:]) {
        let samePictures = pictures.count == self.pictures.count && pictures.allSatisfy { self.pictures[$0.key] === $0.value }
        guard spaces != self.spaces || active != self.active || wallpaper !== self.wallpaper || !samePictures else { return }
        self.spaces = spaces
        self.active = active
        self.wallpaper = wallpaper
        self.pictures = pictures
        isHidden = spaces.count < 2
        (tiles + rings + labels).forEach { $0.removeFromSuperlayer() }
        tiles = spaces.enumerated().map { makeTile($1, at: $0) }
        rings = tiles.map(makeRing)
        labels = spaces.enumerated().map { makeLabel($1, under: tiles[$0]) }
        (tiles + rings + labels).forEach(addSublayer)
        let width = Self.inset * 2 + CGFloat(spaces.count) * (Self.tile.width + Self.gap) - Self.gap
        bounds = CGRect(x: 0, y: 0, width: width, height: Minimap.size.height)
        heading.frame = CGRect(x: Self.inset, y: Minimap.size.height - 25, width: 120, height: 14)
        styleTiles()
    }

    /// Each tile's frame (this layer's coordinates), in the order of `spaces`.
    var tileFrames: [CGRect] { tiles.map(\.frame) }

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
        } else if let picture = pictures[space.id] {
            // A full-screen app: what's on its Space.
            tile.contents = picture
            tile.contentsGravity = .resizeAspectFill
        } else if let pid = space.pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            // No picture yet: its icon (on a colour that suits the glass; see styleTiles).
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

    /// The Space you're on is ringed in the accent colour and named in bold; the one under the
    /// pointer gets a quiet ring. (The others aren't dimmed: that would read as disabled.)
    private func styleTiles() {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        appearance.performAsCurrentDrawingAppearance {
            // Text in a layer gets no vibrancy from the glass, so secondary text is darker than
            // secondaryLabelColor, or it would be too faint to read.
            heading.foregroundColor = (dark ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.75)).cgColor
            for (i, tile) in tiles.enumerated() {
                let current = spaces[i].id == active
                labels[i].foregroundColor = NSColor.labelColor.cgColor
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

/// What's on a full-screen app's Space, as a picture for its tile: every window of its app there,
/// drawn together as they sit (a browser's tabs and toolbar are windows of their own, over the page,
/// and split view is two apps side by side).
enum SpacePicture {
    /// The picture of a tile: what's needed to fill it, in whole pixels, and where each window goes in
    /// it (from its bottom left, as drawing goes). Pictures are captured at the size they're drawn.
    /// `frames` are the windows', from the top left of the screen.
    static func layout(_ frames: [CGRect], tile: CGSize, scale: CGFloat) -> (size: CGSize, rects: [CGRect]) {
        let whole = frames.reduce(CGRect.null) { $0.union($1) }
        guard !whole.isNull, whole.width > 0, whole.height > 0 else { return (.zero, []) }
        let factor = max(tile.width / whole.width, tile.height / whole.height) * scale
        let size = CGSize(width: (whole.width * factor).rounded(), height: (whole.height * factor).rounded())
        // To those whole pixels exactly, or the last row and column are part see-through.
        let x = size.width / whole.width, y = size.height / whole.height
        let rects = frames.map {
            CGRect(x: ($0.minX - whole.minX) * x, y: (whole.maxY - $0.maxY) * y, width: $0.width * x, height: $0.height * y)
        }
        return (size, rects)
    }

    /// The windows to draw for `space`, back to front (ScreenCaptureKit lists them front to back): its
    /// own, and its app's others on that Space and that screen. Not above the ordinary window level,
    /// where a popover or a tooltip that isn't showing would be. `display`: the screen, global.
    static func windows(on space: Spaces.Space, in all: [SCWindow], display: CGRect,
                        spacesOf: (CGWindowID) -> [UInt64] = Spaces.spaces(of:)) -> [SCWindow] {
        let own = all.filter { space.windows.contains($0.windowID) }
        let apps = Set(own.compactMap { $0.owningApplication?.processID })
        return all.filter { w in
            if space.windows.contains(w.windowID) { return true }
            guard w.windowLayer == 0, let app = w.owningApplication?.processID, apps.contains(app),
                  w.frame.intersects(display) else { return false }
            return spacesOf(w.windowID).contains(space.id)
        }.reversed()
    }

    /// One picture at the size asked for is the Space's as it is. Anything else (several windows,
    /// or one that came at its full size) is drawn to that size, in order. Nil with none.
    static func compose(_ pieces: [(image: CGImage, rect: CGRect)], size: CGSize) -> CGImage? {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard let first = pieces.first else { return nil }
        if pieces.count == 1, first.image.width == width, first.image.height == height { return first.image }
        guard let space = first.image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        for piece in pieces { context.draw(piece.image, in: piece.rect) }
        return context.makeImage()
    }

    /// Each Space's picture in turn (`answer` runs on the main thread, with nil if there's none to
    /// be had). Only with the canvas up: see CanvasController.refreshSpacePictures.
    static func capture(_ spaces: [Spaces.Space], scale: CGFloat, answer: @escaping (Spaces.Space, CGImage?) -> Void) {
        guard CGPreflightScreenCaptureAccess() else { return }
        // A request to replayd, which quitting waits for (see WindowCapture.unanswered).
        WindowCapture.requestSent()
        // Not only those on screen: that's just the Space showing.
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, _ in
            let windows = content?.windows ?? []
            DispatchQueue.main.async { captureNext(spaces[...], windows: windows, scale: scale, answer: answer) }
        }
    }

    /// One Space at a time, so a canvas opening doesn't send replayd a burst of requests.
    private static func captureNext(_ spaces: ArraySlice<Spaces.Space>, windows: [SCWindow], scale: CGFloat,
                                    answer: @escaping (Spaces.Space, CGImage?) -> Void) {
        guard let space = spaces.first, !WindowCapture.closing else {
            WindowCapture.requestAnswered()
            return
        }
        let here = self.windows(on: space, in: windows, display: CGDisplayBounds(CGMainDisplayID()))
        picture(of: here, scale: scale) { image in
            answer(space, image)
            captureNext(spaces.dropFirst(), windows: windows, scale: scale, answer: answer)
        }
    }

    /// The window server's picture of each window, which is the window as it is on any Space. It's
    /// off the queue ScreenCaptureKit calls back on (see Spaces.picture). ScreenCaptureKit is for when
    /// a macOS doesn't have that call: on macOS 27 it refuses a window on another Space ("Failed to
    /// start stream due to audio/video capture failure"), and leaves a clear strip down the side of
    /// a window whose frame isn't the size it captures (Brave's page in full screen).
    private static func picture(of windows: [SCWindow], scale: CGFloat, done: @escaping (CGImage?) -> Void) {
        let (size, rects) = layout(windows.map(\.frame), tile: SpacesBar.tile, scale: scale)
        DispatchQueue.global(qos: .userInitiated).async {
            var images = windows.map { windowServerShot($0.windowID) }
            DispatchQueue.main.async {
                let group = DispatchGroup()
                for i in windows.indices where images[i] == nil {
                    group.enter()
                    shot(windows[i], WindowCapture.configuration(pixelSize: rects[i].size, fps: 1)) { image, error in
                        if let error { logger.info("picture of \(windows[i].windowID) failed: \(error.localizedDescription, privacy: .public)") }
                        DispatchQueue.main.async {
                            images[i] = image
                            group.leave()
                        }
                    }
                }
                // Off the main thread, with the canvas zooming out: full-size pictures take a moment to shrink.
                group.notify(queue: .global(qos: .userInitiated)) {
                    let image = compose(zip(images, rects).compactMap { image, rect in image.map { ($0, rect) } }, size: size)
                    DispatchQueue.main.async { done(image) }
                }
            }
        }
    }

    /// ScreenCaptureKit's one-off picture call. Tests put a stand-in here, so nothing is captured.
    static var shot: (SCWindow, SCStreamConfiguration, @escaping (CGImage?, Error?) -> Void) -> Void = { window, config, done in
        SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                         configuration: config, completionHandler: done)
    }

    /// A window's picture, on any Space (see Spaces.picture). Tests put a stand-in here too.
    static var windowServerShot: (CGWindowID) -> CGImage? = Spaces.picture(of:)
}
