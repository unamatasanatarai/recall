import Foundation

struct ChunkManagerTests {
    static func testDirectoryCreation() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_dir_test_\(UUID().uuidString)")

        _ = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        if !fileSystem.createdDirectories.contains(tempDir) {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Directory was not created at \(tempDir.path)"])
        }
    }

    static func testLoadExistingFiles_mp4AndIgnoreNonMp4() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let mp4URL = tempDir.appendingPathComponent("chunk_2026-10-03_12-00-00-000.mp4")
        let txtURL = tempDir.appendingPathComponent("notes.txt")

        fileSystem.files[mp4URL] = [.size: Int64(1000)]
        fileSystem.files[txtURL] = [.size: Int64(500)]

        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        if manager.chunks.count != 1 || manager.chunks.first?.url != mp4URL {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 1 mp4 chunk indexed, got \(manager.chunks.count)"])
        }
    }

    static func testLoadExistingFiles_purgeCorrupt() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let corruptURL = tempDir.appendingPathComponent("chunk_corrupt.mp4")
        fileSystem.files[corruptURL] = [.size: Int64(1000)]

        let corruptProvider = MockVideoMetadataProvider(defaultDuration: 0.0, isValid: false)

        _ = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: corruptProvider,
            chunksDirectory: tempDir
        )

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        if !fileSystem.removedURLs.contains(corruptURL) {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Corrupt chunk was not purged on load"])
        }
    }

    static func testParseDateFromFilename() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let chunkURL = tempDir.appendingPathComponent("chunk_2026-10-03_14-30-00-000.mp4")
        fileSystem.files[chunkURL] = [.size: Int64(1000)]

        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        guard let loaded = manager.chunks.first else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Chunk failed to load"])
        }

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: loaded.startTime)
        if comps.year != 2026 || comps.month != 10 || comps.day != 3 || comps.hour != 14 || comps.minute != 30 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Parsed date components incorrect: \(comps)"])
        }
    }

    static func testFallbackCreationDate() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let chunkURL = tempDir.appendingPathComponent("custom_video.mp4")
        let creationDate = Date().addingTimeInterval(-3600)
        fileSystem.files[chunkURL] = [.size: Int64(1000), .creationDate: creationDate]

        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        guard let loaded = manager.chunks.first else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Chunk failed to load"])
        }

        if abs(loaded.startTime.timeIntervalSince(creationDate)) > 1.0 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fallback date mismatch"])
        }
    }

    static func testSortOrder() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        // Sync on queue to ensure loadExistingChunks completes on empty directory
        _ = manager.totalRecordedDuration

        let now = Date()
        let urlLater = tempDir.appendingPathComponent("chunk_later.mp4")
        let urlEarlier = tempDir.appendingPathComponent("chunk_earlier.mp4")
        fileSystem.setFile(urlLater, attributes: [.size: Int64(100)])
        fileSystem.setFile(urlEarlier, attributes: [.size: Int64(100)])

        manager.registerChunk(url: urlLater, startTime: now.addingTimeInterval(-30), duration: 30)
        manager.registerChunk(url: urlEarlier, startTime: now.addingTimeInterval(-60), duration: 30)

        // Sync on queue to ensure both registerChunk calls complete
        _ = manager.totalRecordedDuration

        if manager.chunks.count != 2 || manager.chunks[0].url != urlEarlier || manager.chunks[1].url != urlLater {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Chunks not sorted by startTime ascending"])
        }
    }

    static func testTotalDurationCalculation() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(defaultDuration: 0.0, isValid: true),
            chunksDirectory: tempDir
        )


        let url1 = tempDir.appendingPathComponent("c1.mp4")
        let url2 = tempDir.appendingPathComponent("c2.mp4")
        fileSystem.files[url1] = [.size: Int64(100)]
        fileSystem.files[url2] = [.size: Int64(100)]

        manager.registerChunk(url: url1, startTime: Date().addingTimeInterval(-60), duration: 30.0)
        manager.registerChunk(url: url2, startTime: Date().addingTimeInterval(-30), duration: 45.0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        if abs(manager.totalRecordedDuration - 75.0) > 0.1 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected total duration 75.0, got \(manager.totalRecordedDuration)"])
        }
    }

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

        fileSystem.files[chunk1URL] = [.size: Int64(150)]
        fileSystem.files[chunk2URL] = [.size: Int64(100)]

        manager.registerChunk(url: chunk1URL, startTime: Date().addingTimeInterval(-120), duration: 30.0)
        manager.registerChunk(url: chunk2URL, startTime: Date().addingTimeInterval(-60), duration: 30.0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        if !fileSystem.removedURLs.contains(chunk1URL) {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Oldest chunk was not removed when over size limit"])
        }
    }

    static func testEnforceLimits_purgesOldestWhenOverDuration() throws {
        let config = MockStorageConfig(
            maxBufferSizeBytes: 100000000,
            maxStorageDurationSeconds: 40.0
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

        let chunk1URL = tempDir.appendingPathComponent("chunk1.mp4")
        let chunk2URL = tempDir.appendingPathComponent("chunk2.mp4")

        fileSystem.files[chunk1URL] = [.size: Int64(100)]
        fileSystem.files[chunk2URL] = [.size: Int64(100)]

        manager.registerChunk(url: chunk1URL, startTime: Date().addingTimeInterval(-60), duration: 30.0)
        manager.registerChunk(url: chunk2URL, startTime: Date().addingTimeInterval(-30), duration: 30.0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        if !fileSystem.removedURLs.contains(chunk1URL) {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Oldest chunk was not removed when over duration limit"])
        }
    }

    static func testEnforceLimits_multiChunkSequentialPurge() throws {
        let config = MockStorageConfig(
            maxBufferSizeBytes: 100,
            maxStorageDurationSeconds: 10000
        )
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: config,
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        let c1 = tempDir.appendingPathComponent("c1.mp4")
        let c2 = tempDir.appendingPathComponent("c2.mp4")
        let c3 = tempDir.appendingPathComponent("c3.mp4")

        fileSystem.files[c1] = [.size: Int64(80)]
        fileSystem.files[c2] = [.size: Int64(80)]
        fileSystem.files[c3] = [.size: Int64(80)]

        manager.registerChunk(url: c1, startTime: Date().addingTimeInterval(-90), duration: 30)
        manager.registerChunk(url: c2, startTime: Date().addingTimeInterval(-60), duration: 30)
        manager.registerChunk(url: c3, startTime: Date().addingTimeInterval(-30), duration: 30)

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        if !fileSystem.removedURLs.contains(c1) || !fileSystem.removedURLs.contains(c2) {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sequential multi-chunk purge failed"])
        }
        if manager.chunks.count != 1 || manager.chunks.first?.url != c3 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Remaining chunks list incorrect"])
        }
    }

    static func testEnforceLimits_zeroLimitHandling() throws {
        let config = MockStorageConfig(maxBufferSizeBytes: 0, maxStorageDurationSeconds: 0)
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: config,
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )
        manager.enforceLimits()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
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

        if !fileSystem.removedURLs.contains(chunk1URL) || !manager.chunks.isEmpty {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Chunk was not purged"])
        }
    }

    static func testRegisterZeroByteChunk() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        let zeroURL = tempDir.appendingPathComponent("zero.mp4")
        fileSystem.files[zeroURL] = [.size: Int64(0)]

        manager.registerChunk(url: zeroURL, startTime: Date(), duration: 30)

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        if !fileSystem.removedURLs.contains(zeroURL) || !manager.chunks.isEmpty {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "0-byte chunk was not purged on register"])
        }
    }

    static func testRegisterCorruptChunk() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(defaultDuration: 0.0, isValid: false),
            chunksDirectory: tempDir
        )

        let corruptURL = tempDir.appendingPathComponent("corrupt.mp4")
        fileSystem.files[corruptURL] = [.size: Int64(500)]

        manager.registerChunk(url: corruptURL, startTime: Date(), duration: 30)

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        if !fileSystem.removedURLs.contains(corruptURL) || !manager.chunks.isEmpty {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Corrupt chunk was not purged on register"])
        }
    }
}
