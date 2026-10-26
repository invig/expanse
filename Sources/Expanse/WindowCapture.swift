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
    /// Whether the stream should be running; a pause during start-up stops it once it's up.
    private var wanted = false

    var isRunning: Bool { stream != nil || starting }

    func start(window: SCWindow, pixelSize: CGSize, fps: Int) {
        wanted = true
        guard !isRunning else { return }
        starting = true
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
        queue.async { [weak self] in
            let filter = SCContentFilter(desktopIndependentWindow: window)
            SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config) { sample, error in
                let ok = sample?.imageBuffer != nil
                if let self, let sample, ok { FramePump.shared.post(sample, for: self, snapshot: true) }
                if let error { logger.info("snapshot of \(window.windowID) failed: \(error.localizedDescription, privacy: .public)") }
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    /// Capture at a new size. ScreenCaptureKit can reconfigure a running stream, but a stream
    /// asked to change size sends nothing until the change is through, which takes seconds when
    /// several change at once; starting a new stream is quicker, and the layer keeps the last
    /// picture meanwhile. Frame rates are set when a stream starts: a change takes seconds to
    /// apply, by which time it rarely matters.
    func update(pixelSize: CGSize, fps: Int) {
        guard pixelSize != self.pixelSize else { return }
        self.pixelSize = pixelSize
        self.fps = fps
        restartIfResized()
    }

    private func restartIfResized() {
        guard stream != nil, wanted, pixelSize != configured.size, let window else { return }
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
        c.queueDepth = 5
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
        // A stream recycles its buffers, so hold a few: one still on screen mustn't be reused.
        // A snapshot's buffer is its own; the last one is all that's needed.
        if snapshot { recentSamples = [sample] } else { recentSamples.append(sample) }
        if recentSamples.count > 3 { recentSamples.removeFirst() }
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
