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

    /// Calls back on the main thread.
    static func capture(screen: NSScreen, completion: @escaping (CGImage?) -> Void) {
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
            guard let display = content?.displays.first(where: { $0.displayID == displayID }) ?? content?.displays.first,
                  desktop.contains(where: { $0.frame.size == size && (desktopLevel - 2...desktopLevel).contains($0.windowLayer) })
            else {
                DispatchQueue.main.async { completion(fromFile(screen: screen)) }
                return
            }
            let config = SCStreamConfiguration()
            config.width = Int(size.width * scale)
            config.height = Int(size.height * scale)
            config.showsCursor = false
            config.capturesAudio = false
            SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, including: desktop),
                                             configuration: config) { image, error in
                if let error { logger.error("wallpaper capture failed: \(error.localizedDescription)") }
                DispatchQueue.main.async { completion(image ?? fromFile(screen: screen)) }
            }
        }
    }

    private static func fromFile(screen: NSScreen) -> CGImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
