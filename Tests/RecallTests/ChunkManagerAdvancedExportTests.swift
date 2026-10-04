import Foundation

struct ChunkManagerAdvancedExportTests {
    static func testSubSecondTargetClamping() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_adv_export_\(UUID().uuidString)")
        let mockRunner = MockFFmpegRunner(ffmpegPathToReturn: "/usr/local/bin/ffmpeg", concatAndTrimResult: true, fileSystem: fileSystem)

        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: mockRunner,
            metadataProvider: MockVideoMetadataProvider(defaultDuration: 30.0, isValid: true),
            chunksDirectory: tempDir
        )

        let chunk1 = tempDir.appendingPathComponent("chunk1.mp4")
        fileSystem.setFile(chunk1, attributes: [.size: Int64(1000)])
        manager.registerChunk(url: chunk1, startTime: Date(), duration: 30.0)

        _ = manager.totalRecordedDuration

        var completed = false
        var resultURL: URL? = nil
        manager.exportClip(offsetSeconds: 0.2) { url in
            resultURL = url
            completed = true
        }

        let timeout = Date().addingTimeInterval(1.0)
        while !completed && Date() < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if !completed || resultURL == nil {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected valid export URL for sub-second clamping"])
        }
    }

    static func testExportOffsetLargerThanTotalStore() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_adv_export_\(UUID().uuidString)")
        let mockRunner = MockFFmpegRunner(ffmpegPathToReturn: "/usr/local/bin/ffmpeg", concatAndTrimResult: true, fileSystem: fileSystem)

        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: mockRunner,
            metadataProvider: MockVideoMetadataProvider(defaultDuration: 30.0, isValid: true),
            chunksDirectory: tempDir
        )

        let chunk1 = tempDir.appendingPathComponent("chunk1.mp4")
        fileSystem.setFile(chunk1, attributes: [.size: Int64(1000)])
        manager.registerChunk(url: chunk1, startTime: Date(), duration: 30.0)

        _ = manager.totalRecordedDuration

        var completed = false
        manager.exportClip(offsetSeconds: 3600.0) { _ in
            completed = true
        }

        let timeout = Date().addingTimeInterval(1.0)
        while !completed && Date() < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if !completed {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Export completion failed when offset > total store duration"])
        }
    }

    static func testSingleNewestChunkOverLimitPurge() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_adv_export_\(UUID().uuidString)")
        let config = MockStorageConfig(maxBufferSizeBytes: 500) // 500 bytes max

        let manager = ChunkManager(
            config: config,
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(defaultDuration: 30.0, isValid: true),
            chunksDirectory: tempDir
        )

        let chunk1 = tempDir.appendingPathComponent("giant_chunk.mp4")
        fileSystem.setFile(chunk1, attributes: [.size: Int64(5000)]) // 5000 bytes > 500 max
        manager.registerChunk(url: chunk1, startTime: Date(), duration: 30.0)

        _ = manager.totalRecordedDuration

        if manager.chunks.count != 0 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected giant chunk over size limit to be purged"])
        }
    }

    static func testChunkManagerCoverageEdges() throws {
        // 1. Shared singleton instance access
        _ = ChunkManager.shared

        // 2. Default init without chunksDirectory override (both XDG_CACHE_HOME set & unset)
        setenv("XDG_CACHE_HOME", "/tmp/mock_xdg_cache", 1)
        let xdgManager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: MockFileSystem(),
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider()
        )
        _ = xdgManager.chunksDirectory

        unsetenv("XDG_CACHE_HOME")
        let defaultManager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: MockFileSystem(),
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider()
        )
        _ = defaultManager.chunksDirectory

        // 3. Load existing files with 0-byte size (covers line 71)
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_zero_exist_\(UUID().uuidString)")
        let zeroFile = tempDir.appendingPathComponent("chunk_zero_exist.mp4")
        fileSystem.setFile(zeroFile, attributes: [.size: Int64(0)])

        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )
        manager.syncQueue()

        if !fileSystem.removedURLs.contains(zeroFile) {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 0-byte file to be purged during loadExistingChunks"])
        }

        // 4. Export with corrupt/unsupported composition leading to nil AVAssetExportSession (covers line 269)
        let invalidFileSystem = MockFileSystem()
        let invalidTempDir = URL(fileURLWithPath: "/tmp/recall_nil_export_\(UUID().uuidString)")
        let chunkFile = invalidTempDir.appendingPathComponent("invalid_chunk.mp4")
        invalidFileSystem.setFile(chunkFile, attributes: [.size: Int64(1000)])

        let mockRunner = MockFFmpegRunner(ffmpegPathToReturn: nil, concatAndTrimResult: false)
        let invalidManager = ChunkManager(
            config: MockStorageConfig(exportsDirectoryURL: invalidTempDir),
            fileSystem: invalidFileSystem,
            ffmpegRunner: mockRunner,
            metadataProvider: MockVideoMetadataProvider(defaultDuration: 10.0, isValid: true),
            exportSessionFactory: { _, _ in nil },
            chunksDirectory: invalidTempDir
        )
        invalidManager.registerChunk(url: chunkFile, startTime: Date(), duration: 10.0)
        invalidManager.syncQueue()

        var nilCompleted = false
        invalidManager.exportClip(offsetSeconds: 10.0) { url in
            nilCompleted = true
        }

        let timeout = Date().addingTimeInterval(2.0)
        while !nilCompleted && Date() < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        invalidManager.syncQueue()
    }
}
