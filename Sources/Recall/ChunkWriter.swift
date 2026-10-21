import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import VideoToolbox

// MARK: - Encoder Settings

struct EncoderSettings: Equatable {
    let width: Int
    let height: Int
    let codec: AVVideoCodecType
    let bitRate: Int
    let frameRate: Int32
    let keyFrameIntervalSeconds: TimeInterval

    static func make(width: Int, height: Int, preferHEVC: Bool, config: ConfigManager = .shared) -> EncoderSettings {
        let useHEVC = preferHEVC && EncoderSupport.isHEVCHardwareEncoderAvailable
        // Screen content does not need bitrate proportional to pixel count, so scale sub-linearly.
        var bitRate = config.referenceBitRate * pow(Double(width * height) / config.referencePixelCount, 0.75)
        if useHEVC {
            bitRate *= config.hevcBitRateFactor
        }
        bitRate = min(config.maxBitRate, max(config.minBitRate, bitRate))

        return EncoderSettings(
            width: width,
            height: height,
            codec: useHEVC ? .hevc : .h264,
            bitRate: Int(bitRate),
            frameRate: config.targetFrameRate,
            keyFrameIntervalSeconds: config.keyFrameIntervalSeconds
        )
    }

    var outputSettings: [String: Any] {
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: bitRate,
            AVVideoMaxKeyFrameIntervalKey: Int(Double(frameRate) * keyFrameIntervalSeconds),
            // A frame-count interval stretches when the screen is idle; capping by duration keeps trims precise.
            AVVideoMaxKeyFrameIntervalDurationKey: keyFrameIntervalSeconds,
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoAllowFrameReorderingKey: false
        ]
        if codec == .h264 {
            compressionProperties[AVVideoProfileLevelKey] = AVVideoProfileLevelH264MainAutoLevel
        }

        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]
    }
}

enum EncoderSupport {
    /// Software HEVC is too expensive for continuous capture, so HEVC is only offered with a hardware encoder.
    static let isHEVCHardwareEncoderAvailable: Bool = {
        var encoderList: CFArray?
        guard VTCopyVideoEncoderList(nil, &encoderList) == noErr,
              let encoders = encoderList as? [[String: Any]] else { return false }
        return encoders.contains { encoder in
            (encoder[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value == kCMVideoCodecType_HEVC
                && (encoder[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool) == true
        }
    }()
}

// MARK: - Chunk Writer

struct ChunkWriterError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Writes one recording chunk as a fragmented MP4 to `<name>.mp4.partial`, renamed to
/// `<name>.mp4` once finished. A crash therefore loses at most one fragment, and the
/// chunk directory never shows a half-written file as finished.
/// Not thread-safe: confine each writer to one queue.
final class ChunkWriter {
    struct FinishedChunk {
        let url: URL
        let startDate: Date
        let duration: TimeInterval
    }

    let finalURL: URL
    let partialURL: URL
    let startDate: Date
    let startTime: CMTime
    let settings: EncoderSettings
    private(set) var framesWritten = 0
    private(set) var droppedFrames = 0

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let fileSystem: FileSystemProvider
    private var lastFrame: (buffer: CVPixelBuffer, time: CMTime)?
    private var lastAppendedTime: CMTime?

    init(directory: URL, startTime: CMTime, startDate: Date, settings: EncoderSettings, fileSystem: FileSystemProvider) throws {
        self.finalURL = directory.appendingPathComponent(ChunkNaming.fileName(for: startDate))
        self.partialURL = ChunkNaming.partialURL(for: finalURL)
        self.startDate = startDate
        self.startTime = startTime
        self.settings = settings
        self.fileSystem = fileSystem

        try? fileSystem.removeItem(at: partialURL)
        writer = try AVAssetWriter(outputURL: partialURL, fileType: .mp4)
        writer.movieFragmentInterval = CMTime(seconds: ConfigManager.shared.movieFragmentIntervalSeconds, preferredTimescale: ConfigManager.shared.timescale)

        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings.outputSettings)
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)

        guard writer.canAdd(input) else {
            throw ChunkWriterError(message: "Cannot add a video input for \(settings.width)x\(settings.height)")
        }
        writer.add(input)

        guard writer.startWriting() else {
            try? fileSystem.removeItem(at: partialURL)
            throw writer.error ?? ChunkWriterError(message: "Could not start writing \(partialURL.lastPathComponent)")
        }
        writer.startSession(atSourceTime: startTime)
    }

    var hasFailed: Bool {
        return writer.status == .failed
    }

    var failureDescription: String {
        return writer.error?.localizedDescription ?? "unknown writer error"
    }

    func elapsed(at time: CMTime) -> TimeInterval {
        return CMTimeGetSeconds(CMTimeSubtract(time, startTime))
    }

    func accepts(_ pixelBuffer: CVPixelBuffer) -> Bool {
        return CVPixelBufferGetWidth(pixelBuffer) == settings.width && CVPixelBufferGetHeight(pixelBuffer) == settings.height
    }

    /// How late a frame may be (captured just before this chunk started or before the previous
    /// frame, delivered after it) and still be kept. Such frames are nudged forward instead of
    /// dropped; dropping one right before the screen goes idle would leave a stale image on screen.
    static let lateFrameTolerance = CMTime(value: 1, timescale: 4)

    @discardableResult
    func append(_ pixelBuffer: CVPixelBuffer, at time: CMTime) -> Bool {
        guard writer.status == .writing else { return false }
        // Presentation times must strictly increase.
        let earliest = lastAppendedTime.map { CMTimeAdd($0, CMTime(value: 1, timescale: ConfigManager.shared.timescale)) } ?? startTime
        var presentationTime = time
        if CMTimeCompare(time, earliest) < 0 {
            guard CMTimeCompare(CMTimeSubtract(earliest, time), ChunkWriter.lateFrameTolerance) <= 0 else { return false }
            presentationTime = earliest
        }
        guard input.isReadyForMoreMediaData else {
            droppedFrames += 1
            return false
        }
        guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            return false
        }
        framesWritten += 1
        lastFrame = (pixelBuffer, presentationTime)
        lastAppendedTime = presentationTime
        return true
    }

    /// Ends the chunk at `endTime`, holding the last frame until then so the file covers the
    /// full wall-clock span even while the screen was idle. Calls `completion` on an arbitrary
    /// thread with nil when there was nothing to keep.
    func finish(at endTime: CMTime, completion: @escaping (Result<FinishedChunk?, Error>) -> Void) {
        guard writer.status == .writing, let last = lastFrame, let lastTime = lastAppendedTime else {
            cancel()
            completion(writer.status == .failed ? .failure(writer.error ?? ChunkWriterError(message: failureDescription)) : .success(nil))
            return
        }

        let frameDuration = CMTime(value: 1, timescale: settings.frameRate)
        let holdTime = CMTimeSubtract(endTime, frameDuration)
        if CMTimeCompare(holdTime, lastTime) > 0, waitUntilReadyForMoreMediaData(),
           adaptor.append(last.buffer, withPresentationTime: holdTime) {
            lastAppendedTime = holdTime
        }
        let sessionEnd = CMTimeMaximum(endTime, CMTimeAdd(lastAppendedTime ?? lastTime, frameDuration))
        writer.endSession(atSourceTime: sessionEnd)
        input.markAsFinished()
        lastFrame = nil

        let writer = self.writer
        let fileSystem = self.fileSystem
        let partialURL = self.partialURL
        let finalURL = self.finalURL
        let startDate = self.startDate
        let duration = CMTimeGetSeconds(CMTimeSubtract(sessionEnd, startTime))

        writer.finishWriting {
            guard writer.status == .completed else {
                try? fileSystem.removeItem(at: partialURL)
                completion(.failure(writer.error ?? ChunkWriterError(message: "Writing \(finalURL.lastPathComponent) did not complete")))
                return
            }
            do {
                try fileSystem.moveItem(at: partialURL, to: finalURL)
                completion(.success(FinishedChunk(url: finalURL, startDate: startDate, duration: duration)))
            } catch {
                try? fileSystem.removeItem(at: partialURL)
                completion(.failure(error))
            }
        }
    }

    /// The hold frame decides whether the chunk covers its full span, so it is worth a short wait
    /// for the encoder (once per chunk) rather than being dropped like a live frame.
    private func waitUntilReadyForMoreMediaData(timeout: TimeInterval = 0.1) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline {
            usleep(1000)
        }
        return input.isReadyForMoreMediaData
    }

    /// Abandons the chunk and deletes its file.
    func cancel() {
        if writer.status == .writing {
            writer.cancelWriting()
        }
        lastFrame = nil
        try? fileSystem.removeItem(at: partialURL)
    }
}
