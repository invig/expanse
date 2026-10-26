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
    /// Paused: windows are back in their original macOS layout and Expanse leaves them alone.
    private(set) var isPaused = false

    let view: CanvasView
    private let overlay: OverlayWindow

    private var syncTimer: Timer?
    private var syncing = false
    private var syncRetryScheduled = false
    private var pendingSyncCompletions: [() -> Void] = []
    private var firstSync = true
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
    private var recentlyRemoved: [CGWindowID: Departed] = [:]

    /// Everything Expanse knew about a window that went out of view (app hidden, minimised, on
    /// another Space) or closed, so it comes back exactly as it was and is still restored on quit.
    private struct Departed {
        let pid: pid_t
        let canvasFrame: CGRect
        let originalFrame: CGRect
        let preferredSize: CGSize
        let home: CGPoint?
        let parked: Bool
        let at: Date
    }
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

    /// Parked windows' pictures at the edges of the screen at 100%.
    static let liveFPS = 2
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
        return lastScreen ?? NSScreen()
    }
    private var lastScreen: NSScreen? = NSScreen.screens.first ?? NSScreen.main

    /// expanse://screen?w=&h= pretends the display is this size, to exercise display changes.
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

    /// Only Expanse puts windows in the parking corner; nobody drags a window there. A window
    /// found there is hidden, not moved, even if a placement failed to register (apps answer
    /// slowly around sleep and wake), so it must never take that spot as its canvas position.
    private func inParkingCorner(_ p: CGPoint) -> Bool {
        p.x >= screenRectCG.maxX - 12 && p.y >= screenRectCG.maxY - 80
    }

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
        guard !isPaused else { return }
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
        guard !isPaused else { return }
        suspendTracking = true
        relayoutWork.forEach { $0.cancel() }
        let first = DispatchWorkItem { [weak self] in self?.relayout(final: false) }
        let second = DispatchWorkItem { [weak self] in self?.relayout(final: true) }
        relayoutWork = [first, second]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: first)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.5, execute: second)
    }

    private func relayout(final: Bool) {
        guard !isPaused else { return }
        // Windows still moving in the background (the last pass, or a glide): wait for them, or
        // they'd land where the last screen wanted them.
        guard !gliding else { scheduleRelayout(delay: 0.5); return }
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
            if final { restoreSizesAndPlace() } else { commitInBackground() }
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
        fitLayoutToScreen(margin: 0, tidy: false)
        view.render()
        // Like a glide's last step: input waits while the real windows move in the background.
        gliding = true
        commitAsync { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let self else { return }
                self.overlay.level = OverlayWindow.backdropLevel
                self.isActive = false
                self.gliding = false
                self.view.render()
                self.updateStreamingSoon()
            }
        }
    }

    /// commit(), with the Accessibility calls off the main thread (see commitAsync): with dozens
    /// of windows, a display change would otherwise freeze Expanse for seconds.
    private func commitInBackground() {
        commitAsync { [weak self] in
            guard let self else { return }
            if !self.isActive { self.updateStreaming() }
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
            self.commitInBackground()
        }
        reassertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: Lifecycle

    func start() {
        // A beachballing app must not freeze Expanse (and its full-screen overlay): every
        // Accessibility call gives up after half a second.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
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
        // New, closed, minimised and restored windows trigger a scan straight away (every app is
        // watched; see observeApp and handleAXEvent), and so do apps launching, hiding and
        // unhiding. A scan costs ScreenCaptureKit tens of milliseconds of LaunchServices lookups,
        // so the regular one is only a safety net.
        syncTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.sync() }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for (i, app) in apps.enumerated() {
            // A few at a time: each asks the app to register, and a busy app takes a while.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.05) { [weak self] in
                self?.observeApp(app.processIdentifier)
            }
        }
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.syncSoon()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            // Its first window usually shows up a moment after launch.
            for delay in [0.5, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.syncSoon() }
            }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.activationPolicy == .regular {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.observeApp(app.processIdentifier) }
            }
        }
        magnifyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .magnify) { [weak self] event in
            self?.handleGlobalPinch(event)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            // A pid can be reused by a later app; don't hand it this app's observer.
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.observers[app.processIdentifier] = nil
                self?.focusedWindowByApp[app.processIdentifier] = nil
            }
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
            self?.syncSoon()
        }
    }

    func refreshWallpaper() {
        lastWallpaperRefresh = CACurrentMediaTime()
        guard Wallpaper.enabled, CGPreflightScreenCaptureAccess() else { view.setWallpaper(nil); return }
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
              app.processIdentifier != getpid() else { return }
        windowFocused()
    }

    /// A window got focus (click, ⌘-Tab, Dock). Focus often bounces between windows for a moment
    /// (opening a document focuses the old window, then the new one), so act on where it settles.
    private func windowFocused() {
        focusSettleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.focusSettled() }
        focusSettleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// If the focused window isn't fully on screen, glide to center it.
    private func focusSettled() {
        // Clicking a big window would otherwise bury an open system prompt.
        raiseSystemPrompts()
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        let pid = app.processIdentifier
        // Asking the app which window has focus waits on the app; do that off the main thread.
        // An answer that comes back after you've moved on (another app, or a glide started) is
        // dropped: acting on it would pull you back.
        focusQuery += 1
        let query = focusQuery
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let focused = AX.focusedWindow(pid: pid), let id = AX.windowID(focused) else { return }
            DispatchQueue.main.async {
                guard let self, query == self.focusQuery,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                self.focusedWindowByApp[pid] = id
                self.focusSettled(on: id)
            }
        }
    }

    private var focusQuery = 0

    private func focusSettled(on id: CGWindowID) {
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
        focusQuery += 1   // a focus answer still on its way is out of date now
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
                self.pathRegion = nil
                self.updateStreamingSoon()
                self.glideTarget = nil
                self.view.render()
            }
        }
    }

    /// Give `w` keyboard focus now, keep system prompts on top, and time the app switch.
    private func focusWindow(_ w: ManagedWindow) {
        activationRequest = (w.pid, CACurrentMediaTime())
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == w.pid { activationRequest = nil }
        // The app has to answer each of these; a busy one takes 30ms+, so they go on the
        // Accessibility queue (after any moves still running there), not the main thread.
        let ax = w.ax, pid = w.pid
        focusedWindowByApp[pid] = w.id
        axQueue.async { AX.focus(ax, pid: pid) }
        raiseSystemPrompts()
    }

    // MARK: Live tracking

    private func observe(_ w: ManagedWindow) {
        guard let ax = w.ax else { return }
        observeApp(w.pid)
        observers[w.pid]?.observe(window: ax, id: w.id)
    }

    /// Window created and focus changes for an app, whether or not it has windows on the canvas.
    private func observeApp(_ pid: pid_t) {
        guard observers[pid] == nil, pid != getpid() else { return }
        observers[pid] = AppObserver(pid: pid) { [weak self] element, notification, id in
            self?.handleAXEvent(element, notification, id: id)
        }
    }

    /// `id`: the window's ID if it's one Expanse observes (looked up without asking the app).
    private func handleAXEvent(_ element: AXUIElement, _ notification: String, id: CGWindowID?) {
        switch notification {
        case kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
             kAXWindowDeminiaturizedNotification:
            syncSoon()
        case kAXFocusedWindowChangedNotification:
            var pid: pid_t = 0
            if let id, AXUIElementGetPid(element, &pid) == .success { focusedWindowByApp[pid] = id }
            windowFocused()
        case kAXMovedNotification, kAXResizedNotification:
            // Mid-glide these are our own moves; querying the app here would stall the animation.
            guard !isActive, animation == nil else { return }
            // (The observer knows its windows' IDs; asking the app is the fallback.)
            guard let id = id ?? AX.windowID(element), let w = windows.first(where: { $0.id == id }) else { return }
            let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
            // The echo of a move we just made (it can arrive after a glide hands back). Asking
            // the app where its window is costs two round trips; a slow app with a dozen
            // windows would stall the main thread for half a second right after every glide.
            // (Not around a display change, when macOS shoving windows back must be noticed.)
            if !suspendTracking, CACurrentMediaTime() - w.lastPlacedAt < 0.6, !mouseDown { return }
            // A drag sends dozens of these a second; look at each window at most every 50ms.
            changedWindows[id] = (element, mouseDown || changedWindows[id]?.mouseDown == true)
            guard !changedWindowsScheduled else { return }
            changedWindowsScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                let changed = self.changedWindows
                self.changedWindows = [:]
                self.changedWindowsScheduled = false
                guard !self.isActive, self.animation == nil else { return }
                for (id, change) in changed {
                    if let w = self.windows.first(where: { $0.id == id }) {
                        self.realWindowChanged(w, change.element, userDragging: change.mouseDown)
                    }
                }
            }
        default:
            break
        }
    }

    private var changedWindows: [CGWindowID: (element: AXUIElement, mouseDown: Bool)] = [:]
    private var changedWindowsScheduled = false

    /// A real window moved or resized. In live mode, a move we didn't make means the user
    /// dragged it: the canvas follows.
    /// `userDragging`: the mouse button was down when the change was reported.
    private func realWindowChanged(_ w: ManagedWindow, _ element: AXUIElement, userDragging: Bool) {
        guard !isPaused else { return }
        if let size = AX.size(element) { adoptSize(w, size, fromUser: userDragging) }
        let pos = isActive ? nil : AX.position(element)
        // Around a display change macOS keeps shoving windows for a while; only a drag with the
        // mouse button down counts as you moving a window then.
        if suspendTracking, !userDragging, !isActive, settleUntil != .distantFuture, Date() < settleUntil,
           let last = w.lastPlaced, let pos, last.distance(to: pos) > 2 {
            reassertSoon()
        }
        if !isActive, !suspendTracking || userDragging, animation == nil, let pos {
            if let last = w.lastPlaced, last.distance(to: pos) < 2 {
                // Our own placement.
            } else if inParkingCorner(pos) {
                w.parked = true
                w.lastPlaced = pos
            } else {
                logger.info("follow \(w.appName, privacy: .public)[\(w.id)] moved to \(NSStringFromPoint(pos), privacy: .public) (last placed \(w.lastPlaced.map { NSStringFromPoint($0) } ?? "never", privacy: .public))")
                w.lastPlaced = nil
                w.parked = false
                let before = w.canvasFrame.origin
                w.canvasFrame.origin = canvasPoint(forGlobal: pos)
                noteUserMove(w, from: before)
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
        // Before the first successful window scan (e.g. no Screen Recording yet) `windows` is
        // empty, and saving would wipe the layout and the crash-recovery originals.
        guard !isPaused, hasSynced else { return }
        // While no window is shrunk for a smaller screen, the canvas layout is the home layout.
        if !isDerived { windows.forEach { $0.home = $0.canvasFrame.origin } }
        // Saved positions are canvas coordinates relative to a scale-1 camera.
        let center = camera.center(in: viewSize)
        let layout = SavedLayout(
            cameraX: Double(camera.origin.x), cameraY: Double(camera.origin.y),
            centerX: Double(center.x), centerY: Double(center.y),
            cleanExit: cleanExit,
            windows: windows.map {
                SavedLayout.Window(bundleID: $0.bundleID, appName: $0.appName, title: LayoutStore.titleKey($0.title),
                                   x: Double($0.canvasFrame.minX), y: Double($0.canvasFrame.minY),
                                   w: Double($0.canvasFrame.width), h: Double($0.canvasFrame.height),
                                   hx: Double(($0.home ?? $0.canvasFrame.origin).x),
                                   hy: Double(($0.home ?? $0.canvasFrame.origin).y),
                                   pw: Double($0.preferredSize.width), ph: Double($0.preferredSize.height),
                                   ox: Double($0.originalFrame.minX), oy: Double($0.originalFrame.minY),
                                   ow: Double($0.originalFrame.width), oh: Double($0.originalFrame.height),
                                   id: $0.id, pid: $0.pid)
            } + savedPool.prefix(60))   // windows not open right now keep their saved spots
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

    /// Put every window back exactly where macOS had it before Expanse, and stop managing.
    func pause() {
        guard !isPaused else { return }
        guard !gliding else { whenIdle { [weak self] in self?.pause() }; return }
        cancelAnimation()
        settleBackgroundMoves()
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
        hasSynced = false
        lastSavedLayout = nil
        overlay.level = OverlayWindow.backdropLevel
        overlay.orderFrontRegardless()
        sync()
        logger.info("resumed")
    }

    /// Finish any window moves still running on the background queue, and stop a glide from
    /// handing back afterwards, so nothing lands after windows have been restored.
    private func settleBackgroundMoves() {
        glideGeneration += 1
        gliding = false
        axQueue.sync {}
    }

    private func restoreOriginals() {
        for w in windows {
            guard let ax = w.ax else { continue }
            restore(ax, to: w.originalFrame, currentSize: w.canvasFrame.size)
            w.lastPlaced = nil
            w.parked = false
        }
        // Windows out of view right now (hidden app, minimised, another Space) still go back.
        for (id, gone) in recentlyRemoved {
            guard let ax = AX.windows(pid: gone.pid).first(where: { AX.windowID($0) == id }) else { continue }
            restore(ax, to: gone.originalFrame, currentSize: AX.size(ax) ?? gone.canvasFrame.size)
        }
        recentlyRemoved = [:]
    }

    private func restore(_ ax: AXUIElement, to original: CGRect, currentSize: CGSize) {
        var r = original
        guard r.width > 0, r.height > 0 else { return }
        let vp = viewport
        // If the original spot is gone (smaller screen now), bring it back into view.
        if !r.insetBy(dx: 40, dy: 40).intersects(vp) {
            r.origin = CGPoint(x: vp.midX - r.width / 2, y: vp.minY + 40)
        }
        // Move first: macOS won't grow a window past the screen edge from the parking corner.
        AX.setPosition(ax, r.origin)
        if r.size != currentSize {
            AX.setSize(ax, r.size)
            AX.setPosition(ax, r.origin)
        }
    }

    /// Run `action` now, or once the glide in flight has handed back. Camera actions mid-glide
    /// would cut it short and leave the overlay stuck up.
    func whenIdle(attempts: Int = 60, _ action: @escaping () -> Void) {
        if !gliding { action(); return }
        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.whenIdle(attempts: attempts - 1, action)
        }
    }

    // MARK: Window discovery

    func sync(completion: (() -> Void)? = nil) {
        guard !isPaused else { return }
        // Until Screen Recording is in effect (granted, and Expanse relaunched), any
        // ScreenCaptureKit call makes macOS show its permission prompt again, every time.
        guard CGPreflightScreenCaptureAccess() else { completion?(); return }
        // Window discovery queries every app; don't let it land in the middle of a glide.
        if gliding || view.isDragging || (animation != nil && completion == nil) {
            if let completion { pendingSyncCompletions.append(completion) }
            guard !syncRetryScheduled else { return }
            syncRetryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.syncRetryScheduled = false
                self?.sync()
            }
            return
        }
        if let completion { pendingSyncCompletions.append(completion) }
        guard !syncing else { return }
        syncing = true
        let input = scanInput()
        let s0 = CACurrentMediaTime()
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            let s1 = CACurrentMediaTime()
            // Ask apps about their windows here, off the main thread: slow apps take 100ms+ to
            // answer, which would otherwise stall a glide or a key press.
            var ax = Self.axSnapshot(for: content?.windows ?? [], input: input)
            if input.live { ax.order = Self.windowServerOrder() }
            let s2 = CACurrentMediaTime()
            DispatchQueue.main.async {
                guard let self else { return }
                self.syncing = false
                self.windowKinds = ax.kinds
                if let content, !self.isPaused {
                    let s3 = CACurrentMediaTime()
                    // Windows moved (a glide, leaving the canvas) or the camera changed while the
                    // scan ran: its frames say where windows were, which would read as you moving
                    // them. Take only what's new from it and scan again.
                    let liveNow = !self.isActive && !self.suspendTracking
                    let stale = input.live != liveNow
                        || (liveNow && (input.moves != ManagedWindow.moves || input.camera != self.camera))
                    self.apply(content.windows, ax: ax, stale: stale)
                    if stale { self.syncSoon() }
                    let ms = Int((CACurrentMediaTime() - s0) * 1000)
                    if ms > 120 {
                        logger.info("slow: window scan took \(ms)ms (ScreenCaptureKit \(Int((s1 - s0) * 1000))ms, \(ax.calls) Accessibility calls and window order \(Int((s2 - s1) * 1000))ms, main thread \(Int((CACurrentMediaTime() - s3) * 1000))ms)")
                    }
                } else if let error {
                    logger.error("SCShareableContent failed: \(error.localizedDescription)")
                }
                let completions = self.pendingSyncCompletions
                self.pendingSyncCompletions = []
                completions.forEach { $0() }
            }
        }
    }

    /// `tracked`: Expanse already manages this window. The on-screen test is only for discovering
    /// new windows (so other displays' windows aren't adopted); a tracked window stays tracked
    /// wherever it is, e.g. parked beyond the edge of a screen that just got smaller.
    private func isManageable(_ w: SCWindow, tracked: Bool, regular: (pid_t) -> Bool) -> Bool {
        guard w.windowLayer == 0, w.isOnScreen,
              w.frame.width >= 100, w.frame.height >= 60,
              let app = w.owningApplication, app.processID != getpid(), regular(app.processID)
        else { return false }
        return tracked || screenRectCG.intersects(w.frame)
    }

    /// Ordinary apps (with a Dock icon), not menu-bar extras or background agents. Asking is a
    /// LaunchServices lookup (around a millisecond), and window scans ask for every app, so the
    /// answer is kept for half a minute. Thread-safe.
    static func isRegularApp(_ pid: pid_t) -> Bool {
        appPolicyLock.lock()
        defer { appPolicyLock.unlock() }
        let now = CACurrentMediaTime()
        if let cached = appPolicies[pid], now - cached.at < 30 { return cached.regular }
        let regular = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
        appPolicies[pid] = (regular, now)
        return regular
    }

    private static let appPolicyLock = NSLock()
    nonisolated(unsafe) private static var appPolicies: [pid_t: (regular: Bool, at: CFTimeInterval)] = [:]

    /// The window's true frame. ScreenCaptureKit reports transformed frames during
    /// Mission Control and similar animations; the Accessibility API doesn't.
    private func realFrame(of sc: SCWindow, ax: AXUIElement?) -> CGRect {
        if let ax, let p = AX.position(ax), let s = AX.size(ax), s.width > 0, s.height > 0 {
            return CGRect(origin: p, size: s)
        }
        return sc.frame
    }

    /// What a window scan needs to know about tracked windows, gathered on the main thread.
    private struct ScanInput {
        /// Tracked windows: their Accessibility element, where the real window should be, and
        /// whether it's parked (then anywhere in the corner will do).
        var tracked: [CGWindowID: (ax: AXUIElement?, expected: CGRect?, parked: Bool)] = [:]
        var kinds: [CGWindowID: WindowKind] = [:]
        /// Live mode: tracked windows' real frames matter (zoomed out, they aren't followed).
        var live = false
        /// Top-left of the parking corner (see inParkingCorner).
        var corner = CGPoint.zero
        /// Window moves so far and the camera, when the scan started: if either has changed by
        /// the time it's applied, its frames are out of date (see apply).
        var moves = 0
        var camera = Camera()
    }

    /// Whether a window is a standard document window, as Accessibility said when last asked.
    struct WindowKind {
        var standard: Bool
        var at: CFTimeInterval
    }
    /// Window kinds don't change, so each window is asked once. "Not standard" is asked again
    /// after a while: a brand-new window can briefly report no subrole.
    private var windowKinds: [CGWindowID: WindowKind] = [:]

    private func scanInput() -> ScanInput {
        var input = ScanInput(kinds: windowKinds, live: !isActive && !suspendTracking,
                              corner: CGPoint(x: screenRectCG.maxX - 12, y: screenRectCG.maxY - 80),
                              moves: ManagedWindow.moves, camera: camera)
        let vp = viewport
        for w in windows {
            var expected: CGRect?
            if let last = w.lastPlaced {
                expected = CGRect(origin: last, size: w.canvasFrame.size)
            } else if !w.parked, !isActive {
                expected = camera.toView(w.canvasFrame).offsetBy(dx: vp.minX, dy: vp.minY)
            }
            input.tracked[w.id] = (w.knownAX, expected, w.parked)
        }
        return input
    }

    /// What the Accessibility API says about windows: true frames by window ID (ScreenCaptureKit
    /// reports transformed frames during Mission Control and similar animations), which windows
    /// are standard document windows (as opposed to sheets, dialogs and panels), and elements for
    /// new ones. Apps are only asked about windows that need it: a tracked window whose
    /// ScreenCaptureKit frame is where it should be is left alone, and each window's kind is
    /// asked once, so a scan with nothing new costs no Accessibility calls at all.
    private struct AXSnapshot {
        var frames: [CGWindowID: CGRect] = [:]
        var standard = Set<CGWindowID>()
        var known = Set<CGWindowID>()
        var elements: [CGWindowID: AXUIElement] = [:]
        var kinds: [CGWindowID: WindowKind] = [:]
        var calls = 0
        /// Window server stacking order (live mode only).
        var order: [CGWindowID: Int] = [:]
    }

    private static func axSnapshot(for scWindows: [SCWindow], input: ScanInput) -> AXSnapshot {
        var snapshot = AXSnapshot()
        let now = CACurrentMediaTime()
        var kinds = input.kinds
        var toClassify: [pid_t: Set<CGWindowID>] = [:]
        var regularApps: [pid_t: Bool] = [:]
        func close(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
        }
        for sc in scWindows where sc.windowLayer == 0 {
            guard let pid = sc.owningApplication?.processID, pid != getpid() else { continue }
            let id = sc.windowID
            if let tracked = input.tracked[id] {
                guard input.live else { continue }
                if let expected = tracked.expected, close(sc.frame, expected) { continue }
                if tracked.parked, sc.frame.minX >= input.corner.x, sc.frame.minY >= input.corner.y { continue }
                if let ax = tracked.ax, let p = AX.position(ax), let s = AX.size(ax), s.width > 0, s.height > 0 {
                    snapshot.frames[id] = CGRect(origin: p, size: s)
                }
                snapshot.calls += 2
                continue
            }
            // Not manageable anyway (see isManageable): no need to ask.
            guard sc.isOnScreen, sc.frame.width >= 100, sc.frame.height >= 60 else { continue }
            if regularApps[pid] == nil { regularApps[pid] = isRegularApp(pid) }
            guard regularApps[pid] == true else { continue }
            if let kind = kinds[id], !kind.standard, now - kind.at < 10 {
                snapshot.known.insert(id)
                continue
            }
            // Standard but untracked (new, or back on screen): its element and frame are needed.
            toClassify[pid, default: []].insert(id)
        }
        for (pid, ids) in toClassify {
            var found = Set<CGWindowID>()
            snapshot.calls += 1
            for element in AX.windows(pid: pid) {
                guard let id = AX.windowID(element), ids.contains(id) else { continue }
                found.insert(id)
                snapshot.known.insert(id)
                let standard = kinds[id]?.standard == true || AX.subrole(element) == kAXStandardWindowSubrole as String
                snapshot.calls += 1
                kinds[id] = WindowKind(standard: standard, at: now)
                guard standard else { continue }
                snapshot.standard.insert(id)
                snapshot.elements[id] = element
                if let p = AX.position(element), let s = AX.size(element), s.width > 0, s.height > 0 {
                    snapshot.frames[id] = CGRect(origin: p, size: s)
                }
                snapshot.calls += 2
            }
            // Not one of the app's Accessibility windows (yet): not managed; look again later.
            for id in ids.subtracting(found) {
                kinds[id] = WindowKind(standard: false, at: now)
                snapshot.known.insert(id)
            }
        }
        let onScreen = Set(scWindows.map(\.windowID))
        snapshot.kinds = kinds.filter { onScreen.contains($0.key) || input.tracked[$0.key] != nil }
        return snapshot
    }

    /// Windows open now (see LayoutStore.takeMatch), from the last scan.
    private var openWindowKeys = Set<String>()

    /// `stale`: the windows' frames are out of date; only new and gone windows count.
    private func apply(_ scWindows: [SCWindow], ax: AXSnapshot, stale: Bool = false) {
        let axFrames = ax.frames
        if firstSync { logger.info("first sync: \(scWindows.count) SC windows, AX known \(ax.known.count), standard \(ax.standard.count), frames \(ax.frames.count)") }
        let started = CACurrentMediaTime()
        defer {
            let ms = Int((CACurrentMediaTime() - started) * 1000)
            if ms > 30 { logger.info("slow: window sync took \(ms)ms") }
        }
        noteSystemPrompts(scWindows)
        let live = !isActive && !suspendTracking && !stale
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

        let byID = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        openWindowKeys = Set(scWindows.compactMap { sc in
            sc.owningApplication.map { LayoutStore.windowKey(pid: $0.processID, id: sc.windowID) }
        })
        var regularApps: [pid_t: Bool] = [:]
        func regular(_ pid: pid_t) -> Bool {
            if let known = regularApps[pid] { return known }
            let r = Self.isRegularApp(pid)
            regularApps[pid] = r
            return r
        }
        for sc in scWindows where isManageable(sc, tracked: byID[sc.windowID] != nil, regular: regular) {
            // Only ordinary document windows live on the canvas. Sheets (like Xcode's Manage
            // Certificates), dialogs and floating panels belong to their parent window and stay
            // wherever the app puts them; moving or parking them separately pulls them away from it.
            if ax.known.contains(sc.windowID) && !ax.standard.contains(sc.windowID) { continue }
            if byID[sc.windowID] == nil && !ax.standard.contains(sc.windowID) { continue }
            seen.insert(sc.windowID)
            if let w = byID[sc.windowID] {
                // Zoomed out, positions aren't followed, so skip asking each app (slow apps
                // would stall dragging); ScreenCaptureKit's frame is good enough for sizes.
                let f = live ? (axFrames[sc.windowID] ?? sc.frame) : sc.frame
                w.scWindow = sc
                if let title = sc.title { w.title = title }
                if live && inParkingCorner(f.origin) {
                    w.parked = true
                    w.lastPlaced = f.origin
                } else if live {
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
                if !stale { adoptSize(w, f.size) }
            } else if !stale {
                restoredAny = add(sc, live: live, element: ax.elements[sc.windowID], frame: axFrames[sc.windowID]) || restoredAny
            }
        }

        for w in windows where !seen.contains(w.id) {
            remove(w)
        }

        if live { orderByWindowServer(ax.order) }
        if firstSync && restoredAny {
            // Back where the saved layout had them, without holding up launch.
            commitInBackground()
            view.render()
        }
        firstSync = false
        hasSynced = true
        if isActive { view.render() }
        scheduleSave()
    }

    /// Returns true if the window was put back where a saved layout had it.
    @discardableResult
    private func add(_ sc: SCWindow, live: Bool, element: AXUIElement? = nil, frame: CGRect? = nil) -> Bool {
        let w = ManagedWindow(scWindow: sc, canvasFrame: .zero)
        if let element { w.adopt(ax: element) }
        let f = frame ?? realFrame(of: sc, ax: w.ax)
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
        var returning = recentlyRemoved[w.id] != nil
        if let back = recentlyRemoved.removeValue(forKey: w.id) {
            // Came back (minimised, hidden, another Space, briefly missing during a display
            // change): same spot, same macOS original and chosen size.
            w.canvasFrame.origin = back.canvasFrame.origin
            w.originalFrame = back.originalFrame
            w.preferredSize = back.preferredSize
            w.home = back.home
        } else if let match = LayoutStore.takeMatch(bundleID: w.bundleID, title: w.title, id: w.id, pid: w.pid,
                                                    open: openWindowKeys, from: &savedPool) {
            // A saved spot: at launch, or an app opened later that had windows last time.
            w.canvasFrame.origin = CGPoint(x: match.x, y: match.y)
            if let pw = match.pw, let ph = match.ph { w.preferredSize = CGSize(width: pw, height: ph) }
            if let hx = match.hx, let hy = match.hy { w.home = CGPoint(x: hx, y: hy) }
            if let sw = match.w, let sh = match.h, let ax = w.ax,
               abs(sw - f.width) > 1 || abs(sh - f.height) > 1 {
                // Quitting put the macOS size back; restore the canvas size.
                let actual = resizeReal(w, ax, to: CGSize(width: sw, height: sh))
                w.canvasFrame.size = actual
                logger.info("restore size \(w.appName, privacy: .public)[\(w.id)] \(NSStringFromSize(f.size), privacy: .public) -> \(NSStringFromSize(actual), privacy: .public)")
            }
            if !firstSync { returning = true }
            if saved?.cleanExit != true, let ox = match.ox, let oy = match.oy, let ow = match.ow, let oh = match.oh {
                // Last run didn't put windows back; its record of the macOS layout is the real one.
                w.originalFrame = CGRect(x: ox, y: oy, width: ow, height: oh)
            }
            restored = true
        } else if inParkingCorner(f.origin) {
            // In the parking corner with no record of where it belongs (a previous run that
            // didn't exit cleanly, or a lost record): bring it out where it can be seen.
            global = CGPoint(x: viewport.midX - f.width / 2, y: viewport.minY + 40)
            w.place(at: global)
            w.lastPlaced = nil
            w.canvasFrame.origin = canvasPoint(forGlobal: global)
        }

        // A window opened (or came back) while Expanse is running, not one found at launch.
        let anchor = windows.last { !$0.parked }
        let arriving = !firstSync && !suspendTracking

        windows.append(w)
        w.node.setContentsScale(screen.backingScaleFactor)
        view.addNode(w.node)
        w.capture.onFrame = { [weak self, weak w] surface in
            guard let self, let w else { return }
            // Runs inside the frame pump's transaction (actions disabled).
            w.node.content.contents = surface
            w.pictureWidth = IOSurfaceGetWidth(surface)
            if w.node.content.backgroundColor != nil { w.node.content.backgroundColor = nil }
            if w.needsFirstFrame {
                w.needsFirstFrame = false
                if self.wantsCapture(w, in: self.captureRegion).start { self.scheduleCaptureUpdate() }
            }
        }
        w.capture.onStop = { [weak self, weak w] in
            guard let self, let w else { return }
            self.remove(w)
        }
        // Its first picture comes from a one-off snapshot (see pumpSnapshots), not a stream.
        pumpSnapshotsSoon()
        observe(w)
        logger.info("tracking \(w.appName, privacy: .public) [\(w.id)] \(w.title, privacy: .private)")
        if arriving { arrive(w, anchor: anchor, live: live, returning: returning) }
        return restored
    }

    // MARK: Spatial navigation

    enum Direction { case left, right, up, down }
    /// A live-mode glide is running: the overlay is up, but it isn't canvas mode.
    private(set) var gliding = false
    private var glideGeneration = 0
    /// At least one window scan has succeeded since launch / resume.
    private var hasSynced = false
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
        } else if let app = NSWorkspace.shared.frontmostApplication, let w = focusedWindow(of: app.processIdentifier) {
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
        // With auto-centre on, every hop centres its window: a hop that only moved focus to a
        // window already on screen looked like nothing happened, and the next press skipped on.
        let r = camera.toView(target.canvasFrame)
        if !autoCentre, !target.parked, CGRect(origin: .zero, size: viewSize).insetBy(dx: -1, dy: -1).contains(r) {
            bringToFront(target)
            focusWindow(target)
            view.render()
        } else {
            glide(to: target)
        }
    }

    /// Each app's focused window, kept from its focus-change notifications and our own focusing,
    /// so a hop doesn't wait on the app to say (50ms+ for a busy one) before it can start.
    private var focusedWindowByApp: [pid_t: CGWindowID] = [:]

    private func focusedWindow(of pid: pid_t) -> ManagedWindow? {
        if let id = focusedWindowByApp[pid], let w = windows.first(where: { $0.id == id }) { return w }
        guard let focused = AX.focusedWindow(pid: pid), let id = AX.windowID(focused) else { return nil }
        focusedWindowByApp[pid] = id
        return windows.first { $0.id == id }
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
                // Equal gaps (two windows snapped below one): the better-aligned one wins.
                let score = gap + r.center.distance(to: from.center) / 1000
                if score < (inLine?.1 ?? .infinity) { inLine = (i, score) }
            } else if withinCone {
                let d = r.center.distance(to: from.center)
                if d < (inCone?.1 ?? .infinity) { inCone = (i, d) }
            }
        }
        return inLine?.0 ?? inCone?.0
    }

    // MARK: System prompts

    /// On-screen windows of background system processes (permission reminders, password and
    /// security prompts). Expanse doesn't manage them, but must never bury them.
    private var systemPrompts: [(pid: pid_t, id: CGWindowID)] = []

    private func noteSystemPrompts(_ scWindows: [SCWindow]) {
        let prompts = scWindows.compactMap { w -> (pid_t, CGWindowID)? in
            guard w.windowLayer == 0, w.isOnScreen, w.frame.width >= 150, w.frame.height >= 80,
                  screenRectCG.intersects(w.frame),
                  let pid = w.owningApplication?.processID, pid != getpid(),
                  // Apple's background prompt processes only (universalAccessAuthWarn,
                  // SecurityAgent, UserNotificationCenter, CoreServicesUIAgent, …).
                  w.owningApplication?.bundleIdentifier.hasPrefix("com.apple.") == true,
                  NSRunningApplication(processIdentifier: pid) != nil, !Self.isRegularApp(pid)
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
        let prompts = systemPrompts
        guard !prompts.isEmpty else { return }
        axQueue.async {
            for prompt in prompts {
                guard let ax = AX.windows(pid: prompt.pid).first(where: { AX.windowID($0) == prompt.id }) else { continue }
                AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
                logger.info("raised system prompt [\(prompt.id)]")
            }
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
        guard !gliding else { whenIdle { [weak self] in self?.tidy() }; return }
        guard isActive else {
            enter(zoomOut: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.isActive == true { self?.tidy() }
            }
            return
        }
        guard !windows.isEmpty else { return }
        fitLayoutToScreen(margin: 16, tidy: true)
        view.render()
        animate(to: fitCamera())
        scheduleSave()
    }

    /// True while the canvas is a tightened version of the home layout: some window is smaller
    /// than its chosen size because this screen is smaller.
    var isDerived: Bool {
        windows.contains { $0.preferredSize.width > 0 &&
            ($0.canvasFrame.width < $0.preferredSize.width - 1 || $0.canvasFrame.height < $0.preferredSize.height - 1) }
    }

    /// You moved a window (dragging on the canvas or for real). On a smaller screen the home
    /// layout moves by the same amount, so the move survives going back to the big screen.
    func noteUserMove(_ w: ManagedWindow, from before: CGPoint) {
        guard isDerived else { return }
        let home = w.home ?? before
        w.home = CGPoint(x: home.x + w.canvasFrame.minX - before.x, y: home.y + w.canvasFrame.minY - before.y)
    }

    /// Fit the layout to this screen. Sizes: what you chose, capped at the screen. Positions: the
    /// home layout, tightened by however much windows shrank, so every gap (inside groups and
    /// between them) keeps its size; on the big screen that's the home layout exactly. With
    /// `tidy`, the home layout itself is cleaned up first (overlaps apart, clusters to 20pt).
    private func fitLayoutToScreen(margin: CGFloat, tidy: Bool) {
        let maxSize = CGSize(width: viewSize.width - margin * 2, height: viewSize.height - margin * 2)
        var home = windows.map {
            CGRect(origin: $0.home ?? $0.canvasFrame.origin,
                   size: $0.preferredSize.width > 0 ? $0.preferredSize : $0.canvasFrame.size)
        }
        if tidy {
            Self.separate(&home, gap: Self.gap)
            Self.gravity(&home, clusters: Self.clusters(home, reach: Self.clusterReach), gap: Self.gap)
            Self.separate(&home, gap: Self.gap)
            for (w, h) in zip(windows, home) { w.home = CGPoint(x: h.minX.rounded(), y: h.minY.rounded()) }
        }
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

        let origins = Self.derive(home: home, sizes: windows.map(\.canvasFrame.size))
        var frames = zip(origins, windows).map { CGRect(origin: $0, size: $1.canvasFrame.size) }
        // Only overlaps this screen caused, pushed apart to the standard gap. Windows you have
        // overlapping in the home layout stay that way (pushing them apart would push everything
        // below and to the right too, and the move would stick when you're back on the big screen).
        Self.separate(&frames, gap: Self.gap, onlyOverlaps: true, keep: Self.overlappingPairs(home))
        var moved = 0
        for (w, f) in zip(windows, frames) {
            let rounded = CGPoint(x: f.minX.rounded(), y: f.minY.rounded())
            if rounded.distance(to: w.canvasFrame.origin) >= 1 { moved += 1 }
            w.canvasFrame.origin = rounded
        }
        logger.info("layout fitted: \(moved) of \(self.windows.count) windows moved, derived=\(self.isDerived)")
    }

    /// Positions for windows of `sizes` that keep the `home` layout's gaps where you see them: each
    /// window keeps its distance to its nearest window on the left (and above), whether that's a
    /// snapped neighbour or the next group over, so shrinking windows pull the layout in. With
    /// home sizes this returns the home positions exactly. Callers push apart any overlap left.
    static func derive(home: [CGRect], sizes: [CGSize]) -> [CGPoint] {
        func span(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> CGFloat {
            max(0, max(a0, b0) - min(a1, b1))   // distance between ranges; 0 when they overlap
        }
        var x = home.map(\.minX), y = home.map(\.minY)
        for i in home.indices.sorted(by: { home[$0].minX < home[$1].minX }) {
            let left = home.indices.filter { $0 != i && home[$0].maxX <= home[i].minX + 0.5 }
            // Nearest: the horizontal gap, with rows that don't line up counting extra.
            if let j = left.min(by: {
                (home[i].minX - home[$0].maxX) + 2 * span(home[$0].minY, home[$0].maxY, home[i].minY, home[i].maxY) <
                (home[i].minX - home[$1].maxX) + 2 * span(home[$1].minY, home[$1].maxY, home[i].minY, home[i].maxY)
            }) {
                x[i] = x[j] + sizes[j].width + (home[i].minX - home[j].maxX)
            }
        }
        for i in home.indices.sorted(by: { home[$0].minY < home[$1].minY }) {
            let above = home.indices.filter { $0 != i && home[$0].maxY <= home[i].minY + 0.5 }
            if let j = above.min(by: {
                (home[i].minY - home[$0].maxY) + 2 * span(home[$0].minX, home[$0].maxX, home[i].minX, home[i].maxX) <
                (home[i].minY - home[$1].maxY) + 2 * span(home[$1].minX, home[$1].maxX, home[i].minX, home[i].maxX)
            }) {
                y[i] = y[j] + sizes[j].height + (home[i].minY - home[j].maxY)
            }
        }
        return zip(x, y).map { CGPoint(x: $0, y: $1) }
    }

    /// Push overlapping frames apart in reading order. Only ever moving right or down means it
    /// always finishes.
    /// `keep`: pairs of windows (by index) left overlapping, see overlappingPairs.
    static func separate(_ frames: inout [CGRect], gap: CGFloat, onlyOverlaps: Bool = false, keep: Set<IndexPair> = []) {
        let order = frames.indices.sorted { (frames[$0].minY, frames[$0].minX) < (frames[$1].minY, frames[$1].minX) }
        var settled: [(index: Int, frame: CGRect)] = []
        for i in order {
            var r = frames[i]
            for _ in 0..<200 {
                let reach = onlyOverlaps ? 0.5 : -gap + 0.5
                guard let hit = settled.first(where: {
                    !keep.contains(IndexPair($0.index, i)) && $0.frame.insetBy(dx: reach, dy: reach).intersects(r)
                })?.frame else { break }
                let right = hit.maxX + gap - r.minX
                let down = hit.maxY + gap - r.minY
                if right <= down { r.origin.x += right } else { r.origin.y += down }
            }
            frames[i] = r
            settled.append((i, r))
        }
    }

    /// Two indices, unordered.
    struct IndexPair: Hashable {
        let a: Int, b: Int
        init(_ i: Int, _ j: Int) { a = min(i, j); b = max(i, j) }
    }

    /// Pairs of frames that overlap.
    static func overlappingPairs(_ frames: [CGRect]) -> Set<IndexPair> {
        var pairs = Set<IndexPair>()
        for i in frames.indices {
            for j in frames.indices where j > i && frames[i].insetBy(dx: 0.5, dy: 0.5).intersects(frames[j]) {
                pairs.insert(IndexPair(i, j))
            }
        }
        return pairs
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
        } else if windowKinds[w.id]?.standard ?? (AX.subrole(w.ax) == kAXStandardWindowSubrole as String),
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
        if !isPaused {
            recentlyRemoved[w.id] = Departed(pid: w.pid, canvasFrame: w.canvasFrame, originalFrame: w.originalFrame,
                                             preferredSize: w.preferredSize, home: w.home, parked: w.parked, at: Date())
            // Closed windows never come back; don't keep them forever.
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
            recentlyRemoved = recentlyRemoved.filter { $0.value.at > weekAgo }
            if recentlyRemoved.count > 300, let oldest = recentlyRemoved.min(by: { $0.value.at < $1.value.at })?.key {
                recentlyRemoved.removeValue(forKey: oldest)
            }
        }
        if view.hovered === w { view.hovered = nil }
        if isActive { view.render() }
    }

    /// The window server's stacking order (0 = front-most). It takes 10-80ms with many windows
    /// open, so it's fetched off the main thread, during a window scan.
    private static func windowServerOrder() -> [CGWindowID: Int] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [:] }
        var rank: [CGWindowID: Int] = [:]
        for (i, entry) in info.enumerated() {
            if let n = entry[kCGWindowNumber as String] as? Int { rank[CGWindowID(n)] = i }
        }
        return rank
    }

    /// Match canvas stacking to the real window stacking (front-most last).
    private func orderByWindowServer(_ rank: [CGWindowID: Int]) {
        guard !rank.isEmpty else { return }
        let sorted = windows.sorted { (rank[$0.id] ?? .max) > (rank[$1.id] ?? .max) }
        guard sorted.map(\.id) != windows.map(\.id) else { return }
        windows = sorted
        for w in windows { view.bringToFront(w.node) }
    }

    // MARK: Capture

    /// Canvas area the camera sweeps through in the animation or glide under way (nil when still).
    private var pathRegion: CGRect?

    /// The canvas area whose pictures can be on screen now.
    private var captureRegion: CGRect {
        let inView = camera.toCanvas(CGRect(origin: .zero, size: viewSize))
        return pathRegion.map { $0.union(inView) } ?? inView
    }

    /// Every stream costs the window server work, and macOS marks every captured window with a
    /// purple indicator, so Expanse only captures pictures that can be seen: on the canvas and
    /// during glides, windows in view or on the camera's path (the overlay covers the indicators);
    /// at 100%, parked windows whose stand-in shows on the backdrop. Each window is captured once
    /// when first seen; a paused window keeps its last picture. `start`: capture it; `keep`: don't
    /// stop yet (a wider margin, so panning back and forth doesn't restart streams).
    private func wantsCapture(_ w: ManagedWindow, in region: CGRect) -> (start: Bool, keep: Bool) {
        if w.needsFirstFrame { return (true, true) }
        guard isActive || w.parked else { return (false, false) }
        let near = region.insetBy(dx: -region.width * 0.1, dy: -region.height * 0.1)
        let far = region.insetBy(dx: -region.width * 0.35, dy: -region.height * 0.35)
        // Parked windows' streams linger a few seconds after the canvas or a glide (nothing on
        // screen shows they're captured), so going straight back reuses them instead of
        // restarting dozens of streams.
        let lingering = !isActive && CACurrentMediaTime() < lingerUntil
        return (near.intersects(w.canvasFrame), lingering || far.intersects(w.canvasFrame))
    }

    private var lingerUntil: CFTimeInterval = 0
    private var lingerWork: DispatchWorkItem?

    /// After leaving the canvas or a glide: stop on-screen windows' streams now, the rest later.
    private func updateStreamingLingering() {
        lingerUntil = CACurrentMediaTime() + 5
        updateStreaming()
        lingerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isActive else { return }
            self.updateStreaming()
        }
        lingerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.05, execute: work)
    }

    /// replayd, which runs every ScreenCaptureKit stream on the Mac, runs out of file descriptors
    /// (256, about six a stream) at around 35-50 streams, other apps' included, and a stream
    /// started after that never delivers a frame, without any error. So Expanse streams at most
    /// this many windows, the ones that matter most, leaving room for screen sharing and the
    /// like; the other windows in view get one-off pictures in turn.
    private static let streamBudget = 16

    /// `reconfigure`: also bring running streams to the size they should have now (which restarts
    /// them; see WindowCapture.update). While the camera moves this is left to
    /// scheduleCaptureUpdate's settle pass, so streams aren't restarted over and over as windows
    /// cross size steps.
    func updateStreaming(reconfigure: Bool = true) {
        let t0 = CACurrentMediaTime()
        let region = captureRegion
        let wants = windows.map { wantsCapture($0, in: region) }
        // Most important first: the glide's target, then the most on screen (now or where the
        // camera is heading), then the nearest. Windows still waiting for a first picture get it
        // from a snapshot, not a stream.
        let screen = CGRect(origin: .zero, size: viewSize)
        let target = animation?.to
        let focus = (target ?? camera).center(in: viewSize)
        func shown(_ w: ManagedWindow) -> CGFloat {
            func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
            var a = area(camera.toView(w.canvasFrame).intersection(screen))
            if let target { a = max(a, area(target.toView(w.canvasFrame).intersection(screen))) }
            return w === glideTarget ? .infinity : a
        }
        // A glide at 100% only streams what's on screen where it starts and where it lands:
        // windows it passes on the way are seen for a few frames, and their pictures are sharp
        // already (see livePictureSize).
        typealias Candidate = (w: ManagedWindow, shown: CGFloat, distance: CGFloat)
        var candidates: [Candidate] = []
        for (w, want) in zip(windows, wants) where want.start && !w.needsFirstFrame {
            let c: Candidate = (w, shown(w), w.canvasFrame.center.distance(to: focus))
            if !gliding || c.shown > 0 { candidates.append(c) }
        }
        candidates.sort { $0.shown != $1.shown ? $0.shown > $1.shown : $0.distance < $1.distance }
        let ranked: [ManagedWindow] = candidates.map { $0.w }
        // At 100% nothing streams: what shows of parked windows is a sliver at the edge of the
        // screen, and a snapshot every second or so looks the same as a stream for a fraction of
        // the memory (a stream keeps a pool of full-size buffers).
        let budget = isActive ? Self.streamBudget : 0
        var streamed = Set(ranked.prefix(budget).map(\.id))
        // Spare places keep streams that are still nearby running (no churn at the margins, and
        // streams linger after the canvas; see wantsCapture).
        let keepRunning = isActive || CACurrentMediaTime() < lingerUntil
        for (w, want) in zip(windows, wants) where keepRunning && streamed.count < Self.streamBudget
            && want.keep && w.capture.isRunning && !w.needsFirstFrame {
            streamed.insert(w.id)
        }
        snapshotQueue = ranked.filter { !streamed.contains($0.id) }.map(\.id)
        captureLoad = min(ranked.count, budget)
        var toStart: [ManagedWindow] = []
        for w in ranked where streamed.contains(w.id) {
            if !w.capture.isRunning {
                toStart.append(w)
            } else if reconfigure {
                updateCapture(w)
            }
        }
        for w in windows where w.capture.isRunning && !streamed.contains(w.id) {
            w.capture.pause()
        }
        // A few start per pass (the most important first), the rest on the next ones, so a
        // zoom-out doesn't send replayd a burst of requests at once.
        for w in toStart.prefix(Self.streamStartsPerPass) {
            w.capture.start(window: w.scWindow, pixelSize: pixelSize(for: w), fps: captureFPS(for: w))
        }
        if toStart.count > Self.streamStartsPerPass, !moreStartsQueued {
            moreStartsQueued = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                self?.moreStartsQueued = false
                self?.updateStreaming(reconfigure: false)
            }
        }
        pumpSnapshotsSoon()
        let running = windows.filter { $0.capture.isRunning }.count
        if running != lastCaptureCount {
            lastCaptureCount = running
            logger.info("capturing \(running) of \(self.windows.count) windows, \(self.snapshotQueue.count) more by snapshot")
        }
        let ms = (CACurrentMediaTime() - t0) * 1000
        if ms > 8 { logger.info("slow: updating captures took \(Int(ms))ms (\(min(toStart.count, Self.streamStartsPerPass)) started)") }
    }

    // MARK: Snapshots

    /// Windows in view that don't get a stream, most important first (set by updateStreaming).
    private var snapshotQueue: [CGWindowID] = []
    private var snapshotsInFlight = 0
    private var snapshotTimer: Timer?

    private func pumpSnapshotsSoon() {
        guard snapshotTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.pumpSnapshots() }
        RunLoop.main.add(timer, forMode: .common)
        snapshotTimer = timer
        pumpSnapshots()
    }

    /// One-off pictures, three at a time: first pictures of new windows as fast as they come;
    /// on the canvas, fresh pictures of windows in view without a stream, about ten a second in
    /// all and each at most every 1.5s; at 100%, full-size pictures of parked windows whose last
    /// one is a thumbnail from the canvas, nearest first, four a second (a glide shows them before
    /// their streams catch up). A window whose snapshot fails is tried again later and later.
    private func pumpSnapshots() {
        let now = CACurrentMediaTime()
        func due(_ w: ManagedWindow, every interval: CFTimeInterval) -> Bool {
            now - w.lastSnapshotAt > interval * pow(2, Double(min(w.snapshotFailures, 5)))
        }
        let firsts = windows.filter { $0.needsFirstFrame && !$0.capture.isRunning && due($0, every: 2) }
        let byID = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // (At 100% they're slivers at the edge of the screen: every 3s is plenty.)
        var refresh = snapshotQueue.compactMap { byID[$0] }.filter { due($0, every: isActive ? 1.5 : 3) }
            .sorted { $0.lastSnapshotAt < $1.lastSnapshotAt }
        let blurry = isActive ? [] : windows.filter(pictureNeedsResizing)
        if refresh.isEmpty, now - lastSharpening > 0.25 {
            let centre = camera.center(in: viewSize)
            refresh = blurry.filter { due($0, every: 3) }
                .sorted { $0.canvasFrame.center.distance(to: centre) < $1.canvasFrame.center.distance(to: centre) }
            if !refresh.isEmpty { lastSharpening = now }
        }
        guard !firsts.isEmpty || !refresh.isEmpty else {
            if snapshotsInFlight == 0, snapshotQueue.isEmpty, blurry.isEmpty, !windows.contains(where: \.needsFirstFrame) {
                snapshotTimer?.invalidate()
                snapshotTimer = nil
            }
            return
        }
        var next = firsts
        if next.isEmpty, let w = refresh.first { next = [w] }
        for w in next where snapshotsInFlight < 3 {
            snapshotsInFlight += 1
            w.lastSnapshotAt = now
            let size = isActive ? pixelSize(for: w) : livePictureSize(for: w)
            w.capture.snapshot(window: w.scWindow, pixelSize: size) { [weak self, weak w] ok in
                self?.snapshotsInFlight -= 1
                if let w { w.snapshotFailures = ok ? 0 : w.snapshotFailures + 1 }
            }
        }
    }

    private var lastSharpening: CFTimeInterval = 0

    /// At 100%, the picture a window should have: full size near the view (within half a screen
    /// of it: where a hop is likely to go, so the glide shows it sharp), a quarter of that further
    /// away (full-size pictures of 50 windows would take the best part of a gigabyte).
    private func livePictureSize(for w: ManagedWindow) -> CGSize {
        let view = camera.toCanvas(CGRect(origin: .zero, size: viewSize))
        let near = view.insetBy(dx: -view.width / 2, dy: -view.height / 2).intersects(w.canvasFrame)
        let factor: CGFloat = near ? 1 : 0.25
        let backing = screen.backingScaleFactor
        return CGSize(width: w.canvasFrame.width * backing * factor, height: w.canvasFrame.height * backing * factor)
    }

    /// At 100%: a parked window not being streamed whose picture is well off the size it should
    /// have: a thumbnail from the canvas near the view, or a full-size picture far from it.
    private func pictureNeedsResizing(_ w: ManagedWindow) -> Bool {
        guard w.parked, !w.capture.isRunning, !w.needsFirstFrame else { return false }
        let want = livePictureSize(for: w).width, have = CGFloat(w.pictureWidth)
        return have < want * 0.9 || have > want * 2.5
    }

    private static let streamStartsPerPass = 10
    private var moreStartsQueued = false
    private var lastCaptureCount = -1

    private var captureUpdatePending = false
    private var captureSettleWork: DispatchWorkItem?

    /// While the camera moves: start streams for windows coming into view and stop the ones that
    /// left, at most every 0.15s; once it has been still for 0.3s, sizes and frame rates follow.
    private func scheduleCaptureUpdate() {
        if !captureUpdatePending {
            captureUpdatePending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                self.captureUpdatePending = false
                self.updateStreaming(reconfigure: false)
            }
        }
        captureSettleWork?.cancel()
        let settle = DispatchWorkItem { [weak self] in self?.updateStreaming() }
        captureSettleWork = settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: settle)
    }

    private var streamingWork: DispatchWorkItem?

    /// After handing back to the real windows: keep capturing a moment longer (quick successive
    /// hops reuse the streams), then stop for windows that are on screen.
    private func updateStreamingSoon() {
        streamingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isActive else { return }
            self.updateStreamingLingering()
        }
        streamingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // MARK: Capture resolution

    /// The zoom a window is seen at: now, or where the camera is heading if that's closer, so a
    /// window being zoomed into is sharp on arrival and one being zoomed away from starts small.
    private func viewScale(for w: ManagedWindow) -> CGFloat {
        guard isActive else { return 1 }
        let screen = CGRect(origin: .zero, size: viewSize)
        var s: CGFloat = camera.toView(w.canvasFrame).intersects(screen) ? camera.scale : 0
        if let a = animation, a.to.toView(w.canvasFrame).intersects(screen) { s = max(s, a.to.scale) }
        return s > 0 ? s : camera.scale
    }

    /// Streams are captured at roughly the on-screen pixel size, in power-of-two steps (so zooming
    /// doesn't reconfigure them all the time), down to 1/16.
    private func pixelSize(for w: ManagedWindow) -> CGSize {
        let backing = screen.backingScaleFactor
        let s = viewScale(for: w)
        var factor: CGFloat = 1
        while factor > 1.0 / 16, s < factor * 0.7 { factor /= 2 }
        return CGSize(width: w.canvasFrame.width * backing * factor, height: w.canvasFrame.height * backing * factor)
    }

    /// How many windows are being captured for the view (set by updateStreaming).
    private var captureLoad = 0

    /// Small pictures don't need 30 frames a second, and with dozens of windows in view they
    /// share a budget of about 240 frames a second (every frame costs the window server a render
    /// and Expanse a hand-off), but never drop below 5.
    private func captureFPS(for w: ManagedWindow) -> Int {
        // (Not lower than the live rate: at 1 fps ScreenCaptureKit may never send a picture of a
        // window that isn't changing.)
        guard isActive else { return Self.liveFPS }
        let width = w.canvasFrame.width * viewScale(for: w)
        let bySize = width >= 500 ? Self.canvasFPS : width >= 200 ? 15 : 8
        let share = 240 / max(captureLoad, 1)
        return max(5, min(bySize, share))
    }

    private func updateCapture(_ w: ManagedWindow) {
        w.capture.update(pixelSize: pixelSize(for: w), fps: captureFPS(for: w))
    }

    // MARK: Modes

    func enter(zoomOut: Bool) {
        if isActive {
            if zoomOut { animate(to: overviewCamera()) }
            return
        }
        // Live tracking keeps the canvas current, so don't wait for a window scan (ScreenCaptureKit
        // can take a second to answer when it's busy); one runs right after to catch anything new.
        if hasSynced, !gliding {
            enterNow(zoomOut: zoomOut)
            sync()
        } else {
            sync { [weak self] in
                guard let self, !self.isActive else { return }
                self.enterNow(zoomOut: zoomOut)
            }
        }
    }

    private func enterNow(zoomOut: Bool) {
        isActive = true
        camera.scale = 1
        updateOverlayFrame()
        view.render()
        // Zooming out, the animation's capture pass covers its whole path; one for the 100% view
        // first would stop streams still warm from the last time.
        if !zoomOut { updateStreaming() }
        if CACurrentMediaTime() - lastWallpaperRefresh > 30 { refreshWallpaper() }
        NSApp.activate(ignoringOtherApps: true)
        overlay.level = OverlayWindow.canvasLevel
        overlay.makeKeyAndOrderFront(nil)
        overlay.makeFirstResponder(view)
        returnCamera = nil
        if zoomOut {
            returnCamera = camera
            animate(to: overviewCamera())
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
        animate(to: target, duration: 0.18) { [weak self] in
            guard let self else { return }
            // Like a glide's last step: input waits while the real windows move in the background.
            self.gliding = true
            self.commitAsync {
                let toFocus = focus ?? self.windows.last(where: { !$0.parked })
                if let toFocus {
                    self.focusWindow(toFocus)
                }
                // Give the window server a beat to show the moved windows, then sink the overlay
                // beneath them so it becomes the desktop.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    self.overlay.level = OverlayWindow.backdropLevel
                    self.isActive = false
                    self.gliding = false
                    self.pathRegion = nil
                    self.view.render()
                    self.updateStreamingLingering()
                }
            }
        }
    }

    /// Requires camera.scale == 1.
    private func commit() {
        for (w, target, parked) in commitPlan() {
            if !alreadyAt(w, target, parked: parked) { w.place(at: target) }
            w.parked = parked
        }
        // Newly hidden windows need a live picture for the backdrop; newly visible ones don't.
        if !isActive { updateStreaming() }
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

    private let axQueue = DispatchQueue(label: "com.invignation.expanse.ax", qos: .userInteractive)

    /// The real window is already where `target` would put it: where we last placed it, or, for
    /// a parked window, anywhere in the corner (macOS nudges parked windows, so they never land
    /// exactly on the park point and would otherwise be re-parked on every move).
    private func alreadyAt(_ w: ManagedWindow, _ target: CGPoint, parked: Bool) -> Bool {
        guard let last = w.lastPlaced else { return false }
        return last.distance(to: target) < 0.5 || (parked && w.parked && inParkingCorner(last))
    }

    /// Like commit(), but the Accessibility calls run off the main thread: a slow app (Chromium
    /// apps animate AX moves) can't stall animations or key presses. Each app gets a thread of its
    /// own: apps answer Accessibility calls one at a time, so a slow one (a browser with many
    /// windows) only holds up its own windows. The glide's target moves first. Apps with
    /// Chromium's enhanced-UI mode get it switched off while their windows move, then back on.
    private func commitAsync(_ completion: @escaping () -> Void) {
        let jobs = commitPlan().compactMap { (w, target, parked) -> (ManagedWindow, AXUIElement, CGPoint, Bool)? in
            if alreadyAt(w, target, parked: parked) { w.parked = parked; return nil }
            guard let ax = w.ax else { return nil }
            return (w, ax, target, parked)
        }
        guard !jobs.isEmpty else { scheduleSave(); completion(); return }
        let first = glideTarget?.id
        var byApp: [pid_t: [Int]] = [:]
        for (i, job) in jobs.enumerated() { byApp[job.0.pid, default: []].append(i) }
        let batches = byApp.map { pid, indices in
            (pid: pid, jobs: indices.filter { jobs[$0].0.id == first } + indices.filter { jobs[$0].0.id != first })
        }
        let work = jobs.map { (ax: $0.1, target: $0.2, parked: $0.3) }
        let started = CACurrentMediaTime()
        ManagedWindow.moves += 1
        axQueue.async {
            var landed = [CGPoint?](repeating: nil, count: work.count)
            var slowest: (pid: pid_t, ms: Int) = (0, 0)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: batches.count) { b in
                let batch = batches[b]
                let t0 = CACurrentMediaTime()
                let enhanced = AX.enhancedUserInterface(pid: batch.pid)
                if enhanced { AX.setEnhancedUserInterface(false, pid: batch.pid) }
                var results: [(Int, CGPoint?)] = []
                for i in batch.jobs {
                    AX.setPosition(work[i].ax, work[i].target)
                    // Where exactly a parked window lands doesn't matter (see alreadyAt).
                    results.append((i, work[i].parked ? nil : AX.position(work[i].ax)))
                }
                if enhanced { AX.setEnhancedUserInterface(true, pid: batch.pid) }
                let ms = Int((CACurrentMediaTime() - t0) * 1000)
                lock.lock()
                for (i, p) in results { landed[i] = p }
                if ms > slowest.ms { slowest = (batch.pid, ms) }
                lock.unlock()
            }
            let total = Int((CACurrentMediaTime() - started) * 1000)
            if total > 150 {
                let name = NSRunningApplication(processIdentifier: slowest.pid)?.localizedName ?? "pid \(slowest.pid)"
                logger.info("slow: moving \(work.count) windows took \(total)ms (\(name, privacy: .public): \(slowest.ms)ms)")
            }
            DispatchQueue.main.async {
                let now = CACurrentMediaTime()
                ManagedWindow.moves += 1
                for ((w, _, target, parked), at) in zip(jobs, landed) {
                    w.lastPlaced = at ?? target
                    w.lastPlacedAt = now
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
        cancelAnimation()
        settleBackgroundMoves()
        if !isPaused {
            save(cleanExit: true)
            isPaused = true
            restoreOriginals()
        }
        overlay.orderOut(nil)
        windows.forEach { $0.capture.stop() }
    }

    /// expanse://dump — geometry for debugging alignment between proxies and real windows.
    func dump() {
        logger.info("dump viewport=\(NSStringFromRect(self.viewport), privacy: .public) overlay=\(NSStringFromRect(self.overlay.frame), privacy: .public) view=\(NSStringFromRect(self.view.bounds), privacy: .public) camera=\(NSStringFromPoint(self.camera.origin), privacy: .public)@\(self.camera.scale) active=\(self.isActive) gliding=\(self.gliding) animating=\(self.animation != nil) paused=\(self.isPaused) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-", privacy: .public) focusedByApp=\(self.focusedWindowByApp.description, privacy: .public)")
        for w in windows {
            let axPos = w.ax.flatMap(AX.position).map { NSStringFromPoint($0) } ?? "nil"
            logger.info("dump \(w.appName, privacy: .public)[\(w.id)] sc=\(NSStringFromRect(w.scWindow.frame), privacy: .public) ax=\(axPos, privacy: .public) canvas=\(NSStringFromRect(w.canvasFrame), privacy: .public) layer=\(NSStringFromRect(w.node.container.frame), privacy: .public) parked=\(w.parked) capturing=\(w.capture.isRunning) first=\(w.needsFirstFrame) pic=\(w.pictureWidth) lastPlaced=\(w.lastPlaced.map { NSStringFromPoint($0) } ?? "nil", privacy: .public)")
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
    /// size. macOS, apps (Chromium animates AX resizes in steps) and Expanse itself resize windows
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
        scheduleCaptureUpdate()
    }

    // MARK: Animation

    func animate(to target: Camera, duration: CFTimeInterval = 0.22, completion: (() -> Void)? = nil) {
        animation = CameraAnimation(from: camera, to: target, start: CACurrentMediaTime(), duration: duration, completion: completion)
        if isActive {
            // Pictures for everything the camera will pass over, before it gets there.
            let screen = CGRect(origin: .zero, size: viewSize)
            pathRegion = (pathRegion ?? .null).union(camera.toCanvas(screen)).union(target.toCanvas(screen))
            updateStreaming()
        }
        if displayLink == nil {
            let link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    func cancelAnimation() {
        animation = nil
        stopDisplayLink()
        if !gliding { pathRegion = nil }
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
            if a.maxGap > 0.034 || a.firstFrame - a.start > 0.034 { logger.info("slow: animation \(self.lastAnimationStats, privacy: .public)") }
            camera = a.to
            animation = nil
            stopDisplayLink()
            // A glide keeps its path until it hands back; elsewhere the view is all that's left.
            if !gliding { pathRegion = nil }
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

        // The middle of the screen: a window dragged near it snaps to dead centre.
        let mid = camera.center(in: viewSize)
        consider(f.midX, mid.x, line: mid.x, span: CGRect(x: mid.x, y: f.minY, width: 0, height: f.height), into: &bestX)
        consider(f.midY, mid.y, line: mid.y, span: CGRect(x: f.minX, y: mid.y, width: f.width, height: 0), into: &bestY)

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
