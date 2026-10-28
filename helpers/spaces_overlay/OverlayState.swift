import Foundation
import CoreGraphics

struct MachEnvironment {
    static func parse(_ data: Data) -> [String: String] {
        var fields: [String] = []
        var start = data.startIndex

        while start < data.endIndex {
            guard let terminator = data[start...].firstIndex(of: 0) else { break }
            let field = String(decoding: data[start..<terminator], as: UTF8.self)
            if field.isEmpty { break }
            fields.append(field)
            start = data.index(after: terminator)
        }

        var environment: [String: String] = [:]
        var index = 0
        while index + 1 < fields.count {
            environment[fields[index]] = fields[index + 1]
            index += 2
        }
        return environment
    }
}

struct OverlayDisplayGroup {
    let displayIndex: Int
    let frame: CGRect
    let selected: Int
    let spaces: [Int]
    let apps: [[String]]
    let windowIDs: [[CGWindowID]]
    let foregroundWindowIDs: [CGWindowID?]

    func position(of space: Int) -> Int? {
        spaces.firstIndex(of: space)
    }
}

struct OverlaySnapshot {
    let revision: UInt64
    let visible: Bool
    let rearrangeSpaces: Bool
    let displays: [OverlayDisplayGroup]

    var frame: CGRect { displays.first?.frame ?? .zero }
    var selected: Int { displays.first?.selected ?? 0 }
    var apps: [[String]] { displays.first?.apps ?? [] }
    var windowIDs: [[CGWindowID]] { displays.first?.windowIDs ?? [] }
    var foregroundWindowIDs: [CGWindowID?] { displays.first?.foregroundWindowIDs ?? [] }

    func group(forDisplay displayIndex: Int) -> OverlayDisplayGroup? {
        displays.first(where: { $0.displayIndex == displayIndex })
    }

    init?(environment: [String: String]) {
        guard
            let revisionText = environment["REVISION"],
            let revision = UInt64(revisionText)
        else {
            return nil
        }

        self.revision = revision
        self.visible = environment["VISIBLE"] != "false"
        self.rearrangeSpaces = environment["REARRANGE_SPACES"] == "true"

        if let encodedDisplays = environment["DISPLAYS"],
           !encodedDisplays.isEmpty,
           let parsedDisplays = Self.parseDisplays(encodedDisplays),
           !parsedDisplays.isEmpty {
            self.displays = parsedDisplays
        } else if let legacyDisplay = Self.parseLegacy(environment) {
            self.displays = [legacyDisplay]
        } else {
            return nil
        }
    }

    static func parseLegacy(_ environment: [String: String]) -> OverlayDisplayGroup? {
        guard
            let xText = environment["X"], let x = Double(xText),
            let yText = environment["Y"], let y = Double(yText),
            let widthText = environment["WIDTH"], let width = Double(widthText),
            let heightText = environment["HEIGHT"], let height = Double(heightText),
            let selectedText = environment["SELECTED"], let selected = Int(selectedText),
            width > 0,
            height > 0
        else {
            return nil
        }

        let apps = parseLabels(environment["LABELS"] ?? "")
        let spaces = apps.indices.map { $0 + 1 }
        return OverlayDisplayGroup(
            displayIndex: 0,
            frame: CGRect(x: x, y: y, width: width, height: height),
            selected: selected,
            spaces: spaces,
            apps: apps,
            windowIDs: parseWindowIDs(environment["WINDOW_IDS"], spaceCount: apps.count),
            foregroundWindowIDs: parseForegroundWindowIDs(
                environment["FOREGROUND_IDS"],
                spaceCount: apps.count
            )
        )
    }

    static func parseDisplays(_ encoded: String) -> [OverlayDisplayGroup]? {
        var groups: [OverlayDisplayGroup] = []
        for groupText in encoded.split(separator: ";", omittingEmptySubsequences: false) {
            let fields = groupText.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count == 10,
                  let displayIndex = Int(fields[0]),
                  let x = Double(fields[1]),
                  let y = Double(fields[2]),
                  let width = Double(fields[3]),
                  let height = Double(fields[4]),
                  let selected = Int(fields[5]),
                  width > 0,
                  height > 0
            else {
                return nil
            }

            var spaces: [Int] = []
            for spaceText in fields[6].split(separator: ",", omittingEmptySubsequences: false) {
                if spaceText.isEmpty { continue }
                guard let space = Int(spaceText) else { return nil }
                spaces.append(space)
            }

            let apps = parseLabels(String(fields[7]))
            guard apps.count == spaces.count else { return nil }
            let windowIDs = parseWindowIDs(String(fields[8]), spaceCount: spaces.count)
            let foregroundWindowIDs = parseForegroundWindowIDs(
                String(fields[9]),
                spaceCount: spaces.count
            )

            groups.append(OverlayDisplayGroup(
                displayIndex: displayIndex,
                frame: CGRect(x: x, y: y, width: width, height: height),
                selected: selected,
                spaces: spaces,
                apps: apps,
                windowIDs: windowIDs,
                foregroundWindowIDs: foregroundWindowIDs
            ))
        }
        return groups
    }

    static func parseLabels(_ encoded: String) -> [[String]] {
        if encoded.isEmpty { return [] }
        let separator: Character = "\u{1F}"
        return encoded
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { encodedSpace in
                Self.decodeHex(String(encodedSpace))
                    .split(separator: separator, omittingEmptySubsequences: true)
                    .map(String.init)
            }
    }

    static func parseForegroundWindowIDs(_ encodedForegroundIDs: String?,
                                         spaceCount: Int) -> [CGWindowID?] {
        let count = max(0, spaceCount)
        var foregroundIDs = Array<CGWindowID?>(repeating: nil, count: count)
        guard let encodedForegroundIDs else { return foregroundIDs }

        let groups = encodedForegroundIDs
            .split(separator: ",", omittingEmptySubsequences: false)
        for index in 0..<min(groups.count, count) {
            guard let id = CGWindowID(groups[index]), id > 0 else { continue }
            foregroundIDs[index] = id
        }
        return foregroundIDs
    }

    static func parseWindowIDs(_ encodedWindowIDs: String?,
                               spaceCount: Int) -> [[CGWindowID]] {
        let groupCount = max(0, spaceCount)
        guard let encodedWindowIDs else {
            return Array(repeating: [], count: groupCount)
        }
        var groups = encodedWindowIDs
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { group in
                group
                    .split(separator: ":", omittingEmptySubsequences: false)
                    .compactMap { CGWindowID($0) }
                    .filter { $0 > 0 }
            }
        if groups.count > groupCount {
            groups.removeLast(groups.count - groupCount)
        }
        groups += Array(repeating: [], count: groupCount - groups.count)
        return groups
    }

    private static func decodeHex(_ text: String) -> String {
        guard text.count.isMultiple(of: 2) else { return "" }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.count / 2)
        var index = text.startIndex

        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return "" }
            bytes.append(byte)
            index = next
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

struct SpaceLayoutModel {
    static let cardHeight: CGFloat = 26
    static let horizontalPadding: CGFloat = 2
    static let minimumCardWidth: CGFloat = 50
    static let cardCornerRadius: CGFloat = 6
    static let cardInnerCornerRadius: CGFloat = 5
    static let cardStrokeWidth: CGFloat = 1
    static let leadingPadding: CGFloat = 14
    static let numberToIconsSpacing: CGFloat = 8
    static let iconSize: CGFloat = 16
    static let iconSpacing: CGFloat = 4
    static let trailingPadding: CGFloat = 20

    static func cardWidth(numberWidth: CGFloat, appCount: Int) -> CGFloat {
        let count = max(0, appCount)
        let contentWidth: CGFloat
        if count == 0 {
            contentWidth = trailingPadding
        } else {
            contentWidth = numberToIconsSpacing
                + CGFloat(count) * iconSize
                + CGFloat(count - 1) * iconSpacing
                + trailingPadding
        }
        return max(minimumCardWidth, leadingPadding + numberWidth + contentWidth)
    }
}

struct ScrollModel {
    static let fitTolerance: CGFloat = 3

    static func clampOffset(_ offset: CGFloat,
                            contentWidth: CGFloat,
                            viewportWidth: CGFloat) -> CGFloat {
        let overflow = contentWidth - viewportWidth
        if overflow <= fitTolerance { return 0 }
        return min(max(0, offset), overflow)
    }
}

struct SpaceReorderModel {
    static func destinationIndex(for pointerX: CGFloat,
                                 frames: [CGRect],
                                 source: Int) -> Int? {
        guard source >= 1, source <= frames.count else { return nil }

        var destination = 1
        for (index, frame) in frames.enumerated() where index + 1 != source {
            if pointerX < frame.midX { return destination }
            destination += 1
        }
        return destination
    }

    static func insertionX(for destination: Int,
                           frames: [CGRect],
                           source: Int,
                           spacing: CGFloat) -> CGFloat? {
        guard source >= 1, source <= frames.count else { return nil }

        let remaining = frames.enumerated()
            .filter { $0.offset + 1 != source }
            .map(\.element)
        guard destination >= 1, destination <= remaining.count + 1 else { return nil }

        var x: CGFloat = frames.first?.minX ?? 0
        for index in 0..<(destination - 1) {
            x += remaining[index].width
            if index < remaining.count - 1 { x += spacing }
        }
        return x
    }
}
