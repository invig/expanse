import AppKit
import Combine
import SwiftUI

/// What the menu bar icon opens, in place of a menu: a Liquid Glass panel with the canvas at a
/// glance (a live minimap, which opens it), the everyday commands and switches, the hot corner,
/// earlier layouts to go back to, and anything that needs you (a permission, an update). Updates
/// and Open at Login are in Settings (see SettingsWindow).
final class MenuPanel: NSObject, NSWindowDelegate {
    enum Action {
        case toggleCanvas, setPaused(Bool), centreWindow, tidy, restoreAll, restoreLayout(URL), takeSnapshot
        case autoCentre(Bool), wallpaper(Bool), names(Bool), corner(HotCorner.Corner)
        case grantAccessibility, grantScreenRecording, installUpdate
        case detailedLogging(Bool), copyLogs, showLogFile, reportIssue
        case welcome, settings, quit

        /// Switches and picks leave the panel open, to see them take; commands close it, as a
        /// menu would.
        var closesPanel: Bool {
            switch self {
            case .setPaused, .autoCentre, .wallpaper, .names, .corner, .detailedLogging, .takeSnapshot: false
            default: true
            }
        }

        /// The canvas's own commands, which wait until Expanse has started (see AppDelegate.turnOn).
        var needsCanvas: Bool {
            switch self {
            case .toggleCanvas, .setPaused, .centreWindow, .tidy, .restoreAll, .restoreLayout, .takeSnapshot: true
            default: false
            }
        }
    }

    struct State: Equatable {
        /// Started (the walkthrough is done).
        var isOn = false
        var isPaused = false
        /// Zoomed out.
        var isActive = false
        /// Canvas space: every window, and the part of the canvas the screen shows.
        var windows: [CGRect] = []
        var viewport: CGRect = .zero
        var autoCentre = true
        var wallpaper = false
        var names = false
        var corner = HotCorner.Corner.all
        /// Asked of macOS as the panel opens (see MenuPanel.show), not on every refresh: each is a
        /// round trip to it.
        var accessibility = true
        var screenRecording = true
        /// The version of an update that's downloaded and ready to install.
        var update: String?
        var detailedLogging = false
        var hasLogFile = false
    }

    /// An earlier layout (see LayoutStore.snapshots), drawn from its windows.
    struct Layout: Identifiable, Equatable {
        let id: URL
        let date: Date
        let windows: [CGRect]
    }

    final class Model: ObservableObject {
        @Published var state = State()
        @Published var layouts: [Layout] = []
        var perform: (Action) -> Void = { _ in }
        var troubleshoot: () -> Void = {}
    }

    static let width: CGFloat = 360
    /// Concentric with the cards inside: their 16pt corners plus the 10pt between.
    static let radius: CGFloat = 26
    /// Room in the window around the glass for the glass's own shadow, which the window's edges
    /// would otherwise cut off square.
    private static let margin: CGFloat = 24

    private let model = Model()
    private let readState: () -> State
    private let perform: (Action) -> Void
    private weak var button: NSStatusBarButton?
    private lazy var hosting = NSHostingController(rootView: PanelView(model: model))
    private lazy var panel = makePanel()
    private(set) var isShown = false
    private var monitors: [Any] = []
    private var refreshTimer: Timer?
    private var resize: AnyCancellable?
    /// When it last closed: the click on the icon that took its focus, and so closed it, mustn't
    /// open it again.
    private var closedAt: CFTimeInterval = 0
    /// Bumped on every show, so a fade-out that's been overtaken doesn't hide the panel.
    private var shows = 0
    /// The Troubleshooting menu is up: clicks in it aren't clicks outside the panel.
    private var menuOpen = false
    private var permissions = (accessibility: true, screenRecording: true)

    init(button: NSStatusBarButton, state: @escaping () -> State, perform: @escaping (Action) -> Void) {
        self.button = button
        readState = state
        self.perform = perform
        super.init()
        model.perform = { [weak self] in self?.run($0) }
        model.troubleshoot = { [weak self] in self?.showTroubleshooting() }
        button.target = self
        button.action = #selector(clicked)
        // On the press, as a menu opens.
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    @objc private func clicked() {
        if isShown { close() } else if CACurrentMediaTime() - closedAt > 0.3 { show() }
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        shows += 1
        permissions = (AX.isTrusted(prompt: false), CGPreflightScreenCaptureAccess())
        refresh()
        model.layouts = Self.layouts()
        place()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        // Once the click that opened it is done with the button, which would take this off again.
        DispatchQueue.main.async { [weak self] in
            if self?.isShown == true { self?.button?.highlight(true) }
        }
        // Live while it's open: the minimap, the window count, a pause as it finishes.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        // A banner coming or going changes its height: grow or shrink downwards.
        resize = model.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.fit() } }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in self?.close() },
            NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] e in
                if let self, !self.menuOpen, e.window !== self.button?.window,
                   e.window !== self.panel || !self.glassRect.contains(e.locationInWindow) { self.close() }
                return e
            },
        ].compactMap { $0 }
    }

    func close() {
        guard isShown else { return }
        isShown = false
        closedAt = CACurrentMediaTime()
        refreshTimer?.invalidate()
        refreshTimer = nil
        resize = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        button?.highlight(false)
        let panel = panel, shown = shows
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.1; panel.animator().alphaValue = 0 }, completionHandler: { [weak self] in
            if self?.shows == shown { panel.orderOut(nil) }
        })
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func run(_ action: Action) {
        guard !action.needsCanvas || model.state.isOn else { return }
        if action.closesPanel { close() }
        perform(action)
        refresh()
        // The new one, in front of the others.
        if case .takeSnapshot = action { model.layouts = Self.layouts() }
    }

    private func refresh() {
        var state = readState()
        (state.accessibility, state.screenRecording) = permissions
        if state != model.state { model.state = state }
    }

    private static func layouts() -> [Layout] {
        LayoutStore.snapshots().compactMap { snapshot in
            LayoutStore.load(snapshot).map { layout in
                // What was on the canvas, as the minimap showed it: not the spots kept for
                // windows out of view (see SavedLayout.Window.away).
                Layout(id: snapshot.url, date: snapshot.date, windows: layout.windows.compactMap { w in
                    guard w.away != true, let width = w.w, let height = w.h else { return nil }
                    return CGRect(x: w.x, y: w.y, width: width, height: height)
                })
            }
        }
    }

    /// The glass, in the window's coordinates.
    private var glassRect: CGRect { (panel.contentView?.bounds ?? .zero).insetBy(dx: Self.margin, dy: Self.margin) }

    /// Under the icon, a little below the menu bar, and kept on screen.
    private func place() {
        let size = hosting.sizeThatFits(in: CGSize(width: Self.width, height: 10_000))
        guard let icon = button?.window?.frame, let screen = button?.window?.screen ?? NSScreen.main else { return }
        let usable = screen.visibleFrame
        let x = min(max(icon.midX - size.width / 2, usable.minX + 8), usable.maxX - size.width - 8)
        let top = min(icon.minY, usable.maxY) - 6
        let glass = CGRect(x: x.rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
        panel.setFrame(glass.insetBy(dx: -Self.margin, dy: -Self.margin), display: true)
    }

    private func fit() {
        guard isShown else { return }
        let height = hosting.sizeThatFits(in: CGSize(width: Self.width, height: 10_000)).height + 2 * Self.margin
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    /// A native menu, under the pointer.
    private func showTroubleshooting() {
        let state = model.state
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ClosureItem("Detailed Logging", checked: state.detailedLogging) { [weak self] in
            self?.run(.detailedLogging(!state.detailedLogging))
        })
        menu.addItem(ClosureItem("Copy Logs for a Bug Report") { [weak self] in self?.run(.copyLogs) })
        menu.addItem(ClosureItem("Show Log File in Finder", enabled: state.hasLogFile) { [weak self] in self?.run(.showLogFile) })
        menu.addItem(.separator())
        menu.addItem(ClosureItem("Report an Issue on GitHub…") { [weak self] in self?.run(.reportIssue) })
        guard let view = panel.contentView else { return }
        menuOpen = true
        menu.popUp(positioning: nil, at: view.convert(panel.mouseLocationOutsideOfEventStream, from: nil), in: view)
        menuOpen = false
    }

    private func makePanel() -> NSPanel {
        let p = Panel(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 400),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        // The glass draws its own (see margin).
        p.hasShadow = false
        // Over the canvas, as the menu was.
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.animationBehavior = .none
        p.delegate = self
        p.onEscape = { [weak self] in self?.close() }
        hosting.sizingOptions = []
        let content = hosting.view
        let glass: NSView
        if #available(macOS 26, *) {
            let effect = NSGlassEffectView()
            effect.cornerRadius = Self.radius
            effect.contentView = content
            glass = effect
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.maskImage = Self.roundedMask(radius: Self.radius)
            content.frame = material.bounds
            content.autoresizingMask = [.width, .height]
            material.addSubview(content)
            glass = material
            // The material has no shadow of its own: the window's follows its rounded mask.
            p.hasShadow = true
        }
        let container = NSView(frame: CGRect(x: 0, y: 0, width: Self.width + 2 * Self.margin, height: 400 + 2 * Self.margin))
        glass.frame = container.bounds.insetBy(dx: Self.margin, dy: Self.margin)
        glass.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        p.contentView = container
        return p
    }

    /// Rounded corners for the material behind the window (a layer's corner radius doesn't clip it).
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Takes focus without bringing Expanse to the front (as Control Center's panels do), so the
    /// app you're in stays the one ⌃⌥C centres; Escape closes it.
    private final class Panel: NSPanel {
        var onEscape: () -> Void = {}
        override var canBecomeKey: Bool { true }
        override func sendEvent(_ event: NSEvent) {
            if event.type == .keyDown, event.keyCode == 53 { onEscape(); return }
            super.sendEvent(event)
        }
    }

    private final class ClosureItem: NSMenuItem {
        private let run: () -> Void

        init(_ title: String, checked: Bool = false, enabled: Bool = true, run: @escaping () -> Void) {
            self.run = run
            super.init(title: title, action: #selector(fire), keyEquivalent: "")
            target = self
            state = checked ? .on : .off
            isEnabled = enabled
        }

        required init(coder: NSCoder) { fatalError() }

        @objc private func fire() { run() }
    }
}

// MARK: - The panel

private struct PanelView: View {
    @ObservedObject var model: MenuPanel.Model
    private var state: MenuPanel.State { model.state }

    var body: some View {
        VStack(spacing: 8) {
            header
            if !state.accessibility || !state.screenRecording { permissionBanner }
            if let update = state.update {
                Banner(tint: .accentColor, symbol: "arrow.down.circle.fill", title: "Expanse \(update) is ready",
                       detail: "It relaunches, and your windows stay where they are.",
                       button: "Install and Relaunch") { model.perform(.installUpdate) }
            }
            hero
            HStack(spacing: 8) {
                Button { model.perform(.centreWindow) } label: {
                    Tile(symbol: "dot.viewfinder", title: "Centre window") { Keys(["⌃", "⌥", "C"]) }
                }
                .help("The window you're in, to the middle of the screen")
                Button { model.perform(.tidy) } label: {
                    Tile(symbol: "square.grid.2x2", title: "Tidy up") {
                        Text("Line up each group").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .help("Closes gaps and lines up edges, leaving each group where it is")
            }
            .buttonStyle(CardButtonStyle())
            .disabled(!state.isOn || state.isPaused)
            switches
            HotCornerCard(corner: state.corner) { model.perform(.corner($0)) }
            layouts
            footer
        }
        .padding(10)
        .frame(width: MenuPanel.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var status: String {
        if !state.isOn { return "Starts once the walkthrough is done" }
        if state.isPaused { return "Paused · windows back in the macOS layout" }
        let n = state.windows.count
        return "On · \(n) window\(n == 1 ? "" : "s") on the canvas"
    }

    private var header: some View {
        HStack(spacing: 10) {
            // The app's own icon (its artwork has a margin, so it's drawn a little larger), grey
            // while Expanse is off.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
                .saturation(state.isOn && !state.isPaused ? 1 : 0)
                .padding(-3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Expanse").font(.system(size: 13, weight: .semibold))
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("Expanse", isOn: Binding(get: { !state.isPaused }, set: { model.perform(.setPaused(!$0)) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(!state.isOn)
                .help(state.isPaused ? "Resume Expanse" : "Pause Expanse: windows go back to the macOS layout")
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    @ViewBuilder private var permissionBanner: some View {
        let both = !state.accessibility && !state.screenRecording
        let title = both ? "Accessibility and Screen Recording are off"
            : state.accessibility ? "Screen Recording is off" : "Accessibility is off"
        let detail = !state.accessibility ? "Expanse can't move windows without it."
            : "Zoomed out, windows show as outlines without it. Once it's on, reopen Expanse."
        Banner(tint: .orange, symbol: "exclamationmark.triangle.fill", title: title, detail: detail,
               button: "Open System Settings") {
            model.perform(state.accessibility ? .grantScreenRecording : .grantAccessibility)
        }
    }

    /// The canvas as the minimap draws it; it opens the canvas (or, paused, resumes).
    private var hero: some View {
        Button { model.perform(state.isPaused ? .setPaused(false) : .toggleCanvas) } label: {
            VStack(spacing: 0) {
                MapView(windows: state.windows, viewport: state.isPaused ? nil : state.viewport)
                    .padding(EdgeInsets(top: 12, leading: 14, bottom: 2, trailing: 14))
                    .frame(height: 114)
                    .opacity(state.isPaused ? 0.4 : 1)
                HStack(spacing: 6) {
                    Text(state.isPaused ? "Resume Expanse" : state.isActive ? "Back to 100%" : "Open Expanse")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if !state.isPaused { Keys(["⌥", "`"]) }
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
            }
        }
        .buttonStyle(CardButtonStyle())
        .disabled(!state.isOn)
    }

    private var switches: some View {
        VStack(spacing: 0) {
            SwitchRow(title: "Auto-centre focused window", keys: ["⌥", "⇧", "`"],
                      isOn: binding(state.autoCentre) { .autoCentre($0) })
            SwitchRow(title: "Desktop picture background", isOn: binding(state.wallpaper) { .wallpaper($0) })
            SwitchRow(title: "Window names when zoomed out", isOn: binding(state.names) { .names($0) })
        }
        .padding(.vertical, 4)
        .card()
    }

    private var layouts: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Earlier layouts").font(.system(size: 12, weight: .medium))
                Spacer()
                Group {
                    LinkButton(title: "Take snapshot") { model.perform(.takeSnapshot) }
                        .help("Keeps the layout as it is now, to come back to")
                    Text("·").font(.system(size: 11)).foregroundStyle(.tertiary)
                    LinkButton(title: "Restore all windows") { model.perform(.restoreAll) }
                        .help("Brings every window that's out of view back on screen")
                }
                .disabled(!state.isOn || state.isPaused)
            }
            .padding(.horizontal, 2)
            if model.layouts.isEmpty {
                Text("Expanse keeps your last few layouts, 15 minutes apart, to go back to. Take a snapshot to keep this one.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            } else {
                HStack(spacing: 8) {
                    ForEach(model.layouts) { layout in
                        LayoutThumbnail(layout: layout) { model.perform(.restoreLayout(layout.id)) }
                    }
                    Spacer(minLength: 0)
                }
                .disabled(!state.isOn || state.isPaused)
            }
        }
        .padding(10)
        .card()
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(state.accessibility && state.screenRecording ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .padding(.trailing, 6)
            Text(state.accessibility && state.screenRecording ? "Permissions OK" : "Permission needed")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            FooterButton(symbol: "questionmark.circle", help: "Welcome & Shortcuts") { model.perform(.welcome) }
            FooterButton(symbol: "stethoscope", help: "Troubleshooting") { model.troubleshoot() }
            FooterButton(symbol: "gearshape", help: "Settings…") { model.perform(.settings) }
            FooterButton(symbol: "power", help: "Quit Expanse") { model.perform(.quit) }
        }
        .padding(.leading, 8)
    }

    private func binding(_ value: Bool, _ action: @escaping (Bool) -> MenuPanel.Action) -> Binding<Bool> {
        Binding(get: { value }, set: { model.perform(action($0)) })
    }
}

private extension View {
    /// A card on the glass: 16pt corners, 10pt in from the panel's 26.
    func card() -> some View {
        background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A card that's a button: lighter under the pointer, a little smaller while pressed.
private struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Card(configuration: configuration) }

    private struct Card: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .background(Color.primary.opacity(hovered && isEnabled ? 0.1 : 0.055),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovered)
                .onHover { hovered = $0 }
        }
    }
}

private struct Tile<Detail: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder let detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                detail
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

/// Keyboard keys, as on a shortcut cheat sheet.
private struct Keys: View {
    let keys: [String]
    init(_ keys: [String]) { self.keys = keys }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 16, minHeight: 16)
                    .padding(.horizontal, 2)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }
}

private struct SwitchRow: View {
    let title: String
    var keys: [String] = []
    let isOn: Binding<Bool>

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12))
            if !keys.isEmpty { Keys(keys) }
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden().controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }
}

private struct Banner: View {
    let tint: Color
    let symbol: String
    let title: String
    let detail: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(button, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(tint)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Which corner opens Expanse: All, Off, or a corner of the little screen.
private struct HotCornerCard: View {
    let corner: HotCorner.Corner
    let pick: (HotCorner.Corner) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hot corner").font(.system(size: 12, weight: .medium))
                    Text("Rest the pointer there to open Expanse")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Pill(title: "All corners", selected: corner == .all) { pick(.all) }
                    Pill(title: "Off", selected: corner == .off) { pick(.off) }
                }
            }
            .padding(.leading, 2)
            Spacer(minLength: 0)
            screen
        }
        .padding(10)
        .card()
    }

    /// Concentric with the card: 6pt corners, 10pt in from its 16.
    private var screen: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return shape
            .fill(Color.primary.opacity(0.05))
            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 6) }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.22), lineWidth: 1))
            .overlay(alignment: .topLeading) { dot(.topLeft, "Top left") }
            .overlay(alignment: .topTrailing) { dot(.topRight, "Top right") }
            .overlay(alignment: .bottomLeading) { dot(.bottomLeft, "Bottom left") }
            .overlay(alignment: .bottomTrailing) { dot(.bottomRight, "Bottom right") }
            .frame(width: 116, height: 76)
    }

    private func dot(_ c: HotCorner.Corner, _ name: String) -> some View {
        let lit = corner == .all || corner == c
        return Button { pick(c) } label: {
            Circle()
                .fill(lit ? Color.accentColor : Color.clear)
                .overlay(Circle().strokeBorder(lit ? Color.clear : Color.primary.opacity(0.35), lineWidth: 1.5))
                .frame(width: 10, height: 10)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(name) corner")
        .help(name)
    }
}

/// Accent text, underlined under the pointer. (The system's link style is too dim on dark glass.)
private struct LinkButton: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .underline(hovered && isEnabled)
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(PressStyle())
        .onHover { hovered = $0 }
    }
}

private struct Pill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.08)), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// A little smaller while pressed.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct LayoutThumbnail: View {
    let layout: MenuPanel.Layout
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                MapView(windows: layout.windows, viewport: nil)
                    .padding(6)
                    .frame(width: 100, height: 60)
                    .background(Color.primary.opacity(hovered && isEnabled ? 0.1 : 0.06), in: shape)
                    .overlay(shape.strokeBorder(Color.accentColor, lineWidth: 2).opacity(hovered && isEnabled ? 1 : 0))
                VStack(alignment: .leading, spacing: 0) {
                    Text(ago).font(.system(size: 11, weight: .medium))
                    Text(time).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .lineLimit(1)
                .padding(.leading, 2)
            }
            .frame(width: 100, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help("Put the windows back where they were \(ago.lowercased())")
    }

    /// "12 minutes ago", "Just now".
    private var ago: String {
        guard Date().timeIntervalSince(layout.date) >= 60 else { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let text = formatter.localizedString(for: layout.date, relativeTo: Date())
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "9:29 am", or "Yesterday, 9:29 am".
    private var time: String {
        let formatter = DateFormatter()
        formatter.dateStyle = Calendar.current.isDateInToday(layout.date) ? .none : .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: layout.date)
    }
}

/// Windows as blocks, fitted to the space, as the minimap draws them; the viewport, if given,
/// in the accent colour.
private struct MapView: View {
    let windows: [CGRect]
    let viewport: CGRect?

    var body: some View {
        Canvas { context, size in
            // Room for the viewport's ring, drawn outside it.
            let area = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
            guard var bounds = viewport ?? windows.first else { return }
            bounds = windows.reduce(bounds) { $0.union($1) }
            guard bounds.width > 0, bounds.height > 0, area.width > 0, area.height > 0 else { return }
            bounds = bounds.insetBy(dx: -bounds.width * 0.03, dy: -bounds.height * 0.03)
            let scale = min(area.width / bounds.width, area.height / bounds.height)
            let offset = CGPoint(x: area.minX + (area.width - bounds.width * scale) / 2,
                                 y: area.minY + (area.height - bounds.height * scale) / 2)
            func map(_ r: CGRect) -> CGRect {
                CGRect(x: offset.x + (r.minX - bounds.minX) * scale, y: offset.y + (r.minY - bounds.minY) * scale,
                       width: max(r.width * scale, 1), height: max(r.height * scale, 1))
            }
            // Never so small it can't be found.
            let shown = viewport.map { v -> CGRect in
                let m = map(v)
                return m.insetBy(dx: min(0, (m.width - 16) / 2), dy: min(0, (m.height - 10) / 2))
            }
            if let shown {
                context.fill(Path(roundedRect: shown, cornerRadius: 3, style: .continuous),
                             with: .color(Color.accentColor.opacity(0.12)))
            }
            for w in windows {
                let m = map(w)
                let path = Path(roundedRect: m, cornerRadius: min(3, max(1, min(m.width, m.height) * 0.15)), style: .continuous)
                context.fill(path, with: .color(Color.primary.opacity(0.24)))
                context.stroke(path, with: .color(Color.primary.opacity(0.3)), lineWidth: 0.5)
            }
            if let shown {
                context.stroke(Path(roundedRect: shown.insetBy(dx: -2.5, dy: -2.5), cornerRadius: 5.5, style: .continuous),
                               with: .color(Color.accentColor), lineWidth: 2)
            }
        }
    }
}

private struct FooterButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(hovered ? Color.primary : Color.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(hovered ? 0.08 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(help)
        .accessibilityLabel(help)
    }
}
