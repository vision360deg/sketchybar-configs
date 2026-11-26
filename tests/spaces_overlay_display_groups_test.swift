import CoreGraphics
import Foundation

@main
enum SpacesOverlayDisplayGroupsTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        // Safari = 536166617269, Terminal = 5465726d696e616c
        let snapshot = OverlaySnapshot(environment: [
            "REVISION": "7",
            "VISIBLE": "true",
            "REARRANGE_SPACES": "false",
            "DISPLAYS": "1|10.5|20.0|420.0|26.0|0|1,3|536166617269,5465726d696e616c|101:102,|101,;"
                + "2|-500.0|20.0|400.0|26.0|3|3|5465726d696e616c|201|201",
        ])
        expect(snapshot != nil, "DISPLAYS payload builds a snapshot without legacy geometry")

        let displays = snapshot?.displays ?? []
        expect(displays.count == 2, "one group per display")

        expect(displays[0].displayIndex == 1, "first group carries its display index")
        expect(displays[0].frame == CGRect(x: 10.5, y: 20.0, width: 420.0, height: 26.0),
               "first group carries its quartz frame")
        expect(displays[0].selected == 0, "display without the focused space has no selection")
        expect(displays[0].spaces == [1, 3], "first group keeps real space indices")
        expect(displays[0].apps == [["Safari"], ["Terminal"]],
               "first group decodes only its own labels")
        expect(displays[0].windowIDs == [[101, 102], []],
               "first group decodes only its own window IDs")
        expect(displays[0].foregroundWindowIDs == [101, nil],
               "first group decodes only its own foreground IDs")

        expect(displays[1].displayIndex == 2, "second group carries its display index")
        expect(displays[1].spaces == [3], "second group keeps real space indices")
        expect(displays[1].selected == 3, "focused space selects on its own display")
        expect(displays[1].windowIDs == [[201]], "second group decodes its own window IDs")
        expect(displays[1].foregroundWindowIDs == [201],
               "second group decodes its own foreground IDs")

        expect(displays[1].position(of: 3) == 0, "group resolves its own space positions")
        expect(displays[1].position(of: 1) == nil, "group rejects foreign spaces")

        let legacyAccessors = snapshot!
        expect(legacyAccessors.frame == displays[0].frame,
               "legacy frame accessor mirrors the first display")
        expect(legacyAccessors.selected == displays[0].selected,
               "legacy selected accessor mirrors the first display")
        expect(legacyAccessors.apps == displays[0].apps,
               "legacy apps accessor mirrors the first display")
        expect(snapshot?.group(forDisplay: 2)?.displayIndex == 2,
               "group lookup by display index")

        let emptyDisplay = OverlaySnapshot(environment: [
            "REVISION": "8",
            "DISPLAYS": "1|0|0|420|26|0|||,|",
        ])
        expect(emptyDisplay?.displays.count == 1, "display without spaces still forms a group")
        expect(emptyDisplay?.displays[0].spaces == [], "empty group has no spaces")

        let malformedFallsBackToLegacy = OverlaySnapshot(environment: [
            "REVISION": "9",
            "DISPLAYS": "1|2|3",
            "X": "0", "Y": "0", "WIDTH": "420", "HEIGHT": "26",
            "SELECTED": "1",
        ])
        expect(malformedFallsBackToLegacy?.displays.count == 1,
               "malformed DISPLAYS falls back to the legacy payload")
        expect(malformedFallsBackToLegacy?.displays[0].displayIndex == 0,
               "legacy fallback uses the synthetic display index")
        expect(malformedFallsBackToLegacy?.apps == [],
               "legacy fallback keeps empty labels")

        let mismatchedLabels = OverlaySnapshot(environment: [
            "REVISION": "10",
            "DISPLAYS": "1|0|0|420|26|0|1,2|536166617269|101|101",
        ])
        expect(mismatchedLabels == nil, "label/space count mismatch rejects the payload")



        print("spaces overlay display group tests passed")
    }
}
