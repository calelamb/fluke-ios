import AppKit

let iconSize = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
let outputURL = URL(
    fileURLWithPath: "App/Fluke/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
)

guard let context = CGContext(
    data: nil,
    width: iconSize,
    height: iconSize,
    bitsPerComponent: 8,
    bytesPerRow: iconSize * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fatalError("Unable to allocate opaque app icon context")
}

NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.94, alpha: 1).setFill()
NSRect(origin: .zero, size: NSSize(width: iconSize, height: iconSize)).fill()

NSColor(calibratedRed: 0.04, green: 0.12, blue: 0.18, alpha: 1).setFill()
let path = NSBezierPath()
let scale = CGFloat(iconSize) / 28.0
path.move(to: CGPoint(x: 10 * scale, y: CGFloat(iconSize) - 24 * scale))
path.line(to: CGPoint(x: 10 * scale, y: CGFloat(iconSize) - 14 * scale))
path.curve(
    to: CGPoint(x: 20 * scale, y: CGFloat(iconSize) - 24 * scale),
    controlPoint1: CGPoint(x: 14 * scale, y: CGFloat(iconSize) - 8 * scale),
    controlPoint2: CGPoint(x: 14 * scale, y: CGFloat(iconSize) - 8 * scale)
)
path.close()
path.fill()

NSGraphicsContext.current = nil

guard let image = context.makeImage() else {
    fatalError("Unable to create app icon image")
}
let bitmapRep = NSBitmapImageRep(cgImage: image)
guard let png = bitmapRep.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode app icon PNG")
}
try png.write(to: outputURL)
print("wrote opaque icon-1024.png")
