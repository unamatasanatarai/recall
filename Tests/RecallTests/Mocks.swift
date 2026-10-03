import Foundation

struct MockStorageConfig: StorageConfig {
    var maxBufferSizeBytes: Int64 = 100 * 1024 * 1024 // 100 MB
    var maxStorageDurationSeconds: TimeInterval = 3600 // 1 hour
    var exportsDirectoryURL: URL = URL(fileURLWithPath: "/tmp/mock_exports")
}

final class MockFileSystem: FileSystemProvider, @unchecked Sendable {
    var files: [URL: [FileAttributeKey: Any]] = [:]
    var removedURLs: [URL] = []
    var createdDirectories: [URL] = []
    var movedItems: [(src: URL, dst: URL)] = []
    var executablePaths: Set<String> = []

    func fileExists(atPath path: String) -> Bool {
        return files.keys.contains { $0.path == path }
    }

    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL] {
        return files.keys.filter { $0.deletingLastPathComponent().path == url.path }
    }

    func removeItem(at url: URL) throws {
        removedURLs.append(url)
        files.removeValue(forKey: url)
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        let url = URL(fileURLWithPath: path)
        if let attrs = files[url] {
            return attrs
        }
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws {
        createdDirectories.append(url)
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        movedItems.append((src: srcURL, dst: dstURL))
        if let attrs = files[srcURL] {
            files.removeValue(forKey: srcURL)
            files[dstURL] = attrs
        }
    }

    func isExecutableFile(atPath path: String) -> Bool {
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

    func findFFmpegPath(fileSystem: FileSystemProvider) -> String? {
        return ffmpegPathToReturn
    }

    func concatAndTrim(listURL: URL, outputURL: URL, excessSeconds: Double, ffmpegPath: String) -> Bool {
        return concatAndTrimResult
    }
}
