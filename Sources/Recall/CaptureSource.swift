import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit

struct CaptureConfiguration: Equatable {
    let displayID: CGDirectDisplayID
    let width: Int
    let height: Int
    let frameRate: Int32
}

enum CaptureBackend: String {
    case screenCaptureKit
    case displayStream
}

enum CaptureEvent {
    /// An IOSurface-backed BGRA frame, stamped in host time.
    case frame(CVPixelBuffer, CMTime)
    /// The screen did not change since the last frame.
    case idle
}

struct CaptureError: LocalizedError {
    let message: String
    /// Worth retrying as is (the display or content was briefly unavailable), as opposed to a
    /// sign that this capture backend does not work here.
    var isTransient = false
    var errorDescription: String? { message }
}

/// A source of screen frames.
protocol CaptureSource: AnyObject {
    /// Delivers events and calls `completion` on `queue`. `stopHandler` reports an unexpected
    /// stop (display disconnected, capture revoked) and may be called on any thread.
    func start(
        configuration: CaptureConfiguration,
        queue: DispatchQueue,
        eventHandler: @escaping (CaptureEvent) -> Void,
        stopHandler: @escaping (Error) -> Void,
        completion: @escaping (Error?) -> Void
    )
    func stop(completion: @escaping () -> Void)
}

// MARK: - ScreenCaptureKit

/// Captures the display with ScreenCaptureKit and leaves Recall's own windows (the drag HUD)
/// out of the recording.
final class ScreenCaptureKitSource: NSObject, CaptureSource, SCStreamOutput, SCStreamDelegate {
    // Confined to the queue passed to `start`.
    private var stream: SCStream?
    private var isStopped = true
    private var eventHandler: ((CaptureEvent) -> Void)?
    // Also read on ScreenCaptureKit's delegate queue.
    private let stopHandlerLock = NSLock()
    private var stopHandler: ((Error) -> Void)?

    func start(
        configuration: CaptureConfiguration,
        queue: DispatchQueue,
        eventHandler: @escaping (CaptureEvent) -> Void,
        stopHandler: @escaping (Error) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        isStopped = false
        self.eventHandler = eventHandler
        stopHandlerLock.withCriticalSection { self.stopHandler = stopHandler }

        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
            queue.async {
                // stop() may have run while the content was fetched; creating the stream now would
                // leave it capturing with nobody to stop it.
                guard !self.isStopped else {
                    completion(CaptureError(message: "Capture was stopped before it started.", isTransient: true))
                    return
                }
                guard let content = content else {
                    completion(CaptureError(message: error?.localizedDescription ?? "Shareable content is unavailable.", isTransient: true))
                    return
                }
                guard let display = content.displays.first(where: { $0.displayID == configuration.displayID }) else {
                    completion(CaptureError(message: "Display \(configuration.displayID) is not available.", isTransient: true))
                    return
                }

                let ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                if ownApplications.isEmpty {
                    Log.recorder.notice("Recall is not listed by ScreenCaptureKit; its windows stay in the recording")
                }
                let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])

                let streamConfiguration = SCStreamConfiguration()
                streamConfiguration.width = configuration.width
                streamConfiguration.height = configuration.height
                streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: configuration.frameRate)
                streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
                streamConfiguration.showsCursor = true
                // Room for frames held by the encoder plus the last frame kept for idle chunks.
                streamConfiguration.queueDepth = 6

                let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
                do {
                    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                } catch {
                    completion(error)
                    return
                }
                self.stream = stream
                stream.startCapture { error in
                    queue.async { completion(error) }
                }
            }
        }
    }

    func stop(completion: @escaping () -> Void) {
        isStopped = true
        eventHandler = nil
        stopHandlerLock.withCriticalSection { stopHandler = nil }
        guard let stream = stream else {
            completion()
            return
        }
        self.stream = nil
        stream.stopCapture { _ in
            // Keep the source alive until the stream has stopped.
            _ = self
            completion()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return }

        switch status {
        case .complete:
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            eventHandler?(.frame(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer)))
        case .idle, .blank, .suspended, .started:
            // No new image, but proof that the stream works (the start watchdog counts these).
            eventHandler?(.idle)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let handler = stopHandlerLock.withCriticalSection { stopHandler }
        handler?(error)
    }
}
