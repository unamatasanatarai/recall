import Foundation
import AVFoundation
import Combine

struct ChunkFile: Equatable {
    let url: URL
    let startTime: Date
    let duration: TimeInterval
    let sizeBytes: Int64
}

final class ChunkManager: ChunkStore, @unchecked Sendable {
    static let shared = ChunkManager()

    let chunksDirectory: URL
    private let manifestURL: URL
    private let legacyCacheDirectory: URL?

    // Serializes disk work and every mutation. Readers never wait on it; they take `lock`.
    private let queue = DispatchQueue(label: "com.recall.chunkmanager", qos: .userInitiated)
    private let exportQueue = DispatchQueue(label: "com.recall.chunkmanager.export", qos: .userInitiated)

    private let lock = NSLock()
    private var storedChunks: [ChunkFile] = []   // guarded by lock, sorted by startTime
    private var storedUsage = ChunkUsage()       // guarded by lock
    private var pinCounts: [URL: Int] = [:]      // guarded by lock; chunks an export is reading

    private let usageSubject = CurrentValueSubject<ChunkUsage, Never>(ChunkUsage())

    private let config: StorageConfig
    private let fileSystem: FileSystemProvider
    private let metadataProvider: VideoMetadataProvider
    private let exportSessionFactory: (AVAsset, String) -> AVAssetExportSession?

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    init(
        config: StorageConfig = SettingsManager.shared,
        fileSystem: FileSystemProvider = FileManager.default,
        metadataProvider: VideoMetadataProvider = DefaultVideoMetadataProvider(),
        exportSessionFactory: @escaping (AVAsset, String) -> AVAssetExportSession? = { AVAssetExportSession(asset: $0, presetName: $1) },
        chunksDirectory: URL? = nil,
        legacyCacheDirectory: URL? = nil
    ) {
        self.config = config
        self.fileSystem = fileSystem
        self.metadataProvider = metadataProvider
        self.exportSessionFactory = exportSessionFactory

        if let overrideDir = chunksDirectory {
            self.chunksDirectory = overrideDir
            self.legacyCacheDirectory = legacyCacheDirectory
        } else {
            self.chunksDirectory = ConfigManager.shared.defaultChunksDirectory
            self.legacyCacheDirectory = legacyCacheDirectory ?? ConfigManager.shared.legacyCacheDirectory
        }
        self.manifestURL = self.chunksDirectory.appendingPathComponent("manifest.json")

        loadExistingChunks()
    }

    // MARK: - Reading

    /// Snapshot of the indexed chunks, oldest first.
    var chunks: [ChunkFile] {
        return lock.withCriticalSection { storedChunks }
    }

    var usage: ChunkUsage {
        return lock.withCriticalSection { storedUsage }
    }

    var usagePublisher: AnyPublisher<ChunkUsage, Never> {
        return usageSubject.eraseToAnyPublisher()
    }

    func footageStartDate(footageSeconds: TimeInterval, endingAt endDate: Date) -> Date? {
        return lock.withCriticalSection {
            ExportPlanner.footageStart(chunks: storedChunks, footageSeconds: footageSeconds, endingAt: endDate)
        }
    }

    func whenLoaded(_ completion: @escaping () -> Void) {
        // The initial load was queued in init, so anything queued now runs after it.
        queue.async {
            DispatchQueue.main.async(execute: completion)
        }
    }

    // MARK: - Indexing

    func loadExistingChunks() {
        queue.async {
            StorageDirectory.prepare(self.chunksDirectory, fileSystem: self.fileSystem)
            if let legacy = self.legacyCacheDirectory {
                LegacyStorageMigration.migrate(from: legacy, to: self.chunksDirectory, fileSystem: self.fileSystem)
            }

            guard let files = try? self.fileSystem.contentsOfDirectory(at: self.chunksDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: []) else {
                self.replaceChunks([])
                return
            }

            let manifest = self.readManifest()
            var loaded: [ChunkFile] = []
            var validatedCount = 0
            for file in files {
                if ChunkNaming.isPartial(file) {
                    if let recovered = self.recoverPartialChunk(file) {
                        loaded.append(recovered)
                    }
                    continue
                }
                guard ChunkNaming.isChunk(file) else { continue }

                let attrs = (try? self.fileSystem.attributesOfItem(atPath: file.path)) ?? [:]
                let size = (attrs[.size] as? Int64) ?? 0
                if size == 0 {
                    try? self.fileSystem.removeItem(at: file)
                    continue
                }

                if let entry = manifest[file.lastPathComponent], entry.size == size {
                    loaded.append(ChunkFile(url: file, startTime: entry.start, duration: entry.duration, sizeBytes: size))
                    continue
                }

                // Not indexed yet (written by an earlier release, or just before a crash).
                let meta = self.metadataProvider.durationAndIsValid(for: file)
                guard meta.isValid else {
                    Log.storage.notice("Removing corrupt chunk \(file.lastPathComponent, privacy: .public)")
                    try? self.fileSystem.removeItem(at: file)
                    continue
                }
                validatedCount += 1
                let startTime = ChunkNaming.startDate(from: file) ?? (attrs[.creationDate] as? Date) ?? Date()
                loaded.append(ChunkFile(url: file, startTime: startTime, duration: meta.duration, sizeBytes: size))
            }

            Log.storage.notice("Indexed \(loaded.count) chunks (\(validatedCount) validated from disk)")
            self.replaceChunks(loaded.sorted(by: { $0.startTime < $1.startTime }))
            self.enforceLimitsOnQueue()
        }
    }

    /// A `.partial` chunk left behind by a crash. Fragmented writing keeps everything up to the
    /// last fragment playable, so it is kept if AVFoundation can read it.
    private func recoverPartialChunk(_ partialURL: URL) -> ChunkFile? {
        let finalURL = partialURL.deletingPathExtension()
        guard !fileSystem.fileExists(atPath: finalURL.path),
              (try? fileSystem.moveItem(at: partialURL, to: finalURL)) != nil else {
            try? fileSystem.removeItem(at: partialURL)
            return nil
        }

        let size = ((try? fileSystem.attributesOfItem(atPath: finalURL.path))?[.size] as? Int64) ?? 0
        let meta = metadataProvider.durationAndIsValid(for: finalURL)
        guard size > 0, meta.isValid else {
            try? fileSystem.removeItem(at: finalURL)
            return nil
        }

        Log.storage.notice("Recovered interrupted chunk \(finalURL.lastPathComponent, privacy: .public)")
        let startTime = ChunkNaming.startDate(from: finalURL) ?? Date()
        return ChunkFile(url: finalURL, startTime: startTime, duration: meta.duration, sizeBytes: size)
    }

    func registerChunk(url: URL, startTime: Date, duration passedDuration: TimeInterval) {
        queue.async {
            let attrs = (try? self.fileSystem.attributesOfItem(atPath: url.path)) ?? [:]
            let size = (attrs[.size] as? Int64) ?? 0

            guard size > 0 else {
                try? self.fileSystem.removeItem(at: url)
                return
            }

            let meta = self.metadataProvider.durationAndIsValid(for: url)
            guard meta.isValid else {
                Log.storage.error("Dropping corrupt chunk \(url.lastPathComponent, privacy: .public)")
                try? self.fileSystem.removeItem(at: url)
                return
            }

            let actualDuration = meta.duration > 0 ? meta.duration : passedDuration
            self.insert(ChunkFile(url: url, startTime: startTime, duration: actualDuration, sizeBytes: size))
            self.enforceLimitsOnQueue()
        }
    }

    private func insert(_ chunk: ChunkFile) {
        lock.withCriticalSection {
            // A chunk registered twice must not be counted twice.
            storedChunks.removeAll { $0.url == chunk.url }
            // Chunks arrive in order, so this is almost always an append.
            let index = storedChunks.lastIndex { $0.startTime <= chunk.startTime }.map { $0 + 1 } ?? 0
            storedChunks.insert(chunk, at: index)
            storedUsage = ChunkUsage(chunks: storedChunks)
        }
    }

    private func replaceChunks(_ chunks: [ChunkFile]) {
        lock.withCriticalSection {
            storedChunks = chunks
            storedUsage = ChunkUsage(chunks: chunks)
        }
    }

    // MARK: - Retention

    func purgeAllChunks() {
        queue.async {
            let files = (try? self.fileSystem.contentsOfDirectory(at: self.chunksDirectory, includingPropertiesForKeys: nil, options: [])) ?? []
            var count = 0
            // The `.partial` chunk in progress belongs to the recorder, which discards it itself.
            for file in files where ChunkNaming.isChunk(file) {
                try? self.fileSystem.removeItem(at: file)
                count += 1
            }
            self.replaceChunks([])
            self.persistAndPublish()
            Log.storage.notice("Purged all \(count) stored recording chunks")
        }
    }

    func enforceLimits() {
        queue.async {
            self.enforceLimitsOnQueue()
        }
    }

    private func enforceLimitsOnQueue() {
        let maxSizeBytes = config.maxBufferSizeBytes
        let maxDurationSecs = config.maxStorageDurationSeconds

        let purged: [ChunkFile] = lock.withCriticalSection {
            var purged: [ChunkFile] = []
            var usage = storedUsage
            // A chunk an export is reading stays until the export finishes, then this runs again.
            while usage.totalBytes > maxSizeBytes || usage.totalDuration > maxDurationSecs,
                  let oldest = storedChunks.first, pinCounts[oldest.url] == nil {
                storedChunks.removeFirst()
                usage.count -= 1
                usage.totalBytes -= oldest.sizeBytes
                usage.totalDuration -= oldest.duration
                purged.append(oldest)
            }
            if !purged.isEmpty {
                storedUsage = ChunkUsage(chunks: storedChunks)
            }
            return purged
        }

        for chunk in purged {
            try? fileSystem.removeItem(at: chunk.url)
            Log.storage.info("Purged oldest chunk \(chunk.url.lastPathComponent, privacy: .public)")
        }
        persistAndPublish()
    }

    // MARK: - Manifest

    private func readManifest() -> [String: ChunkManifest.Entry] {
        guard let data = fileSystem.readData(at: manifestURL),
              let manifest = try? JSONDecoder().decode(ChunkManifest.self, from: data) else { return [:] }
        return Dictionary(manifest.chunks.map { ($0.name, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    private func persistAndPublish() {
        let (chunks, usage) = lock.withCriticalSection { (storedChunks, storedUsage) }
        let manifest = ChunkManifest(chunks: chunks.map {
            ChunkManifest.Entry(name: $0.url.lastPathComponent, start: $0.startTime, duration: $0.duration, size: $0.sizeBytes)
        })
        do {
            try fileSystem.writeData(try JSONEncoder().encode(manifest), to: manifestURL)
        } catch {
            Log.storage.error("Could not write chunk manifest: \(error.localizedDescription, privacy: .public)")
        }
        DispatchQueue.main.async {
            self.usageSubject.send(usage)
        }
    }

    // MARK: - Export

    func exportClip(_ request: ExportRequest, completion: @escaping (Result<URL, ExportError>) -> Void) {
        // Queued behind any registration, so a chunk flushed just before this call is included.
        queue.async {
            let footage = max(ConfigManager.shared.minExportOffsetSeconds, request.footageSeconds)
            let segments = self.lock.withCriticalSection {
                ExportPlanner.plan(chunks: self.storedChunks, footageSeconds: footage, endingAt: request.endDate)
            }

            guard !segments.isEmpty else {
                Log.export.notice("No recorded chunks available for export")
                DispatchQueue.main.async { completion(.failure(.noFootage)) }
                return
            }

            self.pin(segments)
            let exportURL = self.uniqueExportURL(for: request.endDate)
            let total = segments.reduce(0.0) { $0 + $1.duration }
            Log.export.notice("Exporting \(segments.count) segments (\(String(format: "%.1f", total), privacy: .public)s)")

            // The chunk queue stays free while AVFoundation works, so recording is never blocked.
            self.exportQueue.async {
                self.export(segments, to: exportURL) { result in
                    self.queue.async {
                        self.unpin(segments)
                        self.enforceLimitsOnQueue()
                    }
                    DispatchQueue.main.async { completion(result) }
                }
            }
        }
    }

    /// Keeps `segments` from being purged while an export reads them.
    func pin(_ segments: [ExportSegment]) {
        lock.withCriticalSection {
            for segment in segments {
                pinCounts[segment.url, default: 0] += 1
            }
        }
    }

    func unpin(_ segments: [ExportSegment]) {
        lock.withCriticalSection {
            for segment in segments {
                let remaining = (pinCounts[segment.url] ?? 1) - 1
                pinCounts[segment.url] = remaining > 0 ? remaining : nil
            }
        }
    }

    /// Never overwrites an earlier export, even one made within the same second.
    private func uniqueExportURL(for date: Date) -> URL {
        let directory = config.exportsDirectoryURL
        let baseName = "Recall_\(ChunkManager.exportDateFormatter.string(from: date))"
        var candidate = directory.appendingPathComponent("\(baseName).mp4")
        var suffix = 2
        while fileSystem.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix).mp4")
            suffix += 1
        }
        return candidate
    }

    private func export(_ segments: [ExportSegment], to outputURL: URL, completion: @escaping (Result<URL, ExportError>) -> Void) {
        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(.failure(.failed("Could not create the export composition.")))
            return
        }

        let timescale = ConfigManager.shared.timescale
        var insertTime = CMTime.zero
        for segment in segments {
            let asset = AVURLAsset(url: segment.url)
            guard let assetVideoTrack = asset.tracks(withMediaType: .video).first else {
                Log.export.error("Skipping unreadable chunk \(segment.url.lastPathComponent, privacy: .public)")
                continue
            }

            let start = CMTime(seconds: segment.start, preferredTimescale: timescale)
            let end = CMTimeMinimum(CMTime(seconds: segment.end, preferredTimescale: timescale), asset.duration)
            guard CMTimeCompare(end, start) > 0 else { continue }

            let range = CMTimeRange(start: start, end: end)
            do {
                try compVideoTrack.insertTimeRange(range, of: assetVideoTrack, at: insertTime)
                insertTime = CMTimeAdd(insertTime, range.duration)
            } catch {
                Log.export.error("Could not add \(segment.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        guard CMTimeCompare(insertTime, .zero) > 0 else {
            completion(.failure(.failed("The recorded chunks could not be read.")))
            return
        }

        // Stream copy first: lossless and near-instant. Re-encode only when the chunks cannot be
        // joined as they are (for example after a resolution or codec change mid-clip).
        runExportSession(composition, presetName: AVAssetExportPresetPassthrough, outputURL: outputURL) { passthroughError in
            guard let passthroughError = passthroughError else {
                Log.export.notice("Clip exported to \(outputURL.lastPathComponent, privacy: .public)")
                completion(.success(outputURL))
                return
            }

            Log.export.notice("Passthrough export failed (\(passthroughError, privacy: .public)); re-encoding")
            try? self.fileSystem.removeItem(at: outputURL)
            self.runExportSession(composition, presetName: AVAssetExportPresetHighestQuality, outputURL: outputURL) { encodeError in
                if let encodeError = encodeError {
                    Log.export.error("Export failed: \(encodeError, privacy: .public)")
                    try? self.fileSystem.removeItem(at: outputURL)
                    completion(.failure(.failed("The clip could not be exported: \(encodeError)")))
                } else {
                    Log.export.notice("Clip re-encoded to \(outputURL.lastPathComponent, privacy: .public)")
                    completion(.success(outputURL))
                }
            }
        }
    }

    /// Calls `completion` with nil on success, or a description of the failure.
    private func runExportSession(_ asset: AVAsset, presetName: String, outputURL: URL, completion: @escaping (String?) -> Void) {
        guard let exportSession = exportSessionFactory(asset, presetName) else {
            completion("\(presetName) export is unavailable")
            return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.exportAsynchronously {
            if exportSession.status == .completed {
                completion(nil)
            } else {
                completion(exportSession.error?.localizedDescription ?? "export ended with status \(exportSession.status.rawValue)")
            }
        }
    }

    func syncQueue() {
        queue.sync {}
    }
}
