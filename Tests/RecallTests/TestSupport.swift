import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

/// Throws with `message` (and the call site) when `condition` is false.
func check(_ condition: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String, file: StaticString = #fileID, line: UInt = #line) throws {
    guard try condition() else {
        throw TestFailure(description: "\(message()) (\(file):\(line))")
    }
}

/// Spins the main run loop until `condition` holds or `timeout` passes.
@discardableResult
func waitUntil(timeout: TimeInterval = 3.0, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

/// Spins the main run loop for `seconds`.
func pump(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

/// Test state written from background queues and read from the test thread.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    var current: Value {
        return lock.withCriticalSection { value }
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.withCriticalSection { body(&value) }
    }
}

enum TestSandbox {
    static var root: URL {
        return URL(fileURLWithPath: ProcessInfo.processInfo.environment["RECALL_CACHE_DIR"] ?? NSTemporaryDirectory())
    }

    /// A fresh, empty directory inside the sandbox.
    static func makeDirectory(_ name: String = "dir") -> URL {
        let url = root.appendingPathComponent("\(name)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum TestMedia {
    /// An IOSurface-backed BGRA frame filled with `shade`, like the frames capture sources deliver.
    static func pixelBuffer(width: Int = 320, height: Int = 240, shade: UInt8 = 128) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer)
        let buffer = pixelBuffer!
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, Int32(shade), CVPixelBufferGetBytesPerRow(buffer) * height)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// Writes a finished chunk lasting `duration` seconds into `directory` and returns it.
    static func writeChunk(in directory: URL, startDate: Date, duration: TimeInterval, width: Int = 320, height: Int = 240) throws -> ChunkWriter.FinishedChunk {
        let start = CMTime(seconds: 1000, preferredTimescale: 600)
        let settings = EncoderSettings.make(width: width, height: height, preferHEVC: false)
        let writer = try ChunkWriter(directory: directory, startTime: start, startDate: startDate, settings: settings, fileSystem: FileManager.default)

        let frameCount = max(1, Int(duration * 10))
        for index in 0..<frameCount {
            let time = CMTimeAdd(start, CMTime(seconds: Double(index) / 10.0, preferredTimescale: 600))
            var attempts = 0
            while !writer.append(pixelBuffer(width: width, height: height, shade: UInt8(index * 20 % 255)), at: time) && attempts < 200 {
                usleep(2000)
                attempts += 1
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<ChunkWriter.FinishedChunk?, Error> = .success(nil)
        writer.finish(at: CMTimeAdd(start, CMTime(seconds: duration, preferredTimescale: 600))) { result in
            outcome = result
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        guard let chunk = try outcome.get() else {
            throw TestFailure(description: "Chunk writer produced no chunk")
        }
        return chunk
    }

    static func duration(of url: URL) -> TimeInterval {
        return CMTimeGetSeconds(AVURLAsset(url: url).duration)
    }
}
