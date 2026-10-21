import AppKit
import UserNotifications

/// Reports export results through Notification Center. When notifications are unavailable
/// (not allowed, or not running from the app bundle) failures fall back to an alert.
final class SystemNotifier: NSObject, UserNotifier, UNUserNotificationCenterDelegate {
    static let shared = SystemNotifier()

    var alertPresenter: AlertPresenter = DefaultAlertPresenter()

    private lazy var center: UNUserNotificationCenter? = {
        // UNUserNotificationCenter raises an exception outside an app bundle.
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }()

    func exportSucceeded(_ url: URL) {
        post(title: "Clip saved", body: url.lastPathComponent, userInfo: ["path": url.path], fallback: nil)
    }

    func exportFailed(_ message: String) {
        post(title: "Export failed", body: message, userInfo: [:]) { [weak self] in
            self?.alertPresenter.showError(title: "Export Failed", message: message)
        }
    }

    func inform(title: String, message: String) {
        post(title: title, body: message, userInfo: [:]) {
            NSSound.beep()
        }
    }

    private func post(title: String, body: String, userInfo: [String: String], fallback: (() -> Void)?) {
        guard let center = center else {
            fallback?()
            return
        }
        // Only prompts the first time; afterwards it returns the user's choice.
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                guard granted else {
                    fallback?()
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.userInfo = userInfo
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let path = response.notification.request.content.userInfo["path"] as? String {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        completionHandler()
    }
}
