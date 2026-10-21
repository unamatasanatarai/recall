import Foundation
import AVFoundation

struct ChunkManagerExportTests {
    private static func export(_ manager: ChunkManager, footage: TimeInterval, endDate: Date) throws -> Result<URL, ExportError> {
        var result: Result<URL, ExportError>?
        manager.exportClip(ExportRequest(footageSeconds: footage, endDate: endDate)) { result = $0 }
        try check(waitUntil(timeout: 20) { result != nil }, "Export did not complete")
        return result!
    }

    /// Three consecutive 2 s chunks on disk, registered with a real chunk manager.
    private static func makeRecordedManager(exportsDirectory: URL, exportSessionFactory: @escaping (AVAsset, String) -> AVAssetExportSession? = { AVAssetExportSession(asset: $0, presetName: $1) }) throws -> (ChunkManager, [ChunkWriter.FinishedChunk]) {
        let chunksDirectory = TestSandbox.makeDirectory("export_chunks")
        let manager = ChunkManager(
            config: MockStorageConfig(exportsDirectoryURL: exportsDirectory),
            fileSystem: FileManager.default,
            exportSessionFactory: exportSessionFactory,
            chunksDirectory: chunksDirectory
        )
        // The initial scan must finish before chunks are written, or it would treat them as crash leftovers.
        manager.syncQueue()
        let firstStart = Date().addingTimeInterval(-60)
        var chunks: [ChunkWriter.FinishedChunk] = []
        for index in 0..<3 {
            let chunk = try TestMedia.writeChunk(in: chunksDirectory, startDate: firstStart.addingTimeInterval(Double(index) * 2), duration: 2.0)
            manager.registerChunk(url: chunk.url, startTime: chunk.startDate, duration: chunk.duration)
            chunks.append(chunk)
        }
        manager.syncQueue()
        try check(manager.chunks.count == 3, "Expected 3 indexed chunks, got \(manager.chunks.count)")
        return (manager, chunks)
    }

    static func testExportClip_emptyChunkGuard() throws {
        let manager = ChunkManager(
            config: MockStorageConfig(),
            fileSystem: MockFileSystem(),
            metadataProvider: MockVideoMetadataProvider(),
            chunksDirectory: URL(fileURLWithPath: "/tmp/recall_export_test_\(UUID().uuidString)")
        )

        let result = try export(manager, footage: 30, endDate: Date())
        try check(result == .failure(.noFootage), "Expected .noFootage when the store is empty, got \(result)")
    }

    static func testExportClip_passthroughTrimsHeadAndTail() throws {
        let exportsDirectory = TestSandbox.makeDirectory("exports")
        let (manager, chunks) = try makeRecordedManager(exportsDirectory: exportsDirectory)

        // End 0.5 s into the last chunk (the moment the drag started) and take 3 s of footage.
        let endDate = chunks[2].startDate.addingTimeInterval(0.5)
        let result = try export(manager, footage: 3.0, endDate: endDate)
        let url = try result.get()

        try check(url.deletingLastPathComponent().standardizedFileURL == exportsDirectory.standardizedFileURL, "Export written outside the exports directory: \(url.path)")
        try check(url.lastPathComponent.hasPrefix("Recall_") && url.pathExtension == "mp4", "Unexpected export name \(url.lastPathComponent)")
        let duration = TestMedia.duration(of: url)
        try check(abs(duration - 3.0) < 0.15, "Expected a 3.0 s clip, got \(duration) s")
    }

    static func testExportClip_reencodesWhenPassthroughUnavailable() throws {
        var presetsRequested: [String] = []
        let exportsDirectory = TestSandbox.makeDirectory("exports_fallback")
        let (manager, chunks) = try makeRecordedManager(exportsDirectory: exportsDirectory) { asset, preset in
            presetsRequested.append(preset)
            return preset == AVAssetExportPresetPassthrough ? nil : AVAssetExportSession(asset: asset, presetName: preset)
        }

        let result = try export(manager, footage: 1.5, endDate: chunks[2].startDate.addingTimeInterval(2.0))
        let url = try result.get()

        try check(presetsRequested == [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality], "Unexpected presets \(presetsRequested)")
        try check(abs(TestMedia.duration(of: url) - 1.5) < 0.2, "Re-encoded clip has the wrong duration")
    }

    static func testExportClip_failsWhenNoExportSessionAvailable() throws {
        let exportsDirectory = TestSandbox.makeDirectory("exports_none")
        let (manager, chunks) = try makeRecordedManager(exportsDirectory: exportsDirectory) { _, _ in nil }

        let result = try export(manager, footage: 2, endDate: chunks[2].startDate.addingTimeInterval(2.0))
        guard case .failure(.failed) = result else {
            throw TestFailure(description: "Expected a .failed result, got \(result)")
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: exportsDirectory.path)
        try check(leftovers.isEmpty, "A failed export must not leave files behind: \(leftovers)")
    }

    static func testExportClip_neverOverwritesEarlierExport() throws {
        let exportsDirectory = TestSandbox.makeDirectory("exports_unique")
        let (manager, chunks) = try makeRecordedManager(exportsDirectory: exportsDirectory)
        let endDate = chunks[2].startDate.addingTimeInterval(2.0)

        let first = try export(manager, footage: 1, endDate: endDate).get()
        let second = try export(manager, footage: 1, endDate: endDate).get()

        try check(first != second, "Second export reused the first export's name")
        try check(second.deletingPathExtension().lastPathComponent == first.deletingPathExtension().lastPathComponent + "-2", "Unexpected second name \(second.lastPathComponent)")
        try check(FileManager.default.fileExists(atPath: first.path) && FileManager.default.fileExists(atPath: second.path), "Both exports should exist")
    }

    static func testExportClip_reportsUnwritableExportDirectory() throws {
        // A folder that cannot exist (say an unmounted drive) must produce a reported failure.
        let (manager, chunks) = try makeRecordedManager(exportsDirectory: URL(fileURLWithPath: "/dev/null/Recall-exports"))
        let result = try export(manager, footage: 2, endDate: chunks[2].startDate.addingTimeInterval(2.0))
        guard case .failure(.failed) = result else {
            throw TestFailure(description: "Expected a reported failure for an unwritable export folder, got \(result)")
        }
    }

    static func testExportClip_skipsUnreadableChunks() throws {
        let exportsDirectory = TestSandbox.makeDirectory("exports_unreadable")
        let fileSystem = MockFileSystem()
        let chunksDirectory = URL(fileURLWithPath: "/tmp/recall_unreadable_\(UUID().uuidString)")
        let manager = ChunkManager(
            config: MockStorageConfig(exportsDirectoryURL: exportsDirectory),
            fileSystem: fileSystem,
            metadataProvider: MockVideoMetadataProvider(defaultDuration: 10, isValid: true),
            chunksDirectory: chunksDirectory
        )
        manager.syncQueue()
        let url = chunksDirectory.appendingPathComponent("missing_on_disk.mp4")
        fileSystem.setFile(url, attributes: [.size: Int64(100)])
        manager.registerChunk(url: url, startTime: Date().addingTimeInterval(-10), duration: 10)
        manager.syncQueue()

        let result = try export(manager, footage: 5, endDate: Date())
        guard case .failure(.failed) = result else {
            throw TestFailure(description: "Expected a .failed result for unreadable chunks, got \(result)")
        }
    }
}
