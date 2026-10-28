import AppKit
import OSLog

/// Menu bar icon › Troubleshooting › Copy Logs for a Bug Report: what's needed to look into a
/// problem, on the clipboard, ready to paste into a GitHub issue. This Mac and its settings, then
/// the log: the Detailed Logging file, or without it, what the system log kept of this run.
enum BugReport {
    static let issuesURL = URL(string: "https://github.com/invig/expanse/issues/new")!
    /// GitHub takes 65,536 characters in an issue; this leaves room for the summary and your words.
    private static let maxLogCharacters = 45_000

    /// `settings`: Expanse's own state, one line each. Copies off the main thread (reading the
    /// system log can take a moment), then says so.
    static func copy(settings: [String]) {
        let summary = self.summary(settings: settings)
        Toast.show("Collecting logs…")
        DispatchQueue.global(qos: .userInitiated).async {
            // The file only while it's being written: with logging off, it's from some other time.
            let file = LogFile.shared.isEnabled ? LogFile.shared.recent(maxCharacters: maxLogCharacters) : ""
            let log = file.isEmpty ? systemLog(maxCharacters: maxLogCharacters) : file
            let source = file.isEmpty
                ? "System log for this run (Detailed Logging is off: turn it on for more)"
                : "Detailed log"
            let report = """
            ### Expanse
            \(summary)

            <details><summary>\(source)</summary>

            ```
            \(log.isEmpty ? "(nothing logged)" : log)
            ```

            </details>
            """
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
                Toast.show(file.isEmpty ? "Copied. For more, turn on Detailed Logging and try again."
                                        : "Logs copied: paste them into a GitHub issue")
            }
        }
    }

    private static func summary(settings: [String]) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        var model = [CChar](repeating: 0, count: 64)
        var size = model.count
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let displays = NSScreen.screens.map { s in
            let f = s.frame, usable = s.visibleFrame
            return "\(Int(f.width))×\(Int(f.height)) @\(Int(s.backingScaleFactor))x (usable \(Int(usable.width))×\(Int(usable.height)))"
        }
        let lines = [
            "Expanse \(version) (\(build)), \(Updater.shared.isRelease ? "release" : "development") build",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(String(cString: model))",
            "Displays: \(displays.isEmpty ? "none" : displays.joined(separator: "; "))",
            "Accessibility: \(AX.isTrusted(prompt: false) ? "granted" : "not granted"), Screen Recording: \(CGPreflightScreenCaptureAccess() ? "granted" : "not granted")",
        ] + settings
        return lines.map { "- \($0)" }.joined(separator: "\n")
    }

    /// Expanse's lines in the system log since it started, at most `maxCharacters` of the newest.
    private static func systemLog(maxCharacters: Int) -> String {
        // From when Expanse started: the store reaches further back than this run.
        let started = NSRunningApplication.current.launchDate ?? Date().addingTimeInterval(-24 * 3600)
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(at: store.position(date: started),
                                                  matching: NSPredicate(format: "subsystem == %@", "com.invignation.expanse"))
        else { return "" }
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        var lines: [String] = []
        for case let entry as OSLogEntryLog in entries {
            let level: String
            switch entry.level {
            case .error, .fault: level = "error"
            case .notice: level = "notice"
            default: level = "info"
            }
            lines.append("\(time.string(from: entry.date)) [\(level)] \(entry.composedMessage)")
        }
        var text = ""
        for line in lines.reversed() {
            guard text.count + line.count + 1 <= maxCharacters else { break }
            text = line + "\n" + text
        }
        return text
    }
}
