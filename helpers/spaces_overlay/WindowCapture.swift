import AppKit
import CoreGraphics
import ScreenCaptureKit

@_silgen_name("CGWindowListCreateImage")
private func createLegacyWindowImage(_ screenBounds: CGRect,
                                     _ listOption: CGWindowListOption,
                                     _ windowID: CGWindowID,
                                     _ imageOption: CGWindowImageOption) -> CGImage?

struct WindowThumbnailData {
    let id: CGWindowID
    let image: CGImage?
    let sourceSize: CGSize
    let appName: String
    let title: String
    let ownerPID: pid_t?
}

enum WindowCapture {
    static func displayTitle(title: String, appName: String) -> String {
        let value = title.isEmpty ? (appName.isEmpty ? "Window" : appName) : title
        return String(value.prefix(48))
    }

    static func capture(ids: [CGWindowID], completion: @escaping ([WindowThumbnailData]) -> Void) {
        if #available(macOS 14.0, *) {
            captureWithScreenCaptureKit(ids: ids, completion: completion)
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                let thumbnails = records(ids: ids, captureOne: captureLegacy)
                DispatchQueue.main.async { completion(thumbnails) }
            }
        }
    }

    static func capture(ids: [CGWindowID],
                        captureOne: @escaping (CGWindowID) -> WindowThumbnailData?,
                        completion: @escaping ([WindowThumbnailData]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let thumbnails = records(ids: ids, captureOne: captureOne)
            DispatchQueue.main.async { completion(thumbnails) }
        }
    }

    static func records(ids: [CGWindowID],
                        captureOne: (CGWindowID) -> WindowThumbnailData?) -> [WindowThumbnailData] {
        ids.map { captureOne($0) ?? fallback(id: $0) }
    }

    private static func captureWithScreenCaptureKit(ids: [CGWindowID],
                                                     completion: @escaping ([WindowThumbnailData]) -> Void) {
        let windowMetadata = ids.map { metadata(for: $0) }

        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, error in
            let windowsByID = Dictionary(
                (content?.windows ?? []).map { ($0.windowID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let group = DispatchGroup()
            let lock = NSLock()
            var thumbnails = Array<WindowThumbnailData?>(repeating: nil, count: ids.count)

            for (index, id) in ids.enumerated() {
                guard let window = windowsByID[id] else {
                    thumbnails[index] = windowMetadata[index] ?? fallback(id: id)
                    continue
                }

                group.enter()
                let configuration = SCStreamConfiguration()
                configuration.width = max(1, Int(window.frame.width.rounded()))
                configuration.height = max(1, Int(window.frame.height.rounded()))
                configuration.showsCursor = false
                configuration.capturesAudio = false

                let filter = SCContentFilter(desktopIndependentWindow: window)
                SCScreenshotManager.captureImage(contentFilter: filter,
                                                  configuration: configuration) { image, error in
                    let base = windowMetadata[index] ?? self.fallback(id: id)
                    let thumbnail = WindowThumbnailData(
                        id: base.id,
                        image: image,
                        sourceSize: image.map { CGSize(width: $0.width, height: $0.height) }
                            ?? base.sourceSize,
                        appName: base.appName,
                        title: base.title,
                        ownerPID: base.ownerPID
                    )
                    lock.lock()
                    thumbnails[index] = thumbnail
                    lock.unlock()
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                completion(thumbnails.enumerated().map { index, thumbnail in
                    thumbnail ?? windowMetadata[index] ?? fallback(id: ids[index])
                })
            }
        }
    }

    private static func fallback(id: CGWindowID) -> WindowThumbnailData {
        WindowThumbnailData(id: id,
                            image: nil,
                            sourceSize: .zero,
                            appName: "",
                            title: "Window",
                            ownerPID: nil)
    }

    private static func metadata(for id: CGWindowID) -> WindowThumbnailData? {
        guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id)
            as? [[String: Any]])?.first else { return nil }

        let appName = info[kCGWindowOwnerName as String] as? String ?? ""
        let rawTitle = info[kCGWindowName as String] as? String ?? ""
        let title = displayTitle(title: rawTitle, appName: appName)
        let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)
            .map { pid_t($0.int32Value) }

        var bounds = CGRect.zero
        if let dictionary = info[kCGWindowBounds as String] as? NSDictionary {
            CGRectMakeWithDictionaryRepresentation(dictionary, &bounds)
        }

        return WindowThumbnailData(id: id,
                                   image: nil,
                                   sourceSize: bounds.size,
                                   appName: appName,
                                   title: title,
                                   ownerPID: ownerPID)
    }

    private static func captureLegacy(id: CGWindowID) -> WindowThumbnailData? {
        guard let base = metadata(for: id) else { return nil }
        let image = createLegacyWindowImage(
            .null,
            .optionIncludingWindow,
            id,
            [.boundsIgnoreFraming, .bestResolution]
        )
        return WindowThumbnailData(id: base.id,
                                   image: image,
                                   sourceSize: image.map {
                                       CGSize(width: $0.width, height: $0.height)
                                   } ?? base.sourceSize,
                                   appName: base.appName,
                                   title: base.title,
                                   ownerPID: base.ownerPID)
    }
}
