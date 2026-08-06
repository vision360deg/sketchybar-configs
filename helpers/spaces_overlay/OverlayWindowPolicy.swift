import AppKit

enum OverlayWindowPolicy {
    static let level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .transient,
        .ignoresCycle,
        .fullScreenAuxiliary,
    ]
}
