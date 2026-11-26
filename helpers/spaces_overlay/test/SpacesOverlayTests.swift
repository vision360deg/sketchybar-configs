import AppKit
import Foundation

@main
enum SpacesOverlayTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        let payload = Data("REVISION\0".utf8)
            + Data("7\0".utf8)
            + Data("VISIBLE\0true\0".utf8)
            + Data("X\010.5\0Y\020.0\0WIDTH\0420.0\0HEIGHT\026.0\0".utf8)
            + Data("SELECTED\03\0LABELS\041,4262,,e29883\0\0".utf8)

        let environment = MachEnvironment.parse(payload)
        expect(environment["REVISION"] == "7", "parses revision")
        expect(environment["VISIBLE"] == "true", "parses visibility")

        let snapshot = OverlaySnapshot(environment: [
            "REVISION": "7",
            "VISIBLE": "true",
            "X": "10.5",
            "Y": "20.0",
            "WIDTH": "420.0",
            "HEIGHT": "26.0",
            "SELECTED": "3",
            "LABELS": "5361666172691f5465726d696e616c,",
            "FOREGROUND_IDS": "101,201,",
        ])
        expect(snapshot != nil, "builds valid snapshot")
        expect(snapshot?.revision == 7, "snapshot revision")
        expect(snapshot?.selected == 3, "snapshot selection")
        expect(snapshot?.apps == [["Safari", "Terminal"], []],
               "decodes per-space app names and empty spaces")
        expect(snapshot?.frame.width == 420, "snapshot width")
        expect(snapshot?.foregroundWindowIDs == [101, 201],
               "decodes per-space foreground window IDs")

        let missingApps = OverlaySnapshot(environment: [
            "REVISION": "8",
            "X": "0", "Y": "0", "WIDTH": "420", "HEIGHT": "26",
            "SELECTED": "1",
        ])
        expect(missingApps?.apps == [], "missing app payload is empty")

        let parsedIDs = OverlaySnapshot.parseWindowIDs("101:102,,201", spaceCount: 3)
        expect(parsedIDs == [[101, 102], [], [201]], "decodes per-space window IDs")
        expect(OverlaySnapshot.parseWindowIDs(nil, spaceCount: 3) == [[], [], []],
               "missing window IDs produce empty groups")
        expect(OverlaySnapshot.parseWindowIDs("101:0:-2:invalid,,0:201", spaceCount: 3)
               == [[101], [], [201]],
               "ignores invalid and non-positive window IDs")
        expect(OverlaySnapshot.parseWindowIDs("101", spaceCount: 3) == [[101], [], []],
               "pads truncated window ID groups")
        expect(OverlaySnapshot.parseWindowIDs("101,201,301,401", spaceCount: 2) == [[101], [201]],
               "truncates overlong window ID groups")
        expect(OverlaySnapshot.parseForegroundWindowIDs("101,,301", spaceCount: 3)
               == [101, nil, 301],
               "decodes sparse foreground window IDs")

        expect(SpaceLayoutModel.cardWidth(numberWidth: 10, appCount: 0) == 50,
               "empty card keeps minimum width")
        expect(SpaceLayoutModel.cardWidth(numberWidth: 10, appCount: 2) == 88,
               "two icons use fixed icon spacing and padding")
        expect(SpaceLayoutModel.cardCornerRadius == 6,
               "overlay shell matches card corner radius")
        expect(SpaceLayoutModel.cardStrokeWidth == 1,
               "overlay shell matches card border width")

        expect(ScrollModel.clampOffset(-10, contentWidth: 800, viewportWidth: 420) == 0,
               "clamps negative offset")
        expect(ScrollModel.clampOffset(150, contentWidth: 800, viewportWidth: 420) == 150,
               "keeps interior offset")
        expect(ScrollModel.clampOffset(900, contentWidth: 800, viewportWidth: 420) == 380,
               "clamps maximum offset")
        expect(ScrollModel.clampOffset(20, contentWidth: 300, viewportWidth: 420) == 0,
               "zero offset when content fits")

        expect(OverlayWindowPolicy.level.rawValue > NSWindow.Level.floating.rawValue,
               "overlay stays above SketchyBar's floating level")
        expect(OverlayWindowPolicy.level.rawValue < NSWindow.Level.statusBar.rawValue,
               "overlay stays below the macOS menu bar")

        expect(OverlayWindowPolicy.collectionBehavior.contains(.transient),
               "overlay hides in Mission Control")
        expect(!OverlayWindowPolicy.collectionBehavior.contains(.stationary),
               "overlay does not remain stationary in Mission Control")

        WindowCarouselTests.run()

        print("spaces overlay tests passed")
    }
}
