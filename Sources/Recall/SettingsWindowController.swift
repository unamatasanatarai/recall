import AppKit
import SwiftUI

final class PreferencesWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        self.close()
    }
}

final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    override private init() {
        super.init()
    }

    func showWindow() {
        if let window = window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
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

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func closeWindow() {
        window?.close()
    }
}
