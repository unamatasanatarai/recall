import Foundation
import CoreGraphics
import AVFoundation
import CoreMedia
import CoreVideo
import CoreImage


enum RecordingState: Equatable {
    case idle
    case recording
    case error(String)
}

final class RecorderEngine: NSObject, ScreenCapture, ObservableObject, @unchecked Sendable {
    static let shared = RecorderEngine()

    @Published private(set) var state: RecordingState = .idle

    private var displayStream: CGDisplayStream?
    private var currentWriter: AVAssetWriter?
    private var currentVideoInput: AVAssetWriterInput?
    private var currentAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var currentChunkURL: URL?
    private var currentChunkStartTime: Date = Date()

    var framesWrittenInChunk: Int64 = 0
    private var isWriterSessionStarted = false
    var chunkStartTimeSeconds: CFTimeInterval = 0
    private let ciContext = CIContext()
    private let segmentDurationThreshold: TimeInterval = 30.0

    private let logFileURL: URL
    private let chunkStore: ChunkStore

    // Dedicated high-priority queue for frame encoding to keep the main thread 100% free
    private let recordingQueue = DispatchQueue(label: "com.recall.recorder.encoding", qos: .userInteractive)

    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static let chunkDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return formatter
    }()

    private let permissionProvider: ScreenCapturePermissionProvider

    init(
        chunkStore: ChunkStore = ChunkManager.shared,
        permissionProvider: ScreenCapturePermissionProvider = DefaultScreenCapturePermissionProvider(),
        logFileURL: URL? = nil
    ) {
        self.chunkStore = chunkStore
        self.permissionProvider = permissionProvider
        if let customLogURL = logFileURL {
            self.logFileURL = customLogURL
        } else {
            let cacheDir: URL
            if let xdgCache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"], !xdgCache.isEmpty {
                cacheDir = URL(fileURLWithPath: xdgCache).appendingPathComponent("recall")
            } else {
                let home = FileManager.default.homeDirectoryForCurrentUser
                cacheDir = home.appendingPathComponent(".cache/recall")
            }
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            self.logFileURL = cacheDir.appendingPathComponent("recall_debug.log")
        }
        super.init()
        log("RecorderEngine initialized.")
    }

    private var permissionTimer: Timer?

    func startContinuousRecording() {
        log("startContinuousRecording requested.")
        guard state != .recording else {
            log("Already recording.")
            return
        }

        let preflightGranted = permissionProvider.preflightAccess()
        log("ScreenCapturePermission preflightGranted: \(preflightGranted)")

        if preflightGranted {
            permissionTimer?.invalidate()
            permissionTimer = nil
            beginStreamCapture()
        } else {
            log("Screen capture permission missing. Requesting access...")
            _ = permissionProvider.requestAccess()
            self.state = .error("Grant screen recording permission in System Settings.")

            permissionTimer?.invalidate()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.permissionProvider.preflightAccess() {
                    self.log("Screen capture permission granted!")
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.beginStreamCapture()
                }
            }
        }
    }

    @discardableResult
    func beginStreamCapture() -> Bool {
        if displayStream != nil {
            displayStream?.stop()
            displayStream = nil
        }

        let mainID = CGMainDisplayID()
        let width = CGDisplayPixelsWide(mainID)
        let height = CGDisplayPixelsHigh(mainID)
        log("beginStreamCapture for display: \(mainID), size: \(width)x\(height)")

        do {
            try startNewChunk(width: width, height: height)

            let stream = CGDisplayStream(
                display: mainID,
                outputWidth: width,
                outputHeight: height,
                pixelFormat: Int32(kCVPixelFormatType_32BGRA),
                properties: [
                    CGDisplayStream.minimumFrameTime: (1.0 / 30.0) as CFNumber
                ] as CFDictionary
            ) { [weak self] status, displayTime, frameSurface, updateRef in
                guard let self = self else { return }
                // Hand frame processing off to the dedicated high-priority queue immediately
                self.recordingQueue.async {
                    self.handleFrame(status: status, displayTime: displayTime, surface: frameSurface, width: width, height: height)
                }
            }

            guard let stream = stream else {
                log("Failed to create CGDisplayStream")
                self.state = .error("Failed to create display stream.")
                return false
            }

            let runLoopSource = stream.runLoopSource!
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

            let err = stream.start()
            if err != .success {
                log("CGDisplayStream start error: \(err.rawValue)")
                self.state = .error("Display stream start failed: \(err.rawValue)")
                return false
            }

            self.displayStream = stream
            self.state = .recording
            log("Always-On CGDisplayStream recording active!")
            return true

        } catch {
            log("beginStreamCapture error: \(error)")
            self.state = .error("Setup error: \(error.localizedDescription)")
            return false
        }
    }

    func startNewChunk(width: Int, height: Int) throws {
        let chunksDir = chunkStore.chunksDirectory
        let timestamp = RecorderEngine.chunkDateFormatter.string(from: Date())
        let chunkURL = chunksDir.appendingPathComponent("chunk_\(timestamp).mp4")
        log("startNewChunk target: \(chunkURL.path)")

        try? FileManager.default.removeItem(at: chunkURL)

        let writer = try AVAssetWriter(outputURL: chunkURL, fileType: .mp4)

        // Hardware H.264 Encoder settings optimized for low CPU/memory footprint
        let compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: 4_000_000, // 4 Mbps
            AVVideoMaxKeyFrameIntervalKey: 60,   // Keyframe every 2 seconds at 30fps
            AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
            AVVideoAllowFrameReorderingKey: false
        ]

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let pixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelAttributes
        )

        guard writer.canAdd(input) else {
            log("Cannot add input to writer for chunk")
            throw NSError(domain: "RecorderEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add input"])
        }

        writer.add(input)
        writer.startWriting()
        log("Started chunk writer: status=\(writer.status.rawValue)")

        self.currentWriter = writer
        self.currentVideoInput = input
        self.currentAdaptor = adaptor
        self.currentChunkURL = chunkURL
        self.currentChunkStartTime = Date()
        self.framesWrittenInChunk = 0
        self.isWriterSessionStarted = false
        self.chunkStartTimeSeconds = CACurrentMediaTime()
    }

    func handleFrame(status: CGDisplayStreamFrameStatus, displayTime: UInt64, surface: IOSurface?, width: Int, height: Int) {
        guard status == .frameComplete || status == .frameIdle else { return }
        guard let surface = surface else { return }

        let elapsed = CACurrentMediaTime() - chunkStartTimeSeconds

        // Rotate chunk if 30 seconds threshold exceeded
        if elapsed >= segmentDurationThreshold {
            rotateChunk(width: width, height: height)
            return
        }

        let pts = CMTime(seconds: elapsed, preferredTimescale: 600)

        guard let writer = currentWriter, let input = currentVideoInput, let adaptor = currentAdaptor else { return }

        var unmanagedPixelBuffer: Unmanaged<CVPixelBuffer>?

        // Zero-copy IOSurface wrapping (O(1) GPU-to-buffer binding with zero CPU/GPU copy overhead)
        let cvErr = CVPixelBufferCreateWithIOSurface(
            kCFAllocatorDefault,
            surface,
            [kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary,
            &unmanagedPixelBuffer
        )

        let pbToAppend: CVPixelBuffer
        if cvErr == kCVReturnSuccess, let unmanaged = unmanagedPixelBuffer {
            pbToAppend = unmanaged.takeRetainedValue()
        } else {
            // Fallback if zero-copy creation is unsupported
            guard let pool = adaptor.pixelBufferPool else { return }
            var poolBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &poolBuffer) == kCVReturnSuccess, let pb = poolBuffer else { return }
            let ciImage = CIImage(ioSurface: surface)
            ciContext.render(ciImage, to: pb)
            pbToAppend = pb
        }

        if !isWriterSessionStarted {
            writer.startSession(atSourceTime: pts)
            isWriterSessionStarted = true
        }

        if input.isReadyForMoreMediaData {
            if adaptor.append(pbToAppend, withPresentationTime: pts) {
                framesWrittenInChunk += 1
            }
        }
    }

    func rotateChunk(width: Int, height: Int) {
        guard let oldWriter = currentWriter, let oldInput = currentVideoInput, let oldURL = currentChunkURL else { return }
        let startTime = currentChunkStartTime
        let duration = CACurrentMediaTime() - chunkStartTimeSeconds
        let frameCount = framesWrittenInChunk

        oldInput.markAsFinished()
        oldWriter.finishWriting {
            if oldWriter.status == .completed && frameCount > 0 {
                self.chunkStore.registerChunk(url: oldURL, startTime: startTime, duration: duration)
            } else {
                try? FileManager.default.removeItem(at: oldURL)
            }
        }

        // Start new chunk immediately
        try? startNewChunk(width: width, height: height)
    }

    /// Flush the current in-progress chunk asynchronously without blocking caller thread.
    func flushCurrentChunk(completion: (() -> Void)? = nil) {
        recordingQueue.async {
            guard let writer = self.currentWriter, let input = self.currentVideoInput, let url = self.currentChunkURL else {
                completion?()
                return
            }

            let startTime = self.currentChunkStartTime
            let duration = CACurrentMediaTime() - self.chunkStartTimeSeconds
            let frameCount = self.framesWrittenInChunk

            self.log("flushCurrentChunk: finalizing \(url.lastPathComponent) (\(frameCount) frames, \(String(format: "%.1f", duration))s)")

            input.markAsFinished()

            writer.finishWriting {
                if writer.status == .completed && frameCount > 0 {
                    self.chunkStore.registerChunk(url: url, startTime: startTime, duration: duration)
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
                
                let mainID = CGMainDisplayID()
                let width = CGDisplayPixelsWide(mainID)
                let height = CGDisplayPixelsHigh(mainID)
                try? self.startNewChunk(width: width, height: height)
                
                completion?()
            }
        }
    }

    func stopStream() {
        recordingQueue.async {
            if let stream = self.displayStream {
                stream.stop()
                self.displayStream = nil
            }
            if let writer = self.currentWriter, let input = self.currentVideoInput, let url = self.currentChunkURL {
                let startTime = self.currentChunkStartTime
                let duration = CACurrentMediaTime() - self.chunkStartTimeSeconds
                let count = self.framesWrittenInChunk
                input.markAsFinished()
                writer.finishWriting {
                    if writer.status == .completed && count > 0 {
                        self.chunkStore.registerChunk(url: url, startTime: startTime, duration: duration)
                    }
                }
            }
            self.currentWriter = nil
            self.currentVideoInput = nil
            self.currentAdaptor = nil
            DispatchQueue.main.async {
                self.state = .idle
            }
        }
    }

    func log(_ message: String) {
        let timestamp = RecorderEngine.logDateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        print(line, terminator: "")

        // Rotate log if it exceeds 10 MB
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
           let size = attrs[.size] as? Int64, size > 10 * 1024 * 1024 {
            try? FileManager.default.removeItem(at: logFileURL)
        }

        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fh = try? FileHandle(forWritingTo: logFileURL) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
}
