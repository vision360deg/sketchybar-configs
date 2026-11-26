import Foundation

@main
enum WindowCaptureTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        expect(WindowCapture.displayTitle(title: "", appName: "Safari") == "Safari",
               "falls back to the app name")
        expect(WindowCapture.displayTitle(title: "", appName: "") == "Window",
               "falls back to a generic title")
        expect(WindowCapture.displayTitle(title: "A very long title", appName: "Safari").count <= 48,
               "bounds title length")

        let records = WindowCapture.records(ids: [101, 202, 303]) { id in
            guard id == 202 else { return nil }
            return WindowThumbnailData(id: id,
                                       image: nil,
                                       sourceSize: CGSize(width: 640, height: 480),
                                       appName: "Safari",
                                       title: "Browser",
                                       ownerPID: 42)
        }
        expect(records.map(\.id) == [101, 202, 303],
               "retains every requested ID in input order")
        expect(records[0].image == nil && records[0].sourceSize == .zero
                   && records[0].appName.isEmpty && records[0].title == "Window"
                   && records[0].ownerPID == nil,
               "uses selectable generic metadata for a disappeared window")
        expect(records[1].image == nil && records[1].sourceSize == CGSize(width: 640, height: 480)
                   && records[1].appName == "Safari" && records[1].title == "Browser"
                   && records[1].ownerPID == 42,
               "retains nil-image metadata from a captured window")

        var completionRecords: [WindowThumbnailData]?
        var completionIsOnMainQueue: Bool?
        WindowCapture.capture(ids: [404], captureOne: { _ in nil }) { records in
            completionRecords = records
            completionIsOnMainQueue = Thread.isMainThread
            CFRunLoopStop(CFRunLoopGetMain())
        }
        CFRunLoopRun()
        expect(completionRecords?.map(\.id) == [404],
               "async capture retains fallback records")
        expect(completionIsOnMainQueue == true,
               "async capture delivers completion on the main queue")

        print("window capture tests passed")
    }
}
