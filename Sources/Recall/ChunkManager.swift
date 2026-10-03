import Foundation
import AVFoundation

struct ChunkFile {
    let url: URL
    let startTime: Date
    let duration: TimeInterval
    let sizeBytes: Int64
}


final class ChunkManager: ChunkStore, @unchecked Sendable {
    static let shared = ChunkManager()

    let chunksDirectory: URL
    private(set) var chunks: [ChunkFile] = []
    private let queue = DispatchQueue(label: "com.recall.chunkmanager", qos: .userInitiated)

    private let config: StorageConfig
    private let fileSystem: FileSystemProvider
    private let ffmpegRunner: FFmpegRunner
    private let metadataProvider: VideoMetadataProvider

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private static let chunkDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return formatter
    }()

    init(
        config: StorageConfig = SettingsManager.shared,
        fileSystem: FileSystemProvider = FileManager.default,
        ffmpegRunner: FFmpegRunner = DefaultFFmpegRunner(),
        metadataProvider: VideoMetadataProvider = DefaultVideoMetadataProvider(),
        chunksDirectory: URL? = nil
    ) {
        self.config = config
        self.fileSystem = fileSystem
        self.ffmpegRunner = ffmpegRunner
        self.metadataProvider = metadataProvider

        if let overrideDir = chunksDirectory {
            self.chunksDirectory = overrideDir
        } else if let xdgCache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"], !xdgCache.isEmpty {
            self.chunksDirectory = URL(fileURLWithPath: xdgCache).appendingPathComponent("recall/chunks")
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.chunksDirectory = home.appendingPathComponent(".cache/recall/chunks")
        }

        try? self.fileSystem.createDirectory(at: self.chunksDirectory, withIntermediateDirectories: true, attributes: nil)
        loadExistingChunks()
    }

    func loadExistingChunks() {
        queue.async {
            guard let files = try? self.fileSystem.contentsOfDirectory(at: self.chunksDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: []) else { return }

            var loaded: [ChunkFile] = []
            for file in files where file.pathExtension == "mp4" {
                let attrs = (try? self.fileSystem.attributesOfItem(atPath: file.path)) ?? [:]
                let size = (attrs[.size] as? Int64) ?? 0

                if size == 0 {
                    try? self.fileSystem.removeItem(at: file)
                    continue
                }

                var startTime = (attrs[.creationDate] as? Date) ?? Date()
                let name = file.deletingPathExtension().lastPathComponent
                if name.hasPrefix("chunk_") {
                    let dateString = String(name.dropFirst(6))
                    if let parsedDate = ChunkManager.chunkDateFormatter.date(from: dateString) {
                        startTime = parsedDate
                    }
                }

                let meta = self.metadataProvider.durationAndIsValid(for: file)

                guard meta.isValid else {
                    print("[ChunkManager] Removing corrupt chunk: \(file.lastPathComponent)")
                    try? self.fileSystem.removeItem(at: file)
                    continue
                }

                loaded.append(ChunkFile(url: file, startTime: startTime, duration: meta.duration, sizeBytes: size))
            }

            self.chunks = loaded.sorted(by: { $0.startTime < $1.startTime })
            self._enforceLimits()
        }
    }

    func registerChunk(url: URL, startTime: Date, duration passedDuration: TimeInterval) {
        queue.async {
            let attrs = (try? self.fileSystem.attributesOfItem(atPath: url.path)) ?? [:]
            let size = (attrs[.size] as? Int64) ?? 0

            if size > 0 {
                let meta = self.metadataProvider.durationAndIsValid(for: url)
                let actualDuration = meta.duration > 0 ? meta.duration : passedDuration

                guard meta.isValid else {
                    print("[ChunkManager] registerChunk: dropping corrupt chunk \(url.lastPathComponent)")
                    try? self.fileSystem.removeItem(at: url)
                    return
                }

                let chunk = ChunkFile(url: url, startTime: startTime, duration: actualDuration, sizeBytes: size)
                self.chunks.append(chunk)
                self.chunks.sort(by: { $0.startTime < $1.startTime })
                self._enforceLimits()

            } else {
                try? self.fileSystem.removeItem(at: url)
            }
        }
    }

    var totalRecordedDuration: TimeInterval {
        queue.sync {
            return chunks.reduce(0.0) { $0 + $1.duration }
        }
    }

    func purgeAllChunks() {
        queue.async {
            guard let files = try? self.fileSystem.contentsOfDirectory(at: self.chunksDirectory, includingPropertiesForKeys: nil, options: []) else { return }
            var count = 0
            for file in files {
                try? self.fileSystem.removeItem(at: file)
                count += 1
            }
            self.chunks.removeAll()
            print("[ChunkManager] Purged all \(count) stored recording chunks from disk.")
        }
    }

    func enforceLimits() {
        queue.async {
            self._enforceLimits()
        }
    }

    private func _enforceLimits() {
        let maxSizeBytes = config.maxBufferSizeBytes
        let maxDurationSecs = config.maxStorageDurationSeconds

        var totalSize = self.chunks.reduce(0) { $0 + $1.sizeBytes }
        var totalDuration = self.chunks.reduce(0.0) { $0 + $1.duration }

        while (totalSize > maxSizeBytes || totalDuration > maxDurationSecs), !self.chunks.isEmpty {
            let oldest = self.chunks.removeFirst()
            try? fileSystem.removeItem(at: oldest.url)
            totalSize -= oldest.sizeBytes
            totalDuration -= oldest.duration
            print("[ChunkManager] Purged oldest chunk: \(oldest.url.lastPathComponent) (Remaining total size: \(totalSize / 1024 / 1024)MB, duration: \(String(format: "%.1f", totalDuration))s)")
        }
    }

    func exportClip(offsetSeconds: TimeInterval, completion: @escaping (URL?) -> Void) {
        // Step 1: Async flush in-progress chunk
        RecorderEngine.shared.flushCurrentChunk {
            self.queue.async {
                let targetSeconds = max(1.0, offsetSeconds)

                let validChunks = self.chunks.filter { chunk in
                    let attrs = (try? self.fileSystem.attributesOfItem(atPath: chunk.url.path)) ?? [:]
                    let size = (attrs[.size] as? Int64) ?? 0
                    return size > 0 && chunk.duration > 0
                }

                let sorted = validChunks.sorted(by: { $0.startTime < $1.startTime })
                var selectedChunks: [ChunkFile] = []
                var accumulated: TimeInterval = 0

                for chunk in sorted.reversed() {
                    selectedChunks.insert(chunk, at: 0)
                    accumulated += chunk.duration
                    if accumulated >= targetSeconds { break }
                }

                guard !selectedChunks.isEmpty else {
                    print("[ChunkManager] No valid chunks available for export")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                let excess = max(0, accumulated - targetSeconds)

                print("[ChunkManager] Exporting \(selectedChunks.count) chunks for \(targetSeconds)s (accumulated=\(String(format: "%.1f", accumulated))s, trimming \(String(format: "%.1f", excess))s from beginning)")

                let now = Date()
                let exportsDir = self.config.exportsDirectoryURL
                let exportURL = exportsDir.appendingPathComponent("Recall_\(ChunkManager.exportDateFormatter.string(from: now)).mp4")
                try? self.fileSystem.removeItem(at: exportURL)

                if let ffmpegPath = self.ffmpegRunner.findFFmpegPath(fileSystem: self.fileSystem) {
                    let tempDir = FileManager.default.temporaryDirectory
                    let listURL = tempDir.appendingPathComponent("recall_concat_\(UUID().uuidString).txt")

                    var listContent = ""
                    for c in selectedChunks {
                        listContent += "file '\(c.url.path)'\n"
                    }
                    try? listContent.write(to: listURL, atomically: true, encoding: .utf8)

                    defer {
                        try? self.fileSystem.removeItem(at: listURL)
                    }

                    print("[ChunkManager] Running single-pass ffmpeg concat & trim via \(ffmpegPath)...")
                    let success = self.ffmpegRunner.concatAndTrim(listURL: listURL, outputURL: exportURL, excessSeconds: excess, ffmpegPath: ffmpegPath)

                    if success && self.fileSystem.fileExists(atPath: exportURL.path) {
                        print("[ChunkManager] Single-pass ffmpeg export successful: \(exportURL.path)")
                        DispatchQueue.main.async { completion(exportURL) }
                        return
                    }
                    print("[ChunkManager] ffmpeg export failed, falling back to AVMutableComposition...")
                }

                // Fallback: AVMutableComposition with re-encoding
                let composition = AVMutableComposition()
                guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                var insertTime = CMTime.zero

                for (index, chunk) in selectedChunks.enumerated() {
                    let asset = AVAsset(url: chunk.url)
                    guard let assetVideoTrack = asset.tracks(withMediaType: .video).first else { continue }

                    let assetDuration = asset.duration
                    var startTimeInChunk = CMTime.zero
                    if index == 0 && excess > 0 {
                        startTimeInChunk = CMTime(seconds: excess, preferredTimescale: 600)
                    }

                    let durationInChunk = CMTimeSubtract(assetDuration, startTimeInChunk)
                    if CMTimeCompare(durationInChunk, .zero) > 0 {
                        let range = CMTimeRange(start: startTimeInChunk, duration: durationInChunk)
                        try? compVideoTrack.insertTimeRange(range, of: assetVideoTrack, at: insertTime)
                        insertTime = CMTimeAdd(insertTime, durationInChunk)
                    }
                }

                guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                exportSession.outputURL = exportURL
                exportSession.outputFileType = .mp4

                exportSession.exportAsynchronously {
                    DispatchQueue.main.async {
                        if exportSession.status == .completed {
                            print("[ChunkManager] Fallback clip exported successfully: \(exportURL.path)")
                            completion(exportURL)
                        } else {
                            print("[ChunkManager] Fallback export failed: \(String(describing: exportSession.error))")
                            completion(nil)
                        }
                    }
                }
            }
        }
    }
}
