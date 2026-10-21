import Foundation
import CoreGraphics

struct ConfigManagerTests {
    static func testDefaultConfigurationValues() throws {
        let config = ConfigManager.shared

        try check(config.maxChunkDuration == 10.0, "Expected maxChunkDuration to be 10.0")
        try check(config.targetFrameRate == 30, "Expected 30 fps")
        try check(config.defaultMaxStorageMB == 1000, "Expected defaultMaxStorageMB to be 1000")
        try check(config.defaultMaxStorageMinutes == 60, "Expected defaultMaxStorageMinutes to be 60")
        try check(config.minDragDistance == 200.0, "Expected minDragDistance to be 200.0")
        try check(config.screenHeightDragRatio == 0.5, "Expected screenHeightDragRatio to be 0.5")
        try check(config.minExportOffsetSeconds == 1.0, "Expected minExportOffsetSeconds to be 1.0")
        try check(config.doublePressQuitThreshold == 2.0, "Expected doublePressQuitThreshold to be 2.0")
    }

    static func testExportOffsetStepsStartFineAndIncrease() throws {
        let steps = ConfigManager.shared.exportOffsetSteps
        try check(steps.first == 10, "The first drag step should be 10 s, got \(String(describing: steps.first))")
        try check(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 }, "Steps must be strictly increasing")
    }

    static func testStorageLivesInPrivateCacheDirectory() throws {
        let config = ConfigManager.shared
        // The test runner points RECALL_CACHE_DIR at a sandbox.
        try check(config.cacheDirectoryOverride != nil, "Tests must run with RECALL_CACHE_DIR set")
        try check(config.defaultBaseCacheDirectory == config.cacheDirectoryOverride, "The override must win")
        try check(config.defaultChunksDirectory.lastPathComponent == "chunks.noindex", "Chunks need the .noindex suffix to stay out of Spotlight")
        try check(config.legacyCacheDirectory == nil, "Legacy migration must be disabled under an override")
    }

    static func testDefaultExportsLocation() throws {
        try check(ConfigManager.shared.defaultExportsDirectory.path.hasSuffix("Movies/Recall-exports"), "Exports URL path mismatch: \(ConfigManager.shared.defaultExportsDirectory.path)")
    }

    static func testSettingsManagerIntegrationWithConfig() throws {
        let config = ConfigManager.shared
        try check(SettingsManager.defaultMaxStorageMB == config.defaultMaxStorageMB, "SettingsManager defaultMaxStorageMB out of sync with ConfigManager")
        try check(SettingsManager.defaultMaxStorageMinutes == config.defaultMaxStorageMinutes, "SettingsManager defaultMaxStorageMinutes out of sync with ConfigManager")
        try check(SettingsManager.defaultExportsDirectory.path == config.defaultExportsDirectory.path, "SettingsManager defaultExportsDirectory out of sync with ConfigManager")
    }
}
