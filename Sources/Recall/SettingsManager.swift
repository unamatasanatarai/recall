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
        let savedPath = defaults.string(forKey: Keys.exportsDirectoryPath)
        if let savedPath = savedPath, !savedPath.isEmpty {
            self.exportsDirectoryPath = savedPath
        } else {
            self.exportsDirectoryPath = SettingsManager.defaultExportsDirectory.path
        }

        let savedMB = defaults.integer(forKey: Keys.maxStorageMB)
        self.maxStorageMB = savedMB > 0 ? savedMB : 1000 // Default 1000 MB (1 GB)

        let savedMin = defaults.integer(forKey: Keys.maxStorageMinutes)
        self.maxStorageMinutes = savedMin > 0 ? savedMin : 60 // Default 60 Minutes (1 Hour)
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
        maxStorageMB = 1000
        maxStorageMinutes = 60
    }
}
