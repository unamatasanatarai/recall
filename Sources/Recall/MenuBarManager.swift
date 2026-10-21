import AppKit
import Combine
import SwiftUI

final class MenuBarManager: NSObject {
    static let shared = MenuBarManager()

    enum IconStyle {
        case recording
        case paused
        case inactive
    }

    private let recorder: ScreenCapture
    private let chunkStore: ChunkStore
    private let alertPresenter: AlertPresenter
    private let notifier: UserNotifier

    private var statusItem: NSStatusItem?
    private var stateSubscription: AnyCancellable?
    private var icons: [IconStyle: NSImage] = [:]
    private var isDragging = false
    private var isHUDVisible = false
    private var dragStartLocation: NSPoint = .zero
    private var dragScreen: NSScreen?
    private var dragEndDate = Date()
    private var selectedOffsetSeconds: TimeInterval = 0
    private(set) var isExporting = false

    var statusButton: NSStatusBarButton? {
        return statusItem?.button
    }

    var appTerminator: () -> Void = { NSApplication.shared.terminate(nil) }
    var fileRevealer: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }

    init(
        recorder: ScreenCapture = RecorderEngine.shared,
        chunkStore: ChunkStore = ChunkManager.shared,
        alertPresenter: AlertPresenter = DefaultAlertPresenter(),
        notifier: UserNotifier = SystemNotifier.shared
    ) {
        self.recorder = recorder
        self.chunkStore = chunkStore
        self.alertPresenter = alertPresenter
        self.notifier = notifier
        super.init()
    }

    func setupMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        updateStatusAppearance()

        stateSubscription = recorder.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateStatusAppearance(for: state)
            }

        setupDragGestureTracking()
    }

    // MARK: - Status

    func updateStatusAppearance(for state: RecordingState? = nil) {
        guard let button = statusItem?.button else { return }
        let state = state ?? recorder.state
        button.image = icon(for: MenuBarManager.iconStyle(for: state))
        button.contentTintColor = isExporting ? .systemRed : nil
        button.toolTip = "Recall: \(MenuBarManager.statusDescription(for: state))"
    }

    static func iconStyle(for state: RecordingState) -> IconStyle {
        switch state {
        case .recording:
            return .recording
        case .paused:
            return .paused
        case .idle, .error:
            return .inactive
        }
    }

    static func statusDescription(for state: RecordingState) -> String {
        switch state {
        case .recording:
            return "Recording"
        case .paused:
            return "Paused"
        case .idle:
            return "Not recording"
        case .error(let message):
            return "Not recording. \(message)"
        }
    }

    private func icon(for style: IconStyle) -> NSImage {
        if let cached = icons[style] {
            return cached
        }
        let image = MenuBarManager.createMenuBarIcon(style: style)
        icons[style] = image
        return image
    }

    static func createMenuBarIcon(style: IconStyle = .recording) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let icon = NSImage(size: size, flipped: false) { _ in
            guard let cgContext = NSGraphicsContext.current?.cgContext else { return false }

            cgContext.saveGState()
            // Dim the glyph whenever Recall is not recording.
            if style != .recording {
                cgContext.setAlpha(0.45)
            }
            cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            drawGlyph(in: cgContext)
            cgContext.endTransparencyLayer()
            cgContext.restoreGState()

            switch style {
            case .recording:
                break
            case .paused:
                drawPauseBadge(in: cgContext)
            case .inactive:
                drawSlash(in: cgContext)
            }
            return true
        }
        icon.isTemplate = true
        return icon
    }

    private static func drawGlyph(in cgContext: CGContext) {
        // Move drawing 2px up towards top of status bar
        cgContext.translateBy(x: 0, y: 2.0)

        let primaryColor = NSColor.black

        // 1. Clock Circle (Bottom center)
        let clockCenter = CGPoint(x: 9.0, y: 4.8)
        let clockRadius: CGFloat = 4.8

        let clockPath = NSBezierPath(ovalIn: NSRect(
            x: clockCenter.x - clockRadius,
            y: clockCenter.y - clockRadius,
            width: clockRadius * 2,
            height: clockRadius * 2
        ))
        clockPath.lineWidth = 1.05 // Lighter stroke
        primaryColor.setStroke()
        clockPath.stroke()

        // Clock Hands (Hour & Minute hands)
        let handsPath = NSBezierPath()
        handsPath.lineWidth = 1.0 // Lighter stroke
        handsPath.lineCapStyle = .round
        // Hour hand (pointing to ~10 o'clock)
        handsPath.move(to: clockCenter)
        handsPath.line(to: CGPoint(x: 7.0, y: 6.6))
        // Minute hand (pointing to ~2 o'clock)
        handsPath.move(to: clockCenter)
        handsPath.line(to: CGPoint(x: 11.6, y: 6.2))
        primaryColor.setStroke()
        handsPath.stroke()

        // Center Dot
        let dotRadius: CGFloat = 1.1
        let dotPath = NSBezierPath(ovalIn: NSRect(
            x: clockCenter.x - dotRadius,
            y: clockCenter.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))
        primaryColor.setFill()
        dotPath.fill()

        // 2. Fedora Hat (Top tilted over clock)
        // Hat Crown
        let crownPath = NSBezierPath()
        crownPath.move(to: CGPoint(x: 5.6, y: 9.4))
        crownPath.curve(to: CGPoint(x: 7.8, y: 14.6),
                        controlPoint1: CGPoint(x: 5.4, y: 11.6),
                        controlPoint2: CGPoint(x: 6.5, y: 14.1))
        crownPath.curve(to: CGPoint(x: 10.5, y: 13.9),
                        controlPoint1: CGPoint(x: 8.8, y: 13.8),
                        controlPoint2: CGPoint(x: 9.5, y: 13.4))
        crownPath.curve(to: CGPoint(x: 12.8, y: 12.8),
                        controlPoint1: CGPoint(x: 11.5, y: 14.3),
                        controlPoint2: CGPoint(x: 12.4, y: 13.6))
        crownPath.curve(to: CGPoint(x: 12.6, y: 8.1),
                        controlPoint1: CGPoint(x: 13.2, y: 11.1),
                        controlPoint2: CGPoint(x: 13.0, y: 9.1))
        crownPath.curve(to: CGPoint(x: 5.6, y: 9.4),
                        controlPoint1: CGPoint(x: 10.0, y: 7.4),
                        controlPoint2: CGPoint(x: 7.5, y: 8.4))
        crownPath.close()

        primaryColor.setFill()
        crownPath.fill()

        // Hat Brim (Sleek tilted brim)
        let brimPath = NSBezierPath()
        brimPath.move(to: CGPoint(x: 2.2, y: 8.4))
        brimPath.curve(to: CGPoint(x: 15.8, y: 10.6),
                       controlPoint1: CGPoint(x: 6.5, y: 10.6),
                       controlPoint2: CGPoint(x: 11.5, y: 11.6))
        brimPath.curve(to: CGPoint(x: 15.0, y: 9.4),
                       controlPoint1: CGPoint(x: 16.2, y: 10.1),
                       controlPoint2: CGPoint(x: 15.8, y: 9.5))
        brimPath.curve(to: CGPoint(x: 2.2, y: 8.4),
                       controlPoint1: CGPoint(x: 10.5, y: 6.6),
                       controlPoint2: CGPoint(x: 5.5, y: 6.8))
        brimPath.close()

        primaryColor.setFill()
        brimPath.fill()

        // Cut out negative space for the hat ribbon band so it works cleanly as a template mask
        cgContext.setBlendMode(.clear)
        let bandPath = NSBezierPath()
        bandPath.move(to: CGPoint(x: 5.7, y: 9.6))
        bandPath.curve(to: CGPoint(x: 12.5, y: 10.9),
                       controlPoint1: CGPoint(x: 8.0, y: 8.9),
                       controlPoint2: CGPoint(x: 10.5, y: 9.7))
        bandPath.lineWidth = 0.85
        NSColor.black.setStroke()
        bandPath.stroke()
    }

    /// Two bars in the bottom-right corner, on a cleared background so they read at 18pt.
    private static func drawPauseBadge(in cgContext: CGContext) {
        cgContext.saveGState()
        cgContext.setBlendMode(.clear)
        cgContext.fill(CGRect(x: 10.5, y: 0, width: 7.5, height: 8.5))
        cgContext.setBlendMode(.normal)
        cgContext.setFillColor(NSColor.black.cgColor)
        cgContext.fill(CGRect(x: 12.0, y: 1.0, width: 1.8, height: 6.5))
        cgContext.fill(CGRect(x: 15.2, y: 1.0, width: 1.8, height: 6.5))
        cgContext.restoreGState()
    }

    /// A "disabled" slash across the glyph, cut out of it first so the line stays legible.
    private static func drawSlash(in cgContext: CGContext) {
        let start = CGPoint(x: 2.5, y: 16.0)
        let end = CGPoint(x: 15.5, y: 2.0)
        cgContext.saveGState()
        cgContext.setLineCap(.round)
        cgContext.setBlendMode(.clear)
        cgContext.setLineWidth(3.4)
        cgContext.move(to: start)
        cgContext.addLine(to: end)
        cgContext.strokePath()
        cgContext.setBlendMode(.normal)
        cgContext.setStrokeColor(NSColor.black.cgColor)
        cgContext.setLineWidth(1.4)
        cgContext.move(to: start)
        cgContext.addLine(to: end)
        cgContext.strokePath()
        cgContext.restoreGState()
    }

    // MARK: - Actions

    @objc func openSettings() {
        SettingsWindowController.shared.showWindow()
    }

    @objc func togglePause() {
        recorder.setPaused(!recorder.isPausedByUser, reason: .user)
    }

    @objc func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func purgeRecordings() {
        if alertPresenter.confirmPurgeRecordings() {
            // The recorder purges the store too, so chunks it is still finalizing cannot survive.
            recorder.purgeRecordings()
        }
    }

    /// Termination goes through AppDelegate, which finalizes the chunk in progress first.
    @objc func quitApp() {
        appTerminator()
    }

    // MARK: - Drag Gesture

    /// Maps drag progress (0...1) to a snap point. Points are evenly spaced along the drag, so
    /// recent history gets fine steps; the end of the drag selects everything recorded.
    static func snappedOffset(progress: CGFloat, available: TimeInterval, steps: [TimeInterval] = ConfigManager.shared.exportOffsetSteps) -> TimeInterval {
        guard available >= ConfigManager.shared.minExportOffsetSeconds else { return 0 }
        let snapPoints = steps.filter { $0 < available } + [available]
        let index = Int(min(1.0, max(0.0, progress)) * CGFloat(snapPoints.count))
        return snapPoints[min(snapPoints.count - 1, index)]
    }

    @discardableResult
    func handleMouseEvent(type: NSEvent.EventType, mouseLocation: NSPoint, buttonFrame: NSRect) -> Bool {
        if type == .rightMouseDown {
            if buttonFrame.contains(mouseLocation) {
                self.showContextMenu()
                return true // Intercepted
            }
            return false
        }

        if type == .leftMouseDown {
            if buttonFrame.contains(mouseLocation) {
                self.isDragging = true
                self.isHUDVisible = false
                self.dragStartLocation = NSPoint(x: buttonFrame.midX, y: buttonFrame.minY)
                self.dragScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
                // The clip ends when the gesture starts, so the drag itself is never in it.
                self.dragEndDate = Date()
                self.selectedOffsetSeconds = 0
                return true // Intercepted
            }
        }

        if self.isDragging {
            if type == .leftMouseDragged {
                let dy = self.dragStartLocation.y - mouseLocation.y
                if dy > 0 {
                    let config = ConfigManager.shared
                    let screenHeight = self.dragScreen?.visibleFrame.height ?? config.defaultFallbackScreenHeight
                    let maxDragDistance = max(config.minDragDistance, screenHeight * config.screenHeightDragRatio)
                    let clampedDy = min(maxDragDistance, dy)
                    let progress = clampedDy / maxDragDistance

                    let available = self.chunkStore.totalRecordedDuration + self.recorder.unsavedDuration
                    let finalSeconds = MenuBarManager.snappedOffset(progress: progress, available: available)
                    self.selectedOffsetSeconds = finalSeconds

                    let clampedY = self.dragStartLocation.y - clampedDy
                    let clampedMouseLocation = NSPoint(x: mouseLocation.x, y: clampedY)

                    OverlayHUDWindow.shared.show(
                        at: clampedMouseLocation,
                        startLocation: self.dragStartLocation,
                        offsetSeconds: finalSeconds,
                        startDate: self.footageStartDate(offset: finalSeconds, endDate: self.dragEndDate),
                        screen: self.dragScreen
                    )
                    self.isHUDVisible = true
                } else {
                    self.selectedOffsetSeconds = 0
                    self.isHUDVisible = false
                    OverlayHUDWindow.shared.hideHUD()
                }
                return true
            }

            if type == .leftMouseUp {
                self.isDragging = false
                OverlayHUDWindow.shared.hideHUD()

                let offset = self.selectedOffsetSeconds
                if offset >= ConfigManager.shared.minExportOffsetSeconds {
                    Log.export.info("Drag released; exporting \(offset)s")
                    self.triggerExport(offsetSeconds: offset, endDate: self.dragEndDate)
                } else if self.isHUDVisible {
                    notifier.inform(title: "Nothing to export yet", message: "Recall has not recorded anything yet. Try again in a few seconds.")
                }
                self.isHUDVisible = false
                return true
            }
        }

        return false
    }

    /// Where `offset` seconds of footage ending at `endDate` begin on the wall clock. The chunk in
    /// progress is continuous footage; older footage comes from the chunk index, which skips pauses.
    func footageStartDate(offset: TimeInterval, endDate: Date) -> Date {
        let unsavedStart = Date().addingTimeInterval(-recorder.unsavedDuration)
        let unsavedBeforeEnd = max(0, endDate.timeIntervalSince(unsavedStart))
        guard offset > unsavedBeforeEnd else {
            return endDate.addingTimeInterval(-offset)
        }
        let savedEnd = min(endDate, unsavedStart)
        return chunkStore.footageStartDate(footageSeconds: offset - unsavedBeforeEnd, endingAt: savedEnd)
            ?? endDate.addingTimeInterval(-offset)
    }

    private func setupDragGestureTracking() {
        guard let button = statusItem?.button else { return }

        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }

            let mouseLocation = NSEvent.mouseLocation
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero

            let intercepted = self.handleMouseEvent(type: event.type, mouseLocation: mouseLocation, buttonFrame: buttonFrame)
            return intercepted ? nil : event
        }
    }

    // MARK: - Menu

    func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let statusLine = NSMenuItem(title: MenuBarManager.statusDescription(for: recorder.state), action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        if recorder.state == .error(RecorderEngine.permissionMessage) {
            let permissionItem = NSMenuItem(title: "Open Screen Recording Settings…", action: #selector(openScreenRecordingSettings), keyEquivalent: "")
            permissionItem.target = self
            menu.addItem(permissionItem)
        }

        let pauseItem = NSMenuItem(
            title: recorder.isPausedByUser ? "Resume Recording" : "Pause Recording",
            action: #selector(togglePause),
            keyEquivalent: "p"
        )
        pauseItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Recall", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    func showContextMenu(button overrideButton: NSButton? = nil) {
        guard let button = overrideButton ?? statusItem?.button, button.window != nil else { return }
        buildContextMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    // MARK: - Export

    func triggerExport(offsetSeconds: TimeInterval, endDate: Date = Date(), overrideButton: NSButton? = nil) {
        guard !isExporting else {
            Log.export.notice("Export already in progress; ignoring request")
            notifier.inform(title: "Export in progress", message: "Wait for the current export to finish.")
            return
        }
        isExporting = true
        let button = overrideButton ?? statusItem?.button
        button?.contentTintColor = .systemRed

        let request = ExportRequest(footageSeconds: offsetSeconds, endDate: endDate)
        // Finalize the chunk in progress so the clip can include the last seconds before the gesture.
        recorder.flushCurrentChunk { [weak self] in
            guard let self = self else { return }
            self.chunkStore.exportClip(request) { result in
                self.isExporting = false
                button?.contentTintColor = nil
                self.updateStatusAppearance()

                switch result {
                case .success(let url):
                    self.fileRevealer(url)
                    self.notifier.exportSucceeded(url)
                case .failure(let error):
                    self.notifier.exportFailed(error.localizedDescription)
                }
            }
        }
    }
}
