import AppKit
import Foundation

struct SystemProcessAutomationTests {
    static func testRevokeScriptCoversAllPermissions() throws {
        let content = try String(contentsOfFile: "scripts/revoke.sh", encoding: .utf8)
        for perm in ["ScreenCapture", "Accessibility", "Microphone", "Camera", "SystemPolicyAllFiles", "All"] {
            try check(content.contains(perm), "scripts/revoke.sh missing revocation for \(perm)")
        }
    }

    static func testBuildScriptProducesUniversalBinaryWithoutTouchingSigning() throws {
        let content = try String(contentsOfFile: "scripts/build.sh", encoding: .utf8)
        try check(content.contains("for ARCH in arm64 x86_64") && content.contains("lipo -create"), "build.sh should produce a universal binary")
        try check(content.contains("codesign -s - --force --deep --options runtime -r='designated => identifier \"com.recall.app\"' build/Recall.app"), "The signing step must stay as it is")
    }

    static func testAppDelegateLifecycle() throws {
        let recorder = MockScreenCapture()
        let store = MockChunkStore()
        let suiteName = "RecallTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsManager(defaults: defaults)
        var replies: [Bool] = []

        let delegate = AppDelegate(instanceLockURL: nil, dependencies: AppDelegate.Dependencies(
            recorder: recorder,
            chunkStore: store,
            settings: settings,
            menuBar: MenuBarManager(recorder: recorder, chunkStore: store, alertPresenter: MockAlertPresenter(), notifier: MockUserNotifier()),
            handlesTerminationSignal: false,
            terminationTimeout: 5,
            terminationReplier: { replies.append($0) }
        ))

        delegate.applicationDidFinishLaunching(Notification(name: Notification.Name("testNotification")))
        try check(recorder.startCount == 1, "Recording should start once chunks are indexed")
        try check(recorder.appliedOptions == [RecordingOptions()], "Saved options should be applied before recording starts")

        settings.maxStorageMB = 2000
        try check(store.enforceCount == 1, "Changing storage limits should enforce them")
        settings.useHEVC = true
        try check(recorder.appliedOptions.last == RecordingOptions(recordAtNativeResolution: false, preferHEVC: true), "Changing options should reach the recorder")

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try check(recorder.displayChangeCount == 1, "Display changes should reach the recorder")

        let reply = delegate.applicationShouldTerminate(NSApplication.shared)
        try check(reply == .terminateLater, "Termination must wait for the last chunk")
        try check(recorder.stopCount == 1, "The stream should be stopped on quit")
        try check(waitUntil { replies == [true] }, "Termination should be confirmed once the recorder finished, got \(replies)")
        pump(0.1)
        try check(replies == [true], "Termination must be confirmed exactly once")
    }

    static func testTerminationTimesOutIfRecorderHangs() throws {
        // Recorder whose stop never completes.
        final class HangingRecorder: MockScreenCapture {
            override func stopStream(completion: (() -> Void)?) {}
        }
        let recorder = HangingRecorder()
        let store = MockChunkStore()
        var replies: [Bool] = []
        let delegate = AppDelegate(instanceLockURL: nil, dependencies: AppDelegate.Dependencies(
            recorder: recorder,
            chunkStore: store,
            settings: SettingsManager(defaults: UserDefaults(suiteName: "RecallTests-\(UUID().uuidString)")!),
            menuBar: MenuBarManager(recorder: recorder, chunkStore: store, alertPresenter: MockAlertPresenter(), notifier: MockUserNotifier()),
            handlesTerminationSignal: false,
            terminationTimeout: 0.3,
            terminationReplier: { replies.append($0) }
        ))
        delegate.applicationDidFinishLaunching(Notification(name: Notification.Name("testNotification")))

        _ = delegate.applicationShouldTerminate(NSApplication.shared)
        try check(waitUntil(timeout: 2) { replies == [true] }, "A hung recorder must not block quitting forever")
    }

    static func testSecondQuitRequestWaitsForTheFirst() throws {
        final class SlowRecorder: MockScreenCapture {
            override func stopStream(completion: (() -> Void)?) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completion?() }
            }
        }
        let recorder = SlowRecorder()
        let store = MockChunkStore()
        var replies: [Bool] = []
        let delegate = AppDelegate(instanceLockURL: nil, dependencies: AppDelegate.Dependencies(
            recorder: recorder,
            chunkStore: store,
            settings: SettingsManager(defaults: UserDefaults(suiteName: "RecallTests-\(UUID().uuidString)")!),
            menuBar: MenuBarManager(recorder: recorder, chunkStore: store, alertPresenter: MockAlertPresenter(), notifier: MockUserNotifier()),
            handlesTerminationSignal: false,
            terminationTimeout: 5,
            terminationReplier: { replies.append($0) }
        ))
        delegate.applicationDidFinishLaunching(Notification(name: Notification.Name("testNotification")))

        try check(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater, "The first quit should wait")
        // SIGTERM arriving during a menu quit asks again.
        try check(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater, "A second quit must wait too, not cut the last chunk short")
        try check(waitUntil { replies == [true] }, "Both requests should be answered by the one reply, got \(replies)")
        try check(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow, "Once answered, further requests can proceed")
    }

    static func testRecallAppInstantiation() throws {
        let app = RecallApp()
        _ = app.body
    }

    // MARK: - System Activity

    static func testSystemActivityPausesAndResumesRecording() throws {
        let recorder = MockScreenCapture()
        let workspace = NotificationCenter()
        let distributed = NotificationCenter()
        let monitor = SystemActivityMonitor(recorder: recorder, workspaceCenter: workspace, distributedCenter: distributed)
        monitor.start()

        distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        distributed.post(name: Notification.Name("com.apple.screensaver.didstart"), object: nil)

        let paused = recorder.pauseCalls.filter { $0.paused }.map(\.reason)
        try check(paused == [.screenLocked, .displaySleep, .systemSleep, .screenSaver], "Unexpected pauses \(paused)")

        distributed.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        let resumed = Set(recorder.pauseCalls.filter { !$0.paused }.map(\.reason))
        try check(resumed == [.screenLocked, .screenSaver, .systemSleep, .displaySleep], "Every system pause should be lifted, got \(resumed)")

        monitor.stop()
        let count = recorder.pauseCalls.count
        distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        try check(recorder.pauseCalls.count == count, "Stopped monitor must not react")
    }

    // MARK: - Single Instance

    static func testSecondInstanceCannotTakeTheLock() throws {
        let url = TestSandbox.makeDirectory("lock").appendingPathComponent(".instance.lock")
        var first: SingleInstanceLock? = try SingleInstanceLock(url: url)

        do {
            _ = try SingleInstanceLock(url: url)
            throw TestFailure(description: "A second lock on the same file must fail")
        } catch SingleInstanceLock.LockError.alreadyHeld {
            // Expected
        }

        first = nil
        _ = first
        let reacquired = try? SingleInstanceLock(url: url)
        try check(reacquired != nil, "The lock should be free once released")
    }

    // MARK: - Login Item

    static func testLaunchAgentLoginItem() throws {
        let fileSystem = MockFileSystem()
        let agents = URL(fileURLWithPath: "/tmp/recall_agents_\(UUID().uuidString)")
        let controller = LoginItemController(
            label: "com.recall.app",
            executablePath: "/Applications/Recall.app/Contents/MacOS/Recall",
            launchAgentsDirectory: agents,
            fileSystem: fileSystem,
            usesServiceManagement: false
        )
        try check(!controller.isEnabled, "Login item should start disabled")

        try controller.setEnabled(true)
        let plistURL = agents.appendingPathComponent("com.recall.app.plist")
        guard let data = fileSystem.storedData(at: plistURL),
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw TestFailure(description: "LaunchAgent plist was not written")
        }
        try check(plist["Label"] as? String == "com.recall.app", "Unexpected label")
        try check(plist["ProgramArguments"] as? [String] == ["/Applications/Recall.app/Contents/MacOS/Recall"], "Unexpected program")
        try check(plist["RunAtLoad"] as? Bool == true, "Agent must run at load")
        try check(controller.isEnabled, "Login item should report enabled")

        try controller.setEnabled(false)
        try check(!controller.isEnabled, "Login item should be removed")
    }

    // MARK: - Notifications

    static func testNotifierFallsBackToAlertsOutsideAppBundle() throws {
        let notifier = SystemNotifier()
        let alert = MockAlertPresenter()
        notifier.alertPresenter = alert

        notifier.exportFailed("The disk is full.")
        try check(alert.errors.map(\.message) == ["The disk is full."], "Failures must be shown even without Notification Center")
        notifier.exportSucceeded(URL(fileURLWithPath: "/tmp/clip.mp4"))
        try check(alert.errors.count == 1, "Success needs no alert; the clip is revealed in Finder")
    }
}
