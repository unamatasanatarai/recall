import AppKit
import Foundation

struct DefaultProtocolsCoverageTests {
    static func testDefaultScreenCapturePermissionProvider() throws {
        var provider = DefaultScreenCapturePermissionProvider()
        provider.preflight = { true }
        provider.request = { false }

        try check(provider.preflightAccess(), "Expected preflight true")
        try check(!provider.requestAccess(), "Expected request false")
    }

    static func testDefaultAlertPresenter() throws {
        var presenter = DefaultAlertPresenter()
        var shown: [String] = []
        presenter.modalRunner = { alert in
            shown.append(alert.messageText)
            return .alertFirstButtonReturn
        }
        try check(presenter.confirmPurgeRecordings(), "Expected confirmPurgeRecordings true")
        try check(presenter.confirmLimitReduction(message: "Deletes 10 MB"), "Expected confirmLimitReduction true")
        presenter.showError(title: "Export Failed", message: "Disk full")

        presenter.modalRunner = { alert in
            shown.append(alert.messageText)
            return .alertSecondButtonReturn
        }
        try check(!presenter.confirmPurgeRecordings(), "Expected confirmPurgeRecordings false")
        try check(!presenter.confirmLimitReduction(message: "Deletes 10 MB"), "Expected confirmLimitReduction false")
        try check(shown.count == 5 && shown.contains("Export Failed"), "Unexpected alerts \(shown)")
    }

    static func testDefaultOpenPanelPresenter() throws {
        var presenter = DefaultOpenPanelPresenter()
        presenter.windowFetcher = { nil }

        presenter.modalRunner = { panel in
            return .OK
        }
        var doneModal = false
        presenter.chooseDirectory { path in
            doneModal = true
        }
        try check(doneModal, "Expected modal completion call")

        presenter.modalRunner = { panel in
            return .cancel
        }
        presenter.chooseDirectory { _ in }

        // Test Sheet path
        let dummyWindow = NSWindow()
        presenter.windowFetcher = { dummyWindow }
        presenter.sheetRunner = { panel, window, completion in
            completion(.OK)
        }
        var doneSheet = false
        presenter.chooseDirectory { path in
            doneSheet = true
        }
        try check(doneSheet, "Expected sheet completion call")
    }

    static func testDefaultVideoMetadataProviderReadsRealChunk() throws {
        let directory = TestSandbox.makeDirectory("metadata")
        let chunk = try TestMedia.writeChunk(in: directory, startDate: Date(), duration: 1.0)
        let meta = DefaultVideoMetadataProvider().durationAndIsValid(for: chunk.url)
        try check(meta.isValid && abs(meta.duration - 1.0) < 0.05, "Expected a valid 1 s chunk, got \(meta)")
    }
}
