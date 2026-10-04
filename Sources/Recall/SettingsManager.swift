import Foundation
import Combine

final class SettingsManager: ObservableObject, @unchecked Sendable {
    static let shared = SettingsManager()

    private enum Keys {
        static let exportsDirectoryPath = "exportsDirectoryPath"
        static let maxStorageMB = "maxStorageMB"
        static let maxStorageMinutes = "maxStorageMinutes"
    }

    private let defaults = UserDefaults.standard

    static var defaultExportsDirectory: URL {
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        return moviesDir.appendingPathComponent("Recall-exports")
    }

    static let defaultMaxStorageMB = 1000
    static let defaultMaxStorageMinutes = 60

    var onSettingsChanged: (() -> Void)?

    @Published var exportsDirectoryPath: String {
        didSet {
            defaults.set(exportsDirectoryPath, forKey: Keys.exportsDirectoryPath)
        }
    }

    @Published var maxStorageMB: Int {
        didSet {
            defaults.set(maxStorageMB, forKey: Keys.maxStorageMB)
            onSettingsChanged?()
        }
    }

    @Published var maxStorageMinutes: Int {
        didSet {
            defaults.set(maxStorageMinutes, forKey: Keys.maxStorageMinutes)
            onSettingsChanged?()
        }
    }

    private init() {
        if let savedPath = defaults.string(forKey: Keys.exportsDirectoryPath), !savedPath.isEmpty {
            self.exportsDirectoryPath = savedPath
        } else {
            self.exportsDirectoryPath = SettingsManager.defaultExportsDirectory.path
        }

        let savedMB = defaults.integer(forKey: Keys.maxStorageMB)
        if savedMB > 0 {
            self.maxStorageMB = savedMB
        } else {
            self.maxStorageMB = SettingsManager.defaultMaxStorageMB
        }

        let savedMin = defaults.integer(forKey: Keys.maxStorageMinutes)
        if savedMin > 0 {
            self.maxStorageMinutes = savedMin
        } else {
            self.maxStorageMinutes = SettingsManager.defaultMaxStorageMinutes
        }
    }

    var exportsDirectoryURL: URL {
        let path = (exportsDirectoryPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var maxBufferSizeBytes: Int64 {
        return Int64(maxStorageMB) * 1024 * 1024
    }

    var maxStorageDurationSeconds: TimeInterval {
        return TimeInterval(maxStorageMinutes) * 60.0
    }

    func resetToDefaults() {
        exportsDirectoryPath = SettingsManager.defaultExportsDirectory.path
        maxStorageMB = SettingsManager.defaultMaxStorageMB
        maxStorageMinutes = SettingsManager.defaultMaxStorageMinutes
    }
}
