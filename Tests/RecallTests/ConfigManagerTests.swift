import Foundation
import CoreGraphics

struct ConfigManagerTests {
    static func testDefaultConfigurationValues() throws {
        let config = ConfigManager.shared
        config.resetToDefaults()

        if config.maxChunkDuration != 10.0 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected maxChunkDuration to be 10.0"])
        }
        if config.defaultMaxStorageMB != 1000 {
            throw NSError(domain: "TestError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected defaultMaxStorageMB to be 1000"])
        }
        if config.defaultMaxStorageMinutes != 60 {
            throw NSError(domain: "TestError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected defaultMaxStorageMinutes to be 60"])
        }
        if config.minDragDistance != 200.0 {
            throw NSError(domain: "TestError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected minDragDistance to be 200.0"])
        }
        if config.screenHeightDragRatio != 0.5 {
            throw NSError(domain: "TestError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected screenHeightDragRatio to be 0.5"])
        }
        if config.dragTimeStepSeconds != 60.0 {
            throw NSError(domain: "TestError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected dragTimeStepSeconds to be 60.0"])
        }
        if config.minExportOffsetSeconds != 1.0 {
            throw NSError(domain: "TestError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected minExportOffsetSeconds to be 1.0"])
        }
        if config.doublePressQuitThreshold != 2.0 {
            throw NSError(domain: "TestError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected doublePressQuitThreshold to be 2.0"])
        }
    }

    static func testDefaultLocationsPaths() throws {
        let config = ConfigManager.shared
        let exportsURL = config.defaultExportsDirectory
        if !exportsURL.path.contains("Recall-exports") {
            throw NSError(domain: "TestError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Exports URL path mismatch: \(exportsURL.path)"])
        }

        let chunksURL = config.defaultChunksDirectory
        if !chunksURL.path.contains("chunks") {
            throw NSError(domain: "TestError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Chunks directory path mismatch: \(chunksURL.path)"])
        }

        let logURL = config.defaultLogFileURL
        if !logURL.path.contains("recall_debug.log") {
            throw NSError(domain: "TestError", code: 11, userInfo: [NSLocalizedDescriptionKey: "Log file URL path mismatch: \(logURL.path)"])
        }
    }

    static func testConfigResetToDefaults() throws {
        let config = ConfigManager.shared
        config.maxChunkDuration = 25.0
        config.defaultMaxStorageMB = 5000
        config.minDragDistance = 350.0

        config.resetToDefaults()

        if config.maxChunkDuration != 10.0 || config.defaultMaxStorageMB != 1000 || config.minDragDistance != 200.0 {
            throw NSError(domain: "TestError", code: 12, userInfo: [NSLocalizedDescriptionKey: "resetToDefaults failed to restore initial parameters"])
        }
    }

    static func testSettingsManagerIntegrationWithConfig() throws {
        let config = ConfigManager.shared
        config.resetToDefaults()

        if SettingsManager.defaultMaxStorageMB != config.defaultMaxStorageMB {
            throw NSError(domain: "TestError", code: 13, userInfo: [NSLocalizedDescriptionKey: "SettingsManager defaultMaxStorageMB out of sync with ConfigManager"])
        }
        if SettingsManager.defaultMaxStorageMinutes != config.defaultMaxStorageMinutes {
            throw NSError(domain: "TestError", code: 14, userInfo: [NSLocalizedDescriptionKey: "SettingsManager defaultMaxStorageMinutes out of sync with ConfigManager"])
        }
        if SettingsManager.defaultExportsDirectory.path != config.defaultExportsDirectory.path {
            throw NSError(domain: "TestError", code: 15, userInfo: [NSLocalizedDescriptionKey: "SettingsManager defaultExportsDirectory out of sync with ConfigManager"])
        }
    }
}
