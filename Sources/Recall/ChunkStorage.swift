import Foundation

// MARK: - Chunk Naming

/// Chunk file names carry the UTC start time, so ordering survives DST changes and
/// locale settings. Chunks still being written carry an extra `.partial` extension.
enum ChunkNaming {
    static let fileExtension = "mp4"
    static let partialExtension = "partial"
    private static let prefix = "chunk_"

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS'Z'"
        return formatter
    }()

    /// Earlier releases named chunks in local time without a zone.
    private static let legacyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return formatter
    }()

    static func fileName(for date: Date) -> String {
        return "\(prefix)\(formatter.string(from: date)).\(fileExtension)"
    }

    static func partialURL(for finalURL: URL) -> URL {
        return finalURL.appendingPathExtension(partialExtension)
    }

    static func isChunk(_ url: URL) -> Bool {
        return url.pathExtension == fileExtension
    }

    static func isPartial(_ url: URL) -> Bool {
        return url.pathExtension == partialExtension
    }

    static func startDate(from url: URL) -> Date? {
        var name = url
        if isPartial(name) {
            name = name.deletingPathExtension()
        }
        let base = name.deletingPathExtension().lastPathComponent
        guard base.hasPrefix(prefix) else { return nil }
        let stamp = String(base.dropFirst(prefix.count))
        // DateFormatter tolerates a missing trailing literal, so pick the format explicitly:
        // parsing a local-time legacy name as UTC would shift it by the time zone offset.
        return stamp.hasSuffix("Z") ? formatter.date(from: stamp) : legacyFormatter.date(from: stamp)
    }
}

// MARK: - Manifest

/// Index of finished chunks, so launch does not have to open every file with AVFoundation.
struct ChunkManifest: Codable {
    struct Entry: Codable {
        let name: String
        let start: Date
        let duration: TimeInterval
        let size: Int64
    }

    var version = 1
    var chunks: [Entry]
}

// MARK: - Storage Directory

enum StorageDirectory {
    /// Creates `url` readable only by the current user and keeps it out of Time Machine.
    static func prepare(_ url: URL, fileSystem: FileSystemProvider) {
        do {
            try fileSystem.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Earlier releases created world-readable directories.
            try fileSystem.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            Log.storage.error("Could not prepare \(url.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
        fileSystem.excludeFromBackup(url)
    }
}

// MARK: - Legacy Migration

enum LegacyStorageMigration {
    /// Moves chunks recorded by earlier releases into `chunksDirectory` and removes the old,
    /// world-readable cache. Returns the number of chunks moved.
    @discardableResult
    static func migrate(from legacyBase: URL, to chunksDirectory: URL, fileSystem: FileSystemProvider) -> Int {
        let legacyChunks = legacyBase.appendingPathComponent("chunks")
        guard legacyBase.standardizedFileURL != chunksDirectory.deletingLastPathComponent().standardizedFileURL,
              fileSystem.fileExists(atPath: legacyBase.path) else { return 0 }

        var moved = 0
        let files = (try? fileSystem.contentsOfDirectory(at: legacyChunks, includingPropertiesForKeys: nil, options: [])) ?? []
        for file in files {
            let size = ((try? fileSystem.attributesOfItem(atPath: file.path))?[.size] as? Int64) ?? 0
            let destination = chunksDirectory.appendingPathComponent(file.lastPathComponent)
            if ChunkNaming.isChunk(file), size > 0, !fileSystem.fileExists(atPath: destination.path),
               (try? fileSystem.moveItem(at: file, to: destination)) != nil {
                moved += 1
            } else {
                try? fileSystem.removeItem(at: file)
            }
        }

        try? fileSystem.removeItem(at: legacyBase.appendingPathComponent("recall_debug.log"))
        for directory in [legacyChunks, legacyBase] {
            if let remaining = try? fileSystem.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: []), remaining.isEmpty {
                try? fileSystem.removeItem(at: directory)
            }
        }

        if moved > 0 {
            Log.storage.notice("Migrated \(moved) chunks from the legacy cache directory")
        }
        return moved
    }
}

// MARK: - Locking

extension NSLock {
    func withCriticalSection<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
