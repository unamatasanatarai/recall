import AppKit
import Foundation

@main
struct TestRunner {
    static func main() {
        // Like the app, every test runs with an NSApplication (it registers the modal run loop
        // modes as common modes, which termination handling relies on).
        _ = NSApplication.shared

        // Every test runs against a throwaway cache directory, so even code that falls back to
        // the default locations can never touch real recordings.
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("RecallTests-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        setenv("RECALL_CACHE_DIR", sandbox.path, 1)

        // Optional substring filter: build/test_runner ChunkWriter
        let filter = CommandLine.arguments.dropFirst().first

        print("==> Running Recall Unit Tests...")
        var passedCount = 0
        var failedCount = 0

        for test in TestRegistry.all where filter.map({ test.name.contains($0) }) ?? true {
            print("  Running \(test.name)...", terminator: " ")
            do {
                try test.run()
                print("✅ PASSED")
                passedCount += 1
            } catch {
                print("❌ FAILED: \(error)")
                failedCount += 1
            }
        }

        try? FileManager.default.removeItem(at: sandbox)

        print("\nSummary: \(passedCount) passed, \(failedCount) failed.\n")
        if failedCount > 0 || passedCount == 0 {
            exit(1)
        }
    }
}
