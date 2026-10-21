import Foundation

struct FileSystemErrorTests {
    static func testPermissionDeniedDirectoryHandling() throws {
        let fileSystem = MockFileSystem()
        let directory = URL(fileURLWithPath: "/non_existent_restricted_dir")
        fileSystem.failingDirectories = [directory.path]
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: directory
        )

        // An unreadable directory must leave an empty, consistent index rather than crash.
        manager.loadExistingChunks()
        manager.syncQueue()
        try check(manager.chunks.isEmpty && manager.usage == ChunkUsage(), "Expected an empty index for an unreadable directory")

        // Purging an unreadable directory must not throw either.
        manager.purgeAllChunks()
        manager.syncQueue()
        try check(manager.chunks.isEmpty, "Expected an empty index after purging")
    }

    static func testDiskFullAttributesHandling() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/disk_full_test_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )
        manager.syncQueue()

        // file not in fileSystem.files dictionary -> attributesOfItem throws error
        manager.registerChunk(url: tempDir.appendingPathComponent("chunk_full.mp4"), startTime: Date(), duration: 10.0)
        manager.syncQueue()

        try check(manager.chunks.isEmpty, "Expected corrupt/missing attribute chunk to be dropped")
    }

    static func testFileRemovalErrorResilience() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/file_removal_test_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(maxBufferSizeBytes: 100, maxStorageDurationSeconds: 3600),
            fileSystem: fileSystem,
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: tempDir
        )
        manager.syncQueue()

        let chunk1 = tempDir.appendingPathComponent("chunk1.mp4")
        fileSystem.setFile(chunk1, attributes: [.size: Int64(2000)])
        manager.registerChunk(url: chunk1, startTime: Date(), duration: 30.0)
        manager.enforceLimits()
        manager.syncQueue()

        try check(manager.chunks.isEmpty, "An oversized chunk should be purged")
    }
}
