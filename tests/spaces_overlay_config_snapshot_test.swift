import CoreGraphics
import Foundation

@main
enum SpacesOverlayConfigSnapshotTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        let disabled = OverlaySnapshot(environment: [
            "REVISION": "1",
            "X": "0", "Y": "0", "WIDTH": "420", "HEIGHT": "26",
            "SELECTED": "1",
            "REARRANGE_SPACES": "false",
        ])
        expect(disabled?.rearrangeSpaces == false,
               "false config disables native rearranging")

        let enabled = OverlaySnapshot(environment: [
            "REVISION": "2",
            "X": "0", "Y": "0", "WIDTH": "420", "HEIGHT": "26",
            "SELECTED": "1",
            "REARRANGE_SPACES": "true",
        ])
        expect(enabled?.rearrangeSpaces == true,
               "true config enables native rearranging")

        let missing = OverlaySnapshot(environment: [
            "REVISION": "3",
            "X": "0", "Y": "0", "WIDTH": "420", "HEIGHT": "26",
            "SELECTED": "1",
        ])
        expect(missing?.rearrangeSpaces == false,
               "missing flag defaults to disabled")

        print("spaces overlay config snapshot tests passed")
    }
}
