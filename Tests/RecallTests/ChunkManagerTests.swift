import Foundation
import Combine

struct ChunkManagerTests {
    private static func makeManager(
        fileSystem: MockFileSystem,
        directory: URL,
        config: StorageConfig = MockStorageConfig(),
        metadata: VideoMetadataProvider = MockVideoMetadataProvider(),
        legacy: URL? = nil
    ) -> ChunkManager {
        let manager = ChunkManager(config: config, fileSystem: fileSystem, metadataProvider: metadata, chunksDirectory: directory, legacyCacheDirectory: legacy)
        // Let the initial scan finish so files a test adds afterwards are only seen through registration.
        manager.syncQueue()
        return manager
    }

    static func testDirectoryCreation() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_dir_test_\(UUID().uuidString)")

        let manager = makeManager(fileSystem: fileSystem, directory: tempDir)
        manager.syncQueue()

        try check(fileSystem.createdDirectories.contains(tempDir), "Directory was not created at \(tempDir.path)")
    }

    static func testStorageDirectoryIsPrivateAndExcludedFromBackup() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_private_test_\(UUID().uuidString)")

        let manager = makeManager(fileSystem: fileSystem, directory: tempDir)
        manager.syncQueue()

        try check(fileSystem.permissionChanges[tempDir.path] == 0o700, "Expected chunk directory permissions 0700, got \(String(describing: fileSystem.permissionChanges[tempDir.path]))")
        try check(fileSystem.backupExclusions.contains(tempDir), "Expected chunk directory to be excluded from Time Machine")
    }

    static func testStorageDirectoryPermissionsOnDisk() throws {
        let directory = TestSandbox.makeDirectory("perm").appendingPathComponent("chunks.noindex")
        // Simulate a directory left world-readable by an earlier release.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])

        StorageDirectory.prepare(directory, fileSystem: FileManager.default)

        let permissions = (try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue
        try check(permissions == 0o700, "Expected 0700 on disk, got \(String(describing: permissions.map { String($0, radix: 8) }))")
        let excluded = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        try check(excluded == true, "Expected the directory to be excluded from backups")
    }

    static func testLoadExistingFiles_mp4AndIgnoreNonMp4() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let mp4URL = tempDir.appendingPathComponent("chunk_2026-10-03_12-00-00-000.mp4")
        let txtURL = tempDir.appendingPathComponent("notes.txt")

        fileSystem.setFile(mp4URL, attributes: [.size: Int64(1000)])
        fileSystem.setFile(txtURL, attributes: [.size: Int64(500)])

        let manager = makeManager(fileSystem: fileSystem, directory: tempDir)
        manager.syncQueue()

        try check(manager.chunks.count == 1 && manager.chunks.first?.url == mp4URL, "Expected 1 mp4 chunk indexed, got \(manager.chunks.count)")
    }

    static func testLoadExistingFiles_purgeCorrupt() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let corruptURL = tempDir.appendingPathComponent("chunk_corrupt.mp4")
        fileSystem.setFile(corruptURL, attributes: [.size: Int64(1000)])

        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, metadata: MockVideoMetadataProvider(defaultDuration: 0.0, isValid: false))
        manager.syncQueue()

        try check(fileSystem.removedURLs.contains(corruptURL), "Corrupt chunk was not purged on load")
    }

    static func testParseDateFromFilename() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        // Name written by an earlier release, in local time.
        let chunkURL = tempDir.appendingPathComponent("chunk_2026-10-03_14-30-00-000.mp4")
        fileSystem.setFile(chunkURL, attributes: [.size: Int64(1000)])

        let manager = makeManager(fileSystem: fileSystem, directory: tempDir)
        manager.syncQueue()

        guard let loaded = manager.chunks.first else {
            throw TestFailure(description: "Chunk failed to load")
        }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: loaded.startTime)
        try check(comps.year == 2026 && comps.month == 10 && comps.day == 3 && comps.hour == 14 && comps.minute == 30, "Parsed date components incorrect: \(comps)")
    }

    static func testChunkNamesUseUTC() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000.25)
        let name = ChunkNaming.fileName(for: date)
        try check(name.hasPrefix("chunk_") && name.hasSuffix("Z.mp4"), "Unexpected chunk name \(name)")

        let parsed = ChunkNaming.startDate(from: URL(fileURLWithPath: "/tmp/\(name)"))
        try check(parsed.map { abs($0.timeIntervalSince(date)) < 0.002 } == true, "UTC name did not round-trip: \(name) -> \(String(describing: parsed))")

        let partial = ChunkNaming.partialURL(for: URL(fileURLWithPath: "/tmp/\(name)"))
        try check(ChunkNaming.isPartial(partial) && !ChunkNaming.isChunk(partial), "Partial chunk must not look finished: \(partial.lastPathComponent)")
        try check(ChunkNaming.startDate(from: partial).map { abs($0.timeIntervalSince(date)) < 0.002 } == true, "Partial name did not parse")
    }

    static func testFallbackCreationDate() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let chunkURL = tempDir.appendingPathComponent("custom_video.mp4")
        let creationDate = Date().addingTimeInterval(-3600)
        fileSystem.setFile(chunkURL, attributes: [.size: Int64(1000), .creationDate: creationDate])

        let manager = makeManager(fileSystem: fileSystem, directory: tempDir)
        manager.syncQueue()

        guard let loaded = manager.chunks.first else {
            throw TestFailure(description: "Chunk failed to load")
        }
        try check(abs(loaded.startTime.timeIntervalSince(creationDate)) < 1.0, "Fallback date mismatch")
    }

    static func testManifestSkipsValidationOnRelaunch() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_manifest_\(UUID().uuidString)")
        let first = makeManager(fileSystem: fileSystem, directory: tempDir)
        first.syncQueue()

        let now = Date()
        for index in 0..<3 {
            let url = tempDir.appendingPathComponent(ChunkNaming.fileName(for: now.addingTimeInterval(Double(index) * 10)))
            fileSystem.setFile(url, attributes: [.size: Int64(1000 + index)])
            first.registerChunk(url: url, startTime: now.addingTimeInterval(Double(index) * 10), duration: 10)
        }
        first.syncQueue()

        let counting = CountingMetadataProvider()
        let relaunched = makeManager(fileSystem: fileSystem, directory: tempDir, metadata: counting)
        relaunched.syncQueue()

        try check(relaunched.chunks.count == 3, "Expected 3 chunks after relaunch, got \(relaunched.chunks.count)")
        try check(counting.count == 0, "Indexed chunks should not be re-validated on launch, validated \(counting.count)")
        try check(relaunched.chunks.map(\.startTime) == first.chunks.map(\.startTime), "Manifest start times differ")
    }

    static func testUnindexedChunkIsValidated() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_unindexed_\(UUID().uuidString)")
        fileSystem.setFile(tempDir.appendingPathComponent(ChunkNaming.fileName(for: Date())), attributes: [.size: Int64(1000)])

        let counting = CountingMetadataProvider()
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, metadata: counting)
        manager.syncQueue()

        try check(counting.count == 1 && manager.chunks.count == 1, "Expected the unindexed chunk to be validated and kept")
    }

    static func testInterruptedPartialChunkIsRecovered() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_partial_\(UUID().uuidString)")
        let finalURL = tempDir.appendingPathComponent(ChunkNaming.fileName(for: Date()))
        let partialURL = ChunkNaming.partialURL(for: finalURL)
        fileSystem.setFile(partialURL, attributes: [.size: Int64(4000)])

        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, metadata: MockVideoMetadataProvider(defaultDuration: 4.0, isValid: true))
        manager.syncQueue()

        try check(manager.chunks.first?.url == finalURL, "Expected the partial chunk to be recovered as \(finalURL.lastPathComponent)")
        try check(manager.chunks.first?.duration == 4.0, "Recovered chunk should use its readable duration")
        try check(!fileSystem.fileExists(atPath: partialURL.path), "Partial file should have been renamed")
    }

    static func testUnreadablePartialChunkIsRemoved() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_partial_bad_\(UUID().uuidString)")
        let finalURL = tempDir.appendingPathComponent(ChunkNaming.fileName(for: Date()))
        fileSystem.setFile(ChunkNaming.partialURL(for: finalURL), attributes: [.size: Int64(4000)])

        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, metadata: MockVideoMetadataProvider(defaultDuration: 0, isValid: false))
        manager.syncQueue()

        try check(manager.chunks.isEmpty, "Unreadable partial chunk must not be indexed")
        try check(fileSystem.removedURLs.contains(finalURL), "Unreadable partial chunk should be deleted")
    }

    static func testLegacyChunksAreMigrated() throws {
        let fileSystem = MockFileSystem()
        let legacy = URL(fileURLWithPath: "/tmp/recall_legacy_\(UUID().uuidString)")
        let tempDir = URL(fileURLWithPath: "/tmp/recall_new_\(UUID().uuidString)/chunks.noindex")
        let legacyChunk = legacy.appendingPathComponent("chunks/chunk_2026-10-03_14-30-00-000.mp4")
        let emptyChunk = legacy.appendingPathComponent("chunks/chunk_2026-10-03_14-30-10-000.mp4")
        fileSystem.setFile(legacyChunk, attributes: [.size: Int64(1000)])
        fileSystem.setFile(emptyChunk, attributes: [.size: Int64(0)])
        fileSystem.setFile(legacy.appendingPathComponent("recall_debug.log"), attributes: [.size: Int64(10)])

        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, legacy: legacy)
        manager.syncQueue()

        let migrated = tempDir.appendingPathComponent(legacyChunk.lastPathComponent)
        try check(manager.chunks.map(\.url) == [migrated], "Expected the legacy chunk to be migrated, got \(manager.chunks.map(\.url.lastPathComponent))")
        try check(fileSystem.removedURLs.contains(emptyChunk), "Empty legacy chunk should be deleted")
        try check(fileSystem.removedURLs.contains(legacy.appendingPathComponent("recall_debug.log")), "Legacy log should be deleted")
    }

    static func testSortOrder() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir)
        manager.syncQueue()

        let now = Date()
        let urlLater = tempDir.appendingPathComponent("chunk_later.mp4")
        let urlEarlier = tempDir.appendingPathComponent("chunk_earlier.mp4")
        fileSystem.setFile(urlLater, attributes: [.size: Int64(100)])
        fileSystem.setFile(urlEarlier, attributes: [.size: Int64(100)])

        manager.registerChunk(url: urlLater, startTime: now.addingTimeInterval(-30), duration: 30)
        manager.registerChunk(url: urlEarlier, startTime: now.addingTimeInterval(-60), duration: 30)
        manager.syncQueue()

        try check(manager.chunks.map(\.url) == [urlEarlier, urlLater], "Chunks not sorted by startTime ascending")
    }

    static func testDuplicateRegistrationCountedOnce() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_dup_\(UUID().uuidString)")
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, metadata: MockVideoMetadataProvider(defaultDuration: 10, isValid: true))

        let url = tempDir.appendingPathComponent("chunk_dup.mp4")
        fileSystem.setFile(url, attributes: [.size: Int64(100)])
        manager.registerChunk(url: url, startTime: Date(), duration: 10)
        manager.registerChunk(url: url, startTime: Date(), duration: 10)
        manager.syncQueue()

        try check(manager.chunks.count == 1, "Expected a chunk registered twice to be indexed once")
        try check(manager.usage == ChunkUsage(count: 1, totalBytes: 100, totalDuration: 10), "Usage double-counted: \(manager.usage)")
    }

    static func testTotalDurationCalculation() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, metadata: MockVideoMetadataProvider(defaultDuration: 0.0, isValid: true))

        let url1 = tempDir.appendingPathComponent("c1.mp4")
        let url2 = tempDir.appendingPathComponent("c2.mp4")
        fileSystem.setFile(url1, attributes: [.size: Int64(100)])
        fileSystem.setFile(url2, attributes: [.size: Int64(100)])

        manager.registerChunk(url: url1, startTime: Date().addingTimeInterval(-60), duration: 30.0)
        manager.registerChunk(url: url2, startTime: Date().addingTimeInterval(-30), duration: 45.0)
        manager.syncQueue()

        try check(abs(manager.totalRecordedDuration - 75.0) < 0.1, "Expected total duration 75.0, got \(manager.totalRecordedDuration)")
        try check(manager.usage.count == 2 && manager.usage.totalBytes == 200, "Unexpected usage \(manager.usage)")
    }

    static func testUsageReadsDoNotWaitForDiskWork() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_nonblocking_\(UUID().uuidString)")
        let slow = CountingMetadataProvider()
        slow.delay = 0.8
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, metadata: slow)
        manager.syncQueue()

        let url = tempDir.appendingPathComponent("slow.mp4")
        fileSystem.setFile(url, attributes: [.size: Int64(100)])
        manager.registerChunk(url: url, startTime: Date(), duration: 10)  // occupies the queue for 0.8s
        Thread.sleep(forTimeInterval: 0.05)

        let started = Date()
        _ = manager.usage
        _ = manager.totalRecordedDuration
        let elapsed = Date().timeIntervalSince(started)
        try check(elapsed < 0.2, "Reading usage blocked behind disk work for \(elapsed)s")
        manager.syncQueue()
    }

    static func testUsagePublisherEmitsOnMainThread() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_publisher_\(UUID().uuidString)")
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, metadata: MockVideoMetadataProvider(defaultDuration: 10, isValid: true))

        var received: [ChunkUsage] = []
        var allOnMain = true
        let subscription = manager.usagePublisher.sink { usage in
            allOnMain = allOnMain && Thread.isMainThread
            received.append(usage)
        }
        defer { subscription.cancel() }

        let url = tempDir.appendingPathComponent("published.mp4")
        fileSystem.setFile(url, attributes: [.size: Int64(100)])
        manager.registerChunk(url: url, startTime: Date(), duration: 10)

        try check(waitUntil { received.last?.count == 1 }, "Expected a usage update with 1 chunk, got \(received)")
        try check(allOnMain, "Usage updates must arrive on the main thread")
    }

    static func testEnforceLimits_purgesOldestWhenOverSizeBytes() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_chunks_\(UUID().uuidString)")
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, config: MockStorageConfig(maxBufferSizeBytes: 200, maxStorageDurationSeconds: 10000))

        let chunk1URL = tempDir.appendingPathComponent("chunk_2026-10-03_10-00-00-000.mp4")
        let chunk2URL = tempDir.appendingPathComponent("chunk_2026-10-03_10-01-00-000.mp4")
        fileSystem.setFile(chunk1URL, attributes: [.size: Int64(150)])
        fileSystem.setFile(chunk2URL, attributes: [.size: Int64(100)])

        manager.registerChunk(url: chunk1URL, startTime: Date().addingTimeInterval(-120), duration: 30.0)
        manager.registerChunk(url: chunk2URL, startTime: Date().addingTimeInterval(-60), duration: 30.0)
        manager.syncQueue()

        try check(fileSystem.removedURLs.contains(chunk1URL), "Oldest chunk was not removed when over size limit")
        try check(manager.chunks.map(\.url) == [chunk2URL], "Expected only the newest chunk to remain")
    }

    static func testEnforceLimits_purgesOldestWhenOverDuration() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_chunks_\(UUID().uuidString)")
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, config: MockStorageConfig(maxBufferSizeBytes: 100000000, maxStorageDurationSeconds: 40.0))

        let chunk1URL = tempDir.appendingPathComponent("chunk1.mp4")
        let chunk2URL = tempDir.appendingPathComponent("chunk2.mp4")
        fileSystem.setFile(chunk1URL, attributes: [.size: Int64(100)])
        fileSystem.setFile(chunk2URL, attributes: [.size: Int64(100)])

        manager.registerChunk(url: chunk1URL, startTime: Date().addingTimeInterval(-60), duration: 30.0)
        manager.registerChunk(url: chunk2URL, startTime: Date().addingTimeInterval(-30), duration: 30.0)
        manager.syncQueue()

        try check(fileSystem.removedURLs.contains(chunk1URL), "Oldest chunk was not removed when over duration limit")
    }

    static func testEnforceLimits_multiChunkSequentialPurge() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, config: MockStorageConfig(maxBufferSizeBytes: 100, maxStorageDurationSeconds: 10000))
        manager.syncQueue()

        let c1 = tempDir.appendingPathComponent("c1.mp4")
        let c2 = tempDir.appendingPathComponent("c2.mp4")
        let c3 = tempDir.appendingPathComponent("c3.mp4")
        for url in [c1, c2, c3] {
            fileSystem.setFile(url, attributes: [.size: Int64(80)])
        }

        manager.registerChunk(url: c1, startTime: Date().addingTimeInterval(-90), duration: 30)
        manager.registerChunk(url: c2, startTime: Date().addingTimeInterval(-60), duration: 30)
        manager.registerChunk(url: c3, startTime: Date().addingTimeInterval(-30), duration: 30)
        manager.syncQueue()

        try check(fileSystem.removedURLs.contains(c1) && fileSystem.removedURLs.contains(c2), "Sequential multi-chunk purge failed")
        try check(manager.chunks.map(\.url) == [c3], "Remaining chunks list incorrect")
    }

    static func testEnforceLimitsKeepsChunksAnExportIsReading() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_pin_\(UUID().uuidString)")
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, config: MockStorageConfig(maxBufferSizeBytes: 150, maxStorageDurationSeconds: 10000))

        let c1 = tempDir.appendingPathComponent("c1.mp4")
        let c2 = tempDir.appendingPathComponent("c2.mp4")
        fileSystem.setFile(c1, attributes: [.size: Int64(100)])
        fileSystem.setFile(c2, attributes: [.size: Int64(100)])
        manager.registerChunk(url: c1, startTime: Date().addingTimeInterval(-60), duration: 30)
        manager.syncQueue()

        let pinned = [ExportSegment(url: c1, start: 0, end: 30)]
        manager.pin(pinned)
        manager.registerChunk(url: c2, startTime: Date().addingTimeInterval(-30), duration: 30)
        manager.syncQueue()
        try check(!fileSystem.removedURLs.contains(c1), "A chunk being exported must not be purged")

        manager.unpin(pinned)
        manager.enforceLimits()
        manager.syncQueue()
        try check(fileSystem.removedURLs.contains(c1), "The chunk should be purged once the export releases it")
    }

    static func testEnforceLimits_zeroLimitHandling() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, config: MockStorageConfig(maxBufferSizeBytes: 0, maxStorageDurationSeconds: 0))
        manager.enforceLimits()
        manager.syncQueue()
        try check(manager.chunks.isEmpty, "Expected no chunks")
    }

    static func testPurgeAllChunks_removesAllRegisteredFiles() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_chunks_\(UUID().uuidString)")
        let chunk1URL = tempDir.appendingPathComponent("chunk1.mp4")
        fileSystem.setFile(chunk1URL, attributes: [.size: Int64(100)])

        let manager = makeManager(fileSystem: fileSystem, directory: tempDir)
        manager.purgeAllChunks()
        manager.syncQueue()

        try check(fileSystem.removedURLs.contains(chunk1URL) && manager.chunks.isEmpty, "Chunk was not purged")
        try check(manager.usage == ChunkUsage(), "Usage should be empty after a purge")
    }

    static func testPurgeLeavesChunkInProgressToRecorder() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_purge_partial_\(UUID().uuidString)")
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir)
        manager.syncQueue()

        let inProgress = ChunkNaming.partialURL(for: tempDir.appendingPathComponent(ChunkNaming.fileName(for: Date())))
        fileSystem.setFile(inProgress, attributes: [.size: Int64(100)])
        manager.purgeAllChunks()
        manager.syncQueue()

        try check(!fileSystem.removedURLs.contains(inProgress), "Purge must not delete the file the writer has open")
    }

    static func testRegisterZeroByteChunk() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir)

        let zeroURL = tempDir.appendingPathComponent("zero.mp4")
        fileSystem.setFile(zeroURL, attributes: [.size: Int64(0)])
        manager.registerChunk(url: zeroURL, startTime: Date(), duration: 30)
        manager.syncQueue()

        try check(fileSystem.removedURLs.contains(zeroURL) && manager.chunks.isEmpty, "0-byte chunk was not purged on register")
    }

    static func testRegisterCorruptChunk() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_test_\(UUID().uuidString)")
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, metadata: MockVideoMetadataProvider(defaultDuration: 0.0, isValid: false))

        let corruptURL = tempDir.appendingPathComponent("corrupt.mp4")
        fileSystem.setFile(corruptURL, attributes: [.size: Int64(500)])
        manager.registerChunk(url: corruptURL, startTime: Date(), duration: 30)
        manager.syncQueue()

        try check(fileSystem.removedURLs.contains(corruptURL) && manager.chunks.isEmpty, "Corrupt chunk was not purged on register")
    }

    static func testWhenLoadedRunsAfterInitialIndexing() throws {
        let fileSystem = MockFileSystem()
        let tempDir = URL(fileURLWithPath: "/tmp/recall_loaded_\(UUID().uuidString)")
        fileSystem.setFile(tempDir.appendingPathComponent(ChunkNaming.fileName(for: Date())), attributes: [.size: Int64(100)])
        let slow = CountingMetadataProvider()
        slow.delay = 0.2
        let manager = makeManager(fileSystem: fileSystem, directory: tempDir, metadata: slow)

        var countWhenLoaded = -1
        manager.whenLoaded {
            countWhenLoaded = manager.chunks.count
        }
        try check(waitUntil { countWhenLoaded >= 0 }, "whenLoaded never ran")
        try check(countWhenLoaded == 1, "whenLoaded ran before indexing finished")
    }
}
