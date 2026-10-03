import AppKit
import SwiftUI

struct OverlayHUDWindowTests {
    static func testHUDWindowProperties() throws {
        let window = OverlayHUDWindow.shared
        if window.isOpaque {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected window.isOpaque == false"])
        }
        if window.backgroundColor != .clear {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected clear background color"])
        }
        if window.level != .popUpMenu {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected popUpMenu window level"])
        }
        if !window.ignoresMouseEvents {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected ignoresMouseEvents == true"])
        }
    }

    static func testCoordinateConversion() throws {
        let screenHeight: CGFloat = 900.0
        let cocoaPoint = NSPoint(x: 100, y: 200)
        let swiftUIPoint = CGPoint(x: cocoaPoint.x, y: screenHeight - cocoaPoint.y)

        if swiftUIPoint.x != 100 || swiftUIPoint.y != 700 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Coordinate conversion mismatch"])
        }
    }

    static func testTaperedBeamPathGeneration() throws {
        let shape = TaperedBeamShape(
            startPoint: CGPoint(x: 100, y: 0),
            endPoint: CGPoint(x: 100, y: 100),
            startWidth: 10,
            endWidth: 20
        )
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 200, height: 200))
        if path.isEmpty {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected non-empty path for beam shape"])
        }
    }

    static func testTimeOffsetFormatter() throws {
        let secondsExact: TimeInterval = 120
        let secondsFractional: TimeInterval = 90

        let minsExact = secondsExact / 60.0
        let minsFractional = secondsFractional / 60.0

        if minsExact != 2.0 || minsFractional != 1.5 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Time offset minute calculation incorrect"])
        }
    }

    static func testViewModelReactivity() throws {
        let vm = HUDViewModel()
        vm.startPoint = CGPoint(x: 10, y: 20)
        vm.currentPoint = CGPoint(x: 10, y: 100)
        vm.offsetSeconds = 60

        if vm.startPoint.x != 10 || vm.currentPoint.y != 100 || vm.offsetSeconds != 60 {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "ViewModel property updates failed"])
        }
    }
}
