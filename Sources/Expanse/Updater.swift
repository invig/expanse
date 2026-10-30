import AppKit
import Security

/// Updates straight from Expanse's GitHub releases, with no other service involved: once a day
/// it asks GitHub which release is the latest, and when that's newer, downloads its zip and
/// offers to install it. It installs only what Apple's code signing says is signed by the same
/// developer as this copy (same Developer ID and app) and notarised, the proof Gatekeeper itself
/// goes by. Release builds only: a development build is signed differently, so never updates.
final class Updater {
    struct Release: Equatable {
        let version: String
        let zip: URL
        let page: URL
    }

    static let shared = Updater()
    /// Called on the main thread when an update has been downloaded and checked.
    var onReady: ((Release) -> Void)?
    /// Downloaded and checked, waiting to be installed.
    private(set) var ready: (release: Release, app: URL)?

    private static let latestURL = URL(string: "https://api.github.com/repos/invig/expanse/releases/latest")!
    private static let automaticKey = "checkForUpdates"
    private var timer: Timer?
    private var checking = false

    /// Checks once a day (and a minute after launch). On unless you turn it off in Settings.
    var automatic: Bool {
        get { UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.automaticKey)
            schedule()
        }
    }

    /// Signed with a Developer ID: a release, which has releases to update to.
    let isRelease: Bool = {
        var me: SecCode?
        var developerID: SecRequirement?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecRequirementCreateWithString("anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]" as CFString,
                                             [], &developerID) == errSecSuccess
        else { return false }
        return SecCodeCheckValidity(me, [], developerID) == errSecSuccess
    }()

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    func start() {
        guard isRelease else { return }
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard isRelease, automatic else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, self.automatic else { return }
            self.check(interactive: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.check(interactive: false)
        }
    }

    /// `interactive`: you asked (Settings), so say if you're up to date or it didn't work.
    /// `install`: install as soon as it's ready, without asking (expanse://update?install=1).
    func check(interactive: Bool, install: Bool = false) {
        guard isRelease else {
            if interactive { Self.tell("Updates come with release builds", "This copy of Expanse is a development build.") }
            return
        }
        guard !checking else { return }
        checking = true
        var request = URLRequest(url: Self.latestURL, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Expanse/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            let release = data.flatMap(Self.release(from:))
            DispatchQueue.main.async {
                guard let release else {
                    self.checking = false
                    logger.info("update check failed: \(error?.localizedDescription ?? "no release found", privacy: .public)")
                    if interactive { Self.tell("Couldn't check for updates", error?.localizedDescription ?? "GitHub didn't say which release is the latest.") }
                    return
                }
                guard Self.isNewer(release.version, than: self.currentVersion) else {
                    self.checking = false
                    logger.info("up to date (\(self.currentVersion, privacy: .public); latest \(release.version, privacy: .public))")
                    if interactive { Self.tell("You're up to date", "Expanse \(self.currentVersion) is the latest version.") }
                    return
                }
                logger.info("update available: \(release.version, privacy: .public)")
                // Already downloaded and waiting (a newer one since means downloading that).
                if let ready = self.ready, ready.release == release {
                    self.checking = false
                    if install { self.install() } else { self.onReady?(release) }
                    return
                }
                self.download(release) { app in
                    self.checking = false
                    guard let app else {
                        if interactive { Self.tell("Couldn't download Expanse \(release.version)", "Try again later, or download it from GitHub.") }
                        return
                    }
                    self.ready = (release, app)
                    if install { self.install() } else { self.onReady?(release) }
                }
            }
        }.resume()
    }

    /// The latest release's version and zip, from GitHub's answer.
    private static func release(from data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]] else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        // Digits and dots only: it's compared, and named in what's downloaded.
        guard !version.isEmpty, version.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        // GitHub gives the asset's real size: one far bigger than a release isn't downloaded at all.
        guard let zip = assets.lazy.compactMap({ asset -> URL? in
            guard let name = asset["name"] as? String, name == "Expanse-\(version).zip",
                  let size = asset["size"] as? Int, size <= maxDownload else { return nil }
            return (asset["browser_download_url"] as? String).flatMap(URL.init(string:))
        }).first else { return nil }
        return Release(version: version, zip: zip, page: page)
    }

    /// "0.1.10" is newer than "0.1.9".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// A release zip is a few MB, about twice that unpacked. Anything far bigger isn't one, and
    /// isn't unpacked: the signature is only checked once it is (see unpackedSize).
    private static let maxDownload = 64 << 20, maxUnpacked = 256 << 20, maxFiles = 10_000

    /// Downloads and unpacks `release`, and hands back the app if it checks out (see verify).
    private func download(_ release: Release, completion: @escaping (URL?) -> Void) {
        LimitedDownload.start(release.zip, limit: Int64(Self.maxDownload)) { file, error in
            var app: URL?
            if let file {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
                let unpacked = size <= Self.maxDownload ? Self.unpackedSize(file) : nil
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Expanse-update-\(UUID().uuidString)")
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-x", "-k", file.path, folder.path]
                if size > Self.maxDownload || unpacked.map({ $0.bytes > Self.maxUnpacked || $0.files > Self.maxFiles }) ?? true {
                    logger.error("update \(release.version, privacy: .public) not unpacked: \(size) bytes, unpacked \(unpacked.map { "\($0.bytes) bytes in \($0.files) files" } ?? "unknown", privacy: .public)")
                } else if (try? unzip.run()) != nil {
                    // A zip can claim one size and unpack to far more: a minute at most.
                    let limit = DispatchWorkItem { if unzip.isRunning { unzip.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: limit)
                    unzip.waitUntilExit()
                    limit.cancel()
                    let candidate = folder.appendingPathComponent("Expanse.app")
                    if unzip.terminationReason == .exit, unzip.terminationStatus == 0,
                       Self.verify(candidate, version: release.version) { app = candidate }
                }
                // Nothing to keep from a download that didn't check out.
                if app == nil { try? FileManager.default.removeItem(at: folder) }
            } else {
                logger.info("update download failed: \(error?.localizedDescription ?? "?", privacy: .public)")
            }
            DispatchQueue.main.async { completion(app) }
        }
    }

    /// What the zip says it unpacks to, from its directory ("19 files, 7379131 bytes uncompressed,
    /// ..."), or nil if it can't be read.
    private static func unpackedSize(_ zip: URL) -> (files: Int, bytes: Int)? {
        let info = Process(), out = Pipe()
        info.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        info.arguments = ["-t", zip.path]
        info.standardOutput = out
        info.standardError = FileHandle.nullDevice
        guard (try? info.run()) != nil else { return nil }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        info.waitUntilExit()
        let parts = text.split(separator: ",").map { $0.split(separator: " ") }
        guard info.terminationStatus == 0, parts.count >= 2,
              parts[0].count >= 2, parts[0][1] == "files" || parts[0][1] == "file", let files = Int(parts[0][0]),
              parts[1].count >= 2, parts[1][1] == "bytes", let bytes = Int(parts[1][0]) else { return nil }
        return (files, bytes)
    }

    /// Signed the way this copy is (same Developer ID and app: its designated requirement), every
    /// part of it intact, notarised by Apple, and the version GitHub said.
    static func verify(_ app: URL, version: String) -> Bool {
        var me: SecCode?, mine: SecStaticCode?, requirement: SecRequirement?, notarised: SecRequirement?, code: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &mine) == errSecSuccess, let mine,
              SecCodeCopyDesignatedRequirement(mine, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCreateWithString("notarized" as CFString, [], &notarised) == errSecSuccess, let notarised,
              SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code
        else { return false }
        let strict = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let signed = SecStaticCodeCheckValidity(code, strict, requirement)
        let notarisedStatus = SecStaticCodeCheckValidity(code, strict, notarised)
        let bundled = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        logger.info("update \(version, privacy: .public) checks: signature \(signed), notarisation \(notarisedStatus), version \(bundled ?? "?", privacy: .public)")
        return signed == errSecSuccess && notarisedStatus == errSecSuccess && bundled == version
    }

    /// Swaps the downloaded copy in for this one and relaunches. Where this copy can't be
    /// replaced (a folder you can't write to, or run straight from a download), opens the
    /// release on GitHub instead.
    func install() {
        guard let ready else { return }
        let current = Bundle.main.bundleURL
        let folder = current.deletingLastPathComponent()
        guard !current.path.contains("/AppTranslocation/"), FileManager.default.isWritableFile(atPath: folder.path) else {
            NSWorkspace.shared.open(ready.release.page)
            return
        }
        let staged = folder.appendingPathComponent(".Expanse-update.app")
        do {
            try? FileManager.default.removeItem(at: staged)
            try FileManager.default.moveItem(at: ready.app, to: staged)
            try? FileManager.default.removeItem(at: ready.app.deletingLastPathComponent())   // the download's folder
            _ = try FileManager.default.replaceItemAt(current, withItemAt: staged)
            logger.info("installed \(ready.release.version, privacy: .public); relaunching")
            Self.relaunch()
        } catch {
            logger.error("update install failed: \(error.localizedDescription, privacy: .public)")
            // The download may already have been moved (and its folder removed): start over at
            // the next check rather than offering a copy that's gone.
            try? FileManager.default.removeItem(at: staged)
            try? FileManager.default.removeItem(at: ready.app.deletingLastPathComponent())
            self.ready = nil
            Self.tell("Couldn't install Expanse \(ready.release.version)", error.localizedDescription)
            NSWorkspace.shared.open(ready.release.page)
        }
    }

    /// Quits (putting windows back) and opens this app again once it's gone: a second copy quits
    /// on launch while the first is still running.
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                          Bundle.main.bundlePath, String(getpid())]
        try? task.run()
        NSApp.terminate(nil)
    }

    private static func tell(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}

/// A download that stops once more than `limit` bytes have come, or are said to be coming.
/// GitHub's size for the asset is checked first (see Updater.release(from:)); this counts what
/// actually arrives.
final class LimitedDownload: NSObject, URLSessionDownloadDelegate {
    private let limit: Int64
    /// The file (gone once this returns), or nil and why.
    private let done: (URL?, Error?) -> Void
    private var finished = false, stopped = false

    private init(limit: Int64, done: @escaping (URL?, Error?) -> Void) {
        self.limit = limit
        self.done = done
    }

    static func start(_ url: URL, limit: Int64, done: @escaping (URL?, Error?) -> Void) {
        // The session holds on to its delegate until it's invalidated, when the download ends.
        let session = URLSession(configuration: .ephemeral, delegate: LimitedDownload(limit: limit, done: done), delegateQueue: nil)
        session.downloadTask(with: url).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard !stopped, totalBytesWritten > limit || totalBytesExpectedToWrite > limit else { return }
        stopped = true
        logger.error("update download stopped at \(totalBytesWritten) bytes (expected \(totalBytesExpectedToWrite)): more than a release")
        downloadTask.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        finished = true
        done(location, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if !finished {
            finished = true
            done(nil, error)
        }
        session.finishTasksAndInvalidate()
    }
}
