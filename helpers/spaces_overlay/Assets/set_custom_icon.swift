import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: set_custom_icon.swift <source-app> <target-file>\n", stderr)
    exit(2)
}

let sourcePath = CommandLine.arguments[1]
let targetPath = CommandLine.arguments[2]
guard FileManager.default.fileExists(atPath: sourcePath),
      FileManager.default.fileExists(atPath: targetPath) else {
    fputs("set_custom_icon: source or target does not exist\n", stderr)
    exit(1)
}

let iconPath = URL(fileURLWithPath: sourcePath)
    .appendingPathComponent("Contents")
    .appendingPathComponent("Resources")
    .appendingPathComponent("SpacesOverlay.icns")
    .path
guard let icon = NSImage(contentsOfFile: iconPath) else {
    fputs("set_custom_icon: source app has no readable SpacesOverlay.icns\n", stderr)
    exit(1)
}

guard NSWorkspace.shared.setIcon(icon, forFile: targetPath, options: []) else {
    fputs("set_custom_icon: failed to apply icon\n", stderr)
    exit(1)
}
