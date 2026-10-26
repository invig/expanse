import AppKit
import QuartzCore
import ScreenCaptureKit

/// Owns the canvas: which windows are on it, the camera, and the two modes.
///
/// Live mode: camera scale is 1 and real windows sit exactly where the camera says.
/// Windows outside the viewport are parked in the bottom-right screen corner. The overlay
/// sinks below all app windows and becomes the desktop: the canvas backdrop, plus proxies
/// for parked windows. Scrolling or pinching on it switches to canvas mode.
///
/// Canvas mode: the overlay rises above everything and draws every window from its live
/// capture stream, so panning and zooming never touches the real windows. Leaving canvas
/// mode animates back to scale 1 and commits real window positions with the Accessibility API.
final class CanvasController: NSObject {
    private(set) var windows: [ManagedWindow] = [] // back to front
    var camera = Camera()
    private(set) var isActive = false
    /// Paused: windows are back in their original macOS layout and Canvas leaves them alone.
    private(set) var isPaused = false

    let view: CanvasView
    private let overlay: OverlayWindow

    private var syncTimer: Timer?
    private var syncing = false
    private var pendingSyncCompletions: [() -> Void] = []
    private var firstSync = true
    private var resolutionWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?
    private var pinchAccumulator: CGFloat = 0
    private var magnifyMonitor: Any?
    private var observers: [pid_t: AppObserver] = [:]
    private var syncSoonWork: DispatchWorkItem?
    private var saved: SavedLayout?
    private var savedPool: [SavedLayout.Window] = []
    private var lastSavedLayout: Data?
    let hotCorner = HotCorner()
    /// Canvas spots of windows that disappeared (minimized, app hidden, closed). Window IDs
    /// are never reused, so a returning ID means the same window coming back.
    private var recentlyRemoved: [CGWindowID: CGRect] = [:]
    private var wallpaperTimer: Timer?
    private var lastWallpaperRefresh: CFTimeInterval = 0

    private struct CameraAnimation {
        var from: Camera
        var to: Camera
        var start: CFTimeInterval
        var duration: CFTimeInterval
        var completion: (() -> Void)?
    }
    private var animation: CameraAnimation?
    private var displayLink: CADisplayLink?

    static let liveFPS = 4
    static let canvasFPS = 60

    override init() {
        view = CanvasView(frame: .zero)
        overlay = OverlayWindow()
        super.init()
        overlay.contentView = view
        view.controller = self
        saved = LayoutStore.load()
        savedPool = saved?.windows ?? []
        updateOverlayFrame()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: Geometry

    /// The primary display (the one with the menu bar). Multi-display comes later.
    var screen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }

    /// canvas://screen?w=&h= pretends the display is this size, to exercise display changes.
    private var screenOverride: CGSize?

    private var screenSize: CGSize { screenOverride ?? screen.frame.size }

    /// The overlay area in global CG coordinates (top-left origin, y down): the screen minus the menu bar.
    var viewport: CGRect {
        let f = screen.frame
        let menuBar = max(0, f.maxY - screen.visibleFrame.maxY)
        return CGRect(x: 0, y: menuBar, width: screenSize.width, height: screenSize.height - menuBar)
    }

    private var screenRectCG: CGRect { CGRect(origin: .zero, size: screenSize) }

    /// Where parked windows go: only their top-left pixel stays on screen.
    private var parkPoint: CGPoint { CGPoint(x: screenRectCG.maxX - 1, y: screenRectCG.maxY - 1) }

    private var viewSize: CGSize { viewport.size }

    private func canvasPoint(forGlobal g: CGPoint) -> CGPoint {
        camera.toCanvas(CGPoint(x: g.x - viewport.minX, y: g.y - viewport.minY))
    }

    private func updateOverlayFrame() {
        let f = screen.frame
        let vp = viewport
        overlay.setFrame(NSRect(x: f.minX + vp.minX, y: f.maxY - vp.maxY, width: vp.width, height: vp.height), display: false)
        view.menuBarHeight = vp.minY
    }

    // MARK: Display changes

    private var lastViewportSize: CGSize = .zero
    /// True while displays are changing: macOS shoves windows around and we must not
    /// mistake that for the user moving them.
    private var suspendTracking = false
    private var relayoutWork: [DispatchWorkItem] = []
    /// After a display change macOS keeps moving windows for a while (it restores each window's
    /// remembered spot for that display). Until then, moves are reverted instead of adopted.
    private var settleUntil = Date.distantPast
    private var reassertWork: DispatchWorkItem?
    private var focusSettleWork: DispatchWorkItem?
    static let settleDuration: TimeInterval = 6

    private func registerDisplayCallback() {
        CGDisplayRegisterReconfigurationCallback({ _, flags, info in
            guard let info else { return }
            let me = Unmanaged<CanvasController>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async {
                if flags.contains(.beginConfigurationFlag) { me.displaysWillChange() } else { me.scheduleRelayout() }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func displaysWillChange() {
        suspendTracking = true
        settleUntil = .distantFuture
        relayoutWork.forEach { $0.cancel() }
    }

    @objc private func screensChanged() {
        displaysWillChange()
        scheduleRelayout()
    }

    func simulateScreen(_ size: CGSize?) {
        screenOverride = size
        displaysWillChange()
        scheduleRelayout(delay: 0.1)
    }

    /// Wait for macOS to finish rearranging windows, then put every window back where the
    /// canvas says. A second pass catches windows macOS moved late.
    private func scheduleRelayout(delay: TimeInterval = 1.0) {
        suspendTracking = true
        relayoutWork.forEach { $0.cancel() }
        let first = DispatchWorkItem { [weak self] in self?.relayout(final: false) }
        let second = DispatchWorkItem { [weak self] in self?.relayout(final: true) }
        relayoutWork = [first, second]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: first)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.5, execute: second)
    }

    private func relayout(final: Bool) {
        let newSize = viewSize
        if newSize != lastViewportSize, lastViewportSize != .zero {
            // Whatever was in the middle of the old screen stays in the middle of the new one.
            let center = camera.center(in: lastViewportSize)
            camera = Camera.centered(on: center, scale: camera.scale, viewSize: newSize)
            if !isActive { camera.origin = CGPoint(x: camera.origin.x.rounded(), y: camera.origin.y.rounded()) }
            logger.info("display changed: \(NSStringFromSize(self.lastViewportSize), privacy: .public) -> \(NSStringFromSize(newSize), privacy: .public)")
        }
        lastViewportSize = newSize
        updateOverlayFrame()
        if final { refreshWallpaper() }
        // Whatever macOS did to the real windows, re-place all of them.
        windows.forEach { $0.lastPlaced = nil }
        if !isActive { commit() }
        view.render()
        if final {
            settleUntil = Date().addingTimeInterval(Self.settleDuration)
            let end = DispatchWorkItem { [weak self] in
                guard let self, Date() >= self.settleUntil else { return }
                self.suspendTracking = false
                logger.info("display change settled")
            }
            relayoutWork.append(end)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDuration, execute: end)
        }
    }

    /// A window moved while displays are settling: put everything back where the canvas says.
    private func reassertSoon() {
        reassertWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isActive, !self.isPaused, self.suspendTracking else { return }
            logger.info("re-placing windows moved by macOS during a display change")
            self.windows.forEach { $0.lastPlaced = nil }
            self.commit()
            self.view.render()
        }
        reassertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: Lifecycle

    func start() {
        lastViewportSize = viewSize
        registerDisplayCallback()
        sync()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.sync() }
        magnifyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .magnify) { [weak self] event in
            self?.handleGlobalPinch(event)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        overlay.level = OverlayWindow.backdropLevel
        overlay.orderFrontRegardless()

        hotCorner.onTrigger = { [weak self] in
            guard let self, !self.isPaused else { return }
            self.toggle()
        }
        hotCorner.start()

        refreshWallpaper()
        // Dynamic wallpapers change through the day; Spaces can each have their own picture.
        wallpaperTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refreshWallpaper() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.refreshWallpaper()
        }
    }

    func refreshWallpaper() {
        lastWallpaperRefresh = CACurrentMediaTime()
        guard Wallpaper.enabled else { view.setWallpaper(nil); return }
        Wallpaper.capture(screen: screen) { [weak self] image in
            guard Wallpaper.enabled else { return }
            self?.view.setWallpaper(image)
        }
    }

    /// ⌘-Tab / Dock to an app whose window is parked: jump the canvas to that window.
    @objc private func appActivated(_ note: Notification) {
        guard !isPaused, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != getpid(),
              let focused = AX.focusedWindow(pid: app.processIdentifier),
              let id = AX.windowID(focused) else { return }
        windowFocused(id)
    }

    /// A window got focus (click, ⌘-Tab, Dock). Focus often bounces between windows for a moment
    /// (opening a document focuses the old window, then the new one), so act on where it settles.
    private func windowFocused(_ id: CGWindowID) {
        focusSettleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.focusSettled() }
        focusSettleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// If the focused window isn't fully on screen, glide to center it.
    private func focusSettled() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              let focused = AX.focusedWindow(pid: app.processIdentifier), let id = AX.windowID(focused) else { return }
        guard !isActive, !isPaused, !suspendTracking, animation == nil,
              let w = windows.first(where: { $0.id == id }) else { return }
        let r = camera.toView(w.canvasFrame)
        let fullyVisible = !w.parked && CGRect(origin: .zero, size: viewSize).insetBy(dx: -1, dy: -1).contains(r)
        if !fullyVisible { glide(to: w) }
    }

    /// Center `w` at 100% and make it the active window, from either mode.
    func focus(_ w: ManagedWindow) {
        if isActive { exit(focus: w) } else { glide(to: w) }
    }

    /// Live mode: pan the camera to `w`. The overlay rises at scale 1 (where proxies line up
    /// with the real windows), animates, commits, then sinks again. It never takes key focus,
    /// so typing keeps going to the window that was just clicked.
    private func glide(to w: ManagedWindow) {
        guard !isActive, animation == nil else { return }
        isActive = true
        bringToFront(w)
        fitToScreen(w)
        view.render()
        overlay.level = OverlayWindow.canvasLevel
        overlay.orderFrontRegardless()
        animate(to: focusCamera(for: w), duration: 0.3) { [weak self] in
            guard let self else { return }
            self.commit()
            if let ax = w.ax { AX.raise(ax) }
            NSRunningApplication(processIdentifier: w.pid)?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.overlay.level = OverlayWindow.backdropLevel
                self.isActive = false
                self.view.render()
            }
        }
    }

    // MARK: Live tracking

    private func observe(_ w: ManagedWindow) {
        guard let ax = w.ax else { return }
        if observers[w.pid] == nil {
            observers[w.pid] = AppObserver(pid: w.pid) { [weak self] element, notification in
                self?.handleAXEvent(element, notification)
            }
        }
        observers[w.pid]?.observe(window: ax, id: w.id)
    }

    private func handleAXEvent(_ element: AXUIElement, _ notification: String) {
        switch notification {
        case kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            syncSoon()
        case kAXFocusedWindowChangedNotification:
            if let id = AX.windowID(element) { windowFocused(id) }
        case kAXMovedNotification, kAXResizedNotification:
            guard let id = AX.windowID(element), let w = windows.first(where: { $0.id == id }) else { return }
            realWindowChanged(w, element)
        default:
            break
        }
    }

    /// A real window moved or resized. In live mode, a move we didn't make means the user
    /// dragged it: the canvas follows.
    private func realWindowChanged(_ w: ManagedWindow, _ element: AXUIElement) {
        guard !isPaused else { return }
        if let size = AX.size(element) { adoptSize(w, size) }
        if suspendTracking, !isActive, settleUntil != .distantFuture, Date() < settleUntil,
           let last = w.lastPlaced, let pos = AX.position(element), last.distance(to: pos) > 2 {
            reassertSoon()
        }
        if !isActive, !suspendTracking, animation == nil, let pos = AX.position(element) {
            if let last = w.lastPlaced, last.distance(to: pos) < 2 {
                // Our own placement.
            } else {
                w.lastPlaced = nil
                w.parked = false
                w.canvasFrame.origin = canvasPoint(forGlobal: pos)
            }
        }
        view.render()
        scheduleSave()
    }

    private func syncSoon() {
        syncSoonWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sync() }
        syncSoonWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: Persistence

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// `cleanExit` is true only when windows have just been put back in their original
    /// macOS layout (quit / pause). Otherwise the saved originals are what a crash recovery needs.
    func save(cleanExit: Bool = false) {
        guard !isPaused else { return }
        // Saved positions are canvas coordinates relative to a scale-1 camera.
        let center = camera.center(in: viewSize)
        let layout = SavedLayout(
            cameraX: Double(camera.origin.x), cameraY: Double(camera.origin.y),
            centerX: Double(center.x), centerY: Double(center.y),
            cleanExit: cleanExit,
            windows: windows.map {
                SavedLayout.Window(bundleID: $0.bundleID, appName: $0.appName, title: $0.title,
                                   x: Double($0.canvasFrame.minX), y: Double($0.canvasFrame.minY),
                                   pw: Double($0.preferredSize.width), ph: Double($0.preferredSize.height),
                                   ox: Double($0.originalFrame.minX), oy: Double($0.originalFrame.minY),
                                   ow: Double($0.originalFrame.width), oh: Double($0.originalFrame.height))
            })
        guard let data = try? JSONEncoder().encode(layout), data != lastSavedLayout else { return }
        lastSavedLayout = data
        LayoutStore.save(layout)
    }

    /// ⌥ + pinch-in anywhere opens the canvas.
    private func handleGlobalPinch(_ event: NSEvent) {
        guard !isActive, !isPaused, event.modifierFlags.contains(.option) else { pinchAccumulator = 0; return }
        if event.phase == .began { pinchAccumulator = 0 }
        pinchAccumulator += event.magnification
        if pinchAccumulator < -0.12 {
            pinchAccumulator = 0
            enter(zoomOut: true)
        }
    }

    func toggle() {
        if isPaused { resume(); return }
        isActive ? exit() : enter(zoomOut: true)
    }

    // MARK: Switching in and out

    /// Put every window back exactly where macOS had it before Canvas, and stop managing.
    func pause() {
        guard !isPaused else { return }
        cancelAnimation()
        if isActive {
            isActive = false
            camera = Camera.centered(on: camera.center(in: viewSize), scale: 1, viewSize: viewSize)
        }
        save(cleanExit: true)
        isPaused = true
        restoreOriginals()
        overlay.orderOut(nil)
        for w in windows { remove(w) }
        observers = [:]
        logger.info("paused")
    }

    /// Like a fresh launch: bring the canvas back from the layout saved by pause().
    func resume() {
        guard isPaused else { return }
        isPaused = false
        saved = LayoutStore.load()
        savedPool = saved?.windows ?? []
        firstSync = true
        lastSavedLayout = nil
        overlay.level = OverlayWindow.backdropLevel
        overlay.orderFrontRegardless()
        sync()
        logger.info("resumed")
    }

    private func restoreOriginals() {
        let vp = viewport
        for w in windows {
            guard let ax = w.ax else { continue }
            var r = w.originalFrame
            guard r.width > 0, r.height > 0 else { continue }
            // If the original spot is gone (smaller screen now), bring it back into view.
            if !r.insetBy(dx: 40, dy: 40).intersects(vp) {
                r.origin = CGPoint(x: vp.midX - r.width / 2, y: vp.minY + 40)
            }
            if r.size != w.canvasFrame.size { AX.setSize(ax, r.size) }
            AX.setPosition(ax, r.origin)
            w.lastPlaced = nil
            w.parked = false
        }
    }

    // MARK: Window discovery

    func sync(completion: (() -> Void)? = nil) {
        guard !isPaused else { return }
        if let completion { pendingSyncCompletions.append(completion) }
        guard !syncing else { return }
        syncing = true
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.syncing = false
                if let content, !self.isPaused {
                    self.apply(content.windows)
                } else if let error {
                    logger.error("SCShareableContent failed: \(error.localizedDescription)")
                }
                let completions = self.pendingSyncCompletions
                self.pendingSyncCompletions = []
                completions.forEach { $0() }
            }
        }
    }

    private func isManageable(_ w: SCWindow) -> Bool {
        guard w.windowLayer == 0, w.isOnScreen,
              w.frame.width >= 100, w.frame.height >= 60,
              let app = w.owningApplication, app.processID != getpid(),
              let running = NSRunningApplication(processIdentifier: app.processID),
              running.activationPolicy == .regular
        else { return false }
        return screenRectCG.intersects(w.frame)
    }

    /// The window's true frame. ScreenCaptureKit reports transformed frames during
    /// Mission Control and similar animations; the Accessibility API doesn't.
    private func realFrame(of sc: SCWindow, ax: AXUIElement?) -> CGRect {
        if let ax, let p = AX.position(ax), let s = AX.size(ax), s.width > 0, s.height > 0 {
            return CGRect(origin: p, size: s)
        }
        return sc.frame
    }

    private func isStranded(_ f: CGRect) -> Bool {
        f.minX >= screenRectCG.maxX - 8 && f.minY >= screenRectCG.maxY - 8
    }

    private func apply(_ scWindows: [SCWindow]) {
        let live = !isActive && !suspendTracking
        var seen = Set<CGWindowID>()
        var restoredAny = false
        if firstSync, let saved {
            // Restore the camera first so windows we don't recognise keep their real position.
            if let cx = saved.centerX, let cy = saved.centerY {
                camera = Camera.centered(on: CGPoint(x: cx, y: cy), scale: 1, viewSize: viewSize)
                camera.origin = CGPoint(x: camera.origin.x.rounded(), y: camera.origin.y.rounded())
            } else {
                camera = Camera(origin: CGPoint(x: saved.cameraX, y: saved.cameraY), scale: 1)
            }
        }

        for sc in scWindows where isManageable(sc) {
            seen.insert(sc.windowID)
            if let w = windows.first(where: { $0.id == sc.windowID }) {
                let f = realFrame(of: sc, ax: w.ax)
                w.scWindow = sc
                if let title = sc.title { w.title = title }
                if live {
                    if let last = w.lastPlaced {
                        if last.distance(to: f.origin) > 2 {
                            // Moved behind our back (by the user or the app): follow it.
                            w.parked = false
                            w.lastPlaced = nil
                            w.canvasFrame.origin = canvasPoint(forGlobal: f.origin)
                        }
                    } else {
                        w.canvasFrame.origin = canvasPoint(forGlobal: f.origin)
                    }
                }
                adoptSize(w, f.size)
            } else {
                restoredAny = add(sc, live: live) || restoredAny
            }
        }

        for w in windows where !seen.contains(w.id) {
            remove(w)
        }

        if live { orderByWindowServer() }
        if firstSync && restoredAny {
            commit()
            view.render()
        }
        firstSync = false
        savedPool = []
        if isActive { view.render() }
        scheduleSave()
    }

    /// Returns true if the window was put back where a saved layout had it.
    @discardableResult
    private func add(_ sc: SCWindow, live: Bool) -> Bool {
        let w = ManagedWindow(scWindow: sc, canvasFrame: .zero)
        let f = realFrame(of: sc, ax: w.ax)
        w.preferredSize = f.size
        w.originalFrame = f
        var global = f.origin
        if live {
            w.canvasFrame = CGRect(origin: canvasPoint(forGlobal: global), size: f.size)
        } else {
            let c = camera.center(in: viewSize)
            w.canvasFrame = CGRect(x: c.x - f.width / 2, y: c.y - f.height / 2, width: f.width, height: f.height)
        }

        var restored = false
        if firstSync, let match = LayoutStore.takeMatch(bundleID: w.bundleID, title: w.title, from: &savedPool) {
            w.canvasFrame.origin = CGPoint(x: match.x, y: match.y)
            if let pw = match.pw, let ph = match.ph { w.preferredSize = CGSize(width: pw, height: ph) }
            if saved?.cleanExit != true, let ox = match.ox, let oy = match.oy, let ow = match.ow, let oh = match.oh {
                // Last run didn't put windows back; its record of the macOS layout is the real one.
                w.originalFrame = CGRect(x: ox, y: oy, width: ow, height: oh)
            }
            restored = true
        } else if firstSync && isStranded(f) {
            // Left in the corner by a previous run that didn't exit cleanly.
            global = CGPoint(x: viewport.midX - f.width / 2, y: viewport.minY + 40)
            w.place(at: global)
            w.lastPlaced = nil
            w.canvasFrame.origin = canvasPoint(forGlobal: global)
        }

        // A window opened (or came back) while Canvas is running, not one found at launch.
        let anchor = windows.last { !$0.parked }
        let arriving = !firstSync && !suspendTracking

        windows.append(w)
        w.node.setContentsScale(screen.backingScaleFactor)
        view.addNode(w.node)
        w.capture.onFrame = { [weak w] surface in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            w?.node.content.contents = surface
            CATransaction.commit()
        }
        w.capture.onStop = { [weak self, weak w] in
            guard let self, let w else { return }
            self.remove(w)
        }
        w.capture.start(window: sc, pixelSize: pixelSize(for: w), fps: isActive ? Self.canvasFPS : Self.liveFPS)
        observe(w)
        logger.info("tracking \(w.appName, privacy: .public) [\(w.id)] \(w.title, privacy: .public)")
        if arriving { arrive(w, anchor: anchor, live: live) }
        return restored
    }

    // MARK: New windows

    /// New windows go to an empty spot next to what you were working on; windows coming back
    /// from minimize / hide go back where they were.
    private func arrive(_ w: ManagedWindow, anchor: ManagedWindow?, live: Bool) {
        if let back = recentlyRemoved.removeValue(forKey: w.id) {
            w.canvasFrame.origin = back.origin
        } else if AX.subrole(w.ax) == kAXStandardWindowSubrole as String, let spot = freeSpot(for: w, near: anchor) {
            w.canvasFrame.origin = spot
            logger.info("placed new window \(w.appName, privacy: .public) at \(NSStringFromPoint(spot), privacy: .public)")
        } else {
            return
        }
        guard live else { view.render(); return }
        let r = camera.toView(w.canvasFrame)
        if CGRect(origin: .zero, size: viewSize).contains(r) {
            w.place(at: CGPoint(x: (r.minX + viewport.minX).rounded(), y: (r.minY + viewport.minY).rounded()))
            w.parked = false
            view.render()
        } else {
            glideWhenIdle(to: w)
        }
        scheduleSave()
    }

    /// Opening a window usually activates its app, which may already be gliding somewhere;
    /// wait for that to finish rather than dropping this glide.
    private func glideWhenIdle(to w: ManagedWindow, attempts: Int = 20) {
        guard !isPaused, windows.contains(where: { $0 === w }) else { return }
        if !isActive && animation == nil {
            glide(to: w)
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.glideWhenIdle(to: w, attempts: attempts - 1)
            }
        }
    }

    /// The nearest canvas position for `w` that overlaps nothing: beside, below, left of or above
    /// existing windows, closest to the anchor. Spots already on screen win.
    private func freeSpot(for w: ManagedWindow, near anchor: ManagedWindow?) -> CGPoint? {
        let others = windows.filter { $0 !== w }.map(\.canvasFrame)
        guard !others.isEmpty else { return nil }
        let gap: CGFloat = 24
        let size = w.canvasFrame.size
        let target = anchor?.canvasFrame.center ?? camera.center(in: viewSize)
        let visible = camera.toCanvas(CGRect(origin: .zero, size: viewSize))

        // Neighbours of the windows nearest the anchor; nudged by direction so ties go right, then down.
        let nearest = others.sorted { $0.center.distance(to: target) < $1.center.distance(to: target) }.prefix(12)
        var candidates: [(CGPoint, CGFloat)] = []
        for o in nearest {
            candidates.append((CGPoint(x: o.maxX + gap, y: o.minY), 0))
            candidates.append((CGPoint(x: o.minX, y: o.maxY + gap), 40))
            candidates.append((CGPoint(x: o.minX - gap - size.width, y: o.minY), 80))
            candidates.append((CGPoint(x: o.minX, y: o.minY - gap - size.height), 120))
        }

        var best: (CGPoint, CGFloat)?
        for (origin, bias) in candidates {
            let r = CGRect(origin: origin, size: size)
            if others.contains(where: { $0.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(r) }) { continue }
            let score = r.center.distance(to: target) + bias + (visible.contains(r) ? 0 : 1500)
            if score < (best?.1 ?? .infinity) { best = (origin, score) }
        }
        return best.map { CGPoint(x: $0.0.x.rounded(), y: $0.0.y.rounded()) }
    }

    private func remove(_ w: ManagedWindow) {
        guard windows.contains(where: { $0 === w }) else { return }
        w.capture.stop()
        observers[w.pid]?.forget(w.id)
        view.removeNode(w.node)
        windows.removeAll { $0 === w }
        if !isPaused { recentlyRemoved[w.id] = w.canvasFrame }
        if view.hovered === w { view.hovered = nil }
        if isActive { view.render() }
    }

    /// Match canvas stacking to the real window stacking (front-most last).
    private func orderByWindowServer() {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return }
        var rank: [CGWindowID: Int] = [:]
        for (i, entry) in info.enumerated() {
            if let n = entry[kCGWindowNumber as String] as? Int { rank[CGWindowID(n)] = i }
        }
        let sorted = windows.sorted { (rank[$0.id] ?? .max) > (rank[$1.id] ?? .max) }
        guard sorted.map(\.id) != windows.map(\.id) else { return }
        windows = sorted
        for w in windows { view.bringToFront(w.node) }
    }

    // MARK: Capture resolution

    /// Streams are captured at roughly the on-screen pixel size, in power-of-two steps.
    private func pixelSize(for w: ManagedWindow) -> CGSize {
        let backing = screen.backingScaleFactor
        var factor: CGFloat = 1
        if isActive {
            let s = camera.scale
            factor = s >= 0.7 ? 1 : s >= 0.35 ? 0.5 : 0.25
        }
        return CGSize(width: w.canvasFrame.width * backing * factor, height: w.canvasFrame.height * backing * factor)
    }

    private func updateCapture(_ w: ManagedWindow) {
        w.capture.update(pixelSize: pixelSize(for: w), fps: isActive ? Self.canvasFPS : Self.liveFPS)
    }

    private func scheduleResolutionUpdate() {
        resolutionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.windows.forEach(self.updateCapture)
        }
        resolutionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: Modes

    func enter(zoomOut: Bool) {
        if isActive {
            if zoomOut { animate(to: overviewCamera()) }
            return
        }
        sync { [weak self] in
            guard let self, !self.isActive else { return }
            self.isActive = true
            self.camera.scale = 1
            self.updateOverlayFrame()
            self.view.render()
            self.windows.forEach(self.updateCapture)
            if CACurrentMediaTime() - self.lastWallpaperRefresh > 30 { self.refreshWallpaper() }
            NSApp.activate(ignoringOtherApps: true)
            self.overlay.level = OverlayWindow.canvasLevel
            self.overlay.makeKeyAndOrderFront(nil)
            self.overlay.makeFirstResponder(self.view)
            if zoomOut { self.animate(to: self.overviewCamera()) }
        }
    }

    /// Animate to 100% (onto `focus` if given), put real windows where the camera says, drop the overlay.
    func exit(focus: ManagedWindow? = nil) {
        guard isActive else { return }
        let target: Camera
        if let focus {
            bringToFront(focus)
            fitToScreen(focus)
            target = focusCamera(for: focus)
        } else {
            target = Camera.centered(on: camera.center(in: viewSize), scale: 1, viewSize: viewSize)
        }
        animate(to: target, duration: 0.32) { [weak self] in
            guard let self else { return }
            self.commit()
            let toFocus = focus ?? self.windows.last(where: { !$0.parked })
            if let toFocus {
                if let ax = toFocus.ax { AX.raise(ax) }
                NSRunningApplication(processIdentifier: toFocus.pid)?.activate()
            }
            // Give the window server a beat to show the moved windows, then sink the overlay
            // beneath them so it becomes the desktop.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.overlay.level = OverlayWindow.backdropLevel
                self.isActive = false
                self.view.render()
                self.windows.forEach(self.updateCapture)
            }
        }
    }

    /// Requires camera.scale == 1.
    private func commit() {
        let vp = viewport
        for w in windows {
            let r = camera.toView(w.canvasFrame).offsetBy(dx: vp.minX, dy: vp.minY)
            let target = CGPoint(x: r.minX.rounded(), y: r.minY.rounded())
            let visible = r.intersection(vp)
            // macOS won't put a title bar above the menu bar; it would shove the window down.
            // Such windows stay parked and the backdrop draws them where they belong.
            let topClipped = r.minY < vp.minY - 1
            if !topClipped, !visible.isNull, visible.width >= 48, visible.height >= 48 {
                w.place(at: target)
                w.parked = false
            } else {
                w.place(at: parkPoint)
                w.parked = true
            }
        }
        scheduleSave()
    }

    /// Bring every parked window back on screen. Called on quit and from the menu.
    func restoreAll() {
        var i = 0
        let vp = viewport
        for w in windows where w.parked {
            let p = CGPoint(x: vp.midX - w.canvasFrame.width / 2 + CGFloat(i % 8) * 28,
                            y: vp.minY + 40 + CGFloat(i % 8) * 28)
            w.place(at: p)
            w.parked = false
            if !isActive { w.canvasFrame.origin = canvasPoint(forGlobal: w.lastPlaced ?? p) }
            i += 1
        }
    }

    func shutdown() {
        if !isPaused {
            save(cleanExit: true)
            isPaused = true
            restoreOriginals()
        }
        overlay.orderOut(nil)
        windows.forEach { $0.capture.stop() }
    }

    /// canvas://dump — geometry for debugging alignment between proxies and real windows.
    func dump() {
        logger.info("dump viewport=\(NSStringFromRect(self.viewport), privacy: .public) overlay=\(NSStringFromRect(self.overlay.frame), privacy: .public) view=\(NSStringFromRect(self.view.bounds), privacy: .public) camera=\(NSStringFromPoint(self.camera.origin), privacy: .public)@\(self.camera.scale) active=\(self.isActive)")
        for w in windows {
            let axPos = w.ax.flatMap(AX.position).map { NSStringFromPoint($0) } ?? "nil"
            logger.info("dump \(w.appName, privacy: .public)[\(w.id)] sc=\(NSStringFromRect(w.scWindow.frame), privacy: .public) ax=\(axPos, privacy: .public) canvas=\(NSStringFromRect(w.canvasFrame), privacy: .public) layer=\(NSStringFromRect(w.node.container.frame), privacy: .public) parked=\(w.parked) lastPlaced=\(w.lastPlaced.map { NSStringFromPoint($0) } ?? "nil", privacy: .public)")
        }
    }

    // MARK: Camera targets

    func overviewCamera() -> Camera {
        fitCamera(maxScale: 0.6)
    }

    func fitCamera(maxScale: CGFloat = 1) -> Camera {
        guard !windows.isEmpty else { return Camera.centered(on: camera.center(in: viewSize), scale: 0.5, viewSize: viewSize) }
        let bounds = windows.map(\.canvasFrame).reduce(windows[0].canvasFrame) { $0.union($1) }
            .insetBy(dx: -80, dy: -80)
        let s = min(viewSize.width / bounds.width, viewSize.height / bounds.height, maxScale)
        return Camera.centered(on: bounds.center, scale: max(s, Camera.minScale), viewSize: viewSize)
    }

    /// Shrink a window that doesn't fit the screen; grow it back toward the size the user chose.
    private func fitToScreen(_ w: ManagedWindow) {
        let margin: CGFloat = 16
        let target = CGSize(width: min(w.preferredSize.width, viewSize.width - margin * 2).rounded(),
                            height: min(w.preferredSize.height, viewSize.height - margin * 2).rounded())
        guard let ax = w.ax,
              abs(target.width - w.canvasFrame.width) > 1 || abs(target.height - w.canvasFrame.height) > 1 else { return }
        AX.setSize(ax, target)
        let actual = AX.size(ax) ?? target
        w.lastSized = actual
        let c = w.canvasFrame.center
        w.canvasFrame = CGRect(x: c.x - actual.width / 2, y: c.y - actual.height / 2, width: actual.width, height: actual.height)
        updateCapture(w)
    }

    /// Takes on a size change of the real window. Resizes we didn't make become the
    /// window's preferred size.
    private func adoptSize(_ w: ManagedWindow, _ size: CGSize) {
        guard size != w.canvasFrame.size, size.width > 0, size.height > 0 else { return }
        w.canvasFrame.size = size
        let ours = w.lastSized.map { abs($0.width - size.width) < 2 && abs($0.height - size.height) < 2 } ?? false
        if !ours && !suspendTracking {
            w.preferredSize = size
            w.lastSized = nil
        }
        updateCapture(w)
    }

    /// Scale 1 with the window centered (top-aligned if it's taller than the screen).
    func focusCamera(for w: ManagedWindow) -> Camera {
        let size = w.canvasFrame.size
        let x = (viewSize.width - size.width) / 2
        let y = size.height > viewSize.height ? 0 : (viewSize.height - size.height) / 2
        return Camera(origin: CGPoint(x: (w.canvasFrame.minX - x).rounded(), y: (w.canvasFrame.minY - y).rounded()), scale: 1)
    }

    // MARK: Camera manipulation (called by the view)

    func pan(by d: CGVector) {
        guard isActive else { return }
        cancelAnimation()
        camera.pan(by: d)
        cameraChanged()
    }

    func zoom(by factor: CGFloat, at anchor: CGPoint) {
        guard isActive else { return }
        cancelAnimation()
        camera.zoom(to: camera.scale * factor, anchor: anchor)
        cameraChanged()
    }

    func center(on canvasPoint: CGPoint) {
        guard isActive else { return }
        cancelAnimation()
        camera = Camera.centered(on: canvasPoint, scale: camera.scale, viewSize: viewSize)
        cameraChanged()
    }

    func toggleOverview(at anchor: CGPoint) {
        if camera.scale < 0.95 {
            var target = camera
            target.zoom(to: 1, anchor: anchor)
            animate(to: target)
        } else {
            animate(to: overviewCamera())
        }
    }

    func zoomAnimated(to scale: CGFloat) {
        var target = camera
        target.zoom(to: scale, anchor: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
        animate(to: target)
    }

    private func cameraChanged() {
        view.render()
        scheduleResolutionUpdate()
    }

    // MARK: Animation

    func animate(to target: Camera, duration: CFTimeInterval = 0.38, completion: (() -> Void)? = nil) {
        animation = CameraAnimation(from: camera, to: target, start: CACurrentMediaTime(), duration: duration, completion: completion)
        if displayLink == nil {
            let link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    func cancelAnimation() {
        animation = nil
        stopDisplayLink()
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let a = animation else { stopDisplayLink(); return }
        let t = min(1, (CACurrentMediaTime() - a.start) / a.duration)
        let e = 1 - pow(1 - t, 3) // ease-out cubic
        let s = exp(lerp(log(a.from.scale), log(a.to.scale), e))
        let c0 = a.from.center(in: viewSize), c1 = a.to.center(in: viewSize)
        camera = Camera.centered(on: CGPoint(x: lerp(c0.x, c1.x, e), y: lerp(c0.y, c1.y, e)), scale: s, viewSize: viewSize)
        if t >= 1 {
            camera = a.to
            animation = nil
            stopDisplayLink()
            cameraChanged()
            a.completion?()
        } else {
            view.render()
        }
    }

    // MARK: Windows on the canvas

    func window(atView p: CGPoint, parkedOnly: Bool = false) -> ManagedWindow? {
        let c = camera.toCanvas(p)
        return windows.last { $0.canvasFrame.contains(c) && (!parkedOnly || $0.parked) }
    }

    func bringToFront(_ w: ManagedWindow) {
        guard windows.last !== w else { return }
        windows.removeAll { $0 === w }
        windows.append(w)
        view.bringToFront(w.node)
    }

    func close(_ w: ManagedWindow) {
        if let ax = w.ax { AX.close(ax) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.sync() }
    }

    /// Snap a dragged window's edges and centers to other windows. Returns guide lines in canvas space.
    func snap(_ f: CGRect, for w: ManagedWindow) -> (CGRect, [(CGPoint, CGPoint)]) {
        let threshold = 8 / camera.scale
        let gap: CGFloat = 24
        var bestX: (dist: CGFloat, delta: CGFloat, line: CGFloat?)?
        var bestY: (dist: CGFloat, delta: CGFloat, line: CGFloat?)?
        let others = windows.filter { $0 !== w }.map(\.canvasFrame)

        func consider(_ a: CGFloat, _ b: CGFloat, line: CGFloat?, into best: inout (dist: CGFloat, delta: CGFloat, line: CGFloat?)?) {
            let d = b - a
            if abs(d) < threshold, abs(d) < (best?.dist ?? .infinity) { best = (abs(d), d, line) }
        }
        for r in others {
            for a in [f.minX, f.midX, f.maxX] {
                for b in [r.minX, r.midX, r.maxX] { consider(a, b, line: b, into: &bestX) }
            }
            consider(f.minX, r.maxX + gap, line: nil, into: &bestX)
            consider(f.maxX, r.minX - gap, line: nil, into: &bestX)
            for a in [f.minY, f.midY, f.maxY] {
                for b in [r.minY, r.midY, r.maxY] { consider(a, b, line: b, into: &bestY) }
            }
            consider(f.minY, r.maxY + gap, line: nil, into: &bestY)
            consider(f.maxY, r.minY - gap, line: nil, into: &bestY)
        }

        var out = f
        if let bx = bestX { out.origin.x += bx.delta }
        if let by = bestY { out.origin.y += by.delta }

        var lines: [(CGPoint, CGPoint)] = []
        if let x = bestX?.line {
            let aligned = others.filter { [$0.minX, $0.midX, $0.maxX].contains { abs($0 - x) < 0.5 } } + [out]
            lines.append((CGPoint(x: x, y: aligned.map(\.minY).min()!), CGPoint(x: x, y: aligned.map(\.maxY).max()!)))
        }
        if let y = bestY?.line {
            let aligned = others.filter { [$0.minY, $0.midY, $0.maxY].contains { abs($0 - y) < 0.5 } } + [out]
            lines.append((CGPoint(x: aligned.map(\.minX).min()!, y: y), CGPoint(x: aligned.map(\.maxX).max()!, y: y)))
        }
        return (out, lines)
    }
}

final class OverlayWindow: NSWindow {
    /// Canvas mode: just under the menu bar, above every app window and the Dock.
    static let canvasLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
    /// Live mode: below every app window. Not a desktop-level window: under the menu bar macOS
    /// treats those as wallpaper and adds its legibility shadow, which flickers as apps switch.
    static let backdropLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        level = OverlayWindow.backdropLevel
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
