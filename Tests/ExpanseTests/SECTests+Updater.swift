import Testing
import Foundation
import Network
@_private(sourceFile: "Updater.swift") @testable import Expanse

/// SEC cases about updates: what's downloaded and what's unpacked. Downloads come from a server
/// on 127.0.0.1 inside the test; nothing reaches the internet, and nothing is installed.
extension SECTests {

    private func releaseJSON(size: Any?, name: String = "Expanse-0.2.0.zip") -> Data {
        var asset: [String: Any] = ["name": name,
                                    "browser_download_url": "https://github.com/invig/expanse/releases/download/v0.2.0/\(name)"]
        if let size { asset["size"] = size }
        let json: [String: Any] = ["tag_name": "v0.2.0", "html_url": "https://github.com/invig/expanse/releases/tag/v0.2.0",
                                   "assets": [["name": "Expanse-0.2.0.dmg", "size": 1000, "browser_download_url": "https://example.com/x"], asset]]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    /// LimitedDownload from `url`: the downloaded file's size (nil if none) and the error, or nil
    /// if it hadn't finished after 20 seconds.
    private func limitedDownload(_ url: URL, limit: Int64) async -> (size: Int?, error: Error?)? {
        let result = Box<(size: Int?, error: Error?)>()
        LimitedDownload.start(url, limit: limit) { file, error in
            // The file is gone once this returns.
            result.set((file.map { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1 }, error))
        }
        guard await wait(upTo: 20, until: { result.value != nil }) else { return nil }
        return result.value
    }

    /// Updater's download of a release from `url`: true if it handed back an app, false if not,
    /// nil if it hadn't finished after 30 seconds.
    private func updateDownload(_ url: URL) async -> Bool? {
        let result = Box<Bool>()
        let release = Updater.Release(version: "9.9.9", zip: url, page: URL(string: "https://example.com/release")!)
        Updater.shared.download(release) { app in result.set(app != nil) }
        guard await wait(upTo: 30, until: { result.value != nil }) else { return nil }
        return result.value
    }

    private func isCancelled(_ error: Error?) -> Bool { (error as? URLError)?.code == .cancelled }

    // MARK: SEC-25

    @Test("SEC-25 An update GitHub lists as too big isn't downloaded") func sec25() {
        #expect(Updater.maxDownload == 64 << 20)
        let ok = Updater.release(from: releaseJSON(size: 3_000_000))
        #expect(ok?.version == "0.2.0")
        #expect(ok?.zip.lastPathComponent == "Expanse-0.2.0.zip")
        #expect(Updater.release(from: releaseJSON(size: 64 << 20)) != nil)
        #expect(Updater.release(from: releaseJSON(size: (64 << 20) + 1)) == nil)
        #expect(Updater.release(from: releaseJSON(size: 1_000_000_000_000)) == nil)
        #expect(Updater.release(from: releaseJSON(size: nil)) == nil)
        #expect(Updater.release(from: releaseJSON(size: "3000000")) == nil)
        #expect(Updater.release(from: releaseJSON(size: 3_000_000, name: "Expanse.zip")) == nil)
    }

    // MARK: SEC-26

    @Test("SEC-26 A download that keeps coming past the limit is stopped") func sec26a() async throws {
        let server = try await LocalServer.start(length: nil, sending: 2_000_000, holdOpen: true)
        defer { server.stop() }
        let result = try #require(await limitedDownload(server.url, limit: 100_000))
        #expect(result.size == nil)
        #expect(isCancelled(result.error))
    }

    @Test("SEC-26 A download announcing more than the limit is stopped") func sec26b() async throws {
        let server = try await LocalServer.start(length: 2_000_000, sending: 20_000, holdOpen: true)
        defer { server.stop() }
        let result = try #require(await limitedDownload(server.url, limit: 100_000))
        #expect(result.size == nil)
        #expect(isCancelled(result.error))
    }

    @Test("SEC-26 A download within the limit comes through") func sec26c() async throws {
        for length in [50_000, nil] {
            let server = try await LocalServer.start(length: length, sending: 50_000, holdOpen: false)
            defer { server.stop() }
            let result = try #require(await limitedDownload(server.url, limit: 100_000))
            #expect(result.size == 50_000)
            #expect(result.error == nil)
        }
    }

    @Test("SEC-26 An update download past 64 MB is stopped and nothing is unpacked") func sec26d() async throws {
        let mark = logMark()
        // Said to be over 64 MB, then more than 64 MB with nothing said.
        for (length, sending) in [((64 << 20) + 1, 100_000), (nil, 80 << 20)] as [(Int?, Int)] {
            let server = try await LocalServer.start(length: length, sending: sending, holdOpen: true)
            defer { server.stop() }
            #expect(await updateDownload(server.url) == false)
        }
        let lines = try logLines(after: mark)
        let stops = lines.filter { $0.hasPrefix("update download stopped at") }
        #expect(stops.count == 2)
        #expect(stops.first?.hasSuffix("bytes (expected 67108865): more than a release") == true)
        let streamed = stops.last.flatMap { Int($0.split(separator: " ")[4]) } ?? 0
        #expect(stops.last?.hasSuffix("bytes (expected -1): more than a release") == true && streamed > 64 << 20)
        #expect(!lines.contains { $0.contains("not unpacked") || $0.contains("checks: signature") })
    }

    // MARK: SEC-27

    @Test("SEC-27 unpackedSize reads what a zip says it unpacks to") func sec27a() throws {
        #expect(Updater.maxUnpacked == 256 << 20)
        #expect(Updater.maxFiles == 10_000)
        let folder = Env.tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        func size(_ name: String, _ data: Data) throws -> (files: Int, bytes: Int)? {
            let file = folder.appendingPathComponent(name)
            try data.write(to: file)
            return Updater.unpackedSize(file)
        }
        let release = try size("release.zip", ZipFixture.release)
        #expect(release?.files == 3 && release?.bytes == ZipFixture.releaseBytes)
        let big = try size("big.zip", ZipFixture.tooBig)
        #expect(big?.files == 1 && big?.bytes == 300_000_000)
        let many = try size("many.zip", ZipFixture.tooMany)
        #expect(many?.files == 10_001 && many?.bytes == 0)
        #expect(try size("garbage.zip", ZipFixture.unreadable) == nil)
        #expect(try size("empty.zip", Data()) == nil)
        #expect(Updater.unpackedSize(folder.appendingPathComponent("missing.zip")) == nil)
    }

    @Test("SEC-27 A zip that would unpack too big, or can't be read, isn't unpacked") func sec27b() async throws {
        let cases: [(Data, String)] = [
            (ZipFixture.tooBig, "unpacked 300000000 bytes in 1 files"),
            (ZipFixture.tooMany, "unpacked 0 bytes in 10001 files"),
            (ZipFixture.unreadable, "unpacked unknown"),
        ]
        let mark = logMark()
        for (zip, _) in cases {
            let server = try await LocalServer.start(body: zip)
            defer { server.stop() }
            #expect(await updateDownload(server.url) == false)
        }
        let lines = try logLines(after: mark)
        for (zip, unpacked) in cases {
            #expect(lines.contains("update 9.9.9 not unpacked: \(zip.count) bytes, \(unpacked)"), "\(unpacked)")
        }
        // ditto never ran: nothing was checked.
        #expect(!lines.contains { $0.contains("checks: signature") })
    }
}

/// A value set once, from any thread.
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    var value: T? { lock.withLock { stored } }
    func set(_ v: T) { lock.withLock { if stored == nil { stored = v } } }
}

/// A web server on 127.0.0.1 that gives every request the same answer: `body`, or `sending`
/// zero bytes, with a Content-Length of `length` (none if nil). With `holdOpen` it then keeps
/// the connection open, so a download only ends if the client gives up.
private final class LocalServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "SECTests.LocalServer")
    private let length: Int?, body: Data?, sending: Int, holdOpen: Bool
    private var connections: [NWConnection] = []
    private(set) var url = URL(string: "http://127.0.0.1/")!

    private init(length: Int?, body: Data?, sending: Int, holdOpen: Bool) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.length = length
        self.body = body
        self.sending = sending
        self.holdOpen = holdOpen
    }

    static func start(length: Int?, sending: Int, holdOpen: Bool) async throws -> LocalServer {
        try await LocalServer(length: length, body: nil, sending: sending, holdOpen: holdOpen).run()
    }

    static func start(body: Data) async throws -> LocalServer {
        try await LocalServer(length: body.count, body: body, sending: 0, holdOpen: false).run()
    }

    private func run() async throws -> LocalServer {
        listener.newConnectionHandler = { c in self.serve(c) }
        listener.start(queue: queue)
        for _ in 0..<500 {
            if let port = listener.port, port.rawValue != 0 {
                url = URL(string: "http://127.0.0.1:\(port.rawValue)/Expanse-9.9.9.zip")!
                return self
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw URLError(.cannotConnectToHost)
    }

    func stop() {
        queue.sync {
            connections.forEach { $0.cancel() }
            connections = []
        }
        listener.cancel()
    }

    private func serve(_ c: NWConnection) {
        connections.append(c)
        c.start(queue: queue)
        // Whatever the request is, the same answer.
        let length = self.length, body = self.body
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
            var head = "HTTP/1.1 200 OK\r\nContent-Type: application/zip\r\nConnection: close\r\n"
            if let length { head += "Content-Length: \(length)\r\n" }
            head += "\r\n"
            c.send(content: Data(head.utf8), completion: .contentProcessed { _ in
                if let body {
                    c.send(content: body, completion: .contentProcessed { _ in self.end(c) })
                } else {
                    self.send(c, from: 0)
                }
            })
        }
    }

    private func send(_ c: NWConnection, from offset: Int) {
        guard offset < sending else { end(c); return }
        let n = min(65_536, sending - offset)
        c.send(content: Data(count: n), completion: .contentProcessed { error in
            // The client hung up: that's the end of it.
            guard error == nil else { c.cancel(); return }
            self.send(c, from: offset + n)
        })
    }

    private func end(_ c: NWConnection) {
        guard !holdOpen else { return }
        c.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in c.cancel() })
    }
}

/// Zips made byte by byte (stored, uncompressed), so their directories can say what they like.
private enum ZipFixture {
    struct Entry {
        var name: String
        var data = Data()
        /// The unpacked size the directory gives, if not the data's.
        var claimed: UInt32?
    }

    static let releaseFiles = [
        Entry(name: "Expanse.app/Contents/Info.plist", data: Data(repeating: 0x41, count: 1200)),
        Entry(name: "Expanse.app/Contents/MacOS/Expanse", data: Data(repeating: 0x42, count: 5000)),
        Entry(name: "Expanse.app/Contents/Resources/AppIcon.icns", data: Data(repeating: 0x43, count: 800)),
    ]
    static let release = make(releaseFiles)
    static let releaseBytes = releaseFiles.reduce(0) { $0 + $1.data.count }
    /// A few bytes that say they unpack to 300 MB.
    static let tooBig = make([Entry(name: "Expanse.app/Contents/MacOS/Expanse", data: Data("tiny".utf8), claimed: 300_000_000)])
    static let tooMany = make((0...10_000).map { Entry(name: "Expanse.app/Contents/Resources/\($0)") })
    static let unreadable = Data("PK\u{3}\u{4} this is not a zip at all".utf8) + Data(repeating: 0x7f, count: 4000)

    static func make(_ entries: [Entry]) -> Data {
        var out = Data(), directory = Data()
        func u16(_ v: Int, _ d: inout Data) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32, _ d: inout Data) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        for e in entries {
            let offset = UInt32(out.count), name = Data(e.name.utf8), crc = crc32(e.data)
            let size = UInt32(e.data.count), unpacked = e.claimed ?? size
            // Local header: version 2.0, no flags, stored, 1 Jan 1980.
            u32(0x0403_4b50, &out); u16(20, &out); u16(0, &out); u16(0, &out); u16(0, &out); u16(0x21, &out)
            u32(crc, &out); u32(size, &out); u32(unpacked, &out); u16(name.count, &out); u16(0, &out)
            out.append(name)
            out.append(e.data)
            // Its directory entry.
            u32(0x0201_4b50, &directory); u16(20, &directory); u16(20, &directory); u16(0, &directory); u16(0, &directory)
            u16(0, &directory); u16(0x21, &directory)
            u32(crc, &directory); u32(size, &directory); u32(unpacked, &directory)
            u16(name.count, &directory); u16(0, &directory); u16(0, &directory); u16(0, &directory); u16(0, &directory)
            u32(0, &directory); u32(offset, &directory)
            directory.append(name)
        }
        let start = UInt32(out.count)
        out.append(directory)
        u32(0x0605_4b50, &out); u16(0, &out); u16(0, &out); u16(entries.count, &out); u16(entries.count, &out)
        u32(UInt32(directory.count), &out); u32(start, &out); u16(0, &out)
        return out
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xffff_ffff
        for byte in data {
            c ^= UInt32(byte)
            for _ in 0..<8 { c = (c >> 1) ^ (0xedb8_8320 & (0 &- (c & 1))) }
        }
        return ~c
    }
}
