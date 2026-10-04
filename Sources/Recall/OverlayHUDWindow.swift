import AppKit
import SwiftUI

final class HUDViewModel: ObservableObject {
    @Published var startPoint: CGPoint = .zero
    @Published var currentPoint: CGPoint = .zero
    @Published var offsetSeconds: TimeInterval = 0
}

final class OverlayHUDWindow: NSWindow {
    static let shared = OverlayHUDWindow()

    private let viewModel = HUDViewModel()
    private var hostingView: NSHostingView<OverlayHUDBeamView>?

    private init() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .popUpMenu
        self.ignoresMouseEvents = true
        self.hasShadow = false

        let beamView = OverlayHUDBeamView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: beamView)
        self.contentView = hosting
        self.hostingView = hosting
    }

    func show(at mouseLocation: NSPoint, startLocation: NSPoint, offsetSeconds: TimeInterval) {
        guard let mainScreen = NSScreen.main else { return }
        let screenFrame = mainScreen.frame

        if self.frame != screenFrame {
            self.setFrame(screenFrame, display: true)
        }

        // Convert Cocoa screen coordinates (origin bottom-left) to SwiftUI view coordinates (origin top-left)
        let startViewPoint = CGPoint(x: startLocation.x, y: screenFrame.height - startLocation.y)
        let currentViewPoint = CGPoint(x: mouseLocation.x, y: screenFrame.height - mouseLocation.y)

        // Reactive update of ViewModel properties without destroying NSHostingView tree
        viewModel.startPoint = startViewPoint
        viewModel.currentPoint = currentViewPoint
        viewModel.offsetSeconds = offsetSeconds

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
        formatter.dateFormat = "HH:mm"
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
            HUDTimeBadge(timeText: OverlayHUDBeamView.formatTimeOffset(viewModel.offsetSeconds))
                .position(x: viewModel.currentPoint.x + 95, y: viewModel.currentPoint.y + 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func formatTimeOffset(_ seconds: TimeInterval, referenceDate: Date = Date()) -> String {
        let mins = max(0.5, seconds / 60.0)
        let minsFormatted: String
        if mins.truncatingRemainder(dividingBy: 1.0) == 0 {
            minsFormatted = String(format: "%.0f", mins)
        } else {
            minsFormatted = String(format: "%.1f", mins)
        }

        let roundedMins = (seconds / 60.0).rounded()
        let targetDate = Date(timeIntervalSince1970: referenceDate.timeIntervalSince1970 - (roundedMins * 60.0))
        let clockTime = OverlayHUDBeamView.timeFormatter.string(from: targetDate)

        return "\(clockTime) (-\(minsFormatted)min)"
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
