import Foundation
import ServiceManagement

/// Opens Recall at login: `SMAppService` on macOS 13 and later, a per-user LaunchAgent on macOS 12.
struct LoginItemController: LoginItemControlling {
    var label = ConfigManager.shared.bundleIdentifier
    var executablePath: String? = Bundle.main.executablePath
    var launchAgentsDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    var fileSystem: FileSystemProvider = FileManager.default
    var usesServiceManagement: Bool = {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }()

    var launchAgentURL: URL {
        return launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    var isEnabled: Bool {
        if usesServiceManagement, #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
            return true
        }
        return fileSystem.fileExists(atPath: launchAgentURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        guard enabled else {
            if usesServiceManagement, #available(macOS 13.0, *) {
                try? SMAppService.mainApp.unregister()
            }
            // Also removes a LaunchAgent written before an upgrade to macOS 13.
            if fileSystem.fileExists(atPath: launchAgentURL.path) {
                try fileSystem.removeItem(at: launchAgentURL)
            }
            return
        }

        if usesServiceManagement, #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                return
            } catch {
                Log.app.error("SMAppService registration failed (\(error.localizedDescription, privacy: .public)); using a LaunchAgent")
            }
        }
        try writeLaunchAgent()
    }

    private func writeLaunchAgent() throws {
        guard let executablePath = executablePath else {
            throw CocoaError(.fileNoSuchFile)
        }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try fileSystem.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true, attributes: nil)
        try fileSystem.writeData(data, to: launchAgentURL)
    }
}
