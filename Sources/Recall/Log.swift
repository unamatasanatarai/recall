import Foundation
import os

/// Unified logging. View with Console.app or
/// `log stream --predicate 'subsystem == "com.recall.app"'`.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.recall.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let recorder = Logger(subsystem: subsystem, category: "recorder")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let export = Logger(subsystem: subsystem, category: "export")
}
