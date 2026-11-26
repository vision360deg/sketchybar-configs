import AppKit
import Foundation

@main
enum SpacesOverlayNumberingTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func secondaryGroup(selected: Int) -> OverlayDisplayGroup {
        OverlayDisplayGroup(
            displayIndex: 2,
            frame: CGRect(x: -500, y: 20, width: 420, height: 26),
            selected: selected,
            spaces: [4, 5, 6],
            apps: [["Mail", "Safari", "Terminal"], [], ["Music"]],
            windowIDs: [[], [], []],
            foregroundWindowIDs: [nil, nil, nil]
        )
    }

    static func main() {
        let view = SpacesView(frame: CGRect(x: 0, y: 0, width: 150, height: 26))
        view.apply(group: secondaryGroup(selected: 0),
                   visible: true,
                   rearrangeSpaces: false)

        let layouts = view.itemLayouts()
        expect(layouts.count == 3, "secondary display lays out its own card count")
        expect(layouts.map(\.number) == ["1", "2", "3"],
               "cards restart numbering within each display")
        expect(layouts.map(\.space) == [4, 5, 6],
               "cards keep their real yabai space indices for commands")

        var hovered = [Int?]()
        view.onHoverChanged = { (space: Int?, _: CGRect?) in
            hovered.append(space)
        }

        view.revalidateHover(at: CGPoint(x: 10, y: 13))
        expect(hovered.last == 4, "row starts at its first card without focus")

        view.apply(group: secondaryGroup(selected: 6),
                   visible: true,
                   rearrangeSpaces: false)
        view.revalidateHover(at: CGPoint(x: 100, y: 13))
        expect(hovered.last == 6, "selection scrolls the focused card into view")

        view.apply(group: secondaryGroup(selected: 0),
                   visible: true,
                   rearrangeSpaces: false)
        view.revalidateHover(at: CGPoint(x: 115, y: 13))
        expect(hovered.last == 5, "losing focus resets the row scroll")
        view.revalidateHover(at: CGPoint(x: 10, y: 13))
        expect(hovered.last == 4, "row starts from its first card after the reset")

        let legacy = SpacesView(frame: CGRect(x: 0, y: 0, width: 300, height: 26))
        let legacySnapshot = OverlaySnapshot(environment: [
            "REVISION": "1",
            "VISIBLE": "true",
            "X": "0", "Y": "0", "WIDTH": "300", "HEIGHT": "26",
            "SELECTED": "2",
            "LABELS": "536166617269,5465726d696e616c,4d75736963",
        ])!
        legacy.apply(legacySnapshot)
        expect(legacy.itemLayouts().map(\.number) == ["1", "2", "3"],
               "legacy single-display layout keeps positional numbering")
        expect(legacy.itemLayouts().map(\.space) == [1, 2, 3],
               "legacy layout keeps one-based space indices")

        print("spaces overlay numbering tests passed")
    }
}
