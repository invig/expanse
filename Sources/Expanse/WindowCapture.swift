import AppKit
import ScreenCaptureKit
import os

let logger = Logger(subsystem: "com.invignation.expanse", category: "canvas")

/// One ScreenCaptureKit stream per window. Desktop-independent window capture keeps
/// delivering content while the window is covered by the overlay or parked off-screen.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    /// Called on the main thread with the newest frame (see FramePump).
    var onFrame: ((IOSurface) -> Void)?
    /// Called on the main thread when the stream dies (usually: window closed).
    var onStop: (() -> Void)?

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.invignation.expanse.capture", qos: .userInteractive)
    private var recentSamples: [CMSampleBuffer] = []
    /// What the stream should capture at; `configured` is what it was started with.
    private(set) var pixelSize: CGSize = .zero
    private(set) var fps: Int = 0
    private var configured: (size: CGSize, fps: Int) = (.zero, 0)
    private var window: SCWindow?
    private var starting = false
    /// Bumped by each start, so the answer to one that was given up on (see start) is ignored.
    private var startToken = 0
    /// Whether the stream should be running; a pause during start-up stops it once it's up.
    private var wanted = false

    var isRunning: Bool { stream != nil || starting }

    /// How long to wait for replayd, which runs every capture on the Mac. When it's restarted (or
    /// stuck), requests already sent never get an answer, and waiting for one would leave a stream
    /// "starting" for ever, or a snapshot holding one of the few places (see pumpSnapshots).
    static let replaydTimeout: TimeInterval = 5

    func start(window: SCWindow, pixelSize: CGSize, fps: Int) {
        wanted = true
        guard !isRunning else { return }
        starting = true
        startToken += 1
        let token = startToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.replaydTimeout) { [weak self] in
            guard let self, self.starting, self.startToken == token else { return }
            logger.info("stream start for \(window.windowID) timed out")
            self.starting = false
            self.startToken += 1
        }
        self.window = window
        self.pixelSize = pixelSize
        self.fps = fps
        configured = (pixelSize, fps)
        let config = Self.configuration(pixelSize: pixelSize, fps: fps)
        // Setting a stream up takes a millisecond or two; do it on the capture queue, so starting
        // dozens at once (zooming out) doesn't hold up the main thread.
        queue.async { [weak self] in
            guard let self else { return }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
            } catch {
                logger.error("addStreamOutput failed: \(error.localizedDescription)")
                DispatchQueue.main.async { self.starting = false }
                return
            }
            stream.startCapture { [weak self] error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    // Given up on meanwhile: not this capture's stream any more.
                    guard self.startToken == token else {
                        if error == nil { self.queue.async { stream.stopCapture(completionHandler: nil) } }
                        return
                    }
                    self.starting = false
                    if let error {
                        logger.error("startCapture failed for \(window.windowID): \(error.localizedDescription)")
                        self.onStop?()
                    } else {
                        self.stream = stream
                        if !self.wanted { self.pause() } else { self.restartIfResized() }
                    }
                }
            }
        }
    }

    /// One picture, without a stream (ScreenCaptureKit's screenshot call), delivered like a stream
    /// frame. `completion` runs on the main thread either way.
    func snapshot(window: SCWindow, pixelSize: CGSize, completion: @escaping (_ ok: Bool) -> Void) {
        let config = Self.configuration(pixelSize: pixelSize, fps: 1)
        // Once, on the main thread: when replayd answers, or when it's taken too long.
        var finished = false
        let finish = { (ok: Bool) in
            guard !finished else { return }
            finished = true
            completion(ok)
        }
        queue.async { [weak self] in
            let filter = SCContentFilter(desktopIndependentWindow: window)
            SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config) { sample, error in
                let ok = sample?.imageBuffer != nil
                if let self, let sample, ok { FramePump.shared.post(sample, for: self, snapshot: true) }
                if let error { logger.info("snapshot of \(window.windowID) failed: \(error.localizedDescription, privacy: .public)") }
                DispatchQueue.main.async { finish(ok) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.replaydTimeout) {
            if !finished { logger.info("snapshot of \(window.windowID) timed out") }
            finish(false)
        }
    }

    /// Capture at a new size or rate. ScreenCaptureKit can reconfigure a running stream, but a
    /// stream asked to change size sends nothing until the change is through, which takes seconds
    /// when several change at once, and a new frame rate takes seconds to apply; starting a new
    /// stream is quicker, and the layer keeps the last picture meanwhile. So the stream restarts
    /// for a new size, or a rate at least twice or half the old one (a glide's 30 fps back to
    /// 2 at rest, say); smaller rate changes wait for the next restart.
    func update(pixelSize: CGSize, fps: Int) {
        self.pixelSize = pixelSize
        self.fps = fps
        restartIfResized()
    }

    private func restartIfResized() {
        let rateChanged = fps >= configured.fps * 2 || fps * 2 <= configured.fps
        guard stream != nil, wanted, pixelSize != configured.size || rateChanged, let window else { return }
        pause()
        start(window: window, pixelSize: pixelSize, fps: fps)
    }

    /// Stop capturing but keep the callbacks, so start() can pick up again later. The layer
    /// keeps showing the last frame meanwhile.
    func pause() {
        wanted = false
        // Only the picture on the layer is needed now; let ScreenCaptureKit have the rest back.
        if recentSamples.count > 1 { recentSamples.removeFirst(recentSamples.count - 1) }
        guard let stream else { return }
        queue.async { stream.stopCapture(completionHandler: nil) }
        self.stream = nil
    }

    func stop() {
        wanted = false
        if let stream { queue.async { stream.stopCapture(completionHandler: nil) } }
        stream = nil
        onFrame = nil
        onStop = nil
    }

    private static func configuration(pixelSize: CGSize, fps: Int) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.width = max(2, Int(pixelSize.width.rounded()))
        c.height = max(2, Int(pixelSize.height.rounded()))
        c.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        c.pixelFormat = kCVPixelFormatType_32BGRA
        // Each buffer in the pool is a full picture (tens of MB for a big window at full size): a
        // pool of four covers the two held below plus one in flight to the main thread.
        c.queueDepth = 4
        c.showsCursor = false
        c.scalesToFit = true
        c.ignoreShadowsSingleWindow = true
        c.backgroundColor = .clear
        return c
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let rawStatus = info[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              sampleBuffer.imageBuffer != nil
        else { return }

        FramePump.shared.post(sampleBuffer, for: self, snapshot: false)
    }

    /// Main thread: show a frame (see FramePump).
    fileprivate func deliver(_ sample: CMSampleBuffer, snapshot: Bool) {
        guard let pixelBuffer = sample.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }
        // A stream recycles its buffers, so hold the one on screen and the one before (the window
        // server may still be drawing it). A snapshot's buffer is its own; one is enough.
        if snapshot { recentSamples = [sample] } else { recentSamples.append(sample) }
        if recentSamples.count > 2 { recentSamples.removeFirst() }
        onFrame?(surface)
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            logger.info("stream stopped: \(error.localizedDescription)")
            self.stream = nil
            self.onStop?()
        }
    }
}

/// Hands frames from every stream to the main thread in batches: each window's newest frame,
/// all applied in one Core Animation transaction, at most every 8ms. With 50 windows streaming
/// on the canvas that's a few hundred frames a second, and one main-thread hop and transaction
/// each would cost more than drawing them. A frame that arrives while an older one from the
/// same window is still waiting replaces it, so a busy main thread never works through a backlog.
private final class FramePump {
    static let shared = FramePump()
    private let lock = NSLock()
    private var pending: [ObjectIdentifier: (capture: WindowCapture, sample: CMSampleBuffer, snapshot: Bool)] = [:]
    private var scheduled = false

    func post(_ sample: CMSampleBuffer, for capture: WindowCapture, snapshot: Bool) {
        lock.lock()
        pending[ObjectIdentifier(capture)] = (capture, sample, snapshot)
        let schedule = !scheduled
        scheduled = true
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) { self.drain() }
    }

    private func drain() {
        lock.lock()
        let batch = pending
        pending = [:]
        scheduled = false
        lock.unlock()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for entry in batch.values { entry.capture.deliver(entry.sample, snapshot: entry.snapshot) }
        CATransaction.commit()
    }
}
