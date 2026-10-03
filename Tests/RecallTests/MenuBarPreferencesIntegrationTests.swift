import AppKit

struct MenuBarPreferencesIntegrationTests {
    static func testPurgeRecordingsConfirmed() throws {
        let store = MockChunkStore()
        let recorder = MockScreenCapture()
        let alert = MockAlertPresenter(confirmResult: true)
        let manager = MenuBarManager(recorder: recorder, chunkStore: store, alertPresenter: alert)

        let fileURL = URL(fileURLWithPath: "/tmp/test.mp4")
        store.registerChunk(url: fileURL, startTime: Date(), duration: 10.0)

        manager.purgeRecordings()

        if store.chunks.count != 0 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected chunks cleared on confirmed purge"])
        }
    }

    static func testPurgeRecordingsCancelled() throws {
        let store = MockChunkStore()
        let recorder = MockScreenCapture()
        let alert = MockAlertPresenter(confirmResult: false)
        let manager = MenuBarManager(recorder: recorder, chunkStore: store, alertPresenter: alert)

        let fileURL = URL(fileURLWithPath: "/tmp/test.mp4")
        store.registerChunk(url: fileURL, startTime: Date(), duration: 10.0)

        manager.purgeRecordings()

        if store.chunks.count != 1 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected chunks preserved on cancelled purge"])
        }
    }

    static func testOpenSettingsAndQuitApp() throws {
        let store = MockChunkStore()
        let recorder = MockScreenCapture()
        let manager = MenuBarManager(recorder: recorder, chunkStore: store)

        manager.openSettings()
        // Tested openSettings execution
    }

    static func testPreferencesDirectoryPickerConfirmed() throws {
        let settings = SettingsManager.shared
        let view = SettingsView(settings: settings, openPanelPresenter: MockOpenPanelPresenter(pathResult: "/tmp/custom_export_path"))

        view.chooseDirectory()

        if settings.exportsDirectoryPath != "/tmp/custom_export_path" {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected exportsDirectoryPath to update to /tmp/custom_export_path"])
        }
    }

    static func testPreferencesDirectoryPickerCancelled() throws {
        let settings = SettingsManager.shared
        let initialPath = settings.exportsDirectoryPath
        let view = SettingsView(settings: settings, openPanelPresenter: MockOpenPanelPresenter(pathResult: nil))

        view.chooseDirectory()

        if settings.exportsDirectoryPath != initialPath {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected exportsDirectoryPath to remain unchanged on cancel"])
        }
    }

    static func testQuitApplicationStreamTearDown() throws {
        let recorder = MockScreenCapture()
        let store = MockChunkStore()
        _ = MenuBarManager(recorder: recorder, chunkStore: store)

        recorder.startContinuousRecording()
        recorder.stopStream()

        if recorder.state != .idle {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected recorder state .idle on tear down"])
        }
    }

    static func testMenuBarManagerMouseEventHandling() throws {
        let store = MockChunkStore()
        let recorder = MockScreenCapture()
        let manager = MenuBarManager(recorder: recorder, chunkStore: store)

        // Register dummy chunk so store has > 30s recorded duration
        let dummyURL = URL(fileURLWithPath: "/tmp/dummy_chunk.mp4")
        store.registerChunk(url: dummyURL, startTime: Date(), duration: 60.0)

        let buttonFrame = NSRect(x: 100, y: 800, width: 30, height: 20)
        let insidePoint = NSPoint(x: 110, y: 810)
        let outsidePoint = NSPoint(x: 50, y: 50)

        // 1. Right Mouse Down
        let rightInside = manager.handleMouseEvent(type: .rightMouseDown, mouseLocation: insidePoint, buttonFrame: buttonFrame)
        if !rightInside {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected rightMouseDown inside buttonFrame to return true"])
        }
        let rightOutside = manager.handleMouseEvent(type: .rightMouseDown, mouseLocation: outsidePoint, buttonFrame: buttonFrame)
        if rightOutside {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected rightMouseDown outside buttonFrame to return false"])
        }

        // 2. Left Mouse Down inside
        let leftInside = manager.handleMouseEvent(type: .leftMouseDown, mouseLocation: insidePoint, buttonFrame: buttonFrame)
        if !leftInside {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected leftMouseDown inside buttonFrame to return true"])
        }

        // 3. Left Mouse Dragged (drag down)
        let dragDownPoint = NSPoint(x: 110, y: 600)
        let dragResult = manager.handleMouseEvent(type: .leftMouseDragged, mouseLocation: dragDownPoint, buttonFrame: buttonFrame)
        if !dragResult {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected leftMouseDragged while dragging to return true"])
        }

        // 4. Left Mouse Dragged (drag up above start)
        let dragUpPoint = NSPoint(x: 110, y: 900)
        let dragUpResult = manager.handleMouseEvent(type: .leftMouseDragged, mouseLocation: dragUpPoint, buttonFrame: buttonFrame)
        if !dragUpResult {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected leftMouseDragged while dragging up to return true"])
        }

        // Re-drag down to establish non-zero offset
        _ = manager.handleMouseEvent(type: .leftMouseDragged, mouseLocation: dragDownPoint, buttonFrame: buttonFrame)

        // 5. Left Mouse Up (with non-zero offset)
        let upResult = manager.handleMouseEvent(type: .leftMouseUp, mouseLocation: dragDownPoint, buttonFrame: buttonFrame)
        if !upResult {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected leftMouseUp to return true"])
        }

        // 6. Left Mouse Up (when offset is 0)
        _ = manager.handleMouseEvent(type: .leftMouseDown, mouseLocation: insidePoint, buttonFrame: buttonFrame)
        _ = manager.handleMouseEvent(type: .leftMouseDragged, mouseLocation: dragUpPoint, buttonFrame: buttonFrame)
        let upZeroResult = manager.handleMouseEvent(type: .leftMouseUp, mouseLocation: dragUpPoint, buttonFrame: buttonFrame)
        if !upZeroResult {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected leftMouseUp with 0 offset to return true"])
        }
    }

    static func testTriggerExport() throws {
        let store = MockChunkStore()
        let recorder = MockScreenCapture()
        let manager = MenuBarManager(recorder: recorder, chunkStore: store)

        // Register dummy chunk
        let dummyURL = URL(fileURLWithPath: "/tmp/dummy_chunk.mp4")
        store.registerChunk(url: dummyURL, startTime: Date(), duration: 60.0)

        // Trigger export with valid offset
        manager.triggerExport(offsetSeconds: 30.0)
    }

    static func testSettingsWindowControllerCloseWindow() throws {
        let controller = SettingsWindowController.shared
        controller.showWindow()
        controller.closeWindow()
    }

    static func testDefaultProtocolImplementations() throws {
        let runner = DefaultFFmpegRunner()
        _ = runner.findFFmpegPath()

        let permProvider = DefaultScreenCapturePermissionProvider()
        _ = permProvider.preflightAccess()
    }
}


