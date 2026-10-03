import Foundation

struct SettingsManagerTests {
    static func testDefaultValuesInitialization_exportsDirectoryPath() throws {
        let expectedDefault = SettingsManager.defaultExportsDirectory.path
        let settings = SettingsManager.shared
        settings.resetToDefaults()
        if settings.exportsDirectoryPath != expectedDefault {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Default exportsDirectoryPath expected \(expectedDefault), got \(settings.exportsDirectoryPath)"])
        }
    }

    static func testDefaultSizeLimit() throws {
        let settings = SettingsManager.shared
        settings.resetToDefaults()
        if settings.maxStorageMB != 1000 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Default maxStorageMB expected 1000, got \(settings.maxStorageMB)"])
        }
    }

    static func testDefaultTimeLimit() throws {
        let settings = SettingsManager.shared
        settings.resetToDefaults()
        if settings.maxStorageMinutes != 60 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Default maxStorageMinutes expected 60, got \(settings.maxStorageMinutes)"])
        }
    }

    static func testUserDefaultsPersistence_exportsDirectoryPath() throws {
        let settings = SettingsManager.shared
        let customPath = "/tmp/test_recall_exports_\(UUID().uuidString)"
        settings.exportsDirectoryPath = customPath

        let saved = UserDefaults.standard.string(forKey: "exportsDirectoryPath")
        if saved != customPath {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "UserDefaults string expected \(customPath), got \(String(describing: saved))"])
        }
        settings.resetToDefaults()
    }

    static func testUserDefaultsPersistence_maxStorageMB() throws {
        let settings = SettingsManager.shared
        settings.maxStorageMB = 2500
        let saved = UserDefaults.standard.integer(forKey: "maxStorageMB")
        if saved != 2500 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "UserDefaults int expected 2500, got \(saved)"])
        }
        settings.resetToDefaults()
    }

    static func testUserDefaultsPersistence_maxStorageMinutes() throws {
        let settings = SettingsManager.shared
        settings.maxStorageMinutes = 180
        let saved = UserDefaults.standard.integer(forKey: "maxStorageMinutes")
        if saved != 180 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "UserDefaults int expected 180, got \(saved)"])
        }
        settings.resetToDefaults()
    }

    static func testStorageConfigByteCalculation_variousValues() throws {
        let settings = SettingsManager.shared
        let cases: [(mb: Int, expectedBytes: Int64)] = [
            (50, 50 * 1024 * 1024),
            (1000, 1000 * 1024 * 1024),
            (5000, 5000 * 1024 * 1024)
        ]
        for c in cases {
            settings.maxStorageMB = c.mb
            if settings.maxBufferSizeBytes != c.expectedBytes {
                throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Byte calculation for \(c.mb)MB expected \(c.expectedBytes), got \(settings.maxBufferSizeBytes)"])
            }
        }
        settings.resetToDefaults()
    }

    static func testStorageConfigSecondCalculation_variousValues() throws {
        let settings = SettingsManager.shared
        let cases: [(min: Int, expectedSecs: TimeInterval)] = [
            (5, 300.0),
            (60, 3600.0),
            (120, 7200.0)
        ]
        for c in cases {
            settings.maxStorageMinutes = c.min
            if settings.maxStorageDurationSeconds != c.expectedSecs {
                throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Second calculation for \(c.min)min expected \(c.expectedSecs), got \(settings.maxStorageDurationSeconds)"])
            }
        }
        settings.resetToDefaults()
    }

    static func testTildePathExpansion() throws {
        let settings = SettingsManager.shared
        settings.exportsDirectoryPath = "~/RecallTestFolder"
        let url = settings.exportsDirectoryURL
        if url.path.contains("~") || !url.path.hasPrefix("/") {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tilde path was not expanded to absolute URL: \(url.path)"])
        }
        settings.resetToDefaults()
    }

    static func testExportDirectoryAutoCreation() throws {
        let settings = SettingsManager.shared
        let tempDir = URL(fileURLWithPath: "/tmp/recall_autocreate_\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: tempDir)

        settings.exportsDirectoryPath = tempDir.path
        let url = settings.exportsDirectoryURL

        if !FileManager.default.fileExists(atPath: url.path) {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Directory was not created at \(url.path)"])
        }

        try? FileManager.default.removeItem(at: tempDir)
        settings.resetToDefaults()
    }

    static func testSettingsChangedCallback_maxStorageMB() throws {
        let settings = SettingsManager.shared
        var callbackTriggered = false
        settings.onSettingsChanged = {
            callbackTriggered = true
        }

        settings.maxStorageMB = 3000
        if !callbackTriggered {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "onSettingsChanged was not triggered when maxStorageMB changed"])
        }

        settings.onSettingsChanged = nil
        settings.resetToDefaults()
    }

    static func testSettingsChangedCallback_maxStorageMinutes() throws {
        let settings = SettingsManager.shared
        var callbackTriggered = false
        settings.onSettingsChanged = {
            callbackTriggered = true
        }

        settings.maxStorageMinutes = 90
        if !callbackTriggered {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "onSettingsChanged was not triggered when maxStorageMinutes changed"])
        }

        settings.onSettingsChanged = nil
        settings.resetToDefaults()
    }

    static func testResetToDefaults_resetsProperties() throws {
        let settings = SettingsManager.shared
        settings.maxStorageMB = 5000
        settings.maxStorageMinutes = 120
        settings.exportsDirectoryPath = "/tmp/custom_path"

        settings.resetToDefaults()

        if settings.maxStorageMB != 1000 || settings.maxStorageMinutes != 60 || settings.exportsDirectoryPath != SettingsManager.defaultExportsDirectory.path {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Reset to defaults failed"])
        }
    }
}
