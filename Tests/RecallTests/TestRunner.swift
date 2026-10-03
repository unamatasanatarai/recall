import Foundation

@main
struct TestRunner {
    static func main() {
        print("==> Running Recall Unit Tests...")
        var passedCount = 0
        var failedCount = 0

        func runTest(_ name: String, _ testBlock: () throws -> Void) {
            print("  Running \(name)...", terminator: " ")
            do {
                try testBlock()
                print("✅ PASSED")
                passedCount += 1
            } catch {
                print("❌ FAILED: \(error)")
                failedCount += 1
            }
        }

        runTest("ChunkManager.testEnforceLimits_purgesOldestWhenOverSizeBytes") {
            try ChunkManagerTests.testEnforceLimits_purgesOldestWhenOverSizeBytes()
        }

        runTest("ChunkManager.testPurgeAllChunks_removesAllRegisteredFiles") {
            try ChunkManagerTests.testPurgeAllChunks_removesAllRegisteredFiles()
        }

        runTest("SettingsManager.testResetToDefaults_resetsProperties") {
            try SettingsManagerTests.testResetToDefaults_resetsProperties()
        }

        runTest("SettingsManager.testStorageConfigCalculations") {
            try SettingsManagerTests.testStorageConfigCalculations()
        }

        print("\nSummary: \(passedCount) passed, \(failedCount) failed.\n")
        if failedCount > 0 {
            exit(1)
        }
    }
}
