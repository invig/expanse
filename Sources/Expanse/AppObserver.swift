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
    /// Signing up for a notification is a round trip to the app, slow while it's busy (opening
    /// ten windows at once, say): five per window would hold up the main thread for half a
    /// second. It happens here instead, one queue per app, so a busy app only delays itself.
    private let queue = DispatchQueue(label: "com.invignation.expanse.observer", qos: .userInitiated)

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
        add(app, [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification])
    }

    deinit {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    func observe(window element: AXUIElement, id: CGWindowID) {
        guard !observedWindows.contains(where: { $0.id == id }) else { return }
        observedWindows.append((element, id))
        add(element, [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
                      kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification])
    }

    func forget(_ id: CGWindowID) {
        observedWindows.removeAll { $0.id == id }
    }

    private func windowID(of element: AXUIElement) -> CGWindowID? {
        observedWindows.first { CFEqual($0.element, element) }?.id
    }

    private func add(_ element: AXUIElement, _ notifications: [String]) {
        guard let observer else { return }
        // Callbacks only arrive through the run loop source, which deinit removes on the main
        // thread, so one never sees a freed observer even if this runs after it's gone.
        let refcon = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        queue.async {
            for n in notifications {
                AXObserverAddNotification(observer, element, n as CFString, UnsafeMutableRawPointer(bitPattern: refcon))
            }
        }
    }
}
