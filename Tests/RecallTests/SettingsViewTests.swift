import Foundation

struct SettingsViewTests {
    static func testUsageStatsFormatting() throws {
        let duration: TimeInterval = 330.0 // 5m 30s
        let maxMins = 60
        let totalSeconds = Int(duration)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        let formatted = "\(mins)m \(secs)s / \(maxMins)m max"

        if formatted != "5m 30s / 60m max" {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected '5m 30s / 60m max', got '\(formatted)'"])
        }
    }

    static func testUsageStatsSizeFormatting() throws {
        let bytes: Int64 = 45 * 1024 * 1024 + Int64(0.2 * 1024 * 1024)
        let maxMB = 1000
        let mb = Double(bytes) / (1024.0 * 1024.0)
        let formatted = String(format: "%.1f MB / %d MB max", mb, maxMB)

        if !formatted.contains("MB") || !formatted.contains("1000 MB max") {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Size formatting mismatch"])
        }
    }

    static func testTotalClipsCountUpdate() throws {
        let store = MockChunkStore()
        if store.chunks.count != 0 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected initial chunk count 0"])
        }
    }

    static func testStepperIncrements() throws {
        var mb = 1000
        var mins = 60
        mb += 50
        mins += 15

        if mb != 1050 || mins != 75 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Stepper increment math mismatch"])
        }
    }

    static func testResetStorageDefaults() throws {
        let settings = SettingsManager.shared
        settings.maxStorageMB = 2500
        settings.maxStorageMinutes = 120

        var purgedCalled = false
        let view = SettingsView(settings: settings, onPurgeRecordings: {
            purgedCalled = true
        })

        view.resetStorageMB()
        if settings.maxStorageMB != 1000 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected resetStorageMB to restore 1000 MB default"])
        }

        view.resetStorageMinutes()
        if settings.maxStorageMinutes != 60 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected resetStorageMinutes to restore 60 minutes default"])
        }

        view.onPurgeRecordings()
        if !purgedCalled {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected onPurgeRecordings callback to execute"])
        }
    }
}

