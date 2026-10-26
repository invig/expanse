import AppKit

/// Saves the canvas (camera + where each window lives) to
/// ~/Library/Application Support/Canvas/layout.json so it survives restarts.
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
        /// The size the user last chose; windows shrink to fit small screens and grow back.
        var pw: Double?
        var ph: Double?
        /// The window's frame in the macOS layout before Canvas (global CG coords).
        var ox: Double?
        var oy: Double?
        var ow: Double?
        var oh: Double?
    }
    var cameraX: Double
    var cameraY: Double
    /// Canvas point at the middle of the screen. Preferred over cameraX/Y so the view stays
    /// centered when the screen size differs between runs.
    var centerX: Double?
    var centerY: Double?
    /// True when the last run put windows back in their macOS layout before exiting.
    var cleanExit: Bool?
    var windows: [Window]
}

enum LayoutStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Canvas", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layout.json")
    }

    static func load() -> SavedLayout? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedLayout.self, from: data)
    }

    static func save(_ layout: SavedLayout) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(layout) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Picks the saved entry for a window: same app and title first, then same app.
    /// Matched entries are removed so two windows never claim the same slot.
    static func takeMatch(bundleID: String, title: String, from pool: inout [SavedLayout.Window]) -> SavedLayout.Window? {
        if let i = pool.firstIndex(where: { $0.bundleID == bundleID && $0.title == title }) {
            return pool.remove(at: i)
        }
        if let i = pool.firstIndex(where: { $0.bundleID == bundleID }) {
            return pool.remove(at: i)
        }
        return nil
    }
}
