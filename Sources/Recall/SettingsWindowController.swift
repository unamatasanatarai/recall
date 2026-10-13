import AppKit
import SwiftUI

final class PreferencesWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        self.close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "q" {
            SettingsWindowController.shared.handleCmdQ()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class SettingsWindowController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private(set) var window: NSWindow?
    @Published var isQuitPromptVisible: Bool = false

    private(set) var lastCmdQPressTime: Date?
    private var quitPromptResetTimer: Timer?
    var doublePressThreshold: TimeInterval = ConfigManager.shared.doublePressQuitThreshold
    var quitHandler: () -> Void = { MenuBarManager.shared.quitApp() }
    private var keyEventMonitor: Any?

    var isWindowVisible: Bool {
        return window?.isVisible ?? false
    }

    override private init() {
        super.init()
    }

    func showWindow() {
        if let window = window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            startMonitoringKeyEvents()
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = PreferencesWindow(
            contentViewController: hostingController
        )
        window.title = "Recall Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        startMonitoringKeyEvents()
    }

    func closeWindow() {
        stopMonitoringKeyEvents()
        resetQuitPrompt()
        window?.close()
    }

    func handleCmdQ(now: Date = Date()) {
        if let lastTime = lastCmdQPressTime {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed < 0.05 {
                // Ignore duplicate event dispatched in the same keystroke
                return
            }
            if elapsed <= doublePressThreshold {
                // Second Cmd+Q within threshold -> close settings and quit application
                resetQuitPrompt()
                closeWindow()
                quitHandler()
                return
            }
        }

        // First press (or previous press timed out)
        lastCmdQPressTime = now
        isQuitPromptVisible = true
        NotificationCenter.default.post(name: Notification.Name("RecallQuitPromptNotification"), object: nil)

        quitPromptResetTimer?.invalidate()
        quitPromptResetTimer = Timer.scheduledTimer(withTimeInterval: doublePressThreshold, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.resetQuitPrompt()
            }
        }
    }

    func resetQuitPrompt() {
        lastCmdQPressTime = nil
        isQuitPromptVisible = false
        quitPromptResetTimer?.invalidate()
        quitPromptResetTimer = nil
    }

    func startMonitoringKeyEvents() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isWindowVisible else { return event }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "q" {
                self.handleCmdQ()
                return nil
            }
            return event
        }
    }

    func stopMonitoringKeyEvents() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        stopMonitoringKeyEvents()
        resetQuitPrompt()
    }
}

