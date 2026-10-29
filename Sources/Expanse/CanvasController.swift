import AppKit
import QuartzCore
import ScreenCaptureKit
import os

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
    /// You've put the view where you want it (panned at 100%): a window you can see that you
    /// click, or dive into, gets focus without the view moving to centre it. Over at the next
    /// glide (⌃ + arrows, ⌃⌥C, focus going to a window off screen), zoom or display change.
    private var viewPlaced = false
    private var dialogTimer: Timer?
    private var syncing = false
    /// The scan in flight (see sync): one given up on is told apart from the one after it.
    private var syncToken = 0
    /// The latest scan's token, for ScreenCaptureKit's answer to check on its own thread: an
    /// answer to a scan since given up on stops there, before asking every app about its windows.
    /// (A capture service that stops answering for hours can answer a thousand requests at once.)
    private let latestScan = OSAllocatedUnfairLock(initialState: 0)
    /// How long a scan may wait for ScreenCaptureKit. When macOS restarts its capture service
    /// (replayd), a request already sent never gets an answer, and without a limit no scan would
    /// ever run again: no new windows, and none of the dropped ones back. Doubled for each scan in
    /// a row that got none (to about five minutes), so a capture service that's stuck isn't sent a
    /// new request every ten seconds.
    private static let scanTimeout: TimeInterval = 10
    private var unansweredScans = 0
    /// No scan before this (CACurrentMediaTime): macOS refused the last one (see sync).
    private var scanRetryAt: CFTimeInterval = 0
    /// A scan was asked for while one was running: run another once it's done.
    private var syncAgain = false
    private var syncRetryScheduled = false
    private var pendingSyncCompletions: [() -> Void] = []
    private var firstSync = true
    private var saveWork: DispatchWorkItem?
    private var pinchAccumulator: CGFloat = 0
    private var magnifyMonitor: Any?
    private var scrollMonitor: Any?
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

    /// The windows in the scan being applied (see tabTakingOver).
    private var scannedIDs = Set<CGWindowID>()

    /// The tab `w` takes over from. macOS shows each tab as a window of its own, at the tab
    /// group's frame, and only the front tab's is on screen: so a window that appears exactly where
    /// a window of the same app has just gone is that app's next tab, not a new window.
    /// `real`: the new window's frame on screen.
    private func tabTakingOver(from w: ManagedWindow, at real: CGRect) -> (id: CGWindowID, canvasFrame: CGRect, originalFrame: CGRect,
                                                                         preferredSize: CGSize, home: CGPoint?, lastPlaced: CGPoint?, parked: Bool)? {
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) <= 2 && abs(a.y - b.y) <= 2 }
        func sameSize(_ s: CGSize) -> Bool { abs(s.width - real.width) <= 2 && abs(s.height - real.height) <= 2 }
        // Where the other tab was: on screen at its canvas spot, or parked (with the group).
        func wasHere(canvas: CGRect, placed: CGPoint?, parked: Bool) -> Bool {
            guard sameSize(canvas.size) else { return false }
            if parked { return inParkingCorner(real.origin) }
            return near(canvas.origin, w.canvasFrame.origin) || placed.map { near($0, real.origin) } == true
        }
        if let tab = windows.first(where: { $0.pid == w.pid && $0.id != w.id && !scannedIDs.contains($0.id)
                                            && wasHere(canvas: $0.canvasFrame, placed: $0.lastPlaced, parked: $0.parked) }) {
            return (tab.id, tab.canvasFrame, tab.originalFrame, tab.preferredSize, tab.home, tab.lastPlaced, tab.parked)
        }
        // Gone a moment before (the scan that saw it go came first).
        if let (id, tab) = recentlyRemoved.first(where: { $0.key != w.id && $0.value.pid == w.pid
                                                            && Date().timeIntervalSince($0.value.at) < 2
                                                            && wasHere(canvas: $0.value.canvasFrame, placed: nil, parked: $0.value.parked) }) {
            return (id, tab.canvasFrame, tab.originalFrame, tab.preferredSize, tab.home, nil, tab.parked)
        }
        return nil
    }

    /// Everything Expanse knew about a window that went out of view (app hidden, minimised, on
    /// another Space) or closed, so it comes back exactly as it was and is still restored on quit.
    private struct Departed {
        let pid: pid_t
        let bundleID: String
        let appName: String
        let title: String
        let canvasFrame: CGRect
        let originalFrame: CGRect
        let preferredSize: CGSize
        let home: CGPoint?
        let parked: Bool
        let at: Date
        /// Closed, not just out of view (see closedWindows): its spot is kept for its app opening
        /// again (appQuit), but a window that turns up with its ID is a new one (Finder reuses them).
        var closed = false
    }
    /// Windows the app has closed (Accessibility says their element is gone), not yet dropped by
    /// a scan: minimised or hidden windows are told apart from them this way.
    private var closedWindows = Set<CGWindowID>()
    /// The app whose window just closed, and when: macOS then gives focus to another of its
    /// windows, which isn't you picking that one (see focusSettled).
    private var lastClose: (pid: pid_t, at: CFTimeInterval)?
    /// When an app was last unhidden (by pid), and a window last brought back from the Dock (by
    /// ID): its windows coming back then are ones you asked for (see arrive).
    private var shownAgainAt: [pid_t: CFTimeInterval] = [:]
    private var restoredAt: [CGWindowID: CFTimeInterval] = [:]
    private var wallpaperTimer: Timer?
    private var lastWallpaperRefresh: CFTimeInterval = 0

    private struct CameraAnimation {
        var from: Camera
        var to: Camera
        var start: CFTimeInterval
        var duration: CFTimeInterval
        var completion: (() -> Void)?
        /// Zooming back in to the real windows, which take over where it ends (see exit).
        var handsBack = false
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
        let corner = parkingCorner
        return p.x >= corner.x && p.y >= corner.y
    }

    /// Top-left of the parking corner. macOS nudges a parked window back until a strip of it is
    /// inside the usable screen area (30-50pt up), and a Dock that's always shown shrinks that
    /// area: so the corner is measured from the usable area's edges, not the screen's.
    private var parkingCorner: CGPoint {
        let f = screen.frame, usable = screen.visibleFrame
        let right = screenRectCG.maxX - max(0, f.maxX - usable.maxX)
        let bottom = screenRectCG.maxY - max(0, usable.minY - f.minY)
        return CGPoint(x: right - 40, y: bottom - 80)
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
    /// The screen changed size since the layout was last fitted to it (see restoreSizesAndPlace).
    private var screenResized = false
    private weak var centreAfterResize: ManagedWindow?

    /// The window you're in: the front app's focused window or, failing that (at the lock screen,
    /// say), the front-most one on screen.
    private func currentWindow() -> ManagedWindow? {
        if let app = NSWorkspace.shared.frontmostApplication, let w = focusedWindow(of: app.processIdentifier) { return w }
        return windows.last { !$0.parked }
    }
    /// True while displays are changing: macOS shoves windows around and we must not
    /// mistake that for the user moving them.
    private var suspendTracking = false
    /// At the lock screen: tracking stays suspended until you're back (see start).
    private var screenLocked = false
    private var relayoutWork: [DispatchWorkItem] = []
    /// After a display change macOS keeps moving windows for a while (it restores each window's
    /// remembered spot for that display). Until then, moves are reverted instead of adopted.
    private var settleUntil = Date.distantPast
    private var reassertWork: DispatchWorkItem?
    private var focusSettleWork: DispatchWorkItem?
    private var lastHiddenHint: CGWindowID?
    static let settleDuration: TimeInterval = 20
    /// The gap kept around a window that would otherwise fill the screen. Every fit uses the same one,
    /// or a window fitted after a display change would shrink (and shift) the first time you focus it.
    static let screenMargin: CGFloat = 16

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
        // The window you're in, before macOS shuffles windows (or the lock screen hides it): it
        // goes in the middle once the layout fits the new screen (see restoreSizesAndPlace).
        if centreAfterResize == nil { centreAfterResize = currentWindow() }
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
            screenResized = true
        }
        lastViewportSize = newSize
        updateOverlayFrame()
        if final { refreshWallpaper() }
        // Whatever macOS did to the real windows, re-place all of them.
        windows.forEach { $0.lastPlaced = nil }
        if !isActive {
            if final { restoreSizesAndPlace() } else { commitInBackground() }
        } else if final {
            // Zoomed out, the layout still fits the new screen (the real windows follow on the way
            // out), but there's no window to centre.
            fitLayoutToScreen(tidy: false, rederiving: [])
            screenResized = false
            centreAfterResize = nil
        }
        view.render()
        if final {
            settleUntil = Date().addingTimeInterval(Self.settleDuration)
            let end = DispatchWorkItem { [weak self] in
                guard let self, Date() >= self.settleUntil, !self.screenLocked else { return }
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
        overlay.level = canvasLevel
        overlay.orderFrontRegardless()
        // Same as Tidy Up: sizes back to what you chose (capped at this screen), overlaps pushed
        // apart, clusters pulled back to the standard gap.
        fitLayoutToScreen(tidy: false, rederiving: [])
        // The screen changed size: the window you were in goes in the middle. Fitting moves windows
        // (the layout tightens on a smaller screen), so the old middle can be somewhere else now.
        if screenResized, let w = centreAfterResize ?? currentWindow(), windows.contains(where: { $0 === w }) {
            camera = focusCamera(for: w)
            viewPlaced = false
            logger.info("display change: centred on \(w.appName, privacy: .public)[\(w.id)]")
        }
        screenResized = false
        centreAfterResize = nil
        view.render()
        // Like a glide's last step: input waits while the real windows move in the background.
        gliding = true
        beginHandBack()
        commitAsync { [weak self] _ in
            self?.stopStreamsOnScreen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard let self else { return }
                    self.handingBackTo = nil
                    self.overlay.level = OverlayWindow.backdropLevel
                    self.isActive = false
                    self.gliding = false
                    self.view.render()
                    self.updateStreamingSoon()
                }
            }
        }
    }

    /// commit(), with the Accessibility calls off the main thread (see commitAsync): with dozens
    /// of windows, a display change would otherwise freeze Expanse for seconds.
    private func commitInBackground() {
        commitAsync { [weak self] _ in
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
        // Streams and pictures held back while replayd wasn't answering (see WindowCapture.overdue).
        WindowCapture.askAgain = { [weak self] in
            self?.updateStreamingSoon()
            self?.pumpSnapshotsSoon()
        }
        lastViewportSize = viewSize
        // macOS can shuffle windows while the Mac sits at the lock screen or its displays sleep
        // (once it pulled every parked window onto a smaller screen, all at one spot, and that
        // was followed as if you'd moved them): none of it is you, so nothing is followed until
        // you're back, then everything goes back where it was.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.screenLocked = true
            guard !self.isPaused else { return }
            logger.info("locked: window moves not followed until unlocked")
            self.displaysWillChange()
        }
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.screenLocked = false
            guard !self.isPaused else { return }
            logger.info("unlocked: re-placing windows")
            self.displaysWillChange()
            self.scheduleRelayout()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            logger.info("displays asleep: window moves not followed until they wake")
            self.displaysWillChange()
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            logger.info("displays awake: re-placing windows")
            self.scheduleRelayout()
        }
        registerDisplayCallback()
        sync()
        // New, closed, minimised and restored windows trigger a scan straight away (every app is
        // watched; see observeApp and handleAXEvent), and so do apps launching, hiding and
        // unhiding. A scan costs ScreenCaptureKit tens of milliseconds of LaunchServices lookups,
        // so the regular one is only a safety net.
        syncTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.sync() }
        // A dialog can open (or close) any time the canvas is up; nothing tells Expanse.
        dialogTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.keepDialogsVisible() }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for (i, app) in apps.enumerated() {
            // A few at a time: each asks the app to register, and a busy app takes a while.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.05) { [weak self] in
                self?.observeApp(app.processIdentifier)
            }
        }
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if name == NSWorkspace.didUnhideApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.shownAgainAt[app.processIdentifier] = CACurrentMediaTime()
                }
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
            self?.handleDesktopGesture(event)
        }
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleDesktopGesture(event)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            // A pid can be reused by a later app; don't hand it this app's observer.
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.observers[app.processIdentifier] = nil
                self?.focusedWindowByApp[app.processIdentifier] = nil
                if self?.isPaused == false { self?.appQuit(app) }
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
            self?.refreshSpaces()
            self?.fullScreenChanging()
            self?.canvasFollowsSpace()
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
    /// The window Expanse last focused, when, and whether that was already putting it back.
    private var lastFocusRequest: (id: CGWindowID, pid: pid_t, at: CFTimeInterval, reasserted: Bool)?

    /// Whether you clicked or typed since `time` (CACurrentMediaTime).
    private func inputSince(_ time: CFTimeInterval) -> Bool {
        let elapsed = CACurrentMediaTime() - time
        return [.leftMouseDown, .rightMouseDown, .keyDown].contains { type in
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type) < elapsed
        }
    }

    private func focusSettled(on id: CGWindowID) {
        guard !isActive, !isPaused, !suspendTracking, animation == nil,
              let w = windows.first(where: { $0.id == id }) else { return }
        // Moments after Expanse focused a window, focus moved to another of the same app's, and
        // not by you: arriving on a Space (from a full-screen app's, say), macOS activates the app
        // in front there, and the app puts its previous window back in focus. That's not a choice
        // to follow; the window you picked gets focus back (once, so an app that insists wins).
        if let request = lastFocusRequest, !request.reasserted, request.pid == w.pid, request.id != id,
           CACurrentMediaTime() - request.at < 1, !inputSince(request.at),
           let picked = windows.first(where: { $0.id == request.id }) {
            logger.info("\(w.appName, privacy: .public)[\(id)] took focus just after [\(request.id)] was picked; giving it back")
            focusWindow(picked, reasserting: true)
            return
        }
        let r = camera.toView(w.canvasFrame)
        let fullyVisible = !w.parked && CGRect(origin: .zero, size: viewSize).insetBy(dx: -1, dy: -1).contains(r)
        guard !fullyVisible else { return }
        if let close = lastClose, close.pid == w.pid, CACurrentMediaTime() - close.at < 1.5, !inputSince(close.at) {
            // You closed a window, and macOS gave focus to another of the app's, wherever that is.
            // The view stays where you were; going to it looked like a window reopening.
            logger.info("\(w.appName, privacy: .public)[\(w.id)] got focus after a window of its app closed; the view stays")
            return
        }
        if viewPlaced, !w.parked {
            // Partly on screen, in a view you put there: it's the one you clicked, not one to go to.
            logger.info("view placed by you: \(w.appName, privacy: .public)[\(w.id)] focused where it is")
            return
        }
        if autoCentre {
            let real = w.ax.flatMap(AX.position).map { NSStringFromPoint($0) } ?? "?"
            logger.info("focus-settled glide to \(w.appName, privacy: .public)[\(w.id)]: \(w.parked ? "parked" : "on screen at \(NSStringFromRect(r))", privacy: .public) in \(NSStringFromSize(self.viewSize), privacy: .public), real window at \(real, privacy: .public)")
            glide(to: w)
        } else if w.parked, lastHiddenHint != w.id {
            // Off means off: macOS often focuses a hidden window by itself (after a close or
            // minimize), so never move the canvas; just say where the window went.
            lastHiddenHint = w.id
            Toast.show("\(w.appName) is off-screen · ⌥` to find it")
        }
    }

    /// ⌃⌥C: the window you're in, to the middle of the screen, with the same glide as a hop.
    /// Zoomed out, back to 100% on the window you were last in.
    func centreCurrentWindow() {
        guard !isPaused, let w = currentWindow() else { return }
        logger.info("centre \(w.appName, privacy: .public)[\(w.id)]")
        focus(w)
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
        viewPlaced = false
        focusQuery += 1   // a focus answer still on its way is out of date now
        let t0 = CACurrentMediaTime()
        if !gliding {
            guard !isActive, animation == nil else { return }
            isActive = true
            gliding = true
            view.render()
            // Cover the screen first, so resizing (which may briefly move the window) isn't seen.
            overlay.level = canvasLevel
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
        beginHandBack()
        commitAsync { moves in
            guard generation == self.glideGeneration else { return }
            logger.info("glide timing: prep \(Int(prep * 1000))ms, \(self.lastAnimationStats, privacy: .public), commit \(Int((CACurrentMediaTime() - c0) * 1000))ms")
            self.focus(self.glideTarget, after: moves) {
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
    /// `applied`, if given, runs on the main thread once the app has taken focus.
    private func focusWindow(_ w: ManagedWindow, reasserting: Bool = false, applied: (() -> Void)? = nil) {
        lastFocusRequest = (w.id, w.pid, CACurrentMediaTime(), reasserting)
        activationRequest = (w.pid, CACurrentMediaTime())
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == w.pid { activationRequest = nil }
        // The app has to answer each of these; a busy one takes 30ms+, so they go on the
        // Accessibility queue (after any moves still running there), not the main thread.
        let ax = w.ax, pid = w.pid
        focusedWindowByApp[pid] = w.id
        axQueue.async {
            AX.focus(ax, pid: pid)
            if let applied { DispatchQueue.main.async(execute: applied) }
        }
        raiseSystemPrompts()
    }

    /// Runs `handBack` (dropping the overlay behind the real windows) once the window server shows
    /// `moves` done, focusing `w` has been applied and the streams of windows on screen have
    /// stopped, plus a frame to draw them. Otherwise, other windows visibly blink on top: switching
    /// apps can bring the new app's windows forward after the overlay drops, windows not yet moved
    /// show the old layout, and streamed ones show macOS's capture badge. Never later than a
    /// quarter of a second, so a slow app can't hold things up.
    private func focus(_ w: ManagedWindow?, after moves: [Move], thenHandBack handBack: @escaping () -> Void) {
        let asked = CACurrentMediaTime()
        let since = { Int((CACurrentMediaTime() - asked) * 1000) }
        var done = false, focused: Int? = w == nil ? 0 : nil, landed: Int?, stopped: Int?
        let area = handingBackTo
        let once = {
            guard !done else { return }
            done = true
            // (Unless a newer hop has started handing back meanwhile.)
            if self.handingBackTo == area { self.handingBackTo = nil }
            let waited = since()
            if waited > 60 {
                logger.info("hand-back waited \(waited)ms: \(w?.appName ?? "-", privacy: .public) \(focused.map { "focused after \($0)ms" } ?? "not focused yet", privacy: .public), windows \(landed.map { "landed after \($0)ms" } ?? "still moving", privacy: .public), streams \(stopped.map { "stopped after \($0)ms" } ?? "still stopping", privacy: .public)")
            }
            handBack()
        }
        let ready = {
            if focused != nil, landed != nil, stopped != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: once) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: once)
        whenOnScreen(moves, until: asked + 0.25) {
            landed = since()
            ready()
        }
        stopStreamsOnScreen {
            stopped = since()
            ready()
        }
        if let w {
            focusWindow(w) {
                focused = since()
                ready()
            }
        }
    }

    /// Calls `done` once the window server shows every window in `moves` where it was put (or
    /// at `deadline`). An app answers the Accessibility move as soon as it has taken it, but a busy
    /// one (Chromium apps especially) hands it to the window server a frame or more later.
    private func whenOnScreen(_ moves: [Move], until deadline: CFTimeInterval, done: @escaping () -> Void) {
        let start = CACurrentMediaTime()
        var pending = moves
        func check() {
            pending = notOnScreenYet(pending)
            if !pending.isEmpty, CACurrentMediaTime() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.008, execute: check)
                return
            }
            let waited = Int((CACurrentMediaTime() - start) * 1000)
            if waited > 0 {
                let apps = Set((pending.isEmpty ? moves : pending).map(\.window.appName)).sorted().joined(separator: ", ")
                logger.info("\(pending.isEmpty ? "windows landed" : "gave up on windows landing", privacy: .public) after \(waited)ms (\(apps, privacy: .public))")
            }
            done()
        }
        check()
    }

    /// The moves in `moves` the window server doesn't show yet. A closed window counts as done.
    private func notOnScreenYet(_ moves: [Move]) -> [Move] {
        guard !moves.isEmpty else { return [] }
        var ids = moves.map { UnsafeRawPointer(bitPattern: UInt($0.window.id)) }
        guard let array = CFArrayCreate(nil, &ids, ids.count, nil),
              let info = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] else { return [] }
        var at: [CGWindowID: CGPoint] = [:]
        for entry in info {
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Double],
                  let x = bounds["X"], let y = bounds["Y"] else { continue }
            at[id] = CGPoint(x: x, y: y)
        }
        return moves.filter { move in
            guard let p = at[move.window.id] else { return false }
            if let to = move.to { return p.distance(to: to) > 2 }
            return !inParkingCorner(p)
        }
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
            if notification == kAXUIElementDestroyedNotification as String, let id, let w = windows.first(where: { $0.id == id }) {
                closedWindows.insert(id)
                lastClose = (w.pid, CACurrentMediaTime())
            }
            if notification == kAXWindowDeminiaturizedNotification as String, let id {
                restoredAt[id] = CACurrentMediaTime()
            }
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

    /// Windows that moved while a full-screen window came or went. You didn't move them (the
    /// canvas's windows aren't even on screen then): macOS or their app did. Chromium browsers fit
    /// their other windows onto the screen when one goes full screen, for instance. So they're
    /// put back where the canvas has them, rather than followed, as soon as the moves stop: while
    /// the full-screen window is still up, out of sight, so they're in place when you come back.
    private var movedAroundFullScreen: Set<CGWindowID> = []
    /// A full-screen window has just come or gone (or the Space changed): until then, see above.
    private var fullScreenSettleUntil: CFTimeInterval = 0
    private var putBackWork: DispatchWorkItem?
    /// Windows gone full screen. One coming back is what you're looking at (macOS shows it and
    /// gives it the keyboard), wherever the view has got to meanwhile, so the view goes to it.
    private var wentFullScreen: Set<CGWindowID> = []

    private func backFromFullScreen(_ w: ManagedWindow) {
        logger.info("\(w.appName, privacy: .public)[\(w.id)] back from full screen")
        fullScreenChanging()
        // Once macOS has finished bringing it back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak w] in
            guard let self, let w, self.windows.contains(where: { $0 === w }) else { return }
            self.glideWhenIdle(to: w)
        }
    }

    private func fullScreenChanging() {
        fullScreenSettleUntil = CACurrentMediaTime() + 1.5
        if !movedAroundFullScreen.isEmpty { putBackAfterFullScreenSoon() }
    }

    /// Whether `w` moving now, not by you, is down to a full-screen window coming or going (see
    /// movedAroundFullScreen). If so it's noted, to be put back.
    private func movedByFullScreen(_ w: ManagedWindow, inFullScreenSpace: Bool) -> Bool {
        // A display change moves every window (and the Space with it): that's its own business.
        guard !suspendTracking else { return false }
        guard inFullScreenSpace || CACurrentMediaTime() < fullScreenSettleUntil else { return false }
        if movedAroundFullScreen.insert(w.id).inserted {
            logger.info("\(w.appName, privacy: .public)[\(w.id)] moved as a full-screen window came or went; putting it back")
        }
        putBackAfterFullScreenSoon()
        return true
    }

    private func putBackAfterFullScreenSoon() {
        putBackWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.putBackWork = nil
            guard !self.isPaused else { return }
            let ids = self.movedAroundFullScreen
            self.movedAroundFullScreen = []
            let moved = self.windows.filter { ids.contains($0.id) }
            guard !moved.isEmpty else { return }
            logger.info("putting back \(moved.count) windows moved as a full-screen window came or went")
            for w in moved {
                w.lastPlaced = nil
                // Apps fitting windows onto the screen can shrink them too.
                if let ax = w.ax, let size = AX.size(ax),
                   abs(size.width - w.canvasFrame.width) > 1 || abs(size.height - w.canvasFrame.height) > 1 {
                    _ = self.resizeReal(w, ax, to: w.canvasFrame.size)
                }
            }
            // Zoomed out (or mid-glide), the next commit puts them back.
            if !self.isActive, !self.gliding { self.commitInBackground() }
        }
        putBackWork = work
        // Half a second after the last such move: an app moves its windows in a burst.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// A real window moved or resized. In live mode, a move we didn't make means the user
    /// dragged it: the canvas follows.
    /// `userDragging`: the mouse button was down when the change was reported.
    private func realWindowChanged(_ w: ManagedWindow, _ element: AXUIElement, userDragging: Bool) {
        guard !isPaused else { return }
        let size = AX.size(element)
        let position = AX.position(element)
        if !userDragging {
            // Going full screen: it has a Space of its own now and keeps its spot on the canvas,
            // and for a moment other windows may move too (see movedAroundFullScreen).
            if AX.isFullScreen(element) || size == screenSize {
                wentFullScreen.insert(w.id)
                fullScreenChanging()
                return
            }
            if !isActive, wentFullScreen.remove(w.id) != nil {
                backFromFullScreen(w)
                return
            }
            // (Not where Expanse just put it: that's its own move, putting it back included.)
            let ours = w.lastPlaced.flatMap { last in position.map { last.distance(to: $0) < 2 } } ?? false
            if !ours, movedByFullScreen(w, inFullScreenSpace: Spaces.inFullScreenSpace) { return }
        }
        let selfResized = !userDragging && resizedItself(w, to: size)
        if let size {
            // Dragging an edge, or a resize right after you clicked or pressed a key in the window's
            // app (macOS's Fill from the green button or the Window menu, its keyboard shortcuts, an
            // app's zoom button), that Expanse didn't cause: the size you chose.
            let now = CACurrentMediaTime()
            let yours = userDragging || (inputSince(now - 1.5) && now - w.lastSizedAt > 2
                                         && NSWorkspace.shared.frontmostApplication?.processIdentifier == w.pid)
            adoptSize(w, size, fromUser: yours)
        }
        let pos = isActive ? nil : position
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
            } else if selfResized {
                w.lastPlaced = nil
                if !gliding { commitInBackground() }
            } else if !userDragging, cameBack(w, to: pos) {
                if !gliding { commitInBackground() }
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

    /// A VM or remote-screen window (see ManagedWindow.sizesItself) whose app just changed its
    /// size, as when the guest's resolution changes: its app moves it too (keeping it centred),
    /// which isn't you moving it. True while a move should be put back rather than followed, so
    /// it keeps its spot, growing or shrinking from its top-left like any other window.
    private func resizedItself(_ w: ManagedWindow, to size: CGSize?) -> Bool {
        guard w.sizesItself, NSEvent.pressedMouseButtons & 1 == 0 else { return false }
        let now = CACurrentMediaTime()
        if let size, abs(size.width - w.canvasFrame.width) > 1 || abs(size.height - w.canvasFrame.height) > 1 {
            if now - w.resizedItselfAt > 2 {
                logger.info("\(w.appName, privacy: .public)[\(w.id)] resized itself \(NSStringFromSize(w.canvasFrame.size), privacy: .public) -> \(NSStringFromSize(size), privacy: .public); keeping its spot")
            }
            w.resizedItselfAt = now
        }
        return now - w.resizedItselfAt < 2
    }

    /// The real window moved seconds after Expanse moved it, and not by you: back to where
    /// Expanse had it before (an app too busy to answer in time, like Finder opening ten windows,
    /// can carry out an old move after a newer one), or, for a window that's just opened, to
    /// where its app wanted it (apps often position a new window a moment late, after Expanse put
    /// it in free space). Neither is followed; the caller puts it back. Only once in a while per
    /// window, so an app that insists on its own spot gets its way rather than a tug of war.
    /// Returns true if the caller should put it back.
    private func cameBack(_ w: ManagedWindow, to p: CGPoint) -> Bool {
        let now = CACurrentMediaTime()
        let toBefore = w.placedBefore.map { $0.distance(to: p) < 2 } ?? false
        guard toBefore || now - w.addedAt < 5, now - w.lastPlacedAt < 10, now - w.cameBackAt > 10 else { return false }
        logger.info("\(w.appName, privacy: .public)[\(w.id)] moved to \(NSStringFromPoint(p), privacy: .public) by its app right after being placed; putting it back")
        w.cameBackAt = now
        // Where it really is, so the next commit moves it.
        w.lastPlaced = p
        w.parked = false
        return true
    }

    /// A window scan shortly. Asking again while one is due doesn't push it back, so a stream of
    /// events (a burst of new windows) is scanned as it happens, not only once it stops.
    private func syncSoon() {
        guard syncSoonWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.syncSoonWork = nil
            self?.sync()
        }
        syncSoonWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: Persistence

    /// While no window is shrunk for a smaller screen, the canvas layout is the home layout.
    /// Not while the screen is changing: coming back to the big screen, macOS gives windows
    /// their big sizes back before Expanse has put them back where they were, and the
    /// tightened layout would become home.
    private func homeFromCanvas() {
        if !isDerived, !suspendTracking { windows.forEach { $0.home = $0.canvasFrame.origin } }
    }

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// A window gone from screen, as a saved layout keeps it.
    private func savedEntry(_ id: CGWindowID, _ gone: Departed) -> SavedLayout.Window {
        SavedLayout.Window(bundleID: gone.bundleID, appName: gone.appName, title: LayoutStore.titleKey(gone.title),
                           x: Double(gone.canvasFrame.minX), y: Double(gone.canvasFrame.minY),
                           w: Double(gone.canvasFrame.width), h: Double(gone.canvasFrame.height),
                           hx: Double((gone.home ?? gone.canvasFrame.origin).x),
                           hy: Double((gone.home ?? gone.canvasFrame.origin).y),
                           pw: Double(gone.preferredSize.width), ph: Double(gone.preferredSize.height),
                           ox: Double(gone.originalFrame.minX), oy: Double(gone.originalFrame.minY),
                           ow: Double(gone.originalFrame.width), oh: Double(gone.originalFrame.height),
                           id: id, pid: gone.pid)
    }

    /// An app quit. Its windows come back with new IDs when it opens again, so their spots go
    /// where a saved layout's do: the app's next windows take them, matched by title as at
    /// launch (see add), instead of opening wherever there's room.
    private func appQuit(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        for w in windows where w.pid == pid { remove(w) }
        let gone = recentlyRemoved.filter { $0.value.pid == pid }.sorted { $0.value.at > $1.value.at }
        guard !gone.isEmpty else { return }
        for (id, _) in gone { recentlyRemoved.removeValue(forKey: id) }
        savedPool.insert(contentsOf: gone.map { savedEntry($0.key, $0.value) }, at: 0)
        logger.notice("\(app.localizedName ?? "?", privacy: .public) quit: keeping \(gone.count) window spots for when it opens again")
        scheduleSave()
    }

    /// `cleanExit` is true only when windows have just been put back in their original
    /// macOS layout (quit / pause). Otherwise the saved originals are what a crash recovery needs.
    func save(cleanExit: Bool = false) {
        // Before the first successful window scan (e.g. no Screen Recording yet) `windows` is
        // empty, and saving would wipe the layout and the crash-recovery originals.
        guard !isPaused, hasSynced else { return }
        homeFromCanvas()
        // Saved positions are canvas coordinates relative to a scale-1 camera.
        let center = camera.center(in: viewSize)
        // Windows out of view (app hidden, minimised, another Space) are saved too, newest
        // first, so a restart while they're away doesn't lose their spots. (Closed windows of
        // apps still running are among them; their spots go to the app's next window, as at launch.)
        let away = recentlyRemoved
            .filter { NSRunningApplication(processIdentifier: $0.value.pid) != nil }
            .sorted { $0.value.at > $1.value.at }
            .prefix(60)
            .map { savedEntry($0.key, $0.value) }
        let layout = SavedLayout(
            cameraX: Double(camera.origin.x), cameraY: Double(camera.origin.y),
            centerX: Double(center.x), centerY: Double(center.y),
            cleanExit: cleanExit,
            fittedWidth: fittedViewSize == .zero ? nil : Double(fittedViewSize.width),
            fittedHeight: fittedViewSize == .zero ? nil : Double(fittedViewSize.height),
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
            } + away + savedPool.prefix(60))   // windows not open right now keep their saved spots
        guard let data = try? JSONEncoder().encode(layout), data != lastSavedLayout else { return }
        lastSavedLayout = data
        LayoutStore.save(layout)
        if Date().timeIntervalSince(lastSnapshotAt) >= LayoutStore.snapshotSpacing { snapshot(layout) }
        lastLayout = layout
    }

    /// When the newest snapshot was taken (see LayoutStore.Snapshot).
    private var lastSnapshotAt = LayoutStore.snapshots().first?.date ?? .distantPast
    /// The layout as last saved, for a snapshot before restoring another.
    private var lastLayout: SavedLayout?

    private func snapshot(_ layout: SavedLayout) {
        LayoutStore.saveSnapshot(layout)
        lastSnapshotAt = Date()
    }

    /// Puts every window back where `layout` (a snapshot) had it, fitted to this screen (it may
    /// have been taken on another); windows it doesn't know stay where they are. The layout it
    /// replaces becomes a snapshot itself, so this can be undone. Shown zoomed out, like Tidy Up.
    func restoreLayout(_ layout: SavedLayout) {
        guard !isPaused else { return }
        guard !gliding else { whenIdle { [weak self] in self?.restoreLayout(layout) }; return }
        guard isActive else {
            enter(zoomOut: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.isActive == true { self?.restoreLayout(layout) }
            }
            return
        }
        save()
        if let lastLayout { snapshot(lastLayout) }
        var pool = layout.windows
        let open = Set(windows.map { LayoutStore.windowKey(pid: $0.pid, id: $0.id) })
        // Taken on this screen: every window where you saw it then. On another, from home spots,
        // fitted to this one.
        let sameScreen = layout.fittedWidth.map { CGFloat($0) } == viewSize.width
            && layout.fittedHeight.map { CGFloat($0) } == viewSize.height
        var restored = 0
        for w in windows {
            guard let e = LayoutStore.takeMatch(bundleID: w.bundleID, title: w.title, id: w.id, pid: w.pid,
                                                size: w.canvasFrame.size, open: open, from: &pool) else { continue }
            // Its home spot and chosen size; fitting (below) works out where it goes on this screen.
            w.home = CGPoint(x: e.hx ?? e.x, y: e.hy ?? e.y)
            w.canvasFrame.origin = sameScreen ? CGPoint(x: e.x, y: e.y) : w.home ?? w.canvasFrame.origin
            w.fitPush = .zero
            if let pw = e.pw ?? e.w, let ph = e.ph ?? e.h, pw > 0 { w.preferredSize = CGSize(width: pw, height: ph) }
            restored += 1
        }
        if sameScreen { fittedViewSize = viewSize }
        // The snapshot's home spots as they are: re-homing works them out from where windows
        // are now, which is what the restore is replacing.
        fitLayoutToScreen(tidy: false, rederiving: sameScreen ? [] : nil, rehoming: false)
        logger.info("restored a layout: \(restored) of \(self.windows.count) windows")
        view.render()
        animate(to: fitCamera())
        scheduleSave()
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

    /// At 100% the desktop shows through the backdrop and gets its events (see OverlayWindow), but
    /// scrolling or pinching on it still opens the canvas at 100%, as on the backdrop: the rest of
    /// the gesture then comes to the canvas, on top. Only where no window is under the pointer.
    private func handleDesktopGesture(_ event: NSEvent) {
        guard !isActive, !isPaused, !gliding else { return }
        // ⌥ + pinch zooms out from anywhere (see handleGlobalPinch).
        if event.type == .magnify, event.modifierFlags.contains(.option) { return }
        // The start of a gesture (a mouse wheel's ticks have no phases: each counts).
        guard event.phase == .began || event.phase == .mayBegin || (event.phase == [] && event.momentumPhase == []) else { return }
        // Where AppKit has it (bottom-left origin) to the window server's (top-left).
        let p = NSEvent.mouseLocation
        let point = CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - p.y)
        // Inside one of the canvas's windows: not the desktop (and no need to ask the window server).
        let vp = viewport
        if windows.contains(where: { !$0.parked && camera.toView($0.canvasFrame).offsetBy(dx: vp.minX, dy: vp.minY).contains(point) }) { return }
        // Any other window there (a dialog, the Dock, the menu bar, another app's panel)?
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let overWindow = info.contains { w in
            guard (w[kCGWindowLayer as String] as? Int ?? 0) >= 0, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0).contains(point)
        }
        guard !overWindow else { return }
        enter(zoomOut: false)
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
        guard !syncing else { syncAgain = true; return }
        guard CACurrentMediaTime() >= scanRetryAt else {
            // Backing off (see below): whoever's waiting gets what the last scan found.
            let completions = pendingSyncCompletions
            pendingSyncCompletions = []
            completions.forEach { $0() }
            return
        }
        // On a full-screen app's Space the canvas's windows aren't on screen, so a scan would be
        // thrown away (see below): skip ScreenCaptureKit and the window server altogether.
        if Spaces.inFullScreenSpace {
            refreshSpaces()
            let completions = pendingSyncCompletions
            pendingSyncCompletions = []
            completions.forEach { $0() }
            return
        }
        syncing = true
        syncAgain = false
        syncToken += 1
        let token = syncToken
        latestScan.withLock { $0 = token }
        let wait = Self.scanTimeout * pow(2, Double(min(unansweredScans, 5)))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.syncing, self.syncToken == token else { return }
            self.unansweredScans += 1
            // No pictures or new streams either until it answers (see WindowCapture.overdue).
            WindowCapture.replaydStuck = true
            logger.notice("window scan got no answer in \(Int(wait))s (macOS's capture service stuck or restarting?); the next waits \(Int(Self.scanTimeout * pow(2, Double(min(self.unansweredScans, 5)))))s")
            self.syncing = false
            self.syncSoon()
        }
        let input = scanInput()
        let s0 = CACurrentMediaTime()
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            // An answer to a scan given up on: a later one is in flight, or has been answered.
            guard let self, self.latestScan.withLock({ $0 }) == token else { return }
            let s1 = CACurrentMediaTime()
            // Full-screen windows have Spaces of their own and stay off the canvas. On a full-screen
            // app's Space, the canvas's windows aren't on screen at all: the scan can't say anything
            // about them, so it isn't applied (or they'd all be dropped, and the app's adopted).
            let inFullScreenSpace = Spaces.inFullScreenSpace
            let fullScreen = Spaces.fullScreenWindows()
            let found = (content?.windows ?? []).filter { !fullScreen.contains($0.windowID) }
            // Ask apps about their windows here, off the main thread: slow apps take 100ms+ to
            // answer, which would otherwise stall a glide or a key press.
            var ax = inFullScreenSpace ? AXSnapshot() : Self.axSnapshot(for: found, input: input)
            if input.live, !inFullScreenSpace { ax.order = Self.windowServerOrder() }
            let s2 = CACurrentMediaTime()
            DispatchQueue.main.async {
                // Given up on (see scanTimeout): the one after it counts.
                guard self.syncToken == token else { return }
                self.syncing = false
                if content != nil {
                    self.unansweredScans = 0
                    WindowCapture.replaydStuck = false
                }
                if !inFullScreenSpace { self.windowKinds = ax.kinds }
                // Asked for while this scan ran, so it may have missed what that was about.
                var again = self.syncAgain
                self.refreshSpaces()
                if content != nil, !self.isPaused, !inFullScreenSpace {
                    let s3 = CACurrentMediaTime()
                    // Windows moved (a glide, leaving the canvas) or the camera changed while the
                    // scan ran: its frames say where windows were, which would read as you moving
                    // them. Take only what's new from it and scan again.
                    let liveNow = !self.isActive && !self.suspendTracking
                    let stale = input.live != liveNow
                        || (liveNow && (input.moves != ManagedWindow.moves || input.camera != self.camera))
                    // Tracked windows this scan leaves out for being full screen (see wentFullScreen).
                    self.wentFullScreen.formUnion(fullScreen.filter { id in self.windows.contains { $0.id == id } })
                    self.apply(found, ax: ax, stale: stale)
                    // A window still opening (see axSnapshot) is looked at again shortly too.
                    again = again || stale || ax.pending
                    let ms = Int((CACurrentMediaTime() - s0) * 1000)
                    if ms > 120 {
                        logger.info("slow: window scan took \(ms)ms (ScreenCaptureKit \(Int((s1 - s0) * 1000))ms, \(ax.calls) Accessibility calls and window order \(Int((s2 - s1) * 1000))ms, main thread \(Int((CACurrentMediaTime() - s3) * 1000))ms)")
                    }
                } else if let error {
                    logger.error("SCShareableContent failed: \(error.localizedDescription, privacy: .public)")
                    // Refused (Screen Recording not allowed, or its approval waiting on you): asking
                    // again at once only asks again. Back off as for a scan with no answer, and
                    // capture nothing meanwhile.
                    self.scanRetryAt = CACurrentMediaTime() + Self.scanTimeout * pow(2, Double(min(self.unansweredScans, 5)))
                    self.unansweredScans += 1
                    WindowCapture.replaydStuck = true
                }
                if again { self.syncSoon() }
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
              let app = w.owningApplication, app.processID != getpid(), regular(app.processID),
              !Self.leftAlone.contains(app.bundleIdentifier)
        else { return false }
        return tracked || screenRectCG.intersects(w.frame)
    }

    /// Calls: a phone or FaceTime call's window stays where its app puts it, in front of you. It
    /// isn't part of your layout, and taking one on sent the view off to wherever there was room
    /// for it (and the app kept moving it back).
    private static let leftAlone: Set<String> = ["com.apple.mobilephone", "com.apple.FaceTime"]

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
        /// Still opening: the app doesn't list it yet, or it has no subrole yet. Asked again at
        /// every scan (and scans follow quickly) for a few seconds from `at`, when it was first seen.
        var pending = false
    }
    /// Window kinds don't change, so each window is asked once. "Not standard" is asked again
    /// after a while, in case it was wrong.
    private var windowKinds: [CGWindowID: WindowKind] = [:]

    private func scanInput() -> ScanInput {
        var input = ScanInput(kinds: windowKinds, live: !isActive && !suspendTracking,
                              corner: parkingCorner,
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
        /// Some window is still opening (see WindowKind.pending): scan again soon.
        var pending = false
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
            if let kind = kinds[id], !kind.standard, !kind.pending, now - kind.at < 10 {
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
                let subrole = kinds[id]?.standard == true ? kAXStandardWindowSubrole as String : AX.subrole(element)
                snapshot.calls += 1
                guard let subrole, subrole != kAXUnknownSubrole as String else { continue }
                found.insert(id)
                snapshot.known.insert(id)
                let standard = subrole == kAXStandardWindowSubrole as String
                kinds[id] = WindowKind(standard: standard, at: now)
                guard standard else { continue }
                snapshot.standard.insert(id)
                snapshot.elements[id] = element
                if let p = AX.position(element), let s = AX.size(element), s.width > 0, s.height > 0 {
                    snapshot.frames[id] = CGRect(origin: p, size: s)
                }
                snapshot.calls += 2
            }
            // Not one of the app's Accessibility windows, or no subrole: not managed for now. A
            // window that's just opening often looks like this for a moment (open ten at once and
            // most do), so it's asked about again at the next scan, for its first few seconds.
            for id in ids.subtracting(found) {
                // (Only a window seen for the first time starts out pending.)
                let firstSeen = kinds[id].map { $0.pending ? $0.at : -.infinity } ?? now
                let pending = now - firstSeen < 5
                kinds[id] = WindowKind(standard: false, at: pending ? firstSeen : now, pending: pending)
                snapshot.pending = snapshot.pending || pending
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
        let liveNow = !isActive && !suspendTracking
        let live = liveNow && !stale
        var seen = Set<CGWindowID>()
        var restored = Set<CGWindowID>()
        var replaceAny = false
        if firstSync, let saved {
            // Saved windows go back where you last saw them, moved only if this screen differs.
            if fittedViewSize == .zero, let w = saved.fittedWidth, let h = saved.fittedHeight {
                fittedViewSize = CGSize(width: w, height: h)
            }
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
        scannedIDs = Set(scWindows.map(\.windowID))
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
                let selfResized = live && resizedItself(w, to: f.size)
                w.scWindow = sc
                if let title = sc.title { w.title = title }
                if live && inParkingCorner(f.origin) {
                    w.parked = true
                    w.lastPlaced = f.origin
                } else if live {
                    if let last = w.lastPlaced {
                        if last.distance(to: f.origin) > 2, NSEvent.pressedMouseButtons & 1 == 0,
                           movedByFullScreen(w, inFullScreenSpace: false) {
                            // Put back later; its size isn't taken either.
                            continue
                        } else if last.distance(to: f.origin) > 2, selfResized {
                            w.lastPlaced = nil
                            replaceAny = true
                        } else if last.distance(to: f.origin) > 2, NSEvent.pressedMouseButtons & 1 == 0, cameBack(w, to: f.origin) {
                            replaceAny = true
                        } else if last.distance(to: f.origin) > 2 {
                            // Moved behind our back (by the user or the app): follow it.
                            logger.info("follow \(w.appName, privacy: .public)[\(w.id)] found at \(NSStringFromPoint(f.origin), privacy: .public) (last placed \(NSStringFromPoint(last), privacy: .public))")
                            w.parked = false
                            w.lastPlaced = nil
                            w.canvasFrame.origin = canvasPoint(forGlobal: f.origin)
                        }
                    } else {
                        let before = w.canvasFrame.origin
                        // Just back from full screen (or another window's), it's at the spot it
                        // had: wherever macOS set it down is put right, not followed.
                        if before.distance(to: canvasPoint(forGlobal: f.origin)) > 2, NSEvent.pressedMouseButtons & 1 == 0,
                           movedByFullScreen(w, inFullScreenSpace: false) {
                            continue
                        }
                        if selfResized {
                            // Its app recentred it as it resized itself: back to its spot.
                            replaceAny = true
                            if !stale { adoptSize(w, f.size) }
                            continue
                        }
                        w.canvasFrame.origin = canvasPoint(forGlobal: f.origin)
                        if before.distance(to: w.canvasFrame.origin) > 2 {
                            logger.info("follow \(w.appName, privacy: .public)[\(w.id)] found at \(NSStringFromPoint(f.origin), privacy: .public) (never placed)")
                        }
                    }
                }
                if !stale { adoptSize(w, f.size) }
            } else {
                // A new window is where its app put it, which nothing here has moved, so its frame
                // holds even in an out-of-date scan (opening windows in a burst makes most scans
                // out of date).
                if add(sc, live: liveNow, element: ax.elements[sc.windowID], frame: axFrames[sc.windowID]) { restored.insert(sc.windowID) }
            }
        }

        let scanned = Dictionary(scWindows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
        for w in windows where !seen.contains(w.id) {
            // Kept on disk (notice, not info), so a window that drops off the canvas can be
            // explained afterwards.
            let reason: String
            if let sc = scanned[w.id] {
                reason = isManageable(sc, tracked: true, regular: regular)
                    ? "Accessibility says it isn't a standard window"
                    : "layer \(sc.windowLayer), on screen \(sc.isOnScreen), \(Int(sc.frame.width))x\(Int(sc.frame.height))"
            } else {
                reason = "not in the window list"
            }
            logger.notice("dropped \(w.appName, privacy: .public)[\(w.id)]: \(reason, privacy: .public)\(stale ? " (out-of-date scan)" : "", privacy: .public)")
            remove(w)
        }

        // Windows put back where the saved layout had them (at launch, after the lock screen, an
        // app that had windows last time opening again) come with the sizes and spots of the
        // screen it was saved on, a laptop's say: fit the layout to this one before anything moves.
        // Only those: the windows already here stay where you see them.
        let restoredAny = !restored.isEmpty
        if restoredAny { fitLayoutToScreen(tidy: false, rederiving: firstSync ? [] : restored) }

        // Windows that opened since the last scan (see arrive), and any that came back from a
        // move (see cameBack), move together, off the main thread; and when several opened at
        // once, there's one glide, to the one in front.
        if arrivals.place || replaceAny || restoredAny && !firstSync { commitInBackground() }
        if let w = arrivals.glide.first(where: { focusedWindowByApp[$0.pid] == $0.id })
            ?? arrivals.glide.max(by: { $0.id < $1.id }) {
            glideWhenIdle(to: w)
        }
        arrivals = ([], false)

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
        // A closed window's ID turning up again is a new window (Finder reuses them), not that
        // one coming back to its spot.
        if recentlyRemoved[w.id]?.closed == true { recentlyRemoved.removeValue(forKey: w.id) }
        var returning = recentlyRemoved[w.id] != nil
        // Saved spots are for windows coming back: at launch, or its app's when that app has just
        // started (opening again after quitting). A window an app opens later is a new one: in a
        // spot of its own beside where you are, not one of the app's old windows' spots.
        let mayTakeSavedSpot = firstSync || (NSRunningApplication(processIdentifier: w.pid)?.launchDate
            .map { Date().timeIntervalSince($0) < 60 } ?? false)
        // An app that quit opening again: its window is back at its spot (see appQuit).
        var reopened = false
        if live, let tab = tabTakingOver(from: w, at: f) {
            // A new tab, or another tab brought to the front: it takes the group's spot (where
            // it already is), instead of being placed as a new window, which would move the group.
            recentlyRemoved.removeValue(forKey: w.id)
            w.canvasFrame = tab.canvasFrame
            w.originalFrame = tab.originalFrame
            w.preferredSize = tab.preferredSize
            w.home = tab.home
            w.lastPlaced = tab.lastPlaced
            w.parked = tab.parked
            returning = true
            logger.info("tab \(w.appName, privacy: .public)[\(w.id)] takes over from [\(tab.id)]")
        } else if let back = recentlyRemoved.removeValue(forKey: w.id) {
            // Came back (minimised, hidden, another Space, briefly missing during a display
            // change): same spot, same macOS original and chosen size.
            w.canvasFrame.origin = back.canvasFrame.origin
            w.originalFrame = back.originalFrame
            w.preferredSize = back.preferredSize
            w.home = back.home
        } else if mayTakeSavedSpot, let match = LayoutStore.takeMatch(bundleID: w.bundleID, title: w.title, id: w.id, pid: w.pid,
                                                                      size: f.size, open: openWindowKeys, from: &savedPool) {
            // A saved spot: at launch, or an app opened later that had windows last time.
            w.canvasFrame.origin = CGPoint(x: match.x, y: match.y)
            if let pw = match.pw, let ph = match.ph { w.preferredSize = CGSize(width: pw, height: ph) }
            if let hx = match.hx, let hy = match.hy { w.home = CGPoint(x: hx, y: hy) }
            if let sw = match.w, let sh = match.h, let ax = w.ax, !w.sizesItself,
               abs(sw - f.width) > 1 || abs(sh - f.height) > 1 {
                // Quitting put the macOS size back; restore the canvas size.
                let actual = resizeReal(w, ax, to: CGSize(width: sw, height: sh))
                w.canvasFrame.size = actual
                logger.info("restore size \(w.appName, privacy: .public)[\(w.id)] \(NSStringFromSize(f.size), privacy: .public) -> \(NSStringFromSize(actual), privacy: .public)")
            }
            if !firstSync { returning = true; reopened = true }
            if saved?.cleanExit != true, let ox = match.ox, let oy = match.oy, let ow = match.ow, let oh = match.oh {
                // Last run didn't put windows back; its record of the macOS layout is the real one.
                w.originalFrame = CGRect(x: ox, y: oy, width: ow, height: oh)
            }
            restored = true
        } else if !firstSync, mayTakeSavedSpot, let spot = LayoutStore.largerSpot(bundleID: w.bundleID, size: f.size, open: openWindowKeys, in: savedPool) {
            // An app opening again shows a small box first (an update or loading screen): it goes
            // in the middle of where the app's window was, which the window itself takes when it
            // comes, so the view doesn't go somewhere else in between.
            let x = spot.x + (spot.pw ?? spot.w ?? Double(f.width)) / 2 - Double(f.width) / 2
            let y = spot.y + (spot.ph ?? spot.h ?? Double(f.height)) / 2 - Double(f.height) / 2
            w.canvasFrame.origin = CGPoint(x: x.rounded(), y: y.rounded())
            returning = true
            reopened = true
            logger.info("\(w.appName, privacy: .public)[\(w.id)] is a small window of an app opening again: centred on its window's spot")
        } else if inParkingCorner(f.origin) {
            // In the parking corner with no record of where it belongs (a previous run that
            // didn't exit cleanly, or a lost record): bring it out where it can be seen.
            global = CGPoint(x: viewport.midX - f.width / 2, y: viewport.minY + 40)
            w.place(at: global)
            w.lastPlaced = nil
            w.canvasFrame.origin = canvasPoint(forGlobal: global)
        }

        // A window opened (or came back) while Expanse is running, not one found at launch. It
        // goes next to the window it came from: its app's front window in view, else the window
        // in front.
        let anchor = windows.last { !$0.parked && $0.pid == w.pid } ?? windows.last { !$0.parked }
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
            // Usually the window closed, which a scan confirms (it drops windows no longer in the
            // window list). But every stream stops when macOS restarts its capture service, with
            // all the windows still open: dropping them here dropped them all, silently.
            logger.notice("\(w.appName, privacy: .public)[\(w.id)]: its capture stopped; checking it's still open")
            self.syncSoon()
        }
        // Its first picture comes from a one-off snapshot (see pumpSnapshots), not a stream.
        pumpSnapshotsSoon()
        observe(w)
        logger.notice("tracking \(w.appName, privacy: .public) [\(w.id)] \(w.title, privacy: .private)")
        if arriving { arrive(w, anchor: anchor, live: live, returning: returning, reopened: reopened) }
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
        viewPlaced = false
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

    /// The canvas covers app windows and the Dock, but never another app's dialog (an alert, a
    /// password or permission prompt, a run-modal Save panel): those float above app windows, and
    /// covered by the canvas they'd wait unseen until you left it. With one on screen, the canvas
    /// goes just under it.
    private var canvasLevel: NSWindow.Level {
        guard let dialog = Self.lowestDialogLevel() else { return OverlayWindow.canvasLevel }
        return NSWindow.Level(rawValue: dialog - 1)
    }

    /// The lowest window level of another app's dialog on screen: a window above app windows and
    /// floating panels (modal-panel level and up) but under the canvas, other than the Dock's.
    static func lowestDialogLevel() -> Int? {
        let modal = Int(CGWindowLevelForKey(.modalPanelWindow)), canvas = OverlayWindow.canvasLevel.rawValue
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { w -> Int? in
            guard let layer = w[kCGWindowLayer as String] as? Int, layer >= modal, layer < canvas,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = w[kCGWindowBounds as String] as? [String: CGFloat],
                  bounds["Width"] ?? 0 >= 100, bounds["Height"] ?? 0 >= 50,
                  NSRunningApplication(processIdentifier: pid)?.bundleIdentifier != "com.apple.dock"
            else { return nil }
            return layer
        }.min()
    }

    /// While the canvas is up (zoomed out, or a glide), keep it under any dialog that opened.
    private func keepDialogsVisible() {
        guard overlay.level != OverlayWindow.backdropLevel else { return }
        let level = canvasLevel
        guard level != overlay.level else { return }
        logger.info("canvas level \(self.overlay.level.rawValue) -> \(level.rawValue)\(level == OverlayWindow.canvasLevel ? "" : " (under a dialog)", privacy: .public)")
        overlay.level = level
    }

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
    /// Windows closer than this to a neighbour count as one group (cluster). Tidy Up tidies each
    /// group where it is, and keeps groups at least this far apart.
    static let clusterReach: CGFloat = 240
    /// Edges closer than this to lining up get lined up by Tidy Up.
    static let alignReach: CGFloat = 60

    /// Fit the layout to this screen without rebuilding it:
    /// 1. every window takes the size you chose, capped at the screen (shrinks on a laptop,
    ///    grows back on a big display);
    /// 2. each group is tidied where it is: overlaps pushed apart, edges that nearly line up
    ///    lined up, gaps closed to the standard gap (see tidyUp).
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
        // Home spots are otherwise brought up to date when the layout is saved, which windows
        // you've only just moved may still be waiting for: Tidy would put them back.
        homeFromCanvas()
        fitLayoutToScreen(tidy: true)
        view.render()
        animate(to: fitCamera())
        scheduleSave()
    }

    /// True while the canvas is a tightened version of the home layout: some window is smaller
    /// than its chosen size because this screen is smaller.
    var isDerived: Bool {
        windows.contains { !$0.sizesItself && $0.preferredSize.width > 0 &&
            ($0.canvasFrame.width < $0.preferredSize.width - Self.appRounding
             || $0.canvasFrame.height < $0.preferredSize.height - Self.appRounding) }
    }

    /// How far short of the size asked for a window can end up because its app rounds sizes
    /// (Terminal to whole character cells, Chess to its board's proportions): that's still the
    /// chosen size, not one shrunk for a smaller screen. Shrinking to fit a screen takes far more.
    static let appRounding: CGFloat = 32

    /// You moved a window (dragging on the canvas or for real). On the big screen its new spot is
    /// its home spot, straight away: anything that fits the layout from home spots before the
    /// next save (Tidy Up, a window coming back) would otherwise put it back. On a smaller
    /// screen its home spot keeps the gaps it now has to its neighbours (see homeSpot), so the
    /// move survives going back to the big screen.
    func noteUserMove(_ w: ManagedWindow, from before: CGPoint) {
        // Where you put it is where it goes: no push left for the next fit to take back.
        w.fitPush = .zero
        guard isDerived else {
            if !suspendTracking { w.home = w.canvasFrame.origin }
            return
        }
        guard let i = windows.firstIndex(where: { $0 === w }) else { return }
        w.home = homeSpot(i, here: windows.map(fittedFrame))
    }

    /// Where the last fit had the window, before pushing it clear of overlaps, at the size that
    /// fit gave it: macOS squeezing windows during a display change doesn't count.
    private func fittedFrame(_ w: ManagedWindow) -> CGRect {
        CGRect(origin: CGPoint(x: w.canvasFrame.minX - w.fitPush.dx, y: w.canvasFrame.minY - w.fitPush.dy),
               size: fittedViewSize == .zero ? w.canvasFrame.size : fittedSize(w, for: fittedViewSize))
    }

    /// A home spot for window `i` that puts it back where it is here (`here`, see fittedFrame): it
    /// keeps what derive keeps (see anchor), measured here and applied to the anchor's home spot.
    /// The inverse of derive, for a window whose canvas spot came from this screen rather than
    /// from the home layout.
    private func homeSpot(_ i: Int, here: [CGRect]) -> CGPoint {
        let home = windows.indices.map { j in
            CGRect(origin: windows[j].home ?? here[j].origin, size: homeSize(windows[j]))
        }
        // Along x; for y the same, transposed. Of equally near windows (two stacked with their
        // right edges lined up here, say), the one that puts it furthest along: clear of all of
        // them at home, where they may differ in size.
        func along(_ here: [CGRect], _ home: [CGRect]) -> CGFloat {
            let r = here[i]
            let spots = Self.anchors(i, in: here).map { anchor -> CGFloat in
                switch anchor {
                case .gap(let j): return home[j].maxX + r.minX - here[j].maxX
                case .edge(let j): return home[j].minX + r.minX - here[j].minX
                }
            }
            return (spots.max() ?? r.minX).rounded()
        }
        return CGPoint(x: along(here, home), y: along(here.map(\.transposed), home.map(\.transposed)))
    }

    /// Windows whose home spot doesn't explain where they are: opened while the screen was smaller
    /// (no home spot yet), left where they were when a window beside them closed (the layout would
    /// close up around it), moved before home spots followed neighbours, or overlapping a window
    /// in the home layout that they're clear of here. A bigger screen would move them by the wrong
    /// amount, or leave them where they are while their neighbours grow over them. Each gets a home
    /// spot from its neighbours here instead (see homeSpot), so it moves along with them.
    private func rehomeStrays() {
        let here = windows.map(fittedFrame)
        let hereFlipped = here.map(\.transposed)
        let sizes = windows.map { fittedViewSize == .zero ? $0.canvasFrame.size : fittedSize($0, for: fittedViewSize) }
        var rehomed = Set<Int>()
        // A new home spot can change which windows another one is anchored to, so again until
        // nothing changes (a few rounds at most).
        for round in 0..<4 {
            let home = windows.indices.map { j in
                CGRect(origin: windows[j].home ?? here[j].origin, size: homeSize(windows[j]))
            }
            var strays = round == 0 ? Set(windows.indices.filter { windows[$0].home == nil }) : []
            for i in windows.indices {
                for j in windows.indices where j > i {
                    guard home[i].insetBy(dx: 0.5, dy: 0.5).intersects(home[j]),
                          !here[i].insetBy(dx: 0.5, dy: 0.5).intersects(here[j]) else { continue }
                    // The one below (or, side by side, on the right) is the one out of place.
                    let stacked = here[i].maxY <= here[j].minY + 0.5 || here[j].maxY <= here[i].minY + 0.5
                    let later = stacked ? (here[j].minY > here[i].minY ? j : i) : (here[j].minX > here[i].minX ? j : i)
                    strays.insert(later)
                }
            }
            let derived = Self.derive(home: home, sizes: sizes)
            let homeFlipped = home.map(\.transposed)
            for i in windows.indices where derived[i].distance(to: here[i].origin) >= 1
                || !Self.isNearest(Self.anchor(i, in: home), i, in: here)
                || !Self.isNearest(Self.anchor(i, in: homeFlipped), i, in: hereFlipped) {
                strays.insert(i)
            }
            // Left to right and top to bottom, so a stray next to another stray measures from its
            // new spot; twice, for one anchored to a stray further on.
            let order = strays.sorted { (here[$0].minX, here[$0].minY) < (here[$1].minX, here[$1].minY) }
            var changed = false
            for _ in 0..<2 {
                for i in order {
                    let spot = homeSpot(i, here: here)
                    if windows[i].home.map({ $0.distance(to: spot) >= 1 }) ?? true {
                        windows[i].home = spot
                        rehomed.insert(i)
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        guard !rehomed.isEmpty else { return }
        logger.info("re-homed \(rehomed.count) windows: \(rehomed.sorted().map { "\(self.windows[$0].appName)[\(self.windows[$0].id)]" }.joined(separator: ", "), privacy: .public)")
    }

    /// Fit the layout to this screen. Sizes: what you chose, capped at the screen. Positions: the
    /// home layout, tightened by however much windows shrank, so every gap (inside groups and
    /// between them) keeps its size; on the big screen that's the home layout exactly. With
    /// `tidy`, the home layout itself is tidied up first (see tidyUp).
    /// `rederiving`: the windows placed from their home spots; nil for all of them. The rest keep
    /// where you see them, moved only as far as the screen change since the last fit moves their
    /// spot in the derived layout. Re-deriving everything would also undo whatever the layout
    /// picked up since then (windows opening and closing change the derived layout), and every
    /// window would jump.
    /// `rehoming`: false when the home spots were just set (see restoreLayout), so rehomeStrays
    /// doesn't rework them.
    private func fitLayoutToScreen(tidy: Bool, rederiving: Set<CGWindowID>? = nil, rehoming: Bool = true) {
        if rehoming { rehomeStrays() }
        var home = windows.map { CGRect(origin: $0.home ?? $0.canvasFrame.origin, size: homeSize($0)) }
        if tidy {
            Self.tidyUp(&home)
            for (w, h) in zip(windows, home) { w.home = CGPoint(x: h.minX.rounded(), y: h.minY.rounded()) }
        }
        for w in windows {
            guard let ax = w.ax, !w.sizesItself else { continue }
            let chosen = w.preferredSize.width > 0 ? w.preferredSize : w.canvasFrame.size
            let target = Self.cap(chosen, to: viewSize)
            guard abs(target.width - w.canvasFrame.width) > 1 || abs(target.height - w.canvasFrame.height) > 1 else { continue }
            let actual = resizeReal(w, ax, to: target)
            logger.info("fit size \(w.appName, privacy: .public)[\(w.id)] \(NSStringFromSize(w.canvasFrame.size), privacy: .public) -> \(NSStringFromSize(actual), privacy: .public)")
            // Asked for the size you chose and the app came as close as it goes (Terminal rounds to
            // character cells, Preview has a minimum width): that's the chosen size from now on,
            // rather than asking again at every fit.
            if chosen.width <= viewSize.width, chosen.height <= viewSize.height,
               abs(actual.width - target.width) <= Self.appRounding, abs(actual.height - target.height) <= Self.appRounding {
                w.preferredSize = actual
            }
            w.canvasFrame.size = actual
            updateCapture(w)
        }

        // A little off its home size, when that fits the screen, is an app rounding, not a smaller
        // screen: counted as home, or the windows beyond it would creep every time the screen changes.
        let sizes = zip(windows, home).map { w, h in
            h.width <= viewSize.width && h.height <= viewSize.height
                && abs(w.canvasFrame.width - h.width) <= Self.appRounding && abs(w.canvasFrame.height - h.height) <= Self.appRounding
                ? h.size : w.canvasFrame.size
        }
        var origins = Self.derive(home: home, sizes: sizes)
        if let rederiving, !tidy, fittedViewSize != .zero {
            // Worked out from the screen sizes rather than measured, so a round trip between two
            // screens comes back exactly. Last fit's push apart is taken back first: on this
            // screen there may be no overlap to push.
            let before = Self.derive(home: home, sizes: windows.map { fittedSize($0, for: fittedViewSize) })
            let after = Self.derive(home: home, sizes: windows.map { fittedSize($0, for: viewSize) })
            for (i, w) in windows.enumerated() where !rederiving.contains(w.id) {
                origins[i] = CGPoint(x: w.canvasFrame.minX - w.fitPush.dx + after[i].x - before[i].x,
                                     y: w.canvasFrame.minY - w.fitPush.dy + after[i].y - before[i].y)
            }
        }
        var frames = zip(origins, windows).map { CGRect(origin: $0, size: $1.canvasFrame.size) }
        // Only overlaps this screen caused, pushed apart to the standard gap. Windows you have
        // overlapping in the home layout stay that way (pushing them apart would push everything
        // below and to the right too, and the move would stick when you're back on the big screen).
        Self.separate(&frames, gap: Self.gap, onlyOverlaps: true, keep: Self.overlappingPairs(home))
        for (i, w) in windows.enumerated() {
            w.fitPush = CGVector(dx: frames[i].minX - origins[i].x, dy: frames[i].minY - origins[i].y)
        }
        fittedViewSize = viewSize
        var moved = 0
        for (w, f) in zip(windows, frames) {
            let rounded = CGPoint(x: f.minX.rounded(), y: f.minY.rounded())
            if rounded.distance(to: w.canvasFrame.origin) >= 1 {
                moved += 1
                if tidy {
                    logger.info("tidy moved \(w.appName, privacy: .public)[\(w.id)] by \(Int(rounded.x - w.canvasFrame.minX)), \(Int(rounded.y - w.canvasFrame.minY))")
                }
            }
            w.canvasFrame.origin = rounded
        }
        logger.info("layout fitted: \(moved) of \(self.windows.count) windows moved, derived=\(self.isDerived)")
    }

    /// The screen size the layout was last fitted to (see fitLayoutToScreen).
    private var fittedViewSize: CGSize = .zero

    /// A window's size in the home layout: the size you chose, or for a VM window (which picks
    /// its own size, see ManagedWindow.sizesItself) the size it is.
    private func homeSize(_ w: ManagedWindow) -> CGSize {
        w.sizesItself || w.preferredSize.width <= 0 ? w.canvasFrame.size : w.preferredSize
    }

    /// The size fitting gives a window on a screen of `size`: the size you chose, capped at the screen.
    private func fittedSize(_ w: ManagedWindow, for size: CGSize) -> CGSize {
        guard !w.sizesItself else { return w.canvasFrame.size }
        return Self.cap(w.preferredSize.width > 0 ? w.preferredSize : w.canvasFrame.size, to: size)
    }

    /// A window of `chosen` size on a screen of `view`: as chosen where it fits; where it doesn't
    /// (a size from a bigger screen), the screen less a margin all round, so it doesn't touch the
    /// edges. A window you sized to fill the screen (macOS's Fill, say) keeps filling it.
    static func cap(_ chosen: CGSize, to view: CGSize) -> CGSize {
        let margin = screenMargin * 2
        return CGSize(width: chosen.width <= view.width ? chosen.width.rounded() : (view.width - margin).rounded(),
                      height: chosen.height <= view.height ? chosen.height.rounded() : (view.height - margin).rounded())
    }

    /// Positions for windows of `sizes` that keep the `home` layout where you see it: each window
    /// keeps its gap to its nearest window on the left or, nearer still, its left edge's offset
    /// from a window above or below it (a column stays lined up); the same for top edges. So
    /// shrinking windows pull the layout in, and a window keeps with its own group rather than
    /// the next group over. With home sizes this returns the home positions exactly. Callers push
    /// apart any overlap left.
    static func derive(home: [CGRect], sizes: [CGSize]) -> [CGPoint] {
        var x = home.map(\.minX), y = home.map(\.minY)
        for i in home.indices.sorted(by: { (home[$0].minX, home[$0].minY) < (home[$1].minX, home[$1].minY) }) {
            switch anchor(i, in: home) {
            case .gap(let j)?: x[i] = x[j] + sizes[j].width + home[i].minX - home[j].maxX
            case .edge(let j)?: x[i] = x[j] + home[i].minX - home[j].minX
            case nil: break
            }
        }
        let flipped = home.map(\.transposed)
        for i in home.indices.sorted(by: { (home[$0].minY, home[$0].minX) < (home[$1].minY, home[$1].minX) }) {
            switch anchor(i, in: flipped) {
            case .gap(let j)?: y[i] = y[j] + sizes[j].height + home[i].minY - home[j].maxY
            case .edge(let j)?: y[i] = y[j] + home[i].minY - home[j].minY
            case nil: break
            }
        }
        return zip(x, y).map { CGPoint(x: $0, y: $1) }
    }

    /// What a window's x keeps from one layout to the next: its gap to another window's right
    /// edge, or its left edge's offset from another window's.
    enum Anchor: Equatable { case gap(Int), edge(Int) }

    /// Window `i`'s anchor among `frames` (for y, pass the frames transposed): the nearest window
    /// on the left, rows that don't line up counting extra; or, when nearer, a window above or
    /// below, its left edge's offset counting extra (gaps win ties). Only windows before it in
    /// left-to-right order, which derive has placed already.
    static func anchor(_ i: Int, in frames: [CGRect]) -> Anchor? {
        anchors(i, in: frames).first
    }

    /// Every anchor as near as the nearest (see anchor), first one first.
    static func anchors(_ i: Int, in frames: [CGRect]) -> [Anchor] {
        let candidates = anchorCandidates(i, in: frames)
        guard let best = candidates.min(by: { ($0.cost, $0.edge ? 1 : 0) < ($1.cost, $1.edge ? 1 : 0) }) else { return [] }
        return candidates.filter { $0.edge == best.edge && $0.cost <= best.cost + 0.5 }.map(\.anchor)
    }

    /// Whether `anchor` is as near as window `i`'s nearest among `frames`, of either kind (none:
    /// whether it has none). Shrinking windows to the same width can put a window in a column
    /// exactly the standard gap from the window beside it: a tie the gap wins (see anchor), though
    /// the column still explains where it is.
    static func isNearest(_ anchor: Anchor?, _ i: Int, in frames: [CGRect]) -> Bool {
        let candidates = anchorCandidates(i, in: frames)
        guard let anchor, let best = candidates.map(\.cost).min() else { return anchor == nil && candidates.isEmpty }
        return candidates.contains { $0.anchor == anchor && $0.cost <= best + 0.5 }
    }

    /// Window `i`'s possible anchors among `frames`, each with how far it is (see anchor).
    private static func anchorCandidates(_ i: Int, in frames: [CGRect]) -> [(cost: CGFloat, edge: Bool, anchor: Anchor)] {
        func span(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> CGFloat {
            max(0, max(a0, b0) - min(a1, b1))   // distance between ranges; 0 when they overlap
        }
        let r = frames[i]
        var candidates: [(cost: CGFloat, edge: Bool, anchor: Anchor)] = []
        for (j, o) in frames.enumerated() where j != i {
            if o.maxX <= r.minX + 0.5 {
                candidates.append((r.minX - o.maxX + 2 * span(o.minY, o.maxY, r.minY, r.maxY), false, .gap(j)))
            } else if (o.minX, o.minY) < (r.minX, r.minY), span(o.minX, o.maxX, r.minX, r.maxX) == 0,
                      o.maxY <= r.minY + 0.5 || r.maxY <= o.minY + 0.5 {
                candidates.append((span(o.minY, o.maxY, r.minY, r.maxY) + 2 * abs(r.minX - o.minX), true, .edge(j)))
            }
        }
        return candidates
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

    /// Tidy Up, on the home layout. Each group of windows is tidied where it is: overlaps pushed
    /// apart, edges that nearly line up lined up, and gaps closed to the standard gap. A group
    /// only moves (as a whole) when another group has grown into its space.
    static func tidyUp(_ frames: inout [CGRect]) {
        let cluster = clusters(frames, reach: clusterReach)
        let groups = Dictionary(grouping: frames.indices, by: { cluster[$0] }).values.map { $0.sorted() }
        for g in groups {
            var f = g.map { frames[$0] }
            separate(&f, gap: gap)
            // Twice: closing a gap can undo a line-up, and lining up can open a gap.
            for _ in 0..<2 {
                gravity(&f, gap: gap)
                align(&f, reach: alignReach, gap: gap)
            }
            separate(&f, gap: gap)
            for (k, i) in g.enumerated() { frames[i] = f[k] }
        }
        separateGroups(&frames, groups: groups, reach: clusterReach)
    }

    private static func overlapY(_ a: CGRect, _ b: CGRect) -> Bool { min(a.maxY, b.maxY) - max(a.minY, b.minY) > 0 }
    private static func overlapX(_ a: CGRect, _ b: CGRect) -> Bool { min(a.maxX, b.maxX) - max(a.minX, b.minX) > 0 }

    /// Close gaps: each frame slides left (then up) until it sits `gap` from its nearest
    /// neighbour on that side. It only slides towards a neighbour it shares rows (or columns)
    /// with, so it never creates overlaps.
    static func gravity(_ frames: inout [CGRect], gap: CGFloat) {
        for _ in 0..<3 {
            for i in frames.indices.sorted(by: { frames[$0].minX < frames[$1].minX }) {
                let r = frames[i]
                let edges = frames.indices.filter {
                    $0 != i && frames[$0].maxX <= r.minX + 0.5 && overlapY(frames[$0], r)
                }.map { frames[$0].maxX }
                if let nearest = edges.max(), r.minX - nearest > gap { frames[i].origin.x = nearest + gap }
            }
            for i in frames.indices.sorted(by: { frames[$0].minY < frames[$1].minY }) {
                let r = frames[i]
                let edges = frames.indices.filter {
                    $0 != i && frames[$0].maxY <= r.minY + 0.5 && overlapX(frames[$0], r)
                }.map { frames[$0].maxY }
                if let nearest = edges.max(), r.minY - nearest > gap { frames[i].origin.y = nearest + gap }
            }
        }
    }

    /// Line up edges that nearly line up (within `reach`): a frame's top with its neighbour on the
    /// left, then its left edge with its neighbour above. Skipped where the move would bring it
    /// closer than `gap` to another frame (windows of different widths can't line up both sides).
    static func align(_ frames: inout [CGRect], reach: CGFloat, gap: CGFloat) {
        func clear(_ r: CGRect, except i: Int) -> Bool {
            !frames.indices.contains { $0 != i && frames[$0].insetBy(dx: -gap + 0.5, dy: -gap + 0.5).intersects(r) }
        }
        for i in frames.indices.sorted(by: { frames[$0].minX < frames[$1].minX }) {
            let r = frames[i]
            let beside = frames.indices.filter {
                $0 != i && frames[$0].maxX <= r.minX + 0.5 && overlapY(frames[$0], r) && abs(frames[$0].minY - r.minY) <= reach
            }
            guard let j = beside.max(by: { frames[$0].maxX < frames[$1].maxX }), frames[j].minY != r.minY else { continue }
            let lined = CGRect(origin: CGPoint(x: r.minX, y: frames[j].minY), size: r.size)
            if clear(lined, except: i) { frames[i] = lined }
        }
        for i in frames.indices.sorted(by: { frames[$0].minY < frames[$1].minY }) {
            let r = frames[i]
            let above = frames.indices.filter {
                $0 != i && frames[$0].maxY <= r.minY + 0.5 && overlapX(frames[$0], r) && abs(frames[$0].minX - r.minX) <= reach
            }
            guard let j = above.max(by: { frames[$0].maxY < frames[$1].maxY }), frames[j].minX != r.minX else { continue }
            let lined = CGRect(origin: CGPoint(x: frames[j].minX, y: r.minY), size: r.size)
            if clear(lined, except: i) { frames[i] = lined }
        }
    }

    /// Keep groups `reach` apart, so they stay separate groups: a group that another has grown
    /// into is pushed away as a whole, right or down, in reading order.
    static func separateGroups(_ frames: inout [CGRect], groups: [[Int]], reach: CGFloat) {
        func bounds(_ g: [Int]) -> CGRect { g.dropFirst().reduce(frames[g[0]]) { $0.union(frames[$1]) } }
        let order = groups.sorted { (bounds($0).minY, bounds($0).minX) < (bounds($1).minY, bounds($1).minX) }
        var settled: [CGRect] = []
        for g in order {
            for _ in 0..<200 {
                var push: CGVector?
                for r in g.map({ frames[$0] }) {
                    guard let hit = settled.first(where: { $0.insetBy(dx: -reach + 0.5, dy: -reach + 0.5).intersects(r) }) else { continue }
                    let right = hit.maxX + reach - r.minX, down = hit.maxY + reach - r.minY
                    push = right <= down ? CGVector(dx: right, dy: 0) : CGVector(dx: 0, dy: down)
                    break
                }
                guard let push else { break }
                for i in g { frames[i] = frames[i].offsetBy(dx: push.dx, dy: push.dy) }
            }
            settled += g.map { frames[$0] }
        }
    }

    /// Repair / scripting: put a window at a canvas position, as if you'd moved it there (its home
    /// spot follows); `commit` then moves real windows.
    func setCanvasOrigin(_ id: CGWindowID, _ origin: CGPoint, commit commitNow: Bool) {
        if let w = windows.first(where: { $0.id == id }) {
            let before = w.canvasFrame.origin
            w.canvasFrame.origin = origin
            noteUserMove(w, from: before)
        }
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
    private func arrive(_ w: ManagedWindow, anchor: ManagedWindow?, live: Bool, returning: Bool, reopened: Bool = false) {
        if returning, wentFullScreen.remove(w.id) != nil, live {
            // Back at its old spot (see add()), and the view goes there.
            backFromFullScreen(w)
            return
        } else if returning {
            // add() already put it back at its old spot.
        } else if windowKinds[w.id]?.standard ?? (AX.subrole(w.ax) == kAXStandardWindowSubrole as String),
                  let spot = freeSpot(for: w, near: anchor, onScreenOnly: !autoCentre) {
            w.canvasFrame.origin = spot
            logger.info("placed new window \(w.appName, privacy: .public) at \(NSStringFromPoint(spot), privacy: .public)\(anchor.map { " beside \($0.appName)[\($0.id)] at \(NSStringFromRect($0.canvasFrame))" } ?? "", privacy: .public)")
        } else {
            return
        }
        guard live else { view.render(); return }
        let r = camera.toView(w.canvasFrame)
        // You opened the app again, or brought it back from hiding (⌘-Tab, the Dock) or this window
        // back from the Dock, and it's in front: the view goes to its window, as to a new one. (Its
        // focus came before the window did, so focus can't decide.) Windows back for other reasons
        // (a display change, a Space switch) come back quietly.
        let now = CACurrentMediaTime()
        let shownAgain = returning && ((shownAgainAt[w.pid].map { now - $0 < 3 } ?? false)
                                       || (restoredAt.removeValue(forKey: w.id).map { now - $0 < 3 } ?? false))
        let opened = (reopened || shownAgain) && NSWorkspace.shared.frontmostApplication?.processIdentifier == w.pid
        if CGRect(origin: .zero, size: viewSize).contains(r) || (returning && !opened) {
            // On screen, or back from minimize / hide (quietly to its spot; focus decides whether
            // to glide): moved with the other new windows once the scan is applied. Until then,
            // its own move's echo isn't you moving it.
            w.lastPlacedAt = CACurrentMediaTime()
            arrivals.place = true
            view.render()
        } else {
            arrivals.glide.append(w)
        }
        scheduleSave()
    }

    /// Windows that opened during the window scan being applied (see apply).
    private var arrivals: (glide: [ManagedWindow], place: Bool) = ([], false)

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

    /// A canvas position for `w` that overlaps nothing. First anywhere along an edge of the
    /// anchor, the window it came from: right, below, left, then above, lined up with the
    /// anchor's top or left edge, then its bottom or right, then centred. Only when every edge is
    /// taken, beside the windows nearest the anchor, the closest first. Spots already on screen win.
    /// Upward comes last, near and far: a spot above the anchor only when there's none beside or
    /// below it within a few thousand points (going by distance alone, a gap in the row above
    /// often won).
    private func freeSpot(for w: ManagedWindow, near anchor: ManagedWindow?, onScreenOnly: Bool) -> CGPoint? {
        let others = windows.filter { $0 !== w }.map(\.canvasFrame)
        guard !others.isEmpty else { return nil }
        let gap = Self.gap
        let size = w.canvasFrame.size
        let target = anchor?.canvasFrame.center ?? camera.center(in: viewSize)
        let above = anchor?.canvasFrame.minY ?? target.y
        let visible = camera.toCanvas(CGRect(origin: .zero, size: viewSize))

        // (origin, score bias, ranked by distance to the anchor?)
        var candidates: [(CGPoint, CGFloat, Bool)] = []
        if let a = anchor?.canvasFrame {
            let ys = [a.minY, a.maxY - size.height, a.midY - size.height / 2]
            let xs = [a.minX, a.maxX - size.width, a.midX - size.width / 2]
            for (i, y) in ys.enumerated() { candidates.append((CGPoint(x: a.maxX + gap, y: y), CGFloat(i) * 10, false)) }
            for (i, x) in xs.enumerated() { candidates.append((CGPoint(x: x, y: a.maxY + gap), 40 + CGFloat(i) * 10, false)) }
            for (i, y) in ys.enumerated() { candidates.append((CGPoint(x: a.minX - gap - size.width, y: y), 80 + CGFloat(i) * 10, false)) }
            for (i, x) in xs.enumerated() { candidates.append((CGPoint(x: x, y: a.minY - gap - size.height), 120 + CGFloat(i) * 10, false)) }
        }
        // Further out: beside the windows nearest the anchor, after every spot touching it;
        // nudged by direction so ties go right, then down.
        let away: CGFloat = anchor == nil ? 0 : 5000
        let nearest = others.sorted { $0.center.distance(to: target) < $1.center.distance(to: target) }.prefix(12)
        for o in nearest {
            candidates.append((CGPoint(x: o.maxX + gap, y: o.minY), away, true))
            candidates.append((CGPoint(x: o.minX, y: o.maxY + gap), away + 40, true))
            candidates.append((CGPoint(x: o.minX - gap - size.width, y: o.minY), away + 80, true))
            candidates.append((CGPoint(x: o.minX, y: o.minY - gap - size.height), away + 120, true))
        }

        var best: (CGPoint, CGFloat)?
        for (origin, bias, byDistance) in candidates {
            let r = CGRect(origin: origin, size: size)
            if others.contains(where: { $0.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(r) }) { continue }
            if onScreenOnly && !visible.contains(r) { continue }
            let score = (byDistance ? r.center.distance(to: target) : 0) + bias + (visible.contains(r) ? 0 : 1500)
                + (r.maxY <= above + 0.5 ? 3000 : 0)
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
            recentlyRemoved[w.id] = Departed(pid: w.pid, bundleID: w.bundleID, appName: w.appName, title: w.title,
                                             canvasFrame: w.canvasFrame, originalFrame: w.originalFrame,
                                             preferredSize: w.preferredSize, home: w.home, parked: w.parked, at: Date(),
                                             closed: closedWindows.remove(w.id) != nil)
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
    /// during glides, windows in view or on the camera's path (the overlay covers the indicators;
    /// the windows it's handing back to stop first, see handingBackTo); at 100%, parked windows
    /// whose stand-in shows on the backdrop. Each window is captured once when first seen; a
    /// paused window keeps its last picture. `start`: capture it; `keep`: don't stop yet (a wider
    /// margin, so panning back and forth doesn't restart streams).
    private func wantsCapture(_ w: ManagedWindow, in region: CGRect) -> (start: Bool, keep: Bool) {
        if w.needsFirstFrame { return (true, true) }
        if let area = handBackArea, w.canvasFrame.intersects(area) { return (false, false) }
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
    /// like; the other windows in view get one-off pictures in turn. A VM's replayd gives out
    /// sooner: `defaults write com.invignation.expanse streamBudget -int 8` lowers it.
    private static let streamBudget = { let n = UserDefaults.standard.integer(forKey: "streamBudget"); return n > 0 ? n : 16 }()

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
        // replayd isn't answering: asking for more only piles them up in it.
        guard WindowCapture.canAsk else { return }
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

    /// While handing back to the real windows (from a glide's last third, or the start of the zoom
    /// back in from the canvas, until the overlay drops), the canvas area they'll show. Windows
    /// there don't stream meanwhile: macOS would badge them (see stopStreamsOnScreen), and a
    /// stream started now would only come up once the real window shows.
    private var handingBackTo: CGRect?

    private var handBackArea: CGRect? {
        if let a = animation, a.handsBack { return a.to.toCanvas(CGRect(origin: .zero, size: viewSize)) }
        return handingBackTo
    }

    private func beginHandBack() {
        handingBackTo = camera.toCanvas(CGRect(origin: .zero, size: viewSize))
    }

    /// While a window is streamed, macOS draws a purple badge over its traffic lights, inside the
    /// app's own window, where nothing can cover it (one-off pictures and whole-screen captures
    /// don't get one). So before the overlay drops, the streams of windows that will be on screen
    /// stop; `done` runs once they have and the badges have gone (about 50ms later), or after a
    /// quarter of a second whatever happens.
    private func stopStreamsOnScreen(then done: @escaping () -> Void) {
        let streamed = windows.filter { !$0.parked && !$0.capture.isStopped }
        guard !streamed.isEmpty else { done(); return }
        var left = streamed.count, finished = false
        let finish = {
            guard !finished else { return }
            finished = true
            done()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: finish)
        for w in streamed {
            w.capture.pause {
                left -= 1
                if left == 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: finish) }
            }
        }
    }

    /// After handing back to the real windows (whose streams have stopped; see
    /// stopStreamsOnScreen): keep capturing parked ones a moment longer, so quick successive hops
    /// reuse their streams.
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
        // The desktop as it is now (its icons, any dimming): the last one shows until it comes.
        if CACurrentMediaTime() - lastWallpaperRefresh > 2, WindowCapture.canAsk { refreshWallpaper() }
        refreshSpaces()
        NSApp.activate(ignoringOtherApps: true)
        overlay.level = canvasLevel
        overlay.makeKeyAndOrderFront(nil)
        overlay.makeFirstResponder(view)
        returnCamera = nil
        if zoomOut {
            returnCamera = camera
            animate(to: overviewCamera())
        }
    }

    func refreshSpaces() {
        let (spaces, active) = Spaces.list()
        // The desktop the canvas lives on is Expanse, as far as you're concerned.
        let canvas = canvasDesktop
        view.updateSpaces(spaces.map { $0.id == canvas ? Spaces.Space(id: $0.id, pid: nil, window: nil, name: "Expanse") : $0 },
                          active: active)
    }

    /// A tile in the Spaces bar (or expanse://space): go to that Space, from the canvas or at 100%.
    /// A window becoming key is what makes macOS switch Spaces; Accessibility and ordinary
    /// activation bring an app forward without leaving the Space you're on (see activate).
    func switchToSpace(_ space: Spaces.Space) {
        guard !gliding else { return }
        // Already on that Space: from the canvas, its tile means back to it at 100%, which is what
        // leaving the canvas does (over a full-screen app, back to that app). At 100% there's
        // nothing to do (and no reason to move focus).
        if space.id == Spaces.list().active {
            if isActive { exit() }
            return
        }
        let target: (pid: pid_t, window: CGWindowID?, element: AXUIElement?)
        if let pid = space.pid {
            target = (pid, space.window, nil)
        } else {
            if canvasDesktop == nil || canvasDesktop == space.id {
                // Back to the canvas's own Space from the canvas (opened over a full-screen app):
                // stay on the canvas, swiping there under it, so you can pick a window.
                if isActive, SpaceSwipe.go(to: space.id) {
                    logger.info("back to the canvas's Space, staying on the canvas")
                    // The canvas comes along when macOS says the Space changed (canvasFollowsSpace).
                    return
                }
                // The canvas's own desktop: back to the window you were last in (whose
                // Accessibility element Expanse already has, and which works from any Space).
                guard let w = windows.last(where: { !$0.parked }) ?? windows.last else { return }
                target = (w.pid, w.id, w.ax)
            } else if let other = Spaces.someWindow(on: space.id) {
                target = (other.pid, other.id, nil)
            } else {
                Toast.show("Nothing open on \(space.name) to switch to")
                return
            }
        }
        let from = Spaces.list().active
        // A swipe too fast to animate gets there instantly; zoomed out, it happens under the
        // canvas, which is on every Space and stays put. Focusing the window afterwards gives it
        // the keyboard (or, if the swipe couldn't be made, takes macOS there the slow way).
        let instant = SpaceSwipe.go(to: space.id)
        logger.info("switching from Space \(from ?? 0) to \(space.name, privacy: .public) (\(space.id))\(instant ? ", instantly" : "", privacy: .public)")
        let go: () -> Void = { [weak self] in
            self?.activate(target.pid, raising: target.window, element: target.element, toward: space.id)
        }
        if isActive {
            // Back to 100% first, so the canvas isn't left covering the screen.
            exit(then: go)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + (instant ? 0.05 : 0), execute: go)
        }
    }

    /// The canvas is open and you've moved to a desktop Space (from a full-screen app's, say): it
    /// comes too. Its window is on every Space, but macOS stops drawing it after a switch away
    /// from a full-screen app's Space until it's shown again, and gives the keyboard to an app on
    /// the new Space. (Moving to a full-screen app's Space, the canvas is on its way out.)
    private func canvasFollowsSpace() {
        // Not once leaving has got to moving windows (gliding): the window you picked has the
        // keyboard, or is about to.
        guard isActive, !gliding, Spaces.current?.isDesktop == true else { return }
        overlay.orderOut(nil)
        overlay.orderFrontRegardless()
        // Once another app is active, ordinary activation is refused; the window server's own
        // "bring this window forward" isn't.
        Spaces.focus(pid: getpid(), window: CGWindowID(overlay.windowNumber))
        NSApp.activate(ignoringOtherApps: true)
        overlay.makeKeyAndOrderFront(nil)
        overlay.makeFirstResponder(view)
    }

    /// The desktop Space the canvas's windows are on.
    var canvasDesktop: UInt64? {
        windows.last.flatMap { Spaces.spaces(of: $0.id).first }
    }

    /// What AltTab does to reach a window on another Space, which is what makes macOS go there:
    /// bring it forward and make it key through the window server (see Spaces.focus), activate its
    /// app, and raise it through Accessibility (see AX.window for finding it off this Space, when
    /// `known` isn't given).
    private func activate(_ pid: pid_t, raising window: CGWindowID?, element known: AXUIElement?, toward space: UInt64) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        axQueue.async {
            let element = known ?? window.flatMap { AX.window(pid: pid, id: $0) }
            DispatchQueue.main.async {
                let focused = window.map { Spaces.focus(pid: pid, window: $0) }
                NSApp.yieldActivation(to: app)
                app.activate(from: .current, options: [])
                self.axQueue.async {
                    if let element { AX.raise(element) }
                }
                logger.info("Space switch: window server focus \(focused.map { "\($0)" } ?? "-", privacy: .public), window \(element == nil ? "not found" : "found", privacy: .public)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let now = Spaces.list().active
                    logger.info("Space switch \(now == space ? "done" : "didn't happen", privacy: .public): on \(now ?? 0)")
                }
            }
        }
    }

    /// Animate to 100% (onto `focus` if given), put real windows where the camera says, drop the overlay.
    /// `then`, if given, runs instead of focusing a window (going to another Space, say).
    func exit(focus: ManagedWindow? = nil, then: (() -> Void)? = nil) {
        guard isActive else { return }
        var then = then
        // Opened over a full-screen app: the canvas's windows are on the desktop's Space.
        if then == nil, let here = Spaces.current, let pid = here.pid {
            if focus != nil {
                // Going to one of them: switch to the desktop now, under the canvas, so it's
                // instant and out of sight, instead of a slide out of the app afterwards.
                if let desktop = canvasDesktop, SpaceSwipe.go(to: desktop) {
                    logger.info("switched to the canvas's desktop under the canvas")
                }
            } else {
                // Leaving without picking one: back to the full-screen app you came from.
                let window = here.window
                then = { [weak self] in self?.activate(pid, raising: window, element: nil, toward: here.id) }
            }
        }
        let target: Camera
        if let focus {
            bringToFront(focus)
            fitToScreen(focus)
            if viewPlaced, abs(camera.scale - 1) < 0.001,
               Self.goesOnScreen(camera.toView(focus.canvasFrame).offsetBy(dx: viewport.minX, dy: viewport.minY), in: viewport) {
                // You put the view here: the window you picked is on screen, and the view stays.
                logger.info("view placed by you: diving into \(focus.appName, privacy: .public)[\(focus.id)] where it is")
                target = Camera(origin: CGPoint(x: camera.origin.x.rounded(), y: camera.origin.y.rounded()), scale: 1)
            } else {
                viewPlaced = false
                target = focusCamera(for: focus)
            }
        } else {
            // Straight back where you were, unless you've moved around since zooming out.
            target = returnCamera ?? Camera.centered(on: camera.center(in: viewSize), scale: 1, viewSize: viewSize)
        }
        animate(to: target, duration: 0.18, handsBack: true) { [weak self] in
            guard let self else { return }
            // Like a glide's last step: input waits while the real windows move in the background.
            self.gliding = true
            self.beginHandBack()
            self.commitAsync { moves in
                // Sink the overlay beneath the real windows so it becomes the desktop.
                let handBack = {
                    self.handingBackTo = nil
                    self.overlay.level = OverlayWindow.backdropLevel
                    self.isActive = false
                    self.gliding = false
                    self.pathRegion = nil
                    self.view.render()
                    self.updateStreamingLingering()
                }
                if let then {
                    // Off to another Space: that takes over, with a beat for the moved windows.
                    then()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: handBack)
                } else {
                    self.focus(focus ?? self.windows.last(where: { !$0.parked }), after: moves, thenHandBack: handBack)
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
            if Self.goesOnScreen(r, in: vp) {
                return (w, CGPoint(x: r.minX.rounded(), y: r.minY.rounded()), false)
            }
            return (w, parkPoint, true)
        }
    }

    /// A window at `r` (global) is put on screen, not parked: enough of it shows. macOS won't put
    /// a title bar above the menu bar (it would shove the window down), so one whose top is cut
    /// off stays parked, and the backdrop draws it where it belongs.
    private static func goesOnScreen(_ r: CGRect, in vp: CGRect) -> Bool {
        let visible = r.intersection(vp)
        return r.minY >= vp.minY - 1 && !visible.isNull && visible.width >= 48 && visible.height >= 48
    }

    private let axQueue = DispatchQueue(label: "com.invignation.expanse.ax", qos: .userInteractive)

    /// A window commitAsync moved, and where it landed: nil for parked (anywhere in the corner).
    private typealias Move = (window: ManagedWindow, to: CGPoint?)

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
    /// `completion` gets the moves made.
    private func commitAsync(_ completion: @escaping ([Move]) -> Void) {
        let jobs = commitPlan().compactMap { (w, target, parked) -> (ManagedWindow, AXUIElement, CGPoint, Bool)? in
            if alreadyAt(w, target, parked: parked) { w.parked = parked; return nil }
            guard let ax = w.ax else { return nil }
            return (w, ax, target, parked)
        }
        guard !jobs.isEmpty else { scheduleSave(); completion([]); return }
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
                var moves: [Move] = []
                for ((w, _, target, parked), at) in zip(jobs, landed) {
                    w.lastPlaced = at ?? target
                    w.lastPlacedAt = now
                    w.parked = parked
                    moves.append((w, parked ? nil : at ?? target))
                }
                self.scheduleSave()
                completion(moves)
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
        // App windows on screen that aren't on the canvas, and why not.
        let managed = Set(windows.map(\.id))
        let fullScreen = Spaces.fullScreenWindows()
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let id = w[kCGWindowNumber as String] as? CGWindowID, !managed.contains(id),
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  let bounds = w[kCGWindowBounds as String] as? [String: CGFloat], bounds["Width"] ?? 0 >= 100 else { continue }
            let kind = windowKinds[id].map { "standard=\($0.standard) pending=\($0.pending) age=\(Int(CACurrentMediaTime() - $0.at))s" } ?? "never asked"
            let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
            logger.info("dump unmanaged \(owner, privacy: .public)[\(id)] \(kind, privacy: .public) scanned=\(self.scannedIDs.contains(id)) fullScreen=\(fullScreen.contains(id)) regular=\(Self.isRegularApp(pid)) recentlyRemoved=\(self.recentlyRemoved[id] != nil)")
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
        let target = Self.cap(w.preferredSize, to: viewSize)
        guard let ax = w.ax, !w.sizesItself,
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
        // A VM or remote-screen window: its app sets the size (see ManagedWindow.sizesItself).
        if w.sizesItself { return AX.size(ax) ?? w.canvasFrame.size }
        if let current = AX.size(ax), size.width > current.width + 1 || size.height > current.height + 1 {
            AX.setPosition(ax, viewport.origin)
            w.lastPlaced = nil
        }
        AX.setSize(ax, size)
        let actual = AX.size(ax) ?? size
        w.lastSized = actual
        w.lastSizedAt = CACurrentMediaTime()
        return actual
    }

    /// Takes on a size change of the real window. Resizes we didn't make become the
    /// window's preferred size.
    /// Only a resize you made counts as you choosing a size: dragging an edge, or one right after
    /// your click or key press in its app (see realWindowChanged). macOS, apps (Chromium animates
    /// AX resizes in steps) and Expanse itself resize windows too, and none of those should change
    /// the size you chose. The exception: a VM or remote
    /// screen window, whose app picks its size (see ManagedWindow.sizesItself).
    private func adoptSize(_ w: ManagedWindow, _ size: CGSize, fromUser: Bool = false) {
        guard size != w.canvasFrame.size, size.width > 0, size.height > 0 else { return }
        w.canvasFrame.size = size
        let ours = w.lastSized.map { abs($0.width - size.width) < 2 && abs($0.height - size.height) < 2 } ?? false
        if (fromUser || w.sizesItself) && !ours && !suspendTracking {
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
        viewPlaced = abs(camera.scale - 1) < 0.001
        cameraChanged()
    }

    /// A scroll at 100% has ended, momentum and all (see CanvasView.scrollWheel): if it left windows
    /// cut off by the screen's edges, the view moves on a little, to where they're whole or out of
    /// sight (see snappedCamera).
    func scrollEnded() {
        guard isActive, !gliding, animation == nil, abs(camera.scale - 1) < 0.001 else { return }
        let target = snappedCamera()
        guard target != camera else { return }
        logger.info("scroll ended: view snapped by \(target.origin.x - self.camera.origin.x), \(target.origin.y - self.camera.origin.y)")
        animate(to: target, duration: 0.25)
    }

    /// The view at 100%, moved by the least that leaves the fewest windows cut off by the screen's
    /// edges, and at least one whole. Each move tried puts the edge of a window on screen a gap in
    /// from the screen's, which (windows being a gap apart) also takes the next one just out of
    /// sight, or centres a window with less than that to spare (one filling the screen, say). None
    /// further than half the screen: you scrolled here, so the view stays near.
    private func snappedCamera() -> Camera {
        let screen = CGRect(origin: .zero, size: viewSize)
        let frames = windows.map { camera.toView($0.canvasFrame) }
        let shown = frames.filter { !$0.intersection(screen).isEmpty }
        guard shown.contains(where: { !screen.contains($0) }) else { return camera }
        let g = Self.gap
        let reach = CGSize(width: screen.width / 2, height: screen.height / 2)
        // Moves along one side that line a window up with the screen (`from`, `to`: its edges).
        func moves(_ from: CGFloat, _ to: CGFloat, screen length: CGFloat) -> [CGFloat] {
            let spare = length - (to - from)
            return spare < 2 * g ? [g - from, length - g - to, spare / 2 - from] : [g - from, length - g - to]
        }
        let xs = ([0] + shown.flatMap { moves($0.minX, $0.maxX, screen: screen.width) }).filter { abs($0) <= reach.width }
        let ys = ([0] + shown.flatMap { moves($0.minY, $0.maxY, screen: screen.height) }).filter { abs($0) <= reach.height }
        // How cut off a window is along one side: 0 whole or out of sight, 0.5 half on screen. One
        // too big for the screen that way counts as whole.
        func cut(_ visible: CGFloat, _ length: CGFloat, screen: CGFloat) -> CGFloat {
            guard length > 0, length <= screen else { return 0 }
            let f = max(0, min(visible / length, 1))
            return min(f, 1 - f)
        }
        // Lower is better: none whole, then how much is cut off and how far the view moves.
        func cost(_ dx: CGFloat, _ dy: CGFloat) -> (noneWhole: Bool, cut: CGFloat) {
            var whole = false
            var cuts: CGFloat = 0
            for r in frames {
                let s = r.offsetBy(dx: dx, dy: dy)
                let visible = s.intersection(screen)
                // Out of sight, just touching the screen's edge included.
                guard !visible.isEmpty else { continue }
                whole = whole || screen.contains(s)
                cuts += cut(visible.width, s.width, screen: screen.width) + cut(visible.height, s.height, screen: screen.height)
            }
            // Of two that leave as much cut off, the shorter move.
            return (!whole, cuts + 0.5 * (abs(dx) / screen.width + abs(dy) / screen.height))
        }
        var best = (dx: CGFloat(0), dy: CGFloat(0), cost: cost(0, 0))
        for dx in xs {
            for dy in ys {
                let c = cost(dx, dy)
                if (!c.noneWhole && best.cost.noneWhole) || (c.noneWhole == best.cost.noneWhole && c.cut < best.cost.cut - 0.001) {
                    best = (dx, dy, c)
                }
            }
        }
        var target = camera
        target.pan(by: CGVector(dx: best.dx, dy: best.dy))
        target.origin = CGPoint(x: target.origin.x.rounded(), y: target.origin.y.rounded())
        return target
    }

    func zoom(by factor: CGFloat, at anchor: CGPoint) {
        returnCamera = nil
        viewPlaced = false
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

    /// For demo recordings: camera moves take this many times as long, so a recorder that can only
    /// keep up at 30fps (in a VM) still gets every frame, and the clip is sped up afterwards.
    /// `defaults write com.invignation.expanse animationSlowdown -float 2`; read at launch.
    private let animationSlowdown = max(1, UserDefaults.standard.double(forKey: "animationSlowdown"))

    func animate(to target: Camera, duration: CFTimeInterval = 0.22, handsBack: Bool = false, completion: (() -> Void)? = nil) {
        animation = CameraAnimation(from: camera, to: target, start: CACurrentMediaTime(), duration: duration * animationSlowdown,
                                    completion: completion, handsBack: handsBack)
        // Moving on (a hop during the last one's hand-back, say): nothing's being handed back to.
        handingBackTo = nil
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
        // A glide's last third moves the camera a few points: the windows it lands on stop
        // streaming now (see handingBackTo), as replayd takes 20ms a stream to stop them, which
        // the hand-back would otherwise wait for.
        if gliding, glideTarget != nil, handingBackTo == nil, t >= 0.65 {
            handingBackTo = a.to.toCanvas(CGRect(origin: .zero, size: viewSize))
            updateStreaming(reconfigure: false)
        }
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

    /// Presses each window's own close button, so apps ask about unsaved changes as usual. Off the
    /// main thread: pressing waits on the app.
    func close(_ ws: [ManagedWindow]) {
        let elements = ws.compactMap(\.ax)
        guard !elements.isEmpty else { return }
        if elements.count > 1 { logger.info("closing \(elements.count) windows") }
        axQueue.async { [weak self] in
            elements.forEach(AX.close)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.sync() }
        }
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
    /// Live mode: below every app window, and see-through but for what Expanse draws there (the
    /// pictures of parked windows, the minimap): the real desktop shows, as macOS draws it, with
    /// the shade it keeps under the menu bar and the dimming behind a window that fills the screen.
    /// A copy of the desktop picture couldn't follow either. Not a desktop-level window: under the
    /// menu bar macOS treats those as wallpaper and adds its legibility shadow over them.
    static let backdropLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        level = OverlayWindow.backdropLevel
        // See-through at 100% (see backdropLevel), and so are its clicks: where nothing's drawn, they
        // reach the desktop under it (its icons, its menu). What Expanse draws there takes its own.
        // Scrolling or pinching on the desktop still opens the canvas (see handleDesktopGesture).
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
