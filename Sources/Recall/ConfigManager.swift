import Foundation
import CoreGraphics

/// Central configuration manager providing centralized defaults and parameters
/// for storage, recording buffers, interaction gestures, and system paths.
final class ConfigManager: @unchecked Sendable {
    static let shared = ConfigManager()

    // MARK: - Chunk & Buffer Settings
    var maxChunkDuration: TimeInterval = 10.0
    var targetFrameRate: Int32 = 30
    var timescale: Int32 = 600

    // MARK: - Storage & Retention Limits
    var defaultMaxStorageMB: Int = 1000
    var defaultMaxStorageMinutes: Int = 60
    var minStorageMB: Int = 50
    var maxAllowedStorageMB: Int = 100_000
    var stepStorageMB: Int = 50
    var minStorageMinutes: Int = 5
    var maxAllowedStorageMinutes: Int = 10_080 // 7 days in minutes
    var stepStorageMinutes: Int = 15

    // MARK: - Logging Configuration
    var maxLogFileSize: Int64 = 10 * 1024 * 1024 // 10 MB

    // MARK: - Drag Gesture & Interaction Settings
    var minDragDistance: CGFloat = 200.0
    var screenHeightDragRatio: CGFloat = 0.5
    var defaultFallbackScreenHeight: CGFloat = 900.0
    var dragTimeStepSeconds: TimeInterval = 60.0
    var minExportOffsetSeconds: TimeInterval = 1.0

    // MARK: - Keyboard & Window Settings
    var doublePressQuitThreshold: TimeInterval = 2.0
    var preferencesWindowWidth: CGFloat = 536.0
    var preferencesWindowHeight: CGFloat = 192.0

    // MARK: - Default File System Locations
    var defaultExportsDirectory: URL {
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        return moviesDir.appendingPathComponent("Recall-exports")
    }

    var defaultBaseCacheDirectory: URL {
        if let xdgCache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"], !xdgCache.isEmpty {
            return URL(fileURLWithPath: xdgCache).appendingPathComponent("recall")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/recall")
    }

    var defaultChunksDirectory: URL {
        return defaultBaseCacheDirectory.appendingPathComponent("chunks")
    }

    var defaultLogFileURL: URL {
        return defaultBaseCacheDirectory.appendingPathComponent("recall_debug.log")
    }

    func resetToDefaults() {
        maxChunkDuration = 10.0
        targetFrameRate = 30
        timescale = 600
        defaultMaxStorageMB = 1000
        defaultMaxStorageMinutes = 60
        minStorageMB = 50
        maxAllowedStorageMB = 100_000
        stepStorageMB = 50
        minStorageMinutes = 5
        maxAllowedStorageMinutes = 10_080
        stepStorageMinutes = 15
        maxLogFileSize = 10 * 1024 * 1024
        minDragDistance = 200.0
        screenHeightDragRatio = 0.5
        defaultFallbackScreenHeight = 900.0
        dragTimeStepSeconds = 60.0
        minExportOffsetSeconds = 1.0
        doublePressQuitThreshold = 2.0
        preferencesWindowWidth = 536.0
        preferencesWindowHeight = 192.0
    }
}
