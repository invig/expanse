import AppKit
import ApplicationServices

/// Accessibility notifications for one app: window created / moved / resized / destroyed,
/// focus changes. Delivered on the main run loop.
final class AppObserver {
    let pid: pid_t
    private let app: AXUIElement
    private var observer: AXObserver?
    /// Observed windows' elements and IDs. Asking an element for its window ID is a round trip
    /// to the app; comparing elements (CFEqual) is local.
    private var observedWindows: [(element: AXUIElement, id: CGWindowID)] = []
    /// Called with the element, the notification and, for an observed window, its ID.
    private let handler: (AXUIElement, String, CGWindowID?) -> Void

    init?(pid: pid_t, handler: @escaping (AXUIElement, String, CGWindowID?) -> Void) {
        self.pid = pid
        self.app = AXUIElementCreateApplication(pid)
        self.handler = handler
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<AppObserver>.fromOpaque(refcon).takeUnretainedValue()
            me.handler(element, notification as String, me.windowID(of: element))
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
        guard !observedWindows.contains(where: { $0.id == id }) else { return }
        observedWindows.append((element, id))
        for n in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
                  kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
            add(element, n)
        }
    }

    func forget(_ id: CGWindowID) {
        observedWindows.removeAll { $0.id == id }
    }

    private func windowID(of element: AXUIElement) -> CGWindowID? {
        observedWindows.first { CFEqual($0.element, element) }?.id
    }

    private func add(_ element: AXUIElement, _ notification: String) {
        guard let observer else { return }
        AXObserverAddNotification(observer, element, notification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
    }
}
