import Foundation
import Combine

final class SettingsManager: ObservableObject, @unchecked Sendable {
    static let shared = SettingsManager()

    private enum Keys {
        static let exportsDirectoryPath = "exportsDirectoryPath"
        static let maxStorageMB = "maxStorageMB"
        static let maxStorageMinutes = "maxStorageMinutes"
        static let recordAtNativeResolution = "recordAtNativeResolution"
        static let useHEVC = "useHEVC"
    }

    /// Storage values read by the chunk store's background queues.
    private struct StorageSnapshot {
        var maxBufferSizeBytes: Int64
        var maxStorageDurationSeconds: TimeInterval
        var exportsDirectoryPath: String
    }

    private let defaults: UserDefaults
    private let snapshotLock = NSLock()
    private var snapshot = StorageSnapshot(maxBufferSizeBytes: 0, maxStorageDurationSeconds: 0, exportsDirectoryPath: "")

    static var defaultExportsDirectory: URL {
        return ConfigManager.shared.defaultExportsDirectory
    }

    static var defaultMaxStorageMB: Int {
        return ConfigManager.shared.defaultMaxStorageMB
    }

    static var defaultMaxStorageMinutes: Int {
        return ConfigManager.shared.defaultMaxStorageMinutes
    }

    static func clampedStorageMB(_ value: Int) -> Int {
        let config = ConfigManager.shared
        return min(config.maxAllowedStorageMB, max(config.minStorageMB, value))
    }

    static func clampedStorageMinutes(_ value: Int) -> Int {
        let config = ConfigManager.shared
        return min(config.maxAllowedStorageMinutes, max(config.minStorageMinutes, value))
    }

    /// Storage limits changed; recordings over the new limits should be purged.
    var onSettingsChanged: (() -> Void)?
    /// Capture options changed; the recorder should pick them up.
    var onRecordingOptionsChanged: (() -> Void)?

    @Published var exportsDirectoryPath: String {
        didSet {
            defaults.set(exportsDirectoryPath, forKey: Keys.exportsDirectoryPath)
            updateSnapshot()
        }
    }

    @Published var maxStorageMB: Int {
        didSet {
            // Out-of-range values (typed into the text field) must never reach retention.
            let clamped = SettingsManager.clampedStorageMB(maxStorageMB)
            if clamped != maxStorageMB {
                maxStorageMB = clamped
            }
            defaults.set(maxStorageMB, forKey: Keys.maxStorageMB)
            updateSnapshot()
            onSettingsChanged?()
        }
    }

    @Published var maxStorageMinutes: Int {
        didSet {
            let clamped = SettingsManager.clampedStorageMinutes(maxStorageMinutes)
            if clamped != maxStorageMinutes {
                maxStorageMinutes = clamped
            }
            defaults.set(maxStorageMinutes, forKey: Keys.maxStorageMinutes)
            updateSnapshot()
            onSettingsChanged?()
        }
    }

    @Published var recordAtNativeResolution: Bool {
        didSet {
            defaults.set(recordAtNativeResolution, forKey: Keys.recordAtNativeResolution)
            onRecordingOptionsChanged?()
        }
    }

    @Published var useHEVC: Bool {
        didSet {
            defaults.set(useHEVC, forKey: Keys.useHEVC)
            onRecordingOptionsChanged?()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let savedPath = defaults.string(forKey: Keys.exportsDirectoryPath), !savedPath.isEmpty {
            self.exportsDirectoryPath = savedPath
        } else {
            self.exportsDirectoryPath = SettingsManager.defaultExportsDirectory.path
        }

        let savedMB = defaults.integer(forKey: Keys.maxStorageMB)
        self.maxStorageMB = savedMB > 0 ? SettingsManager.clampedStorageMB(savedMB) : SettingsManager.defaultMaxStorageMB

        let savedMin = defaults.integer(forKey: Keys.maxStorageMinutes)
        self.maxStorageMinutes = savedMin > 0 ? SettingsManager.clampedStorageMinutes(savedMin) : SettingsManager.defaultMaxStorageMinutes

        self.recordAtNativeResolution = defaults.bool(forKey: Keys.recordAtNativeResolution)
        self.useHEVC = defaults.bool(forKey: Keys.useHEVC)

        updateSnapshot()
    }

    private func updateSnapshot() {
        let newSnapshot = StorageSnapshot(
            maxBufferSizeBytes: Int64(maxStorageMB) * 1024 * 1024,
            maxStorageDurationSeconds: TimeInterval(maxStorageMinutes) * 60.0,
            exportsDirectoryPath: exportsDirectoryPath
        )
        snapshotLock.withCriticalSection { snapshot = newSnapshot }
    }

    var recordingOptions: RecordingOptions {
        return RecordingOptions(recordAtNativeResolution: recordAtNativeResolution, preferHEVC: useHEVC)
    }

    // MARK: - StorageConfig (thread-safe)

    var exportsDirectoryURL: URL {
        let path = snapshotLock.withCriticalSection { snapshot.exportsDirectoryPath }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var maxBufferSizeBytes: Int64 {
        return snapshotLock.withCriticalSection { snapshot.maxBufferSizeBytes }
    }

    var maxStorageDurationSeconds: TimeInterval {
        return snapshotLock.withCriticalSection { snapshot.maxStorageDurationSeconds }
    }

    func resetToDefaults() {
        exportsDirectoryPath = SettingsManager.defaultExportsDirectory.path
        maxStorageMB = SettingsManager.defaultMaxStorageMB
        maxStorageMinutes = SettingsManager.defaultMaxStorageMinutes
    }
}
