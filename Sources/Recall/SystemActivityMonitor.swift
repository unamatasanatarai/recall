import AppKit

/// Pauses recording while nobody can be looking at the screen: when it is locked, the
/// screensaver runs, the display sleeps, or the Mac sleeps. Otherwise hours of a static
/// lock screen would push real footage out of the buffer.
final class SystemActivityMonitor {
    private let recorder: ScreenCapture
    private let workspaceCenter: NotificationCenter
    private let distributedCenter: NotificationCenter
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(
        recorder: ScreenCapture,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributedCenter: NotificationCenter = DistributedNotificationCenter.default()
    ) {
        self.recorder = recorder
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
    }

    deinit {
        stop()
    }

    func start() {
        guard observers.isEmpty else { return }

        observe(workspaceCenter, NSWorkspace.willSleepNotification) { $0.setPaused(true, reason: .systemSleep) }
        observe(workspaceCenter, NSWorkspace.didWakeNotification) {
            $0.setPaused(false, reason: .systemSleep)
            $0.setPaused(false, reason: .displaySleep)
        }
        observe(workspaceCenter, NSWorkspace.screensDidSleepNotification) { $0.setPaused(true, reason: .displaySleep) }
        observe(workspaceCenter, NSWorkspace.screensDidWakeNotification) { $0.setPaused(false, reason: .displaySleep) }

        observe(distributedCenter, Notification.Name("com.apple.screenIsLocked")) { $0.setPaused(true, reason: .screenLocked) }
        observe(distributedCenter, Notification.Name("com.apple.screenIsUnlocked")) {
            // Unlocking also ends a screensaver whose stop notification may have been missed.
            $0.setPaused(false, reason: .screenLocked)
            $0.setPaused(false, reason: .screenSaver)
        }
        observe(distributedCenter, Notification.Name("com.apple.screensaver.didstart")) { $0.setPaused(true, reason: .screenSaver) }
        observe(distributedCenter, Notification.Name("com.apple.screensaver.didstop")) { $0.setPaused(false, reason: .screenSaver) }
    }

    func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping (ScreenCapture) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            action(self.recorder)
        }
        observers.append((center, token))
    }
}
