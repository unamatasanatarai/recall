import Foundation

struct ConcurrencyTests {
    private static func makeManager(_ fileSystem: MockFileSystem, _ tempDir: URL, duration: TimeInterval = 10.0) -> ChunkManager {
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: fileSystem,
            metadataProvider: MockVideoMetadataProvider(defaultDuration: duration, isValid: true),
            chunksDirectory: tempDir
        )
        manager.syncQueue()
        return manager
    }

    static func testConcurrentRegisterChunk() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_concurrency_\(UUID().uuidString)")
        let manager = makeManager(fileSystem, tempDir)
        let base = Date()

        DispatchQueue.concurrentPerform(iterations: 20) { i in
            let fileURL = tempDir.appendingPathComponent("chunk_\(i).mp4")
            fileSystem.setFile(fileURL, attributes: [.size: Int64(1000)])
            manager.registerChunk(url: fileURL, startTime: base.addingTimeInterval(Double(i) * 10), duration: 10.0)
        }
        manager.syncQueue()

        let chunks = manager.chunks
        try check(chunks.count == 20, "Expected 20 chunks, got \(chunks.count)")
        try check(zip(chunks, chunks.dropFirst()).allSatisfy { $0.startTime <= $1.startTime }, "Chunks must stay sorted")
        try check(manager.usage == ChunkUsage(count: 20, totalBytes: 20_000, totalDuration: 200), "Unexpected usage \(manager.usage)")
    }

    static func testReadsWhileWriting() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_concurrency_reads_\(UUID().uuidString)")
        let manager = makeManager(fileSystem, tempDir)

        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            for i in 0..<50 {
                let fileURL = tempDir.appendingPathComponent("chunk_\(i).mp4")
                fileSystem.setFile(fileURL, attributes: [.size: Int64(100)])
                manager.registerChunk(url: fileURL, startTime: Date(), duration: 10)
            }
        }
        // The settings window and the drag gesture read from the main thread while chunks arrive.
        for _ in 0..<500 {
            let usage = manager.usage
            let snapshot = manager.chunks
            try check(usage.count >= 0 && snapshot.count >= 0, "Unreachable")
        }
        group.wait()
        manager.syncQueue()
        try check(manager.chunks.count == 50, "Expected 50 chunks, got \(manager.chunks.count)")
    }

    static func testConcurrentPurgeAndLimitEnforcement() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_concurrency_purge_\(UUID().uuidString)")
        let manager = makeManager(fileSystem, tempDir)

        DispatchQueue.concurrentPerform(iterations: 11) { i in
            if i == 10 {
                manager.purgeAllChunks()
                return
            }
            let fileURL = tempDir.appendingPathComponent("chunk_\(i).mp4")
            fileSystem.setFile(fileURL, attributes: [.size: Int64(1000)])
            manager.registerChunk(url: fileURL, startTime: Date(), duration: 10.0)
            manager.enforceLimits()
        }
        manager.syncQueue()

        try check(manager.usage == ChunkUsage(chunks: manager.chunks), "Usage must always match the indexed chunks")
    }

    static func testThreadSafeDurationAccess() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_concurrency_duration_\(UUID().uuidString)")
        let manager = makeManager(fileSystem, tempDir, duration: 15.0)

        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            _ = manager.totalRecordedDuration
        }
        manager.syncQueue()
        try check(manager.totalRecordedDuration == 0, "Expected an empty store")
    }
}
