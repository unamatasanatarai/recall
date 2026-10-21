import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import IOSurface

/// Fallback capture backend for when ScreenCaptureKit fails to start or delivers no frames.
/// `CGDisplayStream` is deprecated since macOS 14, so it is isolated here and used only on demand.
final class DisplayStreamSource: CaptureSource {
    // Confined to the queue passed to `start`.
    private var stream: CGDisplayStream?
    private var isStopping = false

    static func streamProperties(frameRate: Int32) -> [CFString: Any] {
        return [
            CGDisplayStream.minimumFrameTime: (1.0 / Double(frameRate)) as CFNumber,
            CGDisplayStream.showCursor: true as CFBoolean,
            CGDisplayStream.queueDepth: 5 as CFNumber
        ]
    }

    func start(
        configuration: CaptureConfiguration,
        queue: DispatchQueue,
        eventHandler: @escaping (CaptureEvent) -> Void,
        stopHandler: @escaping (Error) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        isStopping = false
        let stream = CGDisplayStream(
            dispatchQueueDisplay: configuration.displayID,
            outputWidth: configuration.width,
            outputHeight: configuration.height,
            pixelFormat: Int32(kCVPixelFormatType_32BGRA),
            properties: DisplayStreamSource.streamProperties(frameRate: configuration.frameRate) as CFDictionary,
            queue: queue
        ) { [weak self] status, displayTime, frameSurface, _ in
            guard let self = self, !self.isStopping else { return }
            switch status {
            case .frameComplete:
                guard let surface = frameSurface,
                      let pixelBuffer = DisplayStreamSource.retainedPixelBuffer(for: surface) else { return }
                eventHandler(.frame(pixelBuffer, CMClockMakeHostTimeFromSystemUnits(displayTime)))
            case .frameIdle:
                eventHandler(.idle)
            case .stopped:
                stopHandler(CaptureError(message: "The display stream stopped (the display was reconfigured or disconnected)."))
            default:
                break
            }
        }

        guard let stream = stream else {
            completion(CaptureError(message: "Failed to create the display stream."))
            return
        }
        let err = stream.start()
        guard err == .success else {
            completion(CaptureError(message: "Display stream start failed: \(err.rawValue)"))
            return
        }
        self.stream = stream
        completion(nil)
    }

    func stop(completion: @escaping () -> Void) {
        isStopping = true
        stream?.stop()
        stream = nil
        completion()
    }

    /// Wraps `surface` without copying. The stream recycles a surface as soon as the handler
    /// returns unless its use count is raised, and the encoder reads frames after that, so the
    /// count is held until the pixel buffer itself is released.
    static func retainedPixelBuffer(for surface: IOSurface) -> CVPixelBuffer? {
        var unmanagedPixelBuffer: Unmanaged<CVPixelBuffer>?
        guard CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nil, &unmanagedPixelBuffer) == kCVReturnSuccess,
              let pixelBuffer = unmanagedPixelBuffer?.takeRetainedValue() else { return nil }

        IOSurfaceIncrementUseCount(surface)
        CVBufferSetAttachment(pixelBuffer, SurfaceUseToken.attachmentKey, SurfaceUseToken(surface: surface), .shouldNotPropagate)
        return pixelBuffer
    }
}

/// Attached to a pixel buffer; releases the surface's use count when the buffer is deallocated.
private final class SurfaceUseToken {
    static let attachmentKey = "com.recall.surfaceUseToken" as CFString

    private let surface: IOSurface

    init(surface: IOSurface) {
        self.surface = surface
    }

    deinit {
        IOSurfaceDecrementUseCount(surface)
    }
}
