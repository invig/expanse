import AppKit
import ApplicationServices
import CryptoKit
import Security

/// The manual cases in docs/regression/updates-and-install.md. Most need a Developer ID–signed
/// release older than the latest on GitHub; the runner drives a development build (a release
/// ignores the debug links it uses), so those are skipped, saying so. What a development build
/// shows, the Homebrew install and the published cask are checked.
@MainActor enum UPDATE {
    static let cases: [Case] = [
        Case("UPDATE-03", "Settings: updates") { t in
            try await t.updateClosingUp {
                guard AXIsProcessTrusted() else { throw Skip("needs Accessibility for Expanse Tests, to read Expanse's Settings page") }
                guard !updateIsRelease(t.expanseURL) else { throw Skip("the runner drives development builds; this one is a release") }
                // Step 3, a development build: the Updates section greyed out, with the footnote.
                let settings = try await t.updateOpenSettings()
                let version = Bundle(url: t.expanseURL)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                guard let automatic = settings.toggle("Check for updates automatically") else {
                    throw Failure("no “Check for updates automatically” switch in Settings. It has: \(settings.summary)")
                }
                guard let checkNow = settings.button("Check Now") else { throw Failure("no Check Now button in Settings") }
                try t.expect(settings.has("Updates"), "Settings should have an Updates section")
                try t.expect(settings.has("Expanse \(version)"), "Settings should show “Expanse \(version)” beside Check Now")
                try t.expect(!automatic.enabled && !checkNow.enabled, "in a development build the Updates section should be greyed out")
                try t.expect(automatic.on == ((expanseDefault("checkForUpdates") as? Bool) ?? true),
                             "“Check for updates automatically” should show the setting (on unless it's been turned off)")
                try t.expect(settings.has(updateDevNote), "Settings should say “\(updateDevNote)”")
                try await t.updateCloseSettings()
                throw Skip("development build checked (step 3: Updates greyed out, with the footnote); steps 1–2 (Check Now, the daily check) need a Developer ID–signed release and the network")
            }
        },
        Case("UPDATE-04", "A release finds a newer version a minute after launch and asks", .guided) { t in
            throw Skip(updateNeedsRelease(t, "an older release build in /Applications, online"))
        },
        Case("UPDATE-05", "Install and Relaunch replaces Expanse in place", .guided) { t in
            throw Skip(updateNeedsRelease(t, "an update downloaded and ready (an older release build, online)"))
        },
        Case("UPDATE-06", "What's New and Later", .guided) { t in
            throw Skip(updateNeedsRelease(t, "an update ready, with its alert showing (an older release build, online)"))
        },
        Case("UPDATE-08", "The update question never appears over the canvas", .guided) { t in
            throw Skip(updateNeedsRelease(t, "an older release build, just launched, online"))
        },
        Case("UPDATE-09", "Check Now says when you're up to date, or when it couldn't check", .guided) { t in
            throw Skip(updateNeedsRelease(t, "the latest release build, and turning Wi-Fi off"))
        },
        Case("UPDATE-17", "Install with Homebrew", .guided) { t in
            guard ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw Skip("Homebrew isn't installed")
            }
            let app = URL(fileURLWithPath: "/Applications/Expanse.app")
            guard !FileManager.default.fileExists(atPath: app.path) else {
                throw Skip("there's already an Expanse in /Applications: this needs a Mac without one")
            }
            let latest = try await updateLatestRelease()
            try await t.ask("In Terminal, run: brew install --cask invig/tap/expanse")
            var failure: Error?
            do {
                try t.expect(FileManager.default.fileExists(atPath: app.path), "Homebrew didn't install /Applications/Expanse.app")
                let version = (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any])?["CFBundleShortVersionString"] as? String
                try t.expect(version == latest.version, "Homebrew installed Expanse \(version ?? "?"), not the latest release (\(latest.version))")
                try t.expect(updateIsRelease(app), "the Expanse Homebrew installed isn't signed with a Developer ID")
                // It opens with the walkthrough. (One copy runs at a time: the development build quits first.)
                try await t.quitExpanse()
                try await t.ask("Open /Applications/Expanse.app (Finder › Applications), confirming macOS's question about an app from the internet if it asks.")
                var installed: NSRunningApplication?
                try await t.until("the installed Expanse to open", timeout: 20) {
                    installed = updateRunning(at: app)
                    return installed != nil
                }
                if let pid = installed?.processIdentifier {
                    try await t.until("its walkthrough to open", timeout: 20) { updateWelcome(pid: pid) != nil }
                }
            } catch {
                failure = error
            }
            // Back as it was: no Expanse in /Applications, and the development build running.
            updateRunning(at: app)?.terminate()
            try? await t.until("the installed Expanse to quit", timeout: 15) { updateRunning(at: app) == nil }
            do {
                try await t.ask("Put things back: in Terminal, run: brew uninstall --cask expanse")
                try t.expect(!FileManager.default.fileExists(atPath: app.path),
                             "/Applications/Expanse.app is still there: remove it, or expanse:// links may open it instead of the development build")
                try await t.launchExpanse()
            } catch {
                failure = failure ?? error
            }
            if let failure { throw failure }
        },
        Case("UPDATE-18", "Releasing points the Homebrew cask at the new version") { t in
            // What the last release.sh run left: the cask at the latest release, its zip's SHA-256,
            // in a commit titled “Expanse <version>”.
            let latest = try await updateLatestRelease()
            guard let zip = latest.zip else { throw Failure("the latest release (\(latest.version)) has no Expanse-\(latest.version).zip") }
            let caskURL = URL(string: "https://api.github.com/repos/invig/homebrew-tap/contents/Casks/expanse.rb?ref=main")!
            let cask = String(decoding: try await updateFetch(caskURL, accept: "application/vnd.github.raw"), as: UTF8.self)
            let lines = cask.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            try t.expect(lines.contains("  version \"\(latest.version)\""),
                         "the cask isn't at the latest release (\(latest.version)): \(lines.first { $0.hasPrefix("  version") } ?? "it has no version line")")
            let sha = SHA256.hash(data: try await updateFetch(zip)).map { String(format: "%02x", $0) }.joined()
            try t.expect(lines.contains("  sha256 \"\(sha)\""),
                         "the cask's sha256 isn't the release zip's (\(sha)): \(lines.first { $0.hasPrefix("  sha256") } ?? "it has no sha256 line")")
            let commitsURL = URL(string: "https://api.github.com/repos/invig/homebrew-tap/commits?path=Casks/expanse.rb&per_page=20")!
            let commits = try JSONSerialization.jsonObject(with: try await updateFetch(commitsURL)) as? [[String: Any]] ?? []
            let titles = commits.compactMap { (($0["commit"] as? [String: Any])?["message"] as? String)?.split(separator: "\n").first.map(String.init) }
            try t.expect(titles.contains("Expanse \(latest.version)"),
                         "no commit to the cask titled “Expanse \(latest.version)” (the latest is “\(titles.first ?? "none")”)")
        },
    ]
}

// MARK: - Releases

private let updateDevNote = "This is a development build: it has no updates, and opening at login opens this copy."

/// Signed with a Developer ID, as Updater.isRelease checks: a release, which updates.
private func updateIsRelease(_ app: URL) -> Bool {
    var code: SecStaticCode?, requirement: SecRequirement?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
          SecRequirementCreateWithString("anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]" as CFString,
                                         [], &requirement) == errSecSuccess, let requirement else { return false }
    return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
}

/// Why a case that needs a release can't run here.
@MainActor private func updateNeedsRelease(_ t: Ctx, _ what: String) -> String {
    updateIsRelease(t.expanseURL)
        ? "needs \(what); the runner drives development builds (a release ignores the debug links it uses)"
        : "needs \(what), signed with a Developer ID; this is a development build, which never updates"
}

/// A copy of Expanse running from `app`.
private func updateRunning(at app: URL) -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.invignation.expanse")
        .first { !$0.isTerminated && $0.bundleURL?.standardizedFileURL.path == app.standardizedFileURL.path }
}

/// The walkthrough window (960×620) of the Expanse running as `pid`.
private func updateWelcome(pid: pid_t) -> CGWindowID? {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.first { w in
        guard (w[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
              let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) else { return false }
        return abs(r.width - 960) < 2 && abs(r.height - 620) < 2
    }.flatMap { $0[kCGWindowNumber as String] as? CGWindowID }
}

/// GitHub's answer for `url`. Unreachable, or rate-limited: the case is skipped.
private func updateFetch(_ url: URL, accept: String = "application/vnd.github+json") async throws -> Data {
    var request = URLRequest(url: url, timeoutInterval: 30)
    request.setValue(accept, forHTTPHeaderField: "Accept")
    request.setValue("ExpanseTests", forHTTPHeaderField: "User-Agent")
    let data: Data, response: URLResponse
    do {
        (data, response) = try await URLSession.shared.data(for: request)
    } catch {
        throw Skip("couldn't reach GitHub (\(error.localizedDescription))")
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 403 || status == 429 { throw Skip("GitHub turned the request away (\(status): its rate limit?)") }
    guard status == 200 else { throw Failure("GitHub answered \(status) for \(url.absoluteString)") }
    return data
}

/// The latest release on GitHub, as Updater reads it: its version, and its Expanse-<version>.zip.
private func updateLatestRelease() async throws -> (version: String, zip: URL?) {
    let data = try await updateFetch(URL(string: "https://api.github.com/repos/invig/expanse/releases/latest")!)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = json["tag_name"] as? String else {
        throw Failure("GitHub's latest release has no tag")
    }
    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let zip = (json["assets"] as? [[String: Any]] ?? []).first { $0["name"] as? String == "Expanse-\(version).zip" }
        .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
    return (version, zip)
}

// MARK: - Accessibility: Settings

/// Part of Expanse's interface as Accessibility has it, read in one go per element.
private final class UpdateNode {
    let el: AXUIElement
    let role: String, title: String, label: String, help: String
    let value: AnyObject?
    let enabled: Bool
    let frame: CGRect?
    let children: [UpdateNode]
    lazy var flat: [UpdateNode] = [self] + children.flatMap { $0.flat }

    private static let names = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute,
                                kAXEnabledAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute] as CFArray

    /// Reads `el` and (while `budget` lasts) everything in it.
    init(_ el: AXUIElement, budget: inout Int, depth: Int = 0) {
        self.el = el
        var out: CFArray?
        AXUIElementCopyMultipleAttributeValues(el, Self.names, [], &out)
        let values = (out as? [AnyObject]) ?? []
        func at(_ i: Int) -> AnyObject? {
            guard i < values.count else { return nil }
            let v = values[i]
            if CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetType(unsafeBitCast(v, to: AXValue.self)) == .axError { return nil }
            return v
        }
        role = at(0) as? String ?? ""
        title = at(1) as? String ?? ""
        label = at(2) as? String ?? ""
        help = at(3) as? String ?? ""
        value = at(4)
        enabled = at(5) as? Bool ?? true
        var origin = CGPoint.zero, size = CGSize.zero
        if let p = at(6), let s = at(7), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID(),
           AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &origin),
           AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) {
            frame = CGRect(origin: origin, size: size)
        } else {
            frame = nil
        }
        budget -= 1
        var kids: [UpdateNode] = []
        if depth < 40, let list = at(8) as? [AnyObject] {
            for k in list where budget > 0 && CFGetTypeID(k) == AXUIElementGetTypeID() {
                kids.append(UpdateNode(unsafeBitCast(k, to: AXUIElement.self), budget: &budget, depth: depth + 1))
            }
        }
        children = kids
    }

    var string: String { value as? String ?? "" }
    var on: Bool? { (value as? NSNumber)?.boolValue }
    var words: [String] { [title, label, string, help].filter { !$0.isEmpty } }
    func says(_ s: String) -> Bool { words.contains { $0.caseInsensitiveCompare(s) == .orderedSame } }
    func has(_ s: String) -> Bool { flat.contains { $0.says(s) } }
    func first(_ s: String, role: String? = nil) -> UpdateNode? { flat.first { (role == nil || $0.role == role) && $0.says(s) } }

    /// A switch labelled `s`: one that says it itself, or the first after a text that does (SwiftUI
    /// can give a toggle its label as a text beside it). Switches are checkboxes to Accessibility,
    /// or AXSwitch.
    func toggle(_ s: String) -> UpdateNode? {
        let roles: Set<String> = [kAXCheckBoxRole, "AXSwitch", "AXToggle"]
        if let own = flat.first(where: { roles.contains($0.role) && $0.says(s) }) { return own }
        guard let i = flat.firstIndex(where: { $0.says(s) }) else { return nil }
        return flat[i...].first { roles.contains($0.role) }
    }

    /// What's there, for a failure message: each node's role and words.
    var summary: String {
        flat.filter { !$0.words.isEmpty || $0.role != "AXGroup" }.prefix(40).map { "\($0.role)\($0.words.isEmpty ? "" : " “" + $0.words.joined(separator: " / ") + "”")" }.joined(separator: "; ")
    }

    /// A button that says `s`, or holds a text that does.
    func button(_ s: String) -> UpdateNode? {
        let buttons = flat.filter { $0.role == kAXButtonRole }
        return buttons.first { $0.says(s) } ?? buttons.first { $0.flat.dropFirst().contains { $0.says(s) } }
    }

    @discardableResult func press() -> Bool { AXUIElementPerformAction(el, kAXPressAction as CFString) == .success }

    /// The window's close button, pressed.
    func pressClose() -> Bool {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXCloseButtonAttribute as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXUIElementGetTypeID() else { return false }
        return AXUIElementPerformAction(unsafeBitCast(v, to: AXUIElement.self), kAXPressAction as CFString) == .success
    }
}

fileprivate extension Ctx {
    /// Expanse's windows as Accessibility lists them (its panels too, which some lists leave out).
    func updateAXWindows() -> [AXUIElement] {
        guard let pid = expanse?.processIdentifier else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 3)
        var found: [AXUIElement] = []
        for attribute in [kAXWindowsAttribute, kAXChildrenAttribute, kAXFocusedWindowAttribute] {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, attribute as CFString, &v) == .success, let v else { continue }
            let list: [AnyObject] = CFGetTypeID(v) == AXUIElementGetTypeID() ? [v] : (v as? [AnyObject] ?? [])
            for item in list where CFGetTypeID(item) == AXUIElementGetTypeID() {
                let el = unsafeBitCast(item, to: AXUIElement.self)
                if !found.contains(where: { CFEqual($0, el) }) { found.append(el) }
            }
        }
        return found
    }

    /// The first of Expanse's windows (read in full) that `match` picks from its top level.
    func updateWindow(_ match: (UpdateNode) -> Bool) -> UpdateNode? {
        for el in updateAXWindows() {
            var one = 1
            guard match(UpdateNode(el, budget: &one)) else { continue }
            var budget = 3000
            return UpdateNode(el, budget: &budget)
        }
        return nil
    }

    /// The menu bar panel's window and its contents, if it's open, on either page.
    private func updatePanelWindow() -> UpdateNode? {
        updateWindow { $0.frame.map { abs($0.width - (360 + 2 * 24)) < 2 } ?? false }
    }

    /// The menu bar panel's first page, if it's showing.
    func updatePanel() -> UpdateNode? {
        let panel = updatePanelWindow()
        return panel?.has("Quit Expanse") == true ? panel : nil
    }

    /// The panel's Settings page, if it's showing.
    func updateSettings() -> UpdateNode? {
        let panel = updatePanelWindow()
        return panel?.toggle("Open Expanse at login") != nil ? panel : nil
    }

    /// Settings, from the menu bar panel's gear.
    func updateOpenSettings() async throws -> UpdateNode {
        if let open = updateSettings() { return open }
        link("menu")
        var panel: UpdateNode?
        try await until("the menu bar panel", timeout: 5) {
            panel = self.updatePanel()
            return panel != nil
        }
        guard let gear = panel?.button("Settings") else { throw Failure("no Settings button in the menu bar panel") }
        try expect(gear.press(), "couldn't press Settings in the menu bar panel")
        var settings: UpdateNode?
        try await until("the panel's Settings page", timeout: 5) {
            settings = self.updateSettings()
            return settings != nil
        }
        return settings!
    }

    /// Runs `body`, then closes the menu bar panel if it left it open, passing or failing, so the
    /// next case starts clear.
    func updateClosingUp(_ body: () async throws -> Void) async throws {
        var failure: Error?
        do { try await body() } catch { failure = error }
        // On the Settings page, Esc goes back first.
        if updateSettings() != nil, Input.allowed { Input.key(.escape) }
        if updatePanelWindow() != nil, Input.allowed { Input.key(.escape) }
        if let failure { throw failure }
    }

    func updateCloseSettings() async throws {
        guard updateSettings() != nil else { return }
        Input.key(.escape)
        try await until("Esc to go back from Settings", timeout: 3) { self.updateSettings() == nil }
        Input.key(.escape)
        try await until("the menu bar panel to close", timeout: 3) { self.updatePanelWindow() == nil }
    }
}
