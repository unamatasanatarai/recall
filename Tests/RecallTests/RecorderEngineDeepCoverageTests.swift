import Foundation
import CoreGraphics
import QuartzCore
import IOSurface

struct RecorderEngineDeepCoverageTests {
    static func testAlreadyRecordingGuard() throws {
        let store = MockChunkStore()
        let permission = MockScreenCapturePermissionProvider(isGranted: true)
        let engine = RecorderEngine(chunkStore: store, permissionProvider: permission)

        // Call startContinuousRecording
        engine.startContinuousRecording()

        // Call startContinuousRecording second time (triggers already recording guard)
        engine.startContinuousRecording()

        if engine.state == .idle {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected state transition from idle"])
        }
    }

    static func testPermissionPreflightMissing() throws {
        let store = MockChunkStore()
        let permission = MockScreenCapturePermissionProvider(isGranted: false, requestAccessResult: false)
        let engine = RecorderEngine(chunkStore: store, permissionProvider: permission)

        engine.startContinuousRecording()

        if case .error(let msg) = engine.state {
            if !msg.contains("Grant screen recording permission") {
                throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected error message: \(msg)"])
            }
        } else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected state .error when permission is missing"])
        }
    }

    static func testPermissionPreflightGranted() throws {
        let store = MockChunkStore()
        let permission = MockScreenCapturePermissionProvider(isGranted: true)
        let engine = RecorderEngine(chunkStore: store, permissionProvider: permission)

        engine.startContinuousRecording()
        // Tested preflight granted path
    }

    static func testHandleFrameDropAndIdle() throws {
        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store)

        // Pass stopped status -> should return early
        engine.handleFrame(status: .stopped, displayTime: 0, surface: nil, width: 1920, height: 1080)

        // Pass frameBlank status -> should return early
        engine.handleFrame(status: .frameBlank, displayTime: 0, surface: nil, width: 1920, height: 1080)
    }

    static func testHandleFrameNilSurface() throws {
        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store)

        // Pass frameComplete with nil surface -> should return early
        engine.handleFrame(status: .frameComplete, displayTime: 0, surface: nil, width: 1920, height: 1080)
    }

    static func testStartNewChunkAndRotateChunk() throws {
        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store)

        try engine.startNewChunk(width: 1280, height: 720)
        engine.rotateChunk(width: 1280, height: 720)
    }

    static func testStreamStopCleanup() throws {
        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store)

        engine.stopStream()

        let timeout = Date().addingTimeInterval(1.0)
        while engine.state != .idle && Date() < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if engine.state != .idle {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected idle state after stopStream"])
        }
    }

    static func testLogFileOverSizeRotation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logFile = tempDir.appendingPathComponent("recall.log")
        let dummyData = Data(repeating: 0x41, count: 10 * 1024 * 1024 + 10)
        try dummyData.write(to: logFile)

        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store, logFileURL: logFile)

        engine.log("Testing rotation on oversize log")

        let newAttrs = try FileManager.default.attributesOfItem(atPath: logFile.path)
        let newSize = (newAttrs[.size] as? Int64) ?? 0
        if newSize > 1024 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected log file to be truncated/rotated, got size: \(newSize)"])
        }
    }

    static func testFlushCurrentChunkNilWriter() throws {
        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store)

        let expectation = NSCondition()
        var completed = false

        expectation.lock()
        engine.flushCurrentChunk {
            completed = true
            expectation.signal()
        }

        let result = expectation.wait(until: Date().addingTimeInterval(2.0))
        expectation.unlock()

        if !result || !completed {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected completion block to execute for flushCurrentChunk"])
        }
    }

    static func testActiveChunkFlushAndStopStream() throws {
        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store)

        // 1. Start new chunk
        try engine.startNewChunk(width: 640, height: 480)
        engine.framesWrittenInChunk = 3

        // Flush active chunk with writer present
        let flushExpectation = NSCondition()
        var flushDone = false

        flushExpectation.lock()
        engine.flushCurrentChunk {
            flushDone = true
            flushExpectation.signal()
        }

        let flushResult = flushExpectation.wait(until: Date().addingTimeInterval(3.0))
        flushExpectation.unlock()

        if !flushResult || !flushDone {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected flushCurrentChunk completion when active writer present"])
        }

        // 2. Start another chunk and stopStream
        try engine.startNewChunk(width: 640, height: 480)
        engine.framesWrittenInChunk = 5

        engine.stopStream()

        let timeout = Date().addingTimeInterval(3.0)
        while engine.state != .idle && Date() < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if engine.state != .idle {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected idle state after stopping stream with active writer"])
        }
    }

    static func testHandleFrameRotationAndWriting() throws {
        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store)

        try engine.startNewChunk(width: 640, height: 480)

        // Simulate chunk running for over segmentDurationThreshold (30 seconds)
        engine.chunkStartTimeSeconds = CACurrentMediaTime() - 35.0

        // handleFrame should trigger rotateChunk
        engine.handleFrame(status: .frameComplete, displayTime: 35, surface: nil, width: 640, height: 480)
    }

    static func testHandleFrameWithIOSurface() throws {
        let store = MockChunkStore()
        let engine = RecorderEngine(chunkStore: store)

        try engine.startNewChunk(width: 640, height: 480)
        engine.chunkStartTimeSeconds = CACurrentMediaTime()

        let bytesPerRow = 640 * 4
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: 640,
            .height: 480,
            .bytesPerElement: 4,
            .bytesPerRow: bytesPerRow,
            .allocSize: bytesPerRow * 480,
            .pixelFormat: Int(kCVPixelFormatType_32BGRA)
        ]

        if let surface = IOSurface(properties: properties) {
            // First frame starts writer session & appends frame
            engine.handleFrame(status: .frameComplete, displayTime: 1, surface: surface, width: 640, height: 480)

            // Second frame appends with active session
            engine.handleFrame(status: .frameComplete, displayTime: 2, surface: surface, width: 640, height: 480)
        }

        // Flush active chunk so finishWriting completes with framesWrittenInChunk > 0
        let flushExpectation = NSCondition()
        flushExpectation.lock()
        engine.flushCurrentChunk {
            flushExpectation.signal()
        }
        _ = flushExpectation.wait(until: Date().addingTimeInterval(3.0))
        flushExpectation.unlock()
    }
}



