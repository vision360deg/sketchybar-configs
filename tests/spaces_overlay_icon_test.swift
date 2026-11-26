import AppKit
import Foundation

@main
enum SpacesOverlayIconTests {
    static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }

    static func rasterize(_ image: NSImage) -> Data {
        let pixelsWide = 64
        let pixelsHigh = 64
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fail("could not create icon comparison bitmap")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let bitmapData = bitmap.bitmapData else {
            fail("could not read icon comparison bitmap")
        }
        return Data(bytes: bitmapData, count: bitmap.bytesPerRow * pixelsHigh)
    }

    static func main() {
        guard CommandLine.arguments.count == 4 else {
            fail("usage: spaces_overlay_icon_test <app> <binary> <icns>")
        }

        let appPath = CommandLine.arguments[1]
        let binaryPath = CommandLine.arguments[2]
        let iconPath = CommandLine.arguments[3]
        guard FileManager.default.fileExists(atPath: appPath),
              FileManager.default.fileExists(atPath: binaryPath),
              let expectedIcon = NSImage(contentsOfFile: iconPath) else {
            fail("icon test artifacts are missing")
        }

        // The system icon cache can keep a stale icon for the installed path:
        // on macOS 27 it kept a generic one after the build applied the custom
        // icon. A fresh copy carries the same Finder info and resource fork, so
        // it shows the artwork the build attached.
        let copyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: copyDirectory) }
        let copyPath = copyDirectory.appendingPathComponent("SpacesOverlay").path
        guard (try? FileManager.default.createDirectory(at: copyDirectory, withIntermediateDirectories: true)) != nil,
              copyfile(binaryPath, copyPath, nil, copyfile_flags_t(COPYFILE_ALL)) == 0 else {
            fail("could not copy the executable with its icon")
        }

        let actualIcon = NSWorkspace.shared.icon(forFile: copyPath)
        let expectedPixels = rasterize(expectedIcon)
        let actualPixels = rasterize(actualIcon)
        let differingBytes = zip(expectedPixels, actualPixels)
            .reduce(into: 0) { count, pair in
                if pair.0 != pair.1 { count += 1 }
            }
        let differenceRatio = Double(differingBytes) / Double(expectedPixels.count)
        guard differenceRatio < 0.10 else {
            fail("executable icon differs from SpacesOverlay.icns by \(differenceRatio)")
        }

        print("spaces overlay icon artwork test passed")
    }
}
