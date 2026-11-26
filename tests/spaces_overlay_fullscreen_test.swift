import AppKit
import Foundation

@main
enum SpacesOverlayFullscreenTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        expect(OverlayWindowPolicy.collectionBehavior.contains(.fullScreenNone),
               "overlay opts out of fullscreen Spaces")
        expect(!OverlayWindowPolicy.collectionBehavior.contains(.fullScreenAuxiliary),
               "overlay does not join fullscreen Spaces as an auxiliary window")
        testHoverLifecycle()
        print("spaces overlay fullscreen tests passed")
    }

    static func makeSnapshot() -> OverlaySnapshot {
        OverlaySnapshot(environment: [
            "REVISION": "1",
            "VISIBLE": "true",
            "X": "0",
            "Y": "0",
            "WIDTH": "200",
            "HEIGHT": "26",
            "SELECTED": "1",
            "LABELS": "536166617269",
        ])!
    }

    static func testHoverLifecycle() {
        let view = SpacesView(frame: CGRect(x: 0, y: 0, width: 200, height: 26))
        view.apply(makeSnapshot())

        var hoverEvents = [Int?]()
        view.onHoverChanged = { (space: Int?, _: CGRect?) in
            hoverEvents.append(space)
        }

        view.revalidateHover(at: CGPoint(x: 25, y: 13))
        expect(hoverEvents.last == 1,
               "restoration publishes the card under the pointer")

        view.resetHover()
        expect(hoverEvents.count > 1 && hoverEvents[hoverEvents.count - 1] == nil,
               "fullscreen reset clears the active card")

        let eventCount = hoverEvents.count
        view.revalidateHover(at: CGPoint(x: 150, y: 13))
        expect(hoverEvents.count == eventCount,
               "restoration outside a card does not publish a hover")
    }
}
