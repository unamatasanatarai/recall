import Foundation
import AVFoundation

// MARK: - StorageConfig Protocol
protocol StorageConfig {
    var maxBufferSizeBytes: Int64 { get }
    var maxStorageDurationSeconds: TimeInterval { get }
    var exportsDirectoryURL: URL { get }
}

extension SettingsManager: StorageConfig {}

// MARK: - FileSystemProvider Protocol
protocol FileSystemProvider {
    func fileExists(atPath path: String) -> Bool
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL]
    func removeItem(at url: URL) throws
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func isExecutableFile(atPath path: String) -> Bool
}

extension FileManager: FileSystemProvider {}

// MARK: - VideoMetadataProvider Protocol
protocol VideoMetadataProvider {
    func durationAndIsValid(for url: URL) -> (duration: TimeInterval, isValid: Bool)
}

struct DefaultVideoMetadataProvider: VideoMetadataProvider {
    func durationAndIsValid(for url: URL) -> (duration: TimeInterval, isValid: Bool) {
        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        let isValid = duration.isFinite && duration > 0 && asset.tracks(withMediaType: .video).first != nil
        return (duration, isValid)
    }
}

// MARK: - FFmpegRunner Protocol
protocol FFmpegRunner {
    func findFFmpegPath(fileSystem: FileSystemProvider) -> String?
    func concatAndTrim(listURL: URL, outputURL: URL, excessSeconds: Double, ffmpegPath: String) -> Bool
}

struct DefaultFFmpegRunner: FFmpegRunner {
    func findFFmpegPath(fileSystem: FileSystemProvider = FileManager.default) -> String? {
        let candidates = [
            "/usr/local/bin/ffmpeg",
            "/opt/homebrew/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for p in candidates {
            if fileSystem.isExecutableFile(atPath: p) { return p }
        }
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["ffmpeg"]
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                if fileSystem.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }

    func concatAndTrim(listURL: URL, outputURL: URL, excessSeconds: Double, ffmpegPath: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpegPath)
        var args = ["-hide_banner", "-loglevel", "error", "-y"]
        if excessSeconds > 0.05 {
            args += ["-ss", String(format: "%.3f", excessSeconds)]
        }
        args += ["-f", "concat", "-safe", "0", "-i", listURL.path, "-c", "copy", outputURL.path]
        proc.arguments = args
        try? proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
}

// MARK: - ChunkStore Protocol
protocol ChunkStore: AnyObject {
    var chunksDirectory: URL { get }
    var chunks: [ChunkFile] { get }
    var totalRecordedDuration: TimeInterval { get }
    func registerChunk(url: URL, startTime: Date, duration: TimeInterval)
    func enforceLimits()
    func purgeAllChunks()
    func exportClip(offsetSeconds: TimeInterval, completion: @escaping (URL?) -> Void)
}

// MARK: - ScreenCapture Protocol
protocol ScreenCapture: AnyObject {
    var state: RecordingState { get }
    func startContinuousRecording()
    func flushCurrentChunk(completion: (() -> Void)?)
    func stopStream()
}
