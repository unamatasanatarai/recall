import Foundation

struct ChunkManagerExportTests {
    static func testExportClip_emptyChunkGuard() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_export_test_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        var completed = false
        var exportedResultURL: URL? = nil

        manager.exportClip(offsetSeconds: 30.0) { url in
            exportedResultURL = url
            completed = true
        }

        let timeout = Date().addingTimeInterval(1.0)
        while !completed && Date() < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if !completed || exportedResultURL != nil {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected nil export URL when store is empty"])
        }
    }

    static func testExportClip_chunkSelectionAndTrimming() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_export_test_\(UUID().uuidString)")
        let mockRunner = MockFFmpegRunner(ffmpegPathToReturn: "/usr/local/bin/ffmpeg", concatAndTrimResult: true, fileSystem: fileSystem)
        
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: mockRunner,
            metadataProvider: MockVideoMetadataProvider(defaultDuration: 30.0, isValid: true),
            chunksDirectory: tempDir
        )

        let chunk1 = tempDir.appendingPathComponent("chunk1.mp4")
        let chunk2 = tempDir.appendingPathComponent("chunk2.mp4")
        let chunk3 = tempDir.appendingPathComponent("chunk3.mp4")
        fileSystem.files[chunk1] = [.size: Int64(1000)]
        fileSystem.files[chunk2] = [.size: Int64(1000)]
        fileSystem.files[chunk3] = [.size: Int64(1000)]

        let now = Date()
        manager.registerChunk(url: chunk1, startTime: now.addingTimeInterval(-90), duration: 30.0)
        manager.registerChunk(url: chunk2, startTime: now.addingTimeInterval(-60), duration: 30.0)
        manager.registerChunk(url: chunk3, startTime: now.addingTimeInterval(-30), duration: 30.0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        var completed = false
        var exportedURL: URL? = nil
        manager.exportClip(offsetSeconds: 45.0) { url in
            exportedURL = url
            completed = true
        }

        let timeout = Date().addingTimeInterval(1.0)
        while !completed && Date() < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if !completed || exportedURL == nil {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Export clip timed out or returned nil URL"])
        }
    }

    static func testExportClip_avfoundationFallbackWhenFFmpegFails() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_export_test_\(UUID().uuidString)")

        let mockRunner = MockFFmpegRunner(ffmpegPathToReturn: nil, concatAndTrimResult: false)
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: mockRunner,
            metadataProvider: MockVideoMetadataProvider(defaultDuration: 30.0, isValid: true),
            chunksDirectory: tempDir
        )

        let chunk1 = tempDir.appendingPathComponent("chunk1.mp4")
        fileSystem.files[chunk1] = [.size: Int64(1000)]
        manager.registerChunk(url: chunk1, startTime: Date(), duration: 30.0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        var completed = false
        manager.exportClip(offsetSeconds: 30.0) { _ in
            completed = true
        }

        let timeout = Date().addingTimeInterval(1.5)
        while !completed && Date() < timeout {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if !completed {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Export completion was not invoked"])
        }
    }
}
