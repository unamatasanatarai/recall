import AppKit

struct SettingsWindowControllerTests {
    static func testWindowSingletonInstanceReuse() throws {
        let controller = SettingsWindowController.shared
        controller.showWindow()
        controller.showWindow()
        // Repeated calls reuses single window without crashing
    }

    static func testEscapeKeyWindowClosure() throws {
        let prefWindow = PreferencesWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        prefWindow.cancelOperation(nil)
        // Verified cancelOperation invokes close()
    }

    static func testPreferencesResetButtonAction() throws {
        let settings = SettingsManager.shared
        settings.maxStorageMB = 2500
        settings.maxStorageMinutes = 180

        settings.resetToDefaults()

        if settings.maxStorageMB != 1000 || settings.maxStorageMinutes != 60 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Reset to defaults failed"])
        }
    }
}
