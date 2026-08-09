import AppKit
import CoreGraphics

final class WindowCarouselView: NSView {
    var onSelect: ((CGWindowID) -> Void)?
    var onRegionChanged: ((Bool) -> Void)?

    private let shellColor = NSColor(calibratedRed: 0x18 / 255,
                                     green: 0x18 / 255,
                                     blue: 0x19 / 255,
                                     alpha: 0.96)
    private let cardColor = NSColor(calibratedRed: 0x36 / 255,
                                    green: 0x39 / 255,
                                    blue: 0x44 / 255,
                                    alpha: 0.96)
    private let cardBorderColor = NSColor(calibratedRed: 0x2c / 255,
                                          green: 0x2e / 255,
                                          blue: 0x34 / 255,
                                          alpha: 1)
    private let selectedBorderColor = NSColor(calibratedRed: 0xfc / 255,
                                               green: 0x5d / 255,
                                               blue: 0x7c / 255,
                                               alpha: 1)
    private let foregroundBorderColor = NSColor(calibratedRed: 0x7f / 255,
                                                 green: 0x84 / 255,
                                                 blue: 0x90 / 255,
                                                 alpha: 1)
    private let hoveredBorderColor = NSColor(calibratedWhite: 0.85, alpha: 1)
    private let titleFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    private var thumbnails: [WindowThumbnailData] = []
    private var offset: CGFloat = 0
    private var hoveredID: CGWindowID?
    private var selectedID: CGWindowID?
    private(set) var foregroundID: CGWindowID?
    private var pointerTrackingArea: NSTrackingArea?

    private lazy var genericApplicationIcon: NSImage = {
        NSWorkspace.shared.icon(
            forFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"
        )
    }()

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func apply(_ thumbnails: [WindowThumbnailData],
               foregroundID: CGWindowID? = nil) {
        self.thumbnails = thumbnails
        self.foregroundID = foregroundID
        if let selectedID, !thumbnails.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
        hoveredID = nil
        offset = clampedOffset(0)
        needsDisplay = true
    }

    func setForegroundID(_ foregroundID: CGWindowID?) {
        self.foregroundID = foregroundID
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        offset = WindowCarouselModel.clampOffset(
            offset,
            contentWidth: contentWidth,
            viewportWidth: newSize.width
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSGraphicsContext.current?.saveGraphicsState()
        let shellFrame = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shell = NSBezierPath(roundedRect: shellFrame, xRadius: 8, yRadius: 8)
        shell.addClip()
        shellColor.setFill()
        shell.fill()

        for (thumbnail, contentFrame) in zip(thumbnails, cardFrames()) {
            let frame = contentFrame.offsetBy(dx: -offset, dy: 0)
            guard frame.maxX >= dirtyRect.minX, frame.minX <= dirtyRect.maxX else { continue }
            draw(thumbnail, in: frame)
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    override func mouseEntered(with event: NSEvent) {
        onRegionChanged?(true)
        updateHover(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredID = nil
        needsDisplay = true
        onRegionChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        select(at: point)
    }

    @discardableResult
    func select(at point: CGPoint) -> CGWindowID? {
        guard let id = id(at: point) else { return nil }
        return select(id: id)
    }

    @discardableResult
    func select(id: CGWindowID) -> CGWindowID? {
        guard thumbnails.contains(where: { $0.id == id }) else { return nil }
        selectedID = id
        needsDisplay = true
        onSelect?(id)
        return id
    }

    override func scrollWheel(with event: NSEvent) {
        var delta = event.scrollingDeltaX
        if abs(delta) < 0.001 {
            delta = event.scrollingDeltaY
        }
        scroll(by: delta)
    }

    func scroll(by delta: CGFloat) {
        guard abs(delta) >= 0.001 else { return }
        offset = clampedOffset(offset - delta)
        needsDisplay = true
    }

    func cardFrames() -> [CGRect] {
        var x = WindowCarouselModel.horizontalPadding
        let y = max(0, (bounds.height - WindowCarouselModel.cardHeight) / 2)

        return thumbnails.map { _ in
            defer { x += WindowCarouselModel.cardWidth + WindowCarouselModel.cardSpacing }
            return CGRect(x: x,
                          y: y,
                          width: WindowCarouselModel.cardWidth,
                          height: WindowCarouselModel.cardHeight)
        }
    }

    func clampedOffset(_ proposedOffset: CGFloat) -> CGFloat {
        WindowCarouselModel.clampOffset(
            proposedOffset,
            contentWidth: contentWidth,
            viewportWidth: bounds.width
        )
    }

    func id(at point: CGPoint) -> CGWindowID? {
        let contentPoint = CGPoint(x: point.x + offset, y: point.y)
        return zip(thumbnails, cardFrames())
            .first(where: { $0.1.contains(contentPoint) })?
            .0.id
    }

    private var contentWidth: CGFloat {
        cardFrames().last.map { $0.maxX + WindowCarouselModel.horizontalPadding } ?? 0
    }

    private func updateHover(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let newHoveredID = id(at: point)
        guard newHoveredID != hoveredID else { return }
        hoveredID = newHoveredID
        needsDisplay = true
    }

    private func draw(_ thumbnail: WindowThumbnailData, in frame: CGRect) {
        let card = NSBezierPath(roundedRect: frame, xRadius: 7, yRadius: 7)
        cardColor.setFill()
        card.fill()

        if thumbnail.id == hoveredID {
            hoveredBorderColor.setStroke()
            card.lineWidth = 2
        } else if thumbnail.id == selectedID {
            selectedBorderColor.setStroke()
            card.lineWidth = 2
        } else if thumbnail.id == foregroundID {
            foregroundBorderColor.setStroke()
            card.lineWidth = 1
        } else {
            cardBorderColor.setStroke()
            card.lineWidth = 1
        }
        card.stroke()

        let localImageRect = WindowCarouselModel.imageRect
        let imageRect = localImageRect.offsetBy(dx: frame.minX, dy: frame.minY)
        if let image = thumbnail.image {
            let fitted = WindowCarouselModel.aspectFit(source: thumbnail.sourceSize,
                                                        in: imageRect)
            let imageSize = thumbnail.sourceSize.width > 0 && thumbnail.sourceSize.height > 0
                ? thumbnail.sourceSize
                : CGSize(width: image.width, height: image.height)
            NSGraphicsContext.current?.imageInterpolation = .high
            NSImage(cgImage: image, size: imageSize)
                .draw(in: fitted,
                      from: .zero,
                      operation: .sourceOver,
                      fraction: 1,
                      respectFlipped: true,
                      hints: nil)
        } else {
            drawFallback(for: thumbnail, in: imageRect)
        }

        let titleRow = WindowCarouselModel.titleRowLayout(
            in: CGRect(x: frame.minX + 10,
                       y: frame.minY + 8,
                       width: frame.width - 20,
                       height: 16)
        )
        let icon = applicationIcon(for: thumbnail)
        icon.draw(in: titleRow.icon,
                  from: NSRect(origin: .zero, size: icon.size),
                  operation: .sourceOver,
                  fraction: 1,
                  respectFlipped: true,
                  hints: nil)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        (thumbnail.title as NSString).draw(in: titleRow.title, withAttributes: attributes)
    }

    private func drawFallback(for thumbnail: WindowThumbnailData, in imageRect: CGRect) {
        let icon = applicationIcon(for: thumbnail)
        let iconSide = min(56, imageRect.height * 0.5)
        let iconRect = CGRect(x: imageRect.midX - iconSide / 2,
                              y: imageRect.midY - iconSide / 2 + 8,
                              width: iconSide,
                              height: iconSide)
        icon.draw(in: iconRect,
                  from: NSRect(origin: .zero, size: icon.size),
                  operation: .sourceOver,
                  fraction: 1,
                  respectFlipped: true,
                  hints: nil)

        let fallback = thumbnail.appName.isEmpty ? "Application" : thumbnail.appName
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1),
            .paragraphStyle: centeredTruncatingParagraph(),
        ]
        let textRect = CGRect(x: imageRect.minX,
                              y: max(imageRect.minY, iconRect.minY - 24),
                              width: imageRect.width,
                              height: 16)
        (fallback as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func applicationIcon(for thumbnail: WindowThumbnailData) -> NSImage {
        if let ownerPID = thumbnail.ownerPID,
           let icon = NSRunningApplication(processIdentifier: ownerPID)?.icon {
            return icon
        }
        if !thumbnail.appName.isEmpty,
           let icon = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == thumbnail.appName })?.icon {
            return icon
        }
        return genericApplicationIcon
    }

    private func centeredTruncatingParagraph() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }
}
