import AppKit

final class SpacesView: NSView {
    private struct ItemLayout {
        let space: Int
        let frame: CGRect
        let number: String
        let label: String
    }

    private let numberFont = NSFont(name: "SF Mono", size: 14)
        ?? NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    private let iconFont = NSFont(name: "sketchybar-app-font", size: 16)
        ?? NSFont.systemFont(ofSize: 16)
    private let white = NSColor(calibratedRed: 0xe2 / 255, green: 0xe2 / 255, blue: 0xe3 / 255, alpha: 1)
    private let red = NSColor(calibratedRed: 0xfc / 255, green: 0x5d / 255, blue: 0x7c / 255, alpha: 1)
    private let grey = NSColor(calibratedRed: 0x7f / 255, green: 0x84 / 255, blue: 0x90 / 255, alpha: 1)
    private let black = NSColor(calibratedRed: 0x18 / 255, green: 0x18 / 255, blue: 0x19 / 255, alpha: 1)
    private let background = NSColor(calibratedRed: 0x36 / 255, green: 0x39 / 255, blue: 0x44 / 255, alpha: 1)
    private let inactiveBorder = NSColor(calibratedRed: 0x2c / 255, green: 0x2e / 255, blue: 0x34 / 255, alpha: 1)

    private var snapshot: OverlaySnapshot?
    private var offset: CGFloat = 0
    private var contentWidth: CGFloat = 0

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func apply(_ snapshot: OverlaySnapshot) {
        let previousSelection = self.snapshot?.selected
        self.snapshot = snapshot
        let layouts = itemLayouts()
        contentWidth = layouts.last?.frame.maxX ?? 0
        offset = ScrollModel.clampOffset(offset,
                                         contentWidth: contentWidth,
                                         viewportWidth: bounds.width)

        if previousSelection != snapshot.selected,
           let selected = layouts.first(where: { $0.space == snapshot.selected }) {
            if selected.frame.minX < offset {
                offset = selected.frame.minX
            } else if selected.frame.maxX > offset + bounds.width {
                offset = selected.frame.maxX - bounds.width
            }
            offset = ScrollModel.clampOffset(offset,
                                             contentWidth: contentWidth,
                                             viewportWidth: bounds.width)
        }
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let layouts = itemLayouts()
        contentWidth = layouts.last?.frame.maxX ?? 0
        offset = ScrollModel.clampOffset(offset,
                                         contentWidth: contentWidth,
                                         viewportWidth: newSize.width)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let snapshot else { return }

        NSGraphicsContext.current?.saveGraphicsState()
        bounds.clip()

        for item in itemLayouts() {
            let frame = item.frame.offsetBy(dx: -offset, dy: 0)
            if frame.maxX < dirtyRect.minX || frame.minX > dirtyRect.maxX { continue }

            let selected = item.space == snapshot.selected
            let outer = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
            (selected ? grey : inactiveBorder).setStroke()
            outer.lineWidth = 1
            outer.stroke()

            let inner = frame.insetBy(dx: 1, dy: 1)
            let innerPath = NSBezierPath(roundedRect: inner, xRadius: 5, yRadius: 5)
            background.setFill()
            innerPath.fill()
            (selected ? black : inactiveBorder).setStroke()
            innerPath.lineWidth = 1
            innerPath.stroke()

            let numberAttributes: [NSAttributedString.Key: Any] = [
                .font: numberFont,
                .foregroundColor: selected ? red : white,
            ]
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: iconFont,
                .foregroundColor: selected ? white : grey,
            ]

            let numberSize = item.number.size(withAttributes: numberAttributes)
            let numberPoint = CGPoint(x: frame.minX + 14,
                                      y: frame.midY - numberSize.height / 2 + 1)
            item.number.draw(at: numberPoint, withAttributes: numberAttributes)

            if !item.label.isEmpty {
                let labelSize = item.label.size(withAttributes: labelAttributes)
                let labelPoint = CGPoint(x: numberPoint.x + numberSize.width + 8,
                                         y: frame.midY - labelSize.height / 2)
                item.label.draw(at: labelPoint, withAttributes: labelAttributes)
            }
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    override func scrollWheel(with event: NSEvent) {
        var delta = event.scrollingDeltaX
        if abs(delta) < 0.001 {
            delta = event.scrollingDeltaY
        }
        guard abs(delta) >= 0.001 else { return }

        offset = ScrollModel.clampOffset(offset - delta,
                                         contentWidth: contentWidth,
                                         viewportWidth: bounds.width)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let space = space(at: convert(event.locationInWindow, from: nil)) else { return }
        runYabai(["-m", "space", "--focus", String(space)])
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let space = space(at: convert(event.locationInWindow, from: nil)) else { return }
        runYabai(["-m", "space", "--destroy", String(space)])
    }

    private func space(at point: CGPoint) -> Int? {
        let contentPoint = CGPoint(x: point.x + offset, y: point.y)
        return itemLayouts().first(where: { $0.frame.contains(contentPoint) })?.space
    }

    private func itemLayouts() -> [ItemLayout] {
        guard let snapshot else { return [] }
        var x: CGFloat = 0

        return snapshot.labels.enumerated().map { index, label in
            let number = String(index + 1)
            let numberWidth = number.size(withAttributes: [.font: numberFont]).width
            let labelWidth = label.size(withAttributes: [.font: iconFont]).width
            let width = max(50, 14 + numberWidth + (label.isEmpty ? 20 : 8 + labelWidth + 20))
            let frame = CGRect(x: x, y: max(0, (bounds.height - 26) / 2), width: width, height: 26)
            x += width + 5
            return ItemLayout(space: index + 1, frame: frame, number: number, label: label)
        }
    }

    private func runYabai(_ arguments: [String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["yabai"] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }
}
