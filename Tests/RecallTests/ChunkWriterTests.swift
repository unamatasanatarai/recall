import Foundation
import AVFoundation
import CoreMedia
import IOSurface

struct ChunkWriterTests {
    private static let start = CMTime(seconds: 500, preferredTimescale: 600)

    private static func makeWriter(in directory: URL) throws -> ChunkWriter {
        let settings = EncoderSettings.make(width: 320, height: 240, preferHEVC: false)
        return try ChunkWriter(directory: directory, startTime: start, startDate: Date(), settings: settings, fileSystem: FileManager.default)
    }

    private static func time(_ seconds: Double) -> CMTime {
        return CMTimeAdd(start, CMTime(seconds: seconds, preferredTimescale: 600))
    }

    private static func appendFrames(_ writer: ChunkWriter, seconds: Double, fps: Double = 10) {
        for index in 0..<Int(seconds * fps) {
            var attempts = 0
            while !writer.append(TestMedia.pixelBuffer(shade: UInt8(index * 10 % 255)), at: time(Double(index) / fps)) && attempts < 200 {
                usleep(2000)
                attempts += 1
            }
        }
    }

    private static func finish(_ writer: ChunkWriter, at seconds: Double) throws -> ChunkWriter.FinishedChunk? {
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<ChunkWriter.FinishedChunk?, Error>?
        writer.finish(at: time(seconds)) { result in
            outcome = result
            semaphore.signal()
        }
        try check(semaphore.wait(timeout: .now() + 10) == .success, "finish did not complete")
        return try outcome!.get()
    }

    static func testWritesPartialThenRenamesOnFinish() throws {
        let directory = TestSandbox.makeDirectory("writer")
        let writer = try makeWriter(in: directory)
        appendFrames(writer, seconds: 1.0)

        try check(FileManager.default.fileExists(atPath: writer.partialURL.path), "Chunk in progress should be a .partial file")
        try check(!FileManager.default.fileExists(atPath: writer.finalURL.path), "Final name must not exist before finishing")

        let chunk = try finish(writer, at: 1.0)
        try check(chunk?.url == writer.finalURL, "Finished chunk should use the final name")
        try check(FileManager.default.fileExists(atPath: writer.finalURL.path), "Finished chunk missing")
        try check(!FileManager.default.fileExists(atPath: writer.partialURL.path), "Partial file should be gone")
        try check(DefaultVideoMetadataProvider().durationAndIsValid(for: writer.finalURL).isValid, "Finished chunk is not playable")
    }

    static func testHoldsLastFrameUntilEndTime() throws {
        let directory = TestSandbox.makeDirectory("writer_hold")
        let writer = try makeWriter(in: directory)
        // 0.5 s of motion, then an idle screen until the chunk ends at 3 s.
        appendFrames(writer, seconds: 0.5)

        let chunk = try finish(writer, at: 3.0)
        let fileDuration = TestMedia.duration(of: writer.finalURL)
        try check(abs(fileDuration - 3.0) < 0.05, "Expected the chunk to cover 3.0 s of wall-clock time, got \(fileDuration)")
        try check(abs((chunk?.duration ?? 0) - 3.0) < 0.05, "Reported duration should match")
    }

    /// Retries while the real-time encoder is busy; gives up (false) for frames the writer rejects.
    private static func appendEventually(_ writer: ChunkWriter, at time: CMTime) -> Bool {
        for _ in 0..<100 {
            if writer.append(TestMedia.pixelBuffer(), at: time) {
                return true
            }
            usleep(2000)
        }
        return false
    }

    static func testLateFramesAreNudgedNotDropped() throws {
        let directory = TestSandbox.makeDirectory("writer_order")
        let writer = try makeWriter(in: directory)

        try check(appendEventually(writer, at: time(0.5)), "First frame should be accepted")
        // Captured before the previous frame but delivered after it, as happens around a rotation.
        try check(appendEventually(writer, at: time(0.4)), "A slightly late frame should be kept")
        try check(appendEventually(writer, at: time(0.5)), "A repeated timestamp should be nudged forward")
        try check(writer.framesWritten == 3, "Expected 3 frames, got \(writer.framesWritten)")

        try check(!appendEventually(writer, at: time(0.1)), "A frame far older than the last one must be dropped")
        try check(!appendEventually(writer, at: CMTimeSubtract(start, CMTime(seconds: 1, preferredTimescale: 600))), "A frame from before the chunk must be dropped")
        try check(writer.framesWritten == 3, "Rejected frames must not be written")

        let chunk = try finish(writer, at: 1.0)
        try check(chunk.map { DefaultVideoMetadataProvider().durationAndIsValid(for: $0.url).isValid } == true, "Chunk with nudged frames should be playable")
    }

    static func testFinishWithoutFramesKeepsNothing() throws {
        let directory = TestSandbox.makeDirectory("writer_empty")
        let writer = try makeWriter(in: directory)

        let chunk = try finish(writer, at: 1.0)
        try check(chunk == nil, "A chunk without frames should not be kept")
        try check(!FileManager.default.fileExists(atPath: writer.partialURL.path), "Empty partial file should be removed")
    }

    static func testCancelDeletesPartialFile() throws {
        let directory = TestSandbox.makeDirectory("writer_cancel")
        let writer = try makeWriter(in: directory)
        appendFrames(writer, seconds: 0.3)

        writer.cancel()
        try check(!FileManager.default.fileExists(atPath: writer.partialURL.path), "Cancelled chunk should be deleted")
    }

    static func testFailsWhenDirectoryIsMissing() throws {
        let missing = TestSandbox.makeDirectory("writer_missing").appendingPathComponent("does/not/exist")
        do {
            _ = try makeWriter(in: missing)
            throw TestFailure(description: "Expected the writer to fail for a missing directory")
        } catch is TestFailure {
            throw TestFailure(description: "Expected the writer to fail for a missing directory")
        } catch {
            // Expected: the failure surfaces instead of a writer that silently records nothing.
        }
    }

    static func testInterruptedChunkStaysReadable() throws {
        let directory = TestSandbox.makeDirectory("writer_crash")
        let writer = try makeWriter(in: directory)
        appendFrames(writer, seconds: 3.0)
        // Give the writer time to flush fragments, then copy the file as a crash would leave it.
        Thread.sleep(forTimeInterval: 1.0)

        let snapshot = directory.appendingPathComponent("snapshot.mp4")
        try FileManager.default.copyItem(at: writer.partialURL, to: snapshot)
        writer.cancel()

        let meta = DefaultVideoMetadataProvider().durationAndIsValid(for: snapshot)
        try check(meta.isValid && meta.duration >= 1.0, "Expected the interrupted chunk to stay playable, got \(meta)")
    }

    // MARK: - Encoder Settings

    static func testBitrateScalesSubLinearlyWithResolution() throws {
        let reference = EncoderSettings.make(width: 1440, height: 900, preferHEVC: false)
        let retina = EncoderSettings.make(width: 2880, height: 1800, preferHEVC: false)
        let huge = EncoderSettings.make(width: 6016, height: 3384, preferHEVC: false)
        let tiny = EncoderSettings.make(width: 320, height: 240, preferHEVC: false)

        try check(reference.bitRate == 4_000_000, "Reference display should keep 4 Mbps, got \(reference.bitRate)")
        try check(retina.bitRate > reference.bitRate && retina.bitRate < reference.bitRate * 4, "Retina bitrate should grow sub-linearly, got \(retina.bitRate)")
        try check(huge.bitRate == Int(ConfigManager.shared.maxBitRate), "Bitrate should be capped, got \(huge.bitRate)")
        try check(tiny.bitRate == Int(ConfigManager.shared.minBitRate), "Bitrate should have a floor, got \(tiny.bitRate)")
    }

    static func testHEVCRequiresHardwareEncoder() throws {
        let settings = EncoderSettings.make(width: 1440, height: 900, preferHEVC: true)
        let expected: AVVideoCodecType = EncoderSupport.isHEVCHardwareEncoderAvailable ? .hevc : .h264
        try check(settings.codec == expected, "Expected \(expected.rawValue), got \(settings.codec.rawValue)")
        if settings.codec == .hevc {
            try check(settings.bitRate < EncoderSettings.make(width: 1440, height: 900, preferHEVC: false).bitRate, "HEVC should use a lower bitrate")
        }
    }

    static func testKeyFramesAreBoundedByDuration() throws {
        let settings = EncoderSettings.make(width: 1440, height: 900, preferHEVC: false)
        let compression = settings.outputSettings[AVVideoCompressionPropertiesKey] as? [String: Any]
        try check((compression?[AVVideoMaxKeyFrameIntervalDurationKey] as? Double) == ConfigManager.shared.keyFrameIntervalSeconds, "Keyframe interval must be capped by duration")
        try check((compression?[AVVideoMaxKeyFrameIntervalKey] as? Int) == 60, "Expected a 60 frame keyframe interval at 30 fps")
    }

    // MARK: - Display Stream Surfaces

    static func testPixelBufferHoldsSurfaceUseCountUntilReleased() throws {
        let bytesPerRow = 64 * 4
        guard let surface = IOSurface(properties: [
            .width: 64,
            .height: 48,
            .bytesPerElement: 4,
            .bytesPerRow: bytesPerRow,
            .allocSize: bytesPerRow * 48,
            .pixelFormat: Int(kCVPixelFormatType_32BGRA)
        ]) else {
            throw TestFailure(description: "Could not create an IOSurface")
        }
        try check(!IOSurfaceIsInUse(surface), "A fresh surface should not be in use")

        // While the encoder (or Recall) holds the frame, the stream must not recycle the surface.
        var held: CVPixelBuffer? = DisplayStreamSource.retainedPixelBuffer(for: surface)
        try check(held != nil && IOSurfaceIsInUse(surface), "The surface must stay in use while the pixel buffer is alive")
        held = nil
        try check(held == nil && !IOSurfaceIsInUse(surface), "Releasing the pixel buffer must release the surface")
    }

    static func testDisplayStreamPropertiesIncludeCursor() throws {
        let props = DisplayStreamSource.streamProperties(frameRate: 30)
        try check((props[CGDisplayStream.showCursor] as? Bool) == true, "showCursor must be true to record cursor")
        try check(abs(((props[CGDisplayStream.minimumFrameTime] as? Double) ?? 0) - 1.0 / 30.0) < 0.0001, "Expected a 30 fps frame interval")
    }
}
