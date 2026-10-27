import AppKit

/// Private but stable for a decade, and only read here: the window server's list of Spaces, the
/// one Mission Control shows.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?
@_silgen_name("GetProcessForPID") private func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
@_silgen_name("CGSCopySpacesForWindows") private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> CFArray?

/// The main display's Spaces: desktops, and the Spaces macOS gives each full-screen app.
/// Expanse's canvas is the desktop you're on; full-screen windows live outside it.
enum Spaces {
    struct Space: Equatable {
        let id: UInt64
        /// The full-screen app (and its window) this Space belongs to; nil for a desktop.
        let pid: pid_t?
        let window: CGWindowID?
        /// "Desktop", "Desktop 2", or the full-screen app's name ("Safari & Notes" for split view).
        let name: String
        var isDesktop: Bool { pid == nil }
    }

    /// In Mission Control's order, and the id of the one showing.
    static func list() -> (spaces: [Space], active: UInt64?) {
        guard let display = mainDisplay() else { return ([], nil) }
        let raw = display["Spaces"] as? [[String: Any]] ?? []
        let desktops = raw.filter { ($0["type"] as? Int) == 0 }.count
        var desktopNumber = 0
        let spaces = raw.compactMap { s -> Space? in
            guard let id = spaceID(s) else { return nil }
            // 0 is a desktop, 4 a full-screen app.
            switch s["type"] as? Int {
            case 0:
                desktopNumber += 1
                return Space(id: id, pid: nil, window: nil,
                             name: desktops > 1 ? "Desktop \(desktopNumber)" : "Desktop")
            case 4:
                let tiles = (s["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]] ?? []
                guard let pid = (s["pid"] as? NSNumber)?.int32Value ?? (tiles.first?["pid"] as? NSNumber)?.int32Value
                else { return nil }
                let window = (s["fs_wid"] as? NSNumber)?.uint32Value ?? (tiles.first?["TileWindowID"] as? NSNumber)?.uint32Value
                let names = tiles.compactMap { $0["appName"] as? String }
                let name = names.isEmpty ? NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Full Screen"
                    : names.joined(separator: " & ")
                return Space(id: id, pid: pid, window: window, name: name)
            default:
                return nil
            }
        }
        return (spaces, (display["Current Space"] as? [String: Any]).flatMap(spaceID))
    }

    /// Every Space on the main display in Mission Control's order (whatever its kind: what a swipe
    /// steps through), and the one showing.
    static func order() -> (ids: [UInt64], active: UInt64?) {
        guard let display = mainDisplay() else { return ([], nil) }
        let ids = (display["Spaces"] as? [[String: Any]] ?? []).compactMap(spaceID)
        return (ids, (display["Current Space"] as? [String: Any]).flatMap(spaceID))
    }

    /// The Space showing on the main display.
    static var current: Space? {
        let (spaces, active) = list()
        return spaces.first { $0.id == active }
    }

    /// Windows that are full screen, on any display: each has a Space of its own, and Expanse
    /// leaves them be. Thread-safe.
    static func fullScreenWindows() -> Set<CGWindowID> {
        let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? []
        var ids = Set<CGWindowID>()
        for display in displays {
            for s in display["Spaces"] as? [[String: Any]] ?? [] where (s["type"] as? Int) == 4 {
                if let wid = (s["fs_wid"] as? NSNumber)?.uint32Value { ids.insert(wid) }
                let tiles = (s["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]] ?? []
                for tile in tiles {
                    if let wid = (tile["TileWindowID"] as? NSNumber)?.uint32Value { ids.insert(wid) }
                }
            }
        }
        return ids
    }

    /// The Spaces a window is on (usually one).
    static func spaces(of window: CGWindowID) -> [UInt64] {
        let ids = CGSCopySpacesForWindows(CGSMainConnectionID(), 0x7, [NSNumber(value: window)] as CFArray) as? [NSNumber]
        return (ids ?? []).map(\.uint64Value)
    }

    /// An ordinary app window on `space`, front-most first: focusing it is how to get there.
    static func someWindow(on space: UInt64) -> (pid: pid_t, id: CGWindowID)? {
        let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let id = w[kCGWindowNumber as String] as? CGWindowID, let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = w[kCGWindowBounds as String] as? [String: Double],
                  bounds["Width"] ?? 0 >= 100, bounds["Height"] ?? 0 >= 60,
                  NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular,
                  spaces(of: id).contains(space) else { continue }
            return (pid, id)
        }
        return nil
    }

    /// Bring `window` (of `pid`) to the front and make it key, through the window server: this is
    /// what makes macOS follow a window to another Space, full-screen ones included. Accessibility
    /// and ordinary activation can't (they don't see, or don't move to, other Spaces). The same
    /// private calls AltTab and yabai use; looked up at run time, so a macOS without them just
    /// returns false. Main thread.
    @discardableResult
    static func focus(pid: pid_t, window: CGWindowID) -> Bool {
        guard let setFront = WindowServer.setFront, let post = WindowServer.postEventRecord else { return false }
        var psn = ProcessSerialNumber()
        guard GetProcessForPID(pid, &psn) == noErr else { return false }
        guard setFront(&psn, window, 0x200) == 0 else { return false }   // 0x200: user generated
        // Two event records saying "this window is key" (as AltTab and yabai send them).
        for kind: UInt8 in [1, 2] {
            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x08] = kind
            bytes[0x3a] = 0x10
            withUnsafeBytes(of: window) { for (i, b) in $0.enumerated() { bytes[0x3c + i] = b } }
            for i in 0x20..<0x30 { bytes[i] = 0xff }
            _ = bytes.withUnsafeMutableBufferPointer { post(&psn, $0.baseAddress!) }
        }
        return true
    }

    private enum WindowServer {
        typealias SetFront = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
        typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32
        static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        static let setFront = dlsym(skyLight, "_SLPSSetFrontProcessWithOptions").map { unsafeBitCast($0, to: SetFront.self) }
        static let postEventRecord = dlsym(skyLight, "SLPSPostEventRecordTo").map { unsafeBitCast($0, to: PostEventRecord.self) }
    }

    /// Whether the Space showing on the main display is a full-screen app's. Asked at every
    /// window scan, so it reads just that Space's kind (4) rather than building the whole list.
    static var inFullScreenSpace: Bool {
        guard let display = mainDisplay(), let current = display["Current Space"] as? [String: Any] else { return false }
        if let type = current["type"] as? Int { return type == 4 }
        let id = spaceID(current)
        return (display["Spaces"] as? [[String: Any]] ?? []).first { spaceID($0) == id }?["type"] as? Int == 4
    }

    /// A Space's ID, under whichever key this macOS uses.
    private static func spaceID(_ space: [String: Any]) -> UInt64? {
        (space["id64"] as? NSNumber)?.uint64Value ?? (space["ManagedSpaceID"] as? NSNumber)?.uint64Value
    }

    /// The main display's entry (or the only one, when displays share Spaces).
    private static func mainDisplay() -> [String: Any]? {
        let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? []
        let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())
            .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        return displays.first { ($0["Display Identifier"] as? String) == uuid }
            ?? displays.first { ($0["Display Identifier"] as? String) == "Main" }
            ?? displays.first
    }
}
