import AppKit
import SwiftUI

final class HUDViewModel: ObservableObject {
    @Published var startPoint: CGPoint = .zero
    @Published var currentPoint: CGPoint = .zero
    @Published var badgeCenter: CGPoint = .zero
    @Published var offsetSeconds: TimeInterval = 0
    @Published var label: String = ""
}

final class OverlayHUDWindow: NSWindow {
    static let shared = OverlayHUDWindow()

    /// Room around the beam for its glow and the knob at its end.
    static let beamMargin: CGFloat = 40
    static let badgeSize = CGSize(width: 210, height: 30)
    private static let badgeGap: CGFloat = 24
    private static let edgeInset: CGFloat = 8

    /// Window frame (screen coordinates) and the points to draw, in the window's top-left view space.
    struct Layout: Equatable {
        let frame: NSRect
        let startPoint: CGPoint
        let currentPoint: CGPoint
        let badgeCenter: CGPoint
    }

    private let viewModel = HUDViewModel()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .popUpMenu
        self.ignoresMouseEvents = true
        self.hasShadow = false
        // Keep the beam out of screenshots and screen sharing wherever the system honours it.
        // ScreenCaptureKit recording excludes it explicitly.
        self.sharingType = .none

        self.contentView = NSHostingView(rootView: OverlayHUDBeamView(viewModel: viewModel))
    }

    /// Sizes the window to the beam and badge rather than the whole screen, so the blurred
    /// layers are composited over a small area. The badge flips to the left of the knob when it
    /// would run off the right edge (status items sit near it).
    static func layout(start: NSPoint, current: NSPoint, screenFrame: NSRect, badgeSize: CGSize = OverlayHUDWindow.badgeSize) -> Layout {
        let halfWidth = badgeSize.width / 2
        var badgeX = current.x + badgeGap + halfWidth
        if badgeX + halfWidth > screenFrame.maxX - edgeInset {
            badgeX = current.x - badgeGap - halfWidth
        }
        badgeX = min(max(badgeX, screenFrame.minX + edgeInset + halfWidth), screenFrame.maxX - edgeInset - halfWidth)
        let badgeY = current.y - 14
        let badgeRect = NSRect(x: badgeX - halfWidth, y: badgeY - badgeSize.height / 2, width: badgeSize.width, height: badgeSize.height)

        let beamRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        ).insetBy(dx: -beamMargin, dy: -beamMargin)

        let frame = beamRect.union(badgeRect.insetBy(dx: -12, dy: -12)).intersection(screenFrame).integral

        func viewPoint(_ point: NSPoint) -> CGPoint {
            // Cocoa screen coordinates (origin bottom-left) to SwiftUI view coordinates (origin top-left)
            return CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        }
        return Layout(frame: frame, startPoint: viewPoint(start), currentPoint: viewPoint(current), badgeCenter: viewPoint(NSPoint(x: badgeX, y: badgeY)))
    }

    func show(at mouseLocation: NSPoint, startLocation: NSPoint, offsetSeconds: TimeInterval, startDate: Date? = nil, screen: NSScreen? = nil) {
        guard let screen = screen ?? NSScreen.main else { return }
        let layout = OverlayHUDWindow.layout(start: startLocation, current: mouseLocation, screenFrame: screen.frame)

        if self.frame != layout.frame {
            self.setFrame(layout.frame, display: false)
        }

        // Reactive update of ViewModel properties without destroying NSHostingView tree
        viewModel.startPoint = layout.startPoint
        viewModel.currentPoint = layout.currentPoint
        viewModel.badgeCenter = layout.badgeCenter
        viewModel.offsetSeconds = offsetSeconds
        viewModel.label = OverlayHUDBeamView.formatTimeOffset(offsetSeconds, startDate: startDate ?? Date().addingTimeInterval(-offsetSeconds))

        if !self.isVisible {
            self.orderFrontRegardless()
        }
    }

    func hideHUD() {
        self.orderOut(nil)
    }
}

struct TaperedBeamShape: Shape {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let startWidth: CGFloat
    let endWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return path }

        // Normal unit vector perpendicular to beam vector (dx, dy)
        let nx = -dy / distance
        let ny = dx / distance

        let p1 = CGPoint(x: startPoint.x + nx * (startWidth / 2), y: startPoint.y + ny * (startWidth / 2))
        let p2 = CGPoint(x: startPoint.x - nx * (startWidth / 2), y: startPoint.y - ny * (startWidth / 2))
        let p3 = CGPoint(x: endPoint.x - nx * (endWidth / 2), y: endPoint.y - ny * (endWidth / 2))
        let p4 = CGPoint(x: endPoint.x + nx * (endWidth / 2), y: endPoint.y + ny * (endWidth / 2))

        path.move(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        path.addLine(to: p4)
        path.closeSubpath()
        return path
    }
}

struct OverlayHUDBeamView: View {
    @ObservedObject var viewModel: HUDViewModel

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var beamEndWidth: CGFloat {
        let dx = viewModel.currentPoint.x - viewModel.startPoint.x
        let dy = viewModel.currentPoint.y - viewModel.startPoint.y
        let dist = hypot(dx, dy)
        return min(26.0, max(10.0, dist * 0.045))
    }

    var body: some View {
        let electricBlue = Color(red: 0.05, green: 0.5, blue: 1.0)
        let neonCyan = Color(red: 0.2, green: 0.85, blue: 1.0)
        let deepBlue = Color(red: 0.0, green: 0.35, blue: 0.95)

        return ZStack(alignment: .topLeading) {
            // Layer 1: Ambient Glow Blur
            TaperedBeamShape(
                startPoint: viewModel.startPoint,
                endPoint: viewModel.currentPoint,
                startWidth: 4,
                endWidth: beamEndWidth + 12
            )
            .fill(
                LinearGradient(
                    colors: [electricBlue.opacity(0.2), neonCyan.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blur(radius: 8)

            // Layer 2: Main Translucent Tapered Beam
            TaperedBeamShape(
                startPoint: viewModel.startPoint,
                endPoint: viewModel.currentPoint,
                startWidth: 3,
                endWidth: beamEndWidth
            )
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.6),
                        electricBlue.opacity(0.75),
                        deepBlue.opacity(0.9)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Layer 3: Inner Core Light Flare Highlight
            TaperedBeamShape(
                startPoint: viewModel.startPoint,
                endPoint: viewModel.currentPoint,
                startWidth: 1.5,
                endWidth: beamEndWidth * 0.35
            )
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.7),
                        neonCyan.opacity(0.4)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blur(radius: 1)

            // Lens Knob / Endpoint Circle at current drag position
            ZStack {
                Circle()
                    .fill(electricBlue.opacity(0.3))
                    .frame(width: beamEndWidth + 14, height: beamEndWidth + 14)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, neonCyan, deepBlue],
                            center: .center,
                            startRadius: 2,
                            endRadius: beamEndWidth / 2
                        )
                    )
                    .frame(width: beamEndWidth + 2, height: beamEndWidth + 2)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    )
                    .shadow(color: electricBlue.opacity(0.4), radius: 6)

                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }
            .position(x: viewModel.currentPoint.x, y: viewModel.currentPoint.y)

            // macOS Glassmorphism HUD Badge
            HUDTimeBadge(timeText: viewModel.label)
                .position(x: viewModel.badgeCenter.x, y: viewModel.badgeCenter.y)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "45s", "2m 30s", "1h 15m".
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 {
            return "\(total)s"
        }
        if total < 3600 {
            let mins = total / 60
            let secs = total % 60
            return secs == 0 ? "\(mins)m" : "\(mins)m \(secs)s"
        }
        let hours = total / 3600
        let mins = (total % 3600) / 60
        return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
    }

    /// Clock time where the clip starts and how much footage it holds, e.g. "14:27:30 (-2m 30s)".
    static func formatTimeOffset(_ seconds: TimeInterval, startDate: Date) -> String {
        guard seconds >= ConfigManager.shared.minExportOffsetSeconds else {
            return "Nothing recorded yet"
        }
        return "\(OverlayHUDBeamView.timeFormatter.string(from: startDate)) (-\(formatDuration(seconds)))"
    }
}

struct HUDTimeBadge: View {
    let timeText: String

    var body: some View {
        let neonCyan = Color(red: 0.2, green: 0.85, blue: 1.0)
        let electricBlue = Color(red: 0.05, green: 0.5, blue: 1.0)

        return HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption.weight(.bold))
                .foregroundColor(neonCyan)

            Text(timeText)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(electricBlue.opacity(0.6), lineWidth: 1)
                )
                .shadow(color: electricBlue.opacity(0.4), radius: 6, x: 0, y: 3)
        )
    }
}
