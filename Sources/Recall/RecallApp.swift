import AppKit
import SwiftUI

#if !TEST_RUNNER
@main
struct RecallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
#else
struct RecallApp: App {
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    struct Dependencies {
        var recorder: ScreenCapture
        var chunkStore: ChunkStore
        var settings: SettingsManager
        var menuBar: MenuBarManager
        var handlesTerminationSignal: Bool
        var terminationTimeout: TimeInterval
        var terminationReplier: (Bool) -> Void

        static var live: Dependencies {
            return Dependencies(
                recorder: RecorderEngine.shared,
                chunkStore: ChunkManager.shared,
                settings: SettingsManager.shared,
                menuBar: MenuBarManager.shared,
                handlesTerminationSignal: true,
                terminationTimeout: ConfigManager.shared.terminationTimeout,
                terminationReplier: { NSApp.reply(toApplicationShouldTerminate: $0) }
            )
        }
    }

    /// Nil skips the single-instance check.
    private let instanceLockURL: URL?
    // Built only after the instance lock is held: creating the chunk store starts indexing the
    // chunk directory, which must never happen while another instance is writing to it.
    private let makeDependencies: () -> Dependencies
    private var dependencies: Dependencies?
    private var instanceLock: SingleInstanceLock?
    private var activityMonitor: SystemActivityMonitor?
    private var screenParametersObserver: NSObjectProtocol?
    private var terminationSignalSource: DispatchSourceSignal?
    private var isTerminating = false
    private var hasRepliedToTermination = false

    override convenience init() {
        self.init(instanceLockURL: ConfigManager.shared.instanceLockURL, dependencies: .live)
    }

    init(instanceLockURL: URL?, dependencies: @autoclosure @escaping () -> Dependencies) {
        self.instanceLockURL = instanceLockURL
        self.makeDependencies = dependencies
        super.init()
    }

    deinit {
        if let observer = screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let lockURL = instanceLockURL {
            StorageDirectory.prepare(lockURL.deletingLastPathComponent(), fileSystem: FileManager.default)
            do {
                instanceLock = try SingleInstanceLock(url: lockURL)
            } catch SingleInstanceLock.LockError.alreadyHeld {
                Log.app.notice("Another Recall instance is already running; exiting")
                NSApp.terminate(nil)
                return
            } catch {
                Log.app.error("Single-instance lock unavailable (\(String(describing: error), privacy: .public)); continuing")
            }
        }

        // Set accessory policy to hide Dock icon
        NSApplication.shared.setActivationPolicy(.accessory)

        let dependencies = makeDependencies()
        self.dependencies = dependencies
        let recorder = dependencies.recorder
        let chunkStore = dependencies.chunkStore
        let settings = dependencies.settings

        // Enforce chunk limits when storage settings change; restart capture when its options do
        settings.onSettingsChanged = {
            chunkStore.enforceLimits()
        }
        settings.onRecordingOptionsChanged = {
            recorder.applyRecordingOptions(settings.recordingOptions)
        }
        recorder.applyRecordingOptions(settings.recordingOptions)

        // Initialize status bar manager
        dependencies.menuBar.setupMenuBar()

        let monitor = SystemActivityMonitor(recorder: recorder)
        monitor.start()
        activityMonitor = monitor

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            recorder.handleDisplayConfigurationChange()
        }

        if dependencies.handlesTerminationSignal {
            installTerminationSignalHandler()
        }

        // Start capturing once existing chunks are indexed, so the scan never sees the chunk being written.
        chunkStore.whenLoaded {
            recorder.startContinuousRecording()
        }
    }

    /// Finalizes the chunk in progress before quitting; otherwise the newest footage is lost.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // AppKit asks again if another quit arrives while the first waits (say SIGTERM during a
        // menu quit); that one waits for the same reply instead of cutting the last chunk short.
        if isTerminating {
            return hasRepliedToTermination ? .terminateNow : .terminateLater
        }
        guard let dependencies = dependencies else { return .terminateNow }
        isTerminating = true
        activityMonitor?.stop()

        let reply: () -> Void = { [weak self] in
            guard let self = self, !self.hasRepliedToTermination else { return }
            self.hasRepliedToTermination = true
            dependencies.terminationReplier(true)
        }
        dependencies.recorder.stopStream {
            reply()
        }
        // A run loop timer rather than a dispatch: it still fires while terminate: waits in a nested
        // run loop inside a main-queue block.
        let timeout = Timer(timeInterval: dependencies.terminationTimeout, repeats: false) { _ in
            reply()
        }
        RunLoop.main.add(timeout, forMode: .common)
        return .terminateLater
    }

    /// `kill`, `killall` and `launchctl` send SIGTERM; route it through the normal quit path.
    private func installTerminationSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            Log.app.notice("SIGTERM received; quitting")
            NSApp.terminate(nil)
        }
        source.resume()
        terminationSignalSource = source
    }
}
