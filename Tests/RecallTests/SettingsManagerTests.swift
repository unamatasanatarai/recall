import Foundation

struct SettingsManagerTests {
    static func testResetToDefaults_resetsProperties() throws {
        let settings = SettingsManager.shared
        settings.maxStorageMB = 5000
        settings.maxStorageMinutes = 120

        if settings.maxStorageMB != 5000 || settings.maxStorageMinutes != 120 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Initial mutation failed"])
        }

        settings.resetToDefaults()

        if settings.maxStorageMB != 1000 || settings.maxStorageMinutes != 60 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Reset to defaults failed"])
        }
    }

    static func testStorageConfigCalculations() throws {
        let settings = SettingsManager.shared
        settings.maxStorageMB = 2000
        settings.maxStorageMinutes = 30

        if settings.maxBufferSizeBytes != Int64(2000) * 1024 * 1024 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "maxBufferSizeBytes calculation wrong"])
        }

        if settings.maxStorageDurationSeconds != 1800.0 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "maxStorageDurationSeconds calculation wrong"])
        }
    }
}
