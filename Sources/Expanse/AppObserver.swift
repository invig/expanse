import AppKit
import ApplicationServices

/// Accessibility notifications for one app: window created / moved / resized / destroyed,
/// focus changes. Delivered on the main run loop.
final class AppObserver {
    let pid: pid_t
    private let app: AXUIElement
    private var observer: AXObserver?
    private var observedWindows = Set<CGWindowID>()
    private let handler: (AXUIElement, String) -> Void

    init?(pid: pid_t, handler: @escaping (AXUIElement, String) -> Void) {
        self.pid = pid
        self.app = AXUIElementCreateApplication(pid)
        self.handler = handler
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<AppObserver>.fromOpaque(refcon).takeUnretainedValue()
            me.handler(element, notification as String)
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return nil }
        observer = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        add(app, kAXWindowCreatedNotification)
        add(app, kAXFocusedWindowChangedNotification)
    }

    deinit {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    func observe(window element: AXUIElement, id: CGWindowID) {
        guard observedWindows.insert(id).inserted else { return }
        for n in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
                  kAXWindowMiniaturizedNotification] {
            add(element, n)
        }
    }

    func forget(_ id: CGWindowID) {
        observedWindows.remove(id)
    }

    private func add(_ element: AXUIElement, _ notification: String) {
        guard let observer else { return }
        AXObserverAddNotification(observer, element, notification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
    }
}
