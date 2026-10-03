import Foundation

struct ConcurrencyTests {
    static func testConcurrentRegisterChunk() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_concurrency_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(defaultDuration: 10.0, isValid: true),
            chunksDirectory: tempDir
        )

        let queue = DispatchQueue(label: "test.concurrency", attributes: .concurrent)
        let group = DispatchGroup()

        for i in 1...20 {
            group.enter()
            queue.async {
                let fileURL = tempDir.appendingPathComponent("chunk_\(i).mp4")
                fileSystem.setFile(fileURL, attributes: [.size: Int64(1000)])
                manager.registerChunk(url: fileURL, startTime: Date(), duration: 10.0)
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 3.0)
        if result == .timedOut {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Concurrent registerChunk timed out"])
        }
    }

    static func testConcurrentPurgeAndLimitEnforcement() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_concurrency_purge_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(defaultDuration: 10.0, isValid: true),
            chunksDirectory: tempDir
        )

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.purge.concurrency", attributes: .concurrent)

        for i in 1...10 {
            group.enter()
            queue.async {
                let fileURL = tempDir.appendingPathComponent("chunk_\(i).mp4")
                fileSystem.setFile(fileURL, attributes: [.size: Int64(1000)])
                manager.registerChunk(url: fileURL, startTime: Date(), duration: 10.0)
                manager.enforceLimits()
                group.leave()
            }
        }

        group.enter()
        queue.async {
            manager.purgeAllChunks()
            group.leave()
        }

        let res = group.wait(timeout: .now() + 3.0)
        if res == .timedOut {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Concurrent purge timed out"])
        }
    }

    static func testThreadSafeDurationAccess() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_concurrency_duration_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(defaultDuration: 15.0, isValid: true),
            chunksDirectory: tempDir
        )

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.duration.concurrency", attributes: .concurrent)

        for _ in 1...50 {
            group.enter()
            queue.async {
                _ = manager.totalRecordedDuration
                group.leave()
            }
        }

        let res = group.wait(timeout: .now() + 3.0)
        if res == .timedOut {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Thread safe duration access timed out"])
        }
    }

    static func testConcurrentLogFileWriting() throws {
        let engine = RecorderEngine(chunkStore: MockChunkStore())
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.log.concurrency", attributes: .concurrent)

        for i in 1...30 {
            group.enter()
            queue.async {
                engine.log("Concurrent log entry \(i)")
                group.leave()
            }
        }

        let res = group.wait(timeout: .now() + 3.0)
        if res == .timedOut {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Concurrent log writing timed out"])
        }
    }
}
