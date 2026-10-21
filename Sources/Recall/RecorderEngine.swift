import Foundation
import AVFoundation
import Combine
import CoreGraphics
import CoreMedia
import CoreVideo

extension RunLoop {
    /// Runs `block` on the main thread in any common run loop mode, including the modal loop
    /// `terminate:` spins while waiting for a reply, even when that loop runs inside a main-queue block.
    static func performOnMainInCommonModes(_ block: @escaping () -> Void) {
        let mainLoop = CFRunLoopGetMain()
        CFRunLoopPerformBlock(mainLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(mainLoop)
    }
}

/// Host-clock helpers. Capture timestamps are host time, so all chunk timing uses this clock.
enum HostClock {
    static func now() -> CMTime {
        return CMClockGetTime(CMClockGetHostTimeClock())
    }

    /// Wall-clock date of a host-clock timestamp.
    static func date(for time: CMTime, now: CMTime = HostClock.now()) -> Date {
        return Date(timeIntervalSinceNow: CMTimeGetSeconds(CMTimeSubtract(time, now)))
    }
}

// MARK: - Display Info

protocol DisplayInfoProvider {
    /// The display to record and the output size in pixels.
    func mainDisplay(nativeResolution: Bool) -> (id: CGDirectDisplayID, width: Int, height: Int)
}

struct DefaultDisplayInfoProvider: DisplayInfoProvider {
    func mainDisplay(nativeResolution: Bool) -> (id: CGDirectDisplayID, width: Int, height: Int) {
        let mainID = CGMainDisplayID()
        // Point size by default; on Retina displays the native pixel size is twice as large.
        var width = CGDisplayPixelsWide(mainID)
        var height = CGDisplayPixelsHigh(mainID)
        if nativeResolution, let mode = CGDisplayCopyDisplayMode(mainID) {
            width = mode.pixelWidth
            height = mode.pixelHeight
        }
        // Video encoders need even dimensions.
        return (mainID, width & ~1, height & ~1)
    }
}

// MARK: - Recorder Engine

final class RecorderEngine: NSObject, ScreenCapture, ObservableObject, @unchecked Sendable {
    static let shared = RecorderEngine()
    static let permissionMessage = "Grant screen recording permission in System Settings."

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var isPausedByUser = false

    var statePublisher: AnyPublisher<RecordingState, Never> {
        return $state.eraseToAnyPublisher()
    }

    let segmentDurationThreshold: TimeInterval
    private let captureStartTimeout: TimeInterval
    private let captureRestartDelay: TimeInterval

    private let chunkStore: ChunkStore
    private let permissionProvider: ScreenCapturePermissionProvider
    private let displayInfo: DisplayInfoProvider
    private let fileSystem: FileSystemProvider
    private let sourceFactory: (CaptureBackend) -> CaptureSource
    private let preferences: UserDefaults
    private let config = ConfigManager.shared

    // Every capture callback and every writer operation runs on this queue.
    private let recordingQueue = DispatchQueue(label: "com.recall.recorder.encoding", qos: .userInteractive)

    // MARK: Confined to recordingQueue
    private var options = RecordingOptions()
    private var wantsRecording = false
    private var pauseReasons: Set<PauseReason> = []
    private var preferredBackend: CaptureBackend
    private var source: CaptureSource?
    private var sourceGeneration = 0
    private var captureConfiguration: CaptureConfiguration?
    private var writer: ChunkWriter?
    private var lastFrame: (buffer: CVPixelBuffer, time: CMTime)?
    private var hasReceivedEvent = false
    private var consecutiveFailures = 0
    private var lastError: String?
    private var lastWriterAttempt: TimeInterval = -.infinity
    private var hasLoggedClockMismatch = false
    private var rotationTimer: DispatchSourceTimer?
    private var watchdog: DispatchWorkItem?
    private var restartWork: DispatchWorkItem?
    private var displayChangeWork: DispatchWorkItem?
    private let pendingFinishes = DispatchGroup()

    // Read from any thread.
    private let unsavedLock = NSLock()
    private var unsavedChunkStart: CMTime?

    // A purge bumps the generation. A chunk finalized afterwards under an older generation is
    // deleted instead of registered, so footage being finalized during a purge cannot survive it.
    private let purgeLock = NSLock()
    private var purgeGeneration = 0   // guarded by purgeLock

    // MARK: Main thread
    private var permissionTimer: Timer?

    init(
        chunkStore: ChunkStore = ChunkManager.shared,
        permissionProvider: ScreenCapturePermissionProvider = DefaultScreenCapturePermissionProvider(),
        displayInfo: DisplayInfoProvider = DefaultDisplayInfoProvider(),
        fileSystem: FileSystemProvider = FileManager.default,
        segmentDurationThreshold: TimeInterval = ConfigManager.shared.maxChunkDuration,
        captureStartTimeout: TimeInterval = ConfigManager.shared.captureStartTimeout,
        captureRestartDelay: TimeInterval = ConfigManager.shared.captureRestartDelay,
        preferredBackend: CaptureBackend? = nil,
        preferences: UserDefaults = .standard,
        sourceFactory: @escaping (CaptureBackend) -> CaptureSource = RecorderEngine.makeSource
    ) {
        self.chunkStore = chunkStore
        self.permissionProvider = permissionProvider
        self.displayInfo = displayInfo
        self.fileSystem = fileSystem
        self.segmentDurationThreshold = segmentDurationThreshold
        self.captureStartTimeout = captureStartTimeout
        self.captureRestartDelay = captureRestartDelay
        self.preferences = preferences
        self.preferredBackend = preferredBackend ?? RecorderEngine.defaultBackend(preferences: preferences)
        self.sourceFactory = sourceFactory
        super.init()
    }

    /// The macOS version on which ScreenCaptureKit last failed, and when. It is skipped on that
    /// version for a week, so every launch does not lose the watchdog's wait; a system update or
    /// the week passing tries it again.
    static let screenCaptureKitFailureKey = "screenCaptureKitFailedOnSystemVersion"
    static let screenCaptureKitFailureDateKey = "screenCaptureKitFailureDate"
    static let screenCaptureKitRetryInterval: TimeInterval = 7 * 24 * 3600

    /// ScreenCaptureKit had capture bugs before macOS 12.5.
    static func defaultBackend(preferences: UserDefaults = .standard, now: Date = Date()) -> CaptureBackend {
        guard #available(macOS 12.5, *) else { return .displayStream }
        if preferences.string(forKey: screenCaptureKitFailureKey) == ProcessInfo.processInfo.operatingSystemVersionString,
           let failedAt = preferences.object(forKey: screenCaptureKitFailureDateKey) as? Date,
           now.timeIntervalSince(failedAt) < screenCaptureKitRetryInterval {
            return .displayStream
        }
        return .screenCaptureKit
    }

    static func makeSource(_ backend: CaptureBackend) -> CaptureSource {
        switch backend {
        case .screenCaptureKit:
            return ScreenCaptureKitSource()
        case .displayStream:
            return DisplayStreamSource()
        }
    }

    var unsavedDuration: TimeInterval {
        guard let start = unsavedLock.withCriticalSection({ unsavedChunkStart }) else { return 0 }
        return max(0, CMTimeGetSeconds(CMTimeSubtract(HostClock.now(), start)))
    }

    // MARK: - Lifecycle

    func startContinuousRecording() {
        Log.recorder.notice("startContinuousRecording requested")

        guard permissionProvider.preflightAccess() else {
            Log.recorder.notice("Screen capture permission missing; requesting access")
            _ = permissionProvider.requestAccess()
            recordingQueue.async {
                self.lastError = RecorderEngine.permissionMessage
                self.publishState()
            }

            permissionTimer?.invalidate()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.handlePermissionTimerCheck()
            }
            return
        }

        permissionTimer?.invalidate()
        permissionTimer = nil
        recordingQueue.async {
            self.lastError = nil
            self.wantsRecording = true
            self.updateCapture()
        }
    }

    func handlePermissionTimerCheck() {
        guard permissionProvider.preflightAccess() else { return }
        Log.recorder.notice("Screen capture permission granted")
        startContinuousRecording()
    }

    func stopStream(completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            self.permissionTimer?.invalidate()
            self.permissionTimer = nil
        }
        recordingQueue.async {
            self.wantsRecording = false
            self.lastError = nil
            self.restartWork?.cancel()
            self.restartWork = nil
            self.stopCapture()
            self.publishState()
            // Also waits for rotations still being finalized, so quitting never cuts a chunk short.
            // Delivered through the run loop, not the main queue: termination waits for this inside a
            // nested run loop that may itself be running in a main-queue block (a SIGTERM handler, an
            // alert), where nothing else queued on main can run.
            self.pendingFinishes.notify(queue: .global(qos: .userInitiated)) {
                RunLoop.performOnMainInCommonModes {
                    completion?()
                }
            }
        }
    }

    func setPaused(_ paused: Bool, reason: PauseReason) {
        if reason == .user {
            DispatchQueue.main.async { self.isPausedByUser = paused }
        }
        recordingQueue.async {
            let changed = paused ? self.pauseReasons.insert(reason).inserted : self.pauseReasons.remove(reason) != nil
            guard changed else { return }
            Log.recorder.notice("\(paused ? "Paused" : "Resumed", privacy: .public) recording (\(reason.rawValue, privacy: .public))")
            self.updateCapture()
        }
    }

    func applyRecordingOptions(_ options: RecordingOptions) {
        recordingQueue.async {
            guard options != self.options else { return }
            self.options = options
            if self.source != nil {
                Log.recorder.notice("Recording options changed; restarting capture")
                self.restartCapture()
            }
        }
    }

    func handleDisplayConfigurationChange() {
        recordingQueue.async {
            // Reconfiguration arrives as a burst of notifications; act once it settles.
            self.displayChangeWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.source != nil, let current = self.captureConfiguration else { return }
                let display = self.displayInfo.mainDisplay(nativeResolution: self.options.recordAtNativeResolution)
                guard display.id != current.displayID || display.width != current.width || display.height != current.height else { return }
                Log.recorder.notice("Main display changed to \(display.width)x\(display.height); restarting capture")
                self.restartCapture()
            }
            self.displayChangeWork = work
            self.recordingQueue.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }

    // MARK: - Chunks

    /// Finalizes the chunk in progress (registering it with the chunk store) and continues
    /// recording into a new one without a gap.
    func flushCurrentChunk(completion: (() -> Void)? = nil) {
        let completeOnMain = {
            DispatchQueue.main.async { completion?() }
        }
        recordingQueue.async {
            guard let current = self.writer else {
                completeOnMain()
                return
            }
            let now = HostClock.now()
            Log.recorder.info("Flushing \(current.finalURL.lastPathComponent, privacy: .public) (\(current.framesWritten) frames)")
            self.writer = nil
            if let seed = self.lastFrame?.buffer {
                self.openWriter(at: now, seed: seed)
            }
            self.finish(current, at: now, completion: completeOnMain)
        }
    }

    /// Deletes every recording: stored chunks, the chunk being written, and chunks still being
    /// finalized. Recording continues into a fresh chunk.
    func purgeRecordings() {
        recordingQueue.async {
            self.purgeLock.withCriticalSection {
                self.purgeGeneration += 1
                // Queued while holding the lock, so it lands after any registration that passed
                // the generation check and before any that did not.
                self.chunkStore.purgeAllChunks()
            }
            if let current = self.writer {
                self.writer = nil
                current.cancel()
                self.setUnsavedChunkStart(nil)
            }
            if self.source != nil, let seed = self.lastFrame?.buffer {
                self.openWriter(at: HostClock.now(), seed: seed)
            }
        }
    }

    // MARK: - Capture Control (recordingQueue)

    private func updateCapture() {
        let shouldCapture = wantsRecording && pauseReasons.isEmpty
        if shouldCapture && source == nil {
            startCapture()
        } else if !shouldCapture && source != nil {
            stopCapture()
        }
        publishState()
    }

    private func startCapture() {
        let display = displayInfo.mainDisplay(nativeResolution: options.recordAtNativeResolution)
        let configuration = CaptureConfiguration(displayID: display.id, width: display.width, height: display.height, frameRate: config.targetFrameRate)
        let backend = preferredBackend
        let source = sourceFactory(backend)

        sourceGeneration += 1
        let generation = sourceGeneration
        self.source = source
        captureConfiguration = configuration
        hasReceivedEvent = false
        startRotationTimer()

        Log.recorder.notice("Starting \(backend.rawValue, privacy: .public) capture of display \(display.id) at \(display.width)x\(display.height)")
        source.start(
            configuration: configuration,
            queue: recordingQueue,
            eventHandler: { [weak self] event in
                self?.handle(event, generation: generation)
            },
            stopHandler: { [weak self] error in
                self?.recordingQueue.async {
                    self?.handleSourceStopped(error, generation: generation)
                }
            },
            completion: { [weak self] error in
                self?.handleSourceStarted(error: error, backend: backend, generation: generation)
            }
        )
    }

    private func stopCapture() {
        sourceGeneration += 1
        rotationTimer?.cancel()
        rotationTimer = nil
        watchdog?.cancel()
        watchdog = nil
        displayChangeWork?.cancel()
        displayChangeWork = nil

        if let source = source {
            source.stop {}
            self.source = nil
        }
        captureConfiguration = nil

        if let current = writer {
            writer = nil
            finish(current, at: HostClock.now(), completion: nil)
        }
        lastFrame = nil
    }

    private func restartCapture() {
        stopCapture()
        updateCapture()
    }

    private func handleSourceStarted(error: Error?, backend: CaptureBackend, generation: Int) {
        guard generation == sourceGeneration else { return }

        if let error = error {
            Log.recorder.error("\(backend.rawValue, privacy: .public) capture failed to start: \(error.localizedDescription, privacy: .public)")
            stopCapture()
            // A display that just went away or content that is not ready yet says nothing about
            // whether ScreenCaptureKit works; retry those instead of falling back.
            let isTransient = (error as? CaptureError)?.isTransient == true
            if backend == .screenCaptureKit && !isTransient {
                fallBackToDisplayStream()
                return
            }
            lastError = "Screen capture could not start: \(error.localizedDescription)"
            publishState()
            scheduleRestart()
            return
        }

        Log.recorder.notice("\(backend.rawValue, privacy: .public) capture active")
        lastError = nil
        publishState()

        guard backend == .screenCaptureKit else { return }
        // ScreenCaptureKit can start "successfully" and still deliver nothing (seen on macOS 12
        // when the system denies capture silently). Fall back if it stays silent.
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, generation == self.sourceGeneration, !self.hasReceivedEvent else { return }
            Log.recorder.error("ScreenCaptureKit delivered no frames")
            self.stopCapture()
            self.fallBackToDisplayStream()
        }
        watchdog = work
        recordingQueue.asyncAfter(deadline: .now() + captureStartTimeout, execute: work)
    }

    private func handleSourceStopped(_ error: Error, generation: Int) {
        guard generation == sourceGeneration else { return }
        Log.recorder.error("Capture stopped unexpectedly: \(error.localizedDescription, privacy: .public)")
        stopCapture()

        consecutiveFailures += 1
        if preferredBackend == .screenCaptureKit && consecutiveFailures >= 3 {
            fallBackToDisplayStream()
            return
        }
        lastError = "Screen capture stopped: \(error.localizedDescription)"
        publishState()
        scheduleRestart()
    }

    private func fallBackToDisplayStream() {
        Log.recorder.notice("Falling back to CGDisplayStream capture")
        preferences.set(ProcessInfo.processInfo.operatingSystemVersionString, forKey: RecorderEngine.screenCaptureKitFailureKey)
        preferences.set(Date(), forKey: RecorderEngine.screenCaptureKitFailureDateKey)
        preferredBackend = .displayStream
        consecutiveFailures = 0
        updateCapture()
    }

    private func scheduleRestart() {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.restartWork = nil
            self.updateCapture()
        }
        restartWork = work
        recordingQueue.asyncAfter(deadline: .now() + captureRestartDelay, execute: work)
    }

    private func startRotationTimer() {
        rotationTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: recordingQueue)
        // Idle chunks end at most one interval late.
        let interval = min(config.rotationCheckInterval, segmentDurationThreshold / 10)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(interval * 200)))
        timer.setEventHandler { [weak self] in
            self?.rotationTick()
        }
        timer.resume()
        rotationTimer = timer
    }

    // MARK: - Frames (recordingQueue)

    private func handle(_ event: CaptureEvent, generation: Int) {
        guard generation == sourceGeneration else { return }
        hasReceivedEvent = true

        guard case let .frame(buffer, rawTime) = event else { return }
        consecutiveFailures = 0
        let time = hostTime(for: rawTime)
        lastFrame = (buffer, time)

        guard let current = writer else {
            openWriter(at: time, seed: buffer)
            return
        }
        if current.elapsed(at: time) >= segmentDurationThreshold || !current.accepts(buffer) {
            rotate(at: time, seed: buffer)
            return
        }
        current.append(buffer, at: time)
        if current.hasFailed {
            handleWriterFailure(current)
        }
    }

    /// Rotates on schedule even while the screen is idle and no frames arrive, and retries
    /// opening a writer after a failure.
    private func rotationTick() {
        guard source != nil, let seed = lastFrame?.buffer else { return }
        let now = HostClock.now()
        if let current = writer {
            if current.elapsed(at: now) >= segmentDurationThreshold {
                rotate(at: now, seed: seed)
            }
        } else {
            openWriter(at: now, seed: seed)
        }
    }

    /// Starts the next chunk before finishing the current one, so no frame falls between them.
    private func rotate(at time: CMTime, seed: CVPixelBuffer) {
        let previous = writer
        writer = nil
        openWriter(at: time, seed: seed)
        if let previous = previous {
            finish(previous, at: time, completion: nil)
        }
    }

    private func openWriter(at time: CMTime, seed: CVPixelBuffer) {
        guard captureConfiguration != nil else { return }
        let attemptTime = CMTimeGetSeconds(time)
        if lastError != nil && attemptTime - lastWriterAttempt < config.writerRetryInterval {
            return
        }
        lastWriterAttempt = attemptTime

        let directory = chunkStore.chunksDirectory
        if !fileSystem.fileExists(atPath: directory.path) {
            // Recreate the directory if something (a cache cleaner, the user) removed it.
            StorageDirectory.prepare(directory, fileSystem: fileSystem)
        }

        let settings = EncoderSettings.make(
            width: CVPixelBufferGetWidth(seed),
            height: CVPixelBufferGetHeight(seed),
            preferHEVC: options.preferHEVC
        )
        do {
            let newWriter = try ChunkWriter(directory: directory, startTime: time, startDate: HostClock.date(for: time), settings: settings, fileSystem: fileSystem)
            newWriter.append(seed, at: time)
            writer = newWriter
            setUnsavedChunkStart(time)
            if lastError != nil {
                lastError = nil
                publishState()
            }
        } catch {
            Log.recorder.error("Could not start a chunk: \(error.localizedDescription, privacy: .public)")
            setUnsavedChunkStart(nil)
            lastError = "Recording failed: \(error.localizedDescription)"
            publishState()
        }
    }

    private func finish(_ chunkWriter: ChunkWriter, at time: CMTime, completion: (() -> Void)?) {
        if writer == nil {
            setUnsavedChunkStart(nil)
        }
        pendingFinishes.enter()
        let chunkStore = self.chunkStore
        let pendingFinishes = self.pendingFinishes
        let fileSystem = self.fileSystem
        let generation = purgeLock.withCriticalSection { purgeGeneration }
        chunkWriter.finish(at: time) { [self] result in
            switch result {
            case .success(let chunk?):
                // Checked and registered under the purge lock, so a purge cannot slip in between.
                let isCurrent = self.purgeLock.withCriticalSection { () -> Bool in
                    guard generation == self.purgeGeneration else { return false }
                    chunkStore.registerChunk(url: chunk.url, startTime: chunk.startDate, duration: chunk.duration)
                    return true
                }
                if !isCurrent {
                    try? fileSystem.removeItem(at: chunk.url)
                }
            case .success(nil):
                break
            case .failure(let error):
                Log.recorder.error("Could not finish \(chunkWriter.finalURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            completion?()
            pendingFinishes.leave()
        }
    }

    private func handleWriterFailure(_ failed: ChunkWriter) {
        Log.recorder.error("Chunk writer failed: \(failed.failureDescription, privacy: .public)")
        failed.cancel()
        writer = nil
        setUnsavedChunkStart(nil)
        lastError = "Recording failed: \(failed.failureDescription)"
        publishState()
        // rotationTick retries after writerRetryInterval.
    }

    /// ScreenCaptureKit and CGDisplayStream both stamp frames in host time; guard against a
    /// source that does not, since chunk timing assumes it.
    private func hostTime(for time: CMTime) -> CMTime {
        let now = HostClock.now()
        guard time.isValid, abs(CMTimeGetSeconds(CMTimeSubtract(now, time))) < 1.0 else {
            if !hasLoggedClockMismatch {
                hasLoggedClockMismatch = true
                Log.recorder.notice("Frame timestamps are not in host time; using arrival time")
            }
            return now
        }
        return time
    }

    private func setUnsavedChunkStart(_ time: CMTime?) {
        unsavedLock.withCriticalSection { unsavedChunkStart = time }
    }

    private func publishState() {
        let newState: RecordingState
        if wantsRecording && !pauseReasons.isEmpty {
            newState = .paused
        } else if let error = lastError {
            newState = .error(error)
        } else if !wantsRecording {
            newState = .idle
        } else {
            newState = .recording
        }
        DispatchQueue.main.async {
            if self.state != newState {
                self.state = newState
            }
        }
    }

    // MARK: - Testing Support

    var activeBackend: CaptureBackend {
        return recordingQueue.sync { preferredBackend }
    }

    var hasActiveWriter: Bool {
        return recordingQueue.sync { writer != nil }
    }

    func syncQueue() {
        recordingQueue.sync {}
    }
}
