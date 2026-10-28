import Foundation
import os

/// Expanse's log. Every line goes to the system log (Console, `log show`); with Detailed Logging on
/// (menu bar icon › Troubleshooting), it's also written to a file you can attach to a bug report
/// (see LogFile). Values marked private, like window titles, are left out of both.
let logger = ExpanseLog(subsystem: "com.invignation.expanse", category: "canvas")

struct ExpanseLog: Sendable {
    private let system: Logger

    init(subsystem: String, category: String) {
        system = Logger(subsystem: subsystem, category: category)
    }

    func info(_ message: LogMessage) {
        system.info("\(message.text, privacy: .public)")
        LogFile.shared.write("info", message.text)
    }

    /// Kept on disk by the system log, unlike info: for what's worth explaining afterwards.
    func notice(_ message: LogMessage) {
        system.notice("\(message.text, privacy: .public)")
        LogFile.shared.write("notice", message.text)
    }

    func error(_ message: LogMessage) {
        system.error("\(message.text, privacy: .public)")
        LogFile.shared.write("error", message.text)
    }
}

/// A log line, written like a system log message: `"moved \(name, privacy: .public)"`. Values are
/// private unless marked public, as in the system log, except numbers and true/false.
struct LogMessage: ExpressibleByStringInterpolation {
    enum Privacy { case `public`, `private` }

    struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var text = ""

        init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        mutating func appendLiteral(_ literal: String) { text += literal }

        mutating func appendInterpolation<T>(_ value: T, privacy: Privacy? = nil) {
            switch privacy ?? (value is any Numeric || value is Bool ? .public : .private) {
            case .public: text += "\(value)"
            case .private: text += "<private>"
            }
        }
    }

    let text: String

    init(stringLiteral value: String) { text = value }
    init(stringInterpolation: StringInterpolation) { text = stringInterpolation.text }
}

/// Detailed Logging: every log line also goes to ~/Library/Logs/Expanse/Expanse.log, for a bug
/// report. Off unless you turn it on; the file is capped, the older half kept as Expanse.1.log.
final class LogFile: @unchecked Sendable {
    static let shared = LogFile()
    static let enabledKey = "detailedLogging"
    private static let maxBytes: UInt64 = 5_000_000

    let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Expanse", isDirectory: true)
    var url: URL { folder.appendingPathComponent("Expanse.log") }
    private var previousURL: URL { folder.appendingPathComponent("Expanse.1.log") }

    /// Read on every log line, from any thread: a lock rather than the queue, so a line logged
    /// while it's off costs next to nothing.
    private let on = OSAllocatedUnfairLock(initialState: UserDefaults.standard.bool(forKey: LogFile.enabledKey))
    private let queue = DispatchQueue(label: "com.invignation.expanse.logfile", qos: .utility)
    private var handle: FileHandle?
    private let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    var isEnabled: Bool {
        get { on.withLock { $0 } }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            on.withLock { $0 = newValue }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            write("notice", newValue ? "detailed logging on (Expanse \(version))" : "detailed logging off", force: true)
            if !newValue { queue.async { try? self.handle?.close(); self.handle = nil } }
        }
    }

    func write(_ level: String, _ text: String, force: Bool = false) {
        guard force || on.withLock({ $0 }) else { return }
        let now = Date()
        queue.async {
            let line = "\(self.time.string(from: now)) [\(level)] \(text)\n"
            guard let handle = self.openHandle() else { return }
            try? handle.write(contentsOf: Data(line.utf8))
            if (try? handle.offset()) ?? 0 > Self.maxBytes { self.rotate() }
        }
    }

    /// The end of the log (this file, and the one before it if that's not enough), at most
    /// `maxCharacters` long, starting at a whole line. Empty when there's none.
    func recent(maxCharacters: Int) -> String {
        queue.sync {
            try? handle?.synchronize()
            var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if text.count < maxCharacters, let older = try? String(contentsOf: previousURL, encoding: .utf8) {
                text = older + text
            }
            guard text.count > maxCharacters else { return text }
            let tail = text.suffix(maxCharacters)
            return String(tail.drop { $0 != "\n" }.dropFirst())
        }
    }

    private func openHandle() -> FileHandle? {
        if let handle { return handle }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        return handle
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: previousURL)
        try? FileManager.default.moveItem(at: url, to: previousURL)
    }
}
