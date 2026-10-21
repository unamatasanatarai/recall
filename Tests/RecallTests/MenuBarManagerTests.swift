import AppKit

struct MenuBarManagerTests {
    private static func makeManager(
        recorder: MockScreenCapture = MockScreenCapture(),
        store: MockChunkStore = MockChunkStore(),
        alert: MockAlertPresenter = MockAlertPresenter(),
        notifier: MockUserNotifier = MockUserNotifier()
    ) -> MenuBarManager {
        let manager = MenuBarManager(recorder: recorder, chunkStore: store, alertPresenter: alert, notifier: notifier)
        manager.fileRevealer = { _ in }
        return manager
    }

    static func testStatusItemCreation() throws {
        let manager = makeManager()
        manager.setupMenuBar()
        try check(manager.statusButton?.image != nil, "Status item should have an icon")
    }

    static func testIconsAreTemplatesForEveryState() throws {
        for style in [MenuBarManager.IconStyle.recording, .paused, .inactive] {
            let icon = MenuBarManager.createMenuBarIcon(style: style)
            try check(icon.isTemplate, "Icon \(style) must be a template image")
            try check(icon.size == NSSize(width: 18, height: 18), "Icon \(style) has the wrong size")
        }
    }

    static func testIconStyleAndDescriptionFollowState() throws {
        try check(MenuBarManager.iconStyle(for: .recording) == .recording, "Recording icon expected")
        try check(MenuBarManager.iconStyle(for: .paused) == .paused, "Paused icon expected")
        try check(MenuBarManager.iconStyle(for: .idle) == .inactive, "Inactive icon expected when idle")
        try check(MenuBarManager.iconStyle(for: .error("x")) == .inactive, "Inactive icon expected on error")
        try check(MenuBarManager.statusDescription(for: .error("Disk full")) == "Not recording. Disk full", "Errors should be explained")
    }

    static func testStatusAppearanceTracksRecorderState() throws {
        let recorder = MockScreenCapture()
        let manager = makeManager(recorder: recorder)
        manager.setupMenuBar()

        recorder.setState(.recording)
        try check(waitUntil { manager.statusButton?.toolTip == "Recall: Recording" }, "Tooltip should show recording")
        recorder.setState(.error("Recording failed: disk full"))
        try check(waitUntil { manager.statusButton?.toolTip == "Recall: Not recording. Recording failed: disk full" }, "Tooltip should explain the failure, got \(String(describing: manager.statusButton?.toolTip))")
    }

    static func testSnappedOffsetUsesFineStepsForRecentHistory() throws {
        try check(MenuBarManager.snappedOffset(progress: 0.01, available: 600) == 10, "The first step should be 10 s")
        try check(MenuBarManager.snappedOffset(progress: 1.0, available: 600) == 600, "The end of the drag should select everything")
        try check(MenuBarManager.snappedOffset(progress: 0.5, available: 25) == 20, "Expected the middle snap point of [10, 20, 25]")
        try check(MenuBarManager.snappedOffset(progress: 0.01, available: 4) == 4, "Short buffers export what exists")
        try check(MenuBarManager.snappedOffset(progress: 1.0, available: 0.5) == 0, "Nothing to export below the minimum")

        var previous: TimeInterval = 0
        for step in 1...100 {
            let value = MenuBarManager.snappedOffset(progress: CGFloat(step) / 100, available: 7200)
            try check(value >= previous, "Offsets must not decrease as the drag grows")
            previous = value
        }
    }

    static func testDragReleaseExportsFootageEndingAtMouseDown() throws {
        let recorder = MockScreenCapture()
        let store = MockChunkStore()
        store.usageOverride = ChunkUsage(count: 12, totalBytes: 12_000, totalDuration: 120)
        let manager = makeManager(recorder: recorder, store: store)

        let buttonFrame = NSRect(x: 100, y: 800, width: 30, height: 20)
        let beforeGesture = Date()
        manager.handleMouseEvent(type: .leftMouseDown, mouseLocation: NSPoint(x: 110, y: 810), buttonFrame: buttonFrame)
        let afterMouseDown = Date()
        pump(0.1)
        manager.handleMouseEvent(type: .leftMouseDragged, mouseLocation: NSPoint(x: 110, y: 600), buttonFrame: buttonFrame)
        manager.handleMouseEvent(type: .leftMouseUp, mouseLocation: NSPoint(x: 110, y: 600), buttonFrame: buttonFrame)

        try check(recorder.flushCount == 1, "The chunk in progress should be flushed before exporting")
        guard let request = store.exportRequests.first else {
            throw TestFailure(description: "Expected an export request")
        }
        try check(request.footageSeconds >= 10 && request.footageSeconds <= 120, "Unexpected footage \(request.footageSeconds)")
        try check(request.endDate >= beforeGesture && request.endDate <= afterMouseDown, "The clip must end when the drag started, not when it ended")
    }

    static func testDraggingWithoutFootageExplainsWhy() throws {
        let notifier = MockUserNotifier()
        let store = MockChunkStore()
        let manager = makeManager(store: store, notifier: notifier)

        let buttonFrame = NSRect(x: 100, y: 800, width: 30, height: 20)
        manager.handleMouseEvent(type: .leftMouseDown, mouseLocation: NSPoint(x: 110, y: 810), buttonFrame: buttonFrame)
        manager.handleMouseEvent(type: .leftMouseDragged, mouseLocation: NSPoint(x: 110, y: 600), buttonFrame: buttonFrame)
        manager.handleMouseEvent(type: .leftMouseUp, mouseLocation: NSPoint(x: 110, y: 600), buttonFrame: buttonFrame)

        try check(store.exportRequests.isEmpty, "Nothing should be exported")
        try check(notifier.informed == ["Nothing to export yet"], "The user should be told why nothing happened, got \(notifier.informed)")
    }

    static func testClickWithoutDragDoesNothing() throws {
        let notifier = MockUserNotifier()
        let store = MockChunkStore()
        store.usageOverride = ChunkUsage(count: 1, totalBytes: 1, totalDuration: 60)
        let manager = makeManager(store: store, notifier: notifier)

        let buttonFrame = NSRect(x: 100, y: 800, width: 30, height: 20)
        try check(manager.handleMouseEvent(type: .leftMouseDown, mouseLocation: NSPoint(x: 110, y: 810), buttonFrame: buttonFrame), "Mouse down on the icon should be intercepted")
        manager.handleMouseEvent(type: .leftMouseUp, mouseLocation: NSPoint(x: 110, y: 810), buttonFrame: buttonFrame)

        try check(store.exportRequests.isEmpty && notifier.informed.isEmpty, "A plain click should neither export nor notify")
    }

    static func testRightClickOutsideButtonPassesThrough() throws {
        let manager = makeManager()
        let buttonFrame = NSRect(x: 100, y: 800, width: 30, height: 20)
        try check(!manager.handleMouseEvent(type: .rightMouseDown, mouseLocation: NSPoint(x: 50, y: 50), buttonFrame: buttonFrame), "Clicks elsewhere must not be intercepted")
        try check(!manager.handleMouseEvent(type: .leftMouseDragged, mouseLocation: NSPoint(x: 50, y: 50), buttonFrame: buttonFrame), "Drags without a gesture must not be intercepted")
    }

    static func testSecondExportWaitsForFirst() throws {
        let store = MockChunkStore()
        store.completesExportsImmediately = false
        let notifier = MockUserNotifier()
        let manager = makeManager(store: store, notifier: notifier)

        manager.triggerExport(offsetSeconds: 30)
        manager.triggerExport(offsetSeconds: 30)
        try check(store.exportRequests.count == 1, "Only one export may run at a time")
        try check(notifier.informed == ["Export in progress"], "The second request should be explained")

        store.completePendingExport()
        try check(!manager.isExporting, "The guard should reset when the export completes")
        manager.triggerExport(offsetSeconds: 30)
        try check(store.exportRequests.count == 2, "A new export should be possible afterwards")
    }

    static func testExportSuccessRevealsAndNotifies() throws {
        let store = MockChunkStore()
        let notifier = MockUserNotifier()
        let manager = makeManager(store: store, notifier: notifier)
        var revealed: [URL] = []
        manager.fileRevealer = { revealed.append($0) }

        manager.triggerExport(offsetSeconds: 30, overrideButton: NSButton())
        try check(revealed == [URL(fileURLWithPath: "/tmp/mock_export.mp4")], "The clip should be revealed in Finder")
        try check(notifier.succeeded.count == 1 && notifier.failures.isEmpty, "Success should be reported")
    }

    static func testExportFailureIsReported() throws {
        let store = MockChunkStore()
        store.exportResult = .failure(.failed("The disk is full."))
        let notifier = MockUserNotifier()
        let manager = makeManager(store: store, notifier: notifier)

        manager.triggerExport(offsetSeconds: 30)
        try check(notifier.failures == ["The disk is full."], "Failures should be reported, got \(notifier.failures)")
        try check(!manager.isExporting, "The export should be finished")
    }

    static func testContextMenuShowsStatusAndPause() throws {
        let recorder = MockScreenCapture()
        let manager = makeManager(recorder: recorder)

        recorder.setState(.recording)
        var titles = manager.buildContextMenu().items.map(\.title)
        try check(titles.first == "Recording", "Status line expected first, got \(titles)")
        try check(titles.contains("Pause Recording") && titles.contains("Settings") && titles.contains("Quit Recall"), "Unexpected menu \(titles)")

        manager.togglePause()
        try check(recorder.pauseCalls.last.map { $0.paused && $0.reason == .user } == true, "Pause should be a user pause")
        recorder.setState(.paused)
        titles = manager.buildContextMenu().items.map(\.title)
        try check(titles.contains("Resume Recording"), "Expected Resume once paused, got \(titles)")

        recorder.setState(.error(RecorderEngine.permissionMessage))
        titles = manager.buildContextMenu().items.map(\.title)
        try check(titles.contains("Open Screen Recording Settings…"), "Expected a shortcut to the permission settings, got \(titles)")
    }

    static func testShowContextMenuAndSettings() throws {
        let manager = makeManager()
        manager.setupMenuBar()
        manager.openSettings()
        manager.showContextMenu(button: NSButton())
        SettingsWindowController.shared.closeWindow()
    }

    static func testPurgeConfirmedDiscardsEverything() throws {
        let recorder = MockScreenCapture()
        let store = MockChunkStore()
        let manager = makeManager(recorder: recorder, store: store, alert: MockAlertPresenter(confirmResult: true))
        store.registerChunk(url: URL(fileURLWithPath: "/tmp/test.mp4"), startTime: Date(), duration: 10.0)

        manager.purgeRecordings()
        // The recorder purges the store itself, so chunks it is still finalizing cannot survive.
        try check(recorder.purgeCount == 1, "A confirmed purge should go through the recorder")
    }

    static func testPurgeCancelledKeepsEverything() throws {
        let recorder = MockScreenCapture()
        let store = MockChunkStore()
        let manager = makeManager(recorder: recorder, store: store, alert: MockAlertPresenter(confirmResult: false))
        store.registerChunk(url: URL(fileURLWithPath: "/tmp/test.mp4"), startTime: Date(), duration: 10.0)

        manager.purgeRecordings()
        try check(store.chunks.count == 1 && recorder.purgeCount == 0, "Expected chunks preserved on cancelled purge")
    }

    static func testHUDStartTimeSkipsPauses() throws {
        let recorder = MockScreenCapture()
        let store = MockChunkStore()
        let manager = makeManager(recorder: recorder, store: store)

        // Two 10 s chunks with a 5 minute pause between them, and nothing in progress.
        let first = Date().addingTimeInterval(-400)
        store.registerChunk(url: URL(fileURLWithPath: "/tmp/a.mp4"), startTime: first, duration: 10)
        let second = first.addingTimeInterval(310)
        store.registerChunk(url: URL(fileURLWithPath: "/tmp/b.mp4"), startTime: second, duration: 10)

        let start = manager.footageStartDate(offset: 15, endDate: second.addingTimeInterval(10))
        try check(abs(start.timeIntervalSince(first.addingTimeInterval(5))) < 0.01, "The label should point into the first chunk, not into the pause: \(start)")
    }

    static func testHUDStartTimeWithinChunkInProgress() throws {
        let recorder = MockScreenCapture()
        recorder.unsavedDuration = 30
        let manager = makeManager(recorder: recorder)

        let endDate = Date()
        let start = manager.footageStartDate(offset: 10, endDate: endDate)
        try check(abs(start.timeIntervalSince(endDate.addingTimeInterval(-10))) < 0.01, "Footage in progress is continuous: \(start)")
    }

    static func testQuitGoesThroughTermination() throws {
        let recorder = MockScreenCapture()
        let manager = makeManager(recorder: recorder)
        var terminated = false
        manager.appTerminator = { terminated = true }

        manager.quitApp()
        try check(terminated, "Expected quitApp to terminate")
        // AppDelegate.applicationShouldTerminate stops the stream and waits for the last chunk.
        try check(recorder.stopCount == 0, "quitApp must not stop the stream ahead of the delegate")
    }
}
