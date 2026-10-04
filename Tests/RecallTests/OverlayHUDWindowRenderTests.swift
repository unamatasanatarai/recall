import AppKit
import SwiftUI

struct OverlayHUDWindowRenderTests {
    static func testZeroDistanceBeamPath() throws {
        let shape = TaperedBeamShape(
            startPoint: CGPoint(x: 100, y: 100),
            endPoint: CGPoint(x: 100, y: 100),
            startWidth: 10,
            endWidth: 20
        )
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 200, height: 200))
        if !path.isEmpty {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected empty path for zero-distance beam"])
        }
    }

    static func testBeamEndWidthClamping() throws {
        let computeBeamEndWidth = { (dist: CGFloat) -> CGFloat in
            return min(26.0, max(10.0, dist * 0.045))
        }

        let shortWidth = computeBeamEndWidth(20.0) // 0.9 -> clamped to 10.0
        let longWidth = computeBeamEndWidth(1000.0) // 45.0 -> clamped to 26.0
        let midWidth = computeBeamEndWidth(300.0) // 13.5

        if shortWidth != 10.0 || longWidth != 26.0 || midWidth != 13.5 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Beam width clamping math mismatch"])
        }
    }

    static func testSubMinuteHUDTimeFormatting() throws {
        let testDate = Date(timeIntervalSince1970: 1700000000)
        let res = OverlayHUDBeamView.formatTimeOffset(15.0, referenceDate: testDate)
        if !res.contains("(-0.5min)") {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected (-0.5min) for sub-minute 15s offset, got \(res)"])
        }

        let res2 = OverlayHUDBeamView.formatTimeOffset(120.0, referenceDate: testDate)
        if !res2.contains("(-2min)") {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected (-2min) for 120s offset, got \(res2)"])
        }
    }

    static func testOrderOutHUDAction() throws {
        let window = OverlayHUDWindow.shared
        window.hideHUD()
        if window.isVisible {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected window.isVisible = false after hideHUD()"])
        }
    }

    static func testRenderOverlayHUDBeamView() throws {
        let viewModel = HUDViewModel()
        viewModel.startPoint = CGPoint(x: 100, y: 100)
        viewModel.currentPoint = CGPoint(x: 100, y: 300)
        viewModel.offsetSeconds = 120.0
        let view = OverlayHUDBeamView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        _ = hostingView.fittingSize
    }

    static func testRenderHUDTimeBadge() throws {
        let badge = HUDTimeBadge(timeText: "14:29 (-2min)")
        let hostingView = NSHostingView(rootView: badge)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 50)
        _ = hostingView.fittingSize
    }
}


