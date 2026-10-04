import AppKit
import SwiftUI

final class MenuBarManager: NSObject {
    static let shared = MenuBarManager()

    private let recorder: ScreenCapture
    private let chunkStore: ChunkStore

    private var statusItem: NSStatusItem?
    private var isDragging = false
    private var dragStartLocation: NSPoint = .zero
    private var selectedOffsetSeconds: TimeInterval = 0


    private let alertPresenter: AlertPresenter

    init(
        recorder: ScreenCapture = RecorderEngine.shared,
        chunkStore: ChunkStore = ChunkManager.shared,
        alertPresenter: AlertPresenter = DefaultAlertPresenter()
    ) {
        self.recorder = recorder
        self.chunkStore = chunkStore
        self.alertPresenter = alertPresenter
        super.init()
    }

    func setupMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.image = createMenuBarIcon()
        }

        setupDragGestureTracking()
    }

    private func createMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let icon = NSImage(size: size, flipped: false) { rect in
            guard let cgContext = NSGraphicsContext.current?.cgContext else { return false }

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

            return true
        }
        icon.isTemplate = true
        return icon
    }


    @objc func openSettings() {
        SettingsWindowController.shared.showWindow()
    }

    @objc func purgeRecordings() {
        if alertPresenter.confirmPurgeRecordings() {
            chunkStore.purgeAllChunks()
        }
    }

    var appTerminator: () -> Void = { NSApplication.shared.terminate(nil) }

    @objc func quitApp() {
        recorder.stopStream()
        appTerminator()
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
                self.dragStartLocation = NSPoint(x: buttonFrame.midX, y: buttonFrame.minY)
                self.selectedOffsetSeconds = 0
                return true // Intercepted
            }
        }

        if self.isDragging {
            if type == .leftMouseDragged {
                let dy = self.dragStartLocation.y - mouseLocation.y
                if dy > 0 {
                    let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
                    let maxDragDistance = max(200.0, screenHeight * 0.5)
                    let clampedDy = min(maxDragDistance, dy)
                    let progress = min(1.0, max(0.0, clampedDy / maxDragDistance))

                    let maxDuration = self.chunkStore.totalRecordedDuration
                    let rawSeconds = progress * maxDuration
                    let steppedSeconds = max(60.0, round(rawSeconds / 60.0) * 60.0)
                    let finalSeconds = min(maxDuration, steppedSeconds)
                    self.selectedOffsetSeconds = finalSeconds

                    let clampedY = self.dragStartLocation.y - clampedDy
                    let clampedMouseLocation = NSPoint(x: mouseLocation.x, y: clampedY)

                    OverlayHUDWindow.shared.show(at: clampedMouseLocation, startLocation: self.dragStartLocation, offsetSeconds: finalSeconds)
                } else {
                    self.selectedOffsetSeconds = 0
                    OverlayHUDWindow.shared.hideHUD()
                }
                return true
            }

            if type == .leftMouseUp {
                self.isDragging = false
                OverlayHUDWindow.shared.hideHUD()

                let offset = self.selectedOffsetSeconds
                if offset >= 1.0 {
                    print("[MenuBarManager] Mouse released! Exporting snippet for offset: \(offset)s")
                    self.triggerExport(offsetSeconds: offset)
                }
                return true
            }
        }

        return false
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

    func showContextMenu(button overrideButton: NSButton? = nil) {
        guard let button = overrideButton ?? statusItem?.button, button.window != nil else { return }
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Recall", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    func triggerExport(offsetSeconds: TimeInterval, overrideButton: NSButton? = nil) {
        let button = overrideButton ?? statusItem?.button
        if let button = button {
            button.contentTintColor = .systemRed
        }

        chunkStore.exportClip(offsetSeconds: offsetSeconds) { exportedURL in
            if let url = exportedURL {
                NSSound.beep()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            button?.contentTintColor = nil
        }
    }
}
