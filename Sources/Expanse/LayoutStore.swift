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
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Expanse", isDirectory: true)
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
    /// Window titles can be private (document names, mail subjects), so the layout file stores
    /// a hash: enough to recognise the same window next time, not to read the title.
    static func titleKey(_ title: String) -> String {
        guard !title.isEmpty else { return "" }
        let digest = SHA256.hash(data: Data(title.utf8))
        return "sha256:" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func takeMatch(bundleID: String, title: String, from pool: inout [SavedLayout.Window]) -> SavedLayout.Window? {
        let key = titleKey(title)
        // Older layout files stored the title itself.
        if let i = pool.firstIndex(where: { $0.bundleID == bundleID && ($0.title == key || $0.title == title) }) {
            return pool.remove(at: i)
        }
        if let i = pool.firstIndex(where: { $0.bundleID == bundleID }) {
            return pool.remove(at: i)
        }
        return nil
    }
}
