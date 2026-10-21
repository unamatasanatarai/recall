import AppKit
import SwiftUI

struct OverlayHUDWindowTests {
    static func testHUDWindowProperties() throws {
        let window = OverlayHUDWindow.shared
        try check(!window.isOpaque, "Expected window.isOpaque == false")
        try check(window.backgroundColor == .clear, "Expected clear background color")
        try check(window.level == .popUpMenu, "Expected popUpMenu window level")
        try check(window.ignoresMouseEvents, "Expected ignoresMouseEvents == true")
        try check(window.sharingType == .none, "The HUD should be kept out of screen captures")
    }

    static func testLayoutHugsBeamInsteadOfScreen() throws {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let layout = OverlayHUDWindow.layout(start: NSPoint(x: 700, y: 880), current: NSPoint(x: 700, y: 500), screenFrame: screen)

        try check(layout.frame.width < screen.width / 2, "The window should not span the screen: \(layout.frame)")
        try check(screen.contains(layout.frame), "The window must stay on screen: \(layout.frame)")
        // Top-left view coordinates: the start sits above the current point.
        try check(layout.startPoint == CGPoint(x: 700 - layout.frame.minX, y: layout.frame.maxY - 880), "Unexpected start point \(layout.startPoint)")
        try check(layout.currentPoint == CGPoint(x: 700 - layout.frame.minX, y: layout.frame.maxY - 500), "Unexpected current point \(layout.currentPoint)")
        try check(layout.badgeCenter.x > layout.currentPoint.x, "The badge goes to the right of the knob when there is room")
    }

    static func testBadgeFlipsLeftNearRightEdge() throws {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let layout = OverlayHUDWindow.layout(start: NSPoint(x: 1400, y: 880), current: NSPoint(x: 1400, y: 600), screenFrame: screen)

        try check(layout.badgeCenter.x < layout.currentPoint.x, "Near the right edge the badge should sit left of the knob")
        let badgeRightEdge = layout.frame.minX + layout.badgeCenter.x + OverlayHUDWindow.badgeSize.width / 2
        try check(badgeRightEdge <= screen.maxX, "The badge must not be clipped: right edge \(badgeRightEdge)")
    }

    static func testLayoutOnSecondaryScreen() throws {
        // A display to the right of the main one, with its own menu bar.
        let screen = NSRect(x: 1440, y: -180, width: 1920, height: 1080)
        let start = NSPoint(x: 2600, y: 878)
        let current = NSPoint(x: 2600, y: 400)
        let layout = OverlayHUDWindow.layout(start: start, current: current, screenFrame: screen)

        try check(screen.contains(layout.frame), "The window must be on the screen the drag started on: \(layout.frame)")
        try check(layout.startPoint == CGPoint(x: start.x - layout.frame.minX, y: layout.frame.maxY - start.y), "Screen origin must be accounted for: \(layout.startPoint)")
    }

    static func testTaperedBeamPathGeneration() throws {
        let shape = TaperedBeamShape(
            startPoint: CGPoint(x: 100, y: 0),
            endPoint: CGPoint(x: 100, y: 100),
            startWidth: 10,
            endWidth: 20
        )
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 200, height: 200))
        try check(!path.isEmpty, "Expected non-empty path for beam shape")
    }

    static func testViewModelReactivity() throws {
        let vm = HUDViewModel()
        vm.startPoint = CGPoint(x: 10, y: 20)
        vm.currentPoint = CGPoint(x: 10, y: 100)
        vm.offsetSeconds = 60
        vm.label = "label"

        try check(vm.startPoint.x == 10 && vm.currentPoint.y == 100 && vm.offsetSeconds == 60 && vm.label == "label", "ViewModel property updates failed")
    }

    static func testShowAndHide() throws {
        let window = OverlayHUDWindow.shared
        window.show(at: NSPoint(x: 300, y: 400), startLocation: NSPoint(x: 300, y: 880), offsetSeconds: 30)
        if NSScreen.main != nil {
            try check(window.isVisible, "Expected the HUD to be visible")
            try check(window.frame.height < 900, "The HUD should be sized to the beam")
        }
        window.hideHUD()
        try check(!window.isVisible, "Expected window.isVisible = false after hideHUD()")
    }
}
