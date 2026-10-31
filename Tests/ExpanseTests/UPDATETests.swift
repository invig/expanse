import Testing
import AppKit
@_private(sourceFile: "AppDelegate.swift") @testable import Expanse
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "Updater.swift") @testable import Expanse

/// docs/regression/updates-and-install.md. Nothing here reaches the network, GitHub, notarisation
/// or the Homebrew tap: releases are fixtures in temporary folders, the scripts run on a copy of
/// the repo with stand-ins for swift, codesign, gh and the rest, and nothing installs or relaunches.
@MainActor @Suite("UPDATE: Updates, release builds and install", .serialized) struct UPDATETests {

    // MARK: Helpers

    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func release(_ version: String = "9.9.9", zip: URL = URL(string: "https://example.com/Expanse-9.9.9.zip")!) -> Updater.Release {
        Updater.Release(version: version, zip: zip, page: URL(string: "https://example.com/releases/v\(version)")!)
    }

    /// What Updater says and opens, noted instead of shown (put back afterwards).
    final class Noted {
        var told: [(title: String, text: String)] = []
        var opened: [URL] = []
    }

    static func noting<T>(_ body: (Noted) throws -> T) rethrows -> T {
        let noted = Noted()
        let tell = Updater.tell, openPage = Updater.openPage
        Updater.tell = { noted.told.append(($0, $1)) }
        Updater.openPage = { noted.opened.append($0) }
        defer { Updater.tell = tell; Updater.openPage = openPage }
        return try body(noted)
    }

    @discardableResult
    static func shell(_ command: String, _ args: [String], in dir: URL? = nil, env: [String: String]? = nil) -> (status: Int32, output: String) {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: command)
        p.arguments = args
        if let dir { p.currentDirectoryURL = dir }
        if let env { p.environment = env }
        p.standardOutput = out
        p.standardError = out
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return (-1, "couldn't run \(command)") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// A minimal Expanse.app at `version`: Info.plist, an executable (a copy of /usr/bin/true), and
    /// `extra` files, signed ad hoc (no identity, no Keychain).
    static func fixtureApp(in dir: URL, version: String, extra: [String] = []) -> URL {
        let app = dir.appendingPathComponent("Expanse.app")
        let contents = app.appendingPathComponent("Contents")
        let fm = FileManager.default
        try? fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try? fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: contents.appendingPathComponent("MacOS/Expanse"))
        let info: [String: Any] = ["CFBundleExecutable": "Expanse", "CFBundleIdentifier": "com.invignation.expanse",
                                   "CFBundleName": "Expanse", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version]
        (info as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        for name in extra { fm.createFile(atPath: contents.appendingPathComponent("Resources/\(name)").path, contents: Data("x".utf8)) }
        shell("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        return app
    }

    /// A copy of what the scripts use (scripts/, Resources/), so nothing builds into the real build/.
    static func scratchRepo() -> URL {
        let root = Env.tempFolder()
        let fm = FileManager.default
        for dir in ["scripts", "Resources"] {
            try? fm.copyItem(at: repo.appendingPathComponent(dir), to: root.appendingPathComponent(dir))
        }
        return root
    }

    /// Stand-ins for the tools the scripts call, first on PATH. Each notes its arguments in
    /// $STUB_LOG ("---", the tool, then one argument a line).
    static func stubs(_ tools: [String: String]) -> URL {
        let dir = Env.tempFolder()
        for (name, body) in tools {
            let file = dir.appendingPathComponent(name)
            let script = "#!/bin/bash\nprintf '%s\\n' --- \(name) \"$@\" >> \"$STUB_LOG\"\n\(body)\n"
            FileManager.default.createFile(atPath: file.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755])
        }
        return dir
    }

    /// The calls a stand-in noted, each as its arguments.
    static func calls(_ log: URL, _ tool: String) -> [[String]] {
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return text.components(separatedBy: "---\n").dropFirst().compactMap { call in
            let lines = call.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLast()
            guard lines.first == tool else { return nil }
            return Array(lines.dropFirst())
        }
    }

    static func environment(stubs: URL, log: URL, _ extra: [String: String] = [:]) -> [String: String] {
        ["PATH": "\(stubs.path):/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "STUB_LOG": log.path,
         "TMPDIR": FileManager.default.temporaryDirectory.path].merging(extra) { $1 }
    }

    /// `swift build`: makes the binary (a copy of /usr/bin/true) where --show-bin-path says it is.
    static let swiftStub = """
        bin="$STUB_BIN"
        if [[ " $* " == *" --show-bin-path "* ]]; then echo "$bin"; exit 0; fi
        mkdir -p "$bin" && cp /usr/bin/true "$bin/Expanse"
        """

    static func shasum(_ file: URL) -> String {
        shell("/usr/bin/shasum", ["-a", "256", file.path]).output.split(separator: " ").first.map(String.init) ?? ""
    }

    static func cask(version: String?, sha256: String) -> String {
        """
        cask "expanse" do
        \(version.map { "  version \"\($0)\"\n" } ?? "")  sha256 "\(sha256)"

          url "https://github.com/invig/expanse/releases/download/v#{version}/Expanse-#{version}.zip"
          name "Expanse"
          app "Expanse.app"
        end
        """
    }

    /// `gh`: GitHub's answers for update-cask.sh (the cask in $CASK_FIXTURE) and release.sh.
    static let ghStub = """
        if [[ "$1" == release ]]; then cat > /dev/null; echo "https://github.com/invig/expanse/releases/tag/test"; exit 0; fi
        if [[ "$*" == *"-X PUT"* ]]; then echo "https://github.com/invig/homebrew-tap/commit/test"; exit 0; fi
        if [[ "$*" == *"--jq .sha"* ]]; then echo "blob123"; exit 0; fi
        if [[ "$*" == *"application/vnd.github.raw"* ]]; then cat "$CASK_FIXTURE"; exit 0; fi
        exit 1
        """

    /// update-cask.sh against a cask fixture, with gh stubbed.
    static func updateCask(cask: String, version: String, zip: URL, branch: String? = nil) -> (status: Int32, output: String, gh: [[String]]) {
        let root = scratchRepo(), log = root.appendingPathComponent("stub.log")
        let fixture = root.appendingPathComponent("expanse.rb")
        try? cask.write(to: fixture, atomically: true, encoding: .utf8)
        let bin = stubs(["gh": ghStub])
        var extra = ["CASK_FIXTURE": fixture.path]
        if let branch { extra["CASK_BRANCH"] = branch }
        let r = shell("/bin/bash", [root.appendingPathComponent("scripts/update-cask.sh").path, version, zip.path], in: root,
                      env: environment(stubs: bin, log: log, extra))
        return (r.status, r.output, calls(log, "gh"))
    }

    // MARK: UPDATE-01

    @Test("UPDATE-01 build.sh without a signing certificate signs ad hoc") func update01a() {
        let root = Self.scratchRepo(), log = root.appendingPathComponent("stub.log")
        // No identities in the keychain (security is a stand-in: the Keychain isn't asked).
        let bin = Self.stubs(["security": "echo '     0 valid identities found'", "swift": Self.swiftStub])
        let env = Self.environment(stubs: bin, log: log, ["STUB_BIN": root.appendingPathComponent(".build/release").path])
        let r = Self.shell("/bin/bash", [root.appendingPathComponent("scripts/build.sh").path], in: root, env: env)
        #expect(r.status == 0, "\(r.output)")
        #expect(r.output.contains("signed with: -"))
        let app = root.appendingPathComponent("build/Expanse.app")
        let info = Self.shell("/usr/bin/codesign", ["-dv", app.path])
        #expect(info.output.contains("Signature=adhoc"), "\(info.output)")
        #expect(Self.shell("/usr/bin/codesign", ["--verify", app.path]).status == 0)
    }

    @Test("UPDATE-01 build.sh signs with an Apple Development certificate when there is one") func update01b() {
        let root = Self.scratchRepo(), log = root.appendingPathComponent("stub.log")
        let bin = Self.stubs([
            "security": "echo '  1) 0123456789ABCDEF \"Apple Development: Test Person (TEAM123456)\"'; echo '     1 valid identities found'",
            "swift": Self.swiftStub,
            "codesign": "exit 0",
        ])
        let env = Self.environment(stubs: bin, log: log, ["STUB_BIN": root.appendingPathComponent(".build/release").path])
        let r = Self.shell("/bin/bash", [root.appendingPathComponent("scripts/build.sh").path], in: root, env: env)
        #expect(r.status == 0, "\(r.output)")
        #expect(r.output.contains("signed with: Apple Development"))
        let signing = Self.calls(log, "codesign")
        #expect(signing.count == 1)
        if let args = signing.first, let i = args.firstIndex(of: "--sign") {
            #expect(args[i + 1] == "Apple Development")
        } else {
            Issue.record("codesign wasn't asked to sign: \(signing)")
        }
    }

    // MARK: UPDATE-02

    @Test("UPDATE-02 release.sh builds for both architectures and signs with a Developer ID and the hardened runtime") func update02a() {
        let root = Self.scratchRepo(), log = root.appendingPathComponent("stub.log")
        let bin = Self.stubs([
            "swift": Self.swiftStub,
            "lipo": "echo \"Architectures in the fat file: $2 are: x86_64 arm64\"",
            "codesign": "exit 0",
        ])
        let env = Self.environment(stubs: bin, log: log, ["STUB_BIN": root.appendingPathComponent(".build/release").path, "DRY_RUN": "1"])
        let r = Self.shell("/bin/bash", [root.appendingPathComponent("scripts/release.sh").path], in: root, env: env)
        #expect(r.status == 0, "\(r.output)")
        #expect(r.output.contains("Dry run"))
        let builds = Self.calls(log, "swift").filter { !$0.contains("--show-bin-path") }
        #expect(!builds.isEmpty)
        for args in builds {
            #expect(args.joined(separator: " ").contains("--arch arm64 --arch x86_64"), "\(args)")
            #expect(args.joined(separator: " ").contains("-c release"), "\(args)")
        }
        let signing = Self.calls(log, "codesign").filter { $0.contains("--sign") }
        #expect(signing.count == 1)
        if let args = signing.first, let i = args.firstIndex(of: "--sign") {
            #expect(args[i + 1] == "Developer ID Application")
            #expect(args.joined(separator: " ").contains("--options runtime"))
            #expect(args.contains("--timestamp"))
        }
    }

    /// Tests/scripts/UPDATE-02-release-check.sh against what each tool would say about a release.
    static func releaseCheck(archs: String = "x86_64 arm64",
                             codesign: String = "Authority=Developer ID Application: Test Developer (TEAM123456)\\nCodeDirectory v=20500 size=1234 flags=0x10000(runtime) hashes=30+7 location=embedded",
                             spctl: String = "accepted\\nsource=Notarized Developer ID", stapler: Int32 = 0) -> (status: Int32, output: String) {
        let dir = Env.tempFolder(), log = dir.appendingPathComponent("stub.log")
        let bin = stubs([
            "lipo": "echo '\(archs)'",
            "codesign": "printf 'Executable=%s\\n\(codesign)\\n' \"$3\" >&2",
            "spctl": "printf '%s: \(spctl)\\n' \"$3\" >&2",
            "xcrun": stapler == 0 ? "echo 'The validate action worked!'" : "echo 'does not have a ticket stapled to it.'; exit \(stapler)",
        ])
        let app = dir.appendingPathComponent("Expanse.app")
        return shell("/bin/bash", [repo.appendingPathComponent("Tests/scripts/UPDATE-02-release-check.sh").path, app.path],
                     env: environment(stubs: bin, log: log))
    }

    @Test("UPDATE-02 The release check accepts a universal, Developer ID, hardened, notarised and stapled app") func update02b() {
        let ok = Self.releaseCheck()
        #expect(ok.status == 0, "\(ok.output)")
    }

    @Test("UPDATE-02 The release check fails a single-architecture, ad hoc, unhardened, rejected or unstapled app") func update02c() {
        #expect(Self.releaseCheck(archs: "arm64").status != 0)
        #expect(Self.releaseCheck(codesign: "Signature=adhoc\\nCodeDirectory v=20400 size=1234 flags=0x2(adhoc) hashes=30+7").status != 0)
        #expect(Self.releaseCheck(codesign: "Authority=Developer ID Application: X (T)\\nCodeDirectory v=20500 size=1 flags=0x0(none) hashes=1").status != 0)
        #expect(Self.releaseCheck(spctl: "rejected\\nsource=Unnotarized Developer ID").status != 0)
        #expect(Self.releaseCheck(stapler: 65).status != 0)
    }

    // MARK: UPDATE-07, UPDATE-08

    /// An AppDelegate that was never launched, whose update question is answered "Later".
    static func askingApp(_ body: (AppDelegate, _ asked: () -> [String]) throws -> Void) rethrows {
        Env.isolate()
        let app = AppDelegate()
        var asked: [String] = []
        let ask = AppDelegate.askToInstall
        AppDelegate.askToInstall = { asked.append($0.version); return .alertSecondButtonReturn }
        defer { AppDelegate.askToInstall = ask }
        try Env.withDefaults(["updatePromptedFor": nil]) { try body(app, { asked }) }
    }

    @Test("UPDATE-07 Asked once per version; Check Now asks again") func update07() {
        Self.askingApp { app, asked in
            app.updateReady(Self.release("0.2.0"))
            #expect(asked() == ["0.2.0"])
            #expect(UserDefaults.standard.string(forKey: "updatePromptedFor") == "0.2.0")
            // Later, then Expanse reopened: not asked again for that version.
            let reopened = AppDelegate()
            reopened.updateReady(Self.release("0.2.0"))
            #expect(asked() == ["0.2.0"])
            // Check Now (checkForUpdates, without its check): asked again, once.
            reopened.askedToCheck = true
            reopened.updateReady(Self.release("0.2.0"))
            #expect(asked() == ["0.2.0", "0.2.0"])
            #expect(!reopened.askedToCheck)
            reopened.updateReady(Self.release("0.2.0"))
            #expect(asked().count == 2)
            // A newer version is asked about.
            reopened.updateReady(Self.release("0.2.1"))
            #expect(asked() == ["0.2.0", "0.2.0", "0.2.1"])
        }
    }

    @Test("UPDATE-08 The update question waits while zoomed out (logic)") func update08() {
        Self.askingApp { app, asked in
            app.controller.isActive = true
            defer { app.controller.isActive = false }
            app.updateReady(Self.release("0.2.0"))
            // Not asked, and not counted as asked (it's asked again 30s on).
            #expect(asked().isEmpty)
            #expect(UserDefaults.standard.string(forKey: "updatePromptedFor") == nil)
            app.controller.isActive = false
            app.updateReady(Self.release("0.2.0"))
            #expect(asked() == ["0.2.0"])
        }
    }

    // MARK: UPDATE-10

    @Test("UPDATE-10 Development builds never check for updates") func update10() {
        // This test host isn't signed with a Developer ID: a development build, like Expanse's own.
        #expect(!Updater.shared.isRelease)
        let u = Updater()
        #expect(!u.isRelease)
        u.start()
        #expect(u.timer == nil)
        Self.noting { noted in
            u.check(interactive: false)
            #expect(!u.checking)
            #expect(noted.told.isEmpty)
            // Asked from Settings: it says why, without asking GitHub.
            u.check(interactive: true)
            #expect(!u.checking)
            #expect(noted.told.map(\.title) == ["Updates come with release builds"])
        }
        #expect(u.ready == nil)
    }

    // MARK: UPDATE-11

    @Test("UPDATE-11 Where it can't replace itself, installing opens the release page instead", arguments: ["translocated", "read-only"])
    func update11(_ where_: String) throws {
        let dir = Env.tempFolder()
        let download = dir.appendingPathComponent("download")
        let downloaded = Self.fixtureApp(in: download, version: "9.9.9")
        let folder = where_ == "translocated" ? dir.appendingPathComponent("AppTranslocation/ABC/d") : dir.appendingPathComponent("ReadOnly")
        let current = Self.fixtureApp(in: folder, version: "0.1.34")
        if where_ == "read-only" { try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path) }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let u = Updater(isRelease: false)
        u.ready = (Self.release("9.9.9"), downloaded)
        Self.noting { noted in
            u.install(replacing: current)
            #expect(noted.opened == [Self.release("9.9.9").page])
            #expect(noted.told.isEmpty)
        }
        // Nothing moved: this copy is as it was, and the download is still on offer.
        #expect(Bundle(url: current)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "0.1.34")
        #expect(FileManager.default.fileExists(atPath: downloaded.path))
        #expect(u.ready?.app == downloaded)
    }

    // MARK: UPDATE-12

    @Test("UPDATE-12 Updater.verify refuses an ad-hoc-signed copy and the wrong version") func update12() {
        let app = Self.fixtureApp(in: Env.tempFolder(), version: "9.9.9")
        #expect(!Updater.verify(app, version: "9.9.9"))
        #expect(!Updater.verify(app, version: "9.9.8"))
        #expect(!Updater.verify(app.deletingLastPathComponent().appendingPathComponent("Missing.app"), version: "9.9.9"))
        // The genuine copy passing needs a release-signed test host (it's compared with the running
        // copy's designated requirement): checked by hand.
    }

    // MARK: UPDATE-13

    static func json(tag: String = "v0.1.34", assets: [[String: Any]]? = nil) -> Data {
        let assets = assets ?? [["name": "Expanse-0.1.34.zip", "size": 3_500_000,
                                 "browser_download_url": "https://github.com/invig/expanse/releases/download/v0.1.34/Expanse-0.1.34.zip"]]
        return try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": "https://github.com/invig/expanse/releases/tag/\(tag)",
                                                            "assets": assets])
    }

    @Test("UPDATE-13 Version comparison") func update13a() {
        #expect(Updater.isNewer("0.1.10", than: "0.1.9"))
        #expect(!Updater.isNewer("0.1.9", than: "0.1.10"))
        #expect(!Updater.isNewer("0.1.34", than: "0.1.34"))
        #expect(!Updater.isNewer("1.0", than: "1.0.0"))
        #expect(!Updater.isNewer("1.0.0", than: "1.0"))
        #expect(Updater.isNewer("0.2", than: "0.1.34"))
    }

    @Test("UPDATE-13 Reading GitHub's latest release") func update13b() throws {
        let r = try #require(Updater.release(from: Self.json()))
        #expect(r.version == "0.1.34")
        #expect(r.zip.absoluteString == "https://github.com/invig/expanse/releases/download/v0.1.34/Expanse-0.1.34.zip")
        #expect(r.page.absoluteString == "https://github.com/invig/expanse/releases/tag/v0.1.34")
        #expect(Updater.release(from: Self.json(tag: "0.1.34"))?.version == "0.1.34")
        // Letters in the tag: no release.
        #expect(Updater.release(from: Self.json(tag: "0.1.34-beta")) == nil)
        #expect(Updater.release(from: Self.json(tag: "v")) == nil)
        // Only the asset named Expanse-<version>.zip.
        let other: [[String: Any]] = [["name": "Expanse.zip", "size": 1000, "browser_download_url": "https://example.com/Expanse.zip"],
                                      ["name": "Expanse-0.1.33.zip", "size": 1000, "browser_download_url": "https://example.com/old.zip"]]
        #expect(Updater.release(from: Self.json(assets: other)) == nil)
        #expect(Updater.release(from: Self.json(assets: [])) == nil)
        // Since 47ed782: not one bigger than the download limit.
        let huge: [[String: Any]] = [["name": "Expanse-0.1.34.zip", "size": Updater.maxDownload + 1,
                                      "browser_download_url": "https://example.com/Expanse-0.1.34.zip"]]
        #expect(Updater.release(from: Self.json(assets: huge)) == nil)
        #expect(Updater.release(from: Data("not json".utf8)) == nil)
    }

    // MARK: UPDATE-14

    @Test("UPDATE-14 Automatic checks are on unless turned off, and off means none is scheduled") func update14() {
        Env.withDefaults(["checkForUpdates": nil]) {
            let dev = Updater()
            #expect(dev.automatic)
            // One that takes itself for a release; it's never left able to check (see the end).
            let u = Updater(isRelease: true)
            defer {
                u.checking = true
                u.timer?.invalidate()
            }
            u.start()
            #expect(u.timer != nil)
            u.automatic = false
            #expect(UserDefaults.standard.object(forKey: "checkForUpdates") as? Bool == false)
            #expect(!dev.automatic)
            #expect(u.timer == nil)
            u.start()
            #expect(u.timer == nil)
            u.automatic = true
            #expect(u.timer != nil)
            u.timer?.invalidate()
        }
    }

    // MARK: UPDATE-15

    /// A release to install: the download (in a folder of its own, as Updater.download leaves it)
    /// and this copy, in a folder Expanse can write to.
    static func installSetup() -> (u: Updater, current: URL, downloaded: URL, apps: URL) {
        let dir = Env.tempFolder()
        let downloaded = fixtureApp(in: dir.appendingPathComponent("Expanse-update-test"), version: "9.9.9")
        let apps = dir.appendingPathComponent("Applications")
        let current = fixtureApp(in: apps, version: "0.1.34")
        let u = Updater(isRelease: false)
        u.ready = (release("9.9.9"), downloaded)
        return (u, current, downloaded, apps)
    }

    @Test("UPDATE-15 A failed install (the download gone) cleans up and is offered again") func update15a() {
        let (u, current, downloaded, apps) = Self.installSetup()
        try? FileManager.default.removeItem(at: downloaded)
        Self.noting { noted in
            u.install(replacing: current)
            #expect(noted.told.map(\.title) == ["Couldn't install Expanse 9.9.9"])
            #expect(noted.opened == [Self.release("9.9.9").page])
        }
        #expect(u.ready == nil)
        #expect(!FileManager.default.fileExists(atPath: downloaded.deletingLastPathComponent().path))
        #expect(!FileManager.default.fileExists(atPath: apps.appendingPathComponent(".Expanse-update.app").path))
        #expect(Bundle(url: current)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "0.1.34")
    }

    @Test("UPDATE-15 A failed swap (this copy locked) removes the staged copy and the download") func update15b() throws {
        let (u, current, downloaded, apps) = Self.installSetup()
        // Locked, as with chflags uchg: the swap fails.
        #expect(chflags(current.path, UInt32(UF_IMMUTABLE)) == 0)
        defer { chflags(current.path, 0) }
        // Only if a locked copy really can't be replaced here: otherwise install would relaunch.
        let probe = Env.tempFolder()
        let locked = probe.appendingPathComponent("Locked.app"), other = probe.appendingPathComponent("Other.app")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        chflags(locked.path, UInt32(UF_IMMUTABLE))
        defer { chflags(locked.path, 0) }
        try #require((try? FileManager.default.replaceItemAt(locked, withItemAt: other)) == nil, "a locked copy can be replaced here")

        Self.noting { noted in
            u.install(replacing: current)
            #expect(noted.told.map(\.title) == ["Couldn't install Expanse 9.9.9"])
            #expect(noted.opened == [Self.release("9.9.9").page])
        }
        #expect(u.ready == nil)
        #expect(!FileManager.default.fileExists(atPath: apps.appendingPathComponent(".Expanse-update.app").path))
        #expect(!FileManager.default.fileExists(atPath: downloaded.deletingLastPathComponent().path))
        #expect(Bundle(url: current)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "0.1.34")
    }

    // MARK: UPDATE-16

    @Test("UPDATE-16 A download that fails its checks is deleted") func update16() async throws {
        let dir = Env.tempFolder()
        // Marked, to find its unpacked copy among any other Expanse-update-* folders.
        let marker = "marker-\(UUID().uuidString)"
        let app = Self.fixtureApp(in: dir, version: "9.9.9", extra: [marker])
        let zip = dir.appendingPathComponent("Expanse-9.9.9.zip")
        #expect(Self.shell("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path]).status == 0)
        let u = Updater(isRelease: false)
        let got: URL? = await withCheckedContinuation { done in
            u.download(Self.release("9.9.9", zip: zip)) { done.resume(returning: $0) }
        }
        #expect(got == nil)
        let tmp = FileManager.default.temporaryDirectory
        let left = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
        for name in left where name.hasPrefix("Expanse-update-") {
            let marked = tmp.appendingPathComponent(name).appendingPathComponent("Expanse.app/Contents/Resources/\(marker)")
            #expect(!FileManager.default.fileExists(atPath: marked.path), "\(name) was left behind")
        }
    }

    // MARK: UPDATE-18, UPDATE-19

    @Test("UPDATE-18 update-cask.sh points the cask at the new version and its zip (logic)") func update18() throws {
        let zip = Env.tempFolder().appendingPathComponent("Expanse-0.1.35.zip")
        try Data("a release".utf8).write(to: zip)
        let sha = Self.shasum(zip)
        let r = Self.updateCask(cask: Self.cask(version: "0.1.34", sha256: String(repeating: "0", count: 64)), version: "0.1.35", zip: zip,
                                branch: "test")
        #expect(r.status == 0, "\(r.output)")
        #expect(r.output.contains("https://github.com/invig/homebrew-tap/commit/test"))
        // Read from, and committed to, the test branch.
        #expect(r.gh.filter { !$0.contains("PUT") }.allSatisfy { $0.contains("repos/invig/homebrew-tap/contents/Casks/expanse.rb?ref=test") })
        let put = try #require(r.gh.first { $0.contains("PUT") })
        #expect(put.contains("message=Expanse 0.1.35"))
        #expect(put.contains("branch=test"))
        #expect(put.contains("sha=blob123"))
        let content = try #require(put.first { $0.hasPrefix("content=") }.map { String($0.dropFirst("content=".count)) })
        let cask = String(decoding: Data(base64Encoded: content) ?? Data(), as: UTF8.self)
        #expect(cask.contains("  version \"0.1.35\"\n"))
        #expect(cask.contains("  sha256 \"\(sha)\"\n"))
    }

    @Test("UPDATE-19 update-cask.sh: a cask already at the version is left alone") func update19a() throws {
        let zip = Env.tempFolder().appendingPathComponent("Expanse-0.1.34.zip")
        try Data("a release".utf8).write(to: zip)
        let r = Self.updateCask(cask: Self.cask(version: "0.1.34", sha256: Self.shasum(zip)), version: "0.1.34", zip: zip, branch: "test")
        #expect(r.status == 0, "\(r.output)")
        #expect(r.output.contains("The cask is already at 0.1.34."))
        #expect(!r.gh.contains { $0.contains("PUT") })
    }

    @Test("UPDATE-19 update-cask.sh: a cask with no version line isn't touched") func update19b() throws {
        let zip = Env.tempFolder().appendingPathComponent("Expanse-0.1.35.zip")
        try Data("a release".utf8).write(to: zip)
        let r = Self.updateCask(cask: Self.cask(version: nil, sha256: String(repeating: "0", count: 64)), version: "0.1.35", zip: zip, branch: "test")
        #expect(r.status == 1)
        #expect(r.output.contains("Couldn't find the version and sha256 lines in invig/homebrew-tap/Casks/expanse.rb."))
        #expect(!r.gh.contains { $0.contains("PUT") })
    }

    @Test("UPDATE-19 release.sh finishes, and says so, when the cask can't be updated") func update19c() throws {
        let root = Self.scratchRepo(), log = root.appendingPathComponent("stub.log")
        let fixture = root.appendingPathComponent("expanse.rb")
        try Self.cask(version: nil, sha256: String(repeating: "0", count: 64)).write(to: fixture, atomically: true, encoding: .utf8)
        let bin = Self.stubs([
            "git": "exit 0",
            "swift": Self.swiftStub,
            "lipo": "echo \"Architectures in the fat file: $2 are: x86_64 arm64\"",
            "codesign": "exit 0",
            "xcrun": "exit 0",
            "spctl": "exit 0",
            "gh": Self.ghStub,
        ])
        let env = Self.environment(stubs: bin, log: log, ["STUB_BIN": root.appendingPathComponent(".build/release").path,
                                                         "CASK_FIXTURE": fixture.path, "CASK_BRANCH": "test"])
        let r = Self.shell("/bin/bash", [root.appendingPathComponent("scripts/release.sh").path], in: root, env: env)
        let info = NSDictionary(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let version = try #require(info?["CFBundleShortVersionString"] as? String)
        #expect(r.status == 0, "\(r.output)")
        #expect(r.output.contains("==> Updating the Homebrew cask (invig/homebrew-tap)"))
        #expect(r.output.contains("The release is out, but the cask isn't updated: run scripts/update-cask.sh \(version) build/release/Expanse-\(version).zip"))
        #expect(r.output.hasSuffix("==> Done\n"))
        // The release was published (to the stand-in), the cask never committed.
        #expect(Self.calls(log, "gh").contains { $0.first == "release" && $0.contains("v\(version)") })
        #expect(!Self.calls(log, "gh").contains { $0.contains("PUT") })
    }
}
