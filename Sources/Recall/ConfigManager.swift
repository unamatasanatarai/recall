import Foundation
import CoreGraphics
import CoreMedia

/// Central configuration providing defaults and parameters for storage, recording,
/// interaction gestures, and system paths. Values are constants; user-adjustable
/// settings live in `SettingsManager`.
struct ConfigManager {
    static let shared = ConfigManager()

    // MARK: - Chunk & Encoding Settings
    let maxChunkDuration: TimeInterval = 10.0
    let targetFrameRate: Int32 = 30
    let timescale: CMTimeScale = 600
    let keyFrameIntervalSeconds: TimeInterval = 2.0
    let movieFragmentIntervalSeconds: TimeInterval = 1.0
    /// H.264 bitrate for a 1440x900 display; other sizes scale sub-linearly from it.
    let referenceBitRate: Double = 4_000_000
    let referencePixelCount: Double = 1440 * 900
    let minBitRate: Double = 1_500_000
    let maxBitRate: Double = 24_000_000
    let hevcBitRateFactor: Double = 0.6

    // MARK: - Capture Recovery
    let captureStartTimeout: TimeInterval = 5.0
    let captureRestartDelay: TimeInterval = 2.0
    let writerRetryInterval: TimeInterval = 2.0
    let rotationCheckInterval: TimeInterval = 0.5
    let terminationTimeout: TimeInterval = 5.0

    // MARK: - Storage & Retention Limits
    let defaultMaxStorageMB: Int = 1000
    let defaultMaxStorageMinutes: Int = 60
    let minStorageMB: Int = 50
    let maxAllowedStorageMB: Int = 100_000
    let stepStorageMB: Int = 50
    let minStorageMinutes: Int = 5
    let maxAllowedStorageMinutes: Int = 10_080 // 7 days in minutes
    let stepStorageMinutes: Int = 15

    // MARK: - Drag Gesture & Interaction Settings
    let minDragDistance: CGFloat = 200.0
    let screenHeightDragRatio: CGFloat = 0.5
    let defaultFallbackScreenHeight: CGFloat = 900.0
    /// Snap points for the drag gesture: fine-grained for recent history, coarser further back.
    let exportOffsetSteps: [TimeInterval] = [
        10, 20, 30, 45, 60, 90, 120, 180, 240, 300, 450, 600, 900, 1200, 1800,
        2700, 3600, 5400, 7200, 10_800, 14_400, 21_600, 43_200, 86_400
    ]
    let minExportOffsetSeconds: TimeInterval = 1.0

    // MARK: - Keyboard & Window Settings
    let doublePressQuitThreshold: TimeInterval = 2.0
    let preferencesWindowWidth: CGFloat = 560.0
    let preferencesWindowHeight: CGFloat = 300.0

    // MARK: - Default File System Locations
    var bundleIdentifier: String {
        return Bundle.main.bundleIdentifier ?? "com.recall.app"
    }

    var defaultExportsDirectory: URL {
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        return moviesDir.appendingPathComponent("Recall-exports")
    }

    /// `RECALL_CACHE_DIR` redirects all recording storage; tests and smoke runs use it
    /// so they never touch real recordings.
    var cacheDirectoryOverride: URL? {
        guard let path = ProcessInfo.processInfo.environment["RECALL_CACHE_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// `~/Library/Caches/<bundle id>`: private to the user and skipped by Time Machine.
    var defaultBaseCacheDirectory: URL {
        if let override = cacheDirectoryOverride {
            return override
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        return caches.appendingPathComponent(bundleIdentifier)
    }

    /// The `.noindex` suffix keeps Spotlight from indexing the recordings.
    var defaultChunksDirectory: URL {
        return defaultBaseCacheDirectory.appendingPathComponent("chunks.noindex")
    }

    var instanceLockURL: URL {
        return defaultBaseCacheDirectory.appendingPathComponent(".instance.lock")
    }

    /// Location used by earlier releases (`~/.cache/recall`); its chunks are migrated on launch.
    var legacyCacheDirectory: URL? {
        guard cacheDirectoryOverride == nil else { return nil }
        if let xdgCache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"], !xdgCache.isEmpty {
            return URL(fileURLWithPath: xdgCache).appendingPathComponent("recall")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/recall")
    }
}
