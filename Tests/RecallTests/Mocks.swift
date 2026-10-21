import Foundation
import AppKit
import Combine
import CoreMedia
import CoreVideo

struct MockStorageConfig: StorageConfig {
    var maxBufferSizeBytes: Int64 = 100 * 1024 * 1024 // 100 MB
    var maxStorageDurationSeconds: TimeInterval = 3600 // 1 hour
    var exportsDirectoryURL: URL = URL(fileURLWithPath: "/tmp/mock_exports")
}

final class MockFileSystem: FileSystemProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var storedFiles: [URL: [FileAttributeKey: Any]] = [:]
    private var storedData: [URL: Data] = [:]
    private var storedRemovedURLs: [URL] = []
    private var storedCreatedDirectories: [URL] = []
    private var storedMovedItems: [(src: URL, dst: URL)] = []
    private var storedPermissionChanges: [String: Int] = [:]
    private var storedBackupExclusions: [URL] = []
    /// Directories whose listing fails, as an unreadable or vanished directory would.
    var failingDirectories: Set<String> = []

    var files: [URL: [FileAttributeKey: Any]] {
        get { lock.withCriticalSection { storedFiles } }
        set { lock.withCriticalSection { storedFiles = newValue } }
    }
    var removedURLs: [URL] { lock.withCriticalSection { storedRemovedURLs } }
    var createdDirectories: [URL] { lock.withCriticalSection { storedCreatedDirectories } }
    var movedItems: [(src: URL, dst: URL)] { lock.withCriticalSection { storedMovedItems } }
    var permissionChanges: [String: Int] { lock.withCriticalSection { storedPermissionChanges } }
    var backupExclusions: [URL] { lock.withCriticalSection { storedBackupExclusions } }

    func setFile(_ url: URL, attributes: [FileAttributeKey: Any]) {
        lock.withCriticalSection { storedFiles[url] = attributes }
    }

    func storedData(at url: URL) -> Data? {
        return lock.withCriticalSection { storedData[url] }
    }

    func fileExists(atPath path: String) -> Bool {
        return lock.withCriticalSection {
            storedFiles.keys.contains { $0.path == path || $0.path.hasPrefix(path + "/") }
                || storedData.keys.contains { $0.path == path }
                || storedCreatedDirectories.contains { $0.path == path }
        }
    }

    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL] {
        if failingDirectories.contains(url.path) {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        }
        return lock.withCriticalSection {
            storedFiles.keys.filter { $0.deletingLastPathComponent().path == url.path }
        }
    }

    func removeItem(at url: URL) throws {
        lock.withCriticalSection {
            storedRemovedURLs.append(url)
            storedFiles.removeValue(forKey: url)
            storedData.removeValue(forKey: url)
        }
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        let url = URL(fileURLWithPath: path)
        if let attrs = lock.withCriticalSection({ storedFiles[url] }) {
            return attrs
        }
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
    }

    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        lock.withCriticalSection {
            if let permissions = attributes[.posixPermissions] as? Int {
                storedPermissionChanges[path] = permissions
            }
        }
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws {
        lock.withCriticalSection { storedCreatedDirectories.append(url) }
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try lock.withCriticalSection {
            guard let attrs = storedFiles[srcURL] else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
            }
            storedMovedItems.append((src: srcURL, dst: dstURL))
            storedFiles.removeValue(forKey: srcURL)
            storedFiles[dstURL] = attrs
        }
    }

    func readData(at url: URL) -> Data? {
        return lock.withCriticalSection { storedData[url] }
    }

    func writeData(_ data: Data, to url: URL) throws {
        lock.withCriticalSection { storedData[url] = data }
    }

    func excludeFromBackup(_ url: URL) {
        lock.withCriticalSection { storedBackupExclusions.append(url) }
    }
}

struct MockVideoMetadataProvider: VideoMetadataProvider {
    var defaultDuration: TimeInterval = 30.0
    var isValid: Bool = true

    func durationAndIsValid(for url: URL) -> (duration: TimeInterval, isValid: Bool) {
        return (defaultDuration, isValid)
    }
}

/// Counts validations, optionally slowly, to observe launch indexing and queue blocking.
final class CountingMetadataProvider: VideoMetadataProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0
    var duration: TimeInterval = 10.0
    var delay: TimeInterval = 0

    var count: Int { lock.withCriticalSection { storedCount } }

    func durationAndIsValid(for url: URL) -> (duration: TimeInterval, isValid: Bool) {
        lock.withCriticalSection { storedCount += 1 }
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        return (duration, true)
    }
}

final class MockChunkStore: ChunkStore, @unchecked Sendable {
    private let lock = NSLock()
    let chunksDirectory: URL
    private var storedChunks: [ChunkFile] = []
    private var storedExportRequests: [ExportRequest] = []
    private var storedPurgeCount = 0
    private var storedEnforceCount = 0
    private let usageSubject = CurrentValueSubject<ChunkUsage, Never>(ChunkUsage())

    var usageOverride: ChunkUsage?
    var exportResult: Result<URL, ExportError> = .success(URL(fileURLWithPath: "/tmp/mock_export.mp4"))
    /// When false, export completions are held until `completePendingExport()`.
    var completesExportsImmediately = true
    private var pendingExportCompletion: ((Result<URL, ExportError>) -> Void)?

    init(chunksDirectory: URL = TestSandbox.makeDirectory("mock_chunks")) {
        self.chunksDirectory = chunksDirectory
    }

    var chunks: [ChunkFile] { lock.withCriticalSection { storedChunks } }
    var exportRequests: [ExportRequest] { lock.withCriticalSection { storedExportRequests } }
    var purgeCount: Int { lock.withCriticalSection { storedPurgeCount } }
    var enforceCount: Int { lock.withCriticalSection { storedEnforceCount } }

    var usage: ChunkUsage {
        if let override = usageOverride {
            return override
        }
        return ChunkUsage(chunks: chunks)
    }

    var usagePublisher: AnyPublisher<ChunkUsage, Never> {
        return usageSubject.eraseToAnyPublisher()
    }

    func whenLoaded(_ completion: @escaping () -> Void) {
        completion()
    }

    func registerChunk(url: URL, startTime: Date, duration: TimeInterval) {
        lock.withCriticalSection {
            storedChunks.append(ChunkFile(url: url, startTime: startTime, duration: duration, sizeBytes: 1000))
        }
        usageSubject.send(usage)
    }

    func enforceLimits() {
        lock.withCriticalSection { storedEnforceCount += 1 }
    }

    func purgeAllChunks() {
        lock.withCriticalSection {
            storedChunks.removeAll()
            storedPurgeCount += 1
        }
        usageSubject.send(usage)
    }

    func footageStartDate(footageSeconds: TimeInterval, endingAt endDate: Date) -> Date? {
        return ExportPlanner.footageStart(chunks: chunks.sorted { $0.startTime < $1.startTime }, footageSeconds: footageSeconds, endingAt: endDate)
    }

    func exportClip(_ request: ExportRequest, completion: @escaping (Result<URL, ExportError>) -> Void) {
        lock.withCriticalSection { storedExportRequests.append(request) }
        if completesExportsImmediately {
            completion(exportResult)
        } else {
            pendingExportCompletion = completion
        }
    }

    func completePendingExport() {
        pendingExportCompletion?(exportResult)
        pendingExportCompletion = nil
    }
}

class MockScreenCapture: ScreenCapture, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private(set) var isPausedByUser = false
    var unsavedDuration: TimeInterval = 0
    private(set) var startCount = 0
    private(set) var flushCount = 0
    private(set) var purgeCount = 0
    private(set) var stopCount = 0
    private(set) var displayChangeCount = 0
    private(set) var pauseCalls: [(paused: Bool, reason: PauseReason)] = []
    private(set) var appliedOptions: [RecordingOptions] = []

    var state: RecordingState {
        return stateSubject.value
    }

    var statePublisher: AnyPublisher<RecordingState, Never> {
        return stateSubject.eraseToAnyPublisher()
    }

    func setState(_ state: RecordingState) {
        stateSubject.send(state)
    }

    func startContinuousRecording() {
        startCount += 1
        stateSubject.send(.recording)
    }

    func applyRecordingOptions(_ options: RecordingOptions) {
        appliedOptions.append(options)
    }

    func setPaused(_ paused: Bool, reason: PauseReason) {
        pauseCalls.append((paused, reason))
        if reason == .user {
            isPausedByUser = paused
        }
    }

    func handleDisplayConfigurationChange() {
        displayChangeCount += 1
    }

    func flushCurrentChunk(completion: (() -> Void)?) {
        flushCount += 1
        completion?()
    }

    func purgeRecordings() {
        purgeCount += 1
    }

    func stopStream(completion: (() -> Void)?) {
        stopCount += 1
        stateSubject.send(.idle)
        completion?()
    }
}

/// A capture source driven by the test: frames are delivered on demand.
final class MockCaptureSource: CaptureSource, @unchecked Sendable {
    private let lock = NSLock()
    private var storedStartCount = 0
    private var storedStopCount = 0
    private var storedConfiguration: CaptureConfiguration?
    private var queue: DispatchQueue?
    private var eventHandler: ((CaptureEvent) -> Void)?
    private var stopHandler: ((Error) -> Void)?
    var startError: Error?

    var startCount: Int { lock.withCriticalSection { storedStartCount } }
    var stopCount: Int { lock.withCriticalSection { storedStopCount } }
    var lastConfiguration: CaptureConfiguration? { lock.withCriticalSection { storedConfiguration } }
    var isRunning: Bool { lock.withCriticalSection { eventHandler != nil } }

    func start(configuration: CaptureConfiguration, queue: DispatchQueue, eventHandler: @escaping (CaptureEvent) -> Void, stopHandler: @escaping (Error) -> Void, completion: @escaping (Error?) -> Void) {
        let error = startError
        lock.withCriticalSection {
            storedStartCount += 1
            storedConfiguration = configuration
            if error == nil {
                self.queue = queue
                self.eventHandler = eventHandler
                self.stopHandler = stopHandler
            }
        }
        completion(error)
    }

    func stop(completion: @escaping () -> Void) {
        lock.withCriticalSection {
            storedStopCount += 1
            eventHandler = nil
            stopHandler = nil
        }
        completion()
    }

    /// Delivers a frame stamped in host time, as real sources do.
    func deliverFrame(_ buffer: CVPixelBuffer, at time: CMTime = HostClock.now()) {
        let (queue, handler) = lock.withCriticalSection { (self.queue, self.eventHandler) }
        queue?.async { handler?(.frame(buffer, time)) }
    }

    func deliverIdle() {
        let (queue, handler) = lock.withCriticalSection { (self.queue, self.eventHandler) }
        queue?.async { handler?(.idle) }
    }

    func failStream(_ error: Error = CaptureError(message: "mock stream failure")) {
        let handler = lock.withCriticalSection { stopHandler }
        handler?(error)
    }
}

final class MockDisplayInfoProvider: DisplayInfoProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var storedDisplay: (id: CGDirectDisplayID, width: Int, height: Int) = (1, 320, 240)

    var display: (id: CGDirectDisplayID, width: Int, height: Int) {
        get { lock.withCriticalSection { storedDisplay } }
        set { lock.withCriticalSection { storedDisplay = newValue } }
    }

    func mainDisplay(nativeResolution: Bool) -> (id: CGDirectDisplayID, width: Int, height: Int) {
        let display = self.display
        return nativeResolution ? (display.id, display.width * 2, display.height * 2) : display
    }
}

struct MockScreenCapturePermissionProvider: ScreenCapturePermissionProvider {
    var isGranted: Bool = true
    var requestAccessResult: Bool = true

    func preflightAccess() -> Bool {
        return isGranted
    }

    func requestAccess() -> Bool {
        return requestAccessResult
    }
}

final class MockAlertPresenter: AlertPresenter {
    var confirmResult: Bool
    var limitReductionResult: Bool
    private(set) var limitReductionMessages: [String] = []
    private(set) var errors: [(title: String, message: String)] = []

    init(confirmResult: Bool = true, limitReductionResult: Bool = true) {
        self.confirmResult = confirmResult
        self.limitReductionResult = limitReductionResult
    }

    func confirmPurgeRecordings() -> Bool {
        return confirmResult
    }

    func confirmLimitReduction(message: String) -> Bool {
        limitReductionMessages.append(message)
        return limitReductionResult
    }

    func showError(title: String, message: String) {
        errors.append((title, message))
    }
}

struct MockOpenPanelPresenter: OpenPanelPresenter {
    var pathResult: String? = "/tmp/selected_export_folder"

    func chooseDirectory(completion: @escaping (String?) -> Void) {
        completion(pathResult)
    }
}

final class MockUserNotifier: UserNotifier {
    private(set) var succeeded: [URL] = []
    private(set) var failures: [String] = []
    private(set) var informed: [String] = []

    func exportSucceeded(_ url: URL) {
        succeeded.append(url)
    }

    func exportFailed(_ message: String) {
        failures.append(message)
    }

    func inform(title: String, message: String) {
        informed.append(title)
    }
}

final class MockLoginItemController: LoginItemControlling {
    var isEnabled = false
    var error: Error?

    func setEnabled(_ enabled: Bool) throws {
        if let error = error {
            throw error
        }
        isEnabled = enabled
    }
}
