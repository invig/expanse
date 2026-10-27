import AppKit
import ApplicationServices
import SwiftUI

/// The first-launch walkthrough: four short steps, each saying what you get and why macOS needs
/// the change, with a live tick once it's done; then a cheat sheet. Also reachable from the menu.
enum Onboarding {
    static let doneKey = "onboardingDone"
    /// Expanse's hot corner, which the walkthrough lets you pick. Set at launch.
    static var hotCorner: HotCorner?
    private static var window: NSWindow?
    private static let closer = Closer()

    /// Closing with the title-bar button releases the window, its view and the status timer.
    private final class Closer: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            Onboarding.window?.contentView = nil
            Onboarding.window = nil
        }
    }

    /// First launch, or a permission is missing.
    static var needed: Bool {
        !UserDefaults.standard.bool(forKey: doneKey) || !AX.isTrusted(prompt: false) || !CGPreflightScreenCaptureAccess()
    }

    static func show(onFinish: @escaping () -> Void) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView {
            UserDefaults.standard.set(true, forKey: doneKey)
            window?.close()
            onFinish()
        }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        // Above the canvas overlay, which sits just under the menu bar while zoomed out.
        w.level = .modalPanel
        w.contentView = NSHostingView(rootView: view)
        w.delegate = closer
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

// MARK: - What macOS has in the way

/// The macOS settings that get to Expanse's shortcuts first: its own hot corners, and its ⌃ + arrow
/// shortcuts for Spaces and Mission Control. Read straight from macOS's preferences, so the
/// walkthrough can tick them off as you change them in System Settings.
enum SystemShortcuts {
    /// macOS hot corners with an action among `corners`, e.g. "bottom-right corner for Quick Note".
    static func hotCorners(in corners: [HotCorner.Corner]) -> [String] {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        let keys: [HotCorner.Corner: String] = [.topLeft: "tl", .topRight: "tr", .bottomLeft: "bl", .bottomRight: "br"]
        return corners.compactMap { corner in
            guard let key = keys[corner] else { return nil }
            let action = CFPreferencesCopyAppValue("wvous-\(key)-corner" as CFString, domain) as? Int ?? 1
            let modifier = CFPreferencesCopyAppValue("wvous-\(key)-modifier" as CFString, domain) as? Int ?? 0
            // 0 and 1 are "–"; a corner that only fires with a key held down doesn't get in the way.
            guard action > 1, modifier == 0 else { return nil }
            // A non-breaking hyphen: "bottom-right" stays on one line.
            return "\(corner.title.lowercased().replacingOccurrences(of: " ", with: "\u{2011}")) corner for \(cornerActions[action] ?? "something else")"
        }
    }

    private static let cornerActions = [2: "Mission Control", 3: "Application Windows", 4: "Desktop",
                                        5: "Start Screen Saver", 6: "Disable Screen Saver", 10: "Put Display to Sleep",
                                        11: "Launchpad", 12: "Notification Centre", 13: "Lock Screen", 14: "Quick Note"]

    /// macOS shortcuts that are on and use ⌃ + an arrow key, e.g. "Mission Control (⌃↑)".
    static func controlArrows() -> [String] {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any] ?? [:]
        let arrows = [123: "←", 124: "→", 125: "↓", 126: "↑"]
        // Mission Control's own, on until they've been changed.
        let builtIn = [32: ("Mission Control", 126), 33: ("Application windows", 125),
                       79: ("Move left a space", 123), 81: ("Move right a space", 124)]
        var on = builtIn.filter { all[String($0.key)] == nil }.map { "\($0.value.0) (⌃\(arrows[$0.value.1]!))" }
        for (id, value) in all {
            guard let entry = value as? [String: Any], entry["enabled"] as? Bool == true,
                  let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int], params.count == 3,
                  let arrow = arrows[params[1]] else { continue }
            // ⌃ alone: with ⇧, ⌥ or ⌘ as well, it's a different shortcut.
            let control = 0x40000, others = 0x20000 | 0x80000 | 0x100000
            guard params[2] & control != 0, params[2] & others == 0 else { continue }
            on.append("\(Int(id).flatMap { builtIn[$0]?.0 } ?? "A macOS shortcut") (⌃\(arrow))")
        }
        return on.sorted()
    }
}

extension HotCorner.Corner {
    /// The screen corners this setting uses.
    var corners: [HotCorner.Corner] {
        switch self {
        case .off: []
        case .all: [.topLeft, .topRight, .bottomLeft, .bottomRight]
        default: [self]
        }
    }
}

// MARK: - Live status

/// Where each step stands, polled every second: macOS sends no notification when you flip a
/// switch in System Settings.
final class SetupModel: ObservableObject {
    @Published var accessibility = AX.isTrusted(prompt: false)
    @Published var screenRecording = CGPreflightScreenCaptureAccess()
    /// You've asked for Screen Recording; macOS only reports it granted after a relaunch.
    @Published var screenRecordingRequested = false
    /// macOS hot corners in the way of Expanse's (see SystemShortcuts).
    @Published var cornersInTheWay: [String] = []
    /// macOS ⌃ + arrow shortcuts that are still on.
    @Published var arrowsInTheWay: [String] = []
    @Published var corner: HotCorner.Corner {
        didSet {
            Onboarding.hotCorner?.corner = corner
            refresh()
        }
    }
    private var timer: Timer?

    init() {
        corner = Onboarding.hotCorner?.corner ?? .all
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    deinit { timer?.invalidate() }

    var screenRecordingDone: Bool { screenRecording || screenRecordingRequested }
    var cornersDone: Bool { cornersInTheWay.isEmpty }
    var arrowsDone: Bool { arrowsInTheWay.isEmpty }

    private func refresh() {
        let ax = AX.isTrusted(prompt: false)
        if ax != accessibility { accessibility = ax }
        let sr = CGPreflightScreenCaptureAccess()
        if sr != screenRecording { screenRecording = sr }
        let corners = SystemShortcuts.hotCorners(in: corner.corners)
        if corners != cornersInTheWay { cornersInTheWay = corners }
        let arrows = SystemShortcuts.controlArrows()
        if arrows != arrowsInTheWay { arrowsInTheWay = arrows }
    }

    func requestAccessibility() {
        _ = AX.isTrusted(prompt: true)   // adds Expanse to the list
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func requestScreenRecording() {
        screenRecordingRequested = true
        if !CGRequestScreenCaptureAccess() {
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }

    func openScreenRecording() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") }
    func openHotCorners() { open("x-apple.systempreferences:com.apple.Desktop-Settings.extension") }
    func openKeyboardShortcuts() { open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") }

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    /// Screen Recording takes effect on the next launch.
    func relaunch() { Updater.relaunch() }
}

// MARK: - Brand

/// The icon's colours: a deep-space sky, the portal's blue glow and the ring's amber lights.
private extension Color {
    static let sky = Color(red: 0x0C / 255, green: 0x1B / 255, blue: 0x40 / 255)
    static let deepSpace = Color(red: 0x03 / 255, green: 0x09 / 255, blue: 0x1E / 255)
    static let portal = Color(red: 0x30 / 255, green: 0x86 / 255, blue: 0xD1 / 255)
    static let portalGlow = Color(red: 0x80 / 255, green: 0xD1 / 255, blue: 0xFC / 255)
    static let amber = Color(red: 0xF2 / 255, green: 0xA3 / 255, blue: 0x3A / 255)
    /// Buttons and links: the portal blue, a shade deeper so white text reads on it.
    static let brand = Color(red: 0x24 / 255, green: 0x74 / 255, blue: 0xC4 / 255)
}

/// A capsule button that gives a little under the pointer. `prominent` is the one thing to do next.
private struct BrandButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 18)
            .frame(minHeight: 34)
            .background(Capsule().fill(prominent ? Color.brand : Color.primary.opacity(0.07)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Walkthrough

struct OnboardingView: View {
    static let size = CGSize(width: 960, height: 620)
    let finish: () -> Void
    @StateObject private var model = SetupModel()
    @State private var page: Int
    /// Pages after the first one fade in part by part; the first is just there.
    @State private var animateIn = false
    private let pages = 6

    init(startPage: Int = 0, finish: @escaping () -> Void) {
        self.finish = finish
        _page = State(initialValue: startPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            CanvasIllustration(page: page, corner: model.corner)
                .frame(width: 360)
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    switch page {
                    case 0: WelcomePage(model: model)
                    case 1: AccessibilityPage(model: model)
                    case 2: ScreenRecordingPage(model: model)
                    case 3: HotCornerPage(model: model)
                    case 4: ArrowKeysPage(model: model)
                    default: ReadyPage(corner: model.corner)
                    }
                }
                .environment(\.staggerIn, animateIn)
                .transition(.opacity)
                .id(page)
                Spacer(minLength: 20)
                footer
            }
            .padding(.horizontal, 52)
            .padding(.top, 76)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.background)
        // Right up under the (transparent) title bar, so the canvas runs to the top edge.
        .ignoresSafeArea()
        .tint(.brand)
    }

    /// Whether the step on this page is done (or has nothing to do).
    private var stepDone: Bool {
        switch page {
        case 1: model.accessibility
        case 2: model.screenRecordingDone
        case 3: model.cornersDone
        case 4: model.arrowsDone
        default: true
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                ForEach(0..<pages, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.brand : Color.secondary.opacity(0.25))
                        .frame(width: i == page ? 18 : 7, height: 7)
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0), value: page)
            Spacer()
            if page > 0 {
                Button("Back") { go(to: page - 1) }
                    .buttonStyle(BrandButtonStyle(prominent: false))
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
            // Until a step is done, its own button is the one to press; this one only skips.
            Button(page == 0 ? "Get started" : page == pages - 1 ? "Start using Expanse" : stepDone ? "Continue" : "Skip for now") {
                if page == pages - 1 {
                    finish()
                    // Screen Recording only takes effect after a relaunch; do it for them.
                    if model.screenRecordingRequested && !model.screenRecording { model.relaunch() }
                } else {
                    go(to: page + 1)
                }
            }
            .buttonStyle(BrandButtonStyle(prominent: stepDone))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func go(to newPage: Int) {
        animateIn = true
        withAnimation(.easeOut(duration: 0.2)) { page = newPage }
    }
}

// MARK: - Page parts

private struct StaggerInKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    /// Whether a page's parts fade in one after another (not when the window first opens).
    var staggerIn: Bool {
        get { self[StaggerInKey.self] }
        set { self[StaggerInKey.self] = newValue }
    }
}

/// Fades a page part in a beat after the one above it.
private struct StaggerIn: ViewModifier {
    let index: Int
    @Environment(\.staggerIn) private var enabled
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(!enabled || shown ? 1 : 0)
            .offset(y: !enabled || shown ? 0 : 8)
            .onAppear {
                guard enabled else { return }
                withAnimation(.easeOut(duration: 0.35).delay(0.05 + Double(index) * 0.07)) { shown = true }
            }
    }
}

private extension View {
    func staggerIn(_ index: Int) -> some View { modifier(StaggerIn(index: index)) }
}

private struct PageHeader: View {
    let eyebrow: String
    let title: String
    let why: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.brand)
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(why)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 470, alignment: .leading)
        }
        .staggerIn(0)
    }
}

/// A raised surface: white with a soft layered shadow in light mode; in dark mode, where shadows
/// don't show, a lighter fill with a faint top highlight.
private struct Surface: View {
    let cornerRadius: CGFloat
    var depth: CGFloat = 1
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if scheme == .dark {
            shape.fill(Color.white.opacity(0.07))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.02)],
                                                           startPoint: .top, endPoint: .bottom)))
        } else {
            shape.fill(Color.white)
                .shadow(color: .black.opacity(0.08 * depth), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.07 * depth), radius: 10 * depth, y: 4 * depth)
        }
    }
}

/// One step's single action: what it's about, where it stands, and the button that does it.
private struct StepCard<Extra: View>: View {
    let symbol: String
    let title: String
    let done: Bool
    let doneText: String
    /// Shown while not done: what's in the way, or what's left to do.
    var problem: String?
    let actionTitle: String
    let action: () -> Void
    @ViewBuilder var extra: Extra

    private static var padding: CGFloat { 16 }
    private static var iconRadius: CGFloat { 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: Self.iconRadius, style: .continuous)
                        .fill(Color.brand.opacity(0.12))
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.brand)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    if done {
                        Label(doneText, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.green)
                            .transition(.opacity.combined(with: .scale(0.25)).combined(with: .blurReplace))
                    } else if let problem {
                        Text(problem)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                // Still there once it's done (quieter), so the steps below always make sense.
                Button(actionTitle, action: action).buttonStyle(BrandButtonStyle(prominent: !done))
            }
            extra
        }
        .padding(Self.padding)
        // Concentric with the icon tile in its top-left corner.
        .background(Surface(cornerRadius: Self.iconRadius + Self.padding))
        .animation(.spring(duration: 0.3, bounce: 0), value: done)
        .staggerIn(1)
    }
}

extension StepCard where Extra == EmptyView {
    init(symbol: String, title: String, done: Bool, doneText: String, problem: String? = nil,
         actionTitle: String, action: @escaping () -> Void) {
        self.init(symbol: symbol, title: title, done: done, doneText: doneText, problem: problem,
                  actionTitle: actionTitle, action: action) { EmptyView() }
    }
}

private extension String {
    /// Wraps only between items of a list, never inside one ("Move left a space (⌃←)").
    var unbroken: String { replacingOccurrences(of: " ", with: "\u{00A0}") }
}

/// Under the card: how to do it in System Settings, one numbered step per line. **Bold** marks
/// the names of buttons and switches.
private struct HowTo: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(steps.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1).")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)
                    Text(LocalizedStringKey(steps[i]))
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: 470, alignment: .leading)
        .padding(.leading, 4)
        .staggerIn(2)
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            PageHeader(eyebrow: "Welcome to Expanse",
                       title: "Your Mac, on an infinite canvas.",
                       why: "Every window gets a spot on one endless desktop. Zoom out to see them all, then click one to dive in.")
            VStack(alignment: .leading, spacing: 12) {
                Text("Four quick steps")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ChecklistRow(number: 1, title: "Let Expanse move your windows", done: model.accessibility)
                ChecklistRow(number: 2, title: "Let Expanse show your windows", done: model.screenRecording)
                ChecklistRow(number: 3, title: "Free up a screen corner", done: model.cornersDone)
                ChecklistRow(number: 4, title: "Free up ⌃ + arrow keys", done: model.arrowsDone)
            }
            .staggerIn(1)
            Text("No hacks or SIP changes. Quit any time and every window goes back where it was.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .staggerIn(2)
        }
    }
}

private struct ChecklistRow: View {
    let number: Int
    let title: String
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.primary.opacity(0.07))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            Text(title).font(.system(size: 14))
        }
    }
}

private struct AccessibilityPage: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(eyebrow: "Step 1 of 4",
                       title: "Let Expanse move your windows.",
                       why: "macOS only lets an app move, resize and focus other apps’ windows once you switch on Accessibility for it.")
            StepCard(symbol: "hand.raised", title: "Accessibility", done: model.accessibility, doneText: "On",
                     problem: "Off", actionTitle: "Open Settings", action: model.requestAccessibility)
            HowTo(steps: ["Click **Open Settings**.",
                          "Switch on **Expanse**. Not in the list? Press **+** and choose it."])
        }
    }
}

private struct ScreenRecordingPage: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(eyebrow: "Step 2 of 4",
                       title: "Let Expanse show your windows.",
                       why: "Zoomed out, every window is a live picture. Pictures stay in memory: nothing is recorded, saved or sent.")
            StepCard(symbol: "rectangle.dashed.badge.record", title: "Screen Recording", done: model.screenRecording,
                     doneText: "On",
                     problem: model.screenRecordingRequested ? "Switched it on? Reopen Expanse to finish." : "Off",
                     actionTitle: model.screenRecordingRequested && !model.screenRecording ? "Reopen Expanse" : "Open Settings",
                     action: model.screenRecording ? model.openScreenRecording
                         : model.screenRecordingRequested ? model.relaunch : model.requestScreenRecording)
            HowTo(steps: ["Click **Open Settings**.",
                          "Switch on **Expanse**.",
                          "Click **Reopen Expanse**: macOS applies it the next time Expanse opens."])
        }
    }
}

private struct HotCornerPage: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(eyebrow: "Step 3 of 4",
                       title: "Flick to a corner to see everything.",
                       why: "macOS checks its own hot corners first, so a corner it uses can’t open Expanse.")
            StepCard(symbol: "rectangle.inset.topright.filled", title: "Hot corners", done: model.cornersDone,
                     doneText: model.corner == .off ? "Expanse’s hot corner is off" : "Free for Expanse",
                     problem: "macOS uses the " + model.cornersInTheWay.map(\.unbroken).joined(separator: " and the "),
                     actionTitle: "Open Settings", action: model.openHotCorners) {
                HStack(spacing: 10) {
                    Text("Expanse uses").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    Picker("", selection: $model.corner) {
                        ForEach(HotCorner.Corner.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.leading, 54)
            }
            HowTo(steps: ["Click **Open Settings**.",
                          "Click **Hot Corners…** at the bottom.",
                          "Set the corners Expanse uses to **–**."])
        }
    }
}

private struct ArrowKeysPage: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(eyebrow: "Step 4 of 4",
                       title: "Hop between windows with\u{00A0}⌃\u{00A0}+\u{00A0}arrows.",
                       why: "macOS uses ⌃ + arrows to switch Spaces and open Mission Control, and it gets them first.")
            StepCard(symbol: "arrow.up.and.down.and.arrow.left.and.right", title: "⌃ + arrow keys",
                     done: model.arrowsDone, doneText: "Free for Expanse",
                     problem: "Still on: " + model.arrowsInTheWay.map(\.unbroken).joined(separator: ", "),
                     actionTitle: "Open Settings", action: model.openKeyboardShortcuts)
            HowTo(steps: ["Click **Open Settings**.",
                          "Click **Keyboard Shortcuts…**, then **Mission Control**.",
                          "Switch off **Mission Control**, **Application windows** and **Move left/right a space**."])
        }
    }
}

private struct Keycap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 22)
            .background(Surface(cornerRadius: 5, depth: 0.5))
    }
}

private struct ReadyPage: View {
    let corner: HotCorner.Corner

    private let rows: [([String], String)] = [
        (["⌥", "`"], "Zoom out to every window, and back"),
        (["Click"], "Dive into a window"),
        (["⌃", "← → ↑ ↓"], "Hop to the nearest window that way"),
        (["Pinch", "Scroll"], "Zoom and pan the canvas"),
        (["Space", "Drag"], "Hold Space and drag to move around"),
        (["Drag"], "Move windows; they snap into place"),
        (["⇧", "Click"], "Select several, then drag or close them together"),
        (["T"], "Tidy up: fit to this screen, even the gaps"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(eyebrow: "All set",
                       title: "Try it now.",
                       why: corner == .off ? "Press ⌥` to zoom out, then click any window to dive back in."
                           : "Flick the pointer into a corner (or press ⌥`), then click any window to dive back in.")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                ForEach(rows.indices, id: \.self) { i in
                    GridRow {
                        HStack(spacing: 4) { ForEach(rows[i].0, id: \.self) { Keycap(key: $0) } }
                        Text(rows[i].1).font(.system(size: 13)).foregroundStyle(.primary.opacity(0.85))
                    }
                }
            }
            .staggerIn(1)
            Text("Find this again under the menu bar icon › Welcome & Shortcuts.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .staggerIn(2)
        }
    }
}

// MARK: - Illustration

/// A window on the illustration's canvas: its app, its spot (canvas points, around the middle of
/// the view at 100%) and what's drawn in it.
private struct Sketch {
    enum Kind { case doc, list, chat, tiles, calendar }
    let name: String
    let frame: CGRect
    let kind: Kind
}

/// A tiny Expanse in the icon's colours: groups of windows on a starry canvas, with more out past
/// the edges. It gently zooms out to show them all and back in; on the hot corner step a pointer
/// flicks to the corner to zoom out, and on the arrow keys step it glides from window to window.
private struct CanvasIllustration: View {
    let page: Int
    let corner: HotCorner.Corner

    private static let windows: [Sketch] = [
        // The group in view at 100%.
        Sketch(name: "Calendar", frame: CGRect(x: -150, y: -184, width: 128, height: 72), kind: .calendar),
        Sketch(name: "Slack", frame: CGRect(x: -150, y: -84, width: 170, height: 104), kind: .chat),
        Sketch(name: "TV", frame: CGRect(x: 30, y: -84, width: 110, height: 72), kind: .tiles),
        // A second group below it.
        Sketch(name: "Signal", frame: CGRect(x: -122, y: 74, width: 92, height: 66), kind: .chat),
        Sketch(name: "Finder", frame: CGRect(x: -20, y: 74, width: 124, height: 54), kind: .list),
        // Out past the edges until it zooms out.
        Sketch(name: "Notes", frame: CGRect(x: 214, y: -170, width: 88, height: 112), kind: .doc),
        Sketch(name: "Safari", frame: CGRect(x: 196, y: 30, width: 140, height: 90), kind: .doc),
        Sketch(name: "Mail", frame: CGRect(x: -344, y: -84, width: 118, height: 78), kind: .list),
        Sketch(name: "Music", frame: CGRect(x: -320, y: 110, width: 102, height: 66), kind: .tiles),
        Sketch(name: "Xcode", frame: CGRect(x: -70, y: -400, width: 152, height: 88), kind: .doc),
        Sketch(name: "Photos", frame: CGRect(x: 150, y: 220, width: 112, height: 72), kind: .tiles),
    ]
    /// Where the arrow keys step hops: right, down, left, up.
    private let hops = [1, 2, 4, 3, 0]

    /// Where the camera looks (a canvas point), how far it's zoomed (1 = 100%) and which window
    /// has focus, at time `t`.
    private func camera(_ t: Double) -> (look: CGPoint, scale: Double, focused: Int, phase: Double) {
        if page == 4 {
            // Glide to the next window, rest, glide on.
            let hop = 1.5
            let k = Int(t / hop)
            let from = Self.windows[hops[(k + hops.count - 1) % hops.count]].frame
            let to = Self.windows[hops[k % hops.count]].frame
            let f = min((t / hop - Double(k)) / 0.4, 1)
            let e = f * f * (3 - 2 * f)
            let look = CGPoint(x: from.midX + (to.midX - from.midX) * e, y: from.midY + (to.midY - from.midY) * e)
            return (look, 0.85, hops[k % hops.count], 1)
        }
        // 0 = zoomed out, 1 = 100%.
        let phase = (sin(t * (page == 0 ? 0.9 : 0.6)) + 1) / 2
        return (CGPoint(x: -6, y: -40), 0.46 + 0.54 * phase, 1, phase)
    }

    var body: some View {
        // 60 fps is plenty for this, even on a 120 Hz screen.
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let cam = camera(t)
            GeometryReader { geo in
                let middle = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 - 50)
                ZStack {
                    background(t: t, size: geo.size)
                    let spots = Self.windows.map { w in
                        CGPoint(x: middle.x + (w.frame.midX - cam.look.x) * cam.scale,
                                y: middle.y + (w.frame.midY - cam.look.y) * cam.scale)
                    }
                    ForEach(Self.windows.indices, id: \.self) { i in
                        MiniWindow(kind: Self.windows[i].kind, focused: i == cam.focused)
                            .frame(width: Self.windows[i].frame.width, height: Self.windows[i].frame.height)
                            .scaleEffect(cam.scale)
                            .position(spots[i])
                    }
                    .animation(.spring(duration: 0.35, bounce: 0), value: cam.focused)
                    // Names over every window, and the same size at any zoom, as on the real canvas.
                    ForEach(Self.windows.indices, id: \.self) { i in
                        Color.clear
                            .frame(width: Self.windows[i].frame.width * cam.scale, height: Self.windows[i].frame.height * cam.scale)
                            .overlay(alignment: .topLeading) {
                                Text(Self.windows[i].name)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .shadow(color: .black.opacity(0.6), radius: 2)
                                    .fixedSize()
                                    .offset(y: -13)
                            }
                            .position(spots[i])
                    }
                    if page == 3 { pointer(phase: cam.phase, size: geo.size) }
                    // The canvas fades out under the name.
                    LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 200)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    VStack(spacing: 6) {
                        Spacer()
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 72, height: 72)
                            .shadow(color: Color.portal.opacity(0.5), radius: 16)
                        Text("Expanse")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(Int(cam.scale * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.portalGlow.opacity(0.7))
                            .padding(.bottom, 30)
                    }
                }
            }
        }
        .clipped()
    }

    /// Deep space with the portal's glow behind the windows, and a few twinkling stars.
    private func background(t: Double, size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [.sky, .deepSpace, .black], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.portal.opacity(0.55), Color.portal.opacity(0)],
                           center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: size.width * 0.75)
            Canvas { context, canvasSize in
                var seed: UInt64 = 7
                func next() -> Double {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    return Double(seed >> 33) / Double(1 << 31)
                }
                for _ in 0..<46 {
                    let x = next() * canvasSize.width, y = next() * canvasSize.height
                    let r = 0.4 + next() * 1.1
                    let twinkle = 0.35 + 0.35 * (sin(t * (0.6 + next()) + next() * 6.28) + 1) / 2
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                                 with: .color(.white.opacity(twinkle)))
                }
            }
        }
    }

    /// The pointer on its way to Expanse's corner: it gets there as the canvas zooms out.
    private func pointer(phase: Double, size: CGSize) -> some View {
        let target = corner == .all ? .topRight : corner.corners.first ?? .topRight
        let cx = target == .topLeft || target == .bottomLeft ? -size.width / 2 + 14 : size.width / 2 - 14
        let cy = target == .topLeft || target == .topRight ? -size.height / 2 + 16 : size.height / 2 - 16
        let travel = 1 - phase   // 1 = in the corner, zoomed out
        let eased = travel * travel * (3 - 2 * travel)
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.portalGlow.opacity(0.6 * eased), Color.portalGlow.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 60))
                .frame(width: 120, height: 120)
                .offset(x: cx, y: cy)
            Image(systemName: "cursorarrow")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .offset(x: 30 + (cx - 30) * eased, y: 60 + (cy - 60) * eased)
        }
    }
}

/// One window on the illustration: a title bar and a sketch of what the app shows.
private struct MiniWindow: View {
    let kind: Sketch.Kind
    let focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 4, height: 4) }
                Spacer()
            }
            .padding(.horizontal, 5)
            .frame(height: 10)
            .background(Color(white: 0.9))
            Canvas { context, size in Self.draw(kind, in: size, context) }
        }
        .background(Color.white.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(focused ? Color.amber : Color.white.opacity(0.1), lineWidth: focused ? 2 : 1))
        .shadow(color: focused ? Color.amber.opacity(0.55) : .black.opacity(0.35), radius: focused ? 12 : 6, y: focused ? 0 : 3)
    }

    private static func draw(_ kind: Sketch.Kind, in size: CGSize, _ context: GraphicsContext) {
        func box(_ r: CGRect, _ color: Color, radius: CGFloat = 1.5) {
            context.fill(Path(roundedRect: r, cornerRadius: radius), with: .color(color))
        }
        let w = size.width, h = size.height
        switch kind {
        case .doc:
            box(CGRect(x: 6, y: 6, width: w * 0.45, height: 4), Color.portal.opacity(0.45))
            var y: CGFloat = 15
            var i = 0
            while y + 3 < h - 4 {
                box(CGRect(x: 6, y: y, width: (w - 12) * (i % 3 == 2 ? 0.6 : 1), height: 2.5), Color.portal.opacity(0.18))
                y += 7
                i += 1
            }
        case .list:
            box(CGRect(x: 0, y: 0, width: w * 0.26, height: h), Color.portal.opacity(0.08), radius: 0)
            for (i, y) in stride(from: CGFloat(6), to: h - 4, by: 7).enumerated() {
                box(CGRect(x: 4, y: y, width: w * 0.26 - 9, height: 2.5), Color.portal.opacity(i == 1 ? 0.5 : 0.22))
                box(CGRect(x: w * 0.26 + 6, y: y - 0.5, width: 3.5, height: 3.5), Color.portal.opacity(0.45))
                box(CGRect(x: w * 0.26 + 13, y: y, width: (w * 0.74 - 19) * (i % 2 == 0 ? 0.8 : 0.55), height: 2.5),
                    Color.portal.opacity(0.18))
            }
        case .chat:
            box(CGRect(x: 0, y: 0, width: w * 0.24, height: h), Color.sky.opacity(0.92), radius: 0)
            for y in stride(from: CGFloat(6), to: h - 6, by: 9) {
                box(CGRect(x: 4, y: y, width: 4, height: 4), Color.portalGlow.opacity(0.7), radius: 2)
                box(CGRect(x: 10, y: y + 1, width: w * 0.24 - 14, height: 2), Color.white.opacity(0.35))
            }
            let left = w * 0.24 + 6, room = w * 0.76 - 12
            var y: CGFloat = 6
            for i in 0..<6 where y + 8 < h - 4 {
                let mine = i % 3 == 2
                let bw = room * (mine ? 0.5 : 0.7)
                box(CGRect(x: mine ? left + room - bw : left, y: y, width: bw, height: 7),
                    mine ? Color.portal.opacity(0.75) : Color.portal.opacity(0.12), radius: 3)
                y += 11
            }
        case .tiles:
            let colors: [Color] = [.portal, .amber, .sky, .portalGlow, .portal, .sky, .amber]
            let cols = max(3, Int(w / 18)), gap: CGFloat = 3
            let tw = (w - 8 - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let th = tw * 1.4
            var i = 0
            for row in 0..<4 {
                let y = 5 + CGFloat(row) * (th + gap)
                guard y + th < h + th / 2 else { break }
                for c in 0..<cols {
                    box(CGRect(x: 4 + CGFloat(c) * (tw + gap), y: y, width: tw, height: th),
                        colors[(i + row) % colors.count].opacity(0.75), radius: 2)
                    i += 1
                }
            }
        case .calendar:
            let cols = 7, rows = 5
            let cw = (w - 12) / CGFloat(cols), ch = (h - 14) / CGFloat(rows)
            box(CGRect(x: 6, y: 4, width: w * 0.3, height: 3), Color.red.opacity(0.55))
            for r in 0..<rows {
                for c in 0..<cols {
                    let today = r == 2 && c == 3
                    box(CGRect(x: 6 + CGFloat(c) * cw + cw * 0.25, y: 11 + CGFloat(r) * ch + ch * 0.25,
                               width: cw * 0.5, height: ch * 0.5),
                        today ? Color.red.opacity(0.8) : Color.portal.opacity(0.2), radius: 1)
                }
            }
        }
    }
}
