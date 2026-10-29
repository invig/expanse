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
    private let isRelease = Updater.shared.isRelease

    var body: some View {
        Form {
            Section {
                Toggle("Open Expanse at login", isOn: Binding(get: { openAtLogin }, set: { _ in
                    LoginItem.toggle()
                    openAtLogin = LoginItem.enabled
                }))
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
