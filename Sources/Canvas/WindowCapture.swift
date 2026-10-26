import AppKit
import ScreenCaptureKit
import os

let logger = Logger(subsystem: "com.invignation.canvas", category: "canvas")

/// One ScreenCaptureKit stream per window. Desktop-independent window capture keeps
/// delivering content while the window is covered by the overlay or parked off-screen.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    /// Called on the main thread with each new frame.
    var onFrame: ((IOSurface) -> Void)?
    /// Called on the main thread when the stream dies (usually: window closed).
    var onStop: (() -> Void)?

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.invignation.canvas.capture", qos: .userInteractive)
    private var recentSamples: [CMSampleBuffer] = []
    private(set) var pixelSize: CGSize = .zero
    private(set) var fps: Int = 0
    private var starting = false

    var isRunning: Bool { stream != nil || starting }

    func start(window: SCWindow, pixelSize: CGSize, fps: Int) {
        guard !isRunning else { return }
        starting = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = Self.configuration(pixelSize: pixelSize, fps: fps)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        } catch {
            logger.error("addStreamOutput failed: \(error.localizedDescription)")
            starting = false
            return
        }
        self.pixelSize = pixelSize
        self.fps = fps
        stream.startCapture { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.starting = false
                if let error {
                    logger.error("startCapture failed for \(window.windowID): \(error.localizedDescription)")
                    self.onStop?()
                } else {
                    self.stream = stream
                }
            }
        }
    }

    func update(pixelSize: CGSize, fps: Int) {
        guard let stream, pixelSize != self.pixelSize || fps != self.fps else { return }
        self.pixelSize = pixelSize
        self.fps = fps
        stream.updateConfiguration(Self.configuration(pixelSize: pixelSize, fps: fps)) { error in
            if let error { logger.error("updateConfiguration failed: \(error.localizedDescription)") }
        }
    }

    func stop() {
        stream?.stopCapture(completionHandler: nil)
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
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Hold a few buffers so ScreenCaptureKit doesn't recycle a surface still on screen.
            self.recentSamples.append(sampleBuffer)
            if self.recentSamples.count > 3 { self.recentSamples.removeFirst() }
            self.onFrame?(surface)
        }
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
