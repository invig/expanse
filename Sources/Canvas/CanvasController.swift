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

    /// Glide to center a focused window that isn't fully on screen. Toggled with ⌥⇧`.
    var autoCentre: Bool {
        get { UserDefaults.standard.object(forKey: "autoCentre") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCentre") }
    }
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
        var frames = 0
        var firstFrame: CFTimeInterval = 0
        var lastFrame: CFTimeInterval = 0
        var maxGap: CFTimeInterval = 0
    }
    private var lastAnimationStats = "-"
    private var activationRequest: (pid: pid_t, at: CFTimeInterval)?
    private var animation: CameraAnimation?
    private var displayLink: CADisplayLink?

    static let liveFPS = 4
    /// Window pictures on the zoomed-out canvas: plenty for thumbnails, half the work of 60.
    static let canvasFPS = 30

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
    var screen: NSScreen {
        // With the lid shut and no external display there can briefly be no screen at all;
        // keep using the last one until a screen appears.
        if let s = NSScreen.screens.first ?? NSScreen.main { lastScreen = s; return s }
        return lastScreen!
    }
    private var lastScreen: NSScreen? = NSScreen.screens.first ?? NSScreen.main

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
    private var lastHiddenHint: CGWindowID?
    static let settleDuration: TimeInterval = 20

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
        // No display at all (lid shut, nothing plugged in yet): wait for one.
        guard !NSScreen.screens.isEmpty else {
            logger.info("no display yet; waiting")
            scheduleRelayout()
            return
        }
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
        if !isActive {
            if final { restoreSizesAndPlace() } else { commit() }
        }
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

    /// After a display change macOS shrinks windows to fit the new screen, and squeezes parked
    /// ones hard since they sit almost off-screen. Give every window back the size it should have
    /// (the size you chose, capped at the screen), then place everything. The overlay covers the
    /// screen meanwhile, so the shuffling isn't seen.
    private func restoreSizesAndPlace() {
        isActive = true
        view.render()
        overlay.level = OverlayWindow.canvasLevel
        overlay.orderFrontRegardless()
        // Same as Tidy Up: sizes back to what you chose (capped at this screen), overlaps pushed
        // apart, clusters pulled back to the standard gap.
        fitLayoutToScreen(margin: 0)
        commit()
        view.render()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.overlay.level = OverlayWindow.backdropLevel
            self.isActive = false
            self.view.render()
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
        // macOS can still shuffle windows while the Mac sits at the lock screen; put everything
        // back once you're in.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                                            object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            logger.info("unlocked: re-placing windows")
            self.displaysWillChange()
            self.scheduleRelayout()
        }
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
        if let request = activationRequest,
           (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == request.pid {
            logger.info("activation took \(Int((CACurrentMediaTime() - request.at) * 1000))ms")
            activationRequest = nil
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// If the focused window isn't fully on screen, glide to center it.
    private func focusSettled() {
        // Clicking a big window would otherwise bury an open system prompt.
        raiseSystemPrompts()
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              let focused = AX.focusedWindow(pid: app.processIdentifier), let id = AX.windowID(focused) else { return }
        guard !isActive, !isPaused, !suspendTracking, animation == nil,
              let w = windows.first(where: { $0.id == id }) else { return }
        let r = camera.toView(w.canvasFrame)
        let fullyVisible = !w.parked && CGRect(origin: .zero, size: viewSize).insetBy(dx: -1, dy: -1).contains(r)
        guard !fullyVisible else { return }
        if autoCentre {
            logger.info("focus-settled glide to \(w.appName, privacy: .public)[\(w.id)]")
            glide(to: w)
        } else if w.parked, lastHiddenHint != w.id {
            // Off means off: macOS often focuses a hidden window by itself (after a close or
            // minimize), so never move the canvas; just say where the window went.
            lastHiddenHint = w.id
            Toast.show("\(w.appName) is off-screen · ⌥` to find it")
        }
    }

    /// Center `w` at 100% and make it the active window, from either mode.
    func focus(_ w: ManagedWindow) {
        if isActive { exit(focus: w) } else { glide(to: w) }
    }

    /// Live mode: pan the camera to `w`. The overlay rises at scale 1 (where proxies line up
    /// with the real windows), animates, commits, then sinks again. It never takes key focus,
    /// so typing keeps going to the window that was just clicked.
    private func glide(to w: ManagedWindow) {
        logger.info("glide to \(w.appName, privacy: .public)[\(w.id)]")
        let t0 = CACurrentMediaTime()
        if !gliding {
            guard !isActive, animation == nil else { return }
            isActive = true
            gliding = true
            view.render()
            // Cover the screen first, so resizing (which may briefly move the window) isn't seen.
            overlay.level = OverlayWindow.canvasLevel
            overlay.orderFrontRegardless()
        }
        // A hop during a glide (or while the last one's windows are still moving) starts from
        // wherever the camera is; only the newest hop hands the screen back.
        glideGeneration += 1
        let generation = glideGeneration
        glideTarget = w
        bringToFront(w)
        fitToScreen(w)
        view.render()
        let prep = CACurrentMediaTime() - t0
        animate(to: focusCamera(for: w), duration: 0.3) { [weak self] in
            self?.finishGlide(generation, prep: prep)
        }
    }

    /// Move the real windows (in the background), then focus and hand back, unless a newer hop
    /// has started meanwhile, in which case it finishes the job.
    private func finishGlide(_ generation: Int, prep: CFTimeInterval) {
        let c0 = CACurrentMediaTime()
        commitAsync {
            guard generation == self.glideGeneration else { return }
            logger.info("glide timing: prep \(Int(prep * 1000))ms, \(self.lastAnimationStats, privacy: .public), commit \(Int((CACurrentMediaTime() - c0) * 1000))ms")
            if let target = self.glideTarget { self.focusWindow(target) }
            // One frame or so for the window server to show the moved windows, then hand back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                guard generation == self.glideGeneration, self.animation == nil else { return }
                self.overlay.level = OverlayWindow.backdropLevel
                self.isActive = false
                self.gliding = false
                self.glideTarget = nil
                self.view.render()
            }
        }
    }

    /// Give `w` keyboard focus now, keep system prompts on top, and time the app switch.
    private func focusWindow(_ w: ManagedWindow) {
        activationRequest = (w.pid, CACurrentMediaTime())
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == w.pid { activationRequest = nil }
        AX.focus(w.ax, pid: w.pid)
        raiseSystemPrompts()
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
            // Mid-glide these are our own moves; querying the app here would stall the animation.
            guard !isActive, animation == nil else { return }
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
        if let size = AX.size(element) { adoptSize(w, size, fromUser: NSEvent.pressedMouseButtons & 1 != 0) }
        // Around a display change macOS keeps shoving windows for a while; only a drag with the
        // mouse button down counts as you moving a window then.
        let userDragging = NSEvent.pressedMouseButtons & 1 != 0
        if suspendTracking, !userDragging, !isActive, settleUntil != .distantFuture, Date() < settleUntil,
           let last = w.lastPlaced, let pos = AX.position(element), last.distance(to: pos) > 2 {
            reassertSoon()
        }
        if !isActive, !suspendTracking || userDragging, animation == nil, let pos = AX.position(element) {
            if let last = w.lastPlaced, last.distance(to: pos) < 2 {
                // Our own placement.
            } else {
                logger.info("follow \(w.appName, privacy: .public)[\(w.id)] moved to \(NSStringFromPoint(pos), privacy: .public) (last placed \(w.lastPlaced.map { NSStringFromPoint($0) } ?? "never", privacy: .public))")
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
                                   w: Double($0.canvasFrame.width), h: Double($0.canvasFrame.height),
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
        guard !gliding else { return }
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
        // Window discovery queries every app; don't let it land in the middle of a glide.
        if gliding || view.isDragging || (animation != nil && completion == nil) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.sync(completion: completion) }
            return
        }
        if let completion { pendingSyncCompletions.append(completion) }
        guard !syncing else { return }
        syncing = true
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            // Ask each app for its real window frames here, off the main thread: slow apps take
            // 100ms+ to answer, which would otherwise stall a glide or a key press.
            let axFrames = Self.axFrames(for: content?.windows ?? [])
            DispatchQueue.main.async {
                guard let self else { return }
                self.syncing = false
                if let content, !self.isPaused {
                    self.apply(content.windows, axFrames: axFrames)
                } else if let error {
                    logger.error("SCShareableContent failed: \(error.localizedDescription)")
                }
                let completions = self.pendingSyncCompletions
                self.pendingSyncCompletions = []
                completions.forEach { $0() }
            }
        }
    }

    /// `tracked`: Canvas already manages this window. The on-screen test is only for discovering
    /// new windows (so other displays' windows aren't adopted); a tracked window stays tracked
    /// wherever it is, e.g. parked beyond the edge of a screen that just got smaller.
    private func isManageable(_ w: SCWindow, tracked: Bool) -> Bool {
        guard w.windowLayer == 0, w.isOnScreen,
              w.frame.width >= 100, w.frame.height >= 60,
              let app = w.owningApplication, app.processID != getpid(),
              let running = NSRunningApplication(processIdentifier: app.processID),
              running.activationPolicy == .regular
        else { return false }
        return tracked || screenRectCG.intersects(w.frame)
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

    /// True frames (position and size) of ordinary app windows, by window ID, via Accessibility.
    /// ScreenCaptureKit reports transformed frames during Mission Control and similar animations.
    private static func axFrames(for scWindows: [SCWindow]) -> [CGWindowID: CGRect] {
        let pids = Set(scWindows.compactMap { $0.windowLayer == 0 ? $0.owningApplication?.processID : nil })
            .subtracting([getpid()])
        var frames: [CGWindowID: CGRect] = [:]
        for pid in pids {
            for element in AX.windows(pid: pid) {
                guard let id = AX.windowID(element), let p = AX.position(element), let s = AX.size(element),
                      s.width > 0, s.height > 0 else { continue }
                frames[id] = CGRect(origin: p, size: s)
            }
        }
        return frames
    }

    private func apply(_ scWindows: [SCWindow], axFrames: [CGWindowID: CGRect]) {
        let started = CACurrentMediaTime()
        defer {
            let ms = Int((CACurrentMediaTime() - started) * 1000)
            if ms > 30 { logger.info("slow: window sync took \(ms)ms") }
        }
        noteSystemPrompts(scWindows)
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

        let trackedIDs = Set(windows.map(\.id))
        for sc in scWindows where isManageable(sc, tracked: trackedIDs.contains(sc.windowID)) {
            seen.insert(sc.windowID)
            if let w = windows.first(where: { $0.id == sc.windowID }) {
                // Zoomed out, positions aren't followed, so skip asking each app (slow apps
                // would stall dragging); ScreenCaptureKit's frame is good enough for sizes.
                let f = live ? (axFrames[sc.windowID] ?? sc.frame) : sc.frame
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
        let returning = recentlyRemoved[w.id] != nil
        if let back = recentlyRemoved.removeValue(forKey: w.id) {
            // Came back (minimized, hidden, briefly missing during a display change): same spot.
            w.canvasFrame.origin = back.origin
        } else if firstSync, let match = LayoutStore.takeMatch(bundleID: w.bundleID, title: w.title, from: &savedPool) {
            w.canvasFrame.origin = CGPoint(x: match.x, y: match.y)
            if let pw = match.pw, let ph = match.ph { w.preferredSize = CGSize(width: pw, height: ph) }
            if let sw = match.w, let sh = match.h, let ax = w.ax,
               abs(sw - f.width) > 1 || abs(sh - f.height) > 1 {
                // Quitting put the macOS size back; restore the canvas size.
                let actual = resizeReal(w, ax, to: CGSize(width: sw, height: sh))
                w.canvasFrame.size = actual
                logger.info("restore size \(w.appName, privacy: .public)[\(w.id)] \(NSStringFromSize(f.size), privacy: .public) -> \(NSStringFromSize(actual), privacy: .public)")
            }
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
            w?.node.content.backgroundColor = nil
            CATransaction.commit()
        }
        w.capture.onStop = { [weak self, weak w] in
            guard let self, let w else { return }
            self.remove(w)
        }
        w.capture.start(window: sc, pixelSize: pixelSize(for: w), fps: isActive ? Self.canvasFPS : Self.liveFPS)
        observe(w)
        logger.info("tracking \(w.appName, privacy: .public) [\(w.id)] \(w.title, privacy: .public)")
        if arriving { arrive(w, anchor: anchor, live: live, returning: returning) }
        return restored
    }

    // MARK: Spatial navigation

    enum Direction { case left, right, up, down }
    /// A live-mode glide is running: the overlay is up, but it isn't canvas mode.
    private(set) var gliding = false
    private var glideGeneration = 0
    /// The 100% view you left when zooming out; leaving the canvas returns there unless you've
    /// panned or zoomed since.
    private var returnCamera: Camera?

    func cameraMovedByUser() { returnCamera = nil }
    /// Where the glide in flight is heading.
    private var glideTarget: ManagedWindow?

    /// ⌃ + arrow: go to the nearest window that way. At 100% it's focused (gliding to it if it
    /// isn't fully on screen); on the zoomed-out canvas the highlight moves and the view follows.
    func navigate(_ direction: Direction) {
        guard !isPaused else { return }
        // Mid-glide: re-aim the glide in flight, hopping on from the window it's heading to.
        if gliding {
            // Mid-glide: hop on from the window it's heading to, straight away.
            if let current = glideTarget, let next = nearest(direction, from: current.canvasFrame) {
                logger.info("navigate (chained) to \(next.appName, privacy: .public)[\(next.id)]")
                glide(to: next)
            }
            return
        }
        guard animation == nil else { return }
        let from: CGRect
        if isActive {
            from = (view.hovered ?? windows.last)?.canvasFrame
                ?? CGRect(origin: camera.center(in: viewSize), size: .zero)
        } else if let app = NSWorkspace.shared.frontmostApplication,
                  let focused = AX.focusedWindow(pid: app.processIdentifier), let id = AX.windowID(focused),
                  let w = windows.first(where: { $0.id == id }) {
            from = w.canvasFrame
        } else {
            from = CGRect(origin: camera.center(in: viewSize), size: .zero)
        }
        guard let target = nearest(direction, from: from) else { return }
        logger.info("navigate to \(target.appName, privacy: .public)[\(target.id)]")

        if isActive {
            view.highlight(target)
            animate(to: Camera.centered(on: target.canvasFrame.center, scale: camera.scale, viewSize: viewSize), duration: 0.25)
            return
        }
        let r = camera.toView(target.canvasFrame)
        if !target.parked && CGRect(origin: .zero, size: viewSize).insetBy(dx: -1, dy: -1).contains(r) {
            bringToFront(target)
            focusWindow(target)
            view.render()
        } else {
            glide(to: target)
        }
    }

    /// The nearest window in `direction`. A window sharing the row (for left / right) or column
    /// (for up / down) wins outright, nearest first; failing that, the closest window within ~35°
    /// of straight that way. Windows mostly above or below never count as left or right.
    private func nearest(_ direction: Direction, from: CGRect) -> ManagedWindow? {
        Self.nearest(direction, from: from, in: windows.map(\.canvasFrame)).map { windows[$0] }
    }

    static func nearest(_ direction: Direction, from: CGRect, in frames: [CGRect]) -> Int? {
        func shared(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> Bool {
            // Overlap of at least a third of the smaller span.
            min(a1, b1) - max(a0, b0) >= min(a1 - a0, b1 - b0) / 3
        }
        var inLine: (Int, CGFloat)?
        var inCone: (Int, CGFloat)?
        for (i, r) in frames.enumerated() where r != from {
            let dx = r.midX - from.midX, dy = r.midY - from.midY
            let ahead: Bool, gap: CGFloat, sameLine: Bool, withinCone: Bool
            switch direction {
            case .right:
                ahead = dx > 1 && r.minX > from.minX; gap = r.minX - from.maxX
                sameLine = shared(r.minY, r.maxY, from.minY, from.maxY); withinCone = abs(dy) <= dx * 0.7
            case .left:
                ahead = dx < -1 && r.maxX < from.maxX; gap = from.minX - r.maxX
                sameLine = shared(r.minY, r.maxY, from.minY, from.maxY); withinCone = abs(dy) <= -dx * 0.7
            case .down:
                ahead = dy > 1 && r.minY > from.minY; gap = r.minY - from.maxY
                sameLine = shared(r.minX, r.maxX, from.minX, from.maxX); withinCone = abs(dx) <= dy * 0.7
            case .up:
                ahead = dy < -1 && r.maxY < from.maxY; gap = from.minY - r.maxY
                sameLine = shared(r.minX, r.maxX, from.minX, from.maxX); withinCone = abs(dx) <= -dy * 0.7
            }
            guard ahead else { continue }
            if sameLine {
                if gap < (inLine?.1 ?? .infinity) { inLine = (i, gap) }
            } else if withinCone {
                let d = r.center.distance(to: from.center)
                if d < (inCone?.1 ?? .infinity) { inCone = (i, d) }
            }
        }
        return inLine?.0 ?? inCone?.0
    }

    // MARK: System prompts

    /// On-screen windows of background system processes (permission reminders, password and
    /// security prompts). Canvas doesn't manage them, but must never bury them.
    private var systemPrompts: [(pid: pid_t, id: CGWindowID)] = []

    private func noteSystemPrompts(_ scWindows: [SCWindow]) {
        let prompts = scWindows.compactMap { w -> (pid_t, CGWindowID)? in
            guard w.windowLayer == 0, w.isOnScreen, w.frame.width >= 150, w.frame.height >= 80,
                  screenRectCG.intersects(w.frame),
                  let pid = w.owningApplication?.processID, pid != getpid(),
                  // Apple's background prompt processes only (universalAccessAuthWarn,
                  // SecurityAgent, UserNotificationCenter, CoreServicesUIAgent, …).
                  w.owningApplication?.bundleIdentifier.hasPrefix("com.apple.") == true,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy != .regular
            else { return nil }
            return (pid, w.windowID)
        }
        let known = Set(systemPrompts.map(\.id))
        systemPrompts = prompts.map { (pid: $0.0, id: $0.1) }
        // A prompt that just appeared may have opened behind other windows.
        if prompts.contains(where: { !known.contains($0.1) }) { raiseSystemPrompts() }
    }

    /// Raise every known system prompt above app windows (without taking focus).
    func raiseSystemPrompts() {
        for prompt in systemPrompts {
            guard let ax = AX.windows(pid: prompt.pid).first(where: { AX.windowID($0) == prompt.id }) else { continue }
            AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
            logger.info("raised system prompt [\(prompt.id)]")
        }
    }

    // MARK: Tidy up

    /// The gap between neighbouring windows: edge snapping, new-window placement and Tidy Up.
    static let gap: CGFloat = 20
    /// Windows closer than this to a neighbour count as one cluster and get pulled together.
    static let clusterReach: CGFloat = 240

    /// Fit the layout to this screen without rebuilding it:
    /// 1. every window takes the size you chose, capped at the screen (shrinks on a laptop,
    ///    grows back on a big display);
    /// 2. overlaps are pushed apart, right or down, whichever is the smaller move;
    /// 3. gravity: within a cluster, gaps wider than the standard gap close up to it.
    /// Shown zoomed out.
    func tidy() {
        guard !isPaused else { return }
        guard isActive else {
            enter(zoomOut: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.isActive == true { self?.tidy() }
            }
            return
        }
        guard !windows.isEmpty else { return }
        fitLayoutToScreen(margin: 16)
        view.render()
        animate(to: fitCamera())
        scheduleSave()
    }

    /// The layout part of Tidy Up, also run after display changes. Real windows are resized here;
    /// positions are only changed on the canvas (commit or the next glide moves them).
    private func fitLayoutToScreen(margin: CGFloat) {
        let maxSize = CGSize(width: viewSize.width - margin * 2, height: viewSize.height - margin * 2)
        // Clusters come from each window's full chosen size, before anything shrinks, so a row
        // that was snapped together stays one cluster however much it shrinks.
        let clusters = Self.clusters(windows.map {
            CGRect(origin: $0.canvasFrame.origin, size: $0.preferredSize.width > 0 ? $0.preferredSize : $0.canvasFrame.size)
        }, reach: Self.clusterReach)
        for w in windows {
            guard let ax = w.ax else { continue }
            let chosen = w.preferredSize.width > 0 ? w.preferredSize : w.canvasFrame.size
            let target = CGSize(width: min(chosen.width, maxSize.width).rounded(),
                                height: min(chosen.height, maxSize.height).rounded())
            guard abs(target.width - w.canvasFrame.width) > 1 || abs(target.height - w.canvasFrame.height) > 1 else { continue }
            let actual = resizeReal(w, ax, to: target)
            logger.info("fit size \(w.appName, privacy: .public)[\(w.id)] \(NSStringFromSize(w.canvasFrame.size), privacy: .public) -> \(NSStringFromSize(actual), privacy: .public)")
            w.canvasFrame.size = actual
            updateCapture(w)
        }

        var frames = windows.map(\.canvasFrame)
        Self.separate(&frames, gap: Self.gap)
        Self.gravity(&frames, clusters: clusters, gap: Self.gap)
        Self.separate(&frames, gap: Self.gap)
        var moved = 0
        for (w, f) in zip(windows, frames) {
            let rounded = CGPoint(x: f.minX.rounded(), y: f.minY.rounded())
            if rounded.distance(to: w.canvasFrame.origin) >= 1 { moved += 1 }
            w.canvasFrame.origin = rounded
        }
        logger.info("layout fitted: \(moved) of \(self.windows.count) windows moved")
    }

    /// Push overlapping frames apart in reading order. Only ever moving right or down means it
    /// always finishes.
    static func separate(_ frames: inout [CGRect], gap: CGFloat) {
        let order = frames.indices.sorted { (frames[$0].minY, frames[$0].minX) < (frames[$1].minY, frames[$1].minX) }
        var settled: [CGRect] = []
        for i in order {
            var r = frames[i]
            for _ in 0..<200 {
                guard let hit = settled.first(where: { $0.insetBy(dx: -gap + 0.5, dy: -gap + 0.5).intersects(r) }) else { break }
                let right = hit.maxX + gap - r.minX
                let down = hit.maxY + gap - r.minY
                if right <= down { r.origin.x += right } else { r.origin.y += down }
            }
            frames[i] = r
            settled.append(r)
        }
    }

    /// Cluster number for each frame: frames within `reach` of each other (directly or through
    /// a chain of neighbours) share one.
    static func clusters(_ frames: [CGRect], reach: CGFloat) -> [Int] {
        var parent = Array(frames.indices)
        func root(_ i: Int) -> Int { parent[i] == i ? i : root(parent[i]) }
        for i in frames.indices {
            for j in frames.indices where j > i && frames[i].insetBy(dx: -reach / 2, dy: -reach / 2)
                .intersects(frames[j].insetBy(dx: -reach / 2, dy: -reach / 2)) {
                parent[root(j)] = root(i)
            }
        }
        return frames.indices.map(root)
    }

    /// Within each cluster, close gaps: each frame slides left (then up) until it sits `gap` from
    /// its nearest neighbour on that side in the same cluster. It only slides towards a neighbour
    /// it shares rows (or columns) with, so it never creates overlaps.
    static func gravity(_ frames: inout [CGRect], clusters: [Int], gap: CGFloat) {
        func overlapY(_ a: CGRect, _ b: CGRect) -> Bool { min(a.maxY, b.maxY) - max(a.minY, b.minY) > 0 }
        func overlapX(_ a: CGRect, _ b: CGRect) -> Bool { min(a.maxX, b.maxX) - max(a.minX, b.minX) > 0 }
        for _ in 0..<3 {
            for i in frames.indices.sorted(by: { frames[$0].minX < frames[$1].minX }) {
                let r = frames[i]
                let edges = frames.indices.filter {
                    $0 != i && clusters[$0] == clusters[i] && frames[$0].maxX <= r.minX + 0.5 && overlapY(frames[$0], r)
                }.map { frames[$0].maxX }
                if let nearest = edges.max(), r.minX - nearest > gap { frames[i].origin.x = nearest + gap }
            }
            for i in frames.indices.sorted(by: { frames[$0].minY < frames[$1].minY }) {
                let r = frames[i]
                let edges = frames.indices.filter {
                    $0 != i && clusters[$0] == clusters[i] && frames[$0].maxY <= r.minY + 0.5 && overlapX(frames[$0], r)
                }.map { frames[$0].maxY }
                if let nearest = edges.max(), r.minY - nearest > gap { frames[i].origin.y = nearest + gap }
            }
        }
    }

    /// Repair / scripting: put a window at a canvas position; `commit` then moves real windows.
    func setCanvasOrigin(_ id: CGWindowID, _ origin: CGPoint, commit commitNow: Bool) {
        if let w = windows.first(where: { $0.id == id }) { w.canvasFrame.origin = origin }
        guard commitNow else { return }
        if !isActive {
            windows.forEach { $0.lastPlaced = nil }
            commit()
        }
        view.render()
        scheduleSave()
    }

    func setPreferredSize(_ id: CGWindowID, _ size: CGSize) {
        guard let w = windows.first(where: { $0.id == id }) else { return }
        w.preferredSize = size
        scheduleSave()
        logger.info("preferred size \(w.appName, privacy: .public)[\(id)] = \(NSStringFromSize(size), privacy: .public)")
    }

    // MARK: New windows

    /// New windows go to an empty spot next to what you were working on; windows coming back
    /// from minimize / hide go back where they were.
    private func arrive(_ w: ManagedWindow, anchor: ManagedWindow?, live: Bool, returning: Bool) {
        if returning {
            // add() already put it back at its old spot.
        } else if AX.subrole(w.ax) == kAXStandardWindowSubrole as String,
                  let spot = freeSpot(for: w, near: anchor, onScreenOnly: !autoCentre) {
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
        } else if returning {
            // Back from minimize / hide: quietly return to its spot; focus decides whether to glide.
            commit()
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
    private func freeSpot(for w: ManagedWindow, near anchor: ManagedWindow?, onScreenOnly: Bool) -> CGPoint? {
        let others = windows.filter { $0 !== w }.map(\.canvasFrame)
        guard !others.isEmpty else { return nil }
        let gap = Self.gap
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
            if onScreenOnly && !visible.contains(r) { continue }
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

    /// Zoomed-out pictures are captured at reduced resolution. Before zooming in, switch every
    /// window that will be on screen at `target` to full resolution, so it's sharp on arrival.
    private func sharpen(for target: Camera) {
        resolutionWork?.cancel()
        let backing = screen.backingScaleFactor
        let arriving = CGRect(origin: .zero, size: viewSize)
        for w in windows where target.toView(w.canvasFrame).intersects(arriving) {
            w.capture.update(pixelSize: CGSize(width: w.canvasFrame.width * backing, height: w.canvasFrame.height * backing),
                             fps: Self.canvasFPS)
        }
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
            self.returnCamera = nil
            if zoomOut {
                self.returnCamera = self.camera
                self.animate(to: self.overviewCamera())
            }
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
            // Straight back where you were, unless you've moved around since zooming out.
            target = returnCamera ?? Camera.centered(on: camera.center(in: viewSize), scale: 1, viewSize: viewSize)
        }
        sharpen(for: target)
        animate(to: target, duration: 0.18) { [weak self] in
            guard let self else { return }
            self.commit()
            let toFocus = focus ?? self.windows.last(where: { !$0.parked })
            if let toFocus {
                self.focusWindow(toFocus)
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
        for (w, target, parked) in commitPlan() {
            w.place(at: target)
            w.parked = parked
        }
        scheduleSave()
    }

    /// Where every real window should go for the current camera (scale 1).
    private func commitPlan() -> [(ManagedWindow, CGPoint, Bool)] {
        let vp = viewport
        return windows.map { w in
            let r = camera.toView(w.canvasFrame).offsetBy(dx: vp.minX, dy: vp.minY)
            let visible = r.intersection(vp)
            // macOS won't put a title bar above the menu bar; it would shove the window down.
            // Such windows stay parked and the backdrop draws them where they belong.
            let topClipped = r.minY < vp.minY - 1
            if !topClipped, !visible.isNull, visible.width >= 48, visible.height >= 48 {
                return (w, CGPoint(x: r.minX.rounded(), y: r.minY.rounded()), false)
            }
            return (w, parkPoint, true)
        }
    }

    private let axQueue = DispatchQueue(label: "com.invignation.canvas.ax", qos: .userInteractive)

    /// Like commit(), but the Accessibility calls run off the main thread: a slow app (Chromium
    /// apps animate AX moves) can't stall animations or key presses. Apps with Chromium's
    /// enhanced-UI mode get it switched off while their windows move, then back on.
    private func commitAsync(_ completion: @escaping () -> Void) {
        let jobs = commitPlan().compactMap { (w, target, parked) -> (ManagedWindow, AXUIElement, CGPoint, Bool)? in
            if let last = w.lastPlaced, last.distance(to: target) < 0.5 { w.parked = parked; return nil }
            guard let ax = w.ax else { return nil }
            return (w, ax, target, parked)
        }
        guard !jobs.isEmpty else { scheduleSave(); completion(); return }
        let work = jobs.map { (pid: $0.0.pid, ax: $0.1, target: $0.2) }
        axQueue.async {
            var landed: [CGPoint?] = []
            let pids = Set(work.map(\.pid))
            let enhanced = pids.filter { AX.enhancedUserInterface(pid: $0) }
            enhanced.forEach { AX.setEnhancedUserInterface(false, pid: $0) }
            for job in work {
                AX.setPosition(job.ax, job.target)
                landed.append(AX.position(job.ax))
            }
            enhanced.forEach { AX.setEnhancedUserInterface(true, pid: $0) }
            DispatchQueue.main.async {
                for ((w, _, target, parked), at) in zip(jobs, landed) {
                    w.lastPlaced = at ?? target
                    w.parked = parked
                }
                self.scheduleSave()
                completion()
            }
        }
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
        logger.info("resize \(w.appName, privacy: .public)[\(w.id)] \(NSStringFromSize(w.canvasFrame.size), privacy: .public) -> \(NSStringFromSize(target), privacy: .public)")
        let actual = resizeReal(w, ax, to: target)
        let c = w.canvasFrame.center
        w.canvasFrame = CGRect(x: c.x - actual.width / 2, y: c.y - actual.height / 2, width: actual.width, height: actual.height)
        updateCapture(w)
    }

    /// Resizes the real window. macOS won't grow a window past the screen edge from where it
    /// sits, so a window that's growing is first moved to the top-left; the next commit puts it
    /// where the canvas says.
    @discardableResult
    private func resizeReal(_ w: ManagedWindow, _ ax: AXUIElement, to size: CGSize) -> CGSize {
        if let current = AX.size(ax), size.width > current.width + 1 || size.height > current.height + 1 {
            AX.setPosition(ax, viewport.origin)
            w.lastPlaced = nil
        }
        AX.setSize(ax, size)
        let actual = AX.size(ax) ?? size
        w.lastSized = actual
        return actual
    }

    /// Takes on a size change of the real window. Resizes we didn't make become the
    /// window's preferred size.
    /// Only a resize made with the mouse button down (dragging an edge) counts as you choosing a
    /// size. macOS, apps (Chromium animates AX resizes in steps) and Canvas itself resize windows
    /// too, and none of those should change the size you chose.
    private func adoptSize(_ w: ManagedWindow, _ size: CGSize, fromUser: Bool = false) {
        guard size != w.canvasFrame.size, size.width > 0, size.height > 0 else { return }
        w.canvasFrame.size = size
        let ours = w.lastSized.map { abs($0.width - size.width) < 2 && abs($0.height - size.height) < 2 } ?? false
        if fromUser && !ours && !suspendTracking {
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
        returnCamera = nil
        guard isActive else { return }
        cancelAnimation()
        camera.pan(by: d)
        cameraChanged()
    }

    func zoom(by factor: CGFloat, at anchor: CGPoint) {
        returnCamera = nil
        guard isActive else { return }
        cancelAnimation()
        camera.zoom(to: camera.scale * factor, anchor: anchor)
        cameraChanged()
    }

    func center(on canvasPoint: CGPoint) {
        returnCamera = nil
        guard isActive else { return }
        cancelAnimation()
        camera = Camera.centered(on: canvasPoint, scale: camera.scale, viewSize: viewSize)
        cameraChanged()
    }

    func toggleOverview(at anchor: CGPoint) {
        returnCamera = nil
        if camera.scale < 0.95 {
            var target = camera
            target.zoom(to: 1, anchor: anchor)
            animate(to: target)
        } else {
            animate(to: overviewCamera())
        }
    }

    func zoomAnimated(to scale: CGFloat) {
        returnCamera = nil
        var target = camera
        target.zoom(to: scale, anchor: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
        animate(to: target)
    }

    private func cameraChanged() {
        view.render()
        scheduleResolutionUpdate()
    }

    // MARK: Animation

    func animate(to target: Camera, duration: CFTimeInterval = 0.22, completion: (() -> Void)? = nil) {
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
        guard var a = animation else { stopDisplayLink(); return }
        let now = CACurrentMediaTime()
        if a.frames == 0 { a.firstFrame = now } else { a.maxGap = max(a.maxGap, now - a.lastFrame) }
        a.frames += 1
        a.lastFrame = now
        animation = a
        let t = min(1, (CACurrentMediaTime() - a.start) / a.duration)
        let e = 1 - pow(1 - t, 3) // ease-out cubic
        let s = exp(lerp(log(a.from.scale), log(a.to.scale), e))
        let c0 = a.from.center(in: viewSize), c1 = a.to.center(in: viewSize)
        camera = Camera.centered(on: CGPoint(x: lerp(c0.x, c1.x, e), y: lerp(c0.y, c1.y, e)), scale: s, viewSize: viewSize)
        if t >= 1 {
            lastAnimationStats = "first frame after \(Int((a.firstFrame - a.start) * 1000))ms, \(a.frames) frames, max gap \(Int(a.maxGap * 1000))ms"
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

    /// Snap a dragged frame (one window, or a group's bounding box) to the other windows.
    /// Edges and the standard gap snap firmly; centres snap softly (half the reach, and they lose
    /// ties) so they guide without fighting. A frame above or below a row of windows can also
    /// centre on the whole row. Returns guide lines in canvas space.
    func snap(_ f: CGRect, excluding: Set<CGWindowID>) -> (CGRect, [(CGPoint, CGPoint)]) {
        let firm = 10 / camera.scale
        let soft = firm / 2
        let gap = Self.gap
        typealias Candidate = (score: CGFloat, delta: CGFloat, line: CGFloat?, span: CGRect?)
        var bestX: Candidate?
        var bestY: Candidate?
        let others = windows.filter { !excluding.contains($0.id) }.map(\.canvasFrame)

        func consider(_ a: CGFloat, _ b: CGFloat, centre: Bool = false, line: CGFloat?, span: CGRect? = nil,
                      into best: inout Candidate?) {
            let d = b - a
            guard abs(d) < (centre ? soft : firm) else { return }
            let score = abs(d) + (centre ? soft / 2 : 0)
            if score < (best?.score ?? .infinity) { best = (score, d, line, span) }
        }
        for r in others {
            for a in [f.minX, f.maxX] { for b in [r.minX, r.maxX] { consider(a, b, line: b, into: &bestX) } }
            consider(f.midX, r.midX, centre: true, line: r.midX, into: &bestX)
            consider(f.minX, r.maxX + gap, line: nil, into: &bestX)
            consider(f.maxX, r.minX - gap, line: nil, into: &bestX)
            for a in [f.minY, f.maxY] { for b in [r.minY, r.maxY] { consider(a, b, line: b, into: &bestY) } }
            consider(f.midY, r.midY, centre: true, line: r.midY, into: &bestY)
            consider(f.minY, r.maxY + gap, line: nil, into: &bestY)
            consider(f.maxY, r.minY - gap, line: nil, into: &bestY)
        }

        // Centre on a whole neighbouring row (above / below) or column (left / right).
        let reach = Self.clusterReach
        let wide = f.insetBy(dx: -reach, dy: 0), tall = f.insetBy(dx: 0, dy: -reach)
        let below = others.filter { $0.minY >= f.maxY - 1 && $0.minY - f.maxY <= reach && $0.intersects(wide.insetBy(dx: 0, dy: -reach)) }
        let above = others.filter { $0.maxY <= f.minY + 1 && f.minY - $0.maxY <= reach && $0.intersects(wide.insetBy(dx: 0, dy: -reach)) }
        let left = others.filter { $0.maxX <= f.minX + 1 && f.minX - $0.maxX <= reach && $0.intersects(tall.insetBy(dx: -reach, dy: 0)) }
        let right = others.filter { $0.minX >= f.maxX - 1 && $0.minX - f.maxX <= reach && $0.intersects(tall.insetBy(dx: -reach, dy: 0)) }
        for row in [below, above] where row.count > 1 {
            let u = row.dropFirst().reduce(row[0]) { $0.union($1) }
            consider(f.midX, u.midX, centre: true, line: u.midX, span: u, into: &bestX)
        }
        for column in [left, right] where column.count > 1 {
            let u = column.dropFirst().reduce(column[0]) { $0.union($1) }
            consider(f.midY, u.midY, centre: true, line: u.midY, span: u, into: &bestY)
        }

        var out = f
        if let bx = bestX { out.origin.x += bx.delta }
        if let by = bestY { out.origin.y += by.delta }

        var lines: [(CGPoint, CGPoint)] = []
        if let x = bestX?.line {
            let span = bestX?.span.map { $0.union(out) } ?? (others.filter {
                [$0.minX, $0.midX, $0.maxX].contains { abs($0 - x) < 0.5 }
            } + [out]).reduce(out) { $0.union($1) }
            lines.append((CGPoint(x: x, y: span.minY), CGPoint(x: x, y: span.maxY)))
        }
        if let y = bestY?.line {
            let span = bestY?.span.map { $0.union(out) } ?? (others.filter {
                [$0.minY, $0.midY, $0.maxY].contains { abs($0 - y) < 0.5 }
            } + [out]).reduce(out) { $0.union($1) }
            lines.append((CGPoint(x: span.minX, y: y), CGPoint(x: span.maxX, y: y)))
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
