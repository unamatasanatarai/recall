import AppKit

struct SettingsWindowControllerTests {
    private static func commandQ(isARepeat: Bool = false, modifiers: NSEvent.ModifierFlags = [.command], characters: String = "q") -> NSEvent? {
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isARepeat,
            keyCode: 12
        )
    }

    static func testWindowSingletonInstanceReuse() throws {
        let controller = SettingsWindowController.shared
        controller.showWindow()
        let first = controller.window
        controller.showWindow()
        try check(first != nil && controller.window === first, "Repeated calls should reuse the single window")
        controller.closeWindow()
    }

    static func testEscapeKeyWindowClosure() throws {
        let prefWindow = PreferencesWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        prefWindow.isReleasedWhenClosed = false
        prefWindow.orderFront(nil)
        prefWindow.cancelOperation(nil)
        try check(!prefWindow.isVisible, "Escape should close the window")
    }

    static func testPreferencesResetButtonAction() throws {
        let settings = SettingsManager.shared
        settings.maxStorageMB = 2500
        settings.maxStorageMinutes = 180

        settings.resetToDefaults()

        try check(settings.maxStorageMB == 1000 && settings.maxStorageMinutes == 60, "Reset to defaults failed")
    }

    static func testSingleCmdQShowsNotificationPrompt() throws {
        let controller = SettingsWindowController.shared
        var quitInvoked = false
        controller.quitHandler = { quitInvoked = true }
        controller.resetQuitPrompt()

        controller.handleCmdQ(now: Date())

        try check(controller.isQuitPromptVisible, "Expected isQuitPromptVisible to be true on first Cmd+Q")
        try check(!quitInvoked, "Expected quit not to be invoked on single Cmd+Q")
        controller.resetQuitPrompt()
    }

    static func testDoubleCmdQQuitsApp() throws {
        let controller = SettingsWindowController.shared
        var quitInvoked = false
        controller.quitHandler = { quitInvoked = true }
        controller.resetQuitPrompt()

        let t0 = Date()
        controller.handleCmdQ(now: t0)
        controller.handleCmdQ(now: t0.addingTimeInterval(0.3))

        try check(quitInvoked, "Expected quit to be invoked on second Cmd+Q")
        try check(!controller.isQuitPromptVisible, "Expected isQuitPromptVisible to reset on double Cmd+Q quit")
        controller.resetQuitPrompt()
    }

    static func testCmdQTimeoutResetsDoublePress() throws {
        let controller = SettingsWindowController.shared
        var quitInvoked = false
        controller.quitHandler = { quitInvoked = true }
        controller.resetQuitPrompt()

        let t0 = Date()
        controller.handleCmdQ(now: t0)
        // Simulate press after threshold has elapsed (e.g. 2.5s > 2.0s threshold)
        controller.handleCmdQ(now: t0.addingTimeInterval(2.5))

        try check(!quitInvoked, "Expected quit NOT to be invoked when presses exceed doublePressThreshold")
        try check(controller.isQuitPromptVisible, "Expected isQuitPromptVisible to be true for new initial press")
        controller.resetQuitPrompt()
    }

    static func testKeyMonitorHandlesCmdQ() throws {
        let controller = SettingsWindowController.shared
        var quitCount = 0
        controller.quitHandler = { quitCount += 1 }
        controller.resetQuitPrompt()

        guard let press = commandQ(), let held = commandQ(isARepeat: true), let plainQ = commandQ(modifiers: []), let other = commandQ(characters: "w") else {
            throw TestFailure(description: "Could not create key events")
        }

        try check(controller.handleKeyDown(press) == nil, "Cmd+Q must be consumed so the main menu does not quit")
        try check(controller.isQuitPromptVisible && quitCount == 0, "The first press should only show the prompt")

        try check(controller.handleKeyDown(held) == nil, "Key repeat must be consumed too")
        try check(quitCount == 0, "Holding Cmd+Q must not count as a second press")

        try check(controller.handleKeyDown(plainQ) === plainQ, "A plain Q must pass through")
        try check(controller.handleKeyDown(other) === other, "Other shortcuts must pass through")

        _ = controller.handleKeyDown(press)
        try check(quitCount == 1, "A second distinct press should quit")
        controller.resetQuitPrompt()
    }

    static func testCloseWindowCleansUpPrompt() throws {
        let controller = SettingsWindowController.shared
        controller.handleCmdQ()
        controller.closeWindow()

        try check(!controller.isQuitPromptVisible, "Expected closeWindow to dismiss quit prompt")
    }
}
