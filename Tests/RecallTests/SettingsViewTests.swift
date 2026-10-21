import Foundation
import AppKit
import SwiftUI

struct SettingsViewTests {
    private static func makeView(
        store: MockChunkStore = MockChunkStore(),
        alert: MockAlertPresenter = MockAlertPresenter(),
        loginItem: MockLoginItemController = MockLoginItemController(),
        openPanel: MockOpenPanelPresenter = MockOpenPanelPresenter(),
        onPurge: @escaping () -> Void = {}
    ) -> SettingsView {
        return SettingsView(
            settings: SettingsManager.shared,
            chunkStore: store,
            openPanelPresenter: openPanel,
            alertPresenter: alert,
            loginItem: loginItem,
            onPurgeRecordings: onPurge
        )
    }

    static func testUsageStatsFormatting() throws {
        let usage = ChunkUsage(count: 33, totalBytes: 45 * 1024 * 1024 + 209_715, totalDuration: 330)
        try check(SettingsView.durationText(usage, maxMinutes: 60) == "5m 30s / 60m max", "Unexpected duration text \(SettingsView.durationText(usage, maxMinutes: 60))")
        try check(SettingsView.sizeText(usage, maxMB: 1000) == "45.2 MB / 1000 MB max", "Unexpected size text \(SettingsView.sizeText(usage, maxMB: 1000))")
    }

    static func testTypedValuesAreClamped() throws {
        let settings = SettingsManager.shared
        settings.resetToDefaults()
        let view = makeView()

        view.applyStorageMB(0)
        try check(settings.maxStorageMB == ConfigManager.shared.minStorageMB, "0 MB should clamp to the minimum, got \(settings.maxStorageMB)")
        view.applyStorageMinutes(-5)
        try check(settings.maxStorageMinutes == ConfigManager.shared.minStorageMinutes, "Negative minutes should clamp to the minimum, got \(settings.maxStorageMinutes)")
        view.applyStorageMB(10_000_000)
        try check(settings.maxStorageMB == ConfigManager.shared.maxAllowedStorageMB, "Huge values should clamp to the maximum")
        settings.resetToDefaults()
    }

    static func testLoweringLimitBelowUsageAsksFirst() throws {
        let settings = SettingsManager.shared
        settings.resetToDefaults()
        let store = MockChunkStore()
        store.usageOverride = ChunkUsage(count: 50, totalBytes: 500 * 1024 * 1024, totalDuration: 1800)

        let declining = MockAlertPresenter(limitReductionResult: false)
        makeView(store: store, alert: declining).applyStorageMB(100)
        try check(settings.maxStorageMB == 1000, "A declined reduction must keep the old limit")
        try check(declining.limitReductionMessages.first?.contains("400 MB") == true, "The prompt should say how much is deleted, got \(declining.limitReductionMessages)")

        makeView(store: store, alert: declining).applyStorageMinutes(10)
        try check(settings.maxStorageMinutes == 60, "A declined time reduction must keep the old limit")

        let accepting = MockAlertPresenter(limitReductionResult: true)
        makeView(store: store, alert: accepting).applyStorageMB(100)
        try check(settings.maxStorageMB == 100, "An accepted reduction should apply")
        settings.resetToDefaults()
    }

    static func testRaisingLimitDoesNotAsk() throws {
        let settings = SettingsManager.shared
        settings.resetToDefaults()
        let store = MockChunkStore()
        store.usageOverride = ChunkUsage(count: 50, totalBytes: 500 * 1024 * 1024, totalDuration: 1800)
        let alert = MockAlertPresenter(limitReductionResult: false)

        makeView(store: store, alert: alert).applyStorageMB(2000)
        makeView(store: store, alert: alert).applyStorageMB(600)  // lower, but still above usage
        try check(alert.limitReductionMessages.isEmpty, "No prompt when nothing would be deleted")
        try check(settings.maxStorageMB == 600, "Expected 600 MB, got \(settings.maxStorageMB)")
        settings.resetToDefaults()
    }

    static func testResetStorageDefaults() throws {
        let settings = SettingsManager.shared
        settings.maxStorageMB = 2500
        settings.maxStorageMinutes = 120

        var purgedCalled = false
        let view = makeView(onPurge: { purgedCalled = true })

        view.resetStorageMB()
        try check(settings.maxStorageMB == 1000, "Expected resetStorageMB to restore 1000 MB default")
        view.resetStorageMinutes()
        try check(settings.maxStorageMinutes == 60, "Expected resetStorageMinutes to restore 60 minutes default")
        view.onPurgeRecordings()
        try check(purgedCalled, "Expected onPurgeRecordings callback to execute")
    }

    static func testLaunchAtLoginToggle() throws {
        let loginItem = MockLoginItemController()
        let alert = MockAlertPresenter()
        let view = makeView(alert: alert, loginItem: loginItem)

        view.setLaunchAtLogin(true)
        try check(loginItem.isEnabled, "Expected the login item to be enabled")

        loginItem.error = CocoaError(.fileWriteNoPermission)
        view.setLaunchAtLogin(false)
        try check(loginItem.isEnabled, "A failed change must leave the login item as it was")
        try check(alert.errors.count == 1, "A failed change should be reported")
    }

    static func testPreferencesDirectoryPickerConfirmed() throws {
        let settings = SettingsManager.shared
        makeView(openPanel: MockOpenPanelPresenter(pathResult: "/tmp/custom_export_path")).chooseDirectory()
        try check(settings.exportsDirectoryPath == "/tmp/custom_export_path", "Expected exportsDirectoryPath to update to /tmp/custom_export_path")
        settings.resetToDefaults()
    }

    static func testPreferencesDirectoryPickerCancelled() throws {
        let settings = SettingsManager.shared
        let initialPath = settings.exportsDirectoryPath
        makeView(openPanel: MockOpenPanelPresenter(pathResult: nil)).chooseDirectory()
        try check(settings.exportsDirectoryPath == initialPath, "Expected exportsDirectoryPath to remain unchanged on cancel")
    }

    static func testRenderSettingsView() throws {
        let hosting = NSHostingView(rootView: makeView())
        hosting.frame = NSRect(x: 0, y: 0, width: ConfigManager.shared.preferencesWindowWidth, height: ConfigManager.shared.preferencesWindowHeight)
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        try check(fitting.height <= ConfigManager.shared.preferencesWindowHeight + 1, "Content does not fit the window: \(fitting)")
    }
}
