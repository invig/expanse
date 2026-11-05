import AppKit
import ScreenCaptureKit

/// The desktop as macOS is drawing it right now: its picture (dimmed, say, behind a window that
/// fills the screen), with the icons on it, and no windows. The canvas draws it behind the windows,
/// so opening the canvas over the real desktop (which shows at 100%) changes nothing under them.
/// Capturing it (rather than reading the image file) also covers dynamic and generated wallpapers.
enum Wallpaper {
    static let defaultsKey = "background"

    static var enabled: Bool {
        get { UserDefaults.standard.string(forKey: defaultsKey) != "plain" }
        set { UserDefaults.standard.set(newValue ? "wallpaper" : "plain", forKey: defaultsKey) }
    }

    /// What asking for a picture came to.
    enum Result {
        case picture(CGImage?)
        /// The desktop's on its way across the screen (or macOS's black backdrop is showing): ask
        /// again in a moment. See desktopState.
        case notSettled
    }

    /// One of the windows below Expanse's backdrop, as far as desktopState needs to know.
    struct DesktopWindow {
        let frame: CGRect
        let layer: Int
        var title: String?
    }

    enum DesktopState: Equatable {
        /// The desktop's windows are where they rest on this display: a picture of them is good.
        case atRest
        /// macOS moves a Space's windows as it changes Spaces, and draws a black backdrop on a
        /// full-screen app's: a picture now wouldn't be of the desktop.
        case moving
        /// No window of the screen's size at the desktop's levels (an older macOS, say).
        case absent
    }

    /// `levels` are those of the wallpaper's window. Only windows on this display count: another
    /// display's can be the same size, and has a full-screen app's Space of its own.
    static func desktopState(_ windows: [DesktopWindow], display: CGRect, levels: ClosedRange<Int>) -> DesktopState {
        let here = windows.filter { $0.frame.width == display.width && $0.frame.intersects(display) }
        if here.contains(where: { $0.frame.minX != display.minX || $0.title == "Fullscreen Backdrop" }) { return .moving }
        if here.contains(where: { $0.frame == display && levels.contains($0.layer) }) { return .atRest }
        // Right off this display, part way through a change of Spaces.
        return windows.contains(where: { $0.frame.size == display.size && levels.contains($0.layer) }) ? .moving : .absent
    }

    /// Calls back on the main thread.
    static func capture(screen: NSScreen, completion done: @escaping (Result) -> Void) {
        // A request to replayd, which quitting waits for (see WindowCapture.unanswered).
        WindowCapture.requestSent()
        let completion = { (result: Result) in
            WindowCapture.requestAnswered()
            done(result)
        }
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
            // On recent macOS the wallpaper is a full-screen window titled "Wallpaper", owned by
            // WindowManager, one level below kCGDesktopWindowLevel; the icons are Finder's, at the
            // desktop icon level, and the shade under the menu bar just above them. All of it is
            // below Expanse's own backdrop (see OverlayWindow.backdropLevel), and every app window.
            let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
            let backdropLevel = OverlayWindow.backdropLevel.rawValue
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let desktop = (content?.windows ?? []).filter {
                $0.windowLayer < backdropLevel && $0.owningApplication?.processID != ownPID
            }
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content?.displays.first(where: { $0.displayID == displayID }) ?? content?.displays.first else {
                DispatchQueue.main.async { completion(.picture(fromFile(screen: screen))) }
                return
            }
            let state = desktopState(desktop.map { DesktopWindow(frame: $0.frame, layer: $0.windowLayer, title: $0.title) },
                                     display: display.frame, levels: (desktopLevel - 2)...desktopLevel)
            switch state {
            case .moving:
                DispatchQueue.main.async { completion(.notSettled) }
            case .absent:
                DispatchQueue.main.async { completion(.picture(fromFile(screen: screen))) }
            case .atRest:
                let config = configuration(size: size, scale: scale)
                SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, including: desktop),
                                                 configuration: config) { image, error in
                    if let error { logger.error("wallpaper capture failed: \(error.localizedDescription)") }
                    DispatchQueue.main.async { completion(.picture(image ?? fromFile(screen: screen))) }
                }
            }
        }
    }

    /// The desktop at the screen's pixel size: no cursor, no audio.
    private static func configuration(size: CGSize, scale: CGFloat) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = Int(size.width * scale)
        config.height = Int(size.height * scale)
        config.showsCursor = false
        config.capturesAudio = false
        return config
    }

    static func fromFile(screen: NSScreen) -> CGImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

/// Over a full-screen app, along the top of the screen, while the canvas is up. The canvas's window
/// stops at the menu bar, but macOS hides the menu bar on that Space, so the app's own top edge
/// (Brave's tabs, say) would show above the canvas, and take clicks. This carries the canvas's
/// desktop on up to the screen's edge. The menu bar still comes down over it, as macOS does there.
final class MenuBarStrip: NSWindow {
    private let picture = CALayer()

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        level = OverlayWindow.canvasLevel
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let content = NSView()
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        picture.contentsGravity = .resizeAspectFill
        picture.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        content.layer?.addSublayer(picture)
        contentView = content
    }

    /// Its place is where macOS keeps windows out of: left to itself, it moves the strip down below
    /// the menu bar, behind the canvas.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// `frame` is the strip's, `screenHeight` the whole screen's: the picture sits as it does on the
    /// canvas (see CanvasView's wallpaper), so it runs on from there with no join.
    func update(frame: NSRect, screenHeight: CGFloat, image: CGImage?, background: CGColor) {
        setFrame(frame, display: false)
        contentView?.layer?.backgroundColor = background
        picture.contents = image
        picture.frame = CGRect(x: 0, y: frame.height - screenHeight, width: frame.width, height: screenHeight)
    }
}
