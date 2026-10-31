import Foundation

/// Expanse's log as it's written (`log stream`), kept in memory so a test can wait for a line.
/// Lines are numbered as they arrive: `mark()` before doing something, then look only at what
/// came after.
final class LogTail: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private var process: Process?

    func start() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["stream", "--style", "ndjson", "--level", "info",
                       "--predicate", "subsystem == \"com.invignation.expanse\""]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        var pending = Data()
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            pending.append(chunk)
            while let nl = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<nl]
                pending.removeSubrange(pending.startIndex...nl)
                // The first line is a "Filtering the log data…" header, not JSON.
                guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let message = json["eventMessage"] as? String else { continue }
                self?.append(message)
            }
        }
        try p.run()
        process = p
    }

    func stop() { process?.terminate() }

    private func append(_ line: String) {
        lock.lock(); lines.append(line); lock.unlock()
    }

    /// Where the log is up to now.
    func mark() -> Int {
        lock.lock(); defer { lock.unlock() }
        return lines.count
    }

    /// Every line since `mark`.
    func lines(since mark: Int) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return mark < lines.count ? Array(lines[mark...]) : []
    }

    /// The first line since `mark` that `match` accepts, waiting up to `timeout` for it.
    func wait(since mark: Int, timeout: TimeInterval, _ match: (String) -> Bool) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let line = lines(since: mark).first(where: match) { return line }
            if Date() > deadline || Task.isCancelled { return nil }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Lines since `mark` that start with `prefix`, once they've stopped coming for `quiet` seconds.
    func settled(since mark: Int, prefix: String, quiet: TimeInterval = 0.3, timeout: TimeInterval = 5) async -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var count = -1, steadySince = Date()
        while Date() < deadline && !Task.isCancelled {
            let now = lines(since: mark).filter { $0.hasPrefix(prefix) }
            if now.count != count { count = now.count; steadySince = Date() }
            if count > 0, Date().timeIntervalSince(steadySince) >= quiet { return now }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return lines(since: mark).filter { $0.hasPrefix(prefix) }
    }
}
