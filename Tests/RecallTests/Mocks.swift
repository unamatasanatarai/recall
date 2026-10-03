import Foundation

struct MockStorageConfig: StorageConfig {
    var maxBufferSizeBytes: Int64 = 100 * 1024 * 1024 // 100 MB
    var maxStorageDurationSeconds: TimeInterval = 3600 // 1 hour
    var exportsDirectoryURL: URL = URL(fileURLWithPath: "/tmp/mock_exports")
}

final class MockFileSystem: FileSystemProvider, @unchecked Sendable {
    private let lock = NSLock()
    var files: [URL: [FileAttributeKey: Any]] = [:]
    var removedURLs: [URL] = []
    var createdDirectories: [URL] = []
    var movedItems: [(src: URL, dst: URL)] = []
    var executablePaths: Set<String> = []

    func setFile(_ url: URL, attributes: [FileAttributeKey: Any]) {
        lock.lock()
        defer { lock.unlock() }
        files[url] = attributes
    }

    func fileExists(atPath path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return files.keys.contains { $0.path == path }
    }

    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return files.keys.filter { $0.deletingLastPathComponent().path == url.path }
    }

    func removeItem(at url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        removedURLs.append(url)
        files.removeValue(forKey: url)
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        lock.lock()
        defer { lock.unlock() }
        let url = URL(fileURLWithPath: path)
        if let attrs = files[url] {
            return attrs
        }
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws {
        lock.lock()
        defer { lock.unlock() }
        createdDirectories.append(url)
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        movedItems.append((src: srcURL, dst: dstURL))
        if let attrs = files[srcURL] {
            files.removeValue(forKey: srcURL)
            files[dstURL] = attrs
        }
    }

    func isExecutableFile(atPath path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return executablePaths.contains(path)
    }
}

struct MockVideoMetadataProvider: VideoMetadataProvider {
    var defaultDuration: TimeInterval = 30.0
    var isValid: Bool = true

    func durationAndIsValid(for url: URL) -> (duration: TimeInterval, isValid: Bool) {
        return (defaultDuration, isValid)
    }
}

struct MockFFmpegRunner: FFmpegRunner {
    var ffmpegPathToReturn: String? = "/usr/local/bin/ffmpeg"
    var concatAndTrimResult: Bool = true
    var fileSystem: MockFileSystem? = nil

    func findFFmpegPath(fileSystem: FileSystemProvider) -> String? {
        return ffmpegPathToReturn
    }

    func concatAndTrim(listURL: URL, outputURL: URL, excessSeconds: Double, ffmpegPath: String) -> Bool {
        if concatAndTrimResult, let fs = fileSystem {
            fs.setFile(outputURL, attributes: [.size: Int64(1000)])
        }
        return concatAndTrimResult
    }
}

final class MockChunkStore: ChunkStore, @unchecked Sendable {
    private let lock = NSLock()
    var chunksDirectory: URL = URL(fileURLWithPath: "/tmp/mock_chunks")
    var chunks: [ChunkFile] = []
    var totalRecordedDuration: TimeInterval = 0.0

    func registerChunk(url: URL, startTime: Date, duration: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        let chunk = ChunkFile(url: url, startTime: startTime, duration: duration, sizeBytes: 1000)
        chunks.append(chunk)
        totalRecordedDuration += duration
    }

    func enforceLimits() {}
    func purgeAllChunks() {
        lock.lock()
        defer { lock.unlock() }
        chunks.removeAll()
        totalRecordedDuration = 0.0
    }

    func exportClip(offsetSeconds: TimeInterval, completion: @escaping (URL?) -> Void) {
        completion(URL(fileURLWithPath: "/tmp/mock_export.mp4"))
    }
}

final class MockScreenCapture: ScreenCapture, @unchecked Sendable {
    private let lock = NSLock()
    var state: RecordingState = .idle

    func startContinuousRecording() {
        lock.lock()
        defer { lock.unlock() }
        state = .recording
    }

    func flushCurrentChunk(completion: (() -> Void)?) {
        completion?()
    }

    func stopStream() {
        lock.lock()
        defer { lock.unlock() }
        state = .idle
    }
}
