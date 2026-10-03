import AppKit
import SwiftUI

@main
struct RecallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set accessory policy to hide Dock icon
        NSApplication.shared.setActivationPolicy(.accessory)
        
        // Connect settings callback to enforce chunk limits when settings change
        SettingsManager.shared.onSettingsChanged = {
            ChunkManager.shared.enforceLimits()
        }

        // Initialize status bar manager
        MenuBarManager.shared.setupMenuBar()

        // Autostart screen capture on application launch
        RecorderEngine.shared.startContinuousRecording()
    }

    func applicationWillTerminate(_ notification: Notification) {
        RecorderEngine.shared.stopStream()
    }
}
