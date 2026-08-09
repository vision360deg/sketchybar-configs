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

struct OverlaySnapshot {
    let revision: UInt64
    let visible: Bool
    let frame: CGRect
    let selected: Int
    let apps: [[String]]
    let rearrangeSpaces: Bool

    init?(environment: [String: String]) {
        guard
            let revisionText = environment["REVISION"],
            let revision = UInt64(revisionText),
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

        self.revision = revision
        self.visible = environment["VISIBLE"] != "false"
        self.frame = CGRect(x: x, y: y, width: width, height: height)
        self.selected = selected
        self.rearrangeSpaces = environment["REARRANGE_SPACES"] == "true"

        let encodedSpaces = environment["LABELS"] ?? ""
        if encodedSpaces.isEmpty {
            self.apps = []
        } else {
            let separator: Character = "\u{1F}"
            self.apps = encodedSpaces
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { encoded in
                    Self.decodeHex(String(encoded))
                        .split(separator: separator, omittingEmptySubsequences: true)
                        .map(String.init)
                }
        }
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
