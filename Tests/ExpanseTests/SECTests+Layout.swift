import Testing
import AppKit
import CryptoKit
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "LayoutStore.swift") @testable import Expanse

/// SEC cases about the layout file: what's taken from it, and how window titles are kept.
extension SECTests {

    /// Writes `json` as layout.json in a fresh test folder and reads it back as Expanse does at launch.
    private func loadLayout(_ json: String) throws -> SavedLayout? {
        let folder = Env.isolate()
        try Data(json.utf8).write(to: folder.appendingPathComponent("layout.json"))
        return LayoutStore.load()
    }

    /// The same, as a snapshot restored from the panel's Earlier layouts.
    private func loadSnapshot(_ json: String) throws -> SavedLayout? {
        Env.isolate()
        try Data(json.utf8).write(to: LayoutStore.snapshotFolder.appendingPathComponent("1700000000.json"))
        let snapshot = try #require(LayoutStore.snapshots().first)
        return LayoutStore.load(snapshot)
    }

    private func isHex(_ s: Substring) -> Bool { s.allSatisfy { $0.isHexDigit && !$0.isUppercase } }

    /// Picks the saved entry for a window of TextEdit's titled `title`, after a relaunch (another window ID).
    private func match(_ title: String, in pool: inout [SavedLayout.Window]) -> SavedLayout.Window? {
        LayoutStore.takeMatch(bundleID: "com.apple.TextEdit", title: title, id: 999_999, pid: Self.noPID, open: [], from: &pool)
    }

    private func textEdit(_ title: String, x: Double) -> SavedLayout.Window {
        .entry(bundleID: "com.apple.TextEdit", appName: "TextEdit", title: title, x: x, y: 100)
    }

    // MARK: SEC-03

    @Test("SEC-03 A title is stored as sha256: and 24 hex digits in a development build") func sec03a() throws {
        try #require(!Updater.shared.isRelease)
        LayoutStore.titleSecretOverride = nil
        let key = LayoutStore.titleKey("Secret Plan.txt")
        #expect(key.hasPrefix("sha256:"))
        #expect(key.count == 7 + 24 && isHex(key.dropFirst(7)))
        #expect(!key.contains("Secret"))
        let digest = SHA256.hash(data: Data("Secret Plan.txt".utf8))
        #expect(key == "sha256:" + digest.prefix(12).map { String(format: "%02x", $0) }.joined())
        #expect(LayoutStore.titleKey("Secret Plan.txt") == key)
        #expect(LayoutStore.titleKey("Secret Plan 2.txt") != key)
        #expect(LayoutStore.titleKey("") == "")
    }

    @Test("SEC-03 The layout file and snapshots have no window titles in them, and windows still find their spots") func sec03b() throws {
        LayoutStore.titleSecretOverride = nil
        let other = window(1, "TextEdit", title: "Other.txt", at: CGRect(x: 900, y: 100, width: 400, height: 300))
        let secret = window(2, "TextEdit", title: "Secret Plan.txt", at: CGRect(x: 100, y: 100, width: 400, height: 300))
        let c = TestCanvas.make(windows: [other, secret])
        defer { c.windows = [] }
        let folder = try #require(LayoutStore.folderOverride)
        c.hasSynced = true
        c.save()
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "json" } ?? []
        #expect(files.count == 2)   // layout.json and a snapshot
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("Secret Plan"), "\(file.lastPathComponent)")
            #expect(text.contains(LayoutStore.titleKey("Secret Plan.txt")))
        }
        // Relaunched: the window is back (a new ID) and goes to its own spot, not Other's.
        var pool = try #require(LayoutStore.load()).windows.map { var e = $0; e.bundleID = "com.apple.TextEdit"; return e }
        #expect(match("Secret Plan.txt", in: &pool)?.x == 100)
    }

    @Test("SEC-03 Titles are hidden in the log") func sec03c() throws {
        let mark = logMark()
        let title = "Secret Plan.txt"
        // As the tracking line logs it, and as a value with no privacy given.
        logger.notice("tracking \("TextEdit", privacy: .public) [\(7)] \(title, privacy: .private)")
        logger.info("title \(title)")
        let lines = try logLines(after: mark)
        #expect(lines.contains("tracking TextEdit [7] <private>"))
        #expect(lines.contains("title <private>"))
        #expect(!lines.contains { $0.contains("Secret Plan") })
    }

    @Test("SEC-03 Plain titles in an old layout file are hashed when it's read") func sec03d() throws {
        LayoutStore.titleSecretOverride = nil
        let layout = try #require(try loadLayout("""
            {"cameraX": 0, "cameraY": 0, "windows": [
              {"bundleID": "com.apple.TextEdit", "appName": "TextEdit", "title": "Secret Plan.txt", "x": 100, "y": 100}]}
            """))
        #expect(layout.windows.map(\.title) == [LayoutStore.titleKey("Secret Plan.txt")])
    }

    // MARK: SEC-21

    @Test("SEC-21 A layout file with an absurd view position is ignored") func sec21a() throws {
        func layout(_ x: String, _ y: String) -> String {
            """
            {"cameraX": \(x), "cameraY": \(y), "windows": [
              {"bundleID": "com.example.app", "appName": "Example", "title": "", "x": 100, "y": 100}]}
            """
        }
        #expect(try loadLayout(layout("5000000", "0")) == nil)
        #expect(try loadLayout(layout("0", "-5000000")) == nil)
        #expect(try loadLayout(layout("1000000.5", "0")) == nil)
        #expect(try loadLayout(layout("1e400", "0")) == nil)
        // Far, but within reason.
        #expect(try loadLayout(layout("1000000", "-1000000"))?.windows.count == 1)
    }

    @Test("SEC-21 A snapshot with an absurd view position is ignored too") func sec21b() throws {
        #expect(try loadSnapshot("""
            {"cameraX": 5000000, "cameraY": 0, "windows": [
              {"bundleID": "com.example.app", "appName": "Example", "title": "", "x": 100, "y": 100}]}
            """) == nil)
        #expect(try loadSnapshot("""
            {"cameraX": 500, "cameraY": 0, "windows": [
              {"bundleID": "com.example.app", "appName": "Example", "title": "", "x": 100, "y": 100}]}
            """)?.cameraX == 500)
    }

    // MARK: SEC-22

    @Test("SEC-22 Out-of-range numbers in a layout file are dropped") func sec22a() throws {
        let layout = try #require(try loadLayout("""
            {"cameraX": 120, "cameraY": -40, "centerX": 1e9, "centerY": 400, "fittedWidth": -1, "fittedHeight": 900,
             "windows": [
              {"bundleID": "a", "appName": "A", "title": "", "x": 5000000, "y": 100, "w": 400, "h": 300},
              {"bundleID": "b", "appName": "B", "title": "", "x": 200, "y": 100, "w": -100, "h": 300, "hx": 210, "hy": 110},
              {"bundleID": "c", "appName": "C", "title": "", "x": 300, "y": 100, "w": 400, "h": 300,
               "hx": 2000000, "hy": 100, "pw": 0, "ph": 300, "ox": 10, "oy": 1e7, "ow": 400, "oh": 300},
              {"bundleID": "d", "appName": "D", "title": "", "x": 100, "y": -1000001},
              {"bundleID": "e", "appName": "E", "title": "", "x": -1000000, "y": 1000000, "w": 1000000, "h": 0.5,
               "hx": 1, "hy": 2, "pw": 640, "ph": 480, "ox": 0, "oy": 25, "ow": 800, "oh": 600}]}
            """))
        // The view comes from the camera position: the centre is dropped, as is the fitted size.
        #expect(layout.cameraX == 120 && layout.cameraY == -40)
        #expect(layout.centerX == nil && layout.centerY == nil)
        #expect(layout.fittedWidth == nil && layout.fittedHeight == nil)
        // A (x 5,000,000) and D (y below -1,000,000) are left out.
        #expect(layout.windows.map(\.bundleID) == ["b", "c", "e"])
        let b = layout.windows[0], c = layout.windows[1], e = layout.windows[2]
        // B keeps its spot but not its size.
        #expect(b.x == 200 && b.y == 100 && b.w == nil && b.h == nil && b.hx == 210 && b.hy == 110)
        // C loses its bad home, preferred size and original frame, and keeps the rest.
        #expect(c.w == 400 && c.h == 300)
        #expect(c.hx == nil && c.hy == nil && c.pw == nil && c.ph == nil)
        #expect(c.ox == nil && c.oy == nil && c.ow == nil && c.oh == nil)
        // E is all within range, just.
        #expect(e.x == -1_000_000 && e.y == 1_000_000 && e.w == 1_000_000 && e.h == 0.5)
        #expect(e.hx == 1 && e.hy == 2 && e.pw == 640 && e.ph == 480)
        #expect(e.ox == 0 && e.oy == 25 && e.ow == 800 && e.oh == 600)
    }

    @Test("SEC-22 A number that isn't finite drops its entry, not the layout") func sec22b() throws {
        // JSON has no NaN or infinity; a number too big for a Double is the nearest a file gets.
        let layout = try loadLayout("""
            {"cameraX": 0, "cameraY": 0, "windows": [
              {"bundleID": "a", "appName": "A", "title": "", "x": 1e400, "y": 100},
              {"bundleID": "b", "appName": "B", "title": "", "x": 200, "y": 100}]}
            """)
        withKnownIssue("a number beyond a Double in layout.json fails decoding, so the whole file is ignored") {
            #expect(layout?.windows.map(\.bundleID) == ["b"])
        }
    }

    // MARK: SEC-23

    @Test("SEC-23 Old plaintext titles in a layout file are hashed; hashes are left alone") func sec23a() throws {
        LayoutStore.titleSecretOverride = nil
        let layout = try #require(try loadLayout("""
            {"cameraX": 0, "cameraY": 0, "windows": [
              {"bundleID": "com.apple.TextEdit", "appName": "TextEdit", "title": "Other.txt", "x": 900, "y": 100},
              {"bundleID": "com.apple.TextEdit", "appName": "TextEdit", "title": "Secret plan.txt", "x": 100, "y": 100},
              {"bundleID": "com.apple.TextEdit", "appName": "TextEdit", "title": "sha256:0123456789abcdef01234567", "x": 300, "y": 100},
              {"bundleID": "com.apple.TextEdit", "appName": "TextEdit", "title": "hmac:0123456789abcdef01234567", "x": 500, "y": 100},
              {"bundleID": "com.apple.Notes", "appName": "Notes", "title": "", "x": 700, "y": 100}]}
            """))
        #expect(layout.windows.map(\.title) == [LayoutStore.titleKey("Other.txt"), LayoutStore.titleKey("Secret plan.txt"),
                                                "sha256:0123456789abcdef01234567", "hmac:0123456789abcdef01234567", ""])
        // The entry is still there, and the next save doesn't carry the title on.
        LayoutStore.save(layout)
        let folder = try #require(LayoutStore.folderOverride)
        let text = try String(contentsOf: folder.appendingPathComponent("layout.json"), encoding: .utf8)
        #expect(!text.contains("Secret plan"))
        #expect(try #require(LayoutStore.load()).windows.count == 5)
        // A window whose real title matches the plaintext entry still finds its spot.
        var pool = layout.windows
        #expect(match("Secret plan.txt", in: &pool)?.x == 100)
    }

    @Test("SEC-23 In a release, old plaintext titles become hmac: titles") func sec23b() throws {
        LayoutStore.titleSecretOverride = SymmetricKey(size: .bits256)
        defer { LayoutStore.titleSecretOverride = nil }
        let layout = try #require(try loadLayout("""
            {"cameraX": 0, "cameraY": 0, "windows": [
              {"bundleID": "com.apple.TextEdit", "appName": "TextEdit", "title": "Other.txt", "x": 900, "y": 100},
              {"bundleID": "com.apple.TextEdit", "appName": "TextEdit", "title": "Secret plan.txt", "x": 100, "y": 100}]}
            """))
        #expect(layout.windows.allSatisfy { $0.title.hasPrefix("hmac:") && !$0.title.contains("Secret") })
        var pool = layout.windows
        #expect(match("Secret plan.txt", in: &pool)?.x == 100)
    }

    // MARK: SEC-29

    @Test("SEC-29 A keyed title hash is hmac: and 24 hex digits") func sec29a() {
        let key = SymmetricKey(size: .bits256)
        LayoutStore.titleSecretOverride = key
        defer { LayoutStore.titleSecretOverride = nil }
        let hash = LayoutStore.titleKey("Secret Plan.txt")
        #expect(hash.hasPrefix("hmac:"))
        #expect(hash.count == 5 + 24 && isHex(hash.dropFirst(5)))
        let code = HMAC<SHA256>.authenticationCode(for: Data("Secret Plan.txt".utf8), using: key)
        #expect(hash == "hmac:" + Data(code).prefix(12).map { String(format: "%02x", $0) }.joined())
        #expect(hash != LayoutStore.plainTitleKey("Secret Plan.txt"))
        #expect(LayoutStore.titleKey("Secret Plan.txt") == hash)
        #expect(LayoutStore.titleKey("") == "")
        // Another key (another Mac's Keychain), another hash: the file alone can't confirm a guess.
        LayoutStore.titleSecretOverride = SymmetricKey(size: .bits256)
        #expect(LayoutStore.titleKey("Secret Plan.txt") != hash)
    }

    @Test("SEC-29 A development build hashes titles without a key and makes none") func sec29b() throws {
        // Asking for the Keychain's key in a release would make one: only checked in a development build.
        try #require(!Updater.shared.isRelease)
        LayoutStore.titleSecretOverride = nil
        #expect(LayoutStore.keychainTitleSecret == nil)
        #expect(LayoutStore.titleKey("Secret Plan.txt").hasPrefix("sha256:"))
    }

    // MARK: SEC-30

    @Test("SEC-30 Unkeyed and keyed title hashes both find their own window") func sec30a() {
        LayoutStore.titleSecretOverride = SymmetricKey(size: .bits256)
        defer { LayoutStore.titleSecretOverride = nil }
        let a = "Report A.rtf", b = "Report B.rtf"
        // B's entry first each time, so a match by app alone would swap them.
        let saved: [[SavedLayout.Window]] = [
            [textEdit(LayoutStore.plainTitleKey(b), x: 200), textEdit(LayoutStore.plainTitleKey(a), x: 100)],   // 0.1.32, development builds
            [textEdit(LayoutStore.titleKey(b), x: 200), textEdit(LayoutStore.titleKey(a), x: 100)],             // releases since
            [textEdit(LayoutStore.titleKey(b), x: 200), textEdit(LayoutStore.plainTitleKey(a), x: 100)],
        ]
        for entries in saved {
            #expect(entries.allSatisfy { $0.title.hasPrefix("sha256:") || $0.title.hasPrefix("hmac:") })
            var pool = entries
            #expect(match(a, in: &pool)?.x == 100)
            #expect(match(b, in: &pool)?.x == 200)
        }
    }

    @Test("SEC-30 After the next save their entries carry hmac: titles") func sec30b() throws {
        LayoutStore.titleSecretOverride = SymmetricKey(size: .bits256)
        defer { LayoutStore.titleSecretOverride = nil }
        let a = window(1, "TextEdit", title: "Report A.rtf", at: CGRect(x: 100, y: 100, width: 400, height: 300))
        let b = window(2, "TextEdit", title: "Report B.rtf", at: CGRect(x: 600, y: 100, width: 400, height: 300))
        let c = TestCanvas.make(windows: [a, b])
        defer { c.windows = [] }
        c.hasSynced = true
        c.save()
        let titles = try #require(LayoutStore.load()).windows.map(\.title)
        #expect(titles == [LayoutStore.titleKey("Report A.rtf"), LayoutStore.titleKey("Report B.rtf")])
        #expect(titles.allSatisfy { $0.hasPrefix("hmac:") })
    }
}
