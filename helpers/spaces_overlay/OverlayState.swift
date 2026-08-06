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
    let labels: [String]

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
        self.labels = (environment["LABELS"] ?? "")
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { Self.decodeHex(String($0)) }
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

struct ScrollModel {
    static func clampOffset(_ offset: CGFloat,
                            contentWidth: CGFloat,
                            viewportWidth: CGFloat) -> CGFloat {
        min(max(0, offset), max(0, contentWidth - viewportWidth))
    }
}
