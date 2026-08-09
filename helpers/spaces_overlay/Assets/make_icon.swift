import AppKit
import Foundation

let source = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]

guard let image = NSImage(contentsOfFile: source) else {
    fatalError("Unable to load source image")
}

let size = image.size
let pixelsWide = max(1, Int(size.width.rounded()))
let pixelsHigh = max(1, Int(size.height.rounded()))
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                    pixelsWide: pixelsWide,
                                    pixelsHigh: pixelsHigh,
                                    bitsPerSample: 8,
                                    samplesPerPixel: 4,
                                    hasAlpha: true,
                                    isPlanar: false,
                                    colorSpaceName: .deviceRGB,
                                    bitmapFormat: [],
                                    bytesPerRow: 0,
                                    bitsPerPixel: 0) else {
    fatalError("Unable to create bitmap")
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create graphics context")
}
NSGraphicsContext.current = context
image.draw(in: NSRect(origin: .zero, size: size),
           from: .zero,
           operation: .copy,
           fraction: 1)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode PNG")
}
try data.write(to: URL(fileURLWithPath: destination))
