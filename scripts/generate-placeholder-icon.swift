import AppKit

// Create a 1024x1024 bitmap directly
let bitmapRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: [],
    bytesPerRow: 0,
    bitsPerPixel: 32
)!

let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep)
NSGraphicsContext.current = ctx

// Draw light background
NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.94, alpha: 1).setFill()
NSRect(origin: .zero, size: NSSize(width: 1024, height: 1024)).fill()

// Draw dorsal fin
NSColor(calibratedRed: 0.04, green: 0.12, blue: 0.18, alpha: 1).setFill()
let path = NSBezierPath()
let s: CGFloat = 1024.0 / 28.0
path.move(to: CGPoint(x: 10 * s, y: 1024 - 24 * s))
path.line(to: CGPoint(x: 10 * s, y: 1024 - 14 * s))
path.curve(
    to: CGPoint(x: 20 * s, y: 1024 - 24 * s),
    controlPoint1: CGPoint(x: 14 * s, y: 1024 - 8 * s),
    controlPoint2: CGPoint(x: 14 * s, y: 1024 - 8 * s)
)
path.close()
path.fill()

NSGraphicsContext.current = nil

// Write PNG
let png = bitmapRep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: "App/Fluke/Assets.xcassets/AppIcon.appiconset/icon-1024.png"))
print("wrote icon-1024.png")
