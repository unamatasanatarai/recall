import Foundation
import CoreGraphics
import CoreMedia

struct RecorderEngineTests {
    private static func makeEngine(
        store: MockChunkStore = MockChunkStore(),
        source: MockCaptureSource = MockCaptureSource(),
        threshold: TimeInterval = 0.5,
        permission: MockScreenCapturePermissionProvider = MockScreenCapturePermissionProvider(isGranted: true),
        display: MockDisplayInfoProvider = MockDisplayInfoProvider(),
        startTimeout: TimeInterval = 5,
        restartDelay: TimeInterval = 0.3,
        backend: CaptureBackend = .displayStream,
        preferences: UserDefaults = RecorderEngineTests.isolatedPreferences(),
        factory: ((CaptureBackend) -> CaptureSource)? = nil
    ) -> RecorderEngine {
        return RecorderEngine(
            chunkStore: store,
            permissionProvider: permission,
            displayInfo: display,
            fileSystem: FileManager.default,
            segmentDurationThreshold: threshold,
            captureStartTimeout: startTimeout,
            captureRestartDelay: restartDelay,
            preferredBackend: backend,
            preferences: preferences,
            sourceFactory: factory ?? { _ in source }
        )
    }

    private static func isolatedPreferences() -> UserDefaults {
        let suiteName = "RecallTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// Delivers frames for `seconds` at `fps`, pumping the main run loop in between.
    private static func feed(_ source: MockCaptureSource, seconds: TimeInterval, fps: Double = 20, width: Int = 320, height: Int = 240) {
        let frame = TestMedia.pixelBuffer(width: width, height: height)
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            source.deliverFrame(frame)
            pump(1.0 / fps)
        }
    }

    private static func start(_ engine: RecorderEngine) throws {
        engine.startContinuousRecording()
        try check(waitUntil { engine.state == .recording }, "Expected .recording, got \(engine.state)")
    }

    private static func stop(_ engine: RecorderEngine) {
        var stopped = false
        engine.stopStream { stopped = true }
        waitUntil(timeout: 5) { stopped }
    }

    private static func partialFiles(in directory: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".partial") }
    }

    // MARK: - Basics

    static func testInitialIdleState() throws {
        let engine = makeEngine()
        try check(engine.state == .idle, "Expected initial state to be .idle")
        try check(engine.unsavedDuration == 0, "Nothing should be unsaved before recording")
    }

    static func testDefaultBackendPrefersScreenCaptureKit() throws {
        let preferences = isolatedPreferences()
        if #available(macOS 12.5, *) {
            try check(RecorderEngine.defaultBackend(preferences: preferences) == .screenCaptureKit, "Expected ScreenCaptureKit on macOS 12.5+")
        } else {
            try check(RecorderEngine.defaultBackend(preferences: preferences) == .displayStream, "Expected CGDisplayStream before macOS 12.5")
        }
    }

    static func testScreenCaptureKitFailureIsRememberedPerSystemVersion() throws {
        let preferences = isolatedPreferences()
        let failing = MockCaptureSource()
        failing.startError = CaptureError(message: "denied")
        let engine = makeEngine(backend: .screenCaptureKit, preferences: preferences, factory: { $0 == .screenCaptureKit ? failing : MockCaptureSource() })
        try start(engine)
        stop(engine)

        try check(RecorderEngine.defaultBackend(preferences: preferences) == .displayStream, "The next launch should skip ScreenCaptureKit on this system")
        if #available(macOS 12.5, *) {
            let nextWeek = Date().addingTimeInterval(RecorderEngine.screenCaptureKitRetryInterval + 60)
            try check(RecorderEngine.defaultBackend(preferences: preferences, now: nextWeek) == .screenCaptureKit, "ScreenCaptureKit should be retried after a week")
            preferences.set("Version 99.0 (Build 1A1)", forKey: RecorderEngine.screenCaptureKitFailureKey)
            try check(RecorderEngine.defaultBackend(preferences: preferences) == .screenCaptureKit, "A system update should retry ScreenCaptureKit")
        }
    }

    static func testTransientScreenCaptureKitErrorRetriesInsteadOfFallingBack() throws {
        let preferences = isolatedPreferences()
        let created = Locked<[CaptureBackend]>([])
        let engine = makeEngine(restartDelay: 0.2, backend: .screenCaptureKit, preferences: preferences, factory: { backend in
            let source = MockCaptureSource()
            if created.current.isEmpty {
                source.startError = CaptureError(message: "Display 1 is not available.", isTransient: true)
            }
            created.mutate { $0.append(backend) }
            return source
        })

        engine.startContinuousRecording()
        try check(waitUntil { created.current.count == 2 && engine.state == .recording }, "Capture should be retried, got \(created.current) / \(engine.state)")
        try check(created.current == [.screenCaptureKit, .screenCaptureKit], "A transient failure must not switch backends: \(created.current)")
        try check(preferences.string(forKey: RecorderEngine.screenCaptureKitFailureKey) == nil, "A transient failure must not be remembered")
        stop(engine)
    }

    static func testChunkDurationThresholdIsTenSeconds() throws {
        let engine = RecorderEngine(chunkStore: MockChunkStore())
        try check(engine.segmentDurationThreshold == 10.0, "Expected segmentDurationThreshold to be 10.0 seconds, got \(engine.segmentDurationThreshold)")
    }

    static func testPermissionMissingReportsError() throws {
        let source = MockCaptureSource()
        let engine = makeEngine(source: source, permission: MockScreenCapturePermissionProvider(isGranted: false, requestAccessResult: false))

        engine.startContinuousRecording()
        try check(waitUntil { engine.state == .error(RecorderEngine.permissionMessage) }, "Expected the permission error, got \(engine.state)")
        try check(source.startCount == 0, "Capture must not start without permission")
        stop(engine)
    }

    static func testRecordingStartsCaptureAtDisplaySize() throws {
        let source = MockCaptureSource()
        let engine = makeEngine(source: source)
        try start(engine)

        try check(source.lastConfiguration == CaptureConfiguration(displayID: 1, width: 320, height: 240, frameRate: 30), "Unexpected capture configuration \(String(describing: source.lastConfiguration))")
        stop(engine)
    }

    // MARK: - Chunks

    static func testFramesBecomeGaplessRegisteredChunks() throws {
        let store = MockChunkStore()
        let source = MockCaptureSource()
        let engine = makeEngine(store: store, source: source, threshold: 0.5)
        try start(engine)

        feed(source, seconds: 1.4)
        try check(waitUntil { store.chunks.count >= 2 }, "Expected at least 2 chunks, got \(store.chunks.count)")

        let chunks = store.chunks.sorted { $0.startTime < $1.startTime }
        for chunk in chunks {
            try check(chunk.url.pathExtension == "mp4" && FileManager.default.fileExists(atPath: chunk.url.path), "Chunk file missing: \(chunk.url.lastPathComponent)")
            try check(abs(chunk.duration - 0.5) < 0.15, "Expected ~0.5 s chunks, got \(chunk.duration)")
        }
        for (previous, next) in zip(chunks, chunks.dropFirst()) {
            let gap = next.startTime.timeIntervalSince(previous.startTime.addingTimeInterval(previous.duration))
            try check(abs(gap) < 0.05, "Chunks should be contiguous, found a \(gap) s gap")
        }
        stop(engine)
    }

    static func testIdleScreenStillRotatesAndHoldsLastFrame() throws {
        let store = MockChunkStore()
        let source = MockCaptureSource()
        let engine = makeEngine(store: store, source: source, threshold: 0.5)
        try start(engine)

        // One frame, then nothing: a static screen.
        source.deliverFrame(TestMedia.pixelBuffer())
        pump(1.4)

        try check(waitUntil { store.chunks.count >= 2 }, "Chunks should rotate on schedule while the screen is idle, got \(store.chunks.count)")
        for chunk in store.chunks {
            let meta = DefaultVideoMetadataProvider().durationAndIsValid(for: chunk.url)
            try check(meta.isValid && abs(meta.duration - 0.5) < 0.15, "Idle chunk should hold the last frame for its full span, got \(meta)")
        }
        stop(engine)
    }

    static func testFlushRegistersChunkAndKeepsRecording() throws {
        let store = MockChunkStore()
        let source = MockCaptureSource()
        let engine = makeEngine(store: store, source: source, threshold: 30)
        try start(engine)
        feed(source, seconds: 0.4)

        var registeredAtCompletion = -1
        var completedOnMain = false
        let flushRequested = Date()
        engine.flushCurrentChunk {
            completedOnMain = Thread.isMainThread
            registeredAtCompletion = store.chunks.count
        }
        try check(waitUntil { registeredAtCompletion >= 0 }, "Flush never completed")
        try check(completedOnMain, "Flush completion should run on the main thread")
        try check(registeredAtCompletion == 1, "The flushed chunk must be registered before completion runs")
        try check(engine.hasActiveWriter, "Recording should continue into a new chunk")
        try check(engine.unsavedDuration <= Date().timeIntervalSince(flushRequested) + 0.05, "The new chunk should start at the flush, unsaved \(engine.unsavedDuration)")
        stop(engine)
    }

    static func testStopStreamFinalizesCurrentChunkBeforeCompleting() throws {
        let store = MockChunkStore()
        let source = MockCaptureSource()
        let engine = makeEngine(store: store, source: source, threshold: 30)
        try start(engine)
        feed(source, seconds: 0.4)

        var registeredAtCompletion = -1
        engine.stopStream {
            registeredAtCompletion = store.chunks.count
        }
        try check(waitUntil { registeredAtCompletion >= 0 }, "stopStream never completed")
        try check(registeredAtCompletion == 1, "Quitting must not lose the chunk in progress")
        try check(waitUntil { engine.state == .idle }, "Expected .idle after stopping")
        try check(source.stopCount == 1, "Capture source should be stopped")
        try check(partialFiles(in: store.chunksDirectory).isEmpty, "No partial files should remain after stopping")
    }

    static func testStopCompletesWhileTerminationWaitsInsideMainQueueWork() throws {
        let store = MockChunkStore()
        let source = MockCaptureSource()
        let engine = makeEngine(store: store, source: source, threshold: 30)
        try start(engine)
        feed(source, seconds: 0.2)

        // terminate: (here from a SIGTERM dispatch source) waits for the recorder in a nested modal
        // run loop while still inside a main-queue block; main-queue work cannot run there.
        var completed = false
        var completedInsideNestedLoop: Bool?
        DispatchQueue.main.async {
            engine.stopStream { completed = true }
            let deadline = Date().addingTimeInterval(3)
            while !completed && Date() < deadline {
                RunLoop.current.run(mode: .modalPanel, before: Date().addingTimeInterval(0.05))
            }
            completedInsideNestedLoop = completed
        }
        try check(waitUntil(timeout: 5) { completedInsideNestedLoop != nil }, "The nested loop never finished")
        try check(completedInsideNestedLoop == true, "stopStream must complete while termination is waiting, or quitting hangs")
        try check(store.chunks.count == 1, "The last chunk should be saved")
    }

    static func testPurgeDeletesChunkInProgressAndKeepsRecording() throws {
        let store = MockChunkStore()
        let source = MockCaptureSource()
        let engine = makeEngine(store: store, source: source, threshold: 30)
        try start(engine)
        feed(source, seconds: 0.3)
        let before = partialFiles(in: store.chunksDirectory)

        engine.purgeRecordings()
        engine.syncQueue()

        let after = partialFiles(in: store.chunksDirectory)
        try check(before.count == 1 && !after.contains(before[0]), "The chunk in progress should be deleted (before \(before), after \(after))")
        try check(store.purgeCount == 1, "Stored chunks should be purged too")
        try check(engine.hasActiveWriter, "Recording should continue after a purge")
        stop(engine)
        try check(!store.chunks.contains { $0.url.lastPathComponent + ".partial" == before[0] }, "The purged chunk must never be registered")
    }

    static func testPurgeDeletesChunksStillBeingFinalized() throws {
        let directory = TestSandbox.makeDirectory("purge_race")
        let manager = ChunkManager(config: MockStorageConfig(), fileSystem: FileManager.default, chunksDirectory: directory)
        manager.syncQueue()
        let source = MockCaptureSource()
        let engine = RecorderEngine(
            chunkStore: manager,
            permissionProvider: MockScreenCapturePermissionProvider(isGranted: true),
            displayInfo: MockDisplayInfoProvider(),
            segmentDurationThreshold: 30,
            preferredBackend: .displayStream,
            preferences: isolatedPreferences(),
            sourceFactory: { _ in source }
        )
        try start(engine)
        feed(source, seconds: 0.5)

        // The flush hands the chunk to AVFoundation to finalize; the purge arrives while it is still
        // being written out, as when a rotation happens just before "Purge All".
        let purgeMoment = Date()
        engine.flushCurrentChunk()
        engine.purgeRecordings()
        feed(source, seconds: 0.3)
        stop(engine)
        manager.syncQueue()

        let survivors = manager.chunks.filter { $0.startTime < purgeMoment.addingTimeInterval(-0.01) }
        try check(survivors.isEmpty, "Footage recorded before the purge survived: \(survivors.map(\.url.lastPathComponent))")
        let onDisk = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".mp4") }
        try check(Set(onDisk) == Set(manager.chunks.map(\.url.lastPathComponent)), "Unindexed chunk files left behind: \(onDisk)")
        try check(manager.chunks.count == 1, "Footage recorded after the purge should be kept, got \(manager.chunks.count)")
    }

    static func testUnsavedDurationTracksChunkInProgress() throws {
        let source = MockCaptureSource()
        let engine = makeEngine(source: source, threshold: 30)
        try start(engine)
        feed(source, seconds: 0.5)

        try check(engine.unsavedDuration > 0.3, "Expected the chunk in progress to be counted, got \(engine.unsavedDuration)")
        stop(engine)
        try check(engine.unsavedDuration == 0, "Nothing should be unsaved after stopping")
    }

    static func testFrameSizeChangeStartsNewChunk() throws {
        let store = MockChunkStore()
        let source = MockCaptureSource()
        let engine = makeEngine(store: store, source: source, threshold: 30)
        try start(engine)

        feed(source, seconds: 0.3)
        feed(source, seconds: 0.3, width: 640, height: 480)
        try check(waitUntil { store.chunks.count == 1 }, "A resolution change should finish the current chunk")
        stop(engine)
        try check(store.chunks.count == 2, "Expected the second chunk at the new size, got \(store.chunks.count)")
    }

    static func testForeignTimestampsUseArrivalTime() throws {
        let store = MockChunkStore()
        let source = MockCaptureSource()
        let engine = makeEngine(store: store, source: source, threshold: 30)
        try start(engine)

        let frame = TestMedia.pixelBuffer()
        for index in 0..<8 {
            // Timestamps from an unrelated clock must not break chunk timing.
            source.deliverFrame(frame, at: CMTime(seconds: Double(index), preferredTimescale: 600))
            pump(0.05)
        }
        stop(engine)
        try check(store.chunks.count == 1, "Expected one chunk, got \(store.chunks.count)")
    }

    // MARK: - Pausing

    static func testPauseStopsCaptureAndResumeRestarts() throws {
        let store = MockChunkStore()
        let source = MockCaptureSource()
        let engine = makeEngine(store: store, source: source, threshold: 30)
        try start(engine)
        feed(source, seconds: 0.3)

        engine.setPaused(true, reason: .user)
        try check(waitUntil { engine.state == .paused && engine.isPausedByUser }, "Expected .paused, got \(engine.state)")
        try check(source.stopCount == 1 && !source.isRunning, "Capture should stop while paused")
        try check(waitUntil { store.chunks.count == 1 }, "Pausing should keep what was recorded so far")

        engine.setPaused(false, reason: .user)
        try check(waitUntil { engine.state == .recording && !engine.isPausedByUser }, "Expected .recording after resuming")
        try check(source.startCount == 2, "Capture should restart on resume")
        stop(engine)
    }

    static func testPauseReasonsAreIndependent() throws {
        let source = MockCaptureSource()
        let engine = makeEngine(source: source)
        try start(engine)

        engine.setPaused(true, reason: .screenLocked)
        engine.setPaused(true, reason: .displaySleep)
        try check(waitUntil { engine.state == .paused }, "Expected .paused")
        try check(!engine.isPausedByUser, "System pauses are not user pauses")

        engine.setPaused(false, reason: .screenLocked)
        pump(0.2)
        try check(engine.state == .paused, "Still paused while the display sleeps")

        engine.setPaused(false, reason: .displaySleep)
        try check(waitUntil { engine.state == .recording }, "Expected .recording once every reason cleared")
        stop(engine)
    }

    // MARK: - Recovery

    static func testScreenCaptureKitStartFailureFallsBack() throws {
        let failing = MockCaptureSource()
        failing.startError = CaptureError(message: "denied")
        let fallback = MockCaptureSource()
        let engine = makeEngine(backend: .screenCaptureKit, factory: { $0 == .screenCaptureKit ? failing : fallback })

        try start(engine)
        try check(engine.activeBackend == .displayStream, "Expected the CGDisplayStream fallback")
        try check(fallback.startCount == 1, "Fallback source should be started")
        stop(engine)
    }

    static func testWatchdogFallsBackWhenNoFramesArrive() throws {
        let silent = MockCaptureSource()
        let fallback = MockCaptureSource()
        let engine = makeEngine(startTimeout: 0.3, backend: .screenCaptureKit, factory: { $0 == .screenCaptureKit ? silent : fallback })
        try start(engine)

        try check(waitUntil { engine.activeBackend == .displayStream }, "Expected a fallback after a silent start")
        try check(silent.stopCount == 1 && fallback.startCount == 1, "Silent source should be replaced")
        stop(engine)
    }

    static func testWatchdogKeepsWorkingScreenCaptureKit() throws {
        let source = MockCaptureSource()
        let engine = makeEngine(source: source, startTimeout: 0.3, backend: .screenCaptureKit)
        try start(engine)

        source.deliverIdle()
        pump(0.6)
        try check(engine.activeBackend == .screenCaptureKit, "A source that delivers events must be kept")
        stop(engine)
    }

    static func testUnexpectedStopReportsErrorThenRestarts() throws {
        let source = MockCaptureSource()
        let engine = makeEngine(source: source, restartDelay: 0.3)
        try start(engine)

        source.failStream()
        try check(waitUntil {
            if case .error = engine.state { return true }
            return false
        }, "Expected an error state after the stream stopped, got \(engine.state)")
        try check(waitUntil { source.startCount == 2 && engine.state == .recording }, "Capture should restart automatically")
        stop(engine)
    }

    static func testRecreatesDeletedChunkDirectory() throws {
        let store = MockChunkStore()
        let source = MockCaptureSource()
        let engine = makeEngine(store: store, source: source, threshold: 0.4)
        try start(engine)
        feed(source, seconds: 0.2)

        // A cache cleaner removes the directory while recording.
        try FileManager.default.removeItem(at: store.chunksDirectory)
        feed(source, seconds: 1.2)

        try check(FileManager.default.fileExists(atPath: store.chunksDirectory.path), "The chunk directory should be recreated")
        try check(waitUntil { store.chunks.contains { FileManager.default.fileExists(atPath: $0.url.path) } }, "Recording should continue into the recreated directory")
        stop(engine)
    }

    static func testDisplayChangeRestartsCapture() throws {
        let source = MockCaptureSource()
        let display = MockDisplayInfoProvider()
        let engine = makeEngine(source: source, display: display)
        try start(engine)

        display.display = (2, 640, 480)
        engine.handleDisplayConfigurationChange()
        try check(waitUntil { source.startCount == 2 }, "A display change should restart capture")
        try check(source.lastConfiguration?.displayID == 2 && source.lastConfiguration?.width == 640, "Capture should follow the new display")
        stop(engine)
    }

    static func testUnchangedDisplayKeepsCapture() throws {
        let source = MockCaptureSource()
        let engine = makeEngine(source: source)
        try start(engine)

        engine.handleDisplayConfigurationChange()
        pump(1.3)
        try check(source.startCount == 1, "Capture should not restart when nothing changed")
        stop(engine)
    }

    static func testRecordingOptionsChangeRestartsCapture() throws {
        let source = MockCaptureSource()
        let engine = makeEngine(source: source)
        try start(engine)

        engine.applyRecordingOptions(RecordingOptions(recordAtNativeResolution: true, preferHEVC: false))
        try check(waitUntil { source.startCount == 2 }, "New options should restart capture")
        try check(source.lastConfiguration?.width == 640, "Native resolution should double the mock display size")
        stop(engine)
    }
}
