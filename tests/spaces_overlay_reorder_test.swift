import CoreGraphics
import Foundation

@main
enum SpacesOverlayReorderTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        let frames = [
            CGRect(x: 0, y: 0, width: 50, height: 26),
            CGRect(x: 55, y: 0, width: 70, height: 26),
            CGRect(x: 130, y: 0, width: 60, height: 26),
            CGRect(x: 195, y: 0, width: 80, height: 26),
        ]

        expect(SpaceReorderModel.destinationIndex(for: -1, frames: frames, source: 2) == 1,
               "pointer before first remaining card inserts at one")
        expect(SpaceReorderModel.destinationIndex(for: 150, frames: frames, source: 2) == 2,
               "pointer between remaining cards inserts at two")
        expect(SpaceReorderModel.destinationIndex(for: 400, frames: frames, source: 2) == 4,
               "pointer after last remaining card inserts at four")
        expect(SpaceReorderModel.destinationIndex(for: 150, frames: frames, source: 0) == nil,
               "zero-based source is invalid")
        expect(SpaceReorderModel.destinationIndex(for: 150, frames: frames, source: 5) == nil,
               "source beyond the layout is invalid")
        expect(SpaceReorderModel.insertionX(for: 1, frames: frames, source: 2, spacing: 5) == 0,
               "first insertion slot starts at the content origin")
        expect(SpaceReorderModel.insertionX(for: 2, frames: frames, source: 2, spacing: 5) == 55,
               "second insertion slot accounts for the first remaining width")
        expect(SpaceReorderModel.insertionX(for: 4, frames: frames, source: 2, spacing: 5) == 200,
               "last insertion slot accounts for all remaining cards")
        expect(SpaceReorderModel.insertionX(for: 5, frames: frames, source: 2, spacing: 5) == nil,
               "insertion beyond the remaining card count is invalid")

        print("spaces overlay reorder tests passed")
    }
}
