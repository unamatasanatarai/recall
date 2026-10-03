import Foundation

struct ChunkManagerTests {
    static func testEnforceLimits_purgesOldestWhenOverSizeBytes() throws {
        let config = MockStorageConfig(
            maxBufferSizeBytes: 200,
            maxStorageDurationSeconds: 10000
        )
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_chunks_\(UUID().uuidString)")

        let manager = ChunkManager(
            config: config,
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        let chunk1URL = tempDir.appendingPathComponent("chunk_2026-10-03_10-00-00-000.mp4")
        let chunk2URL = tempDir.appendingPathComponent("chunk_2026-10-03_10-01-00-000.mp4")

        fileSystem.files[chunk1URL] = [.size: Int64(150), .creationDate: Date().addingTimeInterval(-120)]
        fileSystem.files[chunk2URL] = [.size: Int64(100), .creationDate: Date().addingTimeInterval(-60)]

        manager.registerChunk(url: chunk1URL, startTime: Date().addingTimeInterval(-120), duration: 30.0)
        manager.registerChunk(url: chunk2URL, startTime: Date().addingTimeInterval(-60), duration: 30.0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        if !fileSystem.removedURLs.contains(chunk1URL) {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Oldest chunk was not removed"])
        }
    }

    static func testPurgeAllChunks_removesAllRegisteredFiles() throws {
        let config = MockStorageConfig()
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_chunks_\(UUID().uuidString)")

        let chunk1URL = tempDir.appendingPathComponent("chunk1.mp4")
        fileSystem.files[chunk1URL] = [.size: Int64(100)]

        let manager = ChunkManager(
            config: config,
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        manager.purgeAllChunks()

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        if !fileSystem.removedURLs.contains(chunk1URL) {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Chunk was not purged"])
        }
    }
}
