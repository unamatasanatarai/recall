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
        try check(path.isEmpty, "Expected empty path for zero-distance beam")
    }

    static func testDurationFormatting() throws {
        let cases: [(TimeInterval, String)] = [(10, "10s"), (45, "45s"), (60, "1m"), (150, "2m 30s"), (3600, "1h"), (4500, "1h 15m")]
        for (seconds, expected) in cases {
            let formatted = OverlayHUDBeamView.formatDuration(seconds)
            try check(formatted == expected, "Expected \(expected) for \(seconds)s, got \(formatted)")
        }
    }

    static func testTimeOffsetShowsClipStart() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let res = OverlayHUDBeamView.formatTimeOffset(150, startDate: start)
        let expected = "\(formatter.string(from: start)) (-2m 30s)"
        try check(res == expected, "Expected \(expected), got \(res)")

        let subMinute = OverlayHUDBeamView.formatTimeOffset(10, startDate: start)
        try check(subMinute.hasSuffix("(-10s)"), "Sub-minute offsets should be exact, got \(subMinute)")

        try check(OverlayHUDBeamView.formatTimeOffset(0, startDate: start) == "Nothing recorded yet", "Expected an explanation when there is no footage")
    }

    static func testRenderOverlayHUDBeamView() throws {
        let viewModel = HUDViewModel()
        viewModel.startPoint = CGPoint(x: 100, y: 100)
        viewModel.currentPoint = CGPoint(x: 100, y: 300)
        viewModel.badgeCenter = CGPoint(x: 230, y: 314)
        viewModel.offsetSeconds = 120.0
        viewModel.label = OverlayHUDBeamView.formatTimeOffset(120, startDate: Date().addingTimeInterval(-120))
        let hostingView = NSHostingView(rootView: OverlayHUDBeamView(viewModel: viewModel))
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        _ = hostingView.fittingSize
    }

    static func testBadgeFitsLongestLabel() throws {
        let badge = HUDTimeBadge(timeText: "23:59:59 (-23h 59m)")
        let hostingView = NSHostingView(rootView: badge)
        let size = hostingView.fittingSize
        try check(size.width <= OverlayHUDWindow.badgeSize.width, "The badge layout reserves \(OverlayHUDWindow.badgeSize.width)pt, the label needs \(size.width)pt")
    }
}
