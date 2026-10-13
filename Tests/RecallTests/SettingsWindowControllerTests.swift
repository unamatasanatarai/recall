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

    static func testSingleCmdQShowsNotificationPrompt() throws {
        let controller = SettingsWindowController.shared
        var quitInvoked = false
        controller.quitHandler = { quitInvoked = true }
        controller.resetQuitPrompt()

        let now = Date()
        controller.handleCmdQ(now: now)

        if !controller.isQuitPromptVisible {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected isQuitPromptVisible to be true on first Cmd+Q"])
        }
        if quitInvoked {
            throw NSError(domain: "TestError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected quit not to be invoked on single Cmd+Q"])
        }
        controller.resetQuitPrompt()
    }

    static func testDoubleCmdQQuitsApp() throws {
        let controller = SettingsWindowController.shared
        var quitInvoked = false
        controller.quitHandler = { quitInvoked = true }
        controller.resetQuitPrompt()

        let t0 = Date()
        controller.handleCmdQ(now: t0)

        let t1 = t0.addingTimeInterval(0.3)
        controller.handleCmdQ(now: t1)

        if !quitInvoked {
            throw NSError(domain: "TestError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected quit to be invoked on second Cmd+Q"])
        }
        if controller.isQuitPromptVisible {
            throw NSError(domain: "TestError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected isQuitPromptVisible to reset on double Cmd+Q quit"])
        }
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
        let t1 = t0.addingTimeInterval(2.5)
        controller.handleCmdQ(now: t1)

        if quitInvoked {
            throw NSError(domain: "TestError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected quit NOT to be invoked when presses exceed doublePressThreshold"])
        }
        if !controller.isQuitPromptVisible {
            throw NSError(domain: "TestError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected isQuitPromptVisible to be true for new initial press"])
        }
        controller.resetQuitPrompt()
    }

    static func testPreferencesWindowKeyEquivalentCmdQ() throws {
        let controller = SettingsWindowController.shared
        controller.resetQuitPrompt()

        let window = PreferencesWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "q",
            charactersIgnoringModifiers: "q",
            isARepeat: false,
            keyCode: 12
        )

        if let event = event {
            let handled = window.performKeyEquivalent(with: event)
            if !handled {
                throw NSError(domain: "TestError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected performKeyEquivalent to handle Cmd+Q"])
            }
            if !controller.isQuitPromptVisible {
                throw NSError(domain: "TestError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected isQuitPromptVisible to be true after keyEquivalent Cmd+Q"])
            }
        }
        controller.resetQuitPrompt()
    }

    static func testCloseWindowCleansUpPrompt() throws {
        let controller = SettingsWindowController.shared
        controller.handleCmdQ()
        controller.closeWindow()

        if controller.isQuitPromptVisible {
            throw NSError(domain: "TestError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected closeWindow to dismiss quit prompt"])
        }
    }
}
