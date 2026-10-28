import AppKit
import CryptoKit

/// Saves the canvas (camera + where each window lives) to
/// ~/Library/Application Support/Expanse/layout.json so it survives restarts.
struct SavedLayout: Codable {
    struct Window: Codable {
        var bundleID: String
        var appName: String
        var title: String
        var x: Double
        var y: Double
        /// The window's size on the canvas; reapplied on launch because quitting restores the
        /// original macOS size.
        var w: Double?
        var h: Double?
        /// Position in the home layout (full chosen sizes).
        var hx: Double?
        var hy: Double?
        /// The size the user last chose; windows shrink to fit small screens and grow back.
        var pw: Double?
        var ph: Double?
        /// The window's frame in the macOS layout before Expanse (global CG coords).
        var ox: Double?
        var oy: Double?
        var ow: Double?
        var oh: Double?
        /// The window's ID and its app's pid: while the app keeps running (Expanse restarted,
        /// say), they identify the window exactly, even among windows with the same title.
        var id: UInt32?
        var pid: Int32?
    }
    var cameraX: Double
    var cameraY: Double
    /// Canvas point at the middle of the screen. Preferred over cameraX/Y so the view stays
    /// centered when the screen size differs between runs.
    var centerX: Double?
    var centerY: Double?
    /// True when the last run put windows back in their macOS layout before exiting.
    var cleanExit: Bool?
    /// The screen size the layout was fitted to: at launch, windows only move by however much
    /// the screen differs (see CanvasController.fitLayoutToScreen).
    var fittedWidth: Double?
    var fittedHeight: Double?
    var windows: [Window]
}

enum LayoutStore {
    private static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Expanse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var url: URL { folder.appendingPathComponent("layout.json") }

    static func load() -> SavedLayout? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedLayout.self, from: data)
    }

    static func save(_ layout: SavedLayout) {
        write(layout, to: url)
    }

    private static func write(_ layout: SavedLayout, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(layout) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Snapshots

    /// Earlier layouts to go back to (Restore Layout in the menu), newest first. One is taken when
    /// the layout has changed and the newest is `snapshotSpacing` old, so they're minutes apart,
    /// not one per window move; only the newest `snapshotsKept` stay.
    struct Snapshot {
        let date: Date
        let url: URL
    }
    static let snapshotsKept = 3
    static let snapshotSpacing: TimeInterval = 15 * 60

    private static var snapshotFolder: URL {
        let dir = folder.appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func snapshots() -> [Snapshot] {
        let files = (try? FileManager.default.contentsOfDirectory(at: snapshotFolder, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { file in
            // Named for the time they were taken (seconds since 1970).
            guard file.pathExtension == "json", let t = TimeInterval(file.deletingPathExtension().lastPathComponent) else { return nil }
            return Snapshot(date: Date(timeIntervalSince1970: t), url: file)
        }.sorted { $0.date > $1.date }
    }

    static func saveSnapshot(_ layout: SavedLayout) {
        let now = Int(Date().timeIntervalSince1970)
        write(layout, to: snapshotFolder.appendingPathComponent("\(now).json"))
        for old in snapshots().dropFirst(snapshotsKept) { try? FileManager.default.removeItem(at: old.url) }
    }

    static func load(_ snapshot: Snapshot) -> SavedLayout? {
        guard let data = try? Data(contentsOf: snapshot.url) else { return nil }
        return try? JSONDecoder().decode(SavedLayout.self, from: data)
    }

    /// Window titles can be private (document names, mail subjects), so the layout file stores
    /// a hash: enough to recognise the same window next time, not to read the title.
    static func titleKey(_ title: String) -> String {
        guard !title.isEmpty else { return "" }
        let digest = SHA256.hash(data: Data(title.utf8))
        return "sha256:" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Identifies a window for as long as its app keeps running.
    static func windowKey(pid: pid_t, id: CGWindowID) -> String { "\(pid):\(id)" }

    /// Whether the window server still has this window, on screen or not.
    private static func exists(id: CGWindowID, pid: pid_t) -> Bool {
        var ids = [UnsafeRawPointer(bitPattern: UInt(id))]
        guard let array = CFArrayCreate(nil, &ids, 1, nil),
              let info = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] else { return false }
        return info.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }
    }

    /// Picks the saved entry for a window: the same window (same ID in the same app process),
    /// then same app and title, then same app. Matched entries are removed so two windows never
    /// claim the same slot, and `open` (keys of windows open now) keeps the fallbacks from taking
    /// an entry that belongs to another open window.
    static func takeMatch(bundleID: String, title: String, id: CGWindowID, pid: pid_t, open: Set<String>,
                          from pool: inout [SavedLayout.Window]) -> SavedLayout.Window? {
        if let i = pool.firstIndex(where: { $0.id == id && $0.pid == pid && $0.bundleID == bundleID }) {
            return pool.remove(at: i)
        }
        func free(_ e: SavedLayout.Window) -> Bool {
            guard let eid = e.id, let epid = e.pid else { return true }
            // Not for another window while its own is open, or out of view (hidden, minimised)
            // and due back.
            return !open.contains(windowKey(pid: epid, id: eid)) && !exists(id: eid, pid: epid)
        }
        let key = titleKey(title)
        // Older layout files stored the title itself.
        if let i = pool.firstIndex(where: { $0.bundleID == bundleID && ($0.title == key || $0.title == title) && free($0) }) {
            return pool.remove(at: i)
        }
        if let i = pool.firstIndex(where: { $0.bundleID == bundleID && free($0) }) {
            return pool.remove(at: i)
        }
        return nil
    }
}
