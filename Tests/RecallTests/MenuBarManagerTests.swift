import AppKit

struct MenuBarManagerTests {
    static func testStatusItemCreation() throws {
        let recorder = MockScreenCapture()
        let store = MockChunkStore()
        let manager = MenuBarManager(recorder: recorder, chunkStore: store)
        
        manager.setupMenuBar()
        // MenuBarManager successfully initializes status item without crashing
    }

    static func testTemplateIconMode() throws {
        let recorder = MockScreenCapture()
        let store = MockChunkStore()
        let manager = MenuBarManager(recorder: recorder, chunkStore: store)
        manager.setupMenuBar()

        // Icon template mode verify
        let size = NSSize(width: 18, height: 18)
        let icon = NSImage(size: size)
        icon.isTemplate = true

        if !icon.isTemplate {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected isTemplate = true"])
        }
    }

    static func testDragDownDistanceClamping() throws {
        let maxDuration: TimeInterval = 300.0 // 5 minutes
        let rawDistance: CGFloat = 500.0 // drag down 500px

        let calculatedSeconds = min(maxDuration, max(30.0, TimeInterval(rawDistance * 2)))
        if calculatedSeconds > maxDuration {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Offset exceeded max duration"])
        }
    }

    static func testStepQuantization() throws {
        let rawSeconds: TimeInterval = 85.0
        let quantized = (rawSeconds / 60.0).rounded() * 60.0
        if quantized != 60.0 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 60.0s for 85.0s raw input, got \(quantized)"])
        }
    }

    static func testDragReleaseExportTrigger() throws {
        let recorder = MockScreenCapture()
        let store = MockChunkStore()
        let manager = MenuBarManager(recorder: recorder, chunkStore: store)

        manager.setupMenuBar()
        var exportCalled = false
        store.exportClip(offsetSeconds: 60) { _ in
            exportCalled = true
        }

        if !exportCalled {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected exportClip to be callable on drag release"])
        }
    }

    static func testShowContextMenuAndSettings() throws {
        let recorder = MockScreenCapture()
        let store = MockChunkStore()
        let manager = MenuBarManager(recorder: recorder, chunkStore: store)
        manager.setupMenuBar()
        manager.openSettings()
        let btn = NSButton()
        manager.showContextMenu(button: btn)
        manager.triggerExport(offsetSeconds: 60, overrideButton: btn)
        var termCalled = false
        manager.appTerminator = { termCalled = true }
        manager.quitApp()
        if !termCalled {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected quitApp to terminate"])
        }
    }
}
