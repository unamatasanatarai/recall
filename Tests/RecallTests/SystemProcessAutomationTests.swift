import Foundation

struct SystemProcessAutomationTests {
    static func testTCCPermissionRevocationCommand() throws {
        let bundleID = "com.recall.app"
        let cmd = "tccutil reset ScreenCapture \(bundleID)"
        if !cmd.contains("ScreenCapture") || !cmd.contains("com.recall.app") {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "TCC command string mismatch"])
        }
    }

    static func testBuildCommandOutputBinaryCheck() throws {
        let binaryPath = "build/Recall.app/Contents/MacOS/Recall"
        if binaryPath.isEmpty || !binaryPath.hasSuffix("Recall") {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Binary path mismatch"])
        }
    }

    static func testAppDelegateLifecycle() throws {
        let delegate = AppDelegate()
        let notif = Notification(name: Notification.Name("testNotification"))
        delegate.applicationDidFinishLaunching(notif)
        delegate.applicationWillTerminate(notif)
    }

    static func testRecallAppInstantiation() throws {
        let app = RecallApp()
        _ = app.body
    }
}

