import Foundation
import AVFoundation
import AppKit
import Combine

// MARK: - StorageConfig Protocol
protocol StorageConfig {
    var maxBufferSizeBytes: Int64 { get }
    var maxStorageDurationSeconds: TimeInterval { get }
    var exportsDirectoryURL: URL { get }
}

extension SettingsManager: StorageConfig {}

// MARK: - FileSystemProvider Protocol
protocol FileSystemProvider {
    func fileExists(atPath path: String) -> Bool
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL]
    func removeItem(at url: URL) throws
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]?) throws
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func readData(at url: URL) -> Data?
    func writeData(_ data: Data, to url: URL) throws
    func excludeFromBackup(_ url: URL)
}

extension FileManager: FileSystemProvider {
    func readData(at url: URL) -> Data? {
        return try? Data(contentsOf: url)
    }

    func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}

// MARK: - VideoMetadataProvider Protocol
protocol VideoMetadataProvider {
    func durationAndIsValid(for url: URL) -> (duration: TimeInterval, isValid: Bool)
}

struct DefaultVideoMetadataProvider: VideoMetadataProvider {
    func durationAndIsValid(for url: URL) -> (duration: TimeInterval, isValid: Bool) {
        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        let isValid = duration.isFinite && duration > 0 && asset.tracks(withMediaType: .video).first != nil
        return (duration, isValid)
    }
}

// MARK: - ChunkStore Protocol
struct ChunkUsage: Equatable {
    var count: Int
    var totalBytes: Int64
    var totalDuration: TimeInterval

    init(count: Int = 0, totalBytes: Int64 = 0, totalDuration: TimeInterval = 0) {
        self.count = count
        self.totalBytes = totalBytes
        self.totalDuration = totalDuration
    }

    init(chunks: [ChunkFile]) {
        self.init(
            count: chunks.count,
            totalBytes: chunks.reduce(0) { $0 + $1.sizeBytes },
            totalDuration: chunks.reduce(0.0) { $0 + $1.duration }
        )
    }
}

/// Export the `footageSeconds` of recording that precede `endDate`.
struct ExportRequest: Equatable {
    let footageSeconds: TimeInterval
    let endDate: Date
}

enum ExportError: LocalizedError, Equatable {
    case noFootage
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noFootage:
            return "There is no recording to export yet."
        case .failed(let reason):
            return reason
        }
    }
}

protocol ChunkStore: AnyObject {
    var chunksDirectory: URL { get }
    /// Current totals. Cheap to read from any thread; never waits on disk work.
    var usage: ChunkUsage { get }
    /// Emits on the main thread whenever chunks are added or removed.
    var usagePublisher: AnyPublisher<ChunkUsage, Never> { get }
    /// Runs `completion` on the main thread once existing chunks have been indexed.
    func whenLoaded(_ completion: @escaping () -> Void)
    func registerChunk(url: URL, startTime: Date, duration: TimeInterval)
    func enforceLimits()
    func purgeAllChunks()
    /// Wall-clock start of the last `footageSeconds` of recorded footage before `endDate`, skipping
    /// pauses. Nil when there is no footage.
    func footageStartDate(footageSeconds: TimeInterval, endingAt endDate: Date) -> Date?
    /// Calls `completion` on the main thread.
    func exportClip(_ request: ExportRequest, completion: @escaping (Result<URL, ExportError>) -> Void)
}

extension ChunkStore {
    var totalRecordedDuration: TimeInterval {
        return usage.totalDuration
    }
}

// MARK: - ScreenCapture Protocol
enum RecordingState: Equatable {
    case idle
    case recording
    case paused
    case error(String)
}

enum PauseReason: String, CaseIterable {
    case user
    case screenLocked
    case screenSaver
    case displaySleep
    case systemSleep
}

struct RecordingOptions: Equatable {
    var recordAtNativeResolution = false
    var preferHEVC = false
}

protocol ScreenCapture: AnyObject {
    var state: RecordingState { get }
    /// Emits on the main thread.
    var statePublisher: AnyPublisher<RecordingState, Never> { get }
    var isPausedByUser: Bool { get }
    /// Seconds recorded into the chunk that is still being written.
    var unsavedDuration: TimeInterval { get }
    func startContinuousRecording()
    func applyRecordingOptions(_ options: RecordingOptions)
    func setPaused(_ paused: Bool, reason: PauseReason)
    func handleDisplayConfigurationChange()
    /// Calls `completion` on the main thread once the chunk in progress has been registered.
    func flushCurrentChunk(completion: (() -> Void)?)
    /// Deletes every recording, including the chunk being written and chunks still being finalized.
    func purgeRecordings()
    /// Calls `completion` on the main thread once every chunk has been finalized.
    func stopStream(completion: (() -> Void)?)
}

// MARK: - ScreenCapturePermissionProvider Protocol
protocol ScreenCapturePermissionProvider {
    func preflightAccess() -> Bool
    func requestAccess() -> Bool
}

struct DefaultScreenCapturePermissionProvider: ScreenCapturePermissionProvider {
    var preflight: () -> Bool = { CGPreflightScreenCaptureAccess() }
    var request: () -> Bool = { CGRequestScreenCaptureAccess() }

    func preflightAccess() -> Bool {
        return preflight()
    }
    func requestAccess() -> Bool {
        return request()
    }
}

// MARK: - AlertPresenter Protocol
protocol AlertPresenter {
    func confirmPurgeRecordings() -> Bool
    func confirmLimitReduction(message: String) -> Bool
    func showError(title: String, message: String)
}

struct DefaultAlertPresenter: AlertPresenter {
    var modalRunner: (NSAlert) -> NSApplication.ModalResponse = { alert in
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    func confirmPurgeRecordings() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Purge Stored Recordings?"
        alert.informativeText = "Are you sure you want to delete all cached recording chunks? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Purge All")
        alert.addButton(withTitle: "Cancel")

        return modalRunner(alert) == .alertFirstButtonReturn
    }

    func confirmLimitReduction(message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete Older Recordings?"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        return modalRunner(alert) == .alertFirstButtonReturn
    }

    func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        _ = modalRunner(alert)
    }
}

// MARK: - OpenPanelPresenter Protocol
protocol OpenPanelPresenter {
    func chooseDirectory(completion: @escaping (String?) -> Void)
}

struct DefaultOpenPanelPresenter: OpenPanelPresenter {
    var windowFetcher: () -> NSWindow? = { NSApp.keyWindow }
    var sheetRunner: (NSOpenPanel, NSWindow, @escaping (NSApplication.ModalResponse) -> Void) -> Void = { panel, window, completion in
        panel.beginSheetModal(for: window, completionHandler: completion)
    }
    var modalRunner: (NSOpenPanel) -> NSApplication.ModalResponse = { panel in
        panel.runModal()
    }

    func chooseDirectory(completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Export Folder"

        if let window = windowFetcher() {
            sheetRunner(panel, window) { response in
                completion(response == .OK ? panel.url?.path : nil)
            }
        } else {
            completion(modalRunner(panel) == .OK ? panel.url?.path : nil)
        }
    }
}

// MARK: - UserNotifier Protocol
protocol UserNotifier {
    func exportSucceeded(_ url: URL)
    func exportFailed(_ message: String)
    func inform(title: String, message: String)
}

// MARK: - LoginItemControlling Protocol
protocol LoginItemControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}
