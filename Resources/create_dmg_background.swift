import AppKit
import CoreGraphics

let width = 740 // Covers full Finder window width
let height = 420 // Covers full Finder window height

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    print("Failed to create graphics context")
    exit(1)
}

let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.current = nsContext

let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))

// 1. Background Gradient (#0F172A to #1E293B)
let topColor = NSColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
let bottomColor = NSColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 1.0)
let bgGradient = NSGradient(starting: topColor, ending: bottomColor)!
bgGradient.draw(in: bounds, angle: 90)

// 2. Ambient Radial Glow in Center (y = 230 in CGContext)
let glowCenter = CGPoint(x: CGFloat(width) / 2.0, y: 230.0)
let glowColorInner = NSColor(red: 0.05, green: 0.65, blue: 0.95, alpha: 0.28)
let glowColorOuter = NSColor(red: 0.05, green: 0.65, blue: 0.95, alpha: 0.0)
let radialGradient = NSGradient(starting: glowColorInner, ending: glowColorOuter)!
radialGradient.draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: 240, options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])

// 3. Icon Seats (Translucent Rounded Rectangles)
// Finder Icon Left Center: {200, 190} -> 190 pt from top -> 230 px from bottom in 420 px height
// Finder Icon Right Center: {540, 190} -> 190 pt from top -> 230 px from bottom in 420 px height
let leftSeatRect = CGRect(x: 200 - 60, y: 230 - 60, width: 120, height: 120)
let rightSeatRect = CGRect(x: 540 - 60, y: 230 - 60, width: 120, height: 120)

func drawSeat(in rect: CGRect) {
    let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
    NSColor.white.withAlphaComponent(0.04).setFill()
    path.fill()
    
    NSColor.white.withAlphaComponent(0.14).setStroke()
    path.lineWidth = 1.5
    path.stroke()
}

drawSeat(in: leftSeatRect)
drawSeat(in: rightSeatRect)

// 4. Connecting Arrow
let arrowY: CGFloat = 230.0
let arrowStart: CGFloat = 280.0
let arrowEnd: CGFloat = 460.0
let shaftThickness: CGFloat = 7.0
let headSize: CGFloat = 18.0

let arrowPath = NSBezierPath()
arrowPath.move(to: CGPoint(x: arrowStart, y: arrowY - shaftThickness / 2))
arrowPath.line(to: CGPoint(x: arrowEnd - headSize + 2, y: arrowY - shaftThickness / 2))
arrowPath.line(to: CGPoint(x: arrowEnd - headSize + 2, y: arrowY - headSize / 1.2))
arrowPath.line(to: CGPoint(x: arrowEnd, y: arrowY))
arrowPath.line(to: CGPoint(x: arrowEnd - headSize + 2, y: arrowY + headSize / 1.2))
arrowPath.line(to: CGPoint(x: arrowEnd - headSize + 2, y: arrowY + shaftThickness / 2))
arrowPath.line(to: CGPoint(x: arrowStart, y: arrowY + shaftThickness / 2))
arrowPath.close()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor(red: 0.05, green: 0.65, blue: 0.95, alpha: 0.6).cgColor)

let arrowGradient = NSGradient(
    starting: NSColor(red: 0.2, green: 0.85, blue: 1.0, alpha: 0.95),
    ending: NSColor(red: 0.05, green: 0.5, blue: 1.0, alpha: 0.95)
)!
arrowGradient.draw(in: arrowPath, angle: 0)
context.restoreGState()

// 5. Title "drag to recall!" at top (y = 335 in CGContext)
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center

let titleFont = NSFont.systemFont(ofSize: 28, weight: .black)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraphStyle,
    .kern: 0.5
]

let titleString = NSAttributedString(string: "drag to recall!", attributes: titleAttrs)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -1), blur: 6, color: NSColor(red: 0.05, green: 0.65, blue: 0.95, alpha: 0.8).cgColor)
let titleRect = CGRect(x: 0, y: 335, width: CGFloat(width), height: 40)
titleString.draw(in: titleRect)
context.restoreGState()

// 6. Subtitle at bottom (y = 45 in CGContext)
let subFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: NSColor(red: 0.7, green: 0.82, blue: 0.95, alpha: 0.85),
    .paragraphStyle: paragraphStyle
]

let subString = NSAttributedString(string: "Drag Recall to your Applications folder to install", attributes: subAttrs)
let subRect = CGRect(x: 0, y: 45, width: CGFloat(width), height: 30)
subString.draw(in: subRect)

// Output PNG
guard let cgImage = context.makeImage() else {
    print("Failed to make CGImage")
    exit(1)
}

let imageRep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = imageRep.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG data")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/dmg_background.png"
let outputURL = URL(fileURLWithPath: outputPath)
try pngData.write(to: outputURL)
print("Successfully generated 740x420 background image at: \(outputPath)")
