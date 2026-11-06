import AppKit
import ScreenCaptureKit
import ObjectiveC
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "LayoutStore.swift") @testable import Expanse

/// Shared setup for the regression tests (docs/regression). Every test that makes a
/// CanvasController or touches LayoutStore calls `Env.isolate()` first, so nothing reads or
/// writes your real layout, snapshots or logs.
enum Env {
    /// A fresh, empty folder for this test's layout and snapshots (LayoutStore.folderOverride).
    @discardableResult
    static func isolate() -> URL {
        _ = NSApplication.shared
        let dir = tempFolder()
        LayoutStore.folderOverride = dir
        return dir
    }

    static func tempFolder() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExpanseTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Runs `body` with these UserDefaults keys set, then puts the old values back. The test
    /// runner has a defaults domain of its own, so this never touches Expanse's.
    static func withDefaults<T>(_ values: [String: Any?], _ body: () throws -> T) rethrows -> T {
        let d = UserDefaults.standard
        let old = values.keys.map { ($0, d.object(forKey: $0)) }
        for (k, v) in values { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } }
        defer { for (k, v) in old { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }
        return try body()
    }
}

/// Stand-ins for ScreenCaptureKit's window and app records, which have no public initialiser:
/// made through the Objective-C runtime and filled in with key-value coding.
enum Fake {
    /// Process IDs that no real process has, for fake apps (see `regularApp`).
    static let firstPID: pid_t = 90_001

    static func app(pid: pid_t = firstPID, bundleID: String = "com.example.app", name: String = "Example") -> SCRunningApplication {
        let a = class_createInstance(SCRunningApplication.self, 0) as! SCRunningApplication
        a.setValue(pid, forKey: "processID")
        a.setValue(bundleID, forKey: "bundleIdentifier")
        a.setValue(name, forKey: "applicationName")
        return a
    }

    static func scWindow(id: CGWindowID, pid: pid_t = firstPID, bundleID: String = "com.example.app", appName: String = "Example",
                         title: String = "", frame: CGRect, layer: Int = 0, onScreen: Bool = true) -> SCWindow {
        let w = class_createInstance(SCWindow.self, 0) as! SCWindow
        w.setValue(id, forKey: "windowID")
        w.setValue(NSValue(rect: frame), forKey: "frame")
        w.setValue(title, forKey: "title")
        w.setValue(layer, forKey: "windowLayer")
        w.setValue(onScreen, forKey: "onScreen")
        w.setValue(app(pid: pid, bundleID: bundleID, name: appName), forKey: "owningApplication")
        return w
    }

    /// Makes `pid` count as an ordinary app (one with a Dock icon) in CanvasController.appPID.
    static func regularApp(_ pid: pid_t = firstPID, ownedBy owner: pid_t? = nil) {
        CanvasController.appPolicyLock.lock()
        CanvasController.appOwners[pid] = (owner ?? pid, CACurrentMediaTime() + 1_000_000)
        CanvasController.appPolicyLock.unlock()
    }

    /// A window on the canvas. Its process is fake, so Accessibility finds nothing for it and
    /// anything that would move the real window does nothing.
    static func window(id: CGWindowID, pid: pid_t = firstPID, bundleID: String = "com.example.app", appName: String = "Example",
                       title: String = "", canvas: CGRect, real: CGRect? = nil) -> ManagedWindow {
        regularApp(pid)
        let sc = scWindow(id: id, pid: pid, bundleID: bundleID, appName: appName, title: title, frame: real ?? canvas)
        let w = ManagedWindow(scWindow: sc, canvasFrame: canvas)
        w.preferredSize = canvas.size
        return w
    }
}

/// A display to pretend Expanse is on (AppKit coordinates for the usable area, like NSScreen).
struct TestDisplay {
    var size = CGSize(width: 1512, height: 982)
    var menuBar: CGFloat = 33
    /// Space a Dock that's always shown takes at the bottom or the right.
    var dockBottom: CGFloat = 0
    var dockRight: CGFloat = 0

    static let laptop = TestDisplay()
    static let external = TestDisplay(size: CGSize(width: 2560, height: 1440), menuBar: 25)

    var frame: CGRect { CGRect(origin: .zero, size: size) }
    var usable: CGRect {
        CGRect(x: 0, y: dockBottom, width: size.width - dockRight, height: size.height - menuBar - dockBottom)
    }
}

enum TestCanvas {
    /// A CanvasController on a pretend display, with no windows unless given some. It isn't
    /// started: no scans, no observers, nothing on screen.
    static func make(display: TestDisplay = .laptop, windows: [ManagedWindow] = [], layout: SavedLayout? = nil) -> CanvasController {
        let folder = Env.isolate()
        if let layout {
            LayoutStore.save(layout)
            _ = folder
        }
        let c = CanvasController()
        // Whatever this Mac's full-screen apps are showing stays out of the tests.
        c.takeSpacePictures = { _, _, _ in }
        c.displayOverride = (display.frame, display.usable)
        c.updateOverlayFrame()
        c.windows = windows
        return c
    }
}

extension SavedLayout {
    /// A layout with these windows and the camera at the origin.
    static func with(_ windows: [SavedLayout.Window], cleanExit: Bool? = true) -> SavedLayout {
        SavedLayout(cameraX: 0, cameraY: 0, centerX: nil, centerY: nil, cleanExit: cleanExit,
                    fittedWidth: nil, fittedHeight: nil, windows: windows)
    }
}

extension SavedLayout.Window {
    static func entry(bundleID: String = "com.example.app", appName: String = "Example", title: String = "",
                      x: Double, y: Double, w: Double? = nil, h: Double? = nil, id: UInt32? = nil, pid: Int32? = nil) -> Self {
        SavedLayout.Window(bundleID: bundleID, appName: appName, title: title, x: x, y: y, w: w, h: h,
                           hx: nil, hy: nil, pw: nil, ph: nil, ox: nil, oy: nil, ow: nil, oh: nil, id: id, pid: pid, away: nil)
    }
}
