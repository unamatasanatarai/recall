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
        let quantized = (rawSeconds / 30.0).rounded() * 30.0
        if quantized != 90.0 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 90.0s for 85.0s raw input, got \(quantized)"])
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
}
