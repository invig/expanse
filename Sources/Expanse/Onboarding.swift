import AppKit
import ApplicationServices
import SwiftUI

/// The first-launch walkthrough: what Expanse is, the two permissions it needs (and why),
/// the macOS shortcuts worth freeing up, and a cheat sheet. Also reachable from the menu.
enum Onboarding {
    static let doneKey = "onboardingDone"
    private static var window: NSWindow?

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
            window = nil
            onFinish()
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        // Above the canvas overlay, which sits just under the menu bar while zoomed out.
        w.level = .modalPanel
        w.contentView = NSHostingView(rootView: view)
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Permissions

/// Live permission status (polled: macOS sends no notification when you flip a switch).
final class PermissionsModel: ObservableObject {
    @Published var accessibility = AX.isTrusted(prompt: false)
    @Published var screenRecording = CGPreflightScreenCaptureAccess()
    /// You've asked for Screen Recording; macOS only reports it granted after a relaunch.
    @Published var screenRecordingRequested = false
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.accessibility = AX.isTrusted(prompt: false)
            self.screenRecording = CGPreflightScreenCaptureAccess()
        }
    }

    deinit { timer?.invalidate() }

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

    func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    /// Screen Recording takes effect on the next launch.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Walkthrough

struct OnboardingView: View {
    let finish: () -> Void
    @StateObject private var permissions = PermissionsModel()
    @State private var page = 0
    private let pages = 5

    var body: some View {
        HStack(spacing: 0) {
            CanvasIllustration(page: page)
                .frame(width: 320)
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    switch page {
                    case 0: WelcomePage()
                    case 1: PermissionsPage(model: permissions)
                    case 2: ShortcutsSetupPage(model: permissions)
                    case 3: CheatSheetPage()
                    default: ReadyPage()
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
                .id(page)
                Spacer(minLength: 16)
                footer
            }
            .padding(.horizontal, 36)
            .padding(.top, 44)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 820, height: 540)
        .background(.background)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(0..<pages, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: i == page ? 18 : 7, height: 7)
                }
            }
            .animation(.spring(duration: 0.3), value: page)
            Spacer()
            if page > 0 {
                Button("Back") { withAnimation(.easeOut(duration: 0.25)) { page -= 1 } }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
            Button(page == pages - 1 ? "Start using Expanse" : "Continue") {
                if page == pages - 1 { finish() } else { withAnimation(.easeOut(duration: 0.25)) { page += 1 } }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 22)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(eyebrow: "Welcome to Expanse",
                       title: "Your Mac, on an infinite canvas.",
                       subtitle: "Every window gets a place on one endless, zoomable desktop. Zoom out to see everything, dive into a window to use it.")
            FeatureRow(symbol: "arrow.up.left.and.arrow.down.right", title: "Zoom out, dive in",
                       detail: "Hit a screen corner or ⌥` to see every window at once. Click one to fly to it.")
            FeatureRow(symbol: "square.grid.3x3.square", title: "Arrange by dragging",
                       detail: "Windows snap into tidy groups with even gaps. The layout follows you between screens.")
            FeatureRow(symbol: "lock.shield", title: "Stock macOS, no hacks",
                       detail: "No System Integrity Protection changes. Quit, and every window goes back where it was.")
        }
    }
}

private struct PermissionCard: View {
    let symbol: String
    let title: String
    let why: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void
    var footnote: String? = nil
    var footnoteAction: (title: String, run: () -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.12))
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(Color.accentColor)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(why).font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let footnote, !granted {
                    HStack(spacing: 6) {
                        Text(footnote).font(.system(size: 12)).foregroundStyle(.orange)
                        if let footnoteAction {
                            Button(footnoteAction.title, action: footnoteAction.run)
                                .buttonStyle(.link).font(.system(size: 12, weight: .medium))
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button(actionTitle, action: action).controlSize(.regular)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(granted ? Color.green.opacity(0.35) : Color.clear))
        .animation(.easeOut(duration: 0.25), value: granted)
    }
}

private struct PermissionsPage: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(eyebrow: "Step 1 · Permissions",
                       title: "Two switches in System Settings.",
                       subtitle: "Expanse needs these to do its job. Everything stays on your Mac: nothing is recorded, saved or sent anywhere.")
            PermissionCard(symbol: "hand.raised", title: "Accessibility",
                           why: "To move, resize and focus your windows as you pan around the canvas.",
                           granted: model.accessibility, actionTitle: "Open Settings",
                           action: model.requestAccessibility)
            PermissionCard(symbol: "rectangle.dashed.badge.record", title: "Screen Recording",
                           why: "To show live pictures of your windows while you're zoomed out. On screen at 100%, windows aren't captured.",
                           granted: model.screenRecording, actionTitle: "Allow",
                           action: model.requestScreenRecording,
                           footnote: model.screenRecordingRequested ? "Switched it on? Expanse needs a quick relaunch." : nil,
                           footnoteAction: ("Reopen Expanse", model.relaunch))
            Text("In each list, turn on the switch next to Expanse. If it's missing, press + and choose Expanse.app.")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 4)
        }
    }
}

private struct ShortcutsSetupPage: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(eyebrow: "Step 2 · Optional",
                       title: "Free up two macOS shortcuts.",
                       subtitle: "Expanse uses screen corners and ⌃ + arrow keys. macOS uses them too, and gets them first.")
            PermissionCard(symbol: "rectangle.inset.topright.filled", title: "Hot Corners",
                           why: "Rest the pointer in a corner to zoom out. Set the macOS hot corners you want Expanse to use to “–”.",
                           granted: false, actionTitle: "Desktop & Dock…",
                           action: { model.open("x-apple.systempreferences:com.apple.Desktop-Settings.extension") })
            PermissionCard(symbol: "arrow.left.arrow.right", title: "⌃ + arrow keys",
                           why: "Jump to the nearest window in any direction. Under Keyboard Shortcuts › Mission Control, turn off Mission Control, Application windows and Move left/right a space.",
                           granted: false, actionTitle: "Keyboard…",
                           action: { model.open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") })
            Text("You can skip this: ⌥` and the menu bar icon always work.")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 4)
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
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.3)))
            .shadow(color: .black.opacity(0.08), radius: 0, x: 0, y: 1)
    }
}

private struct CheatSheetPage: View {
    private let rows: [([String], String)] = [
        (["⌥", "`"], "Zoom out to every window, and back"),
        (["Corner"], "Rest the pointer in a screen corner: same as ⌥`"),
        (["Click"], "Fly to a window and use it"),
        (["⌃", "← → ↑ ↓"], "Jump to the nearest window that way"),
        (["Pinch", "Scroll"], "Zoom and pan the canvas"),
        (["Drag"], "Move windows; they snap to even 20pt gaps"),
        (["⇧", "Click"], "Select several windows, then drag them together"),
        (["Space", "Drag"], "Pan with the mouse"),
        (["T"], "Tidy up: fit to this screen, close the gaps"),
        (["⌥", "⇧", "`"], "Auto-centre on or off, for side-by-side work"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(eyebrow: "Step 3 · Cheat sheet",
                       title: "Everything at your fingertips.",
                       subtitle: "Reopen this any time from the menu bar icon › Welcome & Shortcuts.")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                ForEach(rows.indices, id: \.self) { i in
                    GridRow {
                        HStack(spacing: 4) { ForEach(rows[i].0, id: \.self) { Keycap(key: $0) } }
                        Text(rows[i].1).font(.system(size: 13)).foregroundStyle(.primary.opacity(0.85))
                    }
                }
            }
        }
    }
}

private struct ReadyPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(eyebrow: "All set",
                       title: "Try it now.",
                       subtitle: "Move the pointer into a corner of the screen, or press ⌥`. Click any window to dive back in.")
            FeatureRow(symbol: "pause.circle", title: "Switch out any time",
                       detail: "Pause Expanse from the menu bar, or quit: every window goes back to exactly where macOS had it.")
            FeatureRow(symbol: "display.2", title: "Moving between screens",
                       detail: "On a laptop the layout tightens up; back on the big screen it returns exactly.")
            FeatureRow(symbol: "terminal", title: "Scriptable",
                       detail: "open \"expanse://toggle\", \"expanse://tidy\", \"expanse://nav?dir=left\" and more.")
        }
    }
}

// MARK: - Illustration

/// A tiny Expanse: a handful of windows on a canvas, gently zooming out and back in.
private struct CanvasIllustration: View {
    let page: Int

    private let windows: [(CGRect, Color)] = [
        (CGRect(x: -150, y: -96, width: 128, height: 84), .blue),
        (CGRect(x: -12, y: -96, width: 96, height: 84), .purple),
        (CGRect(x: 94, y: -96, width: 70, height: 50), .pink),
        (CGRect(x: -150, y: 0, width: 82, height: 100), .orange),
        (CGRect(x: -58, y: 0, width: 142, height: 100), .teal),
        (CGRect(x: 94, y: -36, width: 70, height: 136), .indigo),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // Breathe between overview and close-up, a little faster on the welcome page.
            let phase = (sin(t * (page == 0 ? 0.9 : 0.5)) + 1) / 2
            let scale = 0.62 + 0.38 * phase
            ZStack {
                LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.36), Color(red: 0.42, green: 0.22, blue: 0.55),
                                        Color(red: 0.93, green: 0.55, blue: 0.42)],
                               startPoint: .top, endPoint: .bottom)
                ZStack {
                    ForEach(windows.indices, id: \.self) { i in
                        let (r, color) = windows[i]
                        MiniWindow(color: color, focused: i == 4)
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.midX, y: r.midY)
                    }
                }
                .scaleEffect(scale)
                .offset(x: -8 * phase, y: -6 * phase)
                VStack {
                    Spacer()
                    Text("Expanse")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(Int(scale * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.bottom, 26)
                }
            }
        }
        .clipped()
    }
}

private struct MiniWindow: View {
    let color: Color
    let focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 4, height: 4) }
                Spacer()
            }
            .padding(.horizontal, 5)
            .frame(height: 10)
            .background(color.opacity(0.35))
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1).fill(color.opacity(0.25)).frame(height: 3)
                        .frame(maxWidth: i == 2 ? 30 : .infinity, alignment: .leading)
                }
                Spacer()
            }
            .padding(5)
        }
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Color.white : Color.clear, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}
