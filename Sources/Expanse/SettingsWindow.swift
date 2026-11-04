import AppKit
import SwiftUI

/// What doesn't need to be one click away in the menu bar panel: opening at login and updates.
/// A development build has no updates, so those show greyed out; it opens at login only if you
/// turn that on here (a release turns it on by itself: see LoginItem).
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(checkForUpdates: @escaping () -> Void) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(checkForUpdates: checkForUpdates)))
            w.title = "Expanse Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    let checkForUpdates: () -> Void
    @State private var openAtLogin = LoginItem.enabled
    @State private var automatic = Updater.shared.automatic
    /// See CanvasController.gap.
    @AppStorage(CanvasController.gapKey) private var gap: Double = 20
    /// See CanvasController.lowMotion.
    @AppStorage(CanvasController.motionKey) private var motion = "follow"
    private let isRelease = Updater.shared.isRelease

    var body: some View {
        Form {
            Section {
                Toggle("Open Expanse at login", isOn: Binding(get: { openAtLogin }, set: { _ in
                    LoginItem.toggle()
                    openAtLogin = LoginItem.enabled
                }))
            }
            Section("Arranging") {
                Picker("Gaps between windows", selection: $gap) {
                    Text("20pt").tag(20.0)
                    Text("10pt").tag(10.0)
                    Text("None").tag(0.0)
                }
                Text("Snapping, Tidy up and the screens you build use it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Moving around") {
                Picker("Glides and zooms", selection: $motion) {
                    Text("Match macOS").tag("follow")
                    Text("Animate").tag("glide")
                    Text("Jump").tag("jump")
                }
                Text("Jump goes straight to where a glide or zoom would end. Match macOS jumps when Reduce Motion is on.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(get: { automatic }, set: {
                    Updater.shared.automatic = $0
                    automatic = $0
                }))
                LabeledContent("Expanse \(Updater.shared.currentVersion)") {
                    Button("Check Now", action: checkForUpdates)
                }
            }
            .disabled(!isRelease)
            if !isRelease {
                Text("This is a development build: it has no updates, and opening at login opens this copy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
        // Changed in System Settings meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            openAtLogin = LoginItem.enabled
        }
    }
}
