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
        /// Out of view when saved (its app hidden or quit, the window minimised, closed or on
        /// another Space): its spot is kept for when it's back, but it wasn't on the canvas. Nil
        /// in layouts saved before this was recorded.
        var away: Bool?
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
        read(url)
    }

    /// A layout file is the user's to edit, and any app of theirs could write it: what it says
    /// moves other apps' windows, so only numbers within reason are taken (a window with others
    /// is left out). Titles from older files, stored as they were, are hashed (see titleKey), so
    /// the next save doesn't carry them on.
    private static func read(_ url: URL) -> SavedLayout? {
        guard let data = try? Data(contentsOf: url),
              var layout = try? JSONDecoder().decode(SavedLayout.self, from: data),
              plausible(layout.cameraX), plausible(layout.cameraY) else { return nil }
        func valid(_ v: Double?) -> Double? { v.flatMap { plausible($0) ? $0 : nil } }
        func size(_ v: Double?) -> Double? { valid(v).flatMap { $0 > 0 ? $0 : nil } }
        if valid(layout.centerX) == nil || valid(layout.centerY) == nil { layout.centerX = nil; layout.centerY = nil }
        if size(layout.fittedWidth) == nil || size(layout.fittedHeight) == nil { layout.fittedWidth = nil; layout.fittedHeight = nil }
        layout.windows = layout.windows.compactMap { e in
            guard plausible(e.x), plausible(e.y) else { return nil }
            var e = e
            if size(e.w) == nil || size(e.h) == nil { e.w = nil; e.h = nil }
            if valid(e.hx) == nil || valid(e.hy) == nil { e.hx = nil; e.hy = nil }
            if size(e.pw) == nil || size(e.ph) == nil { e.pw = nil; e.ph = nil }
            if valid(e.ox) == nil || valid(e.oy) == nil || size(e.ow) == nil || size(e.oh) == nil {
                e.ox = nil; e.oy = nil; e.ow = nil; e.oh = nil
            }
            if !e.title.isEmpty, !e.title.hasPrefix("sha256:"), !e.title.hasPrefix("hmac:") { e.title = titleKey(e.title) }
            return e
        }
        return layout
    }

    /// Far bigger than any canvas gets (see AX.plausible).
    private static func plausible(_ v: Double) -> Bool { v.isFinite && abs(v) <= 1_000_000 }

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

    /// Earlier layouts to go back to (in the menu bar panel), newest first. One is taken when
    /// the layout has changed and the newest is `snapshotSpacing` old, so they're minutes apart,
    /// not one per window move, or when you take one; only the newest `snapshotsKept` stay.
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
        read(snapshot.url)
    }

    /// Window titles can be private (document names, mail subjects), so the layout file stores
    /// a hash: enough to recognise the same window next time, not to read the title. It's keyed
    /// with a secret kept in your Keychain, so someone with only the file (a copy, a backup)
    /// can't check a guessed title against it either.
    static func titleKey(_ title: String) -> String {
        guard !title.isEmpty else { return "" }
        guard let secret = titleSecret else { return plainTitleKey(title) }
        let code = HMAC<SHA256>.authenticationCode(for: Data(title.utf8), using: secret)
        return "hmac:" + Data(code).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// What layouts saved before the key stored, and what's stored without the Keychain.
    private static func plainTitleKey(_ title: String) -> String {
        let digest = SHA256.hash(data: Data(title.utf8))
        return "sha256:" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Every form a saved entry for `title` can have.
    private static func titleKeys(_ title: String) -> Set<String> {
        title.isEmpty ? [""] : [titleKey(title), plainTitleKey(title)]
    }

    /// The key for title hashes, made on first use. Releases only: the Keychain lets the app that
    /// made an item read it without asking, going by its signature, and asks for any other.
    /// Every release is signed the same way, so none ever asks; a development build is signed
    /// afresh (or ad hoc) as it's built, so it would, and hashes titles unkeyed as before. Both
    /// kinds are recognised.
    private static let titleSecret: SymmetricKey? = {
        guard Updater.shared.isRelease else { return nil }
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "com.invignation.expanse",
                                   kSecAttrAccount as String: "window-title-key"]
        var found: CFTypeRef?
        var query = item
        query[kSecReturnData as String] = true
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        if status == errSecSuccess, let data = found as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound else {
            logger.info("window title key not available (\(status)): titles hashed without it")
            return nil
        }
        let key = SymmetricKey(size: .bits256)
        var add = item
        add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        add[kSecAttrLabel as String] = "Expanse window title key"
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else {
            logger.info("window title key not saved (\(added)): titles hashed without it")
            return nil
        }
        return key
    }()

    /// Identifies a window for as long as its app keeps running.
    static func windowKey(pid: pid_t, id: CGWindowID) -> String { "\(pid):\(id)" }

    /// The saved window is still open (out of view, say), in the same run of its app.
    static func isOpen(_ e: SavedLayout.Window) -> Bool {
        guard let id = e.id, let pid = e.pid else { return false }
        return exists(id: id, pid: pid)
    }

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
    /// an entry that belongs to another open window. A window of `size` far smaller than an
    /// entry's (an update or loading box, a small dialog) doesn't take it either: the app's main
    /// window, a moment later, does (see largerSpot).
    static func takeMatch(bundleID: String, title: String, id: CGWindowID, pid: pid_t, size: CGSize? = nil, open: Set<String>,
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
        let keys = titleKeys(title)
        func fits(_ e: SavedLayout.Window) -> Bool { size.map { !tooSmall($0, for: e) } ?? true }
        if let i = pool.firstIndex(where: { $0.bundleID == bundleID && keys.contains($0.title) && free($0) && fits($0) }) {
            return pool.remove(at: i)
        }
        if let i = pool.firstIndex(where: { $0.bundleID == bundleID && free($0) && fits($0) }) {
            return pool.remove(at: i)
        }
        return nil
    }

    /// A free entry of the app's that a window of `size` is too small to take (see takeMatch):
    /// the window it's standing in for, while the app starts up. Left in the pool.
    static func largerSpot(bundleID: String, size: CGSize, open: Set<String>,
                           in pool: [SavedLayout.Window]) -> SavedLayout.Window? {
        pool.first { e in
            guard e.bundleID == bundleID, tooSmall(size, for: e) else { return false }
            guard let eid = e.id, let epid = e.pid else { return true }
            return !open.contains(windowKey(pid: epid, id: eid)) && !exists(id: eid, pid: epid)
        }
    }

    /// Under a quarter of the entry's area: not the same window coming back.
    private static func tooSmall(_ size: CGSize, for e: SavedLayout.Window) -> Bool {
        guard let w = e.pw ?? e.w, let h = e.ph ?? e.h, w > 0, h > 0 else { return false }
        return Double(size.width * size.height) < 0.25 * w * h
    }
}
