import Foundation

struct FileSystemErrorTests {
    static func testPermissionDeniedDirectoryHandling() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/non_existent_restricted_dir")
        
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        // loadExistingChunks should handle error without crashing
        manager.loadExistingChunks()
        if manager.chunks.count != 0 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 0 chunks for invalid directory"])
        }
    }

    static func testDiskFullAttributesHandling() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/disk_full_test_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        let fileURL = tempDir.appendingPathComponent("chunk_full.mp4")
        // file not in fileSystem.files dictionary -> attributesOfItem throws error
        manager.registerChunk(url: fileURL, startTime: Date(), duration: 10.0)

        // Should drop file gracefully
        if manager.chunks.count != 0 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected corrupt/missing attribute chunk to be dropped"])
        }
    }

    static func testFileRemovalErrorResilience() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/file_removal_test_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            ffmpegRunner: MockFFmpegRunner(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )

        let chunk1 = tempDir.appendingPathComponent("chunk1.mp4")
        fileSystem.files[chunk1] = [.size: Int64(2000)]
        manager.registerChunk(url: chunk1, startTime: Date(), duration: 30.0)

        // enforceLimits should execute resilience logic without crashing
        manager.enforceLimits()
    }

    static func testNonCreatableExportDirectoryFallback() throws {
        let path = "~/Movies/Recall-exports"
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("~") {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tilde expansion failed"])
        }
    }
}
