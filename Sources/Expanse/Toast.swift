import AppKit

/// A short message near the bottom of the screen that fades out, for keyboard toggles.
enum Toast {
    private static var window: NSWindow?
    private static var hideWork: DispatchWorkItem?
    /// Toasts shown so far: a fade only hides the window if no toast has come since it began.
    private static var shown = 0

    static func show(_ text: String) {
        guard let screen = NSScreen.screens.first else { return }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let size = CGSize(width: label.frame.width + 40, height: label.frame.height + 22)

        let w = window ?? {
            let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .statusBar
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            window = w
            return w
        }()
        let background = NSView(frame: CGRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        background.layer?.cornerRadius = size.height / 2
        label.frame.origin = CGPoint(x: 20, y: 11)
        background.addSubview(label)
        w.contentView = background
        let f = screen.visibleFrame
        w.setFrame(CGRect(x: f.midX - size.width / 2, y: f.minY + 80, width: size.width, height: size.height), display: true)
        // Over the last toast's fade, if one's under way (an animator change replaces it).
        NSAnimationContext.runAnimationGroup { $0.duration = 0; w.animator().alphaValue = 1 }
        w.orderFrontRegardless()

        shown += 1
        let this = shown
        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; w.animator().alphaValue = 0 },
                                                 completionHandler: {
                // A toast that came during the fade (Copy Logs' "Copied" after "Collecting
                // logs…") stays: it has a fade of its own.
                if shown == this { w.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}
