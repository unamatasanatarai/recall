import AppKit
import Foundation

struct DefaultProtocolsCoverageTests {
    static func testDefaultScreenCapturePermissionProvider() throws {
        var provider = DefaultScreenCapturePermissionProvider()
        provider.preflight = { true }
        provider.request = { false }

        if !provider.preflightAccess() {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected preflight true"])
        }
        if provider.requestAccess() {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected request false"])
        }
    }

    static func testDefaultAlertPresenter() throws {
        var presenter = DefaultAlertPresenter()
        presenter.modalRunner = { alert in
            return .alertFirstButtonReturn
        }
        if !presenter.confirmPurgeRecordings() {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected confirmPurgeRecordings true"])
        }

        presenter.modalRunner = { alert in
            return .alertSecondButtonReturn
        }
        if presenter.confirmPurgeRecordings() {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected confirmPurgeRecordings false"])
        }
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
        if !doneModal {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected modal completion call"])
        }

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
        if !doneSheet {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected sheet completion call"])
        }
    }

    static func testDefaultFFmpegRunnerConcatAndTrim() throws {
        var runner = DefaultFFmpegRunner()
        runner.processRunner = { execURL, args in
            return 0
        }

        let listURL = URL(fileURLWithPath: "/tmp/list.txt")
        let outputURL = URL(fileURLWithPath: "/tmp/out.mp4")
        let success = runner.concatAndTrim(listURL: listURL, outputURL: outputURL, excessSeconds: 1.5, ffmpegPath: "/usr/local/bin/ffmpeg")

        if !success {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected concatAndTrim success"])
        }

        let runnerDefault = DefaultFFmpegRunner()
        _ = runnerDefault.findFFmpegPath()
    }
}
