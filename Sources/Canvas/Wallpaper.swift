import AppKit
import ScreenCaptureKit

/// The desktop picture as macOS is drawing it right now. Capturing the wallpaper window
/// (rather than reading the image file) also covers dynamic and generated wallpapers.
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
            // WindowManager, one level below kCGDesktopWindowLevel. Match loosely.
            let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
            let fullScreen = (content?.windows ?? []).filter {
                $0.frame.origin == .zero && $0.frame.size == size && (desktopLevel - 2...desktopLevel).contains($0.windowLayer)
            }
            let window = fullScreen.first { $0.title == "Wallpaper" } ?? fullScreen.first
            guard let window else {
                DispatchQueue.main.async { completion(fromFile(screen: screen)) }
                return
            }
            let config = SCStreamConfiguration()
            config.width = Int(size.width * scale)
            config.height = Int(size.height * scale)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
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
