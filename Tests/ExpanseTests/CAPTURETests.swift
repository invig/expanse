import Testing
import AppKit
import CoreMedia
import CoreVideo
import IOSurface
import ScreenCaptureKit
import ObjectiveC
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "WindowCapture.swift") @testable import Expanse
@_private(sourceFile: "Wallpaper.swift") @testable import Expanse

/// docs/regression/capture-and-performance.md. Nothing here captures: ScreenCaptureKit's picture
/// call is replaced by `Shots` (WindowCapture.screenshot), running streams are `FakeStream`s, and
/// stream starts are held back by WindowCapture.canAsk (replayd "stuck") wherever one could start.
@MainActor @Suite("CAPTURE: Capture and performance", .serialized) struct CAPTURETests {

    // MARK: Picture sizes

    @Test("CAPTURE-02 Pictures are captured at the size they're drawn")
    func capture02() async throws {
        try await withCapture { lab in
            let w = window(1, CGRect(x: 0, y: 0, width: 800, height: 500))
            let c = lab.canvas([w], zoomedOut: true)
            let b = c.screen.backingScaleFactor
            func factor(at scale: CGFloat) -> CGFloat {
                c.camera = Camera(origin: .zero, scale: scale)
                let size = c.pixelSize(for: w)
                #expect(size.height / (500 * b) == size.width / (800 * b))
                return size.width / (800 * b)
            }
            let steps: [(zoom: CGFloat, factor: CGFloat)] = [
                (1, 1), (0.9, 1), (0.7, 1), (0.69, 0.5), (0.5, 0.5), (0.36, 0.5), (0.34, 0.25), (0.25, 0.25),
                (0.18, 0.25), (0.17, 0.125), (0.1, 0.125), (0.08, 1.0 / 16), (0.05, 1.0 / 16), (Camera.minScale, 1.0 / 16),
            ]
            for step in steps { #expect(factor(at: step.zoom) == step.factor, "zoom \(step.zoom)") }
            // Halving the zoom halves the picture; in between it stays put (steps, not continuous).
            #expect(factor(at: 0.25) == factor(at: 0.5) / 2)
            #expect(factor(at: 0.6) == factor(at: 0.4))
            // At 100% (live), full size whatever the camera says.
            c.isActive = false
            c.camera = Camera(origin: .zero, scale: 0.1)
            #expect(c.pixelSize(for: w) == CGSize(width: 800 * b, height: 500 * b))
        }
    }

    @Test("CAPTURE-03 Diving into a window shows it sharp on arrival")
    func capture03() async throws {
        try await withCapture { lab in
            let w = window(1, CGRect(x: 0, y: 0, width: 800, height: 500))
            let c = lab.canvas([w], zoomedOut: true, camera: Camera(origin: CGPoint(x: -5000, y: -3000), scale: 0.1))
            let b = c.screen.backingScaleFactor
            let full = CGSize(width: 800 * b, height: 500 * b)
            #expect(c.pixelSize(for: w).width < full.width / 4)
            // Zooming into it: captured at the size it arrives at, from the start of the zoom.
            let target = Camera.centered(on: w.canvasFrame.center, scale: 1, viewSize: c.viewSize)
            c.animation = CanvasController.CameraAnimation(from: c.camera, to: target, start: CACurrentMediaTime(), duration: 0.3)
            #expect(c.pixelSize(for: w) == full)
            c.camera = Camera.centered(on: w.canvasFrame.center, scale: 0.4, viewSize: c.viewSize)
            #expect(c.pixelSize(for: w) == full)
        }
    }

    @Test("CAPTURE-06 Zoomed out, only windows in view are captured")
    func capture06() async throws {
        try await withCapture { lab in
            // Zoom 0.5: the view is canvas (0, 0, 3024, 1898).
            let inView = window(1, CGRect(x: 100, y: 100, width: 400, height: 300))
            let margin = window(2, CGRect(x: 3100, y: 100, width: 200, height: 200))    // within 10% of the view
            let wider = window(3, CGRect(x: 3500, y: 100, width: 200, height: 200))     // within 35%
            let away = window(4, CGRect(x: 5000, y: 100, width: 200, height: 200))
            let c = lab.canvas([inView, margin, wider, away], zoomedOut: true, camera: Camera(origin: .zero, scale: 0.5))
            let region = c.captureRegion
            #expect(c.wantsCapture(inView, in: region) == (true, true))
            #expect(c.wantsCapture(margin, in: region) == (true, true))
            // Kept if already running (no churn at the edges), not started.
            #expect(c.wantsCapture(wider, in: region) == (false, true))
            #expect(c.wantsCapture(away, in: region) == (false, false))
            lab.stream(c)
            #expect(inView.capture.wanted && margin.capture.wanted)
            #expect(!wider.capture.wanted && !away.capture.wanted)
            #expect(c.snapshotQueue.isEmpty)
            // Panning to another area: the windows there instead.
            c.camera = Camera(origin: CGPoint(x: 4000, y: 0), scale: 0.5)
            let moved = c.captureRegion
            #expect(c.wantsCapture(away, in: moved).start)
            #expect(!c.wantsCapture(inView, in: moved).start)
        }
    }

    @Test("CAPTURE-08 Pictures are captured smaller the further out you zoom")
    func capture08() async throws {
        try await withCapture { lab in
            let w = window(1, CGRect(x: 0, y: 0, width: 1000, height: 600))
            let c = lab.canvas([w], zoomedOut: true)
            let b = c.screen.backingScaleFactor
            var last: CGFloat = 1
            var seen = Set<CGFloat>()
            var zoom: CGFloat = 1
            while zoom >= Camera.minScale {
                c.camera = Camera(origin: .zero, scale: zoom)
                let factor = c.pixelSize(for: w).width / (1000 * b)
                #expect([1, 0.5, 0.25, 0.125, 0.0625].contains(factor), "zoom \(zoom): \(factor)")
                #expect(factor <= last, "smaller as you zoom out")
                // Crisp: never much smaller than it's drawn.
                #expect(factor * 1.4 > zoom, "zoom \(zoom): \(factor)")
                seen.insert(factor)
                last = factor
                zoom *= 0.97
            }
            #expect(seen == [1, 0.5, 0.25, 0.125, 0.0625])
        }
    }

    @Test("CAPTURE-11 Hopping to a nearby window after using the canvas shows it sharp: blurry pictures found")
    func capture11a() async throws {
        try await withCapture { lab in
            // At 100%: the view is canvas (0, 0, 1512, 949); half a screen around it reaches x = 2268.
            let near = window(1, CGRect(x: 1600, y: 100, width: 800, height: 600), parked: true)
            let far = window(2, CGRect(x: 3000, y: 100, width: 800, height: 600), parked: true)
            let c = lab.canvas([near, far])
            let b = c.screen.backingScaleFactor
            near.pictureWidth = Int(800 * b / 16)     // a thumbnail from the zoomed-out canvas
            #expect(c.pictureNeedsResizing(near))
            near.pictureWidth = Int(800 * b)
            #expect(!c.pictureNeedsResizing(near))
            far.pictureWidth = Int(800 * b)           // full size, far from the view
            #expect(c.pictureNeedsResizing(far))
            far.pictureWidth = Int(200 * b)
            #expect(!c.pictureNeedsResizing(far))
            // Only parked windows without a stream or a first picture still to come.
            near.pictureWidth = Int(800 * b / 16)
            near.parked = false
            #expect(!c.pictureNeedsResizing(near))
            near.parked = true
            near.needsFirstFrame = true
            #expect(!c.pictureNeedsResizing(near))
            near.needsFirstFrame = false
            lab.run(near)
            #expect(!c.pictureNeedsResizing(near))
        }
    }

    @Test("CAPTURE-11 Parked windows near the view are re-captured at full size, nearest first")
    func capture11b() async throws {
        try await withCapture(stuck: false) { lab in
            let nearer = window(1, CGRect(x: 1550, y: 200, width: 800, height: 600), parked: true)
            let further = window(2, CGRect(x: 1600, y: 1000, width: 800, height: 600), parked: true)
            let c = lab.canvas([further, nearer])
            let b = c.screen.backingScaleFactor
            nearer.pictureWidth = Int(800 * b / 8)
            further.pictureWidth = Int(800 * b / 8)
            c.pumpSnapshots()
            try await settle()
            #expect(lab.shots.asked == [1])
            #expect(lab.shots.sizes == [CGSize(width: 800 * b, height: 600 * b)])
            // Four a second at most.
            c.lastSharpening = CACurrentMediaTime()
            c.pumpSnapshots()
            try await settle()
            #expect(lab.shots.asked == [1])
            c.lastSharpening = 0
            c.pumpSnapshots()
            try await settle()
            #expect(lab.shots.asked == [1, 2])
        }
    }

    @Test("CAPTURE-14 Window pictures take far less memory: full size near the view, a quarter further away")
    func capture14a() async throws {
        try await withCapture { lab in
            let inView = window(1, CGRect(x: 100, y: 100, width: 800, height: 600), parked: true)
            let halfScreen = window(2, CGRect(x: 2200, y: 100, width: 800, height: 600), parked: true)
            let beyond = window(3, CGRect(x: 2300, y: 100, width: 800, height: 600), parked: true)
            let below = window(4, CGRect(x: 100, y: 1500, width: 800, height: 600), parked: true)
            let c = lab.canvas([inView, halfScreen, beyond, below])
            let b = c.screen.backingScaleFactor
            let full = CGSize(width: 800 * b, height: 600 * b)
            let quarter = CGSize(width: 200 * b, height: 150 * b)
            #expect(c.livePictureSize(for: inView) == full)
            #expect(c.livePictureSize(for: halfScreen) == full)
            #expect(c.livePictureSize(for: beyond) == quarter)
            #expect(c.livePictureSize(for: below) == quarter)
            // It follows the view.
            c.camera = Camera(origin: CGPoint(x: 1500, y: 0), scale: 1)
            #expect(c.livePictureSize(for: beyond) == full)
        }
    }

    @Test("CAPTURE-14 A snapshot keeps only its own buffer")
    func capture14b() {
        let cap = WindowCapture()
        cap.deliver(picture(), snapshot: false)
        cap.deliver(picture(), snapshot: false)
        #expect(cap.recentSamples.count == 2)
        cap.deliver(picture(), snapshot: true)
        #expect(cap.recentSamples.count == 1)
    }

    // MARK: Streams

    @Test("CAPTURE-09 At most 16 windows stream: the setting only lowers it")
    func capture09a() {
        #expect(CanvasController.streamBudget == 16)
        for (setting, budget) in [(0, 16), (-3, 16), (1, 1), (4, 4), (8, 8), (16, 16), (17, 16), (50, 16)] {
            #expect(CanvasController.streamBudget(setting: setting) == budget, "streamBudget \(setting)")
        }
    }

    @Test("CAPTURE-09 The glide's target streams first, then those most on screen; the rest by snapshot")
    func capture09b() async throws {
        try await withCapture { lab in
            // Zoom 0.25: the view is canvas (0, 0, 6048, 3796), centred on (3024, 1898).
            var smalls: [ManagedWindow] = []
            for i in 0..<18 {
                smalls.append(window(CGWindowID(10 + i), CGRect(x: 2400 + CGFloat(i) * 150, y: 1850, width: 100, height: 100)))
            }
            let big = window(1, CGRect(x: 100, y: 100, width: 1500, height: 1000))          // far from the centre, most on screen
            let target = window(2, CGRect(x: 5800, y: 3600, width: 100, height: 100))       // far and small
            let c = lab.canvas(smalls + [big, target], zoomedOut: true, camera: Camera(origin: .zero, scale: 0.25))
            c.glideTarget = target
            lab.stream(c)
            let centre = c.camera.center(in: c.viewSize)
            let byDistance = smalls.sorted { $0.canvasFrame.center.distance(to: centre) < $1.canvasFrame.center.distance(to: centre) }
            // 16 stream: the target, the big one, the 14 nearest; the 4 furthest get snapshots, nearest first.
            #expect(c.captureLoad == 16)
            #expect(c.snapshotQueue == byDistance.suffix(4).map(\.id))
            // The most important start first (ten a pass; the rest on the next).
            let first = Set([target, big].map(\.id) + byDistance.prefix(8).map(\.id))
            #expect(Set(c.windows.filter(\.capture.wanted).map(\.id)) == first)
        }
    }

    @Test("CAPTURE-09 Windows without a stream get a snapshot each about every 1.5s, one per pass")
    func capture09c() async throws {
        try await withCapture(stuck: false) { lab in
            let ws = (0..<4).map { window(CGWindowID(1 + $0), CGRect(x: CGFloat($0) * 700, y: 100, width: 600, height: 400)) }
            let c = lab.canvas(ws, zoomedOut: true, camera: Camera(origin: .zero, scale: 0.5))
            c.snapshotQueue = ws.map(\.id)
            for _ in 0..<4 {
                c.pumpSnapshots()
                try await Task.sleep(for: .milliseconds(30))
            }
            #expect(lab.shots.asked.count == 4)
            #expect(Set(lab.shots.asked) == Set(ws.map(\.id)))
            // Each at most every 1.5s.
            c.pumpSnapshots()
            try await settle()
            #expect(lab.shots.asked.count == 4)
            for w in ws { w.lastSnapshotAt = CACurrentMediaTime() - 1.3 }
            c.pumpSnapshots()
            try await settle()
            #expect(lab.shots.asked.count == 4)
            for w in ws { w.lastSnapshotAt = CACurrentMediaTime() - 1.6 }
            c.pumpSnapshots()
            try await settle()
            #expect(lab.shots.asked.count == 5)
            // A pass every 0.1s: about ten a second in all.
            c.pumpSnapshotsSoon()
            #expect(c.snapshotTimer?.timeInterval == 0.1)
            lab.stopTimer(c)
        }
    }

    @Test("CAPTURE-13 A new size restarts the stream rather than reconfiguring it")
    func capture13() async throws {
        try await withCapture { lab in
            let cap = WindowCapture()
            let stream = lab.run(cap, size: CGSize(width: 1600, height: 1000), fps: 30)
            cap.update(pixelSize: CGSize(width: 800, height: 500), fps: 30)
            try await Task.sleep(for: .milliseconds(50))
            #expect(stream.calls == ["stop"])
            #expect(cap.stream == nil && cap.isStopped)
            // Started again at the new size (held back here: nothing may start in a test).
            #expect(cap.wanted && cap.pixelSize == CGSize(width: 800, height: 500))
            // The same size and a similar rate: left running as it is.
            let same = WindowCapture()
            let kept = lab.run(same, size: CGSize(width: 800, height: 500), fps: 30)
            same.update(pixelSize: CGSize(width: 800, height: 500), fps: 20)
            try await Task.sleep(for: .milliseconds(50))
            #expect(kept.calls.isEmpty)
            #expect(same.stream === kept)
        }
    }

    @Test("CAPTURE-17 Interrupting a zoom stops capturing the path it would have taken")
    func capture17() async throws {
        try await withCapture { lab in
            let c = lab.canvas([], zoomedOut: true, camera: Camera(origin: .zero, scale: 0.5))
            let view = c.camera.toCanvas(CGRect(origin: .zero, size: c.viewSize))
            c.pathRegion = CGRect(x: -20_000, y: -20_000, width: 40_000, height: 40_000)
            c.animation = CanvasController.CameraAnimation(from: c.camera, to: Camera(origin: .zero, scale: 0.05),
                                                           start: CACurrentMediaTime(), duration: 0.22)
            c.cancelAnimation()
            #expect(c.pathRegion == nil && c.animation == nil)
            #expect(c.captureRegion == view)
            // A glide keeps its path until it hands back.
            c.gliding = true
            c.pathRegion = CGRect(x: 0, y: 0, width: 5000, height: 1000)
            c.cancelAnimation()
            #expect(c.pathRegion == CGRect(x: 0, y: 0, width: 5000, height: 1000))
        }
    }

    @Test("CAPTURE-18 Streams restart when their rate at least doubles or halves")
    func capture18a() async throws {
        try await withCapture { lab in
            let size = CGSize(width: 800, height: 500)
            for (configured, asked, restarts) in [(30, 2, true), (30, 15, true), (30, 16, false), (30, 60, true),
                                                  (30, 59, false), (2, 4, true), (2, 3, false), (15, 8, false), (15, 7, true)] {
                let cap = WindowCapture()
                let stream = lab.run(cap, size: size, fps: configured)
                cap.update(pixelSize: size, fps: asked)
                try await Task.sleep(for: .milliseconds(20))
                #expect(stream.calls == (restarts ? ["stop"] : []), "\(configured) fps to \(asked)")
                #expect((cap.stream == nil) == restarts)
            }
        }
    }

    @Test("CAPTURE-18 After a glide, streams ask for the resting 2 fps")
    func capture18b() async throws {
        try await withCapture { lab in
            let w = window(1, CGRect(x: 0, y: 0, width: 1200, height: 800), parked: true)
            let c = lab.canvas([w], zoomedOut: true)
            #expect(c.captureFPS(for: w) == CanvasController.canvasFPS)
            c.isActive = false
            #expect(c.captureFPS(for: w) == 2)
            // A glide's 30 fps stream, brought to the resting rate: restarted.
            let stream = lab.run(w, size: c.pixelSize(for: w), fps: 30)
            c.updateCapture(w)
            try await Task.sleep(for: .milliseconds(30))
            #expect(stream.calls == ["stop"])
            #expect(w.capture.fps == 2 && w.capture.wanted)
        }
    }

    @Test("CAPTURE-19 Nothing streams at 100%")
    func capture19() async throws {
        try await withCapture { lab in
            // Parked windows with slivers showing at the screen's right edge (the view ends at x = 1512).
            let sliver = window(1, CGRect(x: 1480, y: 100, width: 900, height: 600), parked: true)
            let streamed = window(2, CGRect(x: 1490, y: 750, width: 900, height: 600), parked: true)
            let c = lab.canvas([sliver, streamed])
            let stream = lab.run(streamed, size: c.livePictureSize(for: streamed), fps: 2)
            c.lingerUntil = 0   // the 5s after leaving the canvas are over
            lab.stream(c)
            try await Task.sleep(for: .milliseconds(30))
            #expect(c.captureLoad == 0)
            #expect(stream.calls == ["stop"])
            #expect(c.windows.allSatisfy { !$0.capture.isRunning && !$0.capture.wanted })
            // Their slivers get pictures instead (one each, unless a stream stopping now just drew it).
            #expect(Set(c.snapshotQueue) == [1, 2])
            #expect(sliver.pictureStale && !streamed.pictureStale)
        }
    }

    @Test("CAPTURE-20 Streaming windows hold fewer picture buffers")
    func capture20() {
        let config = WindowCapture.configuration(pixelSize: CGSize(width: 1600, height: 1000), fps: 30)
        #expect(config.queueDepth == 4)
        let cap = WindowCapture()
        var shown = 0
        cap.onFrame = { _ in shown += 1 }
        for _ in 0..<3 { cap.deliver(picture(), snapshot: false) }
        #expect(cap.recentSamples.count == 2)
        #expect(shown == 3)
        // Paused, only the picture on screen is kept.
        cap.pause()
        #expect(cap.recentSamples.count == 1)
    }

    // MARK: replayd

    @Test("CAPTURE-22 A snapshot replayd never answers gives up once after 5 s, never twice")
    func capture22() async throws {
        try await withCapture(stuck: false) { lab in
            lab.shots.holding = true
            #expect(WindowCapture.replaydTimeout == 5)
            let answered = WindowCapture(), unanswered = WindowCapture()
            var results: [String: [Bool]] = [:]
            answered.snapshot(window: Fake.scWindow(id: 1, frame: CGRect(x: 0, y: 0, width: 400, height: 300)),
                              pixelSize: CGSize(width: 400, height: 300)) { results["answered", default: []].append($0) }
            unanswered.snapshot(window: Fake.scWindow(id: 2, frame: CGRect(x: 0, y: 0, width: 400, height: 300)),
                                pixelSize: CGSize(width: 400, height: 300)) { results["unanswered", default: []].append($0) }
            try await Task.sleep(for: .milliseconds(50))
            #expect(Set(lab.shots.asked) == [1, 2])
            lab.shots.answer(1)    // replayd answers (no picture)
            try await Task.sleep(for: .milliseconds(50))
            #expect(results["answered"] == [false])
            #expect(results["unanswered"] == nil)
            try await Task.sleep(for: .seconds(5.4))
            #expect(results["answered"] == [false])
            #expect(results["unanswered"] == [false])
            #expect(WindowCapture.overdue == 1)
            // The answer turns up late: nothing more.
            lab.shots.answer(2, with: picture())
            try await Task.sleep(for: .milliseconds(50))
            #expect(results["unanswered"] == [false])
            #expect(WindowCapture.overdue == 0)
        }
    }

    @Test("CAPTURE-31 No new request once three are overdue; asked again when one is answered")
    func capture31a() async throws {
        try await withCapture(stuck: false) { lab in
            WindowCapture.overdue = 2
            #expect(WindowCapture.canAsk)
            WindowCapture.overdue = 3
            #expect(!WindowCapture.canAsk)
            WindowCapture.overdueAnswered()
            #expect(WindowCapture.overdue == 2)
            #expect(WindowCapture.canAsk)
            #expect(lab.askedAgain == 1)
        }
    }

    @Test("CAPTURE-31 Three snapshots replayd doesn't answer hold everything back until one is answered")
    func capture31b() async throws {
        try await withCapture(stuck: false) { lab in
            lab.shots.holding = true
            let ws = (0..<4).map { window(CGWindowID(1 + $0), CGRect(x: CGFloat($0) * 700, y: 100, width: 600, height: 400), first: true) }
            let c = lab.canvas(ws, zoomedOut: true, camera: Camera(origin: .zero, scale: 0.5))
            c.pumpSnapshots()
            try await Task.sleep(for: .milliseconds(50))
            // Three at a time.
            #expect(lab.shots.asked.count == 3)
            #expect(c.snapshotsInFlight == 3)
            try await Task.sleep(for: .seconds(5.4))
            // Given up on: their places are free again (CAPTURE-22), but replayd still holds three.
            #expect(c.snapshotsInFlight == 0)
            #expect(WindowCapture.overdue == 3)
            #expect(!WindowCapture.canAsk)
            for w in ws { w.lastSnapshotAt -= 60 }
            c.pumpSnapshots()
            let parked = WindowCapture()
            parked.start(window: ws[0].scWindow, pixelSize: CGSize(width: 600, height: 400), fps: 30)
            try await Task.sleep(for: .milliseconds(50))
            #expect(lab.shots.asked.count == 3)
            #expect(!parked.isRunning && parked.wanted)
            #expect(lab.askedAgain == 0)
            // One overdue answer arrives: what was held back is asked for again.
            lab.shots.answer(lab.shots.asked[0])
            try await Task.sleep(for: .milliseconds(50))
            #expect(WindowCapture.overdue == 2)
            #expect(WindowCapture.canAsk)
            #expect(lab.askedAgain == 1)
            parked.stop()
        }
    }

    @Test("CAPTURE-32 Captures wait while window scans get no answer, and start when one does")
    func capture32() async throws {
        try await withCapture(stuck: false) { lab in
            let w = window(1, CGRect(x: 100, y: 100, width: 600, height: 400), first: true)
            let c = lab.canvas([w], zoomedOut: true, camera: Camera(origin: .zero, scale: 0.5))
            WindowCapture.replaydStuck = true
            #expect(!WindowCapture.canAsk)
            c.pumpSnapshots()
            let cap = WindowCapture()
            cap.start(window: w.scWindow, pixelSize: CGSize(width: 600, height: 400), fps: 30)
            try await Task.sleep(for: .milliseconds(30))
            #expect(lab.shots.asked.isEmpty)
            #expect(!cap.isRunning && cap.wanted)
            #expect(lab.askedAgain == 0)
            // A scan is answered.
            WindowCapture.replaydStuck = false
            #expect(WindowCapture.canAsk)
            #expect(lab.askedAgain == 1)
            c.pumpSnapshots()
            try await Task.sleep(for: .milliseconds(30))
            #expect(lab.shots.asked == [1])
            // Already able to ask: no second call.
            WindowCapture.replaydStuck = false
            #expect(lab.askedAgain == 1)
            cap.stop()
        }
    }

    @Test("CAPTURE-33 Window capture never asks for audio")
    func capture33() {
        for fps in [1, 2, 30] {
            let config = WindowCapture.configuration(pixelSize: CGSize(width: 800, height: 500), fps: fps)
            #expect(!config.capturesAudio)
            #expect(!config.captureMicrophone)
        }
        let desktop = Wallpaper.configuration(size: CGSize(width: 1512, height: 982), scale: 2)
        #expect(!desktop.capturesAudio)
        #expect(!desktop.captureMicrophone)
    }

    @Test("CAPTURE-37 A sliver gets one picture as it comes into view")
    func capture37() async throws {
        try await withCapture(stuck: false) { lab in
            let sliver = window(1, CGRect(x: 1450, y: 300, width: 800, height: 600), parked: true)
            let c = lab.canvas([sliver])
            sliver.pictureWidth = Int(c.livePictureSize(for: sliver).width)
            lab.stream(c)
            try await Task.sleep(for: .milliseconds(50))
            #expect(lab.shots.asked == [1])
            #expect(!sliver.pictureStale)
            // It stays in view: no more pictures, however long you wait.
            for _ in 0..<3 {
                sliver.lastSnapshotAt -= 60
                lab.stream(c)
                c.pumpSnapshots()
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(lab.shots.asked == [1])
            #expect(!sliver.capture.wanted)
            // Out of view and back: one more.
            c.camera = Camera(origin: CGPoint(x: -300, y: 0), scale: 1)
            lab.stream(c)
            #expect(c.snapshotQueue.isEmpty)
            c.camera = Camera()
            lab.stream(c)
            try await Task.sleep(for: .milliseconds(50))
            #expect(lab.shots.asked == [1, 1])
            // Zoomed out, it's live again.
            WindowCapture.replaydStuck = true
            c.isActive = true
            lab.stream(c)
            #expect(sliver.capture.wanted)
        }
    }

    // MARK: Logic of the manual cases

    @Test("CAPTURE-01 Zoomed out, windows are live pictures and never move (logic)")
    func capture01() async throws {
        try await withCapture { lab in
            var ws: [ManagedWindow] = []
            for i in 0..<30 {
                let x = CGFloat(i % 6) * 900, y = CGFloat(i / 6) * 700
                ws.append(window(CGWindowID(1 + i), CGRect(x: x, y: y, width: 800, height: 600)))
            }
            let c = lab.canvas(ws, zoomedOut: true, camera: Camera(origin: .zero, scale: 0.25))
            lab.stream(c)
            #expect(c.captureLoad == 16)
            #expect(c.snapshotQueue.count == 14)
            // (Ten streams start per pass, the rest on the next.)
            let starting = c.windows.filter(\.capture.wanted).map(\.id)
            #expect(starting.count == CanvasController.streamStartsPerPass)
            #expect(Set(c.snapshotQueue).isDisjoint(with: starting))
        }
    }

    @Test("CAPTURE-04 At 100%, windows on screen carry no purple capture badge (logic)")
    func capture04() async throws {
        try await withCapture { lab in
            let a = window(1, CGRect(x: 100, y: 100, width: 600, height: 400))
            let b = window(2, CGRect(x: 800, y: 100, width: 600, height: 400))
            let c = lab.canvas([a, b])
            #expect(c.wantsCapture(a, in: c.captureRegion) == (false, false))
            lab.stream(c)
            #expect(c.captureLoad == 0)
            #expect(!a.capture.wanted && !b.capture.wanted)
            #expect(c.snapshotQueue.isEmpty)
        }
    }

    @Test("CAPTURE-21 Zoomed out, a scan that's answered starts the streams replayd dropped (logic)")
    func capture21() async throws {
        // replayd held as stuck: a start is asked for (the capture wants it) but nothing starts.
        try await withCapture { lab in
            let ws = [window(1, CGRect(x: 0, y: 0, width: 800, height: 600)), window(2, CGRect(x: 900, y: 0, width: 800, height: 600))]
            let c = lab.canvas(ws, zoomedOut: true)
            c.camera = c.overviewCamera()
            c.firstSync = false
            #expect(ws.allSatisfy { !$0.capture.wanted && !$0.capture.isRunning })
            let scan = { c.apply(ws.map { Fake.scWindow(id: $0.id, frame: $0.canvasFrame) }, ax: CanvasController.AXSnapshot()) }
            // An ordinary scan, no stream having stopped: streaming isn't worked out again (in a
            // VM, retrying starts that timed out on every scan stalled the window server).
            scan()
            #expect(ws.allSatisfy { !$0.capture.wanted })
            // replayd restarted and dropped the streams (each stream's onStop); the scan that
            // follows comes back, but the camera is still moving: the capture update at the end of
            // its animation sees to it.
            c.capturesStopped = true
            c.animation = CanvasController.CameraAnimation(from: c.camera, to: c.camera, start: CACurrentMediaTime(), duration: 0.3)
            scan()
            #expect(ws.allSatisfy { !$0.capture.wanted })
            #expect(c.capturesStopped)
            c.animation = nil
            // At rest.
            scan()
            lab.stopTimer(c)
            #expect(ws.allSatisfy { $0.capture.wanted }, "every window in view should be asked to stream again, the camera unmoved")
            #expect(!c.capturesStopped)
            c.cancelAnimation()
            c.isActive = false
        }
    }

    @Test("CAPTURE-07 Going straight back to the canvas reuses its pictures (logic)")
    func capture07() async throws {
        try await withCapture { lab in
            let parked = window(1, CGRect(x: 1400, y: 100, width: 800, height: 600), parked: true)
            let away = window(2, CGRect(x: 9000, y: 100, width: 800, height: 600), parked: true)
            let c = lab.canvas([parked, away])
            let near = lab.run(parked, size: c.livePictureSize(for: parked), fps: 2)
            let far = lab.run(away, size: c.livePictureSize(for: away), fps: 2)
            // Just left the canvas: streams linger for 5s.
            c.lingerUntil = CACurrentMediaTime() + 5
            lab.stream(c, reconfigure: false)
            try await Task.sleep(for: .milliseconds(30))
            #expect(near.calls.isEmpty && far.calls.isEmpty)
            #expect(parked.capture.isRunning && away.capture.isRunning)
            // Then they stop.
            c.lingerUntil = CACurrentMediaTime() - 0.1
            lab.stream(c, reconfigure: false)
            try await Task.sleep(for: .milliseconds(30))
            #expect(near.calls == ["stop"] && far.calls == ["stop"])
            #expect(c.windows.allSatisfy { !$0.capture.isRunning })
        }
    }

    @Test("CAPTURE-10 A new window's first picture appears straight away (logic)")
    func capture10() async throws {
        try await withCapture { lab in
            let new = window(1, CGRect(x: 100, y: 100, width: 600, height: 400), first: true)
            let c = lab.canvas([new], zoomedOut: true, camera: Camera(origin: .zero, scale: 0.5))
            #expect(c.wantsCapture(new, in: c.captureRegion) == (true, true))
            lab.stream(c)
            // Not a stream, and not waiting its turn in the snapshot queue.
            #expect(!new.capture.wanted)
            #expect(c.snapshotQueue.isEmpty)
            WindowCapture.replaydStuck = false
            c.pumpSnapshots()
            try await Task.sleep(for: .milliseconds(30))
            #expect(lab.shots.asked == [1])
            #expect(lab.shots.sizes == [c.pixelSize(for: new)])
        }
    }

    @Test("CAPTURE-12 Glides only stream what's on screen at the start and the end (logic)")
    func capture12() async throws {
        try await withCapture { lab in
            let start = window(1, CGRect(x: 100, y: 100, width: 600, height: 400))
            let passed = window(2, CGRect(x: 3000, y: 100, width: 600, height: 400))
            let end = window(3, CGRect(x: 6100, y: 100, width: 600, height: 400))
            let c = lab.canvas([start, passed, end], zoomedOut: true)
            let screen = CGRect(origin: .zero, size: c.viewSize)
            let to = Camera(origin: CGPoint(x: 6000, y: 0), scale: 1)
            c.gliding = true
            c.glideTarget = end
            c.animation = CanvasController.CameraAnimation(from: c.camera, to: to, start: CACurrentMediaTime(), duration: 0.3)
            c.pathRegion = c.camera.toCanvas(screen).union(to.toCanvas(screen))
            #expect(c.wantsCapture(passed, in: c.captureRegion).start)
            lab.stream(c)
            #expect(start.capture.wanted && end.capture.wanted)
            #expect(!passed.capture.wanted)
            #expect(c.snapshotQueue.isEmpty)
        }
    }

    @Test("CAPTURE-23 No purple badge on a window after a hop (logic)")
    func capture23() async throws {
        try await withCapture { lab in
            // Nothing streaming: straight away.
            var now = false
            WindowCapture().pause { now = true }
            #expect(now)
            // Streams of the windows landing on screen stop first; the hand-back waits for them.
            let a = window(1, CGRect(x: 100, y: 100, width: 600, height: 400))
            let b = window(2, CGRect(x: 800, y: 100, width: 600, height: 400))
            let parked = window(3, CGRect(x: 3000, y: 100, width: 600, height: 400), parked: true)
            let c = lab.canvas([a, b, parked])
            let sa = lab.run(a), sb = lab.run(b), sp = lab.run(parked)
            var done = 0
            let t0 = CACurrentMediaTime()
            var took: CFTimeInterval = 0
            c.stopStreamsOnScreen { done += 1; took = CACurrentMediaTime() - t0 }
            try await Task.sleep(for: .milliseconds(150))
            #expect(sa.calls == ["stop"] && sb.calls == ["stop"])
            #expect(sp.calls.isEmpty)
            #expect(done == 1)
            // Once they'd stopped (and 50ms for the badges to go), not at the quarter-second cap.
            #expect(took >= 0.05 && took < 0.25)
            // A stream that never says it stopped: never longer than a quarter of a second.
            let stuck = window(4, CGRect(x: 100, y: 600, width: 600, height: 300))
            c.windows.append(stuck)
            lab.run(stuck, FakeStream.make(answersStop: false))
            done = 0
            let t1 = CACurrentMediaTime()
            c.stopStreamsOnScreen { done += 1; took = CACurrentMediaTime() - t1 }
            try await Task.sleep(for: .milliseconds(600))
            #expect(done == 1)
            #expect(took >= 0.24 && took < 0.5)
        }
    }

    @Test("CAPTURE-24 No purple badge after zooming back in from the canvas (logic)")
    func capture24() async throws {
        try await withCapture { lab in
            let landing = window(1, CGRect(x: 100, y: 100, width: 600, height: 400))
            let elsewhere = window(2, CGRect(x: 3000, y: 2000, width: 600, height: 400))
            let c = lab.canvas([landing, elsewhere], zoomedOut: true, camera: Camera(origin: .zero, scale: 0.25))
            let sl = lab.run(landing), se = lab.run(elsewhere)
            // Zooming back in to the 100% view at the origin.
            c.animation = CanvasController.CameraAnimation(from: c.camera, to: Camera(), start: CACurrentMediaTime(),
                                                           duration: 0.18, handsBack: true)
            #expect(c.wantsCapture(landing, in: c.captureRegion) == (false, false))
            #expect(c.wantsCapture(elsewhere, in: c.captureRegion).start)
            lab.stream(c, reconfigure: false)
            try await Task.sleep(for: .milliseconds(30))
            // Stopped, not restarted.
            #expect(sl.calls == ["stop"])
            #expect(!landing.capture.isRunning && !landing.capture.wanted)
            #expect(se.calls.isEmpty && elsewhere.capture.isRunning)
        }
    }

    @Test("CAPTURE-26 streamBudget lowers the number of live window streams (logic)")
    func capture26() {
        #expect(CanvasController.streamBudget(setting: 4) == 4)
        #expect(CanvasController.streamBudget(setting: 0) == 16)
        #expect(CanvasController.streamBudget(setting: 50) == 16)
    }

    @Test("CAPTURE-29 Window scans back off while macOS's capture service is stuck (logic)")
    func capture29() {
        let waits = (0...7).map { CanvasController.scanWait(after: $0) }
        #expect(waits == [10, 20, 40, 80, 160, 320, 320, 320])
    }

    @Test("CAPTURE-34 Refused window scans back off (logic)")
    func capture34() {
        // A refusal waits as an unanswered scan does: 10 s, doubling to about five minutes.
        var unanswered = 0
        var waits: [TimeInterval] = []
        for _ in 0..<7 {
            waits.append(CanvasController.scanWait(after: unanswered))
            unanswered += 1
        }
        #expect(waits == [10, 20, 40, 80, 160, 320, 320])
        // Once a scan succeeds the count is back to 0, and so is the wait.
        #expect(CanvasController.scanWait(after: 0) == 10)
    }

    @Test("CAPTURE-36 Protected video doesn't blink while you're at 100% (logic)")
    func capture36() async throws {
        try await withCapture(stuck: false) { lab in
            // Settled at 100%: windows on screen, slivers that have their pictures, nothing new.
            let onScreen = window(1, CGRect(x: 100, y: 100, width: 800, height: 600))
            let sliver = window(2, CGRect(x: 1450, y: 100, width: 800, height: 600), parked: true)
            let c = lab.canvas([onScreen, sliver])
            sliver.pictureWidth = Int(c.livePictureSize(for: sliver).width)
            c.snapshotQueue = [2]
            for _ in 0..<5 {
                for w in c.windows { w.lastSnapshotAt -= 60 }
                lab.stream(c)
                c.pumpSnapshots()
            }
            try await Task.sleep(for: .milliseconds(30))
            #expect(lab.shots.asked.isEmpty)
            #expect(c.windows.allSatisfy { !$0.capture.wanted })
        }
    }
}

// MARK: - Helpers

/// Lets the capture queues and the main queue catch up (the picture call runs on a capture's own queue).
private func settle() async throws {
    try await Task.sleep(for: .milliseconds(40))
}

/// A window on the test canvas. `first`: still waiting for its first picture (new windows are).
private func window(_ id: CGWindowID, _ frame: CGRect, parked: Bool = false, first: Bool = false) -> ManagedWindow {
    let w = Fake.window(id: id, canvas: frame)
    w.parked = parked
    w.needsFirstFrame = first
    return w
}

/// A small picture, as ScreenCaptureKit delivers one: an IOSurface-backed BGRA buffer.
private func picture(width: Int = 64, height: Int = 48) -> CMSampleBuffer {
    var buffer: CVPixelBuffer?
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer)
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer!, formatDescriptionOut: &format)
    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer!, formatDescription: format!,
                                             sampleTiming: &timing, sampleBufferOut: &sample)
    return sample!
}

/// Stands in for ScreenCaptureKit's picture call (WindowCapture.screenshot): records each request
/// and answers it at once with a picture, or, while `holding`, when the test says.
private final class Shots: @unchecked Sendable {
    private struct Request {
        let id: CGWindowID
        let size: CGSize
        var done: ((CMSampleBuffer?, Error?) -> Void)?
    }
    private let lock = NSLock()
    private var requests: [Request] = []
    var holding = false
    private let ready = picture()

    func take(_ window: SCWindow, _ config: SCStreamConfiguration, _ done: @escaping (CMSampleBuffer?, Error?) -> Void) {
        lock.lock()
        let hold = holding
        requests.append(Request(id: window.windowID, size: CGSize(width: config.width, height: config.height), done: hold ? done : nil))
        lock.unlock()
        if !hold { done(ready, nil) }
    }

    var asked: [CGWindowID] { lock.withLock { requests.map(\.id) } }
    var sizes: [CGSize] { lock.withLock { requests.map(\.size) } }

    /// Answers the first waiting request for window `id`.
    func answer(_ id: CGWindowID, with sample: CMSampleBuffer? = nil) {
        lock.lock()
        let i = requests.firstIndex { $0.id == id && $0.done != nil }
        let done = i.flatMap { requests[$0].done }
        if let i { requests[i].done = nil }
        lock.unlock()
        done?(sample, nil)
    }

    func answerAll() {
        lock.lock()
        let waiting = requests.compactMap(\.done)
        for i in requests.indices { requests[i].done = nil }
        lock.unlock()
        waiting.forEach { $0(nil, nil) }
    }
}

/// Stands in for a running SCStream. Made without SCStream's initialiser, so nothing is set up in
/// replayd; its calls are recorded, never made. Kept for good: SCStream's own teardown is for
/// streams it set up.
private final class FakeStream: SCStream {
    private static let lock = NSLock()
    private static var log: [ObjectIdentifier: [String]] = [:]
    private static var silent = Set<ObjectIdentifier>()
    private static var kept: [FakeStream] = []

    /// `answersStop`: false for one that never says it has stopped.
    static func make(answersStop: Bool = true) -> FakeStream {
        let s = class_createInstance(FakeStream.self, 0) as! FakeStream
        lock.withLock {
            kept.append(s)
            if !answersStop { silent.insert(ObjectIdentifier(s)) }
        }
        return s
    }

    var calls: [String] { Self.lock.withLock { Self.log[ObjectIdentifier(self)] ?? [] } }

    /// Records the call; whether to answer it.
    private func record(_ call: String) -> Bool {
        Self.lock.withLock {
            Self.log[ObjectIdentifier(self), default: []].append(call)
            return !Self.silent.contains(ObjectIdentifier(self))
        }
    }

    override func startCapture(completionHandler: ((Error?) -> Void)?) {
        if record("start") { completionHandler?(nil) }
    }

    override func stopCapture(completionHandler: ((Error?) -> Void)?) {
        if record("stop") { completionHandler?(nil) }
    }

    override func updateConfiguration(_ streamConfig: SCStreamConfiguration, completionHandler: ((Error?) -> Void)?) {
        if record("updateConfiguration") { completionHandler?(nil) }
    }
}

/// What a capture test has made, to tidy away afterwards.
private final class Lab {
    let shots = Shots()
    var askedAgain = 0
    private var canvases: [CanvasController] = []

    func canvas(_ windows: [ManagedWindow], zoomedOut: Bool = false, camera: Camera = Camera()) -> CanvasController {
        let c = TestCanvas.make(windows: windows)
        c.isActive = zoomedOut
        c.camera = camera
        canvases.append(c)
        return c
    }

    /// updateStreaming, without leaving its snapshot timer running (tests pump by hand).
    func stream(_ c: CanvasController, reconfigure: Bool = true) {
        c.updateStreaming(reconfigure: reconfigure)
        stopTimer(c)
    }

    func stopTimer(_ c: CanvasController) {
        c.snapshotTimer?.invalidate()
        c.snapshotTimer = nil
    }

    /// Makes `cap` a running stream (a FakeStream), configured at this size and rate.
    @discardableResult
    func run(_ cap: WindowCapture, _ stream: FakeStream = .make(), size: CGSize = CGSize(width: 800, height: 500), fps: Int = 2,
             window: SCWindow? = nil) -> FakeStream {
        cap.stream = stream
        cap.window = window ?? Fake.scWindow(id: 999, frame: CGRect(origin: .zero, size: size))
        cap.wanted = true
        cap.pixelSize = size
        cap.fps = fps
        cap.configured = (size, fps)
        return stream
    }

    @discardableResult
    func run(_ w: ManagedWindow, _ stream: FakeStream = .make(), size: CGSize? = nil, fps: Int = 2) -> FakeStream {
        run(w.capture, stream, size: size ?? w.canvasFrame.size, fps: fps, window: w.scWindow)
    }

    /// Nothing left that could ask for a capture later: timers, pending passes, windows.
    func quiet() {
        for c in canvases {
            stopTimer(c)
            c.captureSettleWork?.cancel()
            c.lingerWork?.cancel()
            c.streamingWork?.cancel()
            c.animation = nil
            for w in c.windows { w.capture.stop() }
            c.windows = []
        }
    }
}

/// Runs a capture test with ScreenCaptureKit's picture call replaced (Lab.shots), replayd's
/// bookkeeping fresh, and, when `stuck`, replayd "not answering", so no stream can start. Puts
/// everything back afterwards.
@MainActor
private func withCapture(stuck: Bool = true, _ body: (Lab) async throws -> Void) async throws {
    let saved = (askAgain: WindowCapture.askAgain, stuck: WindowCapture.replaydStuck,
                 overdue: WindowCapture.overdue, screenshot: WindowCapture.screenshot)
    let lab = Lab()
    WindowCapture.askAgain = nil
    WindowCapture.screenshot = { [shots = lab.shots] window, config, done in shots.take(window, config, done) }
    WindowCapture.replaydStuck = stuck
    WindowCapture.overdue = 0
    WindowCapture.askAgain = { [weak lab] in lab?.askedAgain += 1 }
    var failure: Error?
    do { try await body(lab) } catch { failure = error }
    lab.quiet()
    lab.shots.answerAll()
    try? await Task.sleep(for: .milliseconds(50))
    WindowCapture.askAgain = nil
    WindowCapture.replaydStuck = saved.stuck
    WindowCapture.overdue = saved.overdue
    WindowCapture.screenshot = saved.screenshot
    WindowCapture.askAgain = saved.askAgain
    if let failure { throw failure }
}
